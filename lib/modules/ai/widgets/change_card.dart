import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../tool_gateway.dart';

/// Карточка изменения на подтверждение: «Применить» / «Отклонить».
class ChangeCard extends ConsumerWidget {
  const ChangeCard({super.key, required this.changeId, this.showSource = false});

  final String changeId;
  final bool showSource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = ref.watch(pendingChangesProvider.select(
        (list) => list.where((x) => x.id == changeId).firstOrNull));
    if (c == null) return const SizedBox.shrink();
    final ctl = ref.read(pendingChangesProvider.notifier);

    final (icon, label, color) = switch (c.status) {
      ChangeStatus.pending => (Icons.pending_outlined, 'Ждёт подтверждения', scheme.primary),
      ChangeStatus.applied => (Icons.check_circle_outline, 'Применено', scheme.tertiary),
      ChangeStatus.rejected => (Icons.block, 'Отклонено', scheme.onSurfaceVariant),
      ChangeStatus.failed => (Icons.error_outline, 'Не удалось: ${c.result ?? ''}', scheme.error),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showSource)
            Text(c.source == ChangeSource.external ? 'Внешний агент' : 'Помощник',
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          Text(c.summary, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: color)),
            ),
          ]),
          if (c.status == ChangeStatus.pending) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton.tonal(onPressed: () => ctl.apply(c.id), child: const Text('Применить')),
              TextButton(onPressed: () => ctl.reject(c.id), child: const Text('Отклонить')),
            ]),
          ],
        ],
      ),
    );
  }
}
