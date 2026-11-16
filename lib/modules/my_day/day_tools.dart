import '../../core/agent/agent_tool.dart';
import '../../core/ui/format.dart';
import 'day_model.dart';
import 'day_providers.dart';
import 'day_repository.dart';

DayRepository _repo(Reader read) => read(dayRepositoryProvider);

DateTime _date(String s) {
  final d = DateTime.tryParse(s);
  if (d == null) throw ToolError('Дата "$s" не в формате ГГГГ-ММ-ДД');
  return dateOnly(d);
}

TimeOfDayMinutes? _time(String? s) {
  if (s == null) return null;
  final t = TimeOfDayMinutes.tryParse(s);
  if (t == null || t.minutes >= 24 * 60) throw ToolError('Время "$s" не в формате ЧЧ:ММ');
  return t;
}

ReminderOffset? _reminder(Object? v) {
  if (v == null) return null;
  final r = ReminderOffset.fromMinutes((v as num).toInt());
  if (r == null) {
    throw ToolError('reminder_minutes: ${ReminderOffset.values.map((e) => e.minutes).join(', ')}');
  }
  return r;
}

Map<String, Object?> _json(DayItem i) => {
      'id': i.id,
      'title': i.title,
      'date': encodeDate(i.date),
      if (i.start != null) 'start': '${i.start}',
      if (i.start != null) 'end': '${i.effectiveEnd}',
      if (i.reminder != null) 'reminder_minutes': i.reminder!.minutes,
      'done': i.done,
      if (i.note.isNotEmpty) 'note': i.note,
    };

final List<AgentTool> dayTools = [
  AgentTool(
    name: 'list_day_items',
    description: 'Личные дела «Моего дня» за период (включительно).',
    parameters: objectSchema({
      'from': str('Начало периода, ГГГГ-ММ-ДД'),
      'to': str('Конец периода, ГГГГ-ММ-ДД (по умолчанию = from)'),
    }, required: ['from']),
    scope: ToolScope.personal,
    readOnly: true,
    run: (read, a) async {
      final from = _date(reqStr(a, 'from'));
      final to = optStr(a, 'to') == null ? from : _date(reqStr(a, 'to'));
      return [for (final i in _repo(read).between(from, to)) _json(i)];
    },
  ),
  AgentTool(
    name: 'create_day_item',
    description: 'Запланировать личное дело на дату (и время). Без start — на весь день.',
    parameters: objectSchema({
      'title': str('Название'),
      'date': str('Дата, ГГГГ-ММ-ДД'),
      'start': str('Начало, ЧЧ:ММ'),
      'end': str('Конец, ЧЧ:ММ'),
      'reminder_minutes': integer('Напомнить за N минут до начала: 0, 5, 15, 30, 60, 1440'),
      'note': str('Заметка'),
    }, required: ['title', 'date']),
    scope: ToolScope.personal,
    readOnly: false,
    summarize: (_, a) =>
        'Запланировать «${a['title']}» на ${a['date']}${a['start'] == null ? '' : ' в ${a['start']}'}',
    run: (read, a) async {
      final start = _time(optStr(a, 'start'));
      final id = await _repo(read).create(
        title: reqStr(a, 'title'),
        date: _date(reqStr(a, 'date')),
        start: start,
        end: start == null ? null : _time(optStr(a, 'end')),
        reminder: start == null ? null : _reminder(a['reminder_minutes']),
        note: optStr(a, 'note') ?? '',
      );
      return {'item_id': id};
    },
  ),
  AgentTool(
    name: 'set_day_item_done',
    description: 'Отметить дело выполненным (или снять отметку).',
    parameters: objectSchema(
      {'item_id': str('id дела'), 'done': boolean('Выполнено')},
      required: ['item_id', 'done'],
    ),
    scope: ToolScope.personal,
    readOnly: false,
    summarize: (read, a) {
      final i = _repo(read).get('${a['item_id']}');
      return '${a['done'] == true ? 'Отметить выполненным' : 'Снять отметку'}: «${i?.title ?? a['item_id']}»';
    },
    run: (read, a) async {
      final repo = _repo(read);
      final i = repo.get(reqStr(a, 'item_id')) ?? (throw const ToolError('Дело не найдено'));
      await repo.setDone(i.id, a['done'] == true);
      return {'ok': true};
    },
  ),
  AgentTool(
    name: 'delete_day_item',
    description: 'Удалить личное дело.',
    parameters: objectSchema({'item_id': str('id дела')}, required: ['item_id']),
    scope: ToolScope.personal,
    readOnly: false,
    summarize: (read, a) {
      final i = _repo(read).get('${a['item_id']}');
      return 'Удалить дело «${i?.title ?? a['item_id']}»';
    },
    run: (read, a) async {
      final repo = _repo(read);
      final i = repo.get(reqStr(a, 'item_id')) ?? (throw const ToolError('Дело не найдено'));
      await repo.delete(i.id);
      return {'ok': true};
    },
  ),
];
