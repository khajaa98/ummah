// lib/core/constants/api_constants.dart
// =============================================================================
// API base URL and endpoint path constants.
//
// Base URL selection strategy:
//   The URL is resolved at compile time via --dart-define so that no
//   environment-specific string is ever hardcoded inside business logic.
//
//   Build commands:
//     # Android emulator (maps 10.0.2.2 → host machine's localhost)
//     flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
//
//     # iOS simulator (simulator shares host network)
//     flutter run --dart-define=API_BASE_URL=http://localhost:3000
//
//     # Physical device on same WiFi (replace with your machine's LAN IP)
//     flutter run --dart-define=API_BASE_URL=http://192.168.1.x:3000
//
//     # Production
//     flutter build appbundle --dart-define=API_BASE_URL=https://api.ummah.app
//
//   If --dart-define is not set, falls back to the Android emulator address
//   so `flutter run` with no flags "just works" during local development.
// =============================================================================

abstract final class ApiConstants {
  ApiConstants._(); // prevent instantiation

  /// Resolved at compile time via --dart-define=API_BASE_URL=...
  /// Default: Android emulator loopback (10.0.2.2 → host localhost).
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  // ---------------------------------------------------------------------------
  // Endpoint paths
  // ---------------------------------------------------------------------------

  static const String nearbyMosques    = '/v1/mosques/nearby';
  static const String mosqueTimings    = '/v1/mosques'; // append /:id/timings

  // ---------------------------------------------------------------------------
  // Request defaults (mirror the Node.js validation constraints)
  // ---------------------------------------------------------------------------

  static const double defaultRadiusKm  = 5.0;
  static const double maxRadiusKm      = 50.0;
  static const int    defaultLimit      = 20;
  static const int    maxLimit          = 100;
  static const Duration requestTimeout  = Duration(seconds: 20);
}
