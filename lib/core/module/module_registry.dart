import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/modules.dart';
import '../settings/settings_controller.dart';
import 'app_module.dart';

/// Все модули, которые собраны в приложение.
final allModulesProvider = Provider<List<AppModule>>((ref) => registeredModules);

/// Модули, включённые пользователем.
final enabledModulesProvider = Provider<List<AppModule>>((ref) {
  final all = ref.watch(allModulesProvider);
  final disabled = ref.watch(settingsProvider.select((s) => s.disabledModules));
  return [
    for (final m in all)
      if (!m.canDisable || !disabled.contains(m.id)) m,
  ];
});

/// Пункты навигации всех включённых модулей, отсортированные по [ModuleDestination.order].
final destinationsProvider = Provider<List<ModuleDestination>>((ref) {
  final modules = ref.watch(enabledModulesProvider);
  final list = [for (final m in modules) ...m.destinations];
  list.sort((a, b) => a.order.compareTo(b.order));
  return list;
});
