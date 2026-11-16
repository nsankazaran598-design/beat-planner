import 'package:material_ui/material_ui.dart';

import '../../core/module/app_module.dart';
import '../../core/shell/page_scaffold.dart';

class KanbanModule extends AppModule {
  const KanbanModule();

  @override
  String get id => 'kanban';
  @override
  String get title => 'Проекты · Kanban';
  @override
  String get description => 'Доски проектов с колонками и карточками задач';

  @override
  List<ModuleDestination> get destinations => [
        ModuleDestination(
          path: '/kanban',
          label: 'Проекты',
          icon: Icons.view_kanban_outlined,
          selectedIcon: Icons.view_kanban,
          order: 10,
          builder: (_) => const PageScaffold(
            breadcrumb: 'Рабочее пространство / Проекты',
            title: 'Проекты',
            subtitle: 'От идеи до релиза — всё на одной доске',
            body: ComingSoon(
              icon: Icons.view_kanban_outlined,
              text: 'Kanban-доски появятся в v0.2',
            ),
          ),
        ),
      ];
}
