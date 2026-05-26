// lib/features/mosques/presentation/widgets/mosque_3d_viewport.dart
// =============================================================================
// Sprint 5 — Mosque3DViewport
//
// A reactive Flutter widget that renders a .glb mosque model whose
// architectural complexity scales with community check-in data.
//
// Architecture:
//   communityCheckInProvider(mosqueId)   → int (check-in count)
//   mosque3DTierProvider(mosqueId)       → int (0–3)
//         │
//         ▼
//   Flutter3DController._updateNodes()  → toggle node visibility in .glb
//         │
//         ▼
//   Flutter3DViewer widget              → renders the scene via Filament/SceneKit
//
// pubspec.yaml additions required:
//   flutter_3d_controller: ^1.5.1
//
// assets/models/mosque.glb — artist-deliverable (see mosque_3d_nodes.dart)
// Placeholder: any free CC0 .glb from Sketchfab works for development.
//
// Note on flutter_3d_controller API:
//   - setObjectVisibility(nodeName, visible) toggles a named node.
//   - Unknown node names are silently ignored (no throw) — placeholder .glb
//     assets without named nodes work fine for layout testing.
//   - playAnimation(animationName) would drive entrance animations;
//     deferred to Sprint 6 when the final .glb asset is delivered.
//
// Battery optimisation:
//   - RepaintBoundary isolates the 3D widget from the rest of the tree.
//   - Flutter3DViewer has built-in idle detection that drops to 1 FPS
//     when the model has not moved for 2 seconds.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/mosque_3d_nodes.dart';
import '../providers/community_checkin_provider.dart';

class Mosque3DViewport extends ConsumerStatefulWidget {
  const Mosque3DViewport({
    super.key,
    required this.mosqueId,
    this.height = 300,
  });

  /// The mosque UUID — used to look up the check-in count from the provider.
  final String mosqueId;

  /// Height of the viewport in logical pixels. Defaults to 300.
  final double height;

  @override
  ConsumerState<Mosque3DViewport> createState() => _Mosque3DViewportState();
}

class _Mosque3DViewportState extends ConsumerState<Mosque3DViewport>
    with SingleTickerProviderStateMixin {

  final Flutter3DController _controller = Flutter3DController();

  // Track the last rendered tier so we only call setObjectVisibility
  // when the tier actually changes, not on every widget rebuild.
  int _renderedTier = -1;

  // Animation controller for the tier-upgrade flash effect
  late final AnimationController _flashController;
  late final Animation<double>    _flashAnimation;

  @override
  void initState() {
    super.initState();

    _flashController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 800),
    );
    _flashAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flashController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _flashController.dispose();
    // Flutter3DController does not currently require explicit disposal,
    // but if a future version adds it, do so here.
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Node update logic — called whenever the tier changes
  // ---------------------------------------------------------------------------

  /// Applies the correct node visibility for a given tier.
  /// All lower-tier nodes are always shown (tiers are cumulative upgrades).
  ///
  /// Tier 0: foundation + main dome + entrance (always visible)
  /// Tier 1: + minarets
  /// Tier 2: + grand dome + lanterns
  /// Tier 3: + courtyard + fountain + illumination ring
  void _applyTier(int tier) {
    // Tier 0 nodes are always on — ensure the controller knows this
    _controller.setObjectVisibility(
      objectName: Mosque3DNodes.foundation, visible: true);
    _controller.setObjectVisibility(
      objectName: Mosque3DNodes.mainDome, visible: true);
    _controller.setObjectVisibility(
      objectName: Mosque3DNodes.entranceArch, visible: true);

    // Tier 1
    final bool t1 = tier >= 1;
    _controller.setObjectVisibility(
      objectName: Mosque3DNodes.minaretLeft, visible: t1);
    _controller.setObjectVisibility(
      objectName: Mosque3DNodes.minaretRight, visible: t1);

    // Tier 2
    final bool t2 = tier >= 2;
    _controller.setObjectVisibility(
      objectName: Mosque3DNodes.grandDome, visible: t2);
    _controller.setObjectVisibility(
      objectName: Mosque3DNodes.lanterns, visible: t2);

    // Tier 3
    final bool t3 = tier >= 3;
    _controller.setObjectVisibility(
      objectName: Mosque3DNodes.courtyard, visible: t3);
    _controller.setObjectVisibility(
      objectName: Mosque3DNodes.fountain, visible: t3);
    _controller.setObjectVisibility(
      objectName: Mosque3DNodes.illumination, visible: t3);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme   = Theme.of(context).colorScheme;
    final checkIns = ref.watch(communityCheckInProvider(widget.mosqueId));
    final tier     = ref.watch(mosque3DTierProvider(widget.mosqueId));

    // Trigger node update only when tier changes — not on every rebuild
    if (tier != _renderedTier) {
      _renderedTier = tier;
      // Schedule after frame so the controller is mounted
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _applyTier(tier);
          // Play the upgrade flash if the tier just went up (not on first render)
          if (tier > 0) _flashController.forward(from: 0);
        }
      });
    }

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // ── 3D viewport ────────────────────────────────────────────────
          // RepaintBoundary prevents the rest of the screen from repainting
          // when the 3D scene redraws (e.g. auto-rotation).
          RepaintBoundary(
            child: Flutter3DViewer(
              src:        'assets/models/mosque.glb',
              controller: _controller,
              // Disable the built-in loading indicator — we show our own
              progressBarColor: Colors.transparent,
              onLoad: () {
                // Model is loaded — now safe to set initial node visibility
                _applyTier(tier);
                _renderedTier = tier;
              },
              onProgress: (_) {},
              onError: () => debugPrint('[Mosque3D] Failed to load mosque.glb'),
            ),
          ),

          // ── Upgrade flash overlay ─────────────────────────────────────
          AnimatedBuilder(
            animation: _flashAnimation,
            builder: (context, _) {
              if (_flashAnimation.value == 0) return const SizedBox.shrink();
              return Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: (1 - _flashAnimation.value) * 0.4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [scheme.primary, Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // ── Tier label overlay (bottom-left) ──────────────────────────
          Positioned(
            bottom: 12,
            left:   16,
            child: _TierBadge(checkIns: checkIns, scheme: scheme),
          ),

          // ── Progress bar to next tier (bottom) ────────────────────────
          Positioned(
            bottom: 0,
            left:   0,
            right:  0,
            child: _TierProgressBar(checkIns: checkIns, scheme: scheme),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets
// ---------------------------------------------------------------------------

/// Shows the current tier name and the check-in count.
class _TierBadge extends StatelessWidget {
  const _TierBadge({required this.checkIns, required this.scheme});

  final int         checkIns;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final label = Mosque3DTiers.label(checkIns);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerHighest.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mosque_rounded, size: 14, color: scheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color:      scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '· $checkIns check-ins',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin progress bar at the bottom showing progress to the next tier unlock.
class _TierProgressBar extends StatelessWidget {
  const _TierProgressBar({required this.checkIns, required this.scheme});

  final int         checkIns;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final progress = Mosque3DTiers.progressToNext(checkIns);
    final next     = Mosque3DTiers.nextThreshold(checkIns);

    // Fully upgraded — no progress bar needed
    if (next == null) return const SizedBox.shrink();

    return Semantics(
      label: '${(progress * 100).round()}% to next upgrade at $next check-ins',
      child: Tooltip(
        message: '$checkIns / $next check-ins to next upgrade',
        child:   LinearProgressIndicator(
          value:            progress,
          backgroundColor:  scheme.surfaceContainerHighest.withOpacity(0.5),
          valueColor:       AlwaysStoppedAnimation<Color>(scheme.primary),
          minHeight:        3,
        ),
      ),
    );
  }
}
