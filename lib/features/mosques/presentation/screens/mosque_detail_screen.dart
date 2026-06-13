// lib/features/mosques/presentation/screens/mosque_detail_screen.dart
// =============================================================================
// MosqueDetailScreen — mosque info, real prayer timings, check-in FAB,
// and the community 3D tier progress card.
//
// Sprint 7 changes:
//   • Hero removed (Card→3D viewport morph was visually broken).
//   • Prayer timings stub replaced with live _PrayerTimingsSection that
//     fetches from /v1/mosques/:id/timings and highlights the next prayer.
//   • Arabic mosque name shown as subtitle when nameAr is present.
//   • Check-In FAB opens a bottom sheet for prayer slot selection.
//   • Favourite star wired to favouriteMosqueProvider.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/mosque_model.dart';
import '../../data/models/prayer_timing.dart';
import '../constants/mosque_3d_nodes.dart';
import '../providers/community_checkin_provider.dart';
import '../providers/favourite_mosque_provider.dart';
import '../providers/prayer_timings_provider.dart';
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
    final isFav    = ref.watch(favouriteMosqueProvider.select((m) => m?.id == mosque.id));

    return Scaffold(
      backgroundColor: scheme.surface,
      floatingActionButton: _CheckInFab(mosque: mosque),
      body: CustomScrollView(
        slivers: [
          // ── App bar — no Hero; simple pinned bar with 3D viewport ────────
          SliverAppBar(
            expandedHeight:   320,
            pinned:           true,
            backgroundColor:  scheme.surface,
            foregroundColor:  scheme.onSurface,
            surfaceTintColor: Colors.transparent,
            actions: [
              // Favourite star
              IconButton(
                icon: Icon(
                  isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: isFav ? scheme.primary : scheme.onSurfaceVariant,
                ),
                tooltip: isFav ? 'Remove from favourites' : 'Set as home mosque',
                onPressed: () {
                  HapticFeedback.lightImpact();
                  if (isFav) {
                    ref.read(favouriteMosqueProvider.notifier).clearFavourite();
                  } else {
                    ref.read(favouriteMosqueProvider.notifier).setFavourite(mosque);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${mosque.name} set as your home mosque'),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Mosque3DViewport(
                mosqueId: mosque.id,
                height:   320,
              ),
            ),
          ),

          // ── Mosque info ──────────────────────────────────────────────────
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mosque.name,
                              style: text.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color:      scheme.onSurface,
                              ),
                            ),
                            if (mosque.nameAr != null && mosque.nameAr!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  mosque.nameAr!,
                                  textDirection: TextDirection.rtl,
                                  style: text.titleSmall?.copyWith(
                                    color:      scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (mosque.madhab != Madhab.unknown)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:        scheme.primaryContainer,
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
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
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

                  // ── Tier upgrade card ──────────────────────────────────
                  _TierUpgradeCard(
                    checkIns: checkIns,
                    tier:     tier,
                    nextGoal: next,
                    scheme:   scheme,
                    text:     text,
                  ),

                  const SizedBox(height: 24),

                  // ── Prayer timings — live data ─────────────────────────
                  _PrayerTimingsSection(mosqueId: mosque.id),

                  // Bottom padding so FAB doesn't overlap last row
                  const SizedBox(height: 96),
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
// Check-In FAB
// ---------------------------------------------------------------------------

class _CheckInFab extends ConsumerWidget {
  const _CheckInFab({required this.mosque});
  final Mosque mosque;

  // Maps current hour to the most likely prayer slot
  static String _currentPrayerSlot() {
    final h = DateTime.now().hour;
    if (h >= 4  && h < 7)  return 'fajr';
    if (h >= 7  && h < 13) return 'dhuhr';
    if (h >= 13 && h < 17) return 'asr';
    if (h >= 17 && h < 20) return 'maghrib';
    return 'isha';
  }

  static const _slotLabels = {
    'fajr':    'Fajr',
    'dhuhr':   'Dhuhr',
    'asr':     'Asr',
    'maghrib': 'Maghrib',
    'isha':    'Isha',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return FloatingActionButton.extended(
      onPressed: () => _showCheckInSheet(context, ref),
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      icon:  const Icon(Icons.how_to_reg_rounded),
      label: const Text('Check In', style: TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Future<void> _showCheckInSheet(BuildContext context, WidgetRef ref) async {
    final scheme    = Theme.of(context).colorScheme;
    final text      = Theme.of(context).textTheme;
    String selected = _currentPrayerSlot();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color:        scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Which prayer?', style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                mosque.name,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),

              // Prayer slot selector
              Wrap(
                spacing: 8,
                children: _slotLabels.entries.map((e) {
                  final isSelected = selected == e.key;
                  return ChoiceChip(
                    label:        Text(e.value),
                    selected:     isSelected,
                    onSelected:   (_) => setState(() => selected = e.key),
                    selectedColor:    scheme.primaryContainer,
                    backgroundColor:  scheme.surfaceContainerLow,
                    labelStyle: TextStyle(
                      color:      isSelected ? scheme.onPrimaryContainer : scheme.onSurface,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon:  const Icon(Icons.how_to_reg_rounded, size: 18),
                  label: const Text('Confirm Check-In'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    textStyle:   text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _doCheckIn(context, ref, selected);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doCheckIn(BuildContext context, WidgetRef ref, String slot) async {
    HapticFeedback.heavyImpact();
    try {
      await ref.read(checkInActionProvider(mosque.id).notifier).checkIn(slot);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Text('JazakAllah Khair — ${_slotLabels[slot]} check-in recorded!'),
              ],
            ),
            behavior:        SnackBarBehavior.floating,
            duration:        const Duration(seconds: 3),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Already checked in for this prayer today.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Prayer Timings Section — live data
// ---------------------------------------------------------------------------

class _PrayerTimingsSection extends ConsumerWidget {
  const _PrayerTimingsSection({required this.mosqueId});
  final String mosqueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme       = Theme.of(context).colorScheme;
    final text         = Theme.of(context).textTheme;
    final timingsAsync = ref.watch(mosqueTimingsProvider(mosqueId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.schedule_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              'Prayer Timings',
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color:      scheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        timingsAsync.when(
          loading: () => _TimingsSkeleton(scheme: scheme),
          error:   (_, __) => _NoTimingsCard(scheme: scheme, text: text),
          data:    (timings) {
            if (timings.isEmpty) return _NoTimingsCard(scheme: scheme, text: text);
            final today = timings.first;
            return _TimingsCard(timing: today, scheme: scheme, text: text);
          },
        ),
      ],
    );
  }
}

class _TimingsCard extends StatelessWidget {
  const _TimingsCard({
    required this.timing,
    required this.scheme,
    required this.text,
  });

  final PrayerTiming timing;
  final ColorScheme  scheme;
  final TextTheme    text;

  @override
  Widget build(BuildContext context) {
    final now  = TimeOfDay.now();
    final rows = timing.dailyPrayers;

    // Determine which prayer slot is "next" (first one after current time)
    String? nextPrayerName;
    for (final p in rows) {
      final t = p.time.toTimeOfDay();
      if (t != null) {
        final pMins = t.hour * 60 + t.minute;
        final nowMins = now.hour * 60 + now.minute;
        if (pMins > nowMins) {
          nextPrayerName = p.name;
          break;
        }
      }
    }

    return Container(
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          ...rows.map((p) {
            final isNext = p.name == nextPrayerName;
            return Container(
              decoration: isNext
                  ? BoxDecoration(
                      color:        scheme.primaryContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    )
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  if (isNext)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.arrow_right_rounded,
                          size: 18, color: scheme.primary),
                    ),
                  Expanded(
                    child: Text(
                      p.name,
                      style: text.bodyMedium?.copyWith(
                        color:      isNext ? scheme.primary : scheme.onSurface,
                        fontWeight: isNext ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    p.time,
                    style: text.bodyMedium?.copyWith(
                      color:      isNext ? scheme.primary : scheme.onSurfaceVariant,
                      fontWeight: isNext ? FontWeight.w700 : FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            );
          }),
          // Verification badge
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Icon(Icons.verified_rounded, size: 13, color: scheme.secondary),
                const SizedBox(width: 4),
                Text(
                  'Verified timings · ${timing.calcMethod.displayLabel}',
                  style: text.labelSmall?.copyWith(
                    color:     scheme.secondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimingsSkeleton extends StatelessWidget {
  const _TimingsSkeleton({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        5,
        (i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color:        scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 40),
              Container(
                width: 48, height: 14,
                decoration: BoxDecoration(
                  color:        scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoTimingsCard extends StatelessWidget {
  const _NoTimingsCard({required this.scheme, required this.text});
  final ColorScheme scheme;
  final TextTheme   text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.pending_outlined, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Verified timings not yet available for this mosque.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
    final tierLabel = Mosque3DTiers.label(checkIns);
    final progress  = Mosque3DTiers.progressToNext(checkIns);
    final isMaxed   = nextGoal == null;

    final IconData tierIcon = switch (tier) {
      0 => Icons.home_work_outlined,
      1 => Icons.mosque_outlined,
      2 => Icons.mosque_rounded,
      _ => Icons.auto_awesome_rounded,
    };

    return Container(
      padding: const EdgeInsets.all(16),
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
                ? 'This mosque has reached Grand status!'
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
                valueColor:      AlwaysStoppedAnimation<Color>(scheme.primary),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${nextGoal! - checkIns} more check-ins to unlock '
              '${_nextUnlockLabel(tier)}',
              style: text.labelSmall?.copyWith(
                color:     scheme.onSurfaceVariant,
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
