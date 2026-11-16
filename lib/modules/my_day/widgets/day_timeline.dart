import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../day_model.dart';
import '../day_providers.dart';
import 'day_item_editor.dart';

const _hourHeight = 64.0;
const _gutter = 64.0;
const _minBlock = 48.0;

/// Расписание одного дня: дела без времени сверху и шкала по часам.
class DayTimeline extends ConsumerWidget {
  const DayTimeline({
    super.key,
    required this.date,
    required this.items,
    required this.now,
  });

  final DateTime date;
  final List<DayItem> items;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final untimed = items.where((i) => !i.timed).toList();
    final timed = items.where((i) => i.timed).toList();

    var startHour = 8;
    var endHour = 20;
    for (final i in timed) {
      startHour = math.min(startHour, i.start!.hour);
      endHour = math.max(endHour, (i.effectiveEnd!.minutes / 60).ceil());
    }
    endHour = math.min(endHour, 24);
    final isToday = DateTime(now.year, now.month, now.day) == date;

    return ListView(
      // Снизу запас под плавающую кнопку на телефоне.
      padding: const EdgeInsets.only(top: 8, bottom: 72),
      children: [
        if (untimed.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('В течение дня',
                style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          for (final i in untimed) _UntimedRow(item: i),
          const Divider(height: 24),
        ],
        SizedBox(
          height: (endHour - startHour) * _hourHeight + 16,
          child: LayoutBuilder(builder: (context, box) {
            final lanes = _layoutLanes(timed);
            final width = box.maxWidth - _gutter - 12;
            double y(int minutes) => 8 + (minutes - startHour * 60) / 60 * _hourHeight;

            return Stack(
              children: [
                for (var h = startHour; h <= endHour; h++) ...[
                  Positioned(
                    left: 16,
                    top: y(h * 60) - 8,
                    child: Text('${h.toString().padLeft(2, '0')}:00',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                  Positioned(
                    left: _gutter,
                    right: 12,
                    top: y(h * 60),
                    child: Divider(height: 1, color: scheme.outlineVariant),
                  ),
                ],
                // Пустые слоты: нажатие создаёт дело на этот час.
                for (var h = startHour; h < endHour; h++)
                  Positioned(
                    left: _gutter,
                    right: 12,
                    top: y(h * 60),
                    height: _hourHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onDoubleTap: () => showDayItemEditor(context,
                          date: date, start: TimeOfDayMinutes.hm(h, 0)),
                    ),
                  ),
                for (final e in lanes.entries)
                  Positioned(
                    left: _gutter + 8 + width * e.value.$1 / e.value.$2,
                    width: width / e.value.$2 - 8,
                    top: y(e.key.start!.minutes) + 2,
                    height: math.max(
                      _minBlock,
                      (e.key.effectiveEnd!.minutes - e.key.start!.minutes) /
                              60 *
                              _hourHeight -
                          4,
                    ),
                    child: _Block(item: e.key),
                  ),
                if (isToday && now.hour >= startHour && now.hour < endHour)
                  Positioned(
                    left: _gutter - 5,
                    right: 12,
                    top: y(now.hour * 60 + now.minute) - 5,
                    child: IgnorePointer(
                      child: Row(children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration:
                              BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                        ),
                        Expanded(child: Container(height: 2, color: scheme.primary)),
                      ]),
                    ),
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

/// Раскладывает пересекающиеся дела по дорожкам.
/// Возвращает для каждого дела (номер дорожки, число дорожек в группе).
Map<DayItem, (int, int)> _layoutLanes(List<DayItem> items) {
  final sorted = [...items]..sort((a, b) => a.start!.compareTo(b.start!));
  final result = <DayItem, (int, int)>{};
  var group = <DayItem>[];
  var laneEnds = <int>[];
  var groupEnd = -1;

  void flush() {
    for (final i in group) {
      result[i] = (result[i]!.$1, laneEnds.length);
    }
    group = [];
    laneEnds = [];
  }

  for (final item in sorted) {
    final s = item.start!.minutes;
    final e = math.max(item.effectiveEnd!.minutes, s + 45);
    if (s >= groupEnd) flush();
    var lane = laneEnds.indexWhere((end) => end <= s);
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(e);
    } else {
      laneEnds[lane] = e;
    }
    result[item] = (lane, 0);
    group.add(item);
    groupEnd = math.max(groupEnd, e);
  }
  flush();
  return result;
}

String _subtitle(DayItem i) {
  final parts = <String>[
    if (i.timed) '${i.start}–${i.effectiveEnd}',
    if (i.done) 'Выполнено' else if (i.reminder != null) i.reminder!.label,
  ];
  return parts.join(' · ');
}

class _Block extends ConsumerWidget {
  const _Block({required this.item});

  final DayItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (bg, fg) = item.done
        ? (scheme.surfaceContainerHigh, scheme.onSurfaceVariant)
        : item.reminder != null
            ? (scheme.primaryContainer, scheme.onPrimaryContainer)
            : (scheme.secondaryContainer, scheme.onSecondaryContainer);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDayItemEditor(context, item: item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(color: fg)),
                    Text(_subtitle(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: fg)),
                  ],
                ),
              ),
              _DoneToggle(item: item, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneToggle extends ConsumerWidget {
  const _DoneToggle({required this.item, required this.color});

  final DayItem item;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: item.done ? 'Отметить невыполненным' : 'Отметить выполненным',
      onPressed: () => ref.read(dayRepositoryProvider).setDone(item.id, !item.done),
      icon: Icon(
        item.done ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 20,
        color: color,
      ),
    );
  }
}

class _UntimedRow extends ConsumerWidget {
  const _UntimedRow({required this.item});

  final DayItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 8, right: 16),
      leading: Checkbox(
        value: item.done,
        onChanged: (v) => ref.read(dayRepositoryProvider).setDone(item.id, v ?? false),
      ),
      title: Text(
        item.title,
        style: theme.textTheme.bodyLarge?.copyWith(
          decoration: item.done ? TextDecoration.lineThrough : null,
          color: item.done ? theme.colorScheme.onSurfaceVariant : null,
        ),
      ),
      subtitle: item.note.isEmpty ? null : Text(item.note, maxLines: 1),
      onTap: () => showDayItemEditor(context, item: item),
    );
  }
}
