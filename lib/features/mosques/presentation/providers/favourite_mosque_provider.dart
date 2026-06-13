// lib/features/mosques/presentation/providers/favourite_mosque_provider.dart
// =============================================================================
// favouriteMosqueProvider — persists the user's "home mosque" in SecureStorage.
//
// The favourite mosque drives:
//   • The NextPrayerBanner on the main screen
//   • Notification scheduling (prayer time alerts)
//   • The prayer phase transitions (actual times vs hardcoded clock boundaries)
//
// Uses flutter_secure_storage (already a dependency) so no new package is needed.
// The Mosque object is serialised as JSON and stored under a fixed key.
// =============================================================================

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/models/mosque_model.dart';
import '../../../../services/auth/token_service.dart'; // re-uses flutterSecureStorageProvider

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final favouriteMosqueProvider =
    StateNotifierProvider<FavouriteMosqueNotifier, Mosque?>((ref) {
  return FavouriteMosqueNotifier(ref.read(flutterSecureStorageProvider));
});

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class FavouriteMosqueNotifier extends StateNotifier<Mosque?> {
  static const _key = 'favourite_mosque_v1';

  FavouriteMosqueNotifier(this._storage) : super(null) {
    _load();
  }

  final FlutterSecureStorage _storage;

  Future<void> _load() async {
    try {
      final json = await _storage.read(key: _key);
      if (json != null) {
        state = Mosque.fromJson(jsonDecode(json) as Map<String, dynamic>);
      }
    } catch (_) {
      state = null; // Corrupt data — start fresh
    }
  }

  Future<void> setFavourite(Mosque mosque) async {
    state = mosque;
    await _storage.write(key: _key, value: jsonEncode(mosque.toJson()));
  }

  Future<void> clearFavourite() async {
    state = null;
    await _storage.delete(key: _key);
  }

  bool isFavourite(String mosqueId) => state?.id == mosqueId;
}
