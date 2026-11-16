import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/reminders/reminder.dart';
import '../../core/shell/page_scaffold.dart';
import '../../core/ui/format.dart';
import 'reminders_providers.dart';

class RemindersPage extends ConsumerWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final all = ref.watch(allRemindersProvider).where((r) => r.at.isAfter(now)).toList();
    final enabled = ref.watch(remindersEnabledProvider);
    final today = dateOnly(now);

    final groups = <String, List<Reminder>>{};
    for (final r in all) {
      final diff = dateOnly(r.at).difference(today).inDays;
      final name = switch (diff) {
        0 => 'Сегодня',
        1 => 'Завтра',
        < 7 => 'На этой неделе',
        _ => 'Позже',
      };
      groups.putIfAbsent(name, () => []).add(r);
    }

    return PageScaffold(
      breadcrumb: 'Личное пространство / Напоминания',
      title: 'Напоминания',
      subtitle: 'Уведомления о делах из «Моего дня»',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsCard(enabled: enabled),
                const SizedBox(height: 24),
                if (all.isEmpty)
                  const _Empty()
                else
                  for (final g in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                      child: Text(g.key, style: Theme.of(context).textTheme.titleSmall),
                    ),
                    for (final r in g.value) _ReminderTile(reminder: r, enabled: enabled),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends ConsumerWidget {
  const _SettingsCard({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final perms = ref.watch(notificationPermissionsProvider).value;
    final backend = ref.watch(notificationBackendProvider);
    final blocked = perms?.notifications == false;
    final inexact = perms?.exactAlarms == false;
    final isWindows = !kIsWeb && Platform.isWindows;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text('Напоминания', style: theme.textTheme.titleMedium)),
            Switch(
              value: enabled,
              onChanged: (v) => ref.read(remindersEnabledProvider.notifier).set(v),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            isWindows
                ? 'Уведомления приходят, пока beat запущен — в том числе свёрнутым в трей.'
                : 'Уведомления приходят даже когда приложение закрыто.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (blocked || inexact) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    blocked
                        ? 'Уведомления запрещены для beat в настройках системы.'
                        : 'Нет разрешения на точные будильники — напоминания могут '
                            'опаздывать на несколько минут.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onErrorContainer),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await backend.requestPermissions();
                    ref.invalidate(notificationPermissionsProvider);
                  },
                  child: const Text('Разрешить'),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => backend.show(Reminder(
                key: 'test',
                title: 'Проверка уведомлений',
                body: 'Если вы это видите — напоминания работают.',
                at: DateTime.now(),
                route: '/reminders',
              )),
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Проверить уведомление'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({required this.reminder, required this.enabled});

  final Reminder reminder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: SizedBox(
        width: 52,
        child: Text(formatHm(reminder.at),
            style: theme.textTheme.titleSmall
                ?.copyWith(color: enabled ? scheme.primary : scheme.onSurfaceVariant)),
      ),
      title: Text(reminder.title),
      subtitle: Text(reminder.body),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go(reminder.route),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(children: [
        Icon(Icons.notifications_none, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text('Напоминаний пока нет', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Добавьте напоминание к делу в «Моём дне».',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}
