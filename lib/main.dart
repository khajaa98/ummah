// lib/main.dart
// =============================================================================
// Ummah — app entry point.
//
// Sprint 7 additions:
//   • Onboarding gate: checks SecureStorage for 'onboarding_complete'.
//     If absent, shows OnboardingScreen before the main shell.
//   • UmmahShell wraps the 3-tab NavigationBar (Mosques / Qibla / Supporter).
//   • UmmahApp remains a ConsumerWidget watching dynamicThemeProvider.
//   • ThemeMode.light so our dynamic phase engine has exclusive control.
//   • NotificationService.init() runs before runApp so the timezone db is
//     loaded and the Android channel is created before any schedule call.
//   • UmmahShell listens to favouriteMosqueProvider + mosqueTimingsProvider
//     and re-schedules prayer-time alerts whenever either changes.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'core/providers/dynamic_theme_provider.dart';
import 'features/mosques/data/models/prayer_timing.dart';
import 'features/mosques/presentation/providers/favourite_mosque_provider.dart';
import 'features/mosques/presentation/providers/prayer_timings_provider.dart';
import 'features/mosques/presentation/screens/nearby_mosques_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/qibla/qibla_screen.dart';
import 'features/settings/supporter_screen.dart';
import 'services/notifications/notification_service.dart';
import 'services/purchases/purchases_service.dart';
import 'services/telemetry/sentry_init.dart';

Future<void> main() async {
  // runUmmah() ensures WidgetsFlutterBinding is initialized inside the
  // Sentry zone so unhandled errors during startup are still captured.
  await runUmmah(() {
    // Fire-and-forget service init — they self-guard against running twice.
    NotificationService.instance.init();
    PurchasesService.instance.configure();
    return const ProviderScope(child: UmmahApp());
  });
}

// ---------------------------------------------------------------------------
// Root app — theme engine
// ---------------------------------------------------------------------------

class UmmahApp extends ConsumerWidget {
  const UmmahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTheme = ref.watch(dynamicThemeProvider);

    return MaterialApp(
      title:                      'Ummah',
      debugShowCheckedModeBanner: false,
      theme:                      activeTheme,
      themeMode:                  ThemeMode.light,
      themeAnimationDuration:     const Duration(milliseconds: 600),
      themeAnimationCurve:        Curves.easeInOut,
      home:                       const _OnboardingGate(),
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding gate — checks SecureStorage once at startup
// ---------------------------------------------------------------------------

class _OnboardingGate extends StatefulWidget {
  const _OnboardingGate();

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  static const _storage = FlutterSecureStorage();
  bool? _onboardingComplete; // null = still checking

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final value = await _storage.read(key: 'onboarding_complete');
    setState(() => _onboardingComplete = value == 'true');
  }

  @override
  Widget build(BuildContext context) {
    // Still loading flag from storage — show blank surface (< 1 frame)
    if (_onboardingComplete == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
      );
    }

    if (!_onboardingComplete!) {
      return OnboardingScreen(
        onComplete: () => setState(() => _onboardingComplete = true),
      );
    }

    return const UmmahShell();
  }
}

// ---------------------------------------------------------------------------
// Main shell — bottom nav with 3 tabs
// ---------------------------------------------------------------------------

class UmmahShell extends ConsumerStatefulWidget {
  const UmmahShell({super.key});

  @override
  ConsumerState<UmmahShell> createState() => _UmmahShellState();
}

class _UmmahShellState extends ConsumerState<UmmahShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    NavigationDestination(
      icon:         Icon(Icons.mosque_outlined),
      selectedIcon: Icon(Icons.mosque_rounded),
      label:        'Mosques',
    ),
    NavigationDestination(
      icon:         Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore_rounded),
      label:        'Qibla',
    ),
    NavigationDestination(
      icon:         Icon(Icons.workspace_premium_outlined),
      selectedIcon: Icon(Icons.workspace_premium_rounded),
      label:        'Supporter',
    ),
  ];

  // Using IndexedStack keeps each tab's scroll position alive
  static const _screens = [
    NearbyMosquesScreen(),
    QiblaScreen(),
    SupporterScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Cancel pending alerts if the user clears their favourite mosque.
    ref.listen(favouriteMosqueProvider, (_, mosque) {
      if (mosque == null) {
        NotificationService.instance.cancelAll();
      }
    });

    // Re-schedule prayer alerts whenever the favourite mosque OR its verified
    // timings refresh. The derived provider below collapses both sources into
    // one stream we can listen to.
    ref.listen<AsyncValue<List<PrayerTiming>>?>(
      _favouriteTimingsProvider,
      (_, asyncTimings) {
        final mosque = ref.read(favouriteMosqueProvider);
        if (mosque == null || asyncTimings == null) return;
        asyncTimings.whenData((timings) {
          if (timings.isNotEmpty) {
            NotificationService.instance.schedulePrayerAlerts(
              mosque:  mosque,
              timings: timings,
            );
          }
        });
      },
    );

    return Scaffold(
      body: IndexedStack(
        index:    _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex:  _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        backgroundColor: scheme.surface,
        indicatorColor:  scheme.primaryContainer,
        destinations:    _destinations,
        labelBehavior:   NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Derived provider — surfaces the *current* favourite mosque's timings
// AsyncValue so the shell can re-schedule notifications reactively.
// Returns null when no favourite is set.
// ---------------------------------------------------------------------------

final _favouriteTimingsProvider =
    Provider<AsyncValue<List<PrayerTiming>>?>((ref) {
  final fav = ref.watch(favouriteMosqueProvider);
  if (fav == null) return null;
  return ref.watch(mosqueTimingsProvider(fav.id));
});
