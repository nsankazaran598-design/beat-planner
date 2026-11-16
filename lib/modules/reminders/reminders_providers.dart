import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/reminders/reminder.dart';
import '../../core/settings/settings_controller.dart';
import 'notification_backend.dart';
import 'reminder_scheduler.dart';

bool get _underTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

/// Платформенные уведомления. В тестах — заглушка.
final notificationBackendProvider = Provider<NotificationBackend>((ref) {
  if (kIsWeb || _underTest || !(Platform.isAndroid || Platform.isWindows)) {
    return NoopNotificationBackend();
  }
  return LocalNotificationBackend();
});

/// Глобальный выключатель напоминаний (на этом устройстве).
final remindersEnabledProvider =
    NotifierProvider<RemindersEnabledController, bool>(RemindersEnabledController.new);

class RemindersEnabledController extends Notifier<bool> {
  static const _key = 'reminders.enabled';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? true;

  Future<void> set(bool v) async {
    state = v;
    await ref.read(sharedPreferencesProvider).setBool(_key, v);
  }
}

/// Планировщик, который следит за напоминаниями всех модулей.
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  final scheduler = ReminderScheduler(ref.watch(notificationBackendProvider));
  void sync() => scheduler.sync(
        ref.read(allRemindersProvider),
        enabled: ref.read(remindersEnabledProvider),
      );
  ref.listen(allRemindersProvider, (_, _) => sync());
  ref.listen(remindersEnabledProvider, (_, _) => sync());
  sync();
  // Окно планирования сдвигается со временем — пересинхронизируемся.
  final refresh = Timer.periodic(const Duration(hours: 6), (_) => sync());
  ref.onDispose(() {
    refresh.cancel();
    scheduler.dispose();
  });
  return scheduler;
});

/// Сколько напоминаний ещё осталось сегодня — для счётчика в меню.
final todayRemindersCountProvider = Provider<int>((ref) {
  final now = DateTime.now();
  return ref
      .watch(allRemindersProvider)
      .where((r) =>
          r.at.isAfter(now) &&
          r.at.year == now.year &&
          r.at.month == now.month &&
          r.at.day == now.day)
      .length;
});

/// Состояние разрешений; обновляется через invalidate.
final notificationPermissionsProvider = FutureProvider<NotificationPermissions>(
  (ref) => ref.watch(notificationBackendProvider).permissions(),
);
