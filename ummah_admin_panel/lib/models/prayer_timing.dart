// lib/models/prayer_timing.dart
// =============================================================================
// PrayerTiming — immutable data model.
//
// Maps to GET /v1/mosques/:mosqueId/timings response shape.
// Times are stored as plain strings ("HH:MM") to match the backend contract.
// =============================================================================

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/foundation.dart';

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

enum CalcMethod {
  manual('manual'),
  mwl('MWL'),
  isna('ISNA'),
  rules('Rules'),
  unknown('unknown');

  const CalcMethod(this.value);
  final String value;

  static CalcMethod fromString(String? value) {
    return CalcMethod.values.firstWhere(
      (e) => e.value == value,
      orElse: () => CalcMethod.unknown,
    );
  }
}

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
  final String?            verifiedByDisplay;
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
}

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
  final String            fajr;
  final String            sunrise;
  final String            dhuhr;
  final String            asr;
  final String            maghrib;
  final String            isha;
  final String?           jumuah;
  final CalcMethod        calcMethod;
  final TimingVerification verification;

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

    final verificationRaw = json['verification'] ?? {'status': 'pending'};

    return PrayerTiming(
      effectiveDate: effectiveDate,
      fajr:          _requireTimeString(json, 'fajr'),
      sunrise:       _requireTimeString(json, 'sunrise'),
      dhuhr:         _requireTimeString(json, 'dhuhr'),
      asr:           _requireTimeString(json, 'asr'),
      maghrib:       _requireTimeString(json, 'maghrib'),
      isha:          _requireTimeString(json, 'isha'),
      jumuah:        json['jumu_ah'] as String? ?? json['jumuah'] as String?,
      calcMethod:    CalcMethod.fromString(json['calc_method'] as String?),
      verification:  TimingVerification.fromJson(verificationRaw as Map<String, dynamic>),
    );
  }

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
}

extension PrayerTimeString on String {
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

String _requireTimeString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException(
      'PrayerTiming.fromJson: required time field "$key" is missing or not a String',
    );
  }
  final pattern = RegExp(r'^\d{2}:\d{2}$');
  if (!pattern.hasMatch(value)) {
    throw FormatException(
      'PrayerTiming.fromJson: time field "$key" has unexpected format "$value" (expected HH:MM)',
    );
  }
  return value;
}
