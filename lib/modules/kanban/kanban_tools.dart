import '../../core/agent/agent_tool.dart';
import '../../core/ui/format.dart';
import 'kanban_model.dart';
import 'kanban_providers.dart';
import 'kanban_repository.dart';

KanbanRepository _repo(Reader read) => read(kanbanRepositoryProvider);

Project _project(KanbanRepository repo, String id) =>
    repo.project(id) ?? (throw ToolError('Проект $id не найден'));

Task _task(KanbanRepository repo, String id) =>
    repo.task(id) ?? (throw ToolError('Задача $id не найдена'));

/// Колонка по id или по названию (без учёта регистра).
BoardColumn _column(KanbanRepository repo, String projectId, String? ref) {
  final cols = repo.columns(projectId);
  if (cols.isEmpty) throw const ToolError('В проекте нет колонок');
  if (ref == null) return cols.first;
  final lower = ref.toLowerCase();
  return cols.firstWhere(
    (c) => c.id == ref || c.name.toLowerCase() == lower,
    orElse: () => throw ToolError(
        'Колонка "$ref" не найдена. Есть: ${cols.map((c) => c.name).join(', ')}'),
  );
}

TaskPriority _priority(String? s) => switch (s) {
      null => TaskPriority.normal,
      'high' => TaskPriority.high,
      'urgent' => TaskPriority.urgent,
      'normal' => TaskPriority.normal,
      _ => throw ToolError('priority: normal, high или urgent'),
    };

DateTime? _date(String? s) {
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  if (d == null) throw ToolError('Дата "$s" не в формате ГГГГ-ММ-ДД');
  return dateOnly(d);
}

Map<String, Object?> _taskJson(Task t, String columnName) => {
      'id': t.id,
      'title': t.title,
      'column': columnName,
      'column_id': t.columnId,
      if (t.category.isNotEmpty) 'category': t.category,
      if (t.description.isNotEmpty) 'description': t.description,
      'priority': t.priority.name,
      if (t.due != null) 'due': encodeDate(t.due!),
    };

final _priorityArg = str('Приоритет', enumValues: ['normal', 'high', 'urgent']);
final _dueArg = str('Срок в формате ГГГГ-ММ-ДД');

final List<AgentTool> kanbanTools = [
  AgentTool(
    name: 'list_projects',
    description: 'Список проектов с колонками и числом задач в каждой колонке.',
    parameters: objectSchema(const {}),
    scope: ToolScope.projects,
    readOnly: true,
    run: (read, _) async {
      final repo = _repo(read);
      return [
        for (final p in repo.projects())
          {
            'id': p.id,
            'name': p.name,
            if (p.description.isNotEmpty) 'description': p.description,
            'columns': [
              for (final c in repo.columns(p.id))
                {'id': c.id, 'name': c.name, 'tasks': repo.columnTasks(c.id).length},
            ],
          },
      ];
    },
  ),
  AgentTool(
    name: 'list_tasks',
    description: 'Задачи проекта по колонкам (в порядке на доске).',
    parameters: objectSchema({'project_id': str('id проекта')}, required: ['project_id']),
    scope: ToolScope.projects,
    readOnly: true,
    run: (read, a) async {
      final repo = _repo(read);
      final p = _project(repo, reqStr(a, 'project_id'));
      final cols = {for (final c in repo.columns(p.id)) c.id: c.name};
      return [for (final t in repo.tasks(p.id)) _taskJson(t, cols[t.columnId] ?? '')];
    },
  ),
  AgentTool(
    name: 'create_project',
    description: 'Создать проект с колонками «К выполнению», «В работе», «Готово».',
    parameters: objectSchema(
      {'name': str('Название'), 'description': str('Описание')},
      required: ['name'],
    ),
    scope: ToolScope.projects,
    readOnly: false,
    summarize: (_, a) => 'Создать проект «${a['name']}»',
    run: (read, a) async {
      final id = await _repo(read)
          .createProject(reqStr(a, 'name'), description: optStr(a, 'description') ?? '');
      return {'project_id': id};
    },
  ),
  AgentTool(
    name: 'create_task',
    description: 'Добавить задачу в проект. Без column — в первую колонку.',
    parameters: objectSchema({
      'project_id': str('id проекта'),
      'title': str('Название задачи'),
      'column': str('Название или id колонки'),
      'category': str('Категория: Исследование, Дизайн, Разработка…'),
      'description': str('Описание'),
      'priority': _priorityArg,
      'due': _dueArg,
    }, required: ['project_id', 'title']),
    scope: ToolScope.projects,
    readOnly: false,
    summarize: (read, a) {
      final p = _repo(read).project('${a['project_id']}');
      return 'Добавить задачу «${a['title']}»${p == null ? '' : ' в «${p.name}»'}';
    },
    run: (read, a) async {
      final repo = _repo(read);
      final p = _project(repo, reqStr(a, 'project_id'));
      final col = _column(repo, p.id, optStr(a, 'column'));
      final id = await repo.createTask(
        projectId: p.id,
        columnId: col.id,
        title: reqStr(a, 'title'),
        category: optStr(a, 'category') ?? '',
        description: optStr(a, 'description') ?? '',
        priority: _priority(optStr(a, 'priority')),
        due: _date(optStr(a, 'due')),
      );
      return {'task_id': id, 'column': col.name};
    },
  ),
  AgentTool(
    name: 'update_task',
    description: 'Изменить поля задачи. Передавайте только то, что меняется; '
        'due: "" — убрать срок.',
    parameters: objectSchema({
      'task_id': str('id задачи'),
      'title': str('Название'),
      'category': str('Категория'),
      'description': str('Описание'),
      'priority': _priorityArg,
      'due': _dueArg,
    }, required: ['task_id']),
    scope: ToolScope.projects,
    readOnly: false,
    summarize: (read, a) {
      final t = _repo(read).task('${a['task_id']}');
      return 'Изменить задачу «${t?.title ?? a['task_id']}»';
    },
    run: (read, a) async {
      final repo = _repo(read);
      final t = _task(repo, reqStr(a, 'task_id'));
      final due = a.containsKey('due') ? _date(optStr(a, 'due')) : t.due;
      await repo.updateTask(
        t,
        Task(
          id: t.id,
          projectId: t.projectId,
          columnId: t.columnId,
          title: optStr(a, 'title') ?? t.title,
          category: a['category'] is String ? (a['category']! as String).trim() : t.category,
          description:
              a['description'] is String ? (a['description']! as String).trim() : t.description,
          priority: a.containsKey('priority') ? _priority(optStr(a, 'priority')) : t.priority,
          due: due,
          order: t.order,
        ),
      );
      return {'ok': true};
    },
  ),
  AgentTool(
    name: 'move_task',
    description: 'Переместить задачу в другую колонку (в конец).',
    parameters: objectSchema(
      {'task_id': str('id задачи'), 'column': str('Название или id колонки')},
      required: ['task_id', 'column'],
    ),
    scope: ToolScope.projects,
    readOnly: false,
    summarize: (read, a) {
      final t = _repo(read).task('${a['task_id']}');
      return 'Переместить «${t?.title ?? a['task_id']}» в «${a['column']}»';
    },
    run: (read, a) async {
      final repo = _repo(read);
      final t = _task(repo, reqStr(a, 'task_id'));
      final col = _column(repo, t.projectId, reqStr(a, 'column'));
      await repo.moveTask(t.id, col.id);
      return {'ok': true, 'column': col.name};
    },
  ),
  AgentTool(
    name: 'delete_task',
    description: 'Удалить задачу.',
    parameters: objectSchema({'task_id': str('id задачи')}, required: ['task_id']),
    scope: ToolScope.projects,
    readOnly: false,
    summarize: (read, a) {
      final t = _repo(read).task('${a['task_id']}');
      return 'Удалить задачу «${t?.title ?? a['task_id']}»';
    },
    run: (read, a) async {
      final repo = _repo(read);
      await repo.deleteTask(_task(repo, reqStr(a, 'task_id')).id);
      return {'ok': true};
    },
  ),
];
