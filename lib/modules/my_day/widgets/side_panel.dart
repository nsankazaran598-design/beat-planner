import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/format.dart';
import '../../../core/ui/picker_field.dart';
import '../day_model.dart';
import '../day_providers.dart';
import 'day_item_editor.dart';

/// Правая панель из макета: быстрая форма и ближайшие напоминания.
class DaySidePanel extends StatelessWidget {
  const DaySidePanel({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const _Card(child: QuickScheduleForm()),
        const SizedBox(height: 20),
        _Card(child: UpcomingReminders(now: now)),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );
}

class QuickScheduleForm extends ConsumerStatefulWidget {
  const QuickScheduleForm({super.key});

  @override
  ConsumerState<QuickScheduleForm> createState() => _QuickScheduleFormState();
}

class _QuickScheduleFormState extends ConsumerState<QuickScheduleForm> {
  final _title = TextEditingController();
  DateTime? _date;
  TimeOfDayMinutes? _time;
  ReminderOffset? _reminder = ReminderOffset.min15;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final DateTime date = _date ?? ref.read(selectedDateProvider);
    await ref.read(dayRepositoryProvider).create(
          title: title,
          date: date,
          start: _time,
          reminder: _time == null ? null : _reminder,
        );
    ref.read(selectedDateProvider.notifier).select(date);
    setState(() {
      _title.clear();
      _time = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final DateTime date = _date ?? ref.watch(selectedDateProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Запланировать задачу', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Без привязки к проекту',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Название'),
          onSubmitted: (_) => _add(),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: PickerField(
              label: 'Дата',
              value: '${date.day.toString().padLeft(2, '0')}.'
                  '${date.month.toString().padLeft(2, '0')}.${date.year}',
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(date.year - 5),
                  lastDate: DateTime(date.year + 10),
                );
                if (picked != null) setState(() => _date = dateOnly(picked));
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PickerField(
              label: 'Время',
              value: _time?.toString(),
              onClear: () => setState(() => _time = null),
              onTap: () async {
                final t = await pickTime(context, TimeOfDay(hour: DateTime.now().hour + 1 > 23 ? 23 : DateTime.now().hour + 1, minute: 0));
                if (t != null) setState(() => _time = TimeOfDayMinutes.hm(t.hour, t.minute));
              },
            ),
          ),
        ]),
        const SizedBox(height: 16),
        ReminderDropdown(
          value: _reminder,
          enabled: _time != null,
          onChanged: (r) => setState(() => _reminder = r),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _title.text.trim().isEmpty ? null : _add,
            child: const Text('Добавить в мой день'),
          ),
        ),
      ],
    );
  }
}

class UpcomingReminders extends ConsumerWidget {
  const UpcomingReminders({super.key, required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = ref.watch(dayRepositoryProvider).upcomingReminders(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Напоминания', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Text('Ближайших напоминаний нет',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        for (final i in items)
          InkWell(
            onTap: () => showDayItemEditor(context, item: i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(formatHm(i.remindAt!),
                        style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.title, style: theme.textTheme.titleSmall),
                        Text(formatRelativeDateTime(i.startsAt!, now: now),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text('Уведомления в приложении и на устройстве',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
