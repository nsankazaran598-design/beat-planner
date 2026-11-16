import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      ],
    );
  }
}
