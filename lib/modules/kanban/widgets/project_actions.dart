import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/dialogs.dart';
import '../kanban_model.dart';
import '../kanban_providers.dart';

ProviderContainer _container(BuildContext context) =>
    ProviderScope.containerOf(context, listen: false);

Future<void> createProjectFlow(BuildContext context) async {
  final r = await promptText(context,
      title: 'Новый проект',
      labels: const ['Название', 'Описание'],
      action: 'Создать');
  if (r == null || !context.mounted) return;
  final c = _container(context);
  final id = await c
      .read(kanbanRepositoryProvider)
      .createProject(r[0], description: r[1]);
  await c.read(selectedProjectIdProvider.notifier).select(id);
}

Future<void> editProjectFlow(BuildContext context, Project p) async {
  final r = await promptText(context,
      title: 'Проект',
      labels: const ['Название', 'Описание'],
      initial: [p.name, p.description]);
  if (r == null || !context.mounted) return;
  await _container(context)
      .read(kanbanRepositoryProvider)
      .updateProject(p.id, name: r[0], description: r[1]);
}

Future<void> deleteProjectFlow(BuildContext context, Project p) async {
  final ok = await confirm(context,
      title: 'Удалить проект «${p.name}»?',
      message: 'Все колонки и задачи проекта будут удалены.');
  if (!ok || !context.mounted) return;
  await _container(context).read(kanbanRepositoryProvider).deleteProject(p.id);
}

/// Секция «Мои проекты» в боковом меню десктопа.
class ProjectsSidebarSection extends ConsumerWidget {
  const ProjectsSidebarSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final projects = ref.watch(projectsProvider);
    final current = ref.watch(currentProjectProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 0, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('МОИ ПРОЕКТЫ',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              IconButton(
                tooltip: 'Новый проект',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: () => createProjectFlow(context),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        for (final p in projects)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              ref.read(selectedProjectIdProvider.notifier).select(p.id);
              context.go('/kanban');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                p.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: p.id == current?.id ? scheme.primary : scheme.onSurface,
                  fontWeight: p.id == current?.id ? FontWeight.w500 : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
