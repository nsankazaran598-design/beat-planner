import 'package:material_ui/material_ui.dart';

import '../../core/module/app_module.dart';
import '../../core/shell/page_scaffold.dart';

class RemindersModule extends AppModule {
  const RemindersModule();

  @override
  String get id => 'reminders';
  @override
  String get title => 'Напоминания';
  @override
  String get description => 'Уведомления о задачах на Android и Windows';

  @override
  List<ModuleDestination> get destinations => [
        ModuleDestination(
          path: '/reminders',
          label: 'Напоминания',
          icon: Icons.notifications_none,
          selectedIcon: Icons.notifications,
          order: 30,
          builder: (_) => const PageScaffold(
            breadcrumb: 'Личное пространство / Напоминания',
            title: 'Напоминания',
            body: ComingSoon(
              icon: Icons.notifications_none,
              text: 'Напоминания появятся в v0.4',
            ),
          ),
        ),
      ];
}
