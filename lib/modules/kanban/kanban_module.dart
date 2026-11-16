import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/module/app_module.dart';
import 'kanban_page.dart';
import 'kanban_providers.dart';
import 'widgets/project_actions.dart';
import 'widgets/task_editor.dart';

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
          builder: (_) => const KanbanPage(),
        ),
      ];

  @override
  WidgetBuilder? get sidebarSection => (_) => const ProjectsSidebarSection();

  @override
  Future<void> Function(BuildContext context)? get quickAdd => (context) async {
        final project = ProviderScope.containerOf(context, listen: false)
            .read(currentProjectProvider);
        if (project == null) {
          await createProjectFlow(context);
        } else {
          await showTaskEditor(context, projectId: project.id);
        }
      };
}
