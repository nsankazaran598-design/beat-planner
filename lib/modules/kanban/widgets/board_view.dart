import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/shell/breakpoints.dart';
import '../../../core/ui/dialogs.dart';
import '../kanban_model.dart';
import '../kanban_providers.dart';
import 'task_card.dart';
import 'task_editor.dart';

/// Доска проекта: колонки с карточками, перетаскивание между колонками.
class BoardView extends ConsumerStatefulWidget {
  const BoardView({super.key, required this.project});

  final Project project;

  @override
  ConsumerState<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends ConsumerState<BoardView> {
  final _horizontal = ScrollController();
  final _pages = PageController(viewportFraction: 0.9);

  @override
  void dispose() {
    _horizontal.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final columns = ref.watch(columnsProvider(project.id));
    final tasks = ref.watch(boardTasksProvider(project.id));
    final compact = Breakpoints.of(context) == LayoutSize.compact;

    Widget column(BoardColumn c, double width) => _ColumnView(
          key: ValueKey(c.id),
          project: project,
          column: c,
          tasks: tasks[c.id] ?? const [],
          width: width,
          isLast: c.id == columns.last.id,
        );

    if (compact) {
      return LayoutBuilder(builder: (context, box) {
        return PageView(
          controller: _pages,
          padEnds: false,
          children: [
            for (final c in columns)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: column(c, double.infinity),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Align(
                alignment: Alignment.topCenter,
                child: _AddColumnButton(projectId: project.id),
              ),
            ),
          ],
        );
      });
    }

    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      child: ListView(
        controller: _horizontal,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          for (final c in columns) ...[column(c, 270), const SizedBox(width: 12)],
          Align(
            alignment: Alignment.topLeft,
            child: _AddColumnButton(projectId: project.id),
          ),
        ],
      ),
    );
  }
}

class _AddColumnButton extends ConsumerWidget {
  const _AddColumnButton({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () async {
        final r = await promptText(context,
            title: 'Новая колонка', labels: const ['Название'], action: 'Добавить');
        if (r != null) {
          await ref.read(kanbanRepositoryProvider).addColumn(projectId, r[0]);
        }
      },
      icon: const Icon(Icons.add),
      label: const Text('Колонка'),
    );
  }
}

class _ColumnView extends ConsumerStatefulWidget {
  const _ColumnView({
    super.key,
    required this.project,
    required this.column,
    required this.tasks,
    required this.width,
    this.isLast = false,
  });

  final Project project;
  final BoardColumn column;
  final List<Task> tasks;
  final double width;
  final bool isLast;

  @override
  ConsumerState<_ColumnView> createState() => _ColumnViewState();
}

class _ColumnViewState extends ConsumerState<_ColumnView> {
  bool _hoverEnd = false;

  bool get _touch =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _move(String taskId, {String? before}) => ref
      .read(kanbanRepositoryProvider)
      .moveTask(taskId, widget.column.id, beforeTaskId: before);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = widget.column;

    return DragTarget<String>(
      onWillAcceptWithDetails: (_) {
        setState(() => _hoverEnd = true);
        return true;
      },
      onLeave: (_) => setState(() => _hoverEnd = false),
      onAcceptWithDetails: (d) {
        setState(() => _hoverEnd = false);
        _move(d.data);
      },
      builder: (context, candidates, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: widget.width,
        decoration: BoxDecoration(
          color: _hoverEnd ? scheme.surfaceContainerHigh : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(theme),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final t in widget.tasks)
                    _DraggableTask(
                      key: ValueKey(t.id),
                      task: t,
                      width: widget.width == double.infinity ? 300 : widget.width - 20,
                      touch: _touch,
                      done: widget.isLast,
                      onDropBefore: (id) => _move(id, before: t.id),
                      onTap: () => showTaskEditor(context,
                          projectId: widget.project.id, task: t),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => showTaskEditor(context,
                          projectId: widget.project.id, columnId: c.id),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final c = widget.column;
    return Row(
      children: [
        Expanded(
          child: Text(c.name,
              overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
        ),
        Text('${widget.tasks.length}',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        PopupMenuButton<String>(
          tooltip: 'Действия с колонкой',
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (v) async {
            final repo = ref.read(kanbanRepositoryProvider);
            if (v == 'rename') {
              final r = await promptText(context,
                  title: 'Переименовать колонку',
                  labels: const ['Название'],
                  initial: [c.name]);
              if (r != null) await repo.renameColumn(c.id, r[0]);
            } else if (v == 'delete') {
              final ok = await confirm(context,
                  title: 'Удалить колонку «${c.name}»?',
                  message: 'Задачи в этой колонке тоже будут удалены.');
              if (ok) await repo.deleteColumn(c.id);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Переименовать')),
            PopupMenuItem(value: 'delete', child: Text('Удалить')),
          ],
        ),
      ],
    );
  }
}

class _DraggableTask extends StatefulWidget {
  const _DraggableTask({
    super.key,
    required this.task,
    required this.width,
    required this.touch,
    required this.onDropBefore,
    required this.onTap,
    this.done = false,
  });

  final Task task;
  final double width;
  final bool touch;
  final bool done;
  final ValueChanged<String> onDropBefore;
  final VoidCallback onTap;

  @override
  State<_DraggableTask> createState() => _DraggableTaskState();
}

class _DraggableTaskState extends State<_DraggableTask> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = TaskCard(task: widget.task, onTap: widget.onTap, done: widget.done);
    final feedback = Material(
      color: Colors.transparent,
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: widget.width, child: TaskCard(task: widget.task, done: widget.done)),
    );
    final dimmed = Opacity(opacity: 0.35, child: card);

    final draggable = widget.touch
        ? LongPressDraggable<String>(
            data: widget.task.id,
            feedback: feedback,
            childWhenDragging: dimmed,
            child: card,
          )
        : Draggable<String>(
            data: widget.task.id,
            feedback: feedback,
            childWhenDragging: dimmed,
            child: card,
          );

    return DragTarget<String>(
      // Принимаем и собственную карточку, чтобы бросок «на себя» ничего
      // не менял (иначе его перехватит колонка и унесёт задачу в конец).
      onWillAcceptWithDetails: (d) {
        if (d.data != widget.task.id) setState(() => _hover = true);
        return true;
      },
      onLeave: (_) => setState(() => _hover = false),
      onAcceptWithDetails: (d) {
        setState(() => _hover = false);
        if (d.data != widget.task.id) widget.onDropBefore(d.data);
      },
      builder: (context, _, _) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: _hover ? 3 : 0,
              margin: EdgeInsets.only(bottom: _hover ? 8 : 0),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            draggable,
          ],
        ),
      ),
    );
  }
}
