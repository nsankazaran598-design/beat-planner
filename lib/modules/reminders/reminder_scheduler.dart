import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/reminders/reminder.dart';
import 'notification_backend.dart';

/// Превращает список напоминаний в уведомления.
///
/// * Если система умеет планировать (Android) — регистрирует уведомления
///   в системе на ближайшие [window] и поддерживает их в актуальном виде.
/// * Иначе (Windows) — держит таймер до ближайшего напоминания и
///   показывает уведомление сам, пока приложение работает (в т.ч. в трее).
class ReminderScheduler {
  ReminderScheduler(this.backend, {DateTime Function()? now})
      : _now = now ?? DateTime.now {
    _startedAt = _now();
  }

  final NotificationBackend backend;
  final DateTime Function() _now;
  late final DateTime _startedAt;

  static const window = Duration(days: 14);
  static const maxScheduled = 64;

  /// Напоминания, пропущенные незадолго до запуска, всё равно показываются.
  static const missedGrace = Duration(minutes: 10);

  final Map<String, Reminder> _scheduled = {};
  final Set<String> _shown = {};
  List<Reminder> _pending = const [];
  Timer? _timer;
  bool _clearedOnStart = false;
  Future<void> _queue = Future.value();

  /// Ключи, зарегистрированные в системе (для тестов и отладки).
  @visibleForTesting
  Set<String> get scheduledKeys => _scheduled.keys.toSet();

  /// Синхронизирует уведомления со списком. Вызовы выполняются по очереди.
  Future<void> sync(List<Reminder> all, {required bool enabled}) =>
      _queue = _queue.then((_) => _sync(all, enabled)).catchError((Object e) {
        debugPrint('reminders sync failed: $e');
      });

  Future<void> _sync(List<Reminder> all, bool enabled) async {
    final now = _now();
    if (backend.supportsScheduling) {
      if (!_clearedOnStart) {
        // Удаляем запланированное прошлым запуском: часть дел могла измениться.
        await backend.cancelAll();
        _clearedOnStart = true;
      }
      final wanted = <String, Reminder>{
        if (enabled)
          for (final r in all
              .where((r) => r.at.isAfter(now) && r.at.isBefore(now.add(window)))
              .take(maxScheduled))
            r.key: r,
      };
      for (final e in [..._scheduled.entries]) {
        if (wanted[e.key] != e.value) {
          await backend.cancel(e.value.notificationId);
          _scheduled.remove(e.key);
        }
      }
      for (final r in wanted.values) {
        if (_scheduled[r.key] != r) {
          await backend.schedule(r);
          _scheduled[r.key] = r;
        }
      }
      return;
    }

    _timer?.cancel();
    if (!enabled) {
      _pending = const [];
      return;
    }
    final earliest = _startedAt.subtract(missedGrace);
    _pending = [
      for (final r in all)
        if (r.at.isAfter(earliest) && !_shown.contains(_shownKey(r))) r,
    ];
    await checkDue();
  }

  /// Показывает наступившие напоминания и заводит таймер до следующего.
  @visibleForTesting
  Future<void> checkDue() async {
    _timer?.cancel();
    final now = _now();
    final due = _pending.where((r) => !r.at.isAfter(now)).toList();
    for (final r in due) {
      _shown.add(_shownKey(r));
      await backend.show(r);
    }
    _pending = _pending.where((r) => r.at.isAfter(now)).toList();
    if (_pending.isEmpty) return;
    final next = _pending.map((r) => r.at).reduce((a, b) => a.isBefore(b) ? a : b);
    // Не дольше часа: на случай сна компьютера и перевода часов.
    var wait = next.difference(now);
    if (wait > const Duration(hours: 1)) wait = const Duration(hours: 1);
    _timer = Timer(wait + const Duration(milliseconds: 200), () => checkDue());
  }

  void dispose() => _timer?.cancel();

  static String _shownKey(Reminder r) => '${r.key}@${r.at.millisecondsSinceEpoch}';
}
