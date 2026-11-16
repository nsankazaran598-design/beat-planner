const _monthsGenitive = [
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// «18 ноября», а для другого года — «18 ноября 2027».
String formatDayMonth(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final base = '${d.day} ${_monthsGenitive[d.month - 1]}';
  return d.year == n.year ? base : '$base ${d.year}';
}

/// Человеческое описание срока: «Сегодня», «Завтра», «До 18 ноября».
String formatDue(DateTime due, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final diff = dateOnly(due).difference(today).inDays;
  if (diff == 0) return 'Сегодня';
  if (diff == 1) return 'Завтра';
  if (diff < 0) return 'Просрочено · ${formatDayMonth(due, now: now)}';
  return 'До ${formatDayMonth(due, now: now)}';
}

/// Прибавляет дни по календарю (без сдвигов из‑за перехода на летнее время).
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// Дата без времени в формате `2026-11-18` для хранения.
String encodeDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

const _weekdays = [
  'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье',
];
const _weekdaysShort = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];
String weekdayShort(DateTime d) => _weekdaysShort[d.weekday - 1];

/// «Понедельник, 16 ноября 2026»
String formatFullDate(DateTime d) =>
    '${weekdayName(d)}, ${d.day} ${_monthsGenitive[d.month - 1]} ${d.year}';

/// «GMT+3», «GMT-4:30»
String formatGmtOffset(Duration offset) {
  final sign = offset.isNegative ? '-' : '+';
  final m = offset.inMinutes.abs();
  final h = m ~/ 60;
  final rest = m % 60;
  return 'GMT$sign$h${rest == 0 ? '' : ':${rest.toString().padLeft(2, '0')}'}';
}

/// Склонение: plural(5, 'дело', 'дела', 'дел') → «дел».
String plural(int n, String one, String few, String many) {
  final m10 = n % 10;
  final m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

String formatHm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// «Сегодня, 13:00», «Завтра, 09:30», «18 ноября, 13:00».
String formatRelativeDateTime(DateTime d, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final diff = dateOnly(d).difference(today).inDays;
  final day = switch (diff) {
    0 => 'Сегодня',
    1 => 'Завтра',
    -1 => 'Вчера',
    _ => formatDayMonth(d, now: now),
  };
  return '$day, ${formatHm(d)}';
}
