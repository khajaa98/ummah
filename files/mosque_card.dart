// lib/features/mosques/presentation/widgets/mosque_card.dart
// =============================================================================
// UMM-305 (partial): MosqueCard — reusable list item widget.
//
// Displays a single Mosque entity in the NearbyMosquesScreen ListView.
// All colours are sourced from ThemeData.colorScheme — zero hardcoded literals.
//
// Layout:
//   ┌──────────────────────────────────────────────────────┐
//   │  🕌  Masjid Al-Falah                    2.1 km away  │
//   │      Banjara Hills · Hyderabad                       │
//   │      [Hanafi]    ✅ Verified Timings   👥 14 today   │
//   └──────────────────────────────────────────────────────┘
//
// Accessibility:
//   The entire card is wrapped in a Semantics widget with a merged label
//   so screen readers announce the mosque name, distance, and city together.
// =============================================================================

import 'package:flutter/material.dart';

import '../../data/models/mosque_model.dart';

class MosqueCard extends StatelessWidget {
  const MosqueCard({
    super.key,
    required this.mosque,
    this.onTap,
  });

  final Mosque    mosque;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Semantics(
      label: '${mosque.name}, ${mosque.formattedDistance} away, ${mosque.city}',
      button: onTap != null,
      child: Card(
        margin:       const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        elevation:    0,
        color:        scheme.surfaceContainerLow,
        shape:        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant, width: 0.8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap:        onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Row 1: name + distance ────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Mosque icon
                    Container(
                      width:  40,
                      height: 40,
                      decoration: BoxDecoration(
                        color:        scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.mosque_rounded,
                        color: scheme.onPrimaryContainer,
                        size:  22,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Name + location subtitle
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mosque.name,
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color:      scheme.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          _LocationLine(mosque: mosque, scheme: scheme, text: text),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Distance badge
                    _DistanceBadge(mosque: mosque, scheme: scheme, text: text),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Row 2: madhab chip + verified badge + checkin count ───
                Wrap(
                  spacing:   8,
                  runSpacing: 6,
                  children: [
                    if (mosque.madhab != Madhab.unknown)
                      _MadhabChip(madhab: mosque.madhab, scheme: scheme),
                    if (mosque.hasVerifiedTimings)
                      _VerifiedBadge(scheme: scheme),
                    if (mosque.checkinCountToday > 0)
                      _CheckinCount(count: mosque.checkinCountToday, scheme: scheme),
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

// ---------------------------------------------------------------------------
// Private sub-widgets — each focused on a single visual element
// ---------------------------------------------------------------------------

class _LocationLine extends StatelessWidget {
  const _LocationLine({
    required this.mosque,
    required this.scheme,
    required this.text,
  });

  final Mosque          mosque;
  final ColorScheme     scheme;
  final TextTheme       text;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (mosque.addressLine != null && mosque.addressLine!.isNotEmpty) {
      parts.add(mosque.addressLine!);
    }
    parts.add(mosque.city);

    return Row(
      children: [
        Icon(Icons.location_on_outlined, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            parts.join(' · '),
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _DistanceBadge extends StatelessWidget {
  const _DistanceBadge({
    required this.mosque,
    required this.scheme,
    required this.text,
  });

  final Mosque      mosque;
  final ColorScheme scheme;
  final TextTheme   text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color:        scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        mosque.formattedDistance,
        style: text.labelSmall?.copyWith(
          color:      scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MadhabChip extends StatelessWidget {
  const _MadhabChip({required this.madhab, required this.scheme});

  final Madhab      madhab;
  final ColorScheme scheme;

  /// Each madhab gets a semantically distinct colour derived from the
  /// MaterialYou tonal palette so they remain legible in light and dark mode.
  Color _chipColor() => switch (madhab) {
    Madhab.hanafi  => scheme.primaryContainer,
    Madhab.shafii  => scheme.tertiaryContainer,
    Madhab.maliki  => scheme.secondaryContainer,
    Madhab.hanbali => scheme.errorContainer,
    Madhab.unknown => scheme.surfaceContainerHighest,
  };

  Color _textColor() => switch (madhab) {
    Madhab.hanafi  => scheme.onPrimaryContainer,
    Madhab.shafii  => scheme.onTertiaryContainer,
    Madhab.maliki  => scheme.onSecondaryContainer,
    Madhab.hanbali => scheme.onErrorContainer,
    Madhab.unknown => scheme.onSurfaceVariant,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        _chipColor(),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        madhab.displayLabel,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color:      _textColor(),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  const _VerifiedBadge({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_rounded, size: 14, color: scheme.primary),
        const SizedBox(width: 3),
        Text(
          'Verified Timings',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color:      scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CheckinCount extends StatelessWidget {
  const _CheckinCount({required this.count, required this.scheme});
  final int count;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.people_outline_rounded, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          '$count ${count == 1 ? "person" : "people"} today',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
