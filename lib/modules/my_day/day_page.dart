import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/shell/breakpoints.dart';
import '../../core/shell/page_scaffold.dart';
import '../../core/ui/format.dart';
import 'day_providers.dart';
import 'widgets/day_item_editor.dart';
import 'widgets/day_timeline.dart';
import 'widgets/side_panel.dart';
import 'widgets/week_agenda.dart';
import 'widgets/week_strip.dart';

class DayPage extends ConsumerStatefulWidget {
  const DayPage({super.key});

  @override
  ConsumerState<DayPage> createState() => _DayPageState();
}

class _DayPageState extends ConsumerState<DayPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Линия «сейчас» и список напоминаний обновляются раз в минуту.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = ref.watch(clockProvider)();
    final today = dateOnly(now);
    final date = ref.watch(selectedDateProvider);
    final mode = ref.watch(dayViewModeProvider);
    final items = ref.watch(dayItemsProvider(date));
    final compact = Breakpoints.of(context) == LayoutSize.compact;
    final done = items.where((i) => i.done).length;

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(mode: mode, compact: compact),
        if (!compact) ...[
          const SizedBox(height: 12),
          Text('Личные задачи и события — отдельно от Kanban',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 12),
        WeekStrip(today: today),
        const SizedBox(height: 12),
        Expanded(
          child: Material(
            color: scheme.surfaceContainerLowest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: mode == DayViewMode.day
                ? DayTimeline(date: date, items: items, now: now)
                : WeekAgenda(monday: weekStart(date), today: today),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            mode == DayViewMode.day
                ? (items.isEmpty
                    ? 'На этот день ничего не запланировано'
                    : 'Запланировано ${items.length} '
                        '${plural(items.length, 'дело', 'дела', 'дел')}'
                        '${done > 0 ? ' · $done уже ${plural(done, 'выполнено', 'выполнены', 'выполнены')}' : ''}')
                : 'Нажмите на день, чтобы открыть его расписание',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );

    return PageScaffold(
      breadcrumb: 'Личное пространство / Расписание',
      title: 'Мой день',
      subtitle: '${formatFullDate(date)} · ${formatGmtOffset(now.timeZoneOffset)}',
      action: compact
          ? null
          : FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => showDayItemEditor(context, date: date),
              icon: const Icon(Icons.add),
              label: const Text('Запланировать'),
            ),
      body: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 960) return main;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: main),
            const SizedBox(width: 20),
            SizedBox(
              width: 340,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DaySidePanel(now: now),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({required this.mode, required this.compact});

  final DayViewMode mode;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modeCtl = ref.read(dayViewModeProvider.notifier);
    final dateCtl = ref.read(selectedDateProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              FilterChip(
                label: const Text('День'),
                selected: mode == DayViewMode.day,
                onSelected: (_) => modeCtl.set(DayViewMode.day),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Неделя'),
                selected: mode == DayViewMode.week,
                onSelected: (_) => modeCtl.set(DayViewMode.week),
              ),
              const SizedBox(width: 8),
              ActionChip(label: const Text('Сегодня'), onPressed: dateCtl.today),
            ]),
          ),
        ),
        IconButton(
          tooltip: 'Предыдущая неделя',
          onPressed: () => dateCtl.shiftWeeks(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Следующая неделя',
          onPressed: () => dateCtl.shiftWeeks(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
