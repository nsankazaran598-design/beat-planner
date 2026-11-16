import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/module/app_module.dart';
import '../../core/router.dart';
import 'reminders_page.dart';
import 'reminders_providers.dart';

class RemindersModule extends AppModule {
  const RemindersModule();

  @override
  String get id => 'reminders';
  @override
  String get title => 'Напоминания';
  @override
  String get description => 'Уведомления о делах на Android и Windows';

  @override
  List<ModuleDestination> get destinations => [
        ModuleDestination(
          path: '/reminders',
          label: 'Напоминания',
          shortLabel: 'Напомин.',
          icon: Icons.notifications_none,
          selectedIcon: Icons.notifications,
          order: 30,
          badge: todayRemindersCountProvider,
          builder: (_) => const RemindersPage(),
        ),
      ];

  @override
  Future<void> init(ProviderContainer container) async {
    final backend = container.read(notificationBackendProvider);
    try {
      await backend.init();
    } catch (e) {
      debugPrint('notifications init failed: $e');
      return;
    }
    // Запускаем планировщик; дальше он сам следит за изменениями.
    container.read(reminderSchedulerProvider);
    // Нажатие на уведомление открывает нужный экран.
    backend.taps.listen((route) => container.read(routerProvider).go(route));
  }
}
