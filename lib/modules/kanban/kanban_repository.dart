import '../../core/data/data_store.dart';
import 'kanban_model.dart';

/// Операции над проектами, колонками и задачами.
/// Все изменения идут через [DataStore], поэтому попадают в журнал
/// и будут синхронизироваться между устройствами.
class KanbanRepository {
  KanbanRepository(this.store);

  final DataStore store;

  static const defaultColumns = ['К выполнению', 'В работе', 'Готово'];
  static const _step = 1024.0;

  // ---------- Чтение ----------

  List<Project> projects() =>
      store.all(KanbanEntities.project).map(Project.fromRecord).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  Project? project(String id) {
    final r = store.get(KanbanEntities.project, id);
    return r == null ? null : Project.fromRecord(r);
  }

  List<BoardColumn> columns(String projectId) => store
      .all(KanbanEntities.column)
      .map(BoardColumn.fromRecord)
      .where((c) => c.projectId == projectId)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  /// Задачи проекта. Задачи из удалённых колонок не возвращаются.
  List<Task> tasks(String projectId) {
    final columnIds = columns(projectId).map((c) => c.id).toSet();
    return store
        .all(KanbanEntities.task)
        .map(Task.fromRecord)
        .where((t) => t.projectId == projectId && columnIds.contains(t.columnId))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  List<Task> columnTasks(String columnId) => store
      .all(KanbanEntities.task)
      .map(Task.fromRecord)
      .where((t) => t.columnId == columnId)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  Task? task(String id) {
    final r = store.get(KanbanEntities.task, id);
    return r == null ? null : Task.fromRecord(r);
  }

  // ---------- Проекты ----------

  Future<String> createProject(String name, {String description = ''}) async {
    final id = store.newId();
    final last = projects().lastOrNull;
    await store.writeAll([
      (
        entity: KanbanEntities.project,
        id: id,
        fields: {
          'name': name,
          'description': description,
          'order': (last?.order ?? 0) + _step,
        },
      ),
      for (var i = 0; i < defaultColumns.length; i++)
        (
          entity: KanbanEntities.column,
          id: store.newId(),
          fields: {
            'projectId': id,
            'name': defaultColumns[i],
            'order': (i + 1) * _step,
          },
        ),
    ]);
    return id;
  }

  Future<void> updateProject(String id, {String? name, String? description}) =>
      store.write(KanbanEntities.project, id, {
        'name': ?name,
        'description': ?description,
      });

  /// Удаляет проект вместе с колонками и задачами.
  Future<void> deleteProject(String id) {
    final cols = columns(id);
    final colIds = cols.map((c) => c.id).toSet();
    final taskIds = store
        .all(KanbanEntities.task)
        .where((r) =>
            r.get<String>('projectId') == id ||
            colIds.contains(r.get<String>('columnId')))
        .map((r) => r.id);
    return store.writeAll([
      for (final t in taskIds) _tombstone(KanbanEntities.task, t),
      for (final c in cols) _tombstone(KanbanEntities.column, c.id),
      _tombstone(KanbanEntities.project, id),
    ]);
  }

  // ---------- Колонки ----------

  Future<String> addColumn(String projectId, String name) async {
    final id = store.newId();
    final last = columns(projectId).lastOrNull;
    await store.write(KanbanEntities.column, id, {
      'projectId': projectId,
      'name': name,
      'order': (last?.order ?? 0) + _step,
    });
    return id;
  }

  Future<void> renameColumn(String id, String name) =>
      store.write(KanbanEntities.column, id, {'name': name});

  /// Удаляет колонку вместе с её задачами.
  Future<void> deleteColumn(String id) => store.writeAll([
        for (final t in columnTasks(id)) _tombstone(KanbanEntities.task, t.id),
        _tombstone(KanbanEntities.column, id),
      ]);

  // ---------- Задачи ----------

  Future<String> createTask({
    required String projectId,
    required String columnId,
    required String title,
    String category = '',
    String description = '',
    TaskPriority priority = TaskPriority.normal,
    DateTime? due,
  }) async {
    final id = store.newId();
    final last = columnTasks(columnId).lastOrNull;
    await store.write(KanbanEntities.task, id, {
      'projectId': projectId,
      'columnId': columnId,
      'title': title,
      'category': category,
      'description': description,
      'priority': priority.name,
      'due': due == null ? null : encodeDate(due),
      'order': (last?.order ?? 0) + _step,
    });
    return id;
  }

  /// Записывает только изменившиеся поля — так правки одной задачи
  /// с разных устройств не затирают друг друга.
  Future<void> updateTask(Task before, Task after) {
    final fields = <String, Object?>{
      if (before.title != after.title) 'title': after.title,
      if (before.category != after.category) 'category': after.category,
      if (before.description != after.description)
        'description': after.description,
      if (before.priority != after.priority) 'priority': after.priority.name,
      if (before.due != after.due)
        'due': after.due == null ? null : encodeDate(after.due!),
    };
    final moved = before.columnId != after.columnId;
    if (moved) {
      fields['columnId'] = after.columnId;
      fields['order'] = _orderAtEnd(after.columnId, excluding: after.id);
    }
    if (fields.isEmpty) return Future.value();
    return store.write(KanbanEntities.task, after.id, fields);
  }

  /// Перемещает задачу в колонку [columnId] перед задачей [beforeTaskId]
  /// (или в конец колонки, если null).
  Future<void> moveTask(String taskId, String columnId, {String? beforeTaskId}) {
    if (taskId == beforeTaskId) return Future.value();
    final list = columnTasks(columnId).where((t) => t.id != taskId).toList();
    double order;
    final index =
        beforeTaskId == null ? -1 : list.indexWhere((t) => t.id == beforeTaskId);
    if (index < 0) {
      order = (list.lastOrNull?.order ?? 0) + _step;
    } else {
      final next = list[index].order;
      final prev = index == 0 ? next - _step : list[index - 1].order;
      order = (prev + next) / 2;
    }
    return store.write(KanbanEntities.task, taskId, {
      'columnId': columnId,
      'order': order,
    });
  }

  Future<void> deleteTask(String id) => store.delete(KanbanEntities.task, id);

  double _orderAtEnd(String columnId, {String? excluding}) {
    final list = columnTasks(columnId).where((t) => t.id != excluding);
    return (list.lastOrNull?.order ?? 0) + _step;
  }

  Change _tombstone(String entity, String id) =>
      (entity: entity, id: id, fields: const {'_deleted': true});
}
