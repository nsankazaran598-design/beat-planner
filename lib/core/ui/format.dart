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
