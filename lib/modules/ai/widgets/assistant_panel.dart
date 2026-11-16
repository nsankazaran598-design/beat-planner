import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/agent/agent_tool.dart';
import '../ai_settings.dart';
import '../assistant_controller.dart';
import '../tool_gateway.dart';
import 'change_card.dart';

/// Панель ИИ-помощника из макета (правая колонка на доске).
class AssistantPanel extends ConsumerStatefulWidget {
  const AssistantPanel({super.key, required this.assistantContext, this.inSheet = false});

  final AssistantContext assistantContext;
  final bool inSheet;

  @override
  ConsumerState<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends ConsumerState<AssistantPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty) return;
    _input.clear();
    ref.read(assistantProvider.notifier).send(t, widget.assistantContext);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(assistantProvider);
    final settings = ref.watch(aiSettingsProvider);
    final key = ref.watch(aiApiKeyProvider).value ?? '';
    final configured = settings.model.trim().isNotEmpty &&
        (settings.provider != AiProvider.anthropic || key.isNotEmpty);
    final changes = ref.watch(pendingChangesProvider);
    final myPending = [
      for (final e in state.entries)
        if (e.changeId != null)
          ?changes
              .where((c) => c.id == e.changeId && c.status == ChangeStatus.pending)
              .firstOrNull,
    ];

    // Прокрутка к последнему сообщению, когда оно появилось.
    if (state.entries.length != _lastCount) {
      _lastCount = state.entries.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
      decoration: widget.inSheet
          ? null
          : BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.chat_bubble_outline, color: scheme.onSurface),
            const SizedBox(width: 8),
            Expanded(child: Text('ИИ-помощник', style: theme.textTheme.titleMedium)),
            PopupMenuButton<String>(
              tooltip: 'Действия',
              onSelected: (v) {
                if (v == 'new') ref.read(assistantProvider.notifier).reset();
                if (v == 'settings') {
                  if (widget.inSheet) Navigator.pop(context);
                  context.go('/ai');
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'new', child: Text('Новый диалог')),
                PopupMenuItem(value: 'settings', child: Text('Настройки ИИ')),
              ],
            ),
          ]),
          Text(widget.assistantContext.label,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.only(right: 8),
              children: [
                if (state.entries.isEmpty) ...[
                  _Intro(onPick: _send, enabled: configured),
                  if (!configured) ...[
                    const SizedBox(height: 12),
                    _NotConfigured(inSheet: widget.inSheet),
                  ],
                ],
                for (final e in state.entries) _Entry(entry: e),
                if (myPending.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.icon(
                      onPressed: () => ref
                          .read(pendingChangesProvider.notifier)
                          .applyAll(myPending.map((c) => c.id)),
                      icon: const Icon(Icons.done_all),
                      label: Text('Применить все (${myPending.length})'),
                    ),
                  ),
              ],
            ),
          ),
          if (state.busy) const LinearProgressIndicator(),
          if (settings.confirmChanges && settings.allowChanges)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text('Изменения — только после вашего подтверждения.',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.only(left: 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: configured && !state.busy,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Спросить помощника…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Отправить',
                onPressed: configured && !state.busy ? _send : null,
                icon: const Icon(Icons.send_outlined),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onPick, required this.enabled});

  final ValueChanged<String> onPick;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Планируем вместе',
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.onPrimaryContainer)),
              const SizedBox(height: 8),
              Text('Помогу разбить большую задачу на шаги и найти фокус на день.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onPrimaryContainer)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final s in const [
          'Что сейчас важнее всего?',
          'Разбей самую большую задачу на шаги',
          'Что просрочено или горит?',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(label: Text(s), onPressed: enabled ? () => onPick(s) : null),
            ),
          ),
      ],
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured({required this.inSheet});

  final bool inSheet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Модель не подключена. Укажите провайдера, модель и ключ.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        TextButton(
          onPressed: () {
            if (inSheet) Navigator.pop(context);
            context.go('/ai');
          },
          child: const Text('Настроить'),
        ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pad = const EdgeInsets.only(bottom: 12);
    switch (entry.kind) {
      case ChatKind.user:
        return Padding(
          padding: pad,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(entry.text, style: theme.textTheme.bodyMedium),
          ),
        );
      case ChatKind.assistant:
        return Padding(
          padding: pad,
          child: SelectableText(entry.text, style: theme.textTheme.bodyMedium),
        );
      case ChatKind.tool:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(Icons.manage_search, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(entry.text,
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        );
      case ChatKind.proposal:
        return Padding(padding: pad, child: ChangeCard(changeId: entry.changeId!));
      case ChatKind.error:
        return Padding(
          padding: pad,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(entry.text,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer)),
          ),
        );
    }
  }
}
