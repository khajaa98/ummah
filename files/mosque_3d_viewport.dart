// lib/features/mosques/presentation/widgets/mosque_3d_viewport.dart
// =============================================================================
// Mosque3DViewport — scale-based GLB loader with m3 teal upgrade flash overlays
// and a double-buffered custom pulsating shimmer skeleton loader.
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
    this.height = 320,
  });

  final String mosqueId;
  final double height;

  @override
  ConsumerState<Mosque3DViewport> createState() => _Mosque3DViewportState();
}

class _Mosque3DViewportState extends ConsumerState<Mosque3DViewport>
    with TickerProviderStateMixin {

  final Flutter3DController _controller = Flutter3DController();

  int _renderedTier = -1;
  bool _isLoading = true;

  // Controllers for flash and shimmer effects
  late final AnimationController _flashController;
  late final Animation<double>    _flashAnimation;

  late final AnimationController _shimmerController;
  late Animation<Color?>         _shimmerAnimation;

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

    _shimmerController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scheme = Theme.of(context).colorScheme;

    _shimmerAnimation = ColorTween(
      begin: scheme.surfaceContainerHigh,
      end: scheme.surfaceContainerHighest,
    ).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flashController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _applyTier(int tier) {
    if (_isLoading) return; // Prevent FFI objects from executing visibility too early

    _controller.setObjectVisibility(objectName: Mosque3DNodes.foundation, visible: true);
    _controller.setObjectVisibility(objectName: Mosque3DNodes.mainDome, visible: true);
    _controller.setObjectVisibility(objectName: Mosque3DNodes.entranceArch, visible: true);

    _controller.setObjectVisibility(objectName: Mosque3DNodes.minaretLeft, visible: tier >= 1);
    _controller.setObjectVisibility(objectName: Mosque3DNodes.minaretRight, visible: tier >= 1);
    _controller.setObjectVisibility(objectName: Mosque3DNodes.grandDome, visible: tier >= 2);
    _controller.setObjectVisibility(objectName: Mosque3DNodes.lanterns, visible: tier >= 2);
    _controller.setObjectVisibility(objectName: Mosque3DNodes.courtyard, visible: tier >= 3);
    _controller.setObjectVisibility(objectName: Mosque3DNodes.fountain, visible: tier >= 3);
    _controller.setObjectVisibility(objectName: Mosque3DNodes.illumination, visible: tier >= 3);
  }

  @override
  Widget build(BuildContext context) {
    final scheme   = Theme.of(context).colorScheme;
    final checkIns = ref.watch(communityCheckInProvider(widget.mosqueId));
    final tier     = ref.watch(mosque3DTierProvider(widget.mosqueId));

    if (!_isLoading && tier != _renderedTier) {
      _renderedTier = tier;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _applyTier(tier);
          if (tier > 0) _flashController.forward(from: 0);
        }
      });
    }

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // ── 3D Viewport engine ──────────────────────────────────────────
          RepaintBoundary(
            child: Flutter3DViewer(
              src:        'assets/models/mosque.glb',
              controller: _controller,
              progressBarColor: Colors.transparent, // Disable standard loader bar
              onLoad: () {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                  _applyTier(tier);
                  _renderedTier = tier;
                }
              },
              onProgress: (_) {},
              onError: () => debugPrint('[Mosque3D] Failed to load mosque.glb'),
            ),
          ),

          // ── Upgrade flash overlay ──────────────────────────────────────
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

          // ── Metadata Overlays ──────────────────────────────────────────
          if (!_isLoading) ...[
            Positioned(
              bottom: 12,
              left:   16,
              child: _TierBadge(checkIns: checkIns, scheme: scheme),
            ),
            Positioned(
              bottom: 0,
              left:   0,
              right:  0,
              child: _TierProgressBar(checkIns: checkIns, scheme: scheme),
            ),
          ],

          // ── Double-buffered pulsating skeleton shimmer ──────────────────
          if (_isLoading)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _shimmerAnimation,
                builder: (context, _) {
                  return Container(
                    color: _shimmerAnimation.value,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.blur_circular_rounded,
                            size: 40,
                            color: scheme.onSurfaceVariant.withOpacity(0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Loading Architectural Workspace...',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant.withOpacity(0.5),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

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

class _TierProgressBar extends StatelessWidget {
  const _TierProgressBar({required this.checkIns, required this.scheme});

  final int         checkIns;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final progress = Mosque3DTiers.progressToNext(checkIns);
    final next     = Mosque3DTiers.nextThreshold(checkIns);

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
