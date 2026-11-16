import 'package:beat/core/data/data_store.dart';
import 'package:beat/core/data/log_storage.dart';
import 'package:beat/modules/kanban/kanban_model.dart';
import 'package:beat/modules/kanban/kanban_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Future<KanbanRepository> _repo() async =>
    KanbanRepository(await DataStore.open(MemoryLogStorage()));

void main() {
  test('new project gets three default columns', () async {
    final repo = await _repo();
    final id = await repo.createProject('Запуск продукта');
    expect(repo.projects().single.name, 'Запуск продукта');
    expect(repo.columns(id).map((c) => c.name), KanbanRepository.defaultColumns);
  });

  test('tasks are appended and can be moved between columns', () async {
    final repo = await _repo();
    final p = await repo.createProject('P');
    final [todo, doing, _] = repo.columns(p);
    final t1 = await repo.createTask(projectId: p, columnId: todo.id, title: '1');
    final t2 = await repo.createTask(projectId: p, columnId: todo.id, title: '2');
    final t3 = await repo.createTask(projectId: p, columnId: todo.id, title: '3');
    expect(repo.columnTasks(todo.id).map((t) => t.id), [t1, t2, t3]);

    // Поставить 3 перед 1.
    await repo.moveTask(t3, todo.id, beforeTaskId: t1);
    expect(repo.columnTasks(todo.id).map((t) => t.id), [t3, t1, t2]);

    // Перенести 1 в «В работе».
    await repo.moveTask(t1, doing.id);
    expect(repo.columnTasks(todo.id).map((t) => t.id), [t3, t2]);
    expect(repo.columnTasks(doing.id).map((t) => t.id), [t1]);
  });

  test('updateTask writes only changed fields', () async {
    final repo = await _repo();
    final p = await repo.createProject('P');
    final col = repo.columns(p).first;
    final id = await repo.createTask(
        projectId: p, columnId: col.id, title: 'A', due: DateTime(2026, 11, 18));
    final before = repo.task(id)!;
    final clocksBefore = Map.of(repo.store.get('task', id)!.clocks);

    await repo.updateTask(
      before,
      Task(
        id: id,
        projectId: p,
        columnId: col.id,
        title: 'A',
        priority: TaskPriority.urgent,
        due: before.due,
        order: before.order,
      ),
    );

    final after = repo.task(id)!;
    expect(after.priority, TaskPriority.urgent);
    expect(after.due, DateTime(2026, 11, 18));
    final clocksAfter = repo.store.get('task', id)!.clocks;
    expect(clocksAfter['title'], clocksBefore['title']);
    expect(clocksAfter['priority'], isNot(clocksBefore['priority']));
  });

  test('deleting a project removes its columns and tasks', () async {
    final repo = await _repo();
    final p = await repo.createProject('P');
    final col = repo.columns(p).first;
    await repo.createTask(projectId: p, columnId: col.id, title: 'x');
    await repo.deleteProject(p);
    expect(repo.projects(), isEmpty);
    expect(repo.columns(p), isEmpty);
    expect(repo.store.all(KanbanEntities.task), isEmpty);
  });
}
