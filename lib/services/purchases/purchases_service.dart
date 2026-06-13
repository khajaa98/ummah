// lib/services/purchases/purchases_service.dart
// =============================================================================
// PurchasesService — RevenueCat wrapper.
//
// Why RevenueCat:
//   • Single SDK abstracts Apple StoreKit + Google Play Billing
//   • Server-side receipt validation handled for free
//   • Entitlement model maps cleanly onto our "supporter / non-supporter" gate
//   • Free tier covers up to $10K MTR — well past our launch window
//
// Configuration (set via --dart-define at build time):
//   REVENUECAT_IOS_KEY=appl_xxx
//   REVENUECAT_ANDROID_KEY=goog_xxx
//
// Entitlement identifiers (set up in RevenueCat dashboard):
//   "supporter" — granted by any of the Friend/Patron/Builder subscriptions
//
// Product identifiers (set up in App Store Connect + Play Console):
//   Subscriptions  : ummah.supporter.friend / .patron / .builder
//   Consumables    : ummah.iftar.99 / .299 / .999
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

// ---------------------------------------------------------------------------
// API key resolution
// ---------------------------------------------------------------------------

const _kIosKey      = String.fromEnvironment('REVENUECAT_IOS_KEY');
const _kAndroidKey  = String.fromEnvironment('REVENUECAT_ANDROID_KEY');

/// The entitlement that unlocks supporter status in the app.
const kSupporterEntitlement = 'supporter';

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class PurchasesService {
  PurchasesService._();
  static final PurchasesService instance = PurchasesService._();

  bool _configured = false;

  // Broadcast bridge: convert the SDK's listener callback API into a Stream
  // so Riverpod can watch entitlement changes natively.
  final StreamController<CustomerInfo> _infoCtrl =
      StreamController<CustomerInfo>.broadcast();

  void _onCustomerInfoUpdate(CustomerInfo info) => _infoCtrl.add(info);

  /// Initialize the RevenueCat SDK. Safe to call multiple times.
  Future<void> configure({String? appUserId}) async {
    if (_configured) return;

    final apiKey = Platform.isIOS ? _kIosKey : _kAndroidKey;
    if (apiKey.isEmpty) {
      // No API key in this build — leave un-configured. Calls into the service
      // will throw [PurchasesNotConfiguredException] so the UI can fall back
      // to a "Coming soon" message instead of crashing.
      return;
    }

    await Purchases.setLogLevel(LogLevel.info);
    await Purchases.configure(
      PurchasesConfiguration(apiKey)..appUserID = appUserId,
    );
    Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdate);
    _configured = true;
  }

  bool get isConfigured => _configured;

  /// Returns the current offering (set of available packages) configured in
  /// the RevenueCat dashboard. Throws if no offering is published.
  Future<Offering> currentOffering() async {
    _requireConfigured();
    final offerings = await Purchases.getOfferings();
    final current   = offerings.current;
    if (current == null) {
      throw const PurchasesUnavailableException(
        'No offering is currently published in RevenueCat.',
      );
    }
    return current;
  }

  /// Purchase a package. Returns true if the purchase succeeded and the
  /// supporter entitlement is now active.
  Future<bool> purchase(Package package) async {
    _requireConfigured();
    final result = await Purchases.purchasePackage(package);
    return result.entitlements.active.containsKey(kSupporterEntitlement);
  }

  /// Restore previous purchases (App Store / Play Store account-tied).
  Future<bool> restore() async {
    _requireConfigured();
    final info = await Purchases.restorePurchases();
    return info.entitlements.active.containsKey(kSupporterEntitlement);
  }

  /// One-shot fetch of the current customer info.
  Future<CustomerInfo> customerInfo() async {
    _requireConfigured();
    return Purchases.getCustomerInfo();
  }

  /// Live CustomerInfo stream. Yields the current snapshot first, then every
  /// subsequent update pushed by the SDK.
  Stream<CustomerInfo> customerInfoStream() async* {
    if (!_configured) return;
    yield await Purchases.getCustomerInfo();
    yield* _infoCtrl.stream;
  }
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

class PurchasesNotConfiguredException implements Exception {
  const PurchasesNotConfiguredException(this.message);
  final String message;
  @override
  String toString() => 'PurchasesNotConfiguredException: $message';
}

class PurchasesUnavailableException implements Exception {
  const PurchasesUnavailableException(this.message);
  final String message;
  @override
  String toString() => 'PurchasesUnavailableException: $message';
}

void _requireConfigured() {
  if (!PurchasesService.instance.isConfigured) {
    throw const PurchasesNotConfiguredException(
      'RevenueCat SDK not configured. Build with '
      '--dart-define=REVENUECAT_IOS_KEY=... and --dart-define='
      'REVENUECAT_ANDROID_KEY=...',
    );
  }
}

// ---------------------------------------------------------------------------
// Riverpod providers
// ---------------------------------------------------------------------------

final purchasesServiceProvider = Provider<PurchasesService>(
  (_) => PurchasesService.instance,
  name: 'purchasesServiceProvider',
);

/// Live CustomerInfo — emits whenever entitlements change.
final customerInfoProvider = StreamProvider<CustomerInfo>((ref) {
  final service = ref.watch(purchasesServiceProvider);
  return service.customerInfoStream();
});

/// Derived: true iff the user currently has an active supporter entitlement.
final isSupporterProvider = Provider<bool>((ref) {
  final info = ref.watch(customerInfoProvider).asData?.value;
  if (info == null) return false;
  return info.entitlements.active.containsKey(kSupporterEntitlement);
});

/// Current published offering — refresh-able via ref.invalidate().
final currentOfferingProvider = FutureProvider<Offering>((ref) async {
  final service = ref.watch(purchasesServiceProvider);
  return service.currentOffering();
});
