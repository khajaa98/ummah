// lib/widgets/prayer_tracker_widget.dart
// =============================================================================
// PrayerTrackerWidget — interactive daily prayer circle tracker with streak flame
// and menses pause toggle. Integrates haptics and M3 teal styles.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/prayer_tracker_provider.dart';

class PrayerTrackerWidget extends ConsumerWidget {
  const PrayerTrackerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackerState = ref.watch(prayerTrackerProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Header & Streak count
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.checklist_rtl_rounded, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Daily Tracker',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.local_fire_department_rounded, color: Colors.orange[400], size: 18),
                      const SizedBox(width: 4),
                      Text(
                        '${trackerState.streak} Day Streak',
                        style: textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[300],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // The 5 Prayer Rings
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: trackerState.prayerCompletions.keys.map((prayer) {
                final isCompleted = trackerState.prayerCompletions[prayer]!;
                final isPaused = trackerState.isMensesPaused;

                return Semantics(
                  label: 'Toggle $prayer prayer completion. Status: ${isPaused ? "Paused" : (isCompleted ? "Completed" : "Uncompleted")}',
                  button: !isPaused,
                  child: GestureDetector(
                    onTap: () => ref.read(prayerTrackerProvider.notifier).togglePrayer(prayer),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isPaused 
                            ? colorScheme.errorContainer.withOpacity(0.5)
                            : (isCompleted ? colorScheme.primary : Colors.transparent),
                        border: Border.all(
                          color: isPaused 
                              ? colorScheme.errorContainer 
                              : (isCompleted ? colorScheme.primary : colorScheme.outlineVariant),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: isPaused
                            ? Icon(Icons.nightlight_round, size: 20, color: colorScheme.onErrorContainer)
                            : isCompleted
                                ? Icon(Icons.check_rounded, color: colorScheme.onPrimary, size: 24)
                                : Text(
                                    prayer[0], // First letter (F, D, A, M, I)
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            
            // Menses Pause Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.spa_rounded,
                      size: 16,
                      color: trackerState.isMensesPaused ? colorScheme.error : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Menses Pause (freeze streak)',
                      style: textTheme.bodySmall?.copyWith(
                        color: trackerState.isMensesPaused ? colorScheme.error : colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Semantics(
                  label: 'Toggle menses pause to freeze your prayer streak',
                  child: Switch(
                    value: trackerState.isMensesPaused,
                    onChanged: (_) => ref.read(prayerTrackerProvider.notifier).toggleMensesPause(),
                    activeColor: colorScheme.error,
                    activeTrackColor: colorScheme.errorContainer,
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
