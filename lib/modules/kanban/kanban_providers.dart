import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/settings/settings_controller.dart';
import 'kanban_model.dart';
import 'kanban_repository.dart';

final kanbanRepositoryProvider = Provider<KanbanRepository>(
  (ref) => KanbanRepository(ref.watch(dataSnapshotProvider).store),
);

final projectsProvider = Provider<List<Project>>(
  (ref) => ref.watch(kanbanRepositoryProvider).projects(),
);

/// Выбранный проект (запоминается на устройстве, не синхронизируется).
final selectedProjectIdProvider =
    NotifierProvider<SelectedProjectController, String?>(
        SelectedProjectController.new);

class SelectedProjectController extends Notifier<String?> {
  static const _key = 'kanban.selectedProject';

  @override
  String? build() => ref.watch(sharedPreferencesProvider).getString(_key);

  Future<void> select(String id) async {
    state = id;
    await ref.read(sharedPreferencesProvider).setString(_key, id);
  }
}

/// Текущий проект: выбранный или первый, если выбранный удалён.
final currentProjectProvider = Provider<Project?>((ref) {
  final projects = ref.watch(projectsProvider);
  final selected = ref.watch(selectedProjectIdProvider);
  if (projects.isEmpty) return null;
  return projects.firstWhere((p) => p.id == selected,
      orElse: () => projects.first);
});

final columnsProvider = Provider.family<List<BoardColumn>, String>(
  (ref, projectId) => ref.watch(kanbanRepositoryProvider).columns(projectId),
);

enum KanbanFilter {
  all('Все задачи'),
  priority('Приоритет'),
  soon('Срок близко');

  const KanbanFilter(this.label);
  final String label;

  bool matches(Task t, DateTime today) => switch (this) {
        KanbanFilter.all => true,
        KanbanFilter.priority => t.priority != TaskPriority.normal,
        KanbanFilter.soon =>
          t.due != null && !t.due!.isAfter(today.add(const Duration(days: 3))),
      };
}

final kanbanFilterProvider =
    NotifierProvider<KanbanFilterController, KanbanFilter>(
        KanbanFilterController.new);

class KanbanFilterController extends Notifier<KanbanFilter> {
  @override
  KanbanFilter build() => KanbanFilter.all;

  void set(KanbanFilter f) => state = f;
}

/// Задачи проекта, сгруппированные по колонкам, с учётом фильтра.
final boardTasksProvider = Provider.family<Map<String, List<Task>>, String>(
  (ref, projectId) {
    final filter = ref.watch(kanbanFilterProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final result = <String, List<Task>>{};
    for (final t in ref.watch(kanbanRepositoryProvider).tasks(projectId)) {
      if (filter.matches(t, today)) {
        result.putIfAbsent(t.columnId, () => []).add(t);
      }
    }
    return result;
  },
);
