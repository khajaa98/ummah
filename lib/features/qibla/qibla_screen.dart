// lib/features/qibla/qibla_screen.dart
// =============================================================================
// QiblaScreen — Qibla direction compass with calibration UX.
//
// The naive "rotate an arrow by FlutterCompass.heading" approach silently
// points the user in the wrong direction whenever the magnetometer goes
// out of calibration — and on Android that happens after almost any trip
// through a metallic doorway or near a phone case with a magnetic clasp.
//
// This screen therefore:
//   1. Reads CompassEvent.heading AND CompassEvent.accuracy on every event.
//      Accuracy is a radian value — < 0.35 rad (~ 20°) is "good", 0.35–0.7
//      is "ok", > 0.7 (~ 40°) is "needs calibration".
//   2. Watches the device tilt via sensors_plus.accelerometerEventStream.
//      If |gx| or |gy| > 4.5 m/s² we know the device is being held off-flat
//      and the magnetometer reading is unreliable — we dim the arrow and
//      show a "Hold device flat" hint.
//   3. When accuracy drops below the "ok" threshold for > 2 s, slides in a
//      Figure-8 overlay with an animated stroke showing the recalibration
//      gesture and a Bluetooth-style accuracy meter.
//
// Add to pubspec.yaml:
//   flutter_compass: ^0.8.0
//   sensors_plus:    ^6.0.1
//
// Platform setup:
//   Android: ACCESS_FINE_LOCATION + Hardware feature 'android.hardware.sensor.compass'
//   iOS:     NSLocationWhenInUseUsageDescription (already added for geolocator)
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

class QiblaScreen extends StatefulWidget {
  const QiblaScreen({super.key});

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

// ---------------------------------------------------------------------------
// Compass accuracy buckets
// ---------------------------------------------------------------------------

enum _CompassAccuracy {
  good,
  ok,
  needsCalibration,
  unknown;

  static _CompassAccuracy fromRadians(double? r) {
    if (r == null || r.isNaN) return _CompassAccuracy.unknown;
    if (r < 0.35) return _CompassAccuracy.good;            // < ~20°
    if (r < 0.70) return _CompassAccuracy.ok;              // ~20–40°
    return _CompassAccuracy.needsCalibration;              // > ~40°
  }

  String get label => switch (this) {
        _CompassAccuracy.good             => 'High accuracy',
        _CompassAccuracy.ok               => 'Acceptable',
        _CompassAccuracy.needsCalibration => 'Needs calibration',
        _CompassAccuracy.unknown          => 'Calibrating…',
      };
}

class _QiblaScreenState extends State<QiblaScreen>
    with SingleTickerProviderStateMixin {
  // Kaaba coordinates
  static const double _kaabatLat = 21.4225;
  static const double _kaabatLng = 39.8262;

  Position? _position;
  String?   _locationError;

  // Sensor state
  StreamSubscription<AccelerometerEvent>? _accelSub;
  double _gx = 0; // gravity component on x-axis (m/s²)
  double _gy = 0;

  // Calibration debounce — only flip to "needs calibration" after a sustained
  // poor reading. Magnetometer noise often spikes for a few frames.
  Timer?            _calibrationDebounce;
  _CompassAccuracy  _stableAccuracy = _CompassAccuracy.unknown;

  // Figure-8 animation controller — runs forever while overlay is visible
  late final AnimationController _figureEightController;

  bool get _isHeldFlat => _gx.abs() < 4.5 && _gy.abs() < 4.5;

  @override
  void initState() {
    super.initState();
    _figureEightController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _getLocation();
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 100),
    ).listen((e) {
      if (!mounted) return;
      setState(() {
        _gx = e.x;
        _gy = e.y;
      });
    });
  }

  Future<void> _getLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      if (mounted) setState(() => _position = position);
    } catch (_) {
      if (mounted) {
        setState(() => _locationError =
            'Location unavailable — Qibla bearing may be approximate.');
      }
    }
  }

  /// Returns the bearing (degrees) from [userLat/Lng] toward the Kaaba.
  double _qiblaBearing(double userLat, double userLng) {
    final lat1  = _toRad(userLat);
    final lat2  = _toRad(_kaabatLat);
    final dLng  = _toRad(_kaabatLng - userLng);
    final y     = math.sin(dLng) * math.cos(lat2);
    final x     = math.cos(lat1) * math.sin(lat2) -
                  math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (_toDeg(math.atan2(y, x)) + 360) % 360;
  }

  static double _toRad(double deg) => deg * math.pi / 180;
  static double _toDeg(double rad) => rad * 180 / math.pi;

  /// Apply 2-second debounce so transient magnetometer spikes don't flicker
  /// the "needs calibration" overlay every other frame.
  void _onAccuracyChanged(_CompassAccuracy live) {
    if (live == _stableAccuracy) return;

    // Improvements ("good") can flip instantly — only degradations debounce.
    if (live.index < _stableAccuracy.index) {
      _calibrationDebounce?.cancel();
      setState(() => _stableAccuracy = live);
      return;
    }

    _calibrationDebounce?.cancel();
    _calibrationDebounce = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _stableAccuracy = live);
    });
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _calibrationDebounce?.cancel();
    _figureEightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor:     scheme.surface,
        surfaceTintColor:    Colors.transparent,
        elevation:           0,
        title: Row(
          children: [
            Icon(Icons.explore_rounded, color: scheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              'Qibla Direction',
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color:      scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<CompassEvent>(
        stream: FlutterCompass.events,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(
              message: 'Compass not available on this device.',
              scheme:  scheme,
              text:    text,
            );
          }

          if (!snapshot.hasData || snapshot.data!.heading == null) {
            return Center(
              child: CircularProgressIndicator(color: scheme.primary),
            );
          }

          final heading       = snapshot.data!.heading!;
          final liveAccuracy  = _CompassAccuracy.fromRadians(
              snapshot.data!.accuracy);

          // Debounced accuracy update — schedule outside build so we don't
          // call setState during a frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _onAccuracyChanged(liveAccuracy);
          });

          // Compute qibla offset from device north
          double qiblaOffset = 0;
          if (_position != null) {
            final qiblaBearing =
                _qiblaBearing(_position!.latitude, _position!.longitude);
            qiblaOffset = qiblaBearing - heading;
          }

          final showCalibrationOverlay =
              _stableAccuracy == _CompassAccuracy.needsCalibration;

          return Stack(
            children: [
              _CompassView(
                heading:      heading,
                qiblaOffset:  qiblaOffset,
                hasLocation:  _position != null,
                isHeldFlat:   _isHeldFlat,
                accuracy:     _stableAccuracy,
                locationNote: _locationError,
                scheme:       scheme,
                text:         text,
              ),
              if (showCalibrationOverlay)
                _CalibrationOverlay(
                  animation: _figureEightController,
                  scheme:    scheme,
                  text:      text,
                  onDismiss: () =>
                      setState(() => _stableAccuracy = _CompassAccuracy.ok),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compass view
// ---------------------------------------------------------------------------

class _CompassView extends StatelessWidget {
  const _CompassView({
    required this.heading,
    required this.qiblaOffset,
    required this.hasLocation,
    required this.isHeldFlat,
    required this.accuracy,
    required this.scheme,
    required this.text,
    this.locationNote,
  });

  final double           heading;
  final double           qiblaOffset;
  final bool             hasLocation;
  final bool             isHeldFlat;
  final _CompassAccuracy accuracy;
  final String?          locationNote;
  final ColorScheme      scheme;
  final TextTheme        text;

  @override
  Widget build(BuildContext context) {
    // Dim the arrow when device isn't held flat — the reading is unreliable
    // and we want the user to know it.
    final needleOpacity = isHeldFlat ? 1.0 : 0.35;

    return Column(
      children: [
        // ------------- Accuracy / tilt / location strip -------------
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              _AccuracyPill(accuracy: accuracy, scheme: scheme, text: text),
              if (!isHeldFlat) ...[
                const SizedBox(height: 8),
                _HintBanner(
                  icon:   Icons.screen_rotation_alt_rounded,
                  text:   'Hold your device flat for an accurate reading.',
                  scheme: scheme,
                  style:  text.bodySmall,
                ),
              ],
              if (locationNote != null) ...[
                const SizedBox(height: 8),
                _HintBanner(
                  icon:   Icons.info_outline,
                  text:   locationNote!,
                  scheme: scheme,
                  style:  text.bodySmall,
                ),
              ],
            ],
          ),
        ),

        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Compass dial
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer ring
                    Container(
                      width:  260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.outlineVariant,
                          width: 1.5,
                        ),
                        color: scheme.surfaceContainerLow,
                      ),
                    ),

                    // Compass rose — rotates with heading (shows true N)
                    Transform.rotate(
                      angle: -_toRad(heading),
                      child: SizedBox(
                        width:  220,
                        height: 220,
                        child: CustomPaint(
                          painter: _CompassRosePainter(scheme: scheme),
                        ),
                      ),
                    ),

                    // Qibla needle — points toward Mecca
                    Opacity(
                      opacity: needleOpacity,
                      child: Transform.rotate(
                        angle: _toRad(qiblaOffset),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.navigation_rounded,
                                size: 48, color: scheme.primary),
                            const SizedBox(height: 48), // balance the arrow
                          ],
                        ),
                      ),
                    ),

                    // Centre dot
                    Container(
                      width:  12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                Text(
                  hasLocation
                      ? 'Face the arrow toward Mecca'
                      : 'Point device toward Qibla',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color:      scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Kaaba — Mecca, Saudi Arabia',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}

// ---------------------------------------------------------------------------
// Accuracy pill — Bluetooth-style signal bars + label
// ---------------------------------------------------------------------------

class _AccuracyPill extends StatelessWidget {
  const _AccuracyPill({
    required this.accuracy,
    required this.scheme,
    required this.text,
  });

  final _CompassAccuracy accuracy;
  final ColorScheme      scheme;
  final TextTheme        text;

  Color _color() {
    switch (accuracy) {
      case _CompassAccuracy.good:             return scheme.primary;
      case _CompassAccuracy.ok:               return scheme.tertiary;
      case _CompassAccuracy.needsCalibration: return scheme.error;
      case _CompassAccuracy.unknown:          return scheme.onSurfaceVariant;
    }
  }

  int _bars() {
    switch (accuracy) {
      case _CompassAccuracy.good:             return 3;
      case _CompassAccuracy.ok:               return 2;
      case _CompassAccuracy.needsCalibration: return 1;
      case _CompassAccuracy.unknown:          return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _color();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:        color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Signal bars
          for (var i = 0; i < 3; i++) ...[
            Container(
              width:  4,
              height: 6.0 + i * 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: i < _bars() ? color : color.withOpacity(0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Text(
            accuracy.label,
            style: text.labelSmall?.copyWith(
              color:      color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hint banner — used for tilt + location warnings
// ---------------------------------------------------------------------------

class _HintBanner extends StatelessWidget {
  const _HintBanner({
    required this.icon,
    required this.text,
    required this.scheme,
    required this.style,
  });

  final IconData    icon;
  final String      text;
  final ColorScheme scheme;
  final TextStyle?  style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:        scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border:       Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: style?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Calibration overlay — animated Figure-8 prompt
// ---------------------------------------------------------------------------

class _CalibrationOverlay extends StatelessWidget {
  const _CalibrationOverlay({
    required this.animation,
    required this.scheme,
    required this.text,
    required this.onDismiss,
  });

  final Animation<double> animation;
  final ColorScheme       scheme;
  final TextTheme         text;
  final VoidCallback      onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: scheme.surface.withOpacity(0.94),
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated figure-8
            SizedBox(
              width:  220,
              height: 140,
              child: AnimatedBuilder(
                animation: animation,
                builder: (_, __) => CustomPaint(
                  painter: _FigureEightPainter(
                    progress: animation.value,
                    scheme:   scheme,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Compass needs calibration',
              style: text.titleLarge?.copyWith(
                color:      scheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Hold your device in front of you and move it in a figure-8 motion '
              'a few times. This re-trains the magnetometer.',
              style: text.bodyMedium?.copyWith(
                color:  scheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            OutlinedButton(
              onPressed: onDismiss,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(200, 44),
              ),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom compass rose painter
// ---------------------------------------------------------------------------

class _CompassRosePainter extends CustomPainter {
  _CompassRosePainter({required this.scheme});
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint  = Paint()
      ..color     = scheme.onSurfaceVariant.withOpacity(0.3)
      ..strokeWidth = 1.5
      ..style     = PaintingStyle.stroke;

    // 8 cardinal/intercardinal tick marks
    for (int i = 0; i < 8; i++) {
      final angle  = i * math.pi / 4;
      final inner  = size.width / 2 - 16;
      final outer  = size.width / 2 - 4;
      canvas.drawLine(
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        paint,
      );
    }

    // N label
    final tp = TextPainter(
      text: TextSpan(
        text:  'N',
        style: TextStyle(
          color:      scheme.primary,
          fontWeight: FontWeight.w700,
          fontSize:   14,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      center + Offset(-tp.width / 2, -size.height / 2 + 4),
    );
  }

  @override
  bool shouldRepaint(_CompassRosePainter old) => false;
}

// ---------------------------------------------------------------------------
// Figure-8 painter — draws an infinity (lemniscate of Gerono) curve with an
// animated "head" stroke travelling around it.
// ---------------------------------------------------------------------------

class _FigureEightPainter extends CustomPainter {
  _FigureEightPainter({required this.progress, required this.scheme});

  /// 0..1 loop progress
  final double      progress;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final a  = math.min(cx, cy) * 0.85;

    final bg = Paint()
      ..color       = scheme.outlineVariant
      ..strokeWidth = 4
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    final fg = Paint()
      ..color       = scheme.primary
      ..strokeWidth = 5
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    // Lemniscate of Gerono: x = a sin(t), y = a sin(t) cos(t)
    Offset point(double t) {
      final s = math.sin(t);
      final c = math.cos(t);
      return Offset(cx + a * s, cy + (a * 0.6) * s * c);
    }

    final bgPath = Path();
    const steps  = 100;
    for (var i = 0; i <= steps; i++) {
      final t  = (i / steps) * 2 * math.pi;
      final p  = point(t);
      if (i == 0) {
        bgPath.moveTo(p.dx, p.dy);
      } else {
        bgPath.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(bgPath, bg);

    // Animated foreground head — last ~25% of the loop
    final fgPath  = Path();
    const tail    = 0.25;
    final start   = progress - tail;
    bool   begun  = false;
    for (var i = 0; i <= steps; i++) {
      final f = i / steps;
      if (f < start || f > progress) continue;
      final t = f * 2 * math.pi;
      final p = point(t);
      if (!begun) {
        fgPath.moveTo(p.dx, p.dy);
        begun = true;
      } else {
        fgPath.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(fgPath, fg);

    // Travelling dot at the head of the stroke
    final headT = progress * 2 * math.pi;
    final head  = point(headT);
    canvas.drawCircle(head, 7, Paint()..color = scheme.primary);
  }

  @override
  bool shouldRepaint(_FigureEightPainter old) => old.progress != progress;
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.scheme,
    required this.text,
  });

  final String      message;
  final ColorScheme scheme;
  final TextTheme   text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_off_rounded, size: 56, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              'Compass Unavailable',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
