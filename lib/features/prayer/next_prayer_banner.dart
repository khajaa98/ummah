// lib/features/prayer/next_prayer_banner.dart
// =============================================================================
// NextPrayerBanner — live countdown to the next prayer at the user's favourite
// mosque.
//
// Drives:
//   • A glance-able banner above the mosque list / hero card
//   • Visual urgency cue when prayer is < 15 min away (tertiaryContainer tint)
//
// Data sources:
//   • favouriteMosqueProvider — which mosque to show (null = onboarding CTA)
//   • mosqueTimingsProvider(mosqueId) — verified HH:MM strings
//
// If no favourite is set OR no verified timings exist, the banner collapses
// into a soft "Set your home mosque" call-to-action so the UI never goes blank.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mosques/data/models/mosque_model.dart';
import '../mosques/data/models/prayer_timing.dart';
import '../mosques/presentation/providers/favourite_mosque_provider.dart';
import '../mosques/presentation/providers/prayer_timings_provider.dart';

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

class NextPrayerBanner extends ConsumerWidget {
  const NextPrayerBanner({super.key, this.onTapSetMosque});

  /// Called when the user taps the "Set home mosque" CTA (no favourite yet).
  final VoidCallback? onTapSetMosque;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favourite = ref.watch(favouriteMosqueProvider);

    if (favourite == null) {
      return _SetMosqueCard(onTap: onTapSetMosque);
    }

    final timingsAsync = ref.watch(mosqueTimingsProvider(favourite.id));

    return timingsAsync.when(
      loading: () => const _BannerSkeleton(),
      error:   (_, __) => _SetMosqueCard(
        onTap:    onTapSetMosque,
        message:  'Could not load timings for ${favourite.name}',
      ),
      data: (timings) {
        if (timings.isEmpty) {
          return _SetMosqueCard(
            onTap:   onTapSetMosque,
            message: '${favourite.name} hasn\'t verified its timings yet.',
          );
        }
        return _CountdownBanner(
          mosque: favourite,
          timing: timings.first,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Countdown banner — ticks every second
// ---------------------------------------------------------------------------

class _CountdownBanner extends StatefulWidget {
  const _CountdownBanner({required this.mosque, required this.timing});

  final Mosque       mosque;
  final PrayerTiming timing;

  @override
  State<_CountdownBanner> createState() => _CountdownBannerState();
}

class _CountdownBannerState extends State<_CountdownBanner> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Returns (name, time-string, dateTime, durationUntil) for the next prayer.
  ({String name, String timeStr, DateTime at, Duration remaining})?
      _nextPrayer() {
    final today = DateTime(_now.year, _now.month, _now.day);
    final pairs = widget.timing.dailyPrayers
        // Skip "Sunrise" — informational, not a prayer slot
        .where((p) => p.name != 'Sunrise')
        .toList();

    for (final p in pairs) {
      final tod = p.time.toTimeOfDay();
      if (tod == null) continue;
      final at = today.add(Duration(hours: tod.hour, minutes: tod.minute));
      if (at.isAfter(_now)) {
        return (
          name:      p.name,
          timeStr:   p.time,
          at:        at,
          remaining: at.difference(_now),
        );
      }
    }
    // All prayers passed today — show tomorrow's Fajr.
    final fajrTod = widget.timing.fajr.toTimeOfDay();
    if (fajrTod == null) return null;
    final tomorrowFajr = today
        .add(const Duration(days: 1))
        .add(Duration(hours: fajrTod.hour, minutes: fajrTod.minute));
    return (
      name:      'Fajr',
      timeStr:   widget.timing.fajr,
      at:        tomorrowFajr,
      remaining: tomorrowFajr.difference(_now),
    );
  }

  String _formatRemaining(Duration d) {
    if (d.inHours >= 1) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    final next = _nextPrayer();
    if (next == null) return const SizedBox.shrink();

    // Urgency tint when < 15 minutes away
    final isImminent = next.remaining.inMinutes < 15;
    final bg = isImminent
        ? scheme.tertiaryContainer
        : scheme.primaryContainer;
    final fg = isImminent
        ? scheme.onTertiaryContainer
        : scheme.onPrimaryContainer;

    return Container(
      margin:  const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Leading prayer-time pill
          Container(
            width:  56,
            height: 56,
            decoration: BoxDecoration(
              color:        fg.withValues(alpha: 0.12),
              shape:        BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.access_time_rounded, color: fg, size: 28),
          ),

          const SizedBox(width: 14),

          // Body
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize:       MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      next.name,
                      style: text.titleMedium?.copyWith(
                        color:      fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'at ${next.timeStr}',
                      style: text.bodyMedium?.copyWith(
                        color: fg.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'in ${_formatRemaining(next.remaining)} · ${widget.mosque.name}',
                  style: text.bodySmall?.copyWith(
                    color: fg.withValues(alpha: 0.85),
                  ),
                  maxLines:  1,
                  overflow:  TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// "Set home mosque" CTA — shown when no favourite is set
// ---------------------------------------------------------------------------

class _SetMosqueCard extends StatelessWidget {
  const _SetMosqueCard({this.onTap, this.message});

  final VoidCallback? onTap;
  final String?       message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: scheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap:        onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width:  56,
                  height: 56,
                  decoration: BoxDecoration(
                    color:  scheme.primaryContainer,
                    shape:  BoxShape.circle,
                  ),
                  child: Icon(Icons.star_outline_rounded,
                      color: scheme.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set your home mosque',
                        style: text.titleMedium?.copyWith(
                          color:      scheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message ??
                            'Tap the star on any mosque to get a live countdown to the next prayer.',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton — shown while timings load
// ---------------------------------------------------------------------------

class _BannerSkeleton extends StatelessWidget {
  const _BannerSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      height: 84,
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: SizedBox(
          width:  20,
          height: 20,
          child:  CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
        ),
      ),
    );
  }
}
