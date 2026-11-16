import 'package:beat/core/data/data_store.dart';
import 'package:beat/core/data/log_storage.dart';
import 'package:beat/core/ui/format.dart';
import 'package:beat/modules/my_day/day_model.dart';
import 'package:beat/modules/my_day/day_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Future<DayRepository> _repo() async =>
    DayRepository(await DataStore.open(MemoryLogStorage()));

void main() {
  final day = DateTime(2026, 11, 16);

  test('items of a day: untimed first, then by start time', () async {
    final repo = await _repo();
    await repo.create(title: 'Тренировка', date: day, start: TimeOfDayMinutes.hm(16, 0));
    await repo.create(title: 'Прогулка', date: day, start: TimeOfDayMinutes.hm(9, 0));
    await repo.create(title: 'Купить продукты', date: day);
    await repo.create(title: 'Завтра', date: addDays(day, 1), start: TimeOfDayMinutes.hm(9, 0));

    expect(repo.forDate(day).map((i) => i.title),
        ['Купить продукты', 'Прогулка', 'Тренировка']);
  });

  test('reminder time and upcoming reminders', () async {
    final repo = await _repo();
    await repo.create(
        title: 'Встреча',
        date: day,
        start: TimeOfDayMinutes.hm(13, 0),
        reminder: ReminderOffset.min15);
    await repo.create(
        title: 'Прошло',
        date: day,
        start: TimeOfDayMinutes.hm(9, 0),
        reminder: ReminderOffset.min15);
    await repo.create(title: 'Без напоминания', date: day, start: TimeOfDayMinutes.hm(14, 0));

    final upcoming = repo.upcomingReminders(DateTime(2026, 11, 16, 12, 15));
    expect(upcoming.map((i) => i.title), ['Встреча']);
    expect(upcoming.single.remindAt, DateTime(2026, 11, 16, 12, 45));
  });

  test('done items do not remind', () async {
    final repo = await _repo();
    final id = await repo.create(
        title: 'X', date: day, start: TimeOfDayMinutes.hm(18, 0), reminder: ReminderOffset.hour1);
    await repo.setDone(id, true);
    expect(repo.upcomingReminders(DateTime(2026, 11, 16, 12)), isEmpty);
    expect(repo.get(id)!.done, isTrue);
  });

  test('default end is one hour after start', () {
    final i = DayItem(id: 'x', title: 't', date: day, start: TimeOfDayMinutes.hm(10, 30));
    expect(i.effectiveEnd.toString(), '11:30');
  });

  test('week range and plural helper', () async {
    final repo = await _repo();
    for (var d = 0; d < 9; d++) {
      await repo.create(title: 'd$d', date: addDays(day, d));
    }
    expect(repo.between(day, addDays(day, 6)).length, 7);
    expect(plural(1, 'дело', 'дела', 'дел'), 'дело');
    expect(plural(3, 'дело', 'дела', 'дел'), 'дела');
    expect(plural(11, 'дело', 'дела', 'дел'), 'дел');
    expect(plural(22, 'дело', 'дела', 'дел'), 'дела');
  });
}
