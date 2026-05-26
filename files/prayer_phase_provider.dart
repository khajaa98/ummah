// lib/core/providers/prayer_phase_provider.dart
// =============================================================================
// Sprint 6 — prayerPhaseProvider
//
// A StreamProvider<PrayerPhase> that transitions the app theme precisely at
// each prayer-phase boundary. Zero CPU activity between transitions.
//
// Polling strategy — why NOT every minute:
//   Polling every 60 seconds would:
//     • Rebuild the entire widget tree 1,440 times/day
//     • Produce theme transitions up to 59 seconds late
//     • Drain battery on always-on devices
//
//   Instead, the stream yields the current phase immediately, then sleeps for
//   exactly [PrayerPhase.durationToNextTransition()] before yielding again.
//   The total number of StreamProvider emissions per day = 4 (one per phase).
//
// Riverpod wiring:
//   • dynamicThemeProvider watches this provider.
//   • UmmahApp watches dynamicThemeProvider and passes the ThemeData to
//     MaterialApp, which internally uses AnimatedTheme for smooth colour lerp.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/prayer_phase.dart';

/// Emits the active [PrayerPhase] immediately, then re-emits precisely at
/// each phase-boundary crossing. Disposes the internal Future when the
/// provider goes out of scope (Riverpod cancels the async* on dispose).
final prayerPhaseProvider = StreamProvider.autoDispose<PrayerPhase>((ref) {
  return _prayerPhaseStream();
});

Stream<PrayerPhase> _prayerPhaseStream() async* {
  while (true) {
    final phase = PrayerPhase.current();
    yield phase;

    // Sleep until the exact moment the next phase begins.
    // durationToNextTransition() adds a 1-second buffer so we land safely
    // past the boundary before re-computing.
    await Future.delayed(phase.durationToNextTransition());
  }
}
