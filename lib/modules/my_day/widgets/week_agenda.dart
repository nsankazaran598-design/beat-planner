import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/format.dart';
import '../day_model.dart';
import '../day_providers.dart';
import 'day_item_editor.dart';

/// Неделя списком: дни с делами по порядку.
class WeekAgenda extends ConsumerWidget {
  const WeekAgenda({super.key, required this.monday, required this.today});

  final DateTime monday;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = ref.watch(weekItemsProvider(monday));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (var d = 0; d < 7; d++) ...[
          Builder(builder: (context) {
            final date = addDays(monday, d);
            final dayItems = items.where((i) => i.date == date).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () {
                    ref.read(selectedDateProvider.notifier).select(date);
                    ref.read(dayViewModeProvider.notifier).set(DayViewMode.day);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      '${weekdayName(date)}, ${formatDayMonth(date)}'
                      '${date == today ? ' · сегодня' : ''}',
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: date == today ? scheme.primary : scheme.onSurface),
                    ),
                  ),
                ),
                if (dayItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text('Свободно',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                for (final i in dayItems) _AgendaRow(item: i),
              ],
            );
          }),
          if (d < 6) const Divider(indent: 16, endIndent: 16),
        ],
      ],
    );
  }
}

class _AgendaRow extends ConsumerWidget {
  const _AgendaRow({required this.item});

  final DayItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 48,
        child: Text(item.timed ? '${item.start}' : '—',
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
      ),
      title: Text(item.title,
          style: TextStyle(decoration: item.done ? TextDecoration.lineThrough : null)),
      subtitle: item.reminder != null && !item.done ? Text(item.reminder!.label) : null,
      trailing: Checkbox(
        value: item.done,
        onChanged: (v) => ref.read(dayRepositoryProvider).setDone(item.id, v ?? false),
      ),
      onTap: () => showDayItemEditor(context, item: item),
    );
  }
}
