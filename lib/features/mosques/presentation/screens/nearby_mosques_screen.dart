// lib/features/mosques/presentation/screens/nearby_mosques_screen.dart
// =============================================================================
// UMM-305: NearbyMosquesScreen — the primary mosque discovery screen.
//
// State machine handled by .when():
//
//   Provider state              UI rendered
//   ─────────────────────────────────────────────────────────────────
//   AsyncLoading (empty list)   Empty body with no spinner (initial idle)
//   AsyncLoading (fetching)     _LoadingState: centred spinner + label
//   AsyncData (non-empty)       _MosqueList: ListView.builder + RefreshIndicator
//   AsyncData (empty list)      _EmptyState: illustration + "no mosques" copy
//   AsyncError (LocationEx)     _LocationErrorState: permission message + CTA
//   AsyncError (NetworkEx)      _NetworkErrorState: generic error + Retry
//   AsyncError (other)          _GenericErrorState: fallback message + Retry
//
// The screen triggers fetchNearby() via PostFrameCallback on first build.
// Pull-to-refresh re-calls the same method, transitioning through AsyncLoading.
//
// All colours: ThemeData.colorScheme only — zero hardcoded Color literals.
// All strings: currently inline — extract to an l10n ARB file in Sprint 4.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../prayer/next_prayer_banner.dart';
import '../../data/models/mosque_model.dart';
import '../providers/nearby_mosques_provider.dart';
import '../widgets/mosque_card.dart';
import '../../../../widgets/prayer_tracker_widget.dart';
import 'mosque_detail_screen.dart';

class NearbyMosquesScreen extends ConsumerStatefulWidget {
  const NearbyMosquesScreen({super.key});

  static const routeName = '/mosques/nearby';

  @override
  ConsumerState<NearbyMosquesScreen> createState() => _NearbyMosquesScreenState();
}

class _NearbyMosquesScreenState extends ConsumerState<NearbyMosquesScreen> {
  // Tracks whether the first fetch has been triggered so we can distinguish
  // "idle before first load" (show spinner) from "API returned 0 results"
  // (show empty state). Both produce AsyncData([]) but mean different things.
  bool _hasFetched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => _hasFetched = true);
      ref.read(nearbyMosquesProvider.notifier).fetchNearby();
    });
  }

  Future<void> _onRefresh() =>
      ref.read(nearbyMosquesProvider.notifier).fetchNearby();

  @override
  Widget build(BuildContext context) {
    final mosquesAsync = ref.watch(nearbyMosquesProvider);
    final scheme       = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor:     scheme.surface,
        surfaceTintColor:    Colors.transparent,
        elevation:           0,
        scrolledUnderElevation: 1,
        title: Row(
          children: [
            Icon(Icons.mosque_rounded, color: scheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              'Mosques Nearby',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color:      scheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          // Manual refresh button — complements the pull-to-refresh gesture
          Semantics(
            label:  'Refresh mosque list',
            button: true,
            child: IconButton(
              icon:     Icon(Icons.refresh_rounded, color: scheme.primary),
              tooltip:  'Refresh',
              onPressed: () => ref
                  .read(nearbyMosquesProvider.notifier)
                  .fetchNearby(),
            ),
          ),
        ],
      ),
      body: mosquesAsync.when(
        // -----------------------------------------------------------------
        // Loading state
        // -----------------------------------------------------------------
        loading: () => const _LoadingState(),

        // -----------------------------------------------------------------
        // Error state — dispatch to the correct error widget by type
        // -----------------------------------------------------------------
        error: (error, _) => _buildErrorState(context, error),

        // -----------------------------------------------------------------
        // Data state — empty list or populated list
        // -----------------------------------------------------------------
        data: (mosques) => RefreshIndicator(
          onRefresh:   _onRefresh,
          color:       scheme.primary,
          strokeWidth: 2.5,
          child: mosques.isEmpty
              // Before the first fetch fires (_hasFetched == false), show a
              // spinner. After the fetch completes with 0 results, show the
              // proper "no mosques found" empty state instead.
              ? (_hasFetched ? const _EmptyState() : const _InitialIdleState())
              : _MosqueList(mosques: mosques, onRefresh: _onRefresh),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    if (error is LocationPermissionPermanentlyDeniedException) {
      return _LocationErrorState(
        message:        error.message,
        showSettingsBtn: true,
        onRetry:        _onRefresh,
      );
    }
    if (error is LocationException) {
      return _LocationErrorState(
        message:         error.message,
        showSettingsBtn: false,
        onRetry:         _onRefresh,
      );
    }
    if (error is NetworkException) {
      return _NetworkErrorState(
        message: error.message,
        onRetry: _onRefresh,
      );
    }
    // ParseException, unknown errors
    return _GenericErrorState(onRetry: _onRefresh);
  }
}

// ---------------------------------------------------------------------------
// State widgets — each handles exactly one UI state
// ---------------------------------------------------------------------------

/// Shown while GPS is being acquired + HTTP request is in flight.
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color:       scheme.primary,
            strokeWidth: 3,
          ),
          const SizedBox(height: 20),
          Text(
            'Finding nearby mosques…',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown immediately on mount before fetchNearby() fires (< 1 frame visible).
class _InitialIdleState extends StatelessWidget {
  const _InitialIdleState();

  @override
  Widget build(BuildContext context) {
    // Make the idle area scrollable so RefreshIndicator can be triggered
    // even before data arrives — purely a UX nicety.
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          child: Center(
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
              strokeWidth: 3,
            ),
          ),
        ),
      ],
    );
  }
}

/// The happy-path list — populated [Mosque] objects in a scrollable view.
class _MosqueList extends StatelessWidget {
  const _MosqueList({required this.mosques, required this.onRefresh});

  final List<Mosque>            mosques;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        const NextPrayerBanner(),
        const PrayerTrackerWidget(),
        // Result count header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Text(
                '${mosques.length} ${mosques.length == 1 ? "mosque" : "mosques"} found',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding:      const EdgeInsets.only(top: 4, bottom: 24),
            itemCount:    mosques.length,
            itemBuilder:  (context, index) => MosqueCard(
              mosque: mosques[index],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MosqueDetailScreen(mosque: mosques[index]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown when data returns but the list is empty (no mosques in radius).
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mosque_rounded, size: 64, color: scheme.outlineVariant),
            const SizedBox(height: 20),
            Text(
              'No mosques found nearby',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color:      scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try increasing your search radius or checking a different area.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown for [LocationException] — adapts CTA based on permanence.
class _LocationErrorState extends StatelessWidget {
  const _LocationErrorState({
    required this.message,
    required this.showSettingsBtn,
    required this.onRetry,
  });

  final String               message;
  final bool                 showSettingsBtn;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width:  72,
              height: 72,
              decoration: BoxDecoration(
                color:        scheme.errorContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.location_off_rounded,
                size:  36,
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Location Required',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color:      scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // "Open Settings" — for permanently denied (OS won't show dialog again)
            if (showSettingsBtn)
              FilledButton.icon(
                onPressed: () => openAppSettings(),
                icon:  const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Open Settings'),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  minimumSize:     const Size(200, 44),
                ),
              ),

            // "Try Again" — for one-time denial (OS can show dialog again)
            if (!showSettingsBtn)
              FilledButton.icon(
                onPressed: onRetry,
                icon:  const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try Again'),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  minimumSize:     const Size(200, 44),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown for [NetworkException] — no internet or server down.
class _NetworkErrorState extends StatelessWidget {
  const _NetworkErrorState({required this.message, required this.onRetry});

  final String               message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width:  72,
              height: 72,
              decoration: BoxDecoration(
                color:        scheme.errorContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size:  36,
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Connection Error',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color:      scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon:  const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                minimumSize:     const Size(200, 44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Catch-all for unexpected errors (ParseException, etc.).
class _GenericErrorState extends StatelessWidget {
  const _GenericErrorState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color:      scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'An unexpected error occurred. Please try again.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 44),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
