// lib/features/onboarding/onboarding_screen.dart
// =============================================================================
// OnboardingScreen — privacy-first, 3-slide welcome flow.
//
// Slide 1: Data sovereignty promise ("your location never leaves your device")
// Slide 2: Hyper-local mosque sync ("real Iqamah times from your actual mosque")
// Slide 3: Prayer tracker intro ("track prayers, build streaks, grow your mosque")
//
// Last slide shows a "Get Started" button that:
//   1. Requests location permission (shows rationale first)
//   2. OR lets the user search manually — they never get locked out
//   3. Writes onboarding_complete=true to SecureStorage
//   4. Pops this screen (caller replaces with NearbyMosquesScreen)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../services/auth/token_service.dart'; // for flutterSecureStorageProvider

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  /// Called when onboarding is finished — replaces this screen in the stack.
  final VoidCallback onComplete;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    _SlideData(
      icon: Icons.shield_rounded,
      title: 'Your Privacy, Protected',
      body:
          'Ummah never sells your location data. Your GPS coordinates are used '
          'only to find nearby mosques and are never stored on our servers.',
      highlight: 'Zero ads. Zero data brokers. Ever.',
    ),
    _SlideData(
      icon: Icons.mosque_rounded,
      title: 'Real Iqamah Times',
      body:
          'Unlike apps that use generic calculations, Ummah syncs directly with '
          "your mosque's actual prayer schedule — verified by the mosque committee.",
      highlight: 'Never miss Fajr because of a wrong algorithm.',
    ),
    _SlideData(
      icon: Icons.auto_awesome_rounded,
      title: 'Pray Together, Grow Together',
      body:
          'Track your 5 daily prayers. Check in at your mosque. Watch your '
          "community's 3D mosque grow as attendance increases.",
      highlight: 'The more your community prays, the grander your mosque becomes.',
    ),
  ];

  Future<void> _complete() async {
    final storage = ref.read(flutterSecureStorageProvider);
    await storage.write(key: 'onboarding_complete', value: 'true');
    widget.onComplete();
  }

  Future<void> _requestLocationAndComplete() async {
    // Request location permission — user can deny and still use manual search
    await Permission.locationWhenInUse.request();
    await _complete();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button (top-right)
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _complete,
                child: Text('Skip', style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            ),

            // Page content
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount:  _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _SlidePage(slide: _slides[i]),
              ),
            ),

            // Dot indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin:   const EdgeInsets.symmetric(horizontal: 4),
                  width:    _page == i ? 24 : 8,
                  height:   8,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? scheme.primary
                        : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 32),

            // CTA buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  if (isLast) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _requestLocationAndComplete,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          textStyle:   text.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        child: const Text('Allow Location & Get Started'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _complete,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('Search Manually Instead'),
                      ),
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _controller.nextPage(
                          duration: const Duration(milliseconds: 350),
                          curve:    Curves.easeInOut,
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: const Text('Next'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide page widget
// ---------------------------------------------------------------------------

class _SlidePage extends StatelessWidget {
  const _SlidePage({required this.slide});
  final _SlideData slide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon circle
          Container(
            width:  96,
            height: 96,
            decoration: BoxDecoration(
              color:  scheme.primaryContainer,
              shape:  BoxShape.circle,
            ),
            child: Icon(slide.icon, size: 48, color: scheme.primary),
          ),

          const SizedBox(height: 32),

          Text(
            slide.title,
            style: text.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color:      scheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Text(
            slide.body,
            style: text.bodyMedium?.copyWith(
              color:  scheme.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),

          // Highlight callout
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color:        scheme.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              slide.highlight,
              style: text.labelMedium?.copyWith(
                color:      scheme.primary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class _SlideData {
  const _SlideData({
    required this.icon,
    required this.title,
    required this.body,
    required this.highlight,
  });

  final IconData icon;
  final String   title;
  final String   body;
  final String   highlight;
}
