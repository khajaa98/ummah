// lib/features/mosques/presentation/providers/nearby_mosques_provider.dart
// =============================================================================
// UMM-304: nearbyMosquesProvider — Riverpod AsyncNotifier
//
// Orchestrates the full data pipeline for the NearbyMosquesScreen:
//
//   fetchNearby()
//     │
//     ├─ sets state = AsyncLoading
//     │
//     ├─ calls MosqueRepository.getNearbyMosques()
//     │     └─ internally: LocationService.getCurrentPosition()
//     │               └─ handles all permission states, throws LocationException
//     │     └─ internally: HTTP GET /v1/mosques/nearby with JWT
//     │               └─ maps all HTTP errors to ServerException
//     │
//     ├─ on success  → state = AsyncData<List<Mosque>>
//     └─ on any error → state = AsyncError<AppException>
//
// Why the repository handles location internally:
//   MosqueRepository owns the full "get me nearby mosques" use case.
//   Splitting GPS acquisition into the provider would create a two-step
//   async cascade with awkward intermediate states. Keeping it in the
//   repository makes the provider lean and fully testable by swapping
//   a single mosqueRepositoryProvider override.
//
// Refresh:
//   The UI calls ref.read(nearbyMosquesProvider.notifier).fetchNearby()
//   for both initial load and pull-to-refresh. Calling it while already
//   in AsyncData transitions through AsyncLoading (standard refresh UX).
//
// Test override pattern:
//   ProviderContainer(overrides: [
//     mosqueRepositoryProvider.overrideWithValue(
//       MosqueRepository(
//         locationService: MockLocationService(),
//         tokenService:    MockTokenService(),
//         httpClient:      MockClient(...),
//         baseUrl:         'https://api.test',
//       ),
//     ),
//   ])
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../data/models/mosque_model.dart';
import '../../data/repositories/mosque_repository.dart';

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class NearbyMosquesNotifier extends AsyncNotifier<List<Mosque>> {
  /// build() initialises the provider in an empty, ready-to-fetch state.
  ///
  /// We return an empty list rather than auto-fetching on build because:
  ///   1. The screen may not be visible yet (Riverpod initialises providers
  ///      eagerly when first watched).
  ///   2. It avoids a GPS permission dialog appearing before any UI is shown.
  ///   3. The screen calls fetchNearby() in its initState equivalent
  ///      (via ref.listen or a WidgetRef.notifier call on first mount).
  ///
  /// If you prefer auto-fetch on first watch, change `return []` to
  /// `return _fetch()` — both patterns compile and work correctly.
  @override
  FutureOr<List<Mosque>> build() => const [];

  // -------------------------------------------------------------------------
  // Public actions
  // -------------------------------------------------------------------------

  /// Triggers a full location → HTTP pipeline.
  ///
  /// Can be called:
  ///   • On first screen mount (initial load)
  ///   • On pull-to-refresh
  ///   • On "Retry" button tap after an error
  ///
  /// [params] — optional: override radius or limit. Defaults to 5 km / 20 results.
  Future<void> fetchNearby([
    NearbyMosquesParams params = const NearbyMosquesParams(),
  ]) async {
    // Transition to loading — UI shows spinner immediately.
    state = const AsyncValue.loading();

    // AsyncValue.guard() executes the closure and:
    //   - Wraps the return value in AsyncData on success
    //   - Wraps any thrown exception in AsyncError (preserving the stack trace)
    // This is the canonical Riverpod pattern — avoids manual try/catch.
    state = await AsyncValue.guard(() => _fetch(params));
  }

  // -------------------------------------------------------------------------
  // Private pipeline
  // -------------------------------------------------------------------------

  /// Executes the repository call and extracts the mosque list.
  ///
  /// All exceptions thrown here bubble up through AsyncValue.guard() and
  /// become AsyncError state — the UI's .when(error:) callback receives them.
  ///
  /// Exception types the UI must handle (all are [AppException] subclasses):
  ///   [LocationServiceDisabledException]             — GPS toggled off
  ///   [LocationPermissionDeniedException]            — user denied dialog
  ///   [LocationPermissionPermanentlyDeniedException] — permanently denied → settings
  ///   [NoInternetException]                          — no connectivity
  ///   [RequestTimeoutException]                      — 20 s timeout
  ///   [ServerException]                              — 4xx / 5xx from backend
  ///   [ParseException]                               — malformed JSON
  Future<List<Mosque>> _fetch(NearbyMosquesParams params) async {
    final repository = ref.read(mosqueRepositoryProvider);
    final result     = await repository.getNearbyMosques(params);
    return result.mosques;
    // result.privacyNote and result.radiusKm are available here if you want
    // to surface them in the UI (e.g. show "Searching within 5 km" header).
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Watches [NearbyMosquesNotifier] and exposes its [AsyncValue<List<Mosque>>].
///
/// Usage in widgets:
///   final mosquesAsync = ref.watch(nearbyMosquesProvider);
///
/// Trigger a fetch / refresh:
///   ref.read(nearbyMosquesProvider.notifier).fetchNearby();
final nearbyMosquesProvider =
    AsyncNotifierProvider<NearbyMosquesNotifier, List<Mosque>>(
  NearbyMosquesNotifier.new,
  name: 'nearbyMosquesProvider',
);
