// lib/services/auth/token_service.dart
// =============================================================================
// UMM-301: TokenService — JWT lifecycle manager.
//
// Wraps flutter_secure_storage to provide a typed, single-responsibility
// interface for all token operations.
//
// Storage backends:
//   Android: EncryptedSharedPreferences (AES-256). Requires minSdkVersion 23.
//   iOS:     Keychain Services. No additional configuration required.
//
// Privacy rules enforced here:
//   ✗ Token value is NEVER written to debugPrint, log(), or analytics.
//   ✗ Token is NEVER stored in SharedPreferences (unencrypted on Android).
//   ✓ Token is accessed only through this service — no other layer imports
//     FlutterSecureStorage directly.
//
// Riverpod integration:
//   tokenServiceProvider is the sole entry point. Inject this provider
//   into any other provider that needs auth (e.g. MosqueRepository).
//   Override in tests with a FakeFlutterSecureStorage.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ---------------------------------------------------------------------------
// Interface — allows mock substitution in unit tests
// ---------------------------------------------------------------------------

abstract interface class ITokenService {
  Future<void>    saveToken(String token);
  Future<String?> getToken();
  Future<void>    deleteToken();
  Future<bool>    hasToken();
}

// ---------------------------------------------------------------------------
// Concrete implementation
// ---------------------------------------------------------------------------

class TokenService implements ITokenService {
  const TokenService(this._storage);

  final FlutterSecureStorage _storage;

  // Private storage key — never a magic string outside this file.
  static const _kAuthToken = 'ummah_auth_token';

  // Android-specific options: use EncryptedSharedPreferences (AES-256).
  // This is a no-op on iOS (Keychain is always used).
  static const _kAndroidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  @override
  Future<void> saveToken(String token) => _storage.write(
        key:            _kAuthToken,
        value:          token,
        aOptions:       _kAndroidOptions,
      );

  @override
  Future<String?> getToken() => _storage.read(
        key:      _kAuthToken,
        aOptions: _kAndroidOptions,
      );

  @override
  Future<void> deleteToken() => _storage.delete(
        key:      _kAuthToken,
        aOptions: _kAndroidOptions,
      );

  @override
  Future<bool> hasToken() async =>
      (await _storage.read(key: _kAuthToken, aOptions: _kAndroidOptions)) != null;
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

/// Provides the [FlutterSecureStorage] instance.
/// Override in tests: ProviderContainer(overrides: [
///   flutterSecureStorageProvider.overrideWithValue(FakeFlutterSecureStorage()),
/// ])
final flutterSecureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
  name: 'flutterSecureStorageProvider',
);

/// The canonical [TokenService] provider.
/// All providers that need to read or write the JWT depend on this.
final tokenServiceProvider = Provider<TokenService>(
  (ref) => TokenService(ref.watch(flutterSecureStorageProvider)),
  name: 'tokenServiceProvider',
);
