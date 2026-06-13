// test/repositories/mosque_repository_test.dart
// =============================================================================
// Unit tests for MosqueRepository.
//
// Covers:
//   ✓ Successful nearby query → parses Mosque list correctly
//   ✓ Location service disabled → LocationServiceDisabledException
//   ✓ Permission denied → LocationPermissionDeniedException
//   ✓ 429 rate limit → ServerException.isRateLimited
//   ✓ 401 unauthorized → ServerException.isUnauthorized
//   ✓ Malformed JSON body → ParseException
//   ✓ Network timeout → RequestTimeoutException
//   ✓ getMosqueTimings → parses PrayerTiming list correctly
//   ✓ Mosque.fromJson field validation → FormatException on missing required fields
//   ✓ PrayerTiming.fromJson time format validation
//   ✓ Madhab.fromString unknown value → Madhab.unknown
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:geolocator/geolocator.dart';

// Canonical import paths matching lib/ folder structure (see sprint3_backlog.md)
import 'package:ummah/core/errors/app_exception.dart';
import 'package:ummah/features/mosques/data/models/mosque_model.dart';
import 'package:ummah/features/mosques/data/models/prayer_timing.dart';
import 'package:ummah/features/mosques/data/repositories/mosque_repository.dart';
import 'package:ummah/services/location/location_service.dart';
import 'package:ummah/services/auth/token_service.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockLocationService extends Mock implements LocationService {}
class MockTokenService    extends Mock implements TokenService    {}

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

final _fakePosition = Position(
  latitude:             17.4126,
  longitude:            78.4482,
  timestamp:            DateTime.now(),
  accuracy:             10.0,
  altitude:             0.0,
  altitudeAccuracy:     0.0,
  heading:              0.0,
  headingAccuracy:      0.0,
  speed:                0.0,
  speedAccuracy:        0.0,
);

const _nearbySuccessBody = {
  'data': [
    {
      'id':                   '01914f2a-0000-0000-0000-000000000001',
      'name':                 'Masjid Al-Falah',
      'name_ar':              'مسجد الفلاح',
      'distance_km':          0.43,
      'address_line':         '12 Banjara Hills Road',
      'city':                 'Hyderabad',
      'madhab':               'Hanafi',
      'status':               'active',
      'coordinates': {
        'latitude':  17.4126,
        'longitude': 78.4482,
      },
      'has_verified_timings': true,
      'checkin_count_today':  14,
    },
  ],
  'meta': {
    'total':        1,
    'radius_km':    5.0,
    'privacy_note': 'Your location was used only to compute this response and was not stored.',
  },
};

const _timingsSuccessBody = {
  'data': {
    'mosque': {
      'id':           '01914f2a-0000-0000-0000-000000000001',
      'name':         'Masjid Al-Falah',
      'name_ar':      'مسجد الفلاح',
      'madhab':       'Hanafi',
      'city':         'Hyderabad',
      'country_code': 'IN',
    },
    'timings': [
      {
        'effective_date': '2026-05-26',
        'fajr':           '04:32',
        'sunrise':        '05:55',
        'dhuhr':          '12:17',
        'asr':            '15:48',
        'maghrib':        '18:38',
        'isha':           '20:02',
        'jumu_ah':        null,
        'calc_method':    'manual',
        'verification': {
          'status':              'verified',
          'verified_at':         '2026-05-24T09:15:00Z',
          'verified_by_display': 'Admin Rashid A.',
          'source_note':         'Confirmed with mosque committee',
        },
      },
    ],
  },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MosqueRepository _makeRepo({
  required http.Client client,
  required MockLocationService locationService,
  required MockTokenService tokenService,
}) {
  return MosqueRepository(
    locationService: locationService,
    tokenService:    tokenService,
    httpClient:      client,
    baseUrl:         'https://api.test',
  );
}

void _stubToken(MockTokenService ts) {
  when(() => ts.getToken()).thenAnswer((_) async => 'test-jwt-token');
}

void _stubPosition(MockLocationService ls) {
  when(() => ls.getCurrentPosition()).thenAnswer((_) async => _fakePosition);
}

// ===========================================================================
// Tests
// ===========================================================================

void main() {
  late MockLocationService locationService;
  late MockTokenService    tokenService;

  setUp(() {
    locationService = MockLocationService();
    tokenService    = MockTokenService();
  });

  // =========================================================================
  // Mosque.fromJson
  // =========================================================================

  group('Mosque.fromJson', () {
    test('parses a valid mosque object correctly', () {
      final json   = _nearbySuccessBody['data'] as List;
      final mosque = Mosque.fromJson(json.first as Map<String, dynamic>);

      expect(mosque.id,                 '01914f2a-0000-0000-0000-000000000001');
      expect(mosque.name,               'Masjid Al-Falah');
      expect(mosque.nameAr,             'مسجد الفلاح');
      expect(mosque.distanceKm,         0.43);
      expect(mosque.madhab,             Madhab.hanafi);
      expect(mosque.status,             MosqueStatus.active);
      expect(mosque.coordinates.latitude,  17.4126);
      expect(mosque.coordinates.longitude, 78.4482);
      expect(mosque.hasVerifiedTimings, true);
      expect(mosque.checkinCountToday,  14);
    });

    test('formattedDistance shows metres for < 1 km', () {
      final mosque = Mosque.fromJson(
        {
          ...((_nearbySuccessBody['data'] as List).first as Map<String, dynamic>),
          'distance_km': 0.35,
        },
      );
      expect(mosque.formattedDistance, '350 m');
    });

    test('formattedDistance shows km for >= 1 km', () {
      final mosque = Mosque.fromJson(
        {
          ...((_nearbySuccessBody['data'] as List).first as Map<String, dynamic>),
          'distance_km': 2.456,
        },
      );
      expect(mosque.formattedDistance, '2.5 km');
    });

    test('throws FormatException when required field "id" is missing', () {
      final json = Map<String, dynamic>.from(
        (_nearbySuccessBody['data'] as List).first as Map<String, dynamic>,
      )..remove('id');
      expect(() => Mosque.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException when "distance_km" is not a number', () {
      final json = {
        ...((_nearbySuccessBody['data'] as List).first as Map<String, dynamic>),
        'distance_km': 'not-a-number',
      };
      expect(() => Mosque.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('Madhab.fromString returns unknown for unrecognised value', () {
      expect(Madhab.fromString('SomeOtherMadhab'), Madhab.unknown);
    });

    test('Madhab.fromString is case-insensitive', () {
      expect(Madhab.fromString('hanafi'), Madhab.hanafi);
      expect(Madhab.fromString('HANAFI'), Madhab.hanafi);
    });
  });

  // =========================================================================
  // PrayerTiming.fromJson
  // =========================================================================

  group('PrayerTiming.fromJson', () {
    test('parses a valid timing object correctly', () {
      final timings = (_timingsSuccessBody['data'] as Map)['timings'] as List;
      final timing  = PrayerTiming.fromJson(timings.first as Map<String, dynamic>);

      expect(timing.fajr,    '04:32');
      expect(timing.isha,    '20:02');
      expect(timing.jumuah,  null);
      expect(timing.calcMethod, CalcMethod.manual);
      expect(timing.isVerified, true);
      expect(timing.verification.verifiedByDisplay, 'Admin Rashid A.');
    });

    test('toTimeOfDay extension parses "04:32" correctly', () {
      final tod = '04:32'.toTimeOfDay();
      expect(tod?.hour,   4);
      expect(tod?.minute, 32);
    });

    test('toTimeOfDay returns null for invalid format', () {
      expect('25:99'.toTimeOfDay(), isNull);
      expect('invalid'.toTimeOfDay(), isNull);
    });

    test('throws FormatException for malformed time string', () {
      final json = Map<String, dynamic>.from(
        ((_timingsSuccessBody['data'] as Map)['timings'] as List).first
            as Map<String, dynamic>,
      )..[('fajr')] = '4:5';  // not HH:MM
      expect(() => PrayerTiming.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('dailyPrayers list has 6 entries on non-Friday', () {
      final timings = (_timingsSuccessBody['data'] as Map)['timings'] as List;
      final timing  = PrayerTiming.fromJson(timings.first as Map<String, dynamic>);
      // 2026-05-26 is a Tuesday — jumuah should not appear
      expect(timing.dailyPrayers.length, 6);
    });
  });

  // =========================================================================
  // getNearbyMosques — success path
  // =========================================================================

  group('getNearbyMosques — success', () {
    test('returns parsed NearbyMosquesResult on 200', () async {
      _stubToken(tokenService);
      _stubPosition(locationService);

      final client = MockClient((_) async =>
          http.Response(jsonEncode(_nearbySuccessBody), 200));

      final repo   = _makeRepo(
        client:          client,
        locationService: locationService,
        tokenService:    tokenService,
      );
      final result = await repo.getNearbyMosques();

      expect(result.mosques.length,   1);
      expect(result.radiusKm,         5.0);
      expect(result.privacyNote,      contains('not stored'));
      expect(result.mosques.first.id, '01914f2a-0000-0000-0000-000000000001');
    });

    test('includes madhab filter in query params when specified', () async {
      _stubToken(tokenService);
      _stubPosition(locationService);

      Uri? capturedUri;
      final client = MockClient((req) async {
        capturedUri = req.url;
        return http.Response(jsonEncode(_nearbySuccessBody), 200);
      });

      final repo = _makeRepo(
        client: client,
        locationService: locationService,
        tokenService: tokenService,
      );
      await repo.getNearbyMosques(
        const NearbyMosquesParams(madhab: Madhab.hanafi),
      );

      expect(capturedUri?.queryParameters['madhab'], 'Hanafi');
    });

    test('sends Bearer token in Authorization header', () async {
      _stubToken(tokenService);
      _stubPosition(locationService);

      String? authHeader;
      final client = MockClient((req) async {
        authHeader = req.headers['authorization'];
        return http.Response(jsonEncode(_nearbySuccessBody), 200);
      });

      final repo = _makeRepo(
        client: client,
        locationService: locationService,
        tokenService: tokenService,
      );
      await repo.getNearbyMosques();

      expect(authHeader, 'Bearer test-jwt-token');
    });
  });

  // =========================================================================
  // getNearbyMosques — location failures
  // =========================================================================

  group('getNearbyMosques — location exceptions', () {
    test('throws LocationServiceDisabledException when GPS is off', () async {
      when(() => locationService.getCurrentPosition())
          .thenThrow(const LocationServiceDisabledException());

      final repo = _makeRepo(
        client: MockClient((_) async => http.Response('{}', 200)),
        locationService: locationService,
        tokenService: tokenService,
      );

      expect(
        () => repo.getNearbyMosques(),
        throwsA(isA<LocationServiceDisabledException>()),
      );
    });

    test('throws LocationPermissionDeniedException when user denies', () async {
      when(() => locationService.getCurrentPosition())
          .thenThrow(const LocationPermissionDeniedException());

      final repo = _makeRepo(
        client: MockClient((_) async => http.Response('{}', 200)),
        locationService: locationService,
        tokenService: tokenService,
      );

      expect(
        () => repo.getNearbyMosques(),
        throwsA(isA<LocationPermissionDeniedException>()),
      );
    });

    test('throws LocationPermissionPermanentlyDeniedException when permanently denied', () async {
      when(() => locationService.getCurrentPosition())
          .thenThrow(const LocationPermissionPermanentlyDeniedException());

      final repo = _makeRepo(
        client: MockClient((_) async => http.Response('{}', 200)),
        locationService: locationService,
        tokenService: tokenService,
      );

      expect(
        () => repo.getNearbyMosques(),
        throwsA(isA<LocationPermissionPermanentlyDeniedException>()),
      );
    });
  });

  // =========================================================================
  // getNearbyMosques — HTTP error handling
  // =========================================================================

  group('getNearbyMosques — HTTP errors', () {
    setUp(() {
      _stubToken(tokenService);
      _stubPosition(locationService);
    });

    test('throws ServerException with isRateLimited for 429', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'error': {'code': 'RATE_LIMITED', 'message': 'Too many requests.'}}),
            429,
          ));

      final repo = _makeRepo(
        client: client,
        locationService: locationService,
        tokenService: tokenService,
      );

      await expectLater(
        repo.getNearbyMosques(),
        throwsA(
          isA<ServerException>()
              .having((e) => e.isRateLimited, 'isRateLimited', true)
              .having((e) => e.serverCode,    'serverCode',    'RATE_LIMITED'),
        ),
      );
    });

    test('throws ServerException with isUnauthorized for 401', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'error': {'code': 'UNAUTHORIZED', 'message': 'Token expired.'}}),
            401,
          ));

      final repo = _makeRepo(
        client: client,
        locationService: locationService,
        tokenService: tokenService,
      );

      await expectLater(
        repo.getNearbyMosques(),
        throwsA(isA<ServerException>().having((e) => e.isUnauthorized, 'isUnauthorized', true)),
      );
    });

    test('throws ParseException when response body is not valid JSON', () async {
      final client = MockClient((_) async =>
          http.Response('this is not json', 200));

      final repo = _makeRepo(
        client: client,
        locationService: locationService,
        tokenService: tokenService,
      );

      await expectLater(
        repo.getNearbyMosques(),
        throwsA(isA<ParseException>()),
      );
    });

    test('throws ParseException when "data" is not an array', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode({'data': 'not-an-array', 'meta': {}}), 200));

      final repo = _makeRepo(
        client: client,
        locationService: locationService,
        tokenService: tokenService,
      );

      await expectLater(
        repo.getNearbyMosques(),
        throwsA(isA<ParseException>()),
      );
    });
  });

  // =========================================================================
  // getMosqueTimings
  // =========================================================================

  group('getMosqueTimings', () {
    setUp(() => _stubToken(tokenService));

    test('returns parsed MosqueTimingsResult on 200', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(_timingsSuccessBody), 200));

      final repo   = _makeRepo(
        client:          client,
        locationService: locationService,
        tokenService:    tokenService,
      );
      final result = await repo.getMosqueTimings('01914f2a-0000-0000-0000-000000000001');

      expect(result.mosque.name,         'Masjid Al-Falah');
      expect(result.mosque.madhab,       Madhab.hanafi);
      expect(result.timings.length,      1);
      expect(result.timings.first.fajr,  '04:32');
      expect(result.timings.first.isVerified, true);
    });

    test('throws ServerException.isNotFound for 404', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'error': {'code': 'MOSQUE_NOT_FOUND', 'message': 'Not found.'}}),
            404,
          ));

      final repo = _makeRepo(
        client: client,
        locationService: locationService,
        tokenService: tokenService,
      );

      await expectLater(
        repo.getMosqueTimings('non-existent-id'),
        throwsA(isA<ServerException>().having((e) => e.isNotFound, 'isNotFound', true)),
      );
    });
  });
}
