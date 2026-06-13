// lib/features/mosques/data/repositories/mosque_repository.dart
// =============================================================================
// UMM-303: MosqueRepository — authenticated HTTP layer for mosque data.
//
// Implements two API endpoints:
//   • getNearbyMosques()   → GET /v1/mosques/nearby
//   • getMosqueTimings()   → GET /v1/mosques/:id/timings
//
// Architectural contracts:
//   1. Every public method either returns a typed value or throws an
//      [AppException] subclass. Callers NEVER catch raw Exception/Error.
//   2. Raw GPS coordinates exist only in this call stack (Step 2 below),
//      passed as HTTPS query params, then immediately dereferenced.
//   3. The JWT is read from [TokenService] — never passed as a parameter
//      from a caller, never hardcoded, never logged.
//   4. Base URL is resolved from [ApiConstants.baseUrl] (--dart-define at
//      build time) — never hardcoded inside this class.
//
// Error mapping:
//   SocketException       → NoInternetException
//   TimeoutException      → RequestTimeoutException
//   ClientException       → NoInternetException
//   null token            → ServerException(401, UNAUTHORIZED)
//   HTTP 4xx/5xx          → ServerException.fromBody()
//   Invalid JSON          → ParseException
//   Missing/wrong field   → ParseException
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../services/auth/token_service.dart';
import '../../../../services/location/location_service.dart';
import '../models/mosque_model.dart';
import '../models/prayer_timing.dart';

// ---------------------------------------------------------------------------
// Result types — named wrappers carry both data and response metadata
// ---------------------------------------------------------------------------

/// Returned by [MosqueRepository.getNearbyMosques].
class NearbyMosquesResult {
  const NearbyMosquesResult({
    required this.mosques,
    required this.radiusKm,
    required this.privacyNote,
  });

  final List<Mosque> mosques;
  final double       radiusKm;
  final String       privacyNote;
}

/// Returned by [MosqueRepository.getMosqueTimings].
class MosqueTimingsResult {
  const MosqueTimingsResult({
    required this.mosque,
    required this.timings,
  });

  final MosqueSummary      mosque;
  final List<PrayerTiming> timings;
}

/// Slim mosque summary nested inside the timings response envelope.
class MosqueSummary {
  const MosqueSummary({
    required this.id,
    required this.name,
    this.nameAr,
    required this.madhab,
    required this.city,
    required this.countryCode,
  });

  final String  id;
  final String  name;
  final String? nameAr;
  final Madhab  madhab;
  final String  city;
  final String  countryCode;

  factory MosqueSummary.fromJson(Map<String, dynamic> json) {
    return MosqueSummary(
      id:          json['id']           as String? ?? '',
      name:        json['name']         as String? ?? '',
      nameAr:      json['name_ar']      as String?,
      madhab:      Madhab.fromString(json['madhab'] as String?),
      city:        json['city']         as String? ?? '',
      countryCode: json['country_code'] as String? ?? '',
    );
  }
}

// ---------------------------------------------------------------------------
// Query parameter value objects — named params prevent arg-order bugs
// ---------------------------------------------------------------------------

class NearbyMosquesParams {
  const NearbyMosquesParams({
    this.radiusKm = ApiConstants.defaultRadiusKm,
    this.limit    = ApiConstants.defaultLimit,
    this.madhab,
  })  : assert(radiusKm > 0 && radiusKm <= ApiConstants.maxRadiusKm,
              'radiusKm must be between 0 and ${ApiConstants.maxRadiusKm}'),
        assert(limit >= 1 && limit <= ApiConstants.maxLimit,
              'limit must be between 1 and ${ApiConstants.maxLimit}');

  final double  radiusKm;
  final int     limit;
  final Madhab? madhab;
}

class MosqueTimingsParams {
  const MosqueTimingsParams({this.date, this.from, this.to})
      : assert(
          (from == null) == (to == null),
          'from and to must both be set or both be null',
        );

  final DateTime? date;
  final DateTime? from;
  final DateTime? to;
}

// ---------------------------------------------------------------------------
// MosqueRepository
// ---------------------------------------------------------------------------

class MosqueRepository {
  MosqueRepository({
    required LocationService locationService,
    required TokenService    tokenService,
    http.Client?             httpClient,
    String?                  baseUrl,
  })  : _locationService = locationService,
        _tokenService    = tokenService,
        _httpClient      = httpClient ?? http.Client(),
        // baseUrl param is only used in tests (pass 'https://api.test').
        // Production always reads from ApiConstants (--dart-define at build time).
        _baseUrl         = baseUrl ?? ApiConstants.baseUrl;

  final LocationService _locationService;
  final TokenService    _tokenService;
  final http.Client     _httpClient;
  final String          _baseUrl;

  // =========================================================================
  // GET /v1/mosques/nearby
  // =========================================================================

  /// Fetches mosques near the user's current GPS position.
  ///
  /// Step 1 — Acquire GPS fix (handles full Android/iOS permission lifecycle).
  ///           Raw [Position] exists only in this call stack.
  /// Step 2 — Build URI with coordinates as HTTPS query params.
  /// Step 3 — Attach Bearer token; dispatch GET request.
  /// Step 4 — Decode response; map errors to typed exceptions.
  /// Step 5 — Return [NearbyMosquesResult]; Position goes out of scope.
  ///
  /// Throws:
  ///   [LocationServiceDisabledException]             — GPS off
  ///   [LocationPermissionDeniedException]            — user denied
  ///   [LocationPermissionPermanentlyDeniedException] — permanently denied
  ///   [NoInternetException]                          — no network
  ///   [RequestTimeoutException]                      — 20 s timeout exceeded
  ///   [ServerException]                              — non-2xx from backend
  ///   [ParseException]                               — malformed JSON
  Future<NearbyMosquesResult> getNearbyMosques([
    NearbyMosquesParams params = const NearbyMosquesParams(),
  ]) async {
    // Step 1 — GPS (throws LocationException on failure)
    final position = await _locationService.getCurrentPosition();

    // Step 2 — Build URI (coordinates used here, then dereferenced)
    final uri = Uri.parse('$_baseUrl${ApiConstants.nearbyMosques}')
        .replace(queryParameters: <String, String>{
      'lat':       position.latitude.toString(),
      'lng':       position.longitude.toString(),
      'radius_km': params.radiusKm.toString(),
      'limit':     params.limit.toString(),
      if (params.madhab != null && params.madhab != Madhab.unknown)
        'madhab': params.madhab!.value,
    });

    // Step 3 — HTTP
    final headers  = await _buildAuthHeaders();
    final response = await _dispatchGet(uri, headers);

    // Step 4 — Validate + decode
    _assertSuccess(response);
    final body = _decodeJson(response.body);

    // Step 5 — Parse data[]
    final dataRaw = body['data'];
    if (dataRaw is! List) {
      throw ParseException(
        field:    'data',
        rawValue: dataRaw.runtimeType,
        hint:     '"data" must be an array',
      );
    }

    final List<Mosque> mosques;
    try {
      mosques = dataRaw
          .cast<Map<String, dynamic>>()
          .map(Mosque.fromJson)
          .toList(growable: false);
    } on FormatException catch (e) {
      throw ParseException(field: 'data[]', rawValue: e.message);
    }

    final meta        = body['meta'] as Map<String, dynamic>? ?? {};
    final radiusKm    = (meta['radius_km']    as num?)?.toDouble() ?? params.radiusKm;
    final privacyNote =  meta['privacy_note'] as String? ?? '';

    return NearbyMosquesResult(
      mosques:     mosques,
      radiusKm:    radiusKm,
      privacyNote: privacyNote,
    );
    // position goes out of scope here — GC reclaims on next cycle
  }

  // =========================================================================
  // GET /v1/mosques/:mosqueId/timings
  // =========================================================================

  /// Fetches prayer timings for a specific mosque.
  ///
  /// [mosqueId] — UUID of the mosque.
  /// [params]   — optional date / date-range filter.
  ///
  /// Throws [ServerException] with [ServerException.isNotFound] == true
  /// if the mosque or its timings are not found (404).
  Future<MosqueTimingsResult> getMosqueTimings(
    String mosqueId, [
    MosqueTimingsParams params = const MosqueTimingsParams(),
  ]) async {
    assert(mosqueId.isNotEmpty, 'mosqueId must not be empty');

    final queryParams = <String, String>{};
    if (params.date != null) {
      queryParams['date'] = _formatDate(params.date!);
    } else if (params.from != null && params.to != null) {
      queryParams['from'] = _formatDate(params.from!);
      queryParams['to']   = _formatDate(params.to!);
    }

    final uri = Uri.parse(
      '$_baseUrl${ApiConstants.mosqueTimings}/$mosqueId/timings',
    ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);

    final headers  = await _buildAuthHeaders();
    final response = await _dispatchGet(uri, headers);

    _assertSuccess(response);
    final body = _decodeJson(response.body);

    final dataRaw = body['data'] as Map<String, dynamic>?;
    if (dataRaw == null) {
      throw const ParseException(field: 'data', rawValue: null, hint: '"data" object missing');
    }

    final mosqueRaw = dataRaw['mosque'] as Map<String, dynamic>?;
    if (mosqueRaw == null) {
      throw const ParseException(field: 'data.mosque', rawValue: null);
    }

    final MosqueSummary mosqueSummary;
    try {
      mosqueSummary = MosqueSummary.fromJson(mosqueRaw);
    } on FormatException catch (e) {
      throw ParseException(field: 'data.mosque', rawValue: e.message);
    }

    final timingsRaw = dataRaw['timings'];
    if (timingsRaw is! List) {
      throw ParseException(field: 'data.timings', rawValue: timingsRaw.runtimeType);
    }

    final List<PrayerTiming> timings;
    try {
      timings = timingsRaw
          .cast<Map<String, dynamic>>()
          .map(PrayerTiming.fromJson)
          .toList(growable: false);
    } on FormatException catch (e) {
      throw ParseException(field: 'data.timings[]', rawValue: e.message);
    }

    return MosqueTimingsResult(mosque: mosqueSummary, timings: timings);
  }

  // =========================================================================
  // POST /v1/mosques/:mosqueId/checkin
  // =========================================================================

  /// Records the authenticated user's attendance at [mosqueId] for [prayerSlot].
  ///
  /// Returns the updated community check-in count for today.
  /// Throws [ServerException] with code 'ALREADY_CHECKED_IN' on duplicate (409).
  Future<int> checkIn(String mosqueId, String prayerSlot) async {
    assert(mosqueId.isNotEmpty);
    assert(['fajr', 'dhuhr', 'asr', 'maghrib', 'isha', 'jumuah'].contains(prayerSlot));

    final uri     = Uri.parse('$_baseUrl/v1/mosques/$mosqueId/checkin');
    final headers = await _buildAuthHeaders();
    final headersWithContent = {
      ...headers,
      HttpHeaders.contentTypeHeader: 'application/json',
    };

    http.Response response;
    try {
      response = await _httpClient
          .post(uri, headers: headersWithContent,
                body: jsonEncode({'prayer_slot': prayerSlot}))
          .timeout(ApiConstants.requestTimeout);
    } on SocketException {
      throw const NoInternetException();
    } on TimeoutException {
      throw const RequestTimeoutException();
    } on http.ClientException {
      throw const NoInternetException();
    }

    // 409 ALREADY_CHECKED_IN — extract the count the server returns
    if (response.statusCode == 409) {
      final body = _decodeJson(response.body);
      final count = (body['error'] as Map<String, dynamic>?)?['checkin_count_today'] as int? ?? 0;
      throw ServerException(
        statusCode: 409,
        serverCode: 'ALREADY_CHECKED_IN',
        message:    'Already checked in for this prayer today.',
        extra:      count,
      );
    }

    _assertSuccess(response);
    final body   = _decodeJson(response.body);
    final data   = body['data'] as Map<String, dynamic>? ?? {};
    return (data['checkin_count_today'] as num?)?.toInt() ?? 0;
  }

  // =========================================================================
  // GET /v1/mosques/search?q=...
  // =========================================================================

  /// Searches mosques by name or city — used when GPS is denied.
  Future<List<Mosque>> searchMosques(String query) async {
    assert(query.length >= 2);

    final uri     = Uri.parse('$_baseUrl/v1/mosques/search')
        .replace(queryParameters: {'q': query, 'limit': '20'});
    final headers = await _buildAuthHeaders();
    final response = await _dispatchGet(uri, headers);

    _assertSuccess(response);
    final body    = _decodeJson(response.body);
    final dataRaw = body['data'];
    if (dataRaw is! List) return const [];

    try {
      return dataRaw
          .cast<Map<String, dynamic>>()
          .map(Mosque.fromJson)
          .toList(growable: false);
    } on FormatException catch (e) {
      throw ParseException(field: 'data[]', rawValue: e.message);
    }
  }

  // =========================================================================
  // Private helpers
  // =========================================================================

  /// Builds the standard request headers including the JWT Bearer token.
  /// Throws [ServerException](401) immediately if no token is stored —
  /// no network call is made when the user is logged out.
  Future<Map<String, String>> _buildAuthHeaders() async {
    final token = await _tokenService.getToken();
    if (token == null) {
      throw const ServerException(
        statusCode: 401,
        serverCode: 'UNAUTHORIZED',
        message:    'No authentication token found. Please log in.',
      );
    }
    return {
      HttpHeaders.authorizationHeader: 'Bearer $token',
      HttpHeaders.acceptHeader:        'application/json',
    };
  }

  /// Dispatches a GET request with a [ApiConstants.requestTimeout] deadline.
  /// Maps transport-level failures to typed [NetworkException] subclasses.
  Future<http.Response> _dispatchGet(
    Uri uri,
    Map<String, String> headers,
  ) async {
    try {
      return await _httpClient
          .get(uri, headers: headers)
          .timeout(ApiConstants.requestTimeout);
    } on SocketException {
      throw const NoInternetException();
    } on TimeoutException {
      throw const RequestTimeoutException();
    } on http.ClientException {
      // DNS failure, connection refused, SSL error, etc.
      throw const NoInternetException();
    }
  }

  /// Decodes the response body as JSON.
  /// Throws [ParseException] if the body is not valid JSON.
  Map<String, dynamic> _decodeJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw ParseException(
        field:    '',
        rawValue: body.length > 200 ? '${body.substring(0, 200)}…' : body,
        hint:     'Response body is not valid JSON',
      );
    }
  }

  /// Throws [ServerException] for any non-2xx HTTP status code.
  /// Parses the backend's standard `{ error: { code, message } }` envelope.
  void _assertSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // Body wasn't JSON — ServerException.fromBody handles the empty map
    }
    throw ServerException.fromBody(response.statusCode, body);
  }

  /// Formats a [DateTime] as 'YYYY-MM-DD' for API query params.
  String _formatDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '-${dt.month.toString().padLeft(2, '0')}'
      '-${dt.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// The canonical [MosqueRepository] provider.
///
/// Depends on [tokenServiceProvider] and [locationServiceProvider].
/// Both are auto-injected by Riverpod's dependency graph.
///
/// Override in tests:
///   ProviderContainer(overrides: [
///     mosqueRepositoryProvider.overrideWithValue(
///       MosqueRepository(
///         locationService: MockLocationService(),
///         tokenService:    MockTokenService(),
///         httpClient:      MockClient(...),
///         baseUrl:         'https://api.test',
///       ),
///     ),
///   ])
final mosqueRepositoryProvider = Provider<MosqueRepository>(
  (ref) => MosqueRepository(
    tokenService:    ref.watch(tokenServiceProvider),
    locationService: ref.watch(locationServiceProvider),
  ),
  name: 'mosqueRepositoryProvider',
);
