import 'package:material_ui/material_ui.dart';

import '../../../core/ui/format.dart';
import '../kanban_model.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, this.onTap, this.done = false});

  final Task task;
  final VoidCallback? onTap;

  /// Задача в последней колонке («Готово»): срок не подсвечивается.
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);

    final subhead = task.category.isNotEmpty
        ? task.category
        : task.priority != TaskPriority.normal
            ? '${task.priority.label} приоритет'
            : null;

    final now = DateTime.now();
    final overdue = !done && task.due != null && dateOnly(task.due!).isBefore(dateOnly(now));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(task.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium),
                  ),
                  if (task.priority != TaskPriority.normal)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Icon(
                        Icons.flag,
                        size: 18,
                        semanticLabel: '${task.priority.label} приоритет',
                        color: task.priority == TaskPriority.urgent
                            ? scheme.error
                            : scheme.tertiary,
                      ),
                    ),
                ],
              ),
              if (subhead != null) Text(subhead, style: muted),
              if (task.description.isNotEmpty || task.due != null)
                const SizedBox(height: 20),
              if (task.description.isNotEmpty)
                Text(task.description,
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: muted),
              if (task.due != null)
                Text(
                  done ? 'Срок: ${formatDayMonth(task.due!, now: now)}' : formatDue(task.due!, now: now),
                  style: muted?.copyWith(color: overdue ? scheme.error : null),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
