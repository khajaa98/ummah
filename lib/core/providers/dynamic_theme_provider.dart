// lib/core/providers/dynamic_theme_provider.dart
// =============================================================================
// Sprint 6 — dynamicThemeProvider
//
// A derived Provider<ThemeData> that maps the current PrayerPhase to the
// matching ThemeData from AppThemes.
//
// Two-layer design:
//   1. prayerPhaseProvider (StreamProvider) — owns the time logic
//   2. dynamicThemeProvider (Provider)      — owns the theme mapping
//
// Separating these layers means:
//   • Tests can override prayerPhaseProvider with a fixed phase (e.g. ishaNight)
//     without touching theme logic.
//   • The theme mapping in AppThemes can be tweaked without touching
//     the stream/timer logic in prayerPhaseProvider.
//
// Fallback: while the stream is loading (first frame only), falls back to
// the current time via PrayerPhase.current() so the app never renders
// a blank/default theme on first paint.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_themes.dart';
import '../theme/prayer_phase.dart';
import 'prayer_phase_provider.dart';

/// Synchronously derives the active [ThemeData] from [prayerPhaseProvider].
///
/// Riverpod unwraps the [AsyncValue<PrayerPhase>] via [AsyncValue.maybeWhen]:
///   • on data  → use the emitted phase
///   • on loading / error → fall back to [PrayerPhase.current()] (no blank flash)
final dynamicThemeProvider = Provider.autoDispose<ThemeData>((ref) {
  final phaseAsync = ref.watch(prayerPhaseProvider);

  final phase = phaseAsync.maybeWhen(
    data:    (p) => p,
    orElse:  ()  => PrayerPhase.current(), // synchronous fallback on first frame
  );

  return AppThemes.forPhase(phase);
});
