// lib/models/mosque.dart
// =============================================================================
// Mosque — immutable data model.
// =============================================================================

import 'package:flutter/foundation.dart';

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
}

enum Madhab {
  hanafi('Hanafi'),
  shafii('Shafii'),
  maliki('Maliki'),
  hanbali('Hanbali'),
  unknown('unknown');

  const Madhab(this.value);
  final String value;

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

  factory Mosque.fromJson(Map<String, dynamic> json) {
    final id   = json['id'] as String? ?? '';
    final name = json['name'] as String? ?? '';
    final city = json['city'] as String? ?? '';

    double distanceKm = 0.0;
    if (json['distance_km'] != null) {
      distanceKm = (json['distance_km'] as num).toDouble();
    }

    double lat = 0.0;
    double lng = 0.0;
    if (json['coordinates'] != null) {
      final coords = json['coordinates'] as Map<String, dynamic>;
      lat = (coords['latitude'] as num).toDouble();
      lng = (coords['longitude'] as num).toDouble();
    } else {
      lat = (json['latitude'] as num?)?.toDouble() ?? 0.0;
      lng = (json['longitude'] as num?)?.toDouble() ?? 0.0;
    }

    return Mosque(
      id:                 id,
      name:               name,
      nameAr:             json['name_ar'] as String?,
      distanceKm:         distanceKm,
      addressLine:        json['address_line'] as String? ?? json['addressLine'] as String?,
      city:               city,
      madhab:             Madhab.fromString(json['madhab'] as String?),
      status:             MosqueStatus.fromString(json['status'] as String?),
      coordinates:        MosqueCoordinates(latitude: lat, longitude: lng),
      hasVerifiedTimings: json['has_verified_timings'] as bool? ?? false,
      checkinCountToday:  json['checkin_count_today']  as int?  ?? 0,
    );
  }

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
}
