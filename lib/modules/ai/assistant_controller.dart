import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/agent/agent_tool.dart';
import '../../core/ui/format.dart';
import 'ai_settings.dart';
import 'llm_client.dart';
import 'tool_gateway.dart';

enum ChatKind { user, assistant, tool, proposal, error }

@immutable
class ChatEntry {
  const ChatEntry(this.kind, this.text, {this.changeId});

  final ChatKind kind;
  final String text;

  /// Для [ChatKind.proposal] — id изменения в очереди.
  final String? changeId;
}

@immutable
class AssistantState {
  const AssistantState({this.entries = const [], this.busy = false});

  final List<ChatEntry> entries;
  final bool busy;

  AssistantState copyWith({List<ChatEntry>? entries, bool? busy}) =>
      AssistantState(entries: entries ?? this.entries, busy: busy ?? this.busy);
}

/// Фабрика сессий — в тестах подменяется фейковой моделью.
typedef SessionFactory = LlmSession Function({
  required AiSettings settings,
  required String apiKey,
  required String system,
  required List<AgentTool> tools,
});

final sessionFactoryProvider = Provider<SessionFactory>((ref) => LlmSession.create);

final assistantProvider =
    NotifierProvider<AssistantController, AssistantState>(AssistantController.new);

class AssistantController extends Notifier<AssistantState> {
  static const maxSteps = 10;

  LlmSession? _session;
  String? _sessionContext;

  @override
  AssistantState build() => const AssistantState();

  void reset() {
    _session = null;
    _sessionContext = null;
    state = const AssistantState();
  }

  void _add(ChatEntry e) => state = state.copyWith(entries: [...state.entries, e]);

  Future<void> send(String text, AssistantContext ctx) async {
    final message = text.trim();
    if (message.isEmpty || state.busy) return;
    _add(ChatEntry(ChatKind.user, message));
    state = state.copyWith(busy: true);
    try {
      final settings = ref.read(aiSettingsProvider);
      final apiKey = await ref.read(secretStoreProvider).read(apiKeySecret) ?? '';
      if (settings.model.trim().isEmpty ||
          (settings.provider == AiProvider.anthropic && apiKey.isEmpty)) {
        _add(const ChatEntry(ChatKind.error,
            'Модель не подключена. Укажите провайдера и ключ в разделе «ИИ и подключения».'));
        return;
      }
      final gateway = ref.read(toolGatewayProvider);
      if (_session == null || _sessionContext != ctx.instructions) {
        _session = ref.read(sessionFactoryProvider)(
          settings: settings,
          apiKey: apiKey,
          system: _systemPrompt(ctx, settings),
          tools: gateway.availableTools(),
        );
        _sessionContext = ctx.instructions;
      }
      final session = _session!;

      var turn = await session.send(userText: message);
      for (var step = 0; step < maxSteps; step++) {
        if (turn.text.isNotEmpty) _add(ChatEntry(ChatKind.assistant, turn.text));
        if (turn.calls.isEmpty) return;
        final results = <ToolResultMsg>[];
        for (final call in turn.calls) {
          final out = await gateway.call(call.name, call.args, ChangeSource.assistant);
          if (out.pending != null) {
            _add(ChatEntry(ChatKind.proposal, out.pending!.summary, changeId: out.pending!.id));
          } else {
            _add(ChatEntry(ChatKind.tool, _toolLabel(call.name)));
          }
          results.add(ToolResultMsg(
            callId: call.id,
            content: out.data is String ? out.data! as String : jsonEncode(out.data),
            isError: out.isError,
          ));
        }
        turn = await session.send(toolResults: results);
      }
      _add(const ChatEntry(ChatKind.error, 'Помощник остановлен: слишком много шагов подряд.'));
    } on LlmException catch (e) {
      _add(ChatEntry(ChatKind.error, e.message));
      _session = null; // история могла остаться в неконсистентном состоянии
    } catch (e) {
      _add(ChatEntry(ChatKind.error, 'Ошибка: $e'));
      _session = null;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  static String _toolLabel(String name) => switch (name) {
        'list_projects' => 'Смотрю проекты',
        'list_tasks' => 'Смотрю задачи',
        'list_day_items' => 'Смотрю расписание',
        _ => 'Выполнено: $name',
      };

  String _systemPrompt(AssistantContext ctx, AiSettings s) {
    final now = DateTime.now();
    return [
      'Ты — ИИ-помощник в планировщике задач beat. Пользователь пишет по-русски; '
          'отвечай по-русски, коротко и по делу.',
      'Сегодня ${formatFullDate(now)}, ${formatHm(now)}.',
      ctx.instructions,
      'Помогай планировать: разбивай большие задачи на конкретные шаги, '
          'находи главный фокус. Прежде чем отвечать про задачи, посмотри их инструментами.',
      if (s.allowChanges && s.confirmChanges)
        'Изменения (создание, правка, перенос, удаление) не применяются сразу: '
            'они уходят пользователю на подтверждение. Предлагай их инструментами и '
            'скажи, что ждёшь подтверждения.',
      if (s.allowChanges && !s.confirmChanges)
        'Ты можешь сразу создавать и менять задачи инструментами.',
      if (!s.allowChanges) 'Менять данные тебе не разрешено — только советуй.',
      if (!s.personalAccess)
        'Личное расписание пользователя («Мой день») тебе недоступно.',
    ].join('\n\n');
  }
}
