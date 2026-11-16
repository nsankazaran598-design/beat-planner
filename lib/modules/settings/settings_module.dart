import 'package:material_ui/material_ui.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/data/providers.dart';
import '../../core/desktop/desktop.dart';
import '../../core/module/app_module.dart';
import '../../core/module/module_registry.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/shell/page_scaffold.dart';

class SettingsModule extends AppModule {
  const SettingsModule();

  @override
  String get id => 'settings';
  @override
  String get title => 'Настройки';
  @override
  String get description => 'Тема оформления и управление модулями';
  @override
  bool get canDisable => false;

  @override
  List<ModuleDestination> get destinations => [
        ModuleDestination(
          path: '/settings',
          label: 'Настройки',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          order: 1000,
          builder: (_) => const PageScaffold(
            breadcrumb: 'Рабочее пространство / Настройки',
            title: 'Настройки',
            body: _SettingsView(),
          ),
        ),
      ];
}

class _SettingsView extends ConsumerWidget {
  const _SettingsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final modules = ref.watch(allModulesProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Text('Тема', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('Системная')),
            ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Светлая')),
            ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Болотная')),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (s) => controller.setThemeMode(s.first),
        ),
        if (isDesktopWindows) ...[
          const SizedBox(height: 32),
          Text('Windows', style: theme.textTheme.titleMedium),
          const _DesktopSettings(),
        ],
        const SizedBox(height: 32),
        Text('Модули', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Выключенные модули скрываются из меню. Данные при этом сохраняются.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        for (final m in modules)
          if (m.canDisable)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(m.title),
              subtitle: Text(m.description),
              value: !settings.disabledModules.contains(m.id),
              onChanged: (v) => controller.setModuleEnabled(m.id, v),
            ),
        const SizedBox(height: 32),
        const _About(),
      ],
    );
  }
}

class _DesktopSettings extends ConsumerWidget {
  const _DesktopSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(desktopSettingsProvider);
    final c = ref.read(desktopSettingsProvider.notifier);
    return Column(children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Сворачивать в трей при закрытии'),
        subtitle: const Text('Напоминания продолжат приходить, пока beat в трее'),
        value: s.closeToTray,
        onChanged: c.setCloseToTray,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Запускать вместе с Windows'),
        subtitle: const Text('beat стартует свёрнутым в трей'),
        value: s.launchAtStartup,
        onChanged: c.setLaunchAtStartup,
      ),
    ]);
  }
}

final _packageInfoProvider = FutureProvider<PackageInfo?>((ref) async {
  try {
    return await PackageInfo.fromPlatform();
  } catch (_) {
    return null;
  }
});

class _About extends ConsumerWidget {
  const _About();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final info = ref.watch(_packageInfoProvider).value;
    final dir = ref.watch(dataDirProvider);
    final store = ref.watch(dataStoreProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('О приложении', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('beat ${info == null ? '' : '${info.version} (${info.buildNumber})'}',
            style: theme.textTheme.bodyMedium),
        Text('Устройство: ${store.deviceId}', style: muted),
        if (dir != null) ...[
          const SizedBox(height: 4),
          Text('Данные: $dir', style: muted),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (isDesktopWindows)
              OutlinedButton.icon(
                onPressed: () => Process.run('explorer', [dir]),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Открыть папку данных'),
              ),
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: dir)),
              child: const Text('Скопировать путь'),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Резервная копия — это просто копия этой папки.', style: muted),
        ],
      ],
    );
  }
}
