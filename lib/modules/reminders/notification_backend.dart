import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/reminders/reminder.dart';

/// Состояние разрешений на уведомления.
class NotificationPermissions {
  const NotificationPermissions({required this.notifications, required this.exactAlarms});

  /// null — платформа не спрашивает (Windows).
  final bool? notifications;
  final bool? exactAlarms;
}

/// Платформенная часть уведомлений. В тестах заменяется на фейк.
abstract class NotificationBackend {
  /// Умеет ли система сама показать уведомление в заданное время,
  /// даже когда приложение закрыто (Android). На Windows без MSIX
  /// запланированные уведомления нельзя отменить, поэтому там
  /// напоминания срабатывают по таймеру, пока приложение работает.
  bool get supportsScheduling;

  /// Нажатия на уведомления: маршрут, который нужно открыть.
  Stream<String> get taps;

  Future<void> init();
  Future<NotificationPermissions> permissions();
  Future<void> requestPermissions();
  Future<void> show(Reminder r);
  Future<void> schedule(Reminder r);
  Future<void> cancel(int id);
  Future<void> cancelAll();
}

class NoopNotificationBackend implements NotificationBackend {
  @override
  bool get supportsScheduling => false;
  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Future<void> init() async {}
  @override
  Future<NotificationPermissions> permissions() async =>
      const NotificationPermissions(notifications: null, exactAlarms: null);
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<void> show(Reminder r) async {}
  @override
  Future<void> schedule(Reminder r) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
}

class LocalNotificationBackend implements NotificationBackend {
  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  String? _launchRoute;

  static const _channel = AndroidNotificationDetails(
    'reminders',
    'Напоминания',
    channelDescription: 'Напоминания о делах из «Моего дня»',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    color: Color(0xFF6750A4),
  );

  static const _details = NotificationDetails(
    android: _channel,
    windows: WindowsNotificationDetails(),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  bool get supportsScheduling => Platform.isAndroid;

  @override
  Stream<String> get taps async* {
    // Маршрут, с которым приложение было запущено из уведомления.
    if (_launchRoute != null) {
      yield _launchRoute!;
      _launchRoute = null;
    }
    yield* _taps.stream;
  }

  @override
  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (e) {
      debugPrint('timezone: $e');
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_beat'),
        windows: WindowsInitializationSettings(
          appName: 'beat',
          appUserModelId: 'BeatPlanner.Beat',
          guid: '3f0b8a0e-7c51-4f6e-9a7c-6c3b5b2d9e41',
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload != null) _taps.add(r.payload!);
      },
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      _launchRoute = launch!.notificationResponse?.payload;
    }
  }

  @override
  Future<NotificationPermissions> permissions() async {
    final a = _android;
    if (a == null) {
      return const NotificationPermissions(notifications: null, exactAlarms: null);
    }
    return NotificationPermissions(
      notifications: await a.areNotificationsEnabled(),
      exactAlarms: await a.canScheduleExactNotifications(),
    );
  }

  @override
  Future<void> requestPermissions() async {
    final a = _android;
    if (a == null) return;
    await a.requestNotificationsPermission();
    if (!(await a.canScheduleExactNotifications() ?? true)) {
      await a.requestExactAlarmsPermission();
    }
  }

  @override
  Future<void> show(Reminder r) => _plugin.show(
        id: r.notificationId,
        title: r.title,
        body: r.body,
        notificationDetails: _details,
        payload: r.route,
      );

  @override
  Future<void> schedule(Reminder r) async {
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    await _plugin.zonedSchedule(
      id: r.notificationId,
      scheduledDate: tz.TZDateTime.from(r.at, tz.local),
      notificationDetails: _details,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      title: r.title,
      body: r.body,
      payload: r.route,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();
}
