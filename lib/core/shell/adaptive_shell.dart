import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../module/app_module.dart';
import '../module/module_registry.dart';
import 'breakpoints.dart';

/// Оболочка приложения: меню слева на десктопе, rail на планшете,
/// нижняя навигация на телефоне.
class AdaptiveShell extends ConsumerWidget {
  const AdaptiveShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = ref.watch(destinationsProvider);
    final selected = destinations.indexWhere((d) => location.startsWith(d.path));
    final index = selected < 0 ? 0 : selected;
    void go(int i) => context.go(destinations[i].path);

    final layout = Breakpoints.of(context);
    switch (layout) {
      case LayoutSize.expanded:
        return Scaffold(
          body: Row(children: [
            _Sidebar(
              destinations: destinations,
              selected: index,
              onSelect: go,
              sections: [
                for (final m in ref.watch(enabledModulesProvider))
                  ?m.sidebarSection,
              ],
            ),
            Expanded(child: child),
          ]),
        );
      case LayoutSize.medium:
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: FloatingActionButton(
                  elevation: 0,
                  tooltip: 'Новая задача',
                  onPressed: () => _quickAdd(context),
                  child: const Icon(Icons.add),
                ),
              ),
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(child: child),
          ]),
        );
      case LayoutSize.compact:
        return Scaffold(
          body: SafeArea(bottom: false, child: child),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Новая задача',
            onPressed: () => _quickAdd(context),
            child: const Icon(Icons.add),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: go,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: [
              for (final d in destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        );
    }
  }
}

void _quickAdd(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  final modules = container.read(enabledModulesProvider);
  final location =
      GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
  AppModule? current;
  for (final m in modules) {
    if (m.destinations.any((d) => location.startsWith(d.path))) current = m;
  }
  final handler = current?.quickAdd ??
      modules.map((m) => m.quickAdd).nonNulls.firstOrNull;
  if (handler != null) {
    handler(context);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет модулей, которые умеют создавать задачи')),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destinations,
    required this.selected,
    required this.onSelect,
    this.sections = const [],
  });

  final List<ModuleDestination> destinations;
  final int selected;
  final ValueChanged<int> onSelect;
  final List<WidgetBuilder> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: 232,
      color: scheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('beat',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(color: scheme.primary)),
                const SizedBox(height: 4),
                Text('Пространство для важного',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => _quickAdd(context),
              icon: const Icon(Icons.add),
              label: const Text('Новая задача'),
            ),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < destinations.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _SidebarItem(
                destination: destinations[i],
                selected: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
          for (final section in sections) ...[
            const SizedBox(height: 24),
            Builder(builder: section),
          ],
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ModuleDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(selected ? destination.selectedIcon : destination.icon,
                  color: fg, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(destination.label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(color: fg)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
