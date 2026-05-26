// lib/features/mosques/presentation/widgets/mosque_card.dart
// =============================================================================
// UMM-305 (upgraded): MosqueCard — reusable list item widget with spatial Hero
// expand animations and native tactile selection click haptics.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/mosque_model.dart';
import '../providers/community_checkin_provider.dart';
import '../screens/mosque_detail_screen.dart';
import '../constants/mosque_3d_nodes.dart';

class MosqueCard extends ConsumerWidget {
  final Mosque mosque;
  final VoidCallback? onTap;

  const MosqueCard({
    super.key,
    required this.mosque,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final count = mosque.checkinCountToday;
    final tierLabel = Mosque3DTiers.label(count);

    return Hero(
      tag: 'mosque_viewport_hero_${mosque.id}',
      // flightShuttleBuilder prevents text scaling and visual jitters during transit
      flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Material(
              type: MaterialType.transparency,
              child: toHeroContext.widget,
            );
          },
        );
      },
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.8), width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            // Trigger native tactile selection click synchronously with tap
            HapticFeedback.selectionClick();
            
            if (onTap != null) {
              onTap!();
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MosqueDetailScreen(mosque: mosque),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        mosque.name,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _DistanceBadge(distance: mosque.formattedDistance),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MadhabChip(madhab: mosque.madhab),
                    const SizedBox(width: 8),
                    if (mosque.hasVerifiedTimings) _VerifiedBadge(),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _CheckinCount(count: count),
                    Text(
                      tierLabel,
                      style: textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DistanceBadge extends StatelessWidget {
  final String distance;
  const _DistanceBadge({required this.distance});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        distance,
        style: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _MadhabChip extends StatelessWidget {
  final Madhab madhab;
  const _MadhabChip({required this.madhab});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (bg, fg) = switch (madhab) {
      Madhab.hanafi => (colorScheme.secondaryContainer, colorScheme.onSecondaryContainer),
      Madhab.shafii => (colorScheme.tertiaryContainer, colorScheme.onTertiaryContainer),
      Madhab.maliki => (colorScheme.errorContainer, colorScheme.onErrorContainer),
      Madhab.hanbali => (colorScheme.primaryContainer, colorScheme.onPrimaryContainer),
      Madhab.unknown => (colorScheme.surfaceContainerHighest, colorScheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        madhab.displayLabel.toUpperCase(),
        style: textTheme.labelSmall?.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.teal.withOpacity(0.3), width: 0.5),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, color: Colors.teal, size: 12),
          SizedBox(width: 4),
          Text(
            'VERIFIED',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckinCount extends StatelessWidget {
  final int count;
  const _CheckinCount({required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(Icons.people_alt_rounded, size: 14, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$count checked in today',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
