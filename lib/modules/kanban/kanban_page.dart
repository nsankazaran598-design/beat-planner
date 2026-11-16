import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/shell/breakpoints.dart';
import '../../core/shell/page_scaffold.dart';
import 'kanban_model.dart';
import 'kanban_providers.dart';
import 'widgets/board_view.dart';
import 'widgets/project_actions.dart';
import 'widgets/task_editor.dart';

class KanbanPage extends ConsumerWidget {
  const KanbanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider);
    final compact = Breakpoints.of(context) == LayoutSize.compact;

    if (project == null) {
      return PageScaffold(
        breadcrumb: 'Рабочее пространство / Проекты',
        title: 'Проекты',
        body: _EmptyProjects(onCreate: () => createProjectFlow(context)),
      );
    }

    // На телефоне задачу добавляет плавающая кнопка оболочки.
    final addTask = compact
        ? null
        : FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => showTaskEditor(context, projectId: project.id),
            icon: const Icon(Icons.add),
            label: const Text('Добавить задачу'),
          );

    return PageScaffold(
      breadcrumb: 'Рабочее пространство / Проекты',
      title: project.name,
      titleTrailing: _ProjectMenu(project: project),
      subtitle: project.description.isEmpty ? null : project.description,
      action: addTask,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Filters(),
          const SizedBox(height: 20),
          Expanded(child: BoardView(project: project)),
        ],
      ),
    );
  }
}

class _ProjectMenu extends ConsumerWidget {
  const _ProjectMenu({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    return PopupMenuButton<String>(
      tooltip: 'Проекты',
      icon: const Icon(Icons.expand_more),
      onSelected: (v) {
        switch (v) {
          case '_new':
            createProjectFlow(context);
          case '_edit':
            editProjectFlow(context, project);
          case '_delete':
            deleteProjectFlow(context, project);
          default:
            ref.read(selectedProjectIdProvider.notifier).select(v);
        }
      },
      itemBuilder: (_) => [
        for (final p in projects)
          CheckedPopupMenuItem(value: p.id, checked: p.id == project.id, child: Text(p.name)),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '_new',
          child: ListTile(leading: Icon(Icons.add), title: Text('Новый проект')),
        ),
        const PopupMenuItem(
          value: '_edit',
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Изменить проект')),
        ),
        const PopupMenuItem(
          value: '_delete',
          child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Удалить проект')),
        ),
      ],
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(kanbanFilterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in KanbanFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(f.label),
                selected: f == current,
                onSelected: (_) => ref.read(kanbanFilterProvider.notifier).set(f),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.view_kanban_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Пока нет проектов', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Создайте первый проект — в нём сразу будут колонки\n«К выполнению», «В работе» и «Готово».',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Создать проект'),
          ),
        ],
      ),
    );
  }
}
