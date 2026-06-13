// lib/models/prayer_timing.dart
// =============================================================================
// PrayerTiming — immutable data model.
//
// Maps to GET /v1/mosques/:mosqueId/timings response shape.
// Times are stored as plain strings ("HH:MM") to match the backend contract —
// they are local civil times with no associated timezone, so converting them
// to DateTime would introduce false UTC semantics.
//
// A TimeOfDay extension is provided for widgets that need native Flutter time
// rendering (e.g. displaying in a CountdownTimer widget).
// =============================================================================

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// VerificationStatus enum
// ---------------------------------------------------------------------------

enum VerificationStatus {
  pending('pending'),
  verified('verified'),
  rejected('rejected'),
  unknown('unknown');

  const VerificationStatus(this.value);
  final String value;

  bool get isVerified => this == VerificationStatus.verified;

  static VerificationStatus fromString(String? value) {
    return VerificationStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => VerificationStatus.unknown,
    );
  }
}

// ---------------------------------------------------------------------------
// CalcMethod enum
// ---------------------------------------------------------------------------

enum CalcMethod {
  manual('manual'),
  mwl('MWL'),
  isna('ISNA'),
  egypt('Egypt'),
  unknown('unknown');

  const CalcMethod(this.value);
  final String value;

  String get displayLabel {
    switch (this) {
      case CalcMethod.manual: return 'Manual verification';
      case CalcMethod.mwl:    return 'Muslim World League';
      case CalcMethod.isna:   return 'ISNA';
      case CalcMethod.egypt:  return 'Egyptian General Authority';
      case CalcMethod.unknown: return 'Unknown';
    }
  }

  static CalcMethod fromString(String? value) {
    return CalcMethod.values.firstWhere(
      (e) => e.value == value,
      orElse: () => CalcMethod.unknown,
    );
  }
}

// ---------------------------------------------------------------------------
// TimingVerification — nested value type
// ---------------------------------------------------------------------------

@immutable
class TimingVerification {
  const TimingVerification({
    required this.status,
    this.verifiedAt,
    this.verifiedByDisplay,
    this.sourceNote,
  });

  final VerificationStatus status;
  final DateTime?          verifiedAt;
  final String?            verifiedByDisplay;   // display name only, no ID (per API contract)
  final String?            sourceNote;

  factory TimingVerification.fromJson(Map<String, dynamic> json) {
    DateTime? verifiedAt;
    final verifiedAtRaw = json['verified_at'];
    if (verifiedAtRaw is String) {
      verifiedAt = DateTime.tryParse(verifiedAtRaw)?.toLocal();
    }

    return TimingVerification(
      status:            VerificationStatus.fromString(json['status'] as String?),
      verifiedAt:        verifiedAt,
      verifiedByDisplay: json['verified_by_display'] as String?,
      sourceNote:        json['source_note']         as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'status':              status.value,
    if (verifiedAt != null)
      'verified_at':       verifiedAt!.toUtc().toIso8601String(),
    if (verifiedByDisplay != null)
      'verified_by_display': verifiedByDisplay,
    if (sourceNote != null)
      'source_note':       sourceNote,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimingVerification &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          verifiedAt == other.verifiedAt;

  @override
  int get hashCode => Object.hash(status, verifiedAt);
}

// ---------------------------------------------------------------------------
// PrayerTiming model
// ---------------------------------------------------------------------------

@immutable
class PrayerTiming {
  const PrayerTiming({
    required this.effectiveDate,
    required this.fajr,
    required this.sunrise,
    required this.dhuhr,
    required this.asr,
    required this.maghrib,
    required this.isha,
    this.jumuah,
    required this.calcMethod,
    required this.verification,
  });

  final DateTime          effectiveDate;

  // Prayer times as "HH:MM" strings — local civil time, no timezone
  final String            fajr;
  final String            sunrise;
  final String            dhuhr;
  final String            asr;
  final String            maghrib;
  final String            isha;
  final String?           jumuah;    // null on non-Fridays

  final CalcMethod        calcMethod;
  final TimingVerification verification;

  // -------------------------------------------------------------------------
  // Deserialization
  // -------------------------------------------------------------------------

  factory PrayerTiming.fromJson(Map<String, dynamic> json) {
    final effectiveDateRaw = json['effective_date'];
    if (effectiveDateRaw is! String) {
      throw FormatException(
        'PrayerTiming.fromJson: "effective_date" must be a String, got $effectiveDateRaw',
      );
    }
    final effectiveDate = DateTime.tryParse(effectiveDateRaw);
    if (effectiveDate == null) {
      throw FormatException(
        'PrayerTiming.fromJson: could not parse "effective_date": $effectiveDateRaw',
      );
    }

    final verificationRaw = json['verification'];
    if (verificationRaw is! Map<String, dynamic>) {
      throw FormatException(
        'PrayerTiming.fromJson: "verification" must be an object, got $verificationRaw',
      );
    }

    return PrayerTiming(
      effectiveDate: effectiveDate,
      fajr:          _requireTimeString(json, 'fajr'),
      sunrise:       _requireTimeString(json, 'sunrise'),
      dhuhr:         _requireTimeString(json, 'dhuhr'),
      asr:           _requireTimeString(json, 'asr'),
      maghrib:       _requireTimeString(json, 'maghrib'),
      isha:          _requireTimeString(json, 'isha'),
      jumuah:        json['jumu_ah'] as String?,
      calcMethod:    CalcMethod.fromString(json['calc_method'] as String?),
      verification:  TimingVerification.fromJson(verificationRaw),
    );
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'effective_date': effectiveDate.toIso8601String().substring(0, 10),
    'fajr':           fajr,
    'sunrise':        sunrise,
    'dhuhr':          dhuhr,
    'asr':            asr,
    'maghrib':        maghrib,
    'isha':           isha,
    if (jumuah != null) 'jumu_ah': jumuah,
    'calc_method':    calcMethod.value,
    'verification':   verification.toJson(),
  };

  // -------------------------------------------------------------------------
  // Immutable update helper
  // -------------------------------------------------------------------------

  PrayerTiming copyWith({
    DateTime?           effectiveDate,
    String?             fajr,
    String?             sunrise,
    String?             dhuhr,
    String?             asr,
    String?             maghrib,
    String?             isha,
    String?             jumuah,
    CalcMethod?         calcMethod,
    TimingVerification? verification,
  }) {
    return PrayerTiming(
      effectiveDate: effectiveDate ?? this.effectiveDate,
      fajr:          fajr          ?? this.fajr,
      sunrise:       sunrise       ?? this.sunrise,
      dhuhr:         dhuhr         ?? this.dhuhr,
      asr:           asr           ?? this.asr,
      maghrib:       maghrib       ?? this.maghrib,
      isha:          isha          ?? this.isha,
      jumuah:        jumuah        ?? this.jumuah,
      calcMethod:    calcMethod    ?? this.calcMethod,
      verification:  verification  ?? this.verification,
    );
  }

  // -------------------------------------------------------------------------
  // Convenience getters
  // -------------------------------------------------------------------------

  bool get isVerified => verification.status.isVerified;

  bool get isFriday => effectiveDate.weekday == DateTime.friday;

  /// All five daily prayer slots as an ordered list of (name, time) pairs.
  List<({String name, String time})> get dailyPrayers => [
    (name: 'Fajr',    time: fajr),
    (name: 'Sunrise', time: sunrise),
    (name: 'Dhuhr',   time: dhuhr),
    (name: 'Asr',     time: asr),
    (name: 'Maghrib', time: maghrib),
    (name: 'Isha',    time: isha),
    if (jumuah != null && isFriday)
      (name: "Jumu'ah", time: jumuah!),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrayerTiming &&
          runtimeType == other.runtimeType &&
          effectiveDate == other.effectiveDate;

  @override
  int get hashCode => effectiveDate.hashCode;

  @override
  String toString() =>
      'PrayerTiming(date: ${effectiveDate.toIso8601String().substring(0, 10)}, '
      'fajr: $fajr, isha: $isha, verified: $isVerified)';
}

// ---------------------------------------------------------------------------
// Extension — convert "HH:MM" string to Flutter TimeOfDay
// ---------------------------------------------------------------------------

extension PrayerTimeString on String {
  /// Parses a "HH:MM" prayer-time string into a Flutter [TimeOfDay].
  /// Returns null if the string is not in the expected format.
  TimeOfDay? toTimeOfDay() {
    final parts = split(':');
    if (parts.length != 2) return null;
    final hour   = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

String _requireTimeString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException(
      'PrayerTiming.fromJson: required time field "$key" is missing or not a String '
      '(got ${value.runtimeType})',
    );
  }
  // Validate basic HH:MM format
  final pattern = RegExp(r'^\d{2}:\d{2}$');
  if (!pattern.hasMatch(value)) {
    throw FormatException(
      'PrayerTiming.fromJson: time field "$key" has unexpected format "$value" '
      '(expected HH:MM)',
    );
  }
  return value;
}
