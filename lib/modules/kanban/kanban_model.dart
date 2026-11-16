import '../../core/data/data_store.dart';

export '../../core/ui/format.dart' show encodeDate;

abstract final class KanbanEntities {
  static const project = 'project';
  static const column = 'column';
  static const task = 'task';
}

class Project {
  const Project({
    required this.id,
    required this.name,
    this.description = '',
    this.order = 0,
  });

  final String id;
  final String name;
  final String description;
  final double order;

  factory Project.fromRecord(Record r) => Project(
        id: r.id,
        name: r.get<String>('name') ?? '',
        description: r.get<String>('description') ?? '',
        order: (r.get<num>('order') ?? 0).toDouble(),
      );
}

class BoardColumn {
  const BoardColumn({
    required this.id,
    required this.projectId,
    required this.name,
    this.order = 0,
  });

  final String id;
  final String projectId;
  final String name;
  final double order;

  factory BoardColumn.fromRecord(Record r) => BoardColumn(
        id: r.id,
        projectId: r.get<String>('projectId') ?? '',
        name: r.get<String>('name') ?? '',
        order: (r.get<num>('order') ?? 0).toDouble(),
      );
}

enum TaskPriority {
  normal('Обычный'),
  high('Высокий'),
  urgent('Срочный');

  const TaskPriority(this.label);
  final String label;
}

class Task {
  const Task({
    required this.id,
    required this.projectId,
    required this.columnId,
    required this.title,
    this.category = '',
    this.description = '',
    this.priority = TaskPriority.normal,
    this.due,
    this.order = 0,
  });

  final String id;
  final String projectId;
  final String columnId;
  final String title;
  final String category;
  final String description;
  final TaskPriority priority;

  /// Срок — только дата, без времени.
  final DateTime? due;
  final double order;

  factory Task.fromRecord(Record r) {
    final due = r.get<String>('due');
    final p = r.get<String>('priority');
    return Task(
      id: r.id,
      projectId: r.get<String>('projectId') ?? '',
      columnId: r.get<String>('columnId') ?? '',
      title: r.get<String>('title') ?? '',
      category: r.get<String>('category') ?? '',
      description: r.get<String>('description') ?? '',
      priority: TaskPriority.values.firstWhere((e) => e.name == p,
          orElse: () => TaskPriority.normal),
      due: due == null ? null : DateTime.tryParse(due),
      order: (r.get<num>('order') ?? 0).toDouble(),
    );
  }
}
