// lib/models/prayer_tracker_state.dart
// =============================================================================
// PrayerTrackerState — state container for the daily prayer tracker.
// =============================================================================

class PrayerTrackerState {
  final Map<String, bool> prayerCompletions;
  final int streak;
  final bool isMensesPaused;
  final String lastDate; // Format: YYYY-MM-DD

  PrayerTrackerState({
    required this.prayerCompletions,
    required this.streak,
    required this.isMensesPaused,
    required this.lastDate,
  });

  factory PrayerTrackerState.initial() {
    final today = DateTime.now().toIso8601String().split('T')[0];
    return PrayerTrackerState(
      prayerCompletions: {
        'Fajr': false,
        'Dhuhr': false,
        'Asr': false,
        'Maghrib': false,
        'Isha': false,
      },
      streak: 0,
      isMensesPaused: false,
      lastDate: today,
    );
  }

  PrayerTrackerState copyWith({
    Map<String, bool>? prayerCompletions,
    int? streak,
    bool? isMensesPaused,
    String? lastDate,
  }) {
    return PrayerTrackerState(
      prayerCompletions: prayerCompletions ?? this.prayerCompletions,
      streak: streak ?? this.streak,
      isMensesPaused: isMensesPaused ?? this.isMensesPaused,
      lastDate: lastDate ?? this.lastDate,
    );
  }

  Map<String, dynamic> toJson() => {
        'prayerCompletions': prayerCompletions,
        'streak': streak,
        'isMensesPaused': isMensesPaused,
        'lastDate': lastDate,
      };

  factory PrayerTrackerState.fromJson(Map<String, dynamic> json) {
    return PrayerTrackerState(
      prayerCompletions: Map<String, bool>.from(json['prayerCompletions']),
      streak: json['streak'] as int,
      isMensesPaused: json['isMensesPaused'] as bool,
      lastDate: json['lastDate'] as String,
    );
  }
}
