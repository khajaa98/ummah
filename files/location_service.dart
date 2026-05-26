// lib/services/location/location_service.dart
// =============================================================================
// UMM-302: LocationService — privacy-first GPS wrapper.
//
// Wraps the geolocator package to provide a clean, typed interface for
// all location operations. No other layer imports geolocator directly.
//
// Permission lifecycle (called on every getNearbyMosques() invocation):
//   1. Assert location service (GPS) is enabled — throws LocationServiceDisabledException
//   2. Check current permission status
//   3. If denied, request permission via OS dialog (shown once)
//   4. If still denied after dialog, throw LocationPermissionDeniedException
//   5. If permanently denied, throw LocationPermissionPermanentlyDeniedException
//   6. If granted, acquire position with LocationAccuracy.high
//
// Privacy rules enforced here:
//   ✗ Position is NEVER cached or written to disk.
//   ✗ Coordinates are NEVER logged or sent to analytics.
//   ✓ The returned Position is used in-memory only, in the repository
//     call stack, and dereferenced immediately after the HTTP request.
//
// Riverpod:
//   locationServiceProvider is the sole entry point.
//   Override in tests with a mock that throws the desired exception.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/errors/app_exception.dart';

class LocationService {
  const LocationService();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Acquires the device's current GPS position.
  ///
  /// Manages the full permission lifecycle. Every call makes a fresh GPS
  /// request — no caching, by design (privacy requirement).
  ///
  /// Throws:
  ///   [LocationServiceDisabledException]             — device GPS is off
  ///   [LocationPermissionDeniedException]            — user denied the dialog
  ///   [LocationPermissionPermanentlyDeniedException] — permanently denied
  Future<Position> getCurrentPosition() async {
    await _assertLocationServiceEnabled();
    await _assertPermissionGranted();

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy:  LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on TimeoutException {
      // GPS fix timed out — surface as a permission-style error (best UX: retry)
      throw const LocationPermissionDeniedException();
    } on LocationServiceDisabledException {
      // User toggled GPS off mid-flight
      throw const LocationServiceDisabledException();
    } catch (_) {
      // Any other geolocator error — don't leak the raw exception type
      throw const LocationPermissionDeniedException();
    }
  }

  /// Returns the last known cached position — does NOT trigger a new GPS fix.
  /// Returns null if no cached position is available (e.g. fresh install).
  ///
  /// Useful as a fast initial map center before the precise fix arrives.
  /// The caller must not rely on this for accuracy-sensitive operations.
  Future<Position?> getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null; // not a fatal error — caller handles null gracefully
    }
  }

  /// Returns the current [LocationPermission] without prompting.
  /// Use to decide whether to show a rationale before calling [getCurrentPosition].
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  /// True if the device's location service (GPS) is currently enabled.
  Future<bool> isLocationServiceEnabled() => Geolocator.isLocationServiceEnabled();

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _assertLocationServiceEnabled() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) throw const LocationServiceDisabledException();
  }

  Future<void> _assertPermissionGranted() async {
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      // Trigger the OS permission dialog (shown only once by the OS)
      permission = await Geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return; // granted — proceed to GPS fix

      case LocationPermission.denied:
        throw const LocationPermissionDeniedException();

      case LocationPermission.deniedForever:
        // OS will not show the dialog again — must deep-link to app settings
        throw const LocationPermissionPermanentlyDeniedException();

      case LocationPermission.unableToDetermine:
        // Platform returned an indeterminate state — treat as denied (safe default)
        throw const LocationPermissionDeniedException();
    }
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// The canonical [LocationService] provider.
///
/// Override in tests:
///   ProviderContainer(overrides: [
///     locationServiceProvider.overrideWithValue(MockLocationService()),
///   ])
final locationServiceProvider = Provider<LocationService>(
  (_) => const LocationService(),
  name: 'locationServiceProvider',
);
