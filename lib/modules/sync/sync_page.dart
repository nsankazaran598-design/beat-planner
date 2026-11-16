import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/shell/page_scaffold.dart';
import '../../core/ui/dialogs.dart';
import '../../core/ui/format.dart';
import 'sync_controller.dart';
import 'sync_protocol.dart';

bool get _canScan => !kIsWeb && Platform.isAndroid;

class SyncPage extends ConsumerWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    return PageScaffold(
      breadcrumb: 'Рабочее пространство / Синхронизация',
      title: 'Синхронизация',
      subtitle: 'Между вашими устройствами в локальной сети — без сервера',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: s.inGroup ? _GroupView(state: s) : const _Intro(),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );
}

class _Intro extends ConsumerWidget {
  const _Intro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sync, size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Свяжите свои устройства', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Данные хранятся только на ваших устройствах и передаются напрямую по '
            'Wi‑Fi, зашифрованными. Покажите QR-код на одном устройстве и '
            'отсканируйте его на другом.',
            style: muted,
          ),
          const SizedBox(height: 20),
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(
              onPressed: () => showPairingCode(context),
              icon: const Icon(Icons.qr_code_2),
              label: const Text('Показать QR-код'),
            ),
            OutlinedButton.icon(
              onPressed: () => joinFlow(context),
              icon: Icon(_canScan ? Icons.qr_code_scanner : Icons.input),
              label: Text(_canScan ? 'Сканировать код' : 'Ввести код'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _GroupView extends ConsumerWidget {
  const _GroupView({required this.state});

  final SyncState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = ref.read(syncControllerProvider.notifier);
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(state.running ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    color: state.running ? scheme.primary : scheme.error),
                const SizedBox(width: 12),
                Expanded(child: Text(state.deviceName, style: theme.textTheme.titleMedium)),
                IconButton(
                  tooltip: 'Переименовать',
                  onPressed: () async {
                    final r = await promptText(context,
                        title: 'Имя устройства',
                        labels: const ['Имя'],
                        initial: [state.deviceName]);
                    if (r != null) await c.rename(r[0]);
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                state.running
                    ? 'Это устройство · ${state.addresses.isEmpty ? 'нет сети' : state.addresses.join(', ')}'
                        ' · порт ${state.port}'
                    : 'Синхронизация не запущена',
                style: muted,
              ),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: [
                FilledButton.icon(
                  onPressed: () => showPairingCode(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить устройство'),
                ),
                OutlinedButton.icon(
                  onPressed: state.running ? c.syncAll : c.start,
                  icon: const Icon(Icons.sync),
                  label: Text(state.running ? 'Синхронизировать' : 'Запустить'),
                ),
                OutlinedButton.icon(
                  onPressed: () => joinFlow(context),
                  icon: Icon(_canScan ? Icons.qr_code_scanner : Icons.input),
                  label: const Text('Подключиться по коду'),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('Устройства группы', style: theme.textTheme.titleSmall),
        ),
        const SizedBox(height: 8),
        if (state.peers.isEmpty)
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text('Пока только это устройство. Нажмите «Добавить устройство».',
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          ),
        for (final p in state.peers) _PeerTile(peer: p),
        const SizedBox(height: 24),
        Text(
          'Устройства находят друг друга в одной сети Wi‑Fi. На Windows при первом '
          'запуске разрешите beat доступ к частной сети в окне брандмауэра.',
          style: muted,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            onPressed: () async {
              final ok = await confirm(context,
                  title: 'Покинуть группу?',
                  message: 'Данные на этом устройстве останутся, но перестанут '
                      'синхронизироваться с другими.',
                  action: 'Покинуть');
              if (ok) await c.leaveGroup();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Покинуть группу'),
          ),
        ),
      ],
    );
  }
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'только что';
  if (d.inMinutes < 60) return '${d.inMinutes} мин назад';
  if (d.inHours < 24) return '${d.inHours} ч назад';
  return formatRelativeDateTime(t);
}

class _PeerTile extends ConsumerWidget {
  const _PeerTile({required this.peer});

  final SyncPeer peer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final lower = peer.name.toLowerCase();
    final icon = lower.contains('телефон') || lower.contains('android')
        ? Icons.smartphone
        : Icons.computer;
    final status = peer.syncing
        ? 'Синхронизация…'
        : [
            if (peer.error != null) peer.error!,
            if (peer.lastSync != null) 'синхронизировано ${_ago(peer.lastSync!)}'
            else 'ещё не синхронизировано',
            ?peer.address,
          ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: peer.error == null ? scheme.primary : scheme.error),
      title: Text(peer.name),
      subtitle: Text(status),
      trailing: peer.syncing
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'forget') ref.read(syncControllerProvider.notifier).forgetPeer(peer.id);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'forget', child: Text('Забыть устройство')),
              ],
            ),
    );
  }
}

/// Показывает QR-код и текстовый код подключения (создаёт группу при необходимости).
Future<void> showPairingCode(BuildContext context) async {
  final c = ProviderScope.containerOf(context, listen: false).read(syncControllerProvider.notifier);
  final code = await c.pairingCode();
  if (!context.mounted) return;
  final text = code.encode();
  await showAdaptiveSheet<void>(context, (ctx) {
    final theme = Theme.of(ctx);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Подключить устройство', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            _canScan
                ? 'Отсканируйте код в beat на другом устройстве или скопируйте код.'
                : 'Отсканируйте код в beat на телефоне: «Синхронизация» → «Сканировать код».',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: text,
              size: 240,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Код скопирован')));
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Скопировать код'),
          ),
          const SizedBox(height: 16),
          Text(
            'Код даёт доступ ко всем задачам. Показывайте его только своим устройствам.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Готово')),
        ],
      ),
    );
  });
}

/// Подключение к группе: сканер на Android, ввод кода — везде.
Future<void> joinFlow(BuildContext context) async {
  String? raw;
  if (_canScan) {
    raw = await Navigator.of(context, rootNavigator: true)
        .push<String>(MaterialPageRoute(builder: (_) => const _ScannerPage()));
  } else {
    final r = await promptText(context,
        title: 'Код подключения',
        labels: const ['Вставьте код (beat1:…)'],
        action: 'Подключить');
    raw = r?.first;
  }
  if (raw == null || !context.mounted) return;
  final code = PairingCode.tryParse(raw);
  final messenger = ScaffoldMessenger.of(context);
  if (code == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Это не код подключения beat')));
    return;
  }
  messenger.showSnackBar(SnackBar(content: Text('Подключение к «${code.deviceName}»…')));
  final error = await ProviderScope.containerOf(context, listen: false)
      .read(syncControllerProvider.notifier)
      .join(code);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(error ?? 'Готово: данные синхронизированы с «${code.deviceName}»'),
  ));
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сканировать код'),
        actions: [
          TextButton(
            onPressed: () async {
              final r = await promptText(context,
                  title: 'Код подключения',
                  labels: const ['Вставьте код (beat1:…)'],
                  action: 'Подключить');
              if (r != null && context.mounted) Navigator.pop(context, r.first);
            },
            child: const Text('Ввести код'),
          ),
        ],
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_done) return;
          for (final b in capture.barcodes) {
            final v = b.rawValue;
            if (v != null && v.startsWith(PairingCode.prefix)) {
              _done = true;
              Navigator.pop(context, v);
              return;
            }
          }
        },
      ),
    );
  }
}
