import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:material_ui/material_ui.dart';

import '../module/module_registry.dart';

/// К каким данным относится инструмент — от этого зависят разрешения.
enum ToolScope {
  /// Проекты и задачи Kanban.
  projects,

  /// Личное расписание («Мой день»).
  personal,
}

/// Чтение провайдеров: подходит и `ref.read`, и `container.read`.
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// Ошибка, понятная агенту (уходит ему текстом).
class ToolError implements Exception {
  const ToolError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Инструмент, который модуль даёт ИИ: встроенному помощнику,
/// MCP-серверу и REST API.
class AgentTool {
  const AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.scope,
    required this.readOnly,
    required this.run,
    this.summarize,
  });

  /// Имя в snake_case, например `create_task`.
  final String name;
  final String description;

  /// JSON Schema объекта аргументов.
  final Map<String, Object?> parameters;
  final ToolScope scope;

  /// Только чтение — выполняется без подтверждения.
  final bool readOnly;
  final Future<Object?> Function(Reader read, Map<String, Object?> args) run;

  /// Понятное человеку описание изменения (для подтверждения).
  final String Function(Reader read, Map<String, Object?> args)? summarize;

  String describe(Reader read, Map<String, Object?> args) =>
      summarize?.call(read, args) ?? name;
}

/// Схема объекта для [AgentTool.parameters].
Map<String, Object?> objectSchema(
  Map<String, Map<String, Object?>> properties, {
  List<String> required = const [],
}) =>
    {
      'type': 'object',
      'properties': properties,
      'required': required,
      'additionalProperties': false,
    };

Map<String, Object?> str(String description, {List<String>? enumValues}) => {
      'type': 'string',
      'description': description,
      'enum': ?enumValues,
    };

Map<String, Object?> integer(String description) =>
    {'type': 'integer', 'description': description};

Map<String, Object?> boolean(String description) =>
    {'type': 'boolean', 'description': description};

/// Аргумент-строка (обязательный).
String reqStr(Map<String, Object?> a, String key) {
  final v = a[key];
  if (v is! String || v.trim().isEmpty) throw ToolError('Нужен параметр "$key"');
  return v.trim();
}

String? optStr(Map<String, Object?> a, String key) {
  final v = a[key];
  return v is String && v.trim().isNotEmpty ? v.trim() : null;
}

/// Инструменты всех включённых модулей.
final allAgentToolsProvider = Provider<List<AgentTool>>((ref) => [
      for (final m in ref.watch(enabledModulesProvider)) ...m.agentTools,
    ]);

/// Контекст встроенного помощника на экране модуля.
class AssistantContext {
  const AssistantContext({required this.label, required this.instructions});

  /// «Контекст: Запуск продукта»
  final String label;

  /// Что сообщить модели о текущем экране (id проекта и т.п.).
  final String instructions;
}

typedef AssistantPanelBuilder = Widget Function(AssistantContext context);

/// Панель помощника, если её предоставляет какой-либо модуль (модуль «ИИ»).
final assistantPanelProvider = Provider<AssistantPanelBuilder?>((ref) {
  for (final m in ref.watch(enabledModulesProvider)) {
    final b = m.assistantPanel;
    if (b != null) return b;
  }
  return null;
});
