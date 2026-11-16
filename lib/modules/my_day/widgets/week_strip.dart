import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/ui/format.dart';
import '../day_providers.dart';

/// Полоса из семи дней недели с выбранным днём.
class WeekStrip extends ConsumerWidget {
  const WeekStrip({super.key, required this.today});

  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDateProvider);
    final monday = weekStart(selected);
    final busyDays = ref.watch(weekItemsProvider(monday)).map((i) => i.date).toSet();

    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _DayCell(
              date: addDays(monday, i),
              selected: addDays(monday, i) == selected,
              isToday: addDays(monday, i) == today,
              busy: busyDays.contains(addDays(monday, i)),
              onTap: () => ref.read(selectedDateProvider.notifier).select(addDays(monday, i)),
            ),
          ),
        ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.selected,
    required this.isToday,
    required this.busy,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool isToday;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      label: '${weekdayName(date)}, ${formatDayMonth(date)}',
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isToday && !selected
              ? BorderSide(color: scheme.primary, width: 1.5)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Text(weekdayShort(date),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: selected ? fg : scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text('${date.day}', style: theme.textTheme.titleLarge?.copyWith(color: fg)),
                const SizedBox(height: 4),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: busy
                        ? (selected ? scheme.onPrimary : scheme.primary)
                        : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
