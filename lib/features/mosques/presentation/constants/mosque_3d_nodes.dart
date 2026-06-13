// lib/features/mosques/presentation/constants/mosque_3d_nodes.dart
// =============================================================================
// Sprint 5 — 3D Architecture Contract
//
// This file is the binding contract between the Flutter engineering team and
// the 3D artist. When the artist builds the mosque .glb file in Blender (or
// similar), they MUST name their mesh nodes exactly as defined here.
//
// Node naming convention: node_{element}_{qualifier}
//
// Upgrade tier thresholds:
//   Tier 0 (always visible)  — foundation, main dome, entrance arch
//   Tier 1 (≥ 50 check-ins)  — minarets (left + right)
//   Tier 2 (≥ 100 check-ins) — grand dome detail, lanterns
//   Tier 3 (≥ 250 check-ins) — courtyard, fountains, illumination ring
//
// Placeholder asset:
//   During development, drop ANY free .glb into assets/models/mosque.glb.
//   A low-poly placeholder from Sketchfab (CC0 license) works perfectly.
//   The controller will load it; node visibility calls are no-ops on
//   unknown node names — they don't throw, they silently skip.
//   Swap the file when the final asset is delivered.
//
// Recommended free placeholder: https://sketchfab.com/3d-models?q=mosque&license=4
// =============================================================================

abstract final class Mosque3DNodes {
  Mosque3DNodes._(); // prevent instantiation

  // ── Tier 0: Always visible ──────────────────────────────────────────────
  static const String foundation     = 'node_foundation';
  static const String mainDome       = 'node_dome_main';
  static const String entranceArch   = 'node_arch_entrance';

  // ── Tier 1: ≥ 50 check-ins ─────────────────────────────────────────────
  static const String minaretLeft    = 'node_minaret_left';
  static const String minaretRight   = 'node_minaret_right';

  // ── Tier 2: ≥ 100 check-ins ────────────────────────────────────────────
  static const String grandDome      = 'node_dome_grand';
  static const String lanterns       = 'node_lanterns';

  // ── Tier 3: ≥ 250 check-ins ────────────────────────────────────────────
  static const String courtyard      = 'node_courtyard';
  static const String fountain       = 'node_fountain';
  static const String illumination   = 'node_illumination_ring';
}

/// Threshold constants — single source of truth for both the widget
/// and any future admin dashboard that wants to display progress bars.
abstract final class Mosque3DTiers {
  Mosque3DTiers._();

  static const int tier1 = 50;   // minarets unlock
  static const int tier2 = 100;  // grand dome + lanterns unlock
  static const int tier3 = 250;  // full courtyard unlocks

  /// Human-readable label for the current tier.
  static String label(int checkIns) {
    if (checkIns >= tier3) return 'Grand Mosque';
    if (checkIns >= tier2) return 'Masjid Jami\'';
    if (checkIns >= tier1) return 'Masjid';
    return 'Musalla';
  }

  /// Progress toward the next tier, 0.0–1.0.
  static double progressToNext(int checkIns) {
    if (checkIns >= tier3) return 1.0;
    if (checkIns >= tier2) return (checkIns - tier2) / (tier3 - tier2);
    if (checkIns >= tier1) return (checkIns - tier1) / (tier2 - tier1);
    return checkIns / tier1;
  }

  /// The check-in target for the next unlock, or null if fully upgraded.
  static int? nextThreshold(int checkIns) {
    if (checkIns < tier1) return tier1;
    if (checkIns < tier2) return tier2;
    if (checkIns < tier3) return tier3;
    return null;
  }
}
