import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../module/module_registry.dart';

/// Напоминание, которое модуль просит показать.
class Reminder {
  const Reminder({
    required this.key,
    required this.title,
    required this.body,
    required this.at,
    required this.route,
  });

  /// Стабильный ключ, например `day_item:abc123`.
  final String key;
  final String title;
  final String body;

  /// Когда показать уведомление.
  final DateTime at;

  /// Куда перейти при нажатии на уведомление.
  final String route;

  /// Целочисленный id для системы уведомлений (FNV-1a, 31 бит).
  int get notificationId {
    var h = 0x811c9dc5;
    for (final c in key.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.key == key &&
      other.title == title &&
      other.body == body &&
      other.at == at &&
      other.route == route;

  @override
  int get hashCode => Object.hash(key, title, body, at, route);
}

/// Напоминания всех включённых модулей, по времени.
final allRemindersProvider = Provider<List<Reminder>>((ref) {
  final list = [
    for (final m in ref.watch(enabledModulesProvider))
      if (m.reminders != null) ...ref.watch(m.reminders!),
  ]..sort((a, b) => a.at.compareTo(b.at));
  return list;
});
