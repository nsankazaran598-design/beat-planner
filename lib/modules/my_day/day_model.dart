import '../../core/data/data_store.dart';
import '../../core/ui/format.dart';

/// Время дня в минутах от полуночи.
class TimeOfDayMinutes implements Comparable<TimeOfDayMinutes> {
  const TimeOfDayMinutes(this.minutes);

  factory TimeOfDayMinutes.hm(int h, int m) => TimeOfDayMinutes(h * 60 + m);

  final int minutes;

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  static TimeOfDayMinutes? tryParse(String? s) {
    if (s == null) return null;
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDayMinutes.hm(h, m);
  }

  TimeOfDayMinutes operator +(int delta) =>
      TimeOfDayMinutes((minutes + delta).clamp(0, 24 * 60 - 1));

  @override
  int compareTo(TimeOfDayMinutes other) => minutes.compareTo(other.minutes);

  @override
  bool operator ==(Object other) => other is TimeOfDayMinutes && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;

  /// `09:05`
  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Варианты напоминания: минуты до начала.
enum ReminderOffset {
  atStart(0, 'В момент начала'),
  min5(5, 'За 5 минут'),
  min15(15, 'За 15 минут'),
  min30(30, 'За 30 минут'),
  hour1(60, 'За 1 час'),
  day1(24 * 60, 'За 1 день');

  const ReminderOffset(this.minutes, this.label);
  final int minutes;
  final String label;

  static ReminderOffset? fromMinutes(int? m) {
    if (m == null) return null;
    for (final r in values) {
      if (r.minutes == m) return r;
    }
    return null;
  }
}

/// Личное дело на конкретный день — отдельно от Kanban.
class DayItem {
  const DayItem({
    required this.id,
    required this.title,
    required this.date,
    this.start,
    this.end,
    this.reminder,
    this.done = false,
    this.note = '',
  });

  static const entity = 'day_item';

  final String id;
  final String title;

  /// Дата без времени.
  final DateTime date;

  /// Начало; null — дело без времени («в течение дня»).
  final TimeOfDayMinutes? start;
  final TimeOfDayMinutes? end;
  final ReminderOffset? reminder;
  final bool done;
  final String note;

  bool get timed => start != null;

  /// Конец с учётом значения по умолчанию (1 час).
  TimeOfDayMinutes? get effectiveEnd {
    if (start == null) return null;
    if (end != null && end!.minutes > start!.minutes) return end;
    return start! + 60;
  }

  /// Момент начала.
  DateTime? get startsAt => start == null
      ? null
      : DateTime(date.year, date.month, date.day, start!.hour, start!.minute);

  /// Момент напоминания (null, если напоминания нет или нет времени).
  DateTime? get remindAt {
    final s = startsAt;
    if (s == null || reminder == null) return null;
    return s.subtract(Duration(minutes: reminder!.minutes));
  }

  factory DayItem.fromRecord(Record r) => DayItem(
        id: r.id,
        title: r.get<String>('title') ?? '',
        date: DateTime.tryParse(r.get<String>('date') ?? '') ?? DateTime(1970),
        start: TimeOfDayMinutes.tryParse(r.get<String>('start')),
        end: TimeOfDayMinutes.tryParse(r.get<String>('end')),
        reminder: ReminderOffset.fromMinutes(r.get<num>('reminder')?.toInt()),
        done: r.get<bool>('done') ?? false,
        note: r.get<String>('note') ?? '',
      );

  Map<String, Object?> toFields() => {
        'title': title,
        'date': encodeDate(date),
        'start': start?.toString(),
        'end': end?.toString(),
        'reminder': reminder?.minutes,
        'done': done,
        'note': note,
      };

  DayItem copyWith({bool? done}) => DayItem(
        id: id,
        title: title,
        date: date,
        start: start,
        end: end,
        reminder: reminder,
        done: done ?? this.done,
        note: note,
      );
}
