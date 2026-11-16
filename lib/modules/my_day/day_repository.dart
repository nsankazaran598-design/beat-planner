import '../../core/data/data_store.dart';
import '../../core/ui/format.dart';
import 'day_model.dart';

class DayRepository {
  DayRepository(this.store);

  final DataStore store;

  Iterable<DayItem> _all() => store.all(DayItem.entity).map(DayItem.fromRecord);

  /// Дела дня: сначала без времени, затем по времени начала.
  List<DayItem> forDate(DateTime date) {
    final d = dateOnly(date);
    return _all().where((i) => i.date == d).toList()..sort(_compare);
  }

  /// Дела в диапазоне дат [from, to] включительно.
  List<DayItem> between(DateTime from, DateTime to) {
    final a = dateOnly(from);
    final b = dateOnly(to);
    return _all()
        .where((i) => !i.date.isBefore(a) && !i.date.isAfter(b))
        .toList()
      ..sort((x, y) {
        final c = x.date.compareTo(y.date);
        return c != 0 ? c : _compare(x, y);
      });
  }

  /// Ближайшие напоминания, начиная с [now].
  List<DayItem> upcomingReminders(DateTime now, {int limit = 5}) {
    final list = _all()
        .where((i) => !i.done && i.remindAt != null && i.remindAt!.isAfter(now))
        .toList()
      ..sort((a, b) => a.remindAt!.compareTo(b.remindAt!));
    return list.take(limit).toList();
  }

  DayItem? get(String id) {
    final r = store.get(DayItem.entity, id);
    return r == null ? null : DayItem.fromRecord(r);
  }

  Future<String> create({
    required String title,
    required DateTime date,
    TimeOfDayMinutes? start,
    TimeOfDayMinutes? end,
    ReminderOffset? reminder,
    String note = '',
  }) async {
    final id = store.newId();
    await store.write(
      DayItem.entity,
      id,
      DayItem(
        id: id,
        title: title,
        date: dateOnly(date),
        start: start,
        end: end,
        reminder: reminder,
        note: note,
      ).toFields(),
    );
    return id;
  }

  /// Записывает только изменившиеся поля.
  Future<void> update(DayItem before, DayItem after) {
    final a = before.toFields();
    final b = after.toFields();
    final changed = {
      for (final k in b.keys)
        if (a[k] != b[k]) k: b[k],
    };
    if (changed.isEmpty) return Future.value();
    return store.write(DayItem.entity, after.id, changed);
  }

  Future<void> setDone(String id, bool done) =>
      store.write(DayItem.entity, id, {'done': done});

  Future<void> delete(String id) => store.delete(DayItem.entity, id);

  static int _compare(DayItem a, DayItem b) {
    if (a.start == null && b.start != null) return -1;
    if (a.start != null && b.start == null) return 1;
    if (a.start != null && b.start != null) {
      final c = a.start!.compareTo(b.start!);
      if (c != 0) return c;
    }
    return a.title.compareTo(b.title);
  }
}
