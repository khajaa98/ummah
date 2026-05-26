// lib/models/mosque.dart
// =============================================================================
// Mosque — immutable data model.
//
// Maps 1-to-1 with the API contract from GET /v1/mosques/nearby.
// All nullable fields mirror the backend schema exactly (e.g. nameAr is
// optional, addressLine may not be set for newly registered mosques).
//
// Uses const constructors throughout for widget-tree efficiency.
// copyWith() supports immutable state updates in the presentation layer.
// =============================================================================

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Supporting value type: MosqueCoordinates
// ---------------------------------------------------------------------------

@immutable
class MosqueCoordinates {
  const MosqueCoordinates({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  factory MosqueCoordinates.fromJson(Map<String, dynamic> json) {
    return MosqueCoordinates(
      latitude:  (json['latitude']  as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude':  latitude,
    'longitude': longitude,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MosqueCoordinates &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'MosqueCoordinates(lat: $latitude, lng: $longitude)';
}

// ---------------------------------------------------------------------------
// Madhab enum — mirrors the Prisma/Postgres enum exactly
// ---------------------------------------------------------------------------

enum Madhab {
  hanafi('Hanafi'),
  shafii('Shafii'),
  maliki('Maliki'),
  hanbali('Hanbali'),
  unknown('unknown');

  const Madhab(this.value);
  final String value;

  /// Display label — Shafii stored as 'Shafii' in API, shown as "Shafi'i"
  String get displayLabel {
    switch (this) {
      case Madhab.hanafi:  return "Hanafi";
      case Madhab.shafii:  return "Shafi'i";
      case Madhab.maliki:  return "Maliki";
      case Madhab.hanbali: return "Hanbali";
      case Madhab.unknown: return "Unknown";
    }
  }

  static Madhab fromString(String? value) {
    return Madhab.values.firstWhere(
      (e) => e.value.toLowerCase() == value?.toLowerCase(),
      orElse: () => Madhab.unknown,
    );
  }
}

// ---------------------------------------------------------------------------
// MosqueStatus enum
// ---------------------------------------------------------------------------

enum MosqueStatus {
  active('active'),
  closed('closed'),
  unverified('unverified'),
  unknown('unknown');

  const MosqueStatus(this.value);
  final String value;

  static MosqueStatus fromString(String? value) {
    return MosqueStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => MosqueStatus.unknown,
    );
  }
}

// ---------------------------------------------------------------------------
// Mosque model
// ---------------------------------------------------------------------------

@immutable
class Mosque {
  const Mosque({
    required this.id,
    required this.name,
    this.nameAr,
    required this.distanceKm,
    this.addressLine,
    required this.city,
    required this.madhab,
    required this.status,
    required this.coordinates,
    required this.hasVerifiedTimings,
    required this.checkinCountToday,
  });

  final String           id;
  final String           name;
  final String?          nameAr;
  final double           distanceKm;
  final String?          addressLine;
  final String           city;
  final Madhab           madhab;
  final MosqueStatus     status;
  final MosqueCoordinates coordinates;
  final bool             hasVerifiedTimings;
  final int              checkinCountToday;

  // -------------------------------------------------------------------------
  // Deserialization
  // -------------------------------------------------------------------------

  /// Parses a single mosque object from the `data[]` array in the API response.
  /// Throws [FormatException] if any required field is missing or maltyped.
  factory Mosque.fromJson(Map<String, dynamic> json) {
    // Required string fields — null-safe coercion with explicit error messaging
    final id   = _requireString(json, 'id');
    final name = _requireString(json, 'name');
    final city = _requireString(json, 'city');

    final distanceKm = switch (json['distance_km']) {
      final num n => n.toDouble(),
      _           => throw FormatException(
          'Mosque.fromJson: "distance_km" must be a number, got ${json['distance_km']}',
        ),
    };

    final coordinatesRaw = json['coordinates'];
    if (coordinatesRaw is! Map<String, dynamic>) {
      throw FormatException(
        'Mosque.fromJson: "coordinates" must be an object, got $coordinatesRaw',
      );
    }

    return Mosque(
      id:                 id,
      name:               name,
      nameAr:             json['name_ar'] as String?,
      distanceKm:         distanceKm,
      addressLine:        json['address_line'] as String?,
      city:               city,
      madhab:             Madhab.fromString(json['madhab'] as String?),
      status:             MosqueStatus.fromString(json['status'] as String?),
      coordinates:        MosqueCoordinates.fromJson(coordinatesRaw),
      hasVerifiedTimings: json['has_verified_timings'] as bool? ?? false,
      checkinCountToday:  json['checkin_count_today']  as int?  ?? 0,
    );
  }

  // -------------------------------------------------------------------------
  // Serialization (useful for caching / offline storage)
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id':                   id,
    'name':                 name,
    if (nameAr != null)     'name_ar': nameAr,
    'distance_km':          distanceKm,
    if (addressLine != null)'address_line': addressLine,
    'city':                 city,
    'madhab':               madhab.value,
    'status':               status.value,
    'coordinates':          coordinates.toJson(),
    'has_verified_timings': hasVerifiedTimings,
    'checkin_count_today':  checkinCountToday,
  };

  // -------------------------------------------------------------------------
  // Immutable update helper
  // -------------------------------------------------------------------------

  Mosque copyWith({
    String?            id,
    String?            name,
    String?            nameAr,
    double?            distanceKm,
    String?            addressLine,
    String?            city,
    Madhab?            madhab,
    MosqueStatus?      status,
    MosqueCoordinates? coordinates,
    bool?              hasVerifiedTimings,
    int?               checkinCountToday,
  }) {
    return Mosque(
      id:                 id                ?? this.id,
      name:               name               ?? this.name,
      nameAr:             nameAr             ?? this.nameAr,
      distanceKm:         distanceKm         ?? this.distanceKm,
      addressLine:        addressLine        ?? this.addressLine,
      city:               city               ?? this.city,
      madhab:             madhab             ?? this.madhab,
      status:             status             ?? this.status,
      coordinates:        coordinates        ?? this.coordinates,
      hasVerifiedTimings: hasVerifiedTimings ?? this.hasVerifiedTimings,
      checkinCountToday:  checkinCountToday  ?? this.checkinCountToday,
    );
  }

  // -------------------------------------------------------------------------
  // Convenience getters
  // -------------------------------------------------------------------------

  /// Formatted distance — shows metres if under 1 km for better UX.
  String get formattedDistance {
    if (distanceKm < 1.0) {
      return '${(distanceKm * 1000).round()} m';
    }
    return '${distanceKm.toStringAsFixed(1)} km';
  }

  bool get isActive => status == MosqueStatus.active;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Mosque &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Mosque(id: $id, name: $name, distance: $formattedDistance)';
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    throw FormatException('Mosque.fromJson: required field "$key" is null or missing');
  }
  if (value is! String) {
    throw FormatException(
      'Mosque.fromJson: field "$key" must be a String, got ${value.runtimeType}',
    );
  }
  return value;
}
