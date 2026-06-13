// lib/services/telemetry/sentry_init.dart
// =============================================================================
// Sentry wiring — privacy-first.
//
// The whole point of Ummah is that location, prayer history, and identity
// stay on the device. Sentry is the one outbound telemetry pipe, so it must
// be locked down hard:
//
//   1. DSN is injected only via --dart-define; absent in dev builds.
//   2. sendDefaultPii = false (never attach IP, device IDs, OS user).
//   3. beforeSend hook strips:
//        - Lat/Lng pairs from any breadcrumb / event message
//        - "Bearer …" JWTs from request/response data
//        - Any field key matching auth_token, jwt, password, lat, lng, etc.
//   4. attachStacktrace = true so we still get the line that crashed.
//   5. tracesSampleRate = 0.1 on prod, 1.0 on staging — performance traces
//      never carry user-identifying spans (we don't instrument widgets).
//
// All of this is wrapped in [runUmmah] which the app's main() calls in place
// of runApp(). If no DSN is configured, runApp is invoked directly so dev
// builds and CI tests don't need a Sentry project.
// =============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// ---------------------------------------------------------------------------
// Compile-time configuration
// ---------------------------------------------------------------------------

const _kDsn         = String.fromEnvironment('SENTRY_DSN');
const _kEnvironment = String.fromEnvironment(
  'SENTRY_ENVIRONMENT',
  defaultValue: 'development',
);
const _kRelease     = String.fromEnvironment('SENTRY_RELEASE');

// ---------------------------------------------------------------------------
// PII scrubber regexes
// ---------------------------------------------------------------------------

final _coordRegex     = RegExp(r'-?\d{1,3}\.\d{2,}\s*,\s*-?\d{1,3}\.\d{2,}');
final _bearerRegex    = RegExp(r'Bearer\s+[A-Za-z0-9\-._~+/]+=*');
final _sensitiveKeys  = <String>{
  'auth_token', 'authToken', 'jwt', 'token', 'password', 'secret',
  'latitude', 'longitude', 'lat', 'lng', 'lon',
  'address', 'street', 'gps',
};

String _scrubString(String value) => value
    .replaceAll(_coordRegex, '<coords-redacted>')
    .replaceAll(_bearerRegex, 'Bearer <redacted>');

dynamic _scrubMap(dynamic node) {
  if (node is Map) {
    return node.map((k, v) {
      if (k is String && _sensitiveKeys.contains(k.toLowerCase())) {
        return MapEntry(k, '<redacted>');
      }
      return MapEntry(k, _scrubMap(v));
    });
  }
  if (node is List)   return node.map(_scrubMap).toList();
  if (node is String) return _scrubString(node);
  return node;
}

// ---------------------------------------------------------------------------
// beforeSend hook — runs on every event AND every breadcrumb
// ---------------------------------------------------------------------------

FutureOr<SentryEvent?> _beforeSend(SentryEvent event, Hint hint) {
  // Scrub message + breadcrumbs + extras
  final scrubbedMessage = event.message == null
      ? null
      : SentryMessage(
          _scrubString(event.message!.formatted),
          template: event.message!.template,
        );

  final scrubbedBreadcrumbs = event.breadcrumbs
      ?.map((b) => b.copyWith(
            message: b.message == null ? null : _scrubString(b.message!),
            data:    b.data    == null ? null : Map<String, dynamic>.from(_scrubMap(b.data!) as Map),
          ))
      .toList();

  return event.copyWith(
    message:     scrubbedMessage,
    breadcrumbs: scrubbedBreadcrumbs,
    extra:       event.extra == null
        ? null
        : Map<String, dynamic>.from(_scrubMap(event.extra!) as Map),
    // Drop request bodies entirely — they may contain GPS in our /nearby call
    request:     event.request?.copyWith(
      data:    null,
      cookies: null,
      headers: null,
    ),
    user:        null, // never attach a user object
  );
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Wraps [appRunner] with Sentry error capture. Falls through to a plain
/// runApp() in builds where no DSN was provided.
Future<void> runUmmah(Widget Function() appRunner) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_kDsn.isEmpty) {
    runApp(appRunner());
    return;
  }

  await SentryFlutter.init(
    (options) {
      options.dsn               = _kDsn;
      options.environment       = _kEnvironment;
      options.release           = _kRelease.isEmpty ? null : _kRelease;
      options.sendDefaultPii    = false;
      options.attachStacktrace  = true;
      options.tracesSampleRate  = _kEnvironment == 'production' ? 0.10 : 1.0;
      options.beforeSend        = _beforeSend;

      // Disable breadcrumb-on-navigation logging since route names can encode
      // mosque IDs that are a proxy for the user's city.
      options.recordHttpBreadcrumbs    = false;
      options.enableAutoNativeBreadcrumbs = false;

      if (kDebugMode) options.debug = true;
    },
    appRunner: () => runApp(appRunner()),
  );
}
