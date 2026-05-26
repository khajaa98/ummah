// lib/providers/prayer_tracker_provider.dart
// =============================================================================
// PrayerTrackerNotifier — handles prayer completion, menses pauses, haptics,
// and date-based streak logic. Persists state using FlutterSecureStorage.
// =============================================================================

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/prayer_tracker_state.dart';
import '../services/auth/token_service.dart'; // Reuses flutterSecureStorageProvider

final prayerTrackerProvider = StateNotifierProvider<PrayerTrackerNotifier, PrayerTrackerState>((ref) {
  return PrayerTrackerNotifier(ref.read(flutterSecureStorageProvider));
});

class PrayerTrackerNotifier extends StateNotifier<PrayerTrackerState> {
  final FlutterSecureStorage _storage;
  static const _key = 'prayer_tracker_data';

  PrayerTrackerNotifier(this._storage) : super(PrayerTrackerState.initial()) {
    _loadAndCheckDate();
  }

  Future<void> _loadAndCheckDate() async {
    final data = await _storage.read(key: _key);
    final today = DateTime.now().toIso8601String().split('T')[0];
    
    if (data != null) {
      var loadedState = PrayerTrackerState.fromJson(jsonDecode(data));

      // Handle Date Roll
      if (loadedState.lastDate != today) {
        final allCompleted = loadedState.prayerCompletions.values.every((v) => v == true);
        
        int newStreak = loadedState.streak;
        if (allCompleted || loadedState.isMensesPaused) {
          // Increment if yesterday was fully completed and not paused.
          // Otherwise, preserve the streak if menses paused was enabled.
          newStreak += (loadedState.lastDate == _getYesterdayDate() && !loadedState.isMensesPaused) ? 1 : 0;
        } else {
          // Reset streak if missed and not paused
          newStreak = 0;
        }

        loadedState = loadedState.copyWith(
          prayerCompletions: {
            'Fajr': false,
            'Dhuhr': false,
            'Asr': false,
            'Maghrib': false,
            'Isha': false,
          },
          streak: newStreak,
          lastDate: today,
        );
      }
      this.state = loadedState;
    } else {
      // Fresh install or first-time setup
      this.state = PrayerTrackerState.initial().copyWith(lastDate: today);
    }
    _saveState();
  }

  String _getYesterdayDate() {
    return DateTime.now().subtract(const Duration(days: 1)).toIso8601String().split('T')[0];
  }

  Future<void> _saveState() async {
    await _storage.write(key: _key, value: jsonEncode(state.toJson()));
  }

  void togglePrayer(String prayer) {
    if (state.isMensesPaused) return; // Locked during menses pause

    HapticFeedback.lightImpact();
    
    final newCompletions = Map<String, bool>.from(state.prayerCompletions);
    final wasCompleted = newCompletions[prayer] ?? false;
    newCompletions[prayer] = !wasCompleted;
    
    // Check if they just completed the 5th prayer
    if (newCompletions.values.every((v) => v == true)) {
      HapticFeedback.heavyImpact(); // Big visceral reward
    }

    state = state.copyWith(prayerCompletions: newCompletions);
    _saveState();
  }

  void toggleMensesPause() {
    HapticFeedback.mediumImpact();
    state = state.copyWith(isMensesPaused: !state.isMensesPaused);
    _saveState();
  }
}
