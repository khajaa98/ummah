// lib/features/mosques/presentation/providers/community_checkin_provider.dart
// =============================================================================
// Sprint 5 — communityCheckInProvider
//
// A synchronous, derived Provider.family — computes the check-in count for a
// specific mosque by watching the already-fetched nearbyMosquesProvider list.
//
// Zero extra network calls. Zero extra Prisma queries.
// The count updates reactively whenever nearbyMosquesProvider refreshes.
//
// Why Provider.family and not AsyncNotifierProvider:
//   The data already lives in nearbyMosquesProvider's AsyncValue.
//   Wrapping it in another async layer adds indirection for no gain.
//   A synchronous derived provider is the correct Riverpod pattern here.
//
// Also exposed: mosque3DTierProvider — derives the upgrade tier from the
// count so the viewport widget doesn't contain business logic.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/mosque_model.dart';
import '../constants/mosque_3d_nodes.dart';
import 'nearby_mosques_provider.dart';

// ---------------------------------------------------------------------------
// communityCheckInProvider
// Returns the checkin_count_today for a specific mosque ID.
// Returns 0 when the nearby list is loading, empty, or the mosque is not found.
// ---------------------------------------------------------------------------

final communityCheckInProvider = Provider.family<int, String>((ref, mosqueId) {
  final nearbyAsync = ref.watch(nearbyMosquesProvider);

  return nearbyAsync.maybeWhen(
    data: (mosques) {
      // firstWhereOrNull pattern — no exception if the mosque isn't in the list
      final Mosque? mosque = mosques.cast<Mosque?>().firstWhere(
        (m) => m?.id == mosqueId,
        orElse: () => null,
      );
      return mosque?.checkinCountToday ?? 0;
    },
    // Loading or error states: return 0 (Tier 0 rendering is always safe)
    orElse: () => 0,
  );
});

// ---------------------------------------------------------------------------
// mosque3DTierProvider
// Derived provider: maps a raw check-in count to a tier integer (0–3).
// Used by the viewport to decide which nodes to show — keeps tier logic
// out of the widget completely.
// ---------------------------------------------------------------------------

final mosque3DTierProvider = Provider.family<int, String>((ref, mosqueId) {
  final count = ref.watch(communityCheckInProvider(mosqueId));

  if (count >= Mosque3DTiers.tier3) return 3;
  if (count >= Mosque3DTiers.tier2) return 2;
  if (count >= Mosque3DTiers.tier1) return 1;
  return 0;
});
