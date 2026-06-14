// lib/core/theme/prayer_phase.dart
// =============================================================================
// PrayerPhase — the four visual periods of the Islamic day.
//
// Used by the dynamic theme engine to select the correct ColorScheme.
// Boundaries use approximate times for Hyderabad (17°N); Sprint 7 will
// replace these with actual prayer times from the API.
//
// Phase boundaries:
//   fajrDawn      04:00 → 07:00  (pre-sunrise calm)
//   dhuhrDay      07:00 → 17:00  (bright daylight)
//   maghribDusk   17:00 → 19:30  (golden-hour twilight)
//   ishaNight     19:30 → 04:00  (deep night)
//
// Timer strategy: instead of polling every minute (wasteful), we compute the
// exact duration to the next phase boundary and schedule a single Future.
// This means the theme transition fires precisely at the boundary, not up to
// 59 seconds late, and causes zero CPU activity between transitions.
// =============================================================================

enum PrayerPhase {
  fajrDawn,
  dhuhrDay,
  maghribDusk,
  ishaNight;

  // ---------------------------------------------------------------------------
  // Factory
  // ---------------------------------------------------------------------------

  /// Returns the phase that is currently active based on [DateTime.now()].
  static PrayerPhase current() {
    final minutes = DateTime.now().hour * 60 + DateTime.now().minute;

    if (minutes >= 4 * 60  && minutes < 7 * 60)  return fajrDawn;
    if (minutes >= 7 * 60  && minutes < 17 * 60) return dhuhrDay;
    if (minutes >= 17 * 60 && minutes < 19 * 60 + 30) return maghribDusk;
    return ishaNight;
  }

  // ---------------------------------------------------------------------------
  // Timer precision
  // ---------------------------------------------------------------------------

  /// Duration from now until the next phase boundary.
  ///
  /// The StreamProvider uses this to sleep exactly until the transition
  /// rather than waking every minute to re-check.
  Duration durationToNextTransition() {
    final now     = DateTime.now();
    DateTime todayAt(int h, int m) =>
        DateTime(now.year, now.month, now.day, h, m);

    // Ordered list of boundary points for today
    final boundaries = [
      todayAt(4,  0),
      todayAt(7,  0),
      todayAt(17, 0),
      todayAt(19, 30),
      // Tomorrow's first boundary
      todayAt(4,  0).add(const Duration(days: 1)),
    ];

    // Find the next boundary that is strictly in the future
    final next = boundaries.firstWhere((b) => b.isAfter(now));
    final remaining = next.difference(now);

    // Add 1 second of padding so we land safely past the boundary
    return remaining + const Duration(seconds: 1);
  }

  // ---------------------------------------------------------------------------
  // Display metadata
  // ---------------------------------------------------------------------------

  String get label => switch (this) {
    fajrDawn    => 'Fajr',
    dhuhrDay    => 'Dhuhr',
    maghribDusk => 'Maghrib',
    ishaNight   => 'Isha',
  };
}
