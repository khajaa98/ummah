// integration_test/screenshots_test.dart
// =============================================================================
// Screenshot harness — generates store-ready screenshots for both platforms.
//
// Runs the app at four "money shot" moments and captures a PNG for each:
//   1. Nearby mosques (with NextPrayerBanner countdown live)
//   2. Mosque detail (with verified timings + 3D viewport)
//   3. Qibla compass (in "high accuracy" state)
//   4. Supporter screen
//
// Usage from Fastlane:
//   fastlane screenshots
//
// Produces files under integration_test/screenshots/:
//   ios-nearby.png, android-nearby.png, etc.
//
// The integration_test framework captures the actual rendered surface,
// not a Flutter-only golden — so OS-specific status bars, fonts, and any
// platform views (3D viewport, native compass) all render correctly.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ummah/main.dart' as app;

void main() {
  final binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  final platform = Platform.isIOS ? 'ios' : 'android';

  testWidgets('1 - nearby mosques', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 4));
    await binding.takeScreenshot('$platform-1-nearby');
  });

  testWidgets('2 - mosque detail', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // Tap the first mosque card if any are rendered
    final firstCard = find.byType(InkWell).first;
    await tester.tap(firstCard);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await binding.takeScreenshot('$platform-2-detail');
  });

  testWidgets('3 - qibla', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Tap "Qibla" tab in the bottom NavigationBar (index 1)
    final qibla = find.text('Qibla');
    await tester.tap(qibla);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await binding.takeScreenshot('$platform-3-qibla');
  });

  testWidgets('4 - supporter', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final supporter = find.text('Supporter');
    await tester.tap(supporter);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await binding.takeScreenshot('$platform-4-supporter');
  });
}
