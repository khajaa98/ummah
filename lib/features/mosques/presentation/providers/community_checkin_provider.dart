// lib/features/mosques/presentation/providers/community_checkin_provider.dart
// =============================================================================
// Sprint 7 update — added checkInActionProvider for the Check-In FAB.
//
// communityCheckInProvider — synchronous, derived, reads from nearbyMosquesProvider
//   + adds the optimistic +1 from _localCheckInsProvider when the user has
//   checked into a mosque this session (before the next background refresh).
//
// checkInActionProvider — AsyncNotifier.family that:
//   1. Calls MosqueRepository.checkIn(mosqueId, slot)
//   2. Optimistically records the check-in in _localCheckInsProvider
//   3. Exposes loading state so the FAB can show a progress indicator
// =============================================================================

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/mosque_model.dart';
import '../../data/repositories/mosque_repository.dart';
import '../constants/mosque_3d_nodes.dart';
import 'nearby_mosques_provider.dart';

// ---------------------------------------------------------------------------
// _localCheckInsProvider — in-memory optimistic check-ins for this session.
// Holds a Set of mosque IDs where the user has checked in since app launch.
// ---------------------------------------------------------------------------

final _localCheckInsProvider =
    StateNotifierProvider<_LocalCheckInNotifier, Set<String>>((ref) {
  return _LocalCheckInNotifier();
});

class _LocalCheckInNotifier extends StateNotifier<Set<String>> {
  _LocalCheckInNotifier() : super(const {});
  void add(String mosqueId) => state = {...state, mosqueId};
}

// ---------------------------------------------------------------------------
// communityCheckInProvider — base count from API + optimistic local offset
// ---------------------------------------------------------------------------

final communityCheckInProvider = Provider.family<int, String>((ref, mosqueId) {
  final nearbyAsync   = ref.watch(nearbyMosquesProvider);
  final localCheckIns = ref.watch(_localCheckInsProvider);

  final base = nearbyAsync.maybeWhen(
    data: (mosques) {
      final Mosque? mosque = mosques.cast<Mosque?>().firstWhere(
        (m) => m?.id == mosqueId,
        orElse: () => null,
      );
      return mosque?.checkinCountToday ?? 0;
    },
    orElse: () => 0,
  );

  // Add 1 if user checked in this session (optimistic until next refresh)
  return base + (localCheckIns.contains(mosqueId) ? 1 : 0);
});

// ---------------------------------------------------------------------------
// mosque3DTierProvider — maps raw count → tier integer 0–3
// ---------------------------------------------------------------------------

final mosque3DTierProvider = Provider.family<int, String>((ref, mosqueId) {
  final count = ref.watch(communityCheckInProvider(mosqueId));
  if (count >= Mosque3DTiers.tier3) return 3;
  if (count >= Mosque3DTiers.tier2) return 2;
  if (count >= Mosque3DTiers.tier1) return 1;
  return 0;
});

// ---------------------------------------------------------------------------
// checkInActionProvider — fires the API call and updates local state
// ---------------------------------------------------------------------------

class CheckInNotifier extends FamilyAsyncNotifier<void, String> {
  /// FamilyAsyncNotifier passes the family argument (the mosque ID) via build().
  String get mosqueId => arg;

  @override
  FutureOr<void> build(String mosqueId) {
    // No initial work — the action is fired explicitly by [checkIn].
  }

  Future<void> checkIn(String prayerSlot) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(mosqueRepositoryProvider);
      await repo.checkIn(mosqueId, prayerSlot);
      // Optimistically update display count for this session
      ref.read(_localCheckInsProvider.notifier).add(mosqueId);
    });
    // Re-surface the error so the caller's await sees it
    final s = state;
    if (s is AsyncError) {
      throw s.error;
    }
  }
}

final checkInActionProvider =
    AsyncNotifierProviderFamily<CheckInNotifier, void, String>(
  CheckInNotifier.new,
);
