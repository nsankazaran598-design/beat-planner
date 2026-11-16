import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/reminders/reminder.dart';
import '../../core/ui/format.dart';
import 'day_model.dart';
import 'day_repository.dart';

final dayRepositoryProvider = Provider<DayRepository>(
  (ref) => DayRepository(ref.watch(dataSnapshotProvider).store),
);

/// Часы для «сейчас»: в тестах подменяются.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final selectedDateProvider =
    NotifierProvider<SelectedDateController, DateTime>(SelectedDateController.new);

class SelectedDateController extends Notifier<DateTime> {
  @override
  DateTime build() => dateOnly(ref.watch(clockProvider)());

  void select(DateTime d) => state = dateOnly(d);
  void today() => state = dateOnly(ref.read(clockProvider)());
  void shiftWeeks(int n) => state = addDays(state, 7 * n);
}

enum DayViewMode { day, week }

final dayViewModeProvider =
    NotifierProvider<DayViewModeController, DayViewMode>(DayViewModeController.new);

class DayViewModeController extends Notifier<DayViewMode> {
  @override
  DayViewMode build() => DayViewMode.day;

  void set(DayViewMode m) => state = m;
}

/// Понедельник недели, в которую входит [d].
DateTime weekStart(DateTime d) => addDays(dateOnly(d), 1 - d.weekday);

final dayItemsProvider = Provider.family<List<DayItem>, DateTime>(
  (ref, date) => ref.watch(dayRepositoryProvider).forDate(date),
);

final weekItemsProvider = Provider.family<List<DayItem>, DateTime>((ref, monday) {
  return ref
      .watch(dayRepositoryProvider)
      .between(monday, addDays(monday, 6));
});

final upcomingRemindersProvider = Provider<List<DayItem>>(
  (ref) => ref.watch(dayRepositoryProvider).upcomingReminders(ref.watch(clockProvider)()),
);

/// Напоминания «Моего дня» для модуля «Напоминания».
final dayRemindersProvider = Provider<List<Reminder>>((ref) {
  final repo = ref.watch(dayRepositoryProvider);
  return [
    for (final i in repo.withReminders())
      Reminder(
        key: 'day_item:${i.id}',
        title: i.title,
        body: '${formatRelativeDateTime(i.startsAt!)}'
            '${i.note.isEmpty ? '' : ' · ${i.note}'}',
        at: i.remindAt!,
        route: '/day',
      ),
  ];
});
