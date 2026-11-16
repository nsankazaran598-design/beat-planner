import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/agent/agent_tool.dart';
import '../../core/module/app_module.dart';
import 'agent_server.dart';
import 'ai_page.dart';
import 'tool_gateway.dart';
import 'widgets/assistant_panel.dart';

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
          label: 'ИИ и подключения',
          shortLabel: 'ИИ',
          icon: Icons.auto_awesome_outlined,
          selectedIcon: Icons.auto_awesome,
          order: 40,
          badge: pendingCountProvider,
          builder: (_) => const AiPage(),
        ),
      ];

  @override
  AssistantPanelBuilder get assistantPanel =>
      (ctx) => AssistantPanel(assistantContext: ctx);

  @override
  Future<void> init(ProviderContainer container) =>
      container.read(agentServerProvider.notifier).init();
}
