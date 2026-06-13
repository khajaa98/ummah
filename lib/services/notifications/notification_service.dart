// lib/services/notifications/notification_service.dart
// =============================================================================
// NotificationService — schedules local prayer-time notifications.
//
// Strategy:
//   • Read the user's favourite mosque from favouriteMosqueProvider.
//   • Read verified PrayerTiming list for the next 7 days.
//   • Cancel all pending Ummah notifications.
//   • Re-schedule one notification per prayer per day (max 35 — well under
//     Android's 50-pending limit per app).
//   • Notification body uses the mosque's verified time, not a calculated one,
//     so it matches what the user sees on the detail screen.
//
// Privacy:
//   • All scheduling happens locally — no push tokens, no FCM, no server.
//   • Notifications fire even when the app is killed (uses zonedSchedule).
//
// Platform setup:
//   Android: requires POST_NOTIFICATIONS runtime permission on API 33+ and
//            SCHEDULE_EXACT_ALARM on API 31+ for exact firing.
//   iOS:     requires the user to grant alert+sound permission on first launch.
//
// Add to pubspec.yaml:
//   flutter_local_notifications: ^17.2.1
//   timezone: ^0.9.4
// =============================================================================

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../features/mosques/data/models/mosque_model.dart';
import '../../features/mosques/data/models/prayer_timing.dart';

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Notification ID range — keep ours in a single bucket so we can cancel cleanly
  static const int _idBase = 10000;

  static const _androidChannel = AndroidNotificationChannel(
    'ummah_prayer_times',
    'Prayer Time Alerts',
    description: 'Notifications for the five daily prayers from your home mosque.',
    importance:  Importance.high,
  );

  // -------------------------------------------------------------------------
  // Initialization — call once at app start
  // -------------------------------------------------------------------------

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    // Best-effort: fall back to UTC if timezone lookup fails on this platform
    try {
      tz.setLocalLocation(tz.getLocation(tz.local.name));
    } catch (_) {
      // local is already initialized by initializeTimeZones; nothing more to do
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit     = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS:     iosInit,
    );

    await _plugin.initialize(initSettings);
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    _initialized = true;
  }

  // -------------------------------------------------------------------------
  // Permission request — call on the onboarding "allow" path
  // -------------------------------------------------------------------------

  Future<bool> requestPermissions() async {
    final iosGranted = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    final androidGranted = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    return iosGranted ?? androidGranted ?? false;
  }

  // -------------------------------------------------------------------------
  // Schedule — wipes & re-schedules ALL pending prayer alerts
  // -------------------------------------------------------------------------

  /// Schedules a notification 5 minutes before each verified prayer for the
  /// next [daysAhead] days at the given [mosque].
  Future<void> schedulePrayerAlerts({
    required Mosque             mosque,
    required List<PrayerTiming> timings,
    int                         daysAhead    = 7,
    int                         minutesBefore = 5,
  }) async {
    if (!_initialized) await init();

    // Wipe previous Ummah notifications
    await cancelAll();

    final now = DateTime.now();
    int notificationId = _idBase;

    for (final timing in timings.take(daysAhead)) {
      final date = timing.effectiveDate;

      for (final prayer in timing.dailyPrayers) {
        // Skip the informational "Sunrise" entry
        if (prayer.name == 'Sunrise') continue;

        final tod = prayer.time.toTimeOfDay();
        if (tod == null) continue;

        // Compose civil DateTime; subtract the lead-time
        final fireAt = DateTime(
          date.year, date.month, date.day,
          tod.hour, tod.minute,
        ).subtract(Duration(minutes: minutesBefore));

        if (fireAt.isBefore(now)) continue;

        await _plugin.zonedSchedule(
          notificationId++,
          '${prayer.name} in $minutesBefore min',
          '${prayer.time} at ${mosque.name}',
          tz.TZDateTime.from(fireAt, tz.local),
          NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannel.id,
              _androidChannel.name,
              channelDescription: _androidChannel.description,
              importance:         Importance.high,
              priority:           Priority.high,
              category:           AndroidNotificationCategory.reminder,
            ),
            iOS: const DarwinNotificationDetails(
              presentSound: true,
              presentAlert: true,
              interruptionLevel: InterruptionLevel.timeSensitive,
            ),
          ),
          androidScheduleMode:        AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents:    null,
          payload:                    'prayer:${prayer.name}:${mosque.id}',
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Cancel all Ummah notifications (does not touch other apps)
  // -------------------------------------------------------------------------

  Future<void> cancelAll() async {
    if (!_initialized) await init();
    await _plugin.cancelAll();
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

final notificationServiceProvider = Provider<NotificationService>(
  (_) => NotificationService.instance,
  name: 'notificationServiceProvider',
);
