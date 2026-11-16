import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/module/app_module.dart';
import 'sync_controller.dart';
import 'sync_page.dart';

class SyncModule extends AppModule {
  const SyncModule();

  @override
  String get id => 'sync';
  @override
  String get title => 'Синхронизация';
  @override
  String get description => 'Обмен данными между вашими устройствами по Wi‑Fi без сервера';

  @override
  List<ModuleDestination> get destinations => [
        ModuleDestination(
          path: '/sync',
          label: 'Синхронизация',
          shortLabel: 'Синхр.',
          icon: Icons.sync_outlined,
          selectedIcon: Icons.sync,
          order: 50,
          builder: (_) => const SyncPage(),
        ),
      ];

  @override
  Future<void> init(ProviderContainer container) async {
    // Не блокируем запуск приложения ожиданием сети.
    container.read(syncControllerProvider.notifier).start();
  }
}
