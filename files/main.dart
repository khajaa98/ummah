// lib/main.dart
// =============================================================================
// Ummah — app entry point.
//
// Sprint 6 changes:
//   • UmmahApp is now a ConsumerWidget — watches dynamicThemeProvider.
//   • MaterialApp.theme is set from the active ThemeData each frame.
//   • Flutter's built-in AnimatedTheme (inside MaterialApp) automatically
//     lerps between ThemeData objects when theme changes, producing the
//     smooth colour transition the spec requires — no custom animation needed.
//   • themeMode is fixed to ThemeMode.light so the dynamic theme engine
//     drives appearance exclusively (day/night handled by our phases, not OS).
//   • home remains NearbyMosquesScreen — NOT MosqueDetailScreen, which
//     requires a required `mosque` parameter and would fail to compile.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/dynamic_theme_provider.dart';
import 'features/mosques/presentation/screens/nearby_mosques_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: UmmahApp(),
    ),
  );
}

class UmmahApp extends ConsumerWidget {
  const UmmahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the dynamic theme — rebuilds only when the prayer phase changes
    // (at most 4 times per day). MaterialApp's internal AnimatedTheme
    // interpolates the colour transition smoothly over 200ms.
    final activeTheme = ref.watch(dynamicThemeProvider);

    return MaterialApp(
      title:                      'Ummah',
      debugShowCheckedModeBanner: false,

      // The dynamic engine drives both light and dark appearance.
      // Maghrib and Isha phases return dark ThemeData; Fajr and Dhuhr return
      // light ThemeData. ThemeMode.light ensures MaterialApp always uses
      // `theme` (not `darkTheme`) so our engine has full control.
      theme:     activeTheme,
      themeMode: ThemeMode.light,

      // AnimatedTheme transition duration (default 200ms — can be tuned here)
      // MaterialApp exposes this via themeAnimationDuration in Flutter 3.18+.
      themeAnimationDuration: const Duration(milliseconds: 600),
      themeAnimationCurve:    Curves.easeInOut,

      home: const NearbyMosquesScreen(),
    );
  }
}
