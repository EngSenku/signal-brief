import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Wraps a single repeating "your digest is ready" notification.
class Notifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Called when the user taps the daily notification.
  VoidCallback? onOpenBrief;

  static const int _id = 1;

  Future<void> init({VoidCallback? onOpenBrief}) async {
    this.onOpenBrief = onOpenBrief;
    if (kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      try {
        final info = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(info.identifier));
      } catch (e) {
        debugPrint('tz lookup failed, using default: $e');
      }

      const android = AndroidInitializationSettings('@drawable/ic_stat_signal');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (_) => onOpenBrief?.call(),
      );
      _ready = true;
    } catch (e) {
      debugPrint('notification init failed: $e');
    }
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return (await android.requestNotificationsPermission()) ?? false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return (await ios.requestPermissions(
                alert: true, badge: true, sound: true)) ??
            false;
      }
    } catch (e) {
      debugPrint('permission request failed: $e');
    }
    return false;
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_digest',
      'Daily digest',
      channelDescription: 'A once-a-day nudge that your brief is ready.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_stat_signal',
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  /// Schedule (or reschedule) the daily alert for [time] local.
  Future<void> scheduleDaily(TimeOfDay time) async {
    if (!_ready) return;
    await cancel();
    try {
      final now = tz.TZDateTime.now(tz.local);
      var when = tz.TZDateTime(
          tz.local, now.year, now.month, now.day, time.hour, time.minute);
      if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: _id,
        title: 'Your digest is ready',
        body: 'About 24 things worth your time. Finite, filtered, done.',
        scheduledDate: when,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'brief',
      );
    } catch (e) {
      debugPrint('schedule failed: $e');
    }
  }

  Future<void> cancel() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _id);
    } catch (_) {}
  }
}
