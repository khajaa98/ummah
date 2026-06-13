// lib/features/settings/supporter_screen.dart
// =============================================================================
// SupporterScreen — privacy-first monetization, RevenueCat-backed.
//
// Phase 6 wiring:
//   • Reads `currentOfferingProvider` to surface live prices straight from the
//     App Store / Play Console (no hard-coded ₹ values).
//   • Sub-tier packages identified by their RevenueCat `package.identifier`:
//       - $rc_monthly_friend   → "Friend"
//       - $rc_monthly_patron   → "Patron"   (default highlighted)
//       - $rc_monthly_builder  → "Builder"
//   • One-time iftar consumables show up under `availablePackages` with
//     `packageType == PackageType.lifetime`.
//   • Purchase → `service.purchase(package)`; success drives `isSupporterProvider`.
//   • A "Restore purchases" button calls `service.restore()`.
//   • If the SDK isn't configured (no API key in this build), falls back to
//     the Sprint-7 stub with a "Coming soon" dialog.
//
// Errors:
//   PurchasesErrorCode.purchaseCancelledError      → silent (user backed out)
//   PurchasesErrorCode.purchaseNotAllowedError     → "Purchases disabled on this device."
//   anything else                                  → SnackBar with `e.message`
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../services/purchases/purchases_service.dart';

class SupporterScreen extends ConsumerStatefulWidget {
  const SupporterScreen({super.key});

  @override
  ConsumerState<SupporterScreen> createState() => _SupporterScreenState();
}

class _SupporterScreenState extends ConsumerState<SupporterScreen> {
  String? _selectedPackageId; // null = nothing chosen yet
  bool _busy = false;

  // ---- friendly metadata for our three tiers (keyed by RC package identifier)
  static const _tierMeta = <String, _TierMeta>{
    r'$rc_monthly_friend': _TierMeta(
      name:  'Friend',
      blurb: 'Cover your share of the servers. Every rupee goes to keeping Ummah ad-free.',
      icon:  Icons.favorite_outline_rounded,
    ),
    r'$rc_monthly_patron': _TierMeta(
      name:      'Patron',
      blurb:     'Help us onboard new mosques and verify their Iqamah times by hand.',
      icon:      Icons.volunteer_activism_rounded,
      isPopular: true,
    ),
    r'$rc_monthly_builder': _TierMeta(
      name:  'Builder',
      blurb: 'Fund the full onboarding of a new mosque — your name appears in our credits page.',
      icon:  Icons.mosque_rounded,
    ),
  };

  // ---------------------------------------------------------------------------
  // Purchase flow
  // ---------------------------------------------------------------------------

  Future<void> _buy(Package package) async {
    final service = ref.read(purchasesServiceProvider);
    setState(() => _busy = true);
    try {
      final unlocked = await service.purchase(package);
      if (!mounted) return;
      if (unlocked) {
        _showSnack('JazakAllah Khair — you\'re officially a Supporter.');
      } else {
        _showSnack('Purchase complete — entitlement is syncing.');
      }
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        // user backed out — silent
      } else if (code == PurchasesErrorCode.purchaseNotAllowedError) {
        _showSnack('Purchases are disabled on this device.');
      } else {
        _showSnack('Purchase failed: ${e.message ?? code.name}');
      }
    } on PurchasesNotConfiguredException {
      _showComingSoonDialog();
    } catch (e) {
      _showSnack('Purchase failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final service = ref.read(purchasesServiceProvider);
    setState(() => _busy = true);
    try {
      final unlocked = await service.restore();
      if (!mounted) return;
      _showSnack(unlocked
          ? 'Purchases restored — welcome back.'
          : 'No previous purchases found on this Apple ID / Google account.');
    } on PurchasesNotConfiguredException {
      _showComingSoonDialog();
    } catch (e) {
      _showSnack('Could not restore: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showComingSoonDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon:  Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 36),
          title: const Text('Coming soon, InshaAllah'),
          content: const Text(
            'Supporter contributions go live in our next release. '
            'JazakAllah Khair for your generosity — we\'ll notify you when it\'s ready.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child:    const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme        = Theme.of(context).colorScheme;
    final text          = Theme.of(context).textTheme;
    final isSupporter   = ref.watch(isSupporterProvider);
    final offeringAsync = ref.watch(currentOfferingProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor:  scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation:        0,
        title: Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: scheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              isSupporter ? 'You\'re a Supporter' : 'Become a Supporter',
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color:      scheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _restore,
            child:     const Text('Restore'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _HeroPitch(isSupporter: isSupporter, scheme: scheme, text: text),
          const SizedBox(height: 24),

          // -------- Live offerings from RevenueCat --------
          offeringAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child:   Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => _OfferingsUnavailable(
              onShowDialog: _showComingSoonDialog,
              scheme:       scheme,
              text:         text,
            ),
            data: (offering) {
              final monthly = offering.availablePackages
                  .where((p) => _tierMeta.containsKey(p.identifier))
                  .toList();
              final oneTime = offering.availablePackages
                  .where((p) => p.packageType == PackageType.lifetime)
                  .toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose a monthly contribution',
                    style: text.titleMedium?.copyWith(
                      color:      scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),

                  for (final pkg in monthly) ...[
                    _TierCard(
                      package:    pkg,
                      meta:       _tierMeta[pkg.identifier]!,
                      isSelected: _selectedPackageId == pkg.identifier,
                      onTap:      () => setState(
                          () => _selectedPackageId = pkg.identifier),
                      scheme:     scheme,
                      text:       text,
                    ),
                    const SizedBox(height: 10),
                  ],

                  const SizedBox(height: 12),

                  // Confirm CTA
                  FilledButton.icon(
                    onPressed: (_busy || _selectedPackageId == null)
                        ? null
                        : () {
                            final pkg = monthly.firstWhere(
                                (p) => p.identifier == _selectedPackageId);
                            _buy(pkg);
                          },
                    icon:  _busy
                        ? const SizedBox(
                            width:  18,
                            height: 18,
                            child:  CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.favorite_rounded),
                    label: Text(_selectedPackageId == null
                        ? 'Choose a tier above'
                        : 'Support with ${_priceForId(monthly, _selectedPackageId!)}/month'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      textStyle:   text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),

                  // -------- One-time iftar contributions --------
                  if (oneTime.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _OneTimeCard(
                      packages:  oneTime,
                      onTap:     _busy ? null : _buy,
                      scheme:    scheme,
                      text:      text,
                    ),
                  ],
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          Center(
            child: Text(
              'Cancel anytime. No locked features. No guilt.',
              style: text.bodySmall?.copyWith(
                color:      scheme.onSurfaceVariant,
                fontStyle:  FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _priceForId(List<Package> pkgs, String id) =>
      pkgs.firstWhere((p) => p.identifier == id).storeProduct.priceString;
}

// ---------------------------------------------------------------------------
// Hero pitch (different copy when already a supporter)
// ---------------------------------------------------------------------------

class _HeroPitch extends StatelessWidget {
  const _HeroPitch({
    required this.isSupporter,
    required this.scheme,
    required this.text,
  });

  final bool        isSupporter;
  final ColorScheme scheme;
  final TextTheme   text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin:  Alignment.topLeft,
          end:    Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isSupporter ? Icons.verified_rounded : Icons.shield_moon_rounded,
            size:  40,
            color: scheme.onPrimaryContainer,
          ),
          const SizedBox(height: 12),
          Text(
            isSupporter
                ? 'JazakAllah Khair.\nYou keep Ummah free.'
                : 'Zero ads. Zero data sold.\nForever.',
            style: text.headlineSmall?.copyWith(
              color:      scheme.onPrimaryContainer,
              fontWeight: FontWeight.w800,
              height:     1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSupporter
                ? 'Your contribution funds new mosques being onboarded by hand. Manage your subscription anytime in your App Store / Play Store account.'
                : 'Ummah is funded entirely by Muslims who believe technology can serve faith without selling souls. If that\'s you, JazakAllah Khair.',
            style: text.bodyMedium?.copyWith(
              color:  scheme.onPrimaryContainer.withOpacity(0.85),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tier card
// ---------------------------------------------------------------------------

class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.package,
    required this.meta,
    required this.isSelected,
    required this.onTap,
    required this.scheme,
    required this.text,
  });

  final Package      package;
  final _TierMeta    meta;
  final bool         isSelected;
  final VoidCallback onTap;
  final ColorScheme  scheme;
  final TextTheme    text;

  @override
  Widget build(BuildContext context) {
    final product = package.storeProduct;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:  const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primaryContainer.withOpacity(0.35)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Radio indicator
              Container(
                width:  24,
                height: 24,
                decoration: BoxDecoration(
                  shape:  BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? scheme.primary : scheme.outline,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width:  12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Body
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(meta.icon, size: 18, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          meta.name,
                          style: text.titleSmall?.copyWith(
                            color:      scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (meta.isPopular) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color:        scheme.tertiary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Popular',
                              style: text.labelSmall?.copyWith(
                                color:      scheme.onTertiary,
                                fontWeight: FontWeight.w700,
                                fontSize:   10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta.blurb,
                      style: text.bodySmall?.copyWith(
                        color:  scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Price — live from store
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    product.priceString,
                    style: text.titleMedium?.copyWith(
                      color:      scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '/month',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One-time contribution card
// ---------------------------------------------------------------------------

class _OneTimeCard extends StatelessWidget {
  const _OneTimeCard({
    required this.packages,
    required this.onTap,
    required this.scheme,
    required this.text,
  });

  final List<Package>         packages;
  final void Function(Package)? onTap;
  final ColorScheme           scheme;
  final TextTheme             text;

  @override
  Widget build(BuildContext context) {
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
              Icon(Icons.fastfood_rounded, color: scheme.tertiary),
              const SizedBox(width: 8),
              Text(
                'One-time contribution',
                style: text.titleSmall?.copyWith(
                  color:      scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Not ready to subscribe? Buy us an iftar — every little bit keeps the servers running through Ramadan.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final pkg in packages)
                OutlinedButton(
                  onPressed: onTap == null ? null : () => onTap!(pkg),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: Text(pkg.storeProduct.priceString),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Offerings unavailable — fallback when SDK isn't configured or no offering
// ---------------------------------------------------------------------------

class _OfferingsUnavailable extends StatelessWidget {
  const _OfferingsUnavailable({
    required this.onShowDialog,
    required this.scheme,
    required this.text,
  });

  final VoidCallback onShowDialog;
  final ColorScheme  scheme;
  final TextTheme    text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_rounded, color: scheme.primary, size: 40),
          const SizedBox(height: 12),
          Text(
            'Supporter tiers launching soon',
            style: text.titleMedium?.copyWith(
              color:      scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'We\'re finalizing prices with the App Store. Check back in our next release.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onShowDialog,
            child:     const Text('Notify me'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metadata
// ---------------------------------------------------------------------------

class _TierMeta {
  const _TierMeta({
    required this.name,
    required this.blurb,
    required this.icon,
    this.isPopular = false,
  });

  final String   name;
  final String   blurb;
  final IconData icon;
  final bool     isPopular;
}
