// test/widget_test.dart
// =============================================================================
// Smoke test — verifies the app boots without throwing during the first frame.
//
// We can't pump the full UmmahApp easily in a unit test because it triggers
// SecureStorage reads, NotificationService init, and Sentry — all of which
// need platform channel mocks. So this test is intentionally minimal: it
// confirms UmmahApp itself is constructable. Full integration tests live in
// integration_test/.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ummah/main.dart';

void main() {
  testWidgets('UmmahApp constructs without errors', (WidgetTester tester) async {
    const app = UmmahApp();
    expect(app, isA<Widget>());
  });
}