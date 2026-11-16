import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/dialogs.dart';
import '../../../core/ui/format.dart';
import '../kanban_model.dart';
import '../kanban_providers.dart';

/// Открывает редактор задачи. Без [task] — создание новой задачи
/// в колонке [columnId] (или в первой колонке проекта).
Future<void> showTaskEditor(
  BuildContext context, {
  required String projectId,
  Task? task,
  String? columnId,
}) =>
    showAdaptiveSheet<void>(
      context,
      (_) => TaskEditor(projectId: projectId, task: task, columnId: columnId),
    );

class TaskEditor extends ConsumerStatefulWidget {
  const TaskEditor({
    super.key,
    required this.projectId,
    this.task,
    this.columnId,
  });

  final String projectId;
  final Task? task;
  final String? columnId;

  @override
  ConsumerState<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<TaskEditor> {
  late final _title = TextEditingController(text: widget.task?.title);
  late final _category = TextEditingController(text: widget.task?.category);
  late final _description = TextEditingController(text: widget.task?.description);
  late TaskPriority _priority = widget.task?.priority ?? TaskPriority.normal;
  late DateTime? _due = widget.task?.due;
  String? _columnId;

  bool get _isNew => widget.task == null;

  @override
  void initState() {
    super.initState();
    _columnId = widget.task?.columnId ?? widget.columnId;
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _category.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _columnId == null) return;
    final repo = ref.read(kanbanRepositoryProvider);
    final old = widget.task;
    if (old == null) {
      await repo.createTask(
        projectId: widget.projectId,
        columnId: _columnId!,
        title: title,
        category: _category.text.trim(),
        description: _description.text.trim(),
        priority: _priority,
        due: _due,
      );
    } else {
      await repo.updateTask(
        old,
        Task(
          id: old.id,
          projectId: old.projectId,
          columnId: _columnId!,
          title: title,
          category: _category.text.trim(),
          description: _description.text.trim(),
          priority: _priority,
          due: _due,
          order: old.order,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(context, title: 'Удалить задачу?');
    if (!ok) return;
    await ref.read(kanbanRepositoryProvider).deleteTask(widget.task!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _due = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final columns = ref.watch(columnsProvider(widget.projectId));
    _columnId ??= columns.firstOrNull?.id;
    if (columns.isNotEmpty && !columns.any((c) => c.id == _columnId)) {
      _columnId = columns.first.id;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_isNew ? 'Новая задача' : 'Задача', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 20),
          TextField(
            controller: _title,
            autofocus: _isNew,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _category,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Категория',
              hintText: 'Исследование, Дизайн, Разработка…',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Описание'),
          ),
          const SizedBox(height: 20),
          Text('Приоритет', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<TaskPriority>(
            showSelectedIcon: false,
            segments: [
              for (final p in TaskPriority.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDue,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(_due == null ? 'Без срока' : 'Срок: ${formatDayMonth(_due!)}'),
                ),
              ),
              if (_due != null)
                IconButton(
                  tooltip: 'Убрать срок',
                  onPressed: () => setState(() => _due = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownMenu<String>(
            key: ValueKey(_columnId),
            initialSelection: _columnId,
            expandedInsets: EdgeInsets.zero,
            label: const Text('Колонка'),
            onSelected: (v) => setState(() => _columnId = v),
            dropdownMenuEntries: [
              for (final c in columns) DropdownMenuEntry(value: c.id, label: c.name),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (!_isNew)
                TextButton.icon(
                  onPressed: _delete,
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить'),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _title.text.trim().isEmpty ? null : _save,
                child: Text(_isNew ? 'Добавить' : 'Сохранить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
