// lib/features/mosques/presentation/providers/prayer_timings_provider.dart
// =============================================================================
// mosqueTimingsProvider — fetches verified prayer timings for a given mosque.
//
// Uses FutureProvider.family so each mosque ID gets its own cache slot.
// autoDispose ensures the HTTP response is cleared when the detail screen
// is popped (avoids stale data on re-entry).
//
// On error (network, 404, parse): returns [] rather than propagating
// AsyncError — the UI renders a graceful "no timings available" message
// instead of crashing the detail screen over a secondary feature.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/prayer_timing.dart';
import '../../data/repositories/mosque_repository.dart';

final mosqueTimingsProvider =
    FutureProvider.family.autoDispose<List<PrayerTiming>, String>(
  (ref, mosqueId) async {
    final repo = ref.watch(mosqueRepositoryProvider);
    try {
      final result = await repo.getMosqueTimings(
        mosqueId,
        // Fetch today only on first load — fast and sufficient for the detail screen
        MosqueTimingsParams(date: DateTime.now()),
      );
      return result.timings;
    } catch (_) {
      // Secondary feature — don't blow up the whole screen on failure
      return const [];
    }
  },
  name: 'mosqueTimingsProvider',
);
