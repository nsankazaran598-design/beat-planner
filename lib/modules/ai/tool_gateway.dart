import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_tool.dart';
import '../../core/data/log_storage.dart' show generateId;
import 'ai_settings.dart';

/// Кто предложил изменение.
enum ChangeSource { assistant, external }

enum ChangeStatus { pending, applied, rejected, failed }

/// Изменение, которое ждёт подтверждения пользователя.
@immutable
class PendingChange {
  const PendingChange({
    required this.id,
    required this.tool,
    required this.args,
    required this.summary,
    required this.source,
    required this.createdAt,
    this.status = ChangeStatus.pending,
    this.result,
  });

  final String id;
  final String tool;
  final Map<String, Object?> args;
  final String summary;
  final ChangeSource source;
  final DateTime createdAt;
  final ChangeStatus status;
  final String? result;

  PendingChange withStatus(ChangeStatus s, [String? result]) => PendingChange(
        id: id,
        tool: tool,
        args: args,
        summary: summary,
        source: source,
        createdAt: createdAt,
        status: s,
        result: result,
      );

  Map<String, Object?> toJson() => {
        'change_id': id,
        'tool': tool,
        'summary': summary,
        'status': status.name,
        'result': ?result,
      };
}

/// Очередь изменений на подтверждение (живёт, пока работает приложение).
final pendingChangesProvider =
    NotifierProvider<PendingChangesController, List<PendingChange>>(
        PendingChangesController.new);

class PendingChangesController extends Notifier<List<PendingChange>> {
  @override
  List<PendingChange> build() => const [];

  PendingChange add(String tool, Map<String, Object?> args, String summary, ChangeSource src) {
    final c = PendingChange(
      id: generateId(6),
      tool: tool,
      args: args,
      summary: summary,
      source: src,
      createdAt: DateTime.now(),
    );
    state = [...state, c];
    return c;
  }

  PendingChange? byId(String id) => state.where((c) => c.id == id).firstOrNull;

  /// Выполнить изменение.
  Future<void> apply(String id) async {
    final c = byId(id);
    if (c == null || c.status != ChangeStatus.pending) return;
    final tool = ref.read(allAgentToolsProvider).where((t) => t.name == c.tool).firstOrNull;
    if (tool == null) {
      _set(c.withStatus(ChangeStatus.failed, 'Инструмент недоступен'));
      return;
    }
    try {
      final r = await tool.run(ref.read, c.args);
      _set(c.withStatus(ChangeStatus.applied, '$r'));
    } catch (e) {
      _set(c.withStatus(ChangeStatus.failed, '$e'));
    }
  }

  Future<void> applyAll(Iterable<String> ids) async {
    for (final id in ids) {
      await apply(id);
    }
  }

  void reject(String id) {
    final c = byId(id);
    if (c != null && c.status == ChangeStatus.pending) _set(c.withStatus(ChangeStatus.rejected));
  }

  /// Убрать завершённые (применённые/отклонённые) из списка.
  void clearDone() =>
      state = state.where((c) => c.status == ChangeStatus.pending).toList();

  void _set(PendingChange c) => state = [for (final x in state) x.id == c.id ? c : x];
}

final pendingCountProvider = Provider<int>(
  (ref) => ref.watch(pendingChangesProvider).where((c) => c.status == ChangeStatus.pending).length,
);

/// Ответ на вызов инструмента.
class ToolOutcome {
  const ToolOutcome(this.data, {this.isError = false, this.pending});

  final Object? data;
  final bool isError;

  /// Если изменение отправлено на подтверждение.
  final PendingChange? pending;
}

/// Единая точка вызова инструментов с учётом разрешений.
/// Через неё работают встроенный помощник, MCP-сервер и REST API.
class ToolGateway {
  ToolGateway(this._ref);

  final Ref _ref;

  static const statusTool = 'get_change_status';

  /// Инструменты, доступные при текущих разрешениях.
  List<AgentTool> availableTools({bool external = false}) {
    final s = _ref.read(aiSettingsProvider);
    final tools = [
      for (final t in _ref.read(allAgentToolsProvider))
        if (_allowed(t, s)) t,
    ];
    if (external && s.confirmChanges && s.allowChanges) tools.add(_statusTool());
    return tools;
  }

  bool _allowed(AgentTool t, AiSettings s) {
    final scopeOk = switch (t.scope) {
      ToolScope.projects => s.readTasks,
      ToolScope.personal => s.personalAccess,
    };
    return scopeOk && (t.readOnly || s.allowChanges);
  }

  Future<ToolOutcome> call(String name, Map<String, Object?> args, ChangeSource source) async {
    final tool = availableTools(external: source == ChangeSource.external)
        .where((t) => t.name == name)
        .firstOrNull;
    if (tool == null) {
      return ToolOutcome('Инструмент "$name" недоступен или запрещён настройками', isError: true);
    }
    final s = _ref.read(aiSettingsProvider);
    if (!tool.readOnly && s.confirmChanges) {
      final summary = tool.describe(_ref.read, args);
      final c = _ref.read(pendingChangesProvider.notifier).add(name, args, summary, source);
      return ToolOutcome({
        'status': 'pending_confirmation',
        'change_id': c.id,
        'message': 'Изменение «$summary» ждёт подтверждения пользователя в приложении.',
      }, pending: c);
    }
    try {
      return ToolOutcome(await tool.run(_ref.read, args));
    } on ToolError catch (e) {
      return ToolOutcome(e.message, isError: true);
    } catch (e) {
      return ToolOutcome('Ошибка: $e', isError: true);
    }
  }

  AgentTool _statusTool() => AgentTool(
        name: statusTool,
        description: 'Статус изменения, отправленного на подтверждение: '
            'pending, applied, rejected или failed.',
        parameters: objectSchema({'change_id': str('id изменения')}, required: ['change_id']),
        scope: ToolScope.projects,
        readOnly: true,
        run: (read, a) async {
          final c = read(pendingChangesProvider.notifier).byId(reqStr(a, 'change_id'));
          if (c == null) throw const ToolError('Изменение не найдено');
          return c.toJson();
        },
      );
}

final toolGatewayProvider = Provider<ToolGateway>((ref) => ToolGateway(ref));
