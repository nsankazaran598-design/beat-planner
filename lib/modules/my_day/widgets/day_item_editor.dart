import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/dialogs.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/picker_field.dart';
import '../day_model.dart';
import '../day_providers.dart';

Future<void> showDayItemEditor(
  BuildContext context, {
  DayItem? item,
  DateTime? date,
  TimeOfDayMinutes? start,
}) =>
    showAdaptiveSheet<void>(
      context,
      (_) => DayItemEditor(item: item, date: date, start: start),
    );

class DayItemEditor extends ConsumerStatefulWidget {
  const DayItemEditor({super.key, this.item, this.date, this.start});

  final DayItem? item;
  final DateTime? date;
  final TimeOfDayMinutes? start;

  @override
  ConsumerState<DayItemEditor> createState() => _DayItemEditorState();
}

class _DayItemEditorState extends ConsumerState<DayItemEditor> {
  late final _title = TextEditingController(text: widget.item?.title);
  late final _note = TextEditingController(text: widget.item?.note);
  late DateTime _date = widget.item?.date ?? widget.date ?? dateOnly(DateTime.now());
  late TimeOfDayMinutes? _start = widget.item?.start ?? widget.start;
  late TimeOfDayMinutes? _end = widget.item?.end ??
      (widget.item == null && widget.start != null ? widget.start! + 60 : null);
  late ReminderOffset? _reminder = widget.item?.reminder;
  late bool _done = widget.item?.done ?? false;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 5),
      lastDate: DateTime(_date.year + 10),
    );
    if (picked != null) setState(() => _date = dateOnly(picked));
  }

  Future<void> _pickStart() async {
    final init = _start ?? TimeOfDayMinutes.hm(DateTime.now().hour + 1, 0);
    final t = await pickTime(context, TimeOfDay(hour: init.hour % 24, minute: init.minute));
    if (t == null) return;
    setState(() {
      final old = _start;
      _start = TimeOfDayMinutes.hm(t.hour, t.minute);
      // Сохраняем длительность при переносе начала.
      final duration = old != null && _end != null ? _end!.minutes - old.minutes : 60;
      _end = _start! + (duration > 0 ? duration : 60);
    });
  }

  Future<void> _pickEnd() async {
    final init = _end ?? (_start! + 60);
    final t = await pickTime(context, TimeOfDay(hour: init.hour, minute: init.minute));
    if (t == null) return;
    setState(() => _end = TimeOfDayMinutes.hm(t.hour, t.minute));
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(dayRepositoryProvider);
    final end = _start != null && _end != null && _end!.minutes > _start!.minutes ? _end : null;
    final reminder = _start == null ? null : _reminder;
    final old = widget.item;
    if (old == null) {
      await repo.create(
        title: title,
        date: _date,
        start: _start,
        end: end,
        reminder: reminder,
        note: _note.text.trim(),
      );
    } else {
      await repo.update(
        old,
        DayItem(
          id: old.id,
          title: title,
          date: _date,
          start: _start,
          end: end,
          reminder: reminder,
          done: _done,
          note: _note.text.trim(),
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    if (!await confirm(context, title: 'Удалить дело?')) return;
    await ref.read(dayRepositoryProvider).delete(widget.item!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_isNew ? 'Запланировать' : 'Дело', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('Без привязки к проекту',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          TextField(
            controller: _title,
            autofocus: _isNew,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Дата',
            value: '${weekdayName(_date)}, ${formatDayMonth(_date)}',
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: PickerField(
                label: 'Начало',
                value: _start?.toString(),
                onTap: _pickStart,
                onClear: () => setState(() {
                  _start = null;
                  _end = null;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PickerField(
                label: 'Конец',
                value: _start == null ? null : (_end ?? _start! + 60).toString(),
                enabled: _start != null,
                onTap: _pickEnd,
              ),
            ),
          ]),
          if (_start == null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text('Без времени — дело на весь день',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 16),
          ReminderDropdown(
            value: _reminder,
            enabled: _start != null,
            onChanged: (r) => setState(() => _reminder = r),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Заметка'),
          ),
          if (!_isNew)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Выполнено'),
              value: _done,
              onChanged: (v) => setState(() => _done = v),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (!_isNew)
                TextButton.icon(
                  onPressed: _delete,
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Удалить'),
                ),
              const Spacer(),
              TextButton(
                  onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _title.text.trim().isEmpty ? null : _save,
                child: Text(_isNew ? 'Добавить' : 'Сохранить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ReminderDropdown extends StatelessWidget {
  const ReminderDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final ReminderOffset? value;
  final ValueChanged<ReminderOffset?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<ReminderOffset?>(
      key: ValueKey('$value-$enabled'),
      initialSelection: enabled ? value : null,
      enabled: enabled,
      expandedInsets: EdgeInsets.zero,
      label: const Text('Напоминание'),
      helperText: enabled ? null : 'Нужно указать время начала',
      onSelected: onChanged,
      dropdownMenuEntries: [
        const DropdownMenuEntry(value: null, label: 'Без напоминания'),
        for (final r in ReminderOffset.values) DropdownMenuEntry(value: r, label: r.label),
      ],
    );
  }
}
