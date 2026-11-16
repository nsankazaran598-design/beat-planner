import 'package:material_ui/material_ui.dart';

import '../../core/module/app_module.dart';
import '../../core/shell/page_scaffold.dart';

class AiModule extends AppModule {
  const AiModule();

  @override
  String get id => 'ai';
  @override
  String get title => 'ИИ и подключения';
  @override
  String get description => 'Помощник, MCP-сервер и локальный API для агентов';

  @override
  List<ModuleDestination> get destinations => [
        ModuleDestination(
          path: '/ai',
          label: 'ИИ',
          icon: Icons.auto_awesome_outlined,
          selectedIcon: Icons.auto_awesome,
          order: 40,
          builder: (_) => const PageScaffold(
            breadcrumb: 'Рабочее пространство / Настройки',
            title: 'ИИ и подключения',
            subtitle: 'Ваш помощник, ваш провайдер, ваши правила',
            body: ComingSoon(
              icon: Icons.auto_awesome_outlined,
              text: 'Подключение ИИ появится в v0.6',
            ),
          ),
        ),
      ];
}
