import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/shell/page_scaffold.dart';
import 'agent_server.dart';
import 'ai_settings.dart';
import 'llm_client.dart';
import 'tool_gateway.dart';
import 'widgets/change_card.dart';

class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

enum _Check { none, running, ok, failed }

class _AiPageState extends ConsumerState<AiPage> {
  late AiProvider _provider;
  late final TextEditingController _url;
  late final TextEditingController _model;
  final _key = TextEditingController();
  bool _showKey = false;
  _Check _check = _Check.none;
  String _checkText = 'Проверка ещё не выполнялась';

  @override
  void initState() {
    super.initState();
    final s = ref.read(aiSettingsProvider);
    _provider = s.provider;
    _url = TextEditingController(text: s.baseUrl);
    _model = TextEditingController(text: s.model);
    ref.read(secretStoreProvider).read(apiKeySecret).then((k) {
      if (mounted && k != null) _key.text = k;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  void _pickProvider(AiProvider p) {
    setState(() {
      // Подставляем адрес и модель по умолчанию, если пользователь их не менял.
      if (_url.text.trim().isEmpty || _url.text == _provider.defaultUrl) _url.text = p.defaultUrl;
      if (_model.text.trim().isEmpty || _model.text == _provider.defaultModel) {
        _model.text = p.defaultModel;
      }
      _provider = p;
    });
  }

  Future<AiSettings> _save() async {
    final s = ref.read(aiSettingsProvider).copyWith(
          provider: _provider,
          baseUrl: _url.text.trim(),
          model: _model.text.trim(),
        );
    await ref.read(aiSettingsProvider.notifier).update(s);
    await ref.read(secretStoreProvider).write(apiKeySecret, _key.text.trim());
    ref.invalidate(aiApiKeyProvider);
    return s;
  }

  Future<void> _saveAndNotify() async {
    await _save();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Настройки ИИ сохранены')));
    }
  }

  Future<void> _test() async {
    setState(() {
      _check = _Check.running;
      _checkText = 'Проверяем…';
    });
    try {
      final s = await _save();
      final reply = await testConnection(s, _key.text.trim());
      setState(() {
        _check = _Check.ok;
        _checkText = 'Подключено · ответ модели: $reply';
      });
    } catch (e) {
      setState(() {
        _check = _Check.failed;
        _checkText = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = [
      _providerCard(context),
      const SizedBox(height: 20),
      const _PrivacyCard(),
    ];
    final right = const [
      _PermissionsCard(),
      SizedBox(height: 20),
      _AgentsCard(),
      SizedBox(height: 20),
      _ChangesCard(),
    ];
    return PageScaffold(
      breadcrumb: 'Рабочее пространство / Настройки',
      title: 'ИИ и подключения',
      subtitle: 'Ваш помощник, ваш провайдер, ваши правила',
      action: FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        onPressed: _saveAndNotify,
        child: const Text('Сохранить'),
      ),
      body: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 1000) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [...left, const SizedBox(height: 20), ...right],
          );
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 32), children: left)),
          const SizedBox(width: 20),
          SizedBox(
            width: 380,
            child: ListView(padding: const EdgeInsets.only(bottom: 32), children: right),
          ),
        ]);
      }),
    );
  }

  Widget _providerCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final (chipText, chipBg, chipFg) = switch (_check) {
      _Check.ok => ('Подключено', scheme.primaryContainer, scheme.onPrimaryContainer),
      _Check.failed => ('Ошибка', scheme.errorContainer, scheme.onErrorContainer),
      _ => ('Не проверено', scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
    };
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text('Подключение провайдера', style: theme.textTheme.titleLarge)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(8)),
              child: Text(chipText, style: theme.textTheme.labelMedium?.copyWith(color: chipFg)),
            ),
          ]),
          const SizedBox(height: 16),
          Text(
            'Подключите свою модель: Claude по API Anthropic или любую модель через '
            'OpenAI-совместимый API — например, локально в LM Studio или Ollama.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          DropdownMenu<AiProvider>(
            initialSelection: _provider,
            expandedInsets: EdgeInsets.zero,
            label: const Text('Провайдер'),
            onSelected: (p) => p == null ? null : _pickProvider(p),
            dropdownMenuEntries: [
              for (final p in AiProvider.values) DropdownMenuEntry(value: p, label: p.label),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _url,
            decoration: const InputDecoration(labelText: 'Базовый URL'),
          ),
          const SizedBox(height: 6),
          Text(
            _provider == AiProvider.anthropic
                ? 'Обычно https://api.anthropic.com'
                : 'LM Studio: http://localhost:1234/v1 · Ollama: http://localhost:11434/v1',
            style: muted,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _model,
            decoration: InputDecoration(
              labelText: 'Модель',
              hintText: _provider == AiProvider.anthropic ? 'claude-opus-5-5' : 'qwen3-8b',
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _key,
            obscureText: !_showKey,
            decoration: InputDecoration(
              labelText: _provider == AiProvider.anthropic ? 'API-ключ' : 'API-ключ (если нужен)',
              suffixIcon: IconButton(
                tooltip: _showKey ? 'Скрыть' : 'Показать',
                onPressed: () => setState(() => _showKey = !_showKey),
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Ключ хранится в защищённом хранилище системы. Не отправляйте его в '
              'диалог с помощником.', style: muted),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _check == _Check.running ? null : _test,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Проверить подключение'),
            ),
          ),
          const SizedBox(height: 8),
          Text(_checkText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: muted?.copyWith(color: _check == _Check.failed ? scheme.error : null)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: Padding(padding: const EdgeInsets.all(24), child: child),
      );
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget step(String n, String t) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            Text(n, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(width: 12),
            Text(t, style: theme.textTheme.bodyMedium),
          ]),
        );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Только нужный контекст', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            'Помощник видит только то, что разрешено справа: задачи проектов и, если '
            'включено, личное расписание. Данные уходят только выбранному провайдеру.',
            style: muted,
          ),
          const SizedBox(height: 20),
          Text('Три шага до старта', style: theme.textTheme.titleSmall),
          step('01', 'Укажите API и модель'),
          step('02', 'Проверьте подключение'),
          step('03', 'Откройте ИИ на доске проекта'),
        ],
      ),
    );
  }
}

class _PermissionsCard extends ConsumerWidget {
  const _PermissionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = ref.watch(aiSettingsProvider);
    final c = ref.read(aiSettingsProvider.notifier);
    Widget sw(String title, String sub, bool v, AiSettings Function(bool) f) => SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: Text(sub),
          value: v,
          onChanged: (x) => c.update(f(x)),
        );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Совместная работа', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Действует для помощника и внешних агентов',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          sw('Читать задачи проекта', 'Чтобы учитывать сроки и приоритеты', s.readTasks,
              (x) => s.copyWith(readTasks: x)),
          sw('Предлагать подзадачи', 'Добавлять и менять задачи', s.allowChanges,
              (x) => s.copyWith(allowChanges: x)),
          sw('Подтверждать изменения', 'Спрашивать перед записью в проект', s.confirmChanges,
              (x) => s.copyWith(confirmChanges: x)),
          sw('Доступ к личным делам',
              s.personalAccess ? 'Помощник видит «Мой день»' : 'Расписание останется приватным',
              s.personalAccess, (x) => s.copyWith(personalAccess: x)),
        ],
      ),
    );
  }
}

class _AgentsCard extends ConsumerWidget {
  const _AgentsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = ref.watch(aiSettingsProvider);
    final server = ref.watch(agentServerProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final port = server.port ?? agentApiPort;
    final mcpUrl = 'http://127.0.0.1:$port/mcp';
    final command =
        'claude mcp add --transport http beat $mcpUrl --header "Authorization: Bearer ${s.apiToken}"';

    Future<void> copy(String text, String what) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what скопирован')));
      }
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text('Внешние агенты', style: theme.textTheme.titleLarge)),
            Switch(
              value: s.apiEnabled,
              onChanged: (v) => ref.read(aiSettingsProvider.notifier).update(s.copyWith(apiEnabled: v)),
            ),
          ]),
          const SizedBox(height: 8),
          Text('MCP-сервер и REST API на этом устройстве — для Claude Code, Cursor и '
              'своих скриптов. Доступны только локально (127.0.0.1) и по токену.', style: muted),
          if (server.error != null) ...[
            const SizedBox(height: 8),
            Text(server.error!, style: muted?.copyWith(color: scheme.error)),
          ],
          if (s.apiEnabled && server.running) ...[
            const SizedBox(height: 16),
            _CodeRow(label: 'MCP', value: mcpUrl, onCopy: () => copy(mcpUrl, 'Адрес')),
            _CodeRow(
                label: 'REST',
                value: 'http://127.0.0.1:$port/api/v1',
                onCopy: () => copy('http://127.0.0.1:$port/api/v1', 'Адрес')),
            _CodeRow(
                label: 'Токен',
                value: '${s.apiToken.substring(0, 6)}••••••',
                onCopy: () => copy(s.apiToken, 'Токен')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                onPressed: () => copy(command, 'Команда'),
                icon: const Icon(Icons.terminal),
                label: const Text('Команда для Claude Code'),
              ),
              TextButton(
                onPressed: () => ref.read(aiSettingsProvider.notifier).regenerateToken(),
                child: const Text('Новый токен'),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.label, required this.value, required this.onCopy});

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      SizedBox(width: 56, child: Text(label, style: theme.textTheme.labelMedium)),
      Expanded(
        child: Text(value,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
      ),
      IconButton(
        tooltip: 'Скопировать',
        visualDensity: VisualDensity.compact,
        onPressed: onCopy,
        icon: const Icon(Icons.copy, size: 18),
      ),
    ]);
  }
}

class _ChangesCard extends ConsumerWidget {
  const _ChangesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = ref.watch(pendingChangesProvider);
    final hasDone = all.any((c) => c.status != ChangeStatus.pending);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text('Изменения на подтверждение', style: theme.textTheme.titleMedium)),
            if (hasDone)
              TextButton(
                onPressed: () => ref.read(pendingChangesProvider.notifier).clearDone(),
                child: const Text('Очистить'),
              ),
          ]),
          const SizedBox(height: 12),
          if (all.isEmpty)
            Text('Пока ничего нет',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          for (final c in all.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ChangeCard(changeId: c.id, showSource: true),
            ),
        ],
      ),
    );
  }
}
