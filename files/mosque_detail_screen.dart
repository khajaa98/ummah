// lib/features/mosques/presentation/screens/mosque_detail_screen.dart
// =============================================================================
// Sprint 5 — MosqueDetailScreen
//
// Displays:
//   • Mosque3DViewport (top) — reactive 3D model driven by check-in tier
//   • Mosque metadata (name, distance, address, madhab)
//   • Tier upgrade progress card
//   • Prayer timings stub (Sprint 6)
//
// The 3D viewport and the rest of the UI share the same scaffold via a
// CustomScrollView with a SliverToBoxAdapter — this lets the 3D header
// scroll with the content naturally without fighting NestedScrollView.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/mosque_model.dart';
import '../constants/mosque_3d_nodes.dart';
import '../providers/community_checkin_provider.dart';
import '../widgets/mosque_3d_viewport.dart';

class MosqueDetailScreen extends ConsumerWidget {
  const MosqueDetailScreen({super.key, required this.mosque});

  final Mosque mosque;

  static const routeName = '/mosques/detail';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme   = Theme.of(context).colorScheme;
    final text     = Theme.of(context).textTheme;
    final checkIns = ref.watch(communityCheckInProvider(mosque.id));
    final tier     = ref.watch(mosque3DTierProvider(mosque.id));
    final next     = Mosque3DTiers.nextThreshold(checkIns);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: CustomScrollView(
        slivers: [
          // ── App bar with 3D viewport as the flexible space ─────────────
          SliverAppBar(
            expandedHeight: 320,
            pinned:         true,
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
            surfaceTintColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              // The 3D viewport fills the collapsed header
              background: Mosque3DViewport(
                mosqueId: mosque.id,
                height:   320,
              ),
            ),
          ),

          // ── Mosque info ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + madhab chip
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          mosque.name,
                          style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color:      scheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (mosque.madhab != Madhab.unknown)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            mosque.madhab.displayLabel,
                            style: text.labelSmall?.copyWith(
                              color:      scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Address + distance
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 15, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          [
                            if (mosque.addressLine != null) mosque.addressLine!,
                            mosque.city,
                          ].join(' · '),
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        mosque.formattedDistance,
                        style: text.labelSmall?.copyWith(
                          color:      scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Tier upgrade card ────────────────────────────────
                  _TierUpgradeCard(
                    checkIns:  checkIns,
                    tier:      tier,
                    nextGoal:  next,
                    scheme:    scheme,
                    text:      text,
                  ),

                  const SizedBox(height: 24),

                  // ── Prayer timings stub ──────────────────────────────
                  _PrayerTimingsStub(scheme: scheme, text: text),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tier upgrade card
// ---------------------------------------------------------------------------

class _TierUpgradeCard extends StatelessWidget {
  const _TierUpgradeCard({
    required this.checkIns,
    required this.tier,
    required this.nextGoal,
    required this.scheme,
    required this.text,
  });

  final int         checkIns;
  final int         tier;
  final int?        nextGoal;
  final ColorScheme scheme;
  final TextTheme   text;

  @override
  Widget build(BuildContext context) {
    final tierLabel    = Mosque3DTiers.label(checkIns);
    final progress     = Mosque3DTiers.progressToNext(checkIns);
    final isMaxed      = nextGoal == null;

    // Icon per tier
    final IconData tierIcon = switch (tier) {
      0 => Icons.home_work_outlined,
      1 => Icons.mosque_outlined,
      2 => Icons.mosque_rounded,
      _ => Icons.auto_awesome_rounded,
    };

    return Container(
      padding:    const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(tierIcon, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Community Level: $tierLabel',
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color:      scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isMaxed
                ? 'This mosque has reached Grand status! 🌟'
                : '$checkIns / $nextGoal community check-ins',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (!isMaxed) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:           progress,
                minHeight:       6,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${nextGoal! - checkIns} more check-ins to unlock '
              '${_nextUnlockLabel(tier)}',
              style: text.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _nextUnlockLabel(int currentTier) => switch (currentTier) {
    0 => 'minarets',
    1 => 'grand dome & lanterns',
    2 => 'the full courtyard',
    _ => 'next upgrade',
  };
}

// ---------------------------------------------------------------------------
// Prayer timings stub
// ---------------------------------------------------------------------------

class _PrayerTimingsStub extends StatelessWidget {
  const _PrayerTimingsStub({required this.scheme, required this.text});

  final ColorScheme scheme;
  final TextTheme   text;

  static const _prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Prayer Timings',
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color:      scheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        // Skeleton placeholders — replaced by real data in Sprint 6
        ..._prayers.map((name) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Text(name,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurface)),
              ),
              Container(
                width:  56,
                height: 16,
                decoration: BoxDecoration(
                  color:        scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        )),
        const SizedBox(height: 8),
        Text(
          'Verified timings arriving in Sprint 6.',
          style: text.bodySmall?.copyWith(
              color:     scheme.onSurfaceVariant,
              fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}
