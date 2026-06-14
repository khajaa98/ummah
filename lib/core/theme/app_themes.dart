// lib/core/theme/app_themes.dart
// =============================================================================
// AppThemes — four curated ColorSchemes for the Islamic day cycle.
//
// Design language:
//   Every colour is chosen to evoke the emotional quality of its prayer time:
//   the cool stillness of pre-dawn, the clarity of midday, the warmth of
//   sunset, and the depth of night.
//
// Material 3 compliance:
//   • useMaterial3: true on every ThemeData — required for tonal surface
//     tokens (surfaceContainerLow, primaryContainer, etc.) used throughout
//     the Sprint 3–5 widget tree.
//   • `background` field is NOT used — it was deprecated in Flutter 3.18
//     and removed in 3.27. Surface colours use the M3 surface tonal system.
//   • textTheme uses GoogleFonts.interTextTheme() — satisfies the Inter
//     spec without bundling font files in the asset directory.
//
// Animated transitions:
//   MaterialApp.theme changes are automatically interpolated by Flutter's
//   built-in AnimatedTheme (wraps the entire app). No extra animation
//   controller is needed — swapping ThemeData produces smooth color lerping.
//
// Seed fallback:
//   Each phase also exposes a `seedColor` constant so that if a component
//   needs to generate its own palette (e.g. a custom chart), it derives from
//   the same source of truth.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'prayer_phase.dart';
export 'prayer_phase.dart';

abstract final class AppThemes {
  AppThemes._();

  // ---------------------------------------------------------------------------
  // Shared text theme — Inter for all phases (Arabic support in Sprint 7)
  // ---------------------------------------------------------------------------

  static TextTheme get _textTheme => GoogleFonts.interTextTheme();

  // ---------------------------------------------------------------------------
  // Fajr / Dawn  04:00–07:00
  // Palette: soft peach + morning sky blue
  // Feel: hushed, hopeful, cool pre-dawn stillness
  // ---------------------------------------------------------------------------

  static const fajrSeed = Color(0xFFFF9E80); // soft peach

  static final fajrDawn = ThemeData(
    useMaterial3: true,
    textTheme:    _textTheme,
    colorScheme:  const ColorScheme(
      brightness:              Brightness.light,
      primary:                 Color(0xFFBF5000), // deep peach on light
      onPrimary:               Colors.white,
      primaryContainer:        Color(0xFFFFDBCC), // pale peach container
      onPrimaryContainer:      Color(0xFF3D1100),
      secondary:               Color(0xFF006494), // dawn blue
      onSecondary:             Colors.white,
      secondaryContainer:      Color(0xFFCBE6FF),
      onSecondaryContainer:    Color(0xFF001E30),
      tertiary:                Color(0xFF7B5E00), // warm gold
      onTertiary:              Colors.white,
      tertiaryContainer:       Color(0xFFFFE08A),
      onTertiaryContainer:     Color(0xFF261A00),
      error:                   Color(0xFFBA1A1A),
      onError:                 Colors.white,
      errorContainer:          Color(0xFFFFDAD6),
      onErrorContainer:        Color(0xFF410002),
      surface:                 Color(0xFFFFF8F5), // warm off-white
      onSurface:               Color(0xFF201A17),
      surfaceContainerLowest:  Color(0xFFFFFFFF),
      surfaceContainerLow:     Color(0xFFFFF0EA),
      surfaceContainer:        Color(0xFFFAE8DF),
      surfaceContainerHigh:    Color(0xFFF4DDD4),
      surfaceContainerHighest: Color(0xFFEED7CD),
      onSurfaceVariant:        Color(0xFF52443D),
      outline:                 Color(0xFF85736B),
      outlineVariant:          Color(0xFFD8C2B9),
      shadow:                  Colors.black,
      scrim:                   Colors.black,
      inverseSurface:          Color(0xFF362F2C),
      onInverseSurface:        Color(0xFFFBEEE8),
      inversePrimary:          Color(0xFFFFB59A),
    ),
  );

  // ---------------------------------------------------------------------------
  // Dhuhr / Day  07:00–17:00
  // Palette: clear sky blue + sun amber
  // Feel: crisp, energetic, full-light clarity
  // ---------------------------------------------------------------------------

  static const dhuhrSeed = Color(0xFF0288D1); // clear sky blue

  static final dhuhrDay = ThemeData(
    useMaterial3: true,
    textTheme:    _textTheme,
    colorScheme:  const ColorScheme(
      brightness:              Brightness.light,
      primary:                 Color(0xFF00658A),
      onPrimary:               Colors.white,
      primaryContainer:        Color(0xFFC3E8FF),
      onPrimaryContainer:      Color(0xFF001E2C),
      secondary:               Color(0xFF825500),
      onSecondary:             Colors.white,
      secondaryContainer:      Color(0xFFFFDEA9),
      onSecondaryContainer:    Color(0xFF291800),
      tertiary:                Color(0xFF006C4C),
      onTertiary:              Colors.white,
      tertiaryContainer:       Color(0xFF86F7CA),
      onTertiaryContainer:     Color(0xFF002116),
      error:                   Color(0xFFBA1A1A),
      onError:                 Colors.white,
      errorContainer:          Color(0xFFFFDAD6),
      onErrorContainer:        Color(0xFF410002),
      surface:                 Color(0xFFF7FAFD),
      onSurface:               Color(0xFF181C1F),
      surfaceContainerLowest:  Colors.white,
      surfaceContainerLow:     Color(0xFFEEF3F7),
      surfaceContainer:        Color(0xFFE8EDF1),
      surfaceContainerHigh:    Color(0xFFE2E7EB),
      surfaceContainerHighest: Color(0xFFDCE2E6),
      onSurfaceVariant:        Color(0xFF40484C),
      outline:                 Color(0xFF70787D),
      outlineVariant:          Color(0xFFC0C8CC),
      shadow:                  Colors.black,
      scrim:                   Colors.black,
      inverseSurface:          Color(0xFF2D3134),
      onInverseSurface:        Color(0xFFEEF3F7),
      inversePrimary:          Color(0xFF7DD4FC),
    ),
  );

  // ---------------------------------------------------------------------------
  // Maghrib / Dusk  17:00–19:30
  // Palette: sunset orange + twilight purple
  // Feel: warm, transitional, golden-hour richness
  // ---------------------------------------------------------------------------

  static const maghribSeed = Color(0xFFFF7043); // sunset orange

  static final maghribDusk = ThemeData(
    useMaterial3: true,
    textTheme:    GoogleFonts.interTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    ),
    colorScheme:  const ColorScheme(
      brightness:              Brightness.dark,
      primary:                 Color(0xFFFFB59A), // warm peach on dark
      onPrimary:               Color(0xFF5C1800),
      primaryContainer:        Color(0xFF7D2C00),
      onPrimaryContainer:      Color(0xFFFFDBCC),
      secondary:               Color(0xFFCEBDFF), // soft lavender
      onSecondary:             Color(0xFF2D0062),
      secondaryContainer:      Color(0xFF420090),
      onSecondaryContainer:    Color(0xFFE9DEFF),
      tertiary:                Color(0xFFFFBD02), // golden yellow
      onTertiary:              Color(0xFF3F2E00),
      tertiaryContainer:       Color(0xFF5A4300),
      onTertiaryContainer:     Color(0xFFFFE08A),
      error:                   Color(0xFFFFB4AB),
      onError:                 Color(0xFF690005),
      errorContainer:          Color(0xFF93000A),
      onErrorContainer:        Color(0xFFFFDAD6),
      surface:                 Color(0xFF18110E), // deep warm dark
      onSurface:               Color(0xFFEDD8D0),
      surfaceContainerLowest:  Color(0xFF120C09),
      surfaceContainerLow:     Color(0xFF201A17),
      surfaceContainer:        Color(0xFF251E1B),
      surfaceContainerHigh:    Color(0xFF2F2825),
      surfaceContainerHighest: Color(0xFF3B3230),
      onSurfaceVariant:        Color(0xFFD8C2BA),
      outline:                 Color(0xFFA18D86),
      outlineVariant:          Color(0xFF52443D),
      shadow:                  Colors.black,
      scrim:                   Colors.black,
      inverseSurface:          Color(0xFFEDD8D0),
      onInverseSurface:        Color(0xFF201A17),
      inversePrimary:          Color(0xFF9C3B00),
    ),
  );

  // ---------------------------------------------------------------------------
  // Isha / Night  19:30–04:00
  // Palette: moon silver + deep indigo
  // Feel: serene, contemplative, infinite depth
  // ---------------------------------------------------------------------------

  static const ishaSeed = Color(0xFF3949AB); // deep indigo

  static final ishaNight = ThemeData(
    useMaterial3: true,
    textTheme:    GoogleFonts.interTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    ),
    colorScheme:  const ColorScheme(
      brightness:              Brightness.dark,
      primary:                 Color(0xFFBEC6FF), // moon silver-blue
      onPrimary:               Color(0xFF050D62),
      primaryContainer:        Color(0xFF222A80),
      onPrimaryContainer:      Color(0xFFDFE0FF),
      secondary:               Color(0xFFC3C7EA), // pale silver
      onSecondary:             Color(0xFF2C2F4F),
      secondaryContainer:      Color(0xFF424567),
      onSecondaryContainer:    Color(0xFFE0E1FF),
      tertiary:                Color(0xFFA9CBFF), // cold starlight blue
      onTertiary:              Color(0xFF003062),
      tertiaryContainer:       Color(0xFF1F477A),
      onTertiaryContainer:     Color(0xFFD4E3FF),
      error:                   Color(0xFFFFB4AB),
      onError:                 Color(0xFF690005),
      errorContainer:          Color(0xFF93000A),
      onErrorContainer:        Color(0xFFFFDAD6),
      surface:                 Color(0xFF101318), // near-black indigo tint
      onSurface:               Color(0xFFE1E2EC),
      surfaceContainerLowest:  Color(0xFF0B0E13),
      surfaceContainerLow:     Color(0xFF181C21),
      surfaceContainer:        Color(0xFF1C2025),
      surfaceContainerHigh:    Color(0xFF272A30),
      surfaceContainerHighest: Color(0xFF32353B),
      onSurfaceVariant:        Color(0xFFC4C6D0),
      outline:                 Color(0xFF8E909A),
      outlineVariant:          Color(0xFF44464F),
      shadow:                  Colors.black,
      scrim:                   Colors.black,
      inverseSurface:          Color(0xFFE1E2EC),
      onInverseSurface:        Color(0xFF181C21),
      inversePrimary:          Color(0xFF3A43A0),
    ),
  );

  // ---------------------------------------------------------------------------
  // Convenience: map phase enum → ThemeData
  // ---------------------------------------------------------------------------

  static ThemeData forPhase(PrayerPhase phase) => switch (phase) {
    PrayerPhase.fajrDawn    => fajrDawn,
    PrayerPhase.dhuhrDay    => dhuhrDay,
    PrayerPhase.maghribDusk => maghribDusk,
    PrayerPhase.ishaNight   => ishaNight,
  };
}

// (prayer_phase.dart imported + re-exported at the top of this file)
