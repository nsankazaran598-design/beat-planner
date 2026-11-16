import 'dart:async';

import 'package:beat/core/reminders/reminder.dart';
import 'package:beat/modules/reminders/notification_backend.dart';
import 'package:beat/modules/reminders/reminder_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBackend implements NotificationBackend {
  FakeBackend({required this.supportsScheduling});

  @override
  final bool supportsScheduling;
  final shown = <String>[];
  final scheduled = <int, Reminder>{};
  var cancelAllCalls = 0;

  @override
  Stream<String> get taps => const Stream.empty();
  @override
  Future<void> init() async {}
  @override
  Future<NotificationPermissions> permissions() async =>
      const NotificationPermissions(notifications: true, exactAlarms: true);
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<void> show(Reminder r) async => shown.add(r.key);
  @override
  Future<void> schedule(Reminder r) async => scheduled[r.notificationId] = r;
  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    scheduled.clear();
  }
}

Reminder r(String key, DateTime at, {String title = 't'}) =>
    Reminder(key: key, title: title, body: '', at: at, route: '/day');

void main() {
  final t0 = DateTime(2026, 11, 16, 12, 0);

  group('scheduling backend (Android)', () {
    test('schedules future reminders and skips past ones', () async {
      final b = FakeBackend(supportsScheduling: true);
      final s = ReminderScheduler(b, now: () => t0);
      await s.sync([
        r('past', t0.subtract(const Duration(minutes: 5))),
        r('a', t0.add(const Duration(minutes: 30))),
        r('far', t0.add(const Duration(days: 30))),
      ], enabled: true);
      expect(b.cancelAllCalls, 1);
      expect(s.scheduledKeys, {'a'});
      expect(b.scheduled.values.map((x) => x.key), ['a']);
    });

    test('reschedules changed and cancels removed reminders', () async {
      final b = FakeBackend(supportsScheduling: true);
      final s = ReminderScheduler(b, now: () => t0);
      final a = r('a', t0.add(const Duration(hours: 1)));
      final c = r('c', t0.add(const Duration(hours: 2)));
      await s.sync([a, c], enabled: true);

      final aMoved = r('a', t0.add(const Duration(hours: 3)));
      await s.sync([aMoved], enabled: true);
      expect(s.scheduledKeys, {'a'});
      expect(b.scheduled[aMoved.notificationId]!.at, aMoved.at);
      expect(b.scheduled.containsKey(c.notificationId), isFalse);
      expect(b.cancelAllCalls, 1, reason: 'cancelAll only on first sync');
    });

    test('disabling cancels everything', () async {
      final b = FakeBackend(supportsScheduling: true);
      final s = ReminderScheduler(b, now: () => t0);
      await s.sync([r('a', t0.add(const Duration(hours: 1)))], enabled: true);
      await s.sync([r('a', t0.add(const Duration(hours: 1)))], enabled: false);
      expect(b.scheduled, isEmpty);
    });
  });

  group('timer backend (Windows)', () {
    test('shows due reminders once and waits for the next', () async {
      var now = t0;
      final b = FakeBackend(supportsScheduling: false);
      final s = ReminderScheduler(b, now: () => now);
      await s.sync([
        r('missed_recently', t0.subtract(const Duration(minutes: 3))),
        r('missed_long_ago', t0.subtract(const Duration(hours: 2))),
        r('soon', t0.add(const Duration(minutes: 15))),
      ], enabled: true);
      expect(b.shown, ['missed_recently']);

      now = t0.add(const Duration(minutes: 16));
      await s.checkDue();
      expect(b.shown, ['missed_recently', 'soon']);

      // Повторная синхронизация не показывает уже показанное.
      await s.sync([r('soon', t0.add(const Duration(minutes: 15)))], enabled: true);
      expect(b.shown, ['missed_recently', 'soon']);
      s.dispose();
    });

    test('a moved reminder fires again at the new time', () async {
      var now = t0;
      final b = FakeBackend(supportsScheduling: false);
      final s = ReminderScheduler(b, now: () => now);
      await s.sync([r('a', t0.add(const Duration(minutes: 1)))], enabled: true);
      now = t0.add(const Duration(minutes: 2));
      await s.checkDue();
      await s.sync([r('a', t0.add(const Duration(minutes: 10)))], enabled: true);
      now = t0.add(const Duration(minutes: 11));
      await s.checkDue();
      expect(b.shown, ['a', 'a']);
      s.dispose();
    });

    test('disabled shows nothing', () async {
      final b = FakeBackend(supportsScheduling: false);
      final s = ReminderScheduler(b, now: () => t0);
      await s.sync([r('a', t0.subtract(const Duration(minutes: 1)))], enabled: false);
      expect(b.shown, isEmpty);
      s.dispose();
    });
  });

  test('notification ids are stable and positive', () {
    final a = r('day_item:abc', t0);
    expect(a.notificationId, r('day_item:abc', t0.add(const Duration(days: 1))).notificationId);
    expect(a.notificationId, greaterThanOrEqualTo(0));
    expect(a.notificationId, isNot(r('day_item:abd', t0).notificationId));
  });

  test('timer is armed for the next reminder', () {
    // Smoke: scheduler with a pending reminder keeps a timer that dispose() cancels.
    final b = FakeBackend(supportsScheduling: false);
    final s = ReminderScheduler(b, now: () => t0);
    unawaited(s.sync([r('x', t0.add(const Duration(hours: 5)))], enabled: true));
    s.dispose();
  });
}
