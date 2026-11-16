// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:beat/core/agent/agent_tool.dart';
import 'package:beat/core/data/data_store.dart';
import 'package:beat/core/data/log_storage.dart';
import 'package:beat/core/data/providers.dart';
import 'package:beat/core/settings/settings_controller.dart';
import 'package:beat/modules/ai/agent_server.dart';
import 'package:beat/modules/ai/ai_settings.dart';
import 'package:beat/modules/ai/assistant_controller.dart';
import 'package:beat/modules/ai/llm_client.dart';
import 'package:beat/modules/ai/tool_gateway.dart';
import 'package:beat/modules/kanban/kanban_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container({SessionFactory? sessions}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = await DataStore.open(MemoryLogStorage());
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    dataStoreProvider.overrideWithValue(store),
    if (sessions != null) sessionFactoryProvider.overrideWithValue(sessions),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _set(ProviderContainer c, AiSettings Function(AiSettings) f) =>
    c.read(aiSettingsProvider.notifier).update(f(c.read(aiSettingsProvider)));

/// Модель-заглушка: отдаёт заранее заданные ответы и запоминает запросы.
class ScriptedSession implements LlmSession {
  ScriptedSession(this.turns);
  final List<LlmTurn> turns;
  final sent = <({String? text, List<ToolResultMsg> results})>[];

  @override
  Future<LlmTurn> send({String? userText, List<ToolResultMsg> toolResults = const []}) async {
    sent.add((text: userText, results: toolResults));
    return turns.removeAt(0);
  }
}

/// Мок-сервер, отвечающий по очереди и сохраняющий запросы.
Future<(HttpServer, List<({Map<String, String> headers, Map<String, Object?> body})>)> _mock(
    List<Map<String, Object?>> replies) async {
  final log = <({Map<String, String> headers, Map<String, Object?> body})>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final headers = <String, String>{};
    req.headers.forEach((k, v) => headers[k] = v.join(','));
    final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, Object?>;
    log.add((headers: headers, body: body));
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(replies.removeAt(0)));
    await req.response.close();
  });
  addTearDown(() => server.close(force: true));
  return (server, log);
}

void main() {
  group('gateway and permissions', () {
    test('tools follow permissions', () async {
      final c = await _container();
      final g = c.read(toolGatewayProvider);
      var names = g.availableTools().map((t) => t.name).toSet();
      expect(names, containsAll(['list_projects', 'create_task']));
      expect(names, isNot(contains('list_day_items')), reason: 'personal off by default');

      await _set(c, (s) => s.copyWith(personalAccess: true, allowChanges: false));
      names = g.availableTools().map((t) => t.name).toSet();
      expect(names, contains('list_day_items'));
      expect(names, isNot(contains('create_task')));
      expect(names, isNot(contains('create_day_item')));
    });

    test('writes wait for confirmation, then apply', () async {
      final c = await _container();
      final repo = c.read(kanbanRepositoryProvider);
      final p = await repo.createProject('Запуск');
      final g = c.read(toolGatewayProvider);

      final out = await g.call('create_task', {'project_id': p, 'title': 'Тексты'},
          ChangeSource.external);
      expect(out.pending, isNotNull);
      expect(out.pending!.summary, 'Добавить задачу «Тексты» в «Запуск»');
      expect(repo.tasks(p), isEmpty);

      final status = await g.call(ToolGateway.statusTool,
          {'change_id': out.pending!.id}, ChangeSource.external);
      expect((status.data! as Map)['status'], 'pending');

      await c.read(pendingChangesProvider.notifier).apply(out.pending!.id);
      expect(repo.tasks(p).single.title, 'Тексты');
      expect(c.read(pendingCountProvider), 0);
    });

    test('without confirmation writes apply directly; errors are reported', () async {
      final c = await _container();
      await _set(c, (s) => s.copyWith(confirmChanges: false));
      final repo = c.read(kanbanRepositoryProvider);
      final p = await repo.createProject('P');
      final g = c.read(toolGatewayProvider);

      final out = await g.call('create_task',
          {'project_id': p, 'title': 'X', 'column': 'В работе', 'priority': 'high', 'due': '2026-11-20'},
          ChangeSource.assistant);
      expect(out.isError, isFalse);
      final t = repo.tasks(p).single;
      expect(repo.columns(p).firstWhere((x) => x.id == t.columnId).name, 'В работе');

      final bad = await g.call('move_task', {'task_id': t.id, 'column': 'Нет такой'},
          ChangeSource.assistant);
      expect(bad.isError, isTrue);
      expect('${bad.data}', contains('Колонка'));
    });
  });

  test('assistant loop: reads, proposes, answers', () async {
    late ScriptedSession session;
    final c = await _container(sessions: ({required settings, required apiKey, required system, required tools}) {
      expect(system, contains('project_id'));
      expect(tools.map((t) => t.name), contains('create_task'));
      return session;
    });
    await c.read(secretStoreProvider).write(apiKeySecret, 'sk-test');
    final p = await c.read(kanbanRepositoryProvider).createProject('Запуск');

    session = ScriptedSession([
      const LlmTurn(text: '', calls: [ToolCall(id: 'c1', name: 'list_tasks', args: {})]),
      LlmTurn(text: 'Предлагаю шаг:', calls: [
        ToolCall(id: 'c2', name: 'create_task', args: {'project_id': p, 'title': 'Сценарий'}),
      ]),
      const LlmTurn(text: 'Готово, жду подтверждения.', calls: []),
    ]);

    const ctx = AssistantContext(label: 'Контекст: Запуск', instructions: 'project_id: X');
    await c.read(assistantProvider.notifier).send('Разбей на шаги', ctx);

    final kinds = c.read(assistantProvider).entries.map((e) => e.kind).toList();
    expect(kinds, [
      ChatKind.user,
      ChatKind.tool,
      ChatKind.assistant,
      ChatKind.proposal,
      ChatKind.assistant,
    ]);
    // list_tasks без project_id → ошибка уходит модели, а не пользователю.
    expect(session.sent[1].results.single.isError, isTrue);
    expect(jsonDecode(session.sent[2].results.single.content)['status'], 'pending_confirmation');
    expect(c.read(pendingCountProvider), 1);
  });

  test('anthropic request shape and tool_result round-trip', () async {
    final (server, log) = await _mock([
      {
        'content': [
          {'type': 'thinking', 'thinking': '', 'signature': 'sig'},
          {'type': 'tool_use', 'id': 'tu1', 'name': 'list_projects', 'input': {}},
        ],
        'stop_reason': 'tool_use',
      },
      {
        'content': [
          {'type': 'text', 'text': 'Два проекта.'},
        ],
        'stop_reason': 'end_turn',
      },
    ]);
    final s = const AiSettings().copyWith(baseUrl: 'http://127.0.0.1:${server.port}');
    final tool = AgentTool(
      name: 'list_projects',
      description: 'd',
      parameters: objectSchema(const {}),
      scope: ToolScope.projects,
      readOnly: true,
      run: (_, _) async => [],
    );
    final session = AnthropicSession(s, 'sk-test', 'sys', [tool]);
    final t1 = await session.send(userText: 'Привет');
    expect(t1.calls.single.name, 'list_projects');
    final t2 = await session.send(toolResults: [const ToolResultMsg(callId: 'tu1', content: '[]')]);
    expect(t2.text, 'Два проекта.');

    final first = log[0];
    expect(first.headers['x-api-key'], 'sk-test');
    expect(first.headers['anthropic-version'], '2026-10-21');
    expect(first.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
    expect(first.body['model'], 'claude-opus-5-5');
    expect(first.body['fallbacks'], 'default');
    expect(first.body.containsKey('temperature'), isFalse);
    expect(((first.body['tools']! as List).single as Map)['input_schema'], isNotNull);

    final msgs = log[1].body['messages']! as List;
    expect(msgs.length, 3);
    // Ответ модели (включая thinking) возвращён без изменений.
    expect(((msgs[1] as Map)['content'] as List).first, containsPair('type', 'thinking'));
    final result = ((msgs[2] as Map)['content'] as List).single as Map;
    expect(result['type'], 'tool_result');
    expect(result['tool_use_id'], 'tu1');
  });

  test('openai-compatible request shape', () async {
    final (server, log) = await _mock([
      {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': null,
              'tool_calls': [
                {'id': 'x1', 'type': 'function', 'function': {'name': 'list_projects', 'arguments': '{}'}},
              ],
            },
          },
        ],
      },
      {
        'choices': [
          {'message': {'role': 'assistant', 'content': 'Ок'}},
        ],
      },
    ]);
    final s = const AiSettings().copyWith(
        provider: AiProvider.openai, baseUrl: 'http://127.0.0.1:${server.port}/v1', model: 'local');
    final session = OpenAiSession(s, '', 'sys', const []);
    final t1 = await session.send(userText: 'hi');
    expect(t1.calls.single.id, 'x1');
    await session.send(toolResults: [const ToolResultMsg(callId: 'x1', content: '[]')]);
    final msgs = log[1].body['messages']! as List;
    expect((msgs.first as Map)['role'], 'system');
    expect((msgs.last as Map)['role'], 'tool');
    expect(log[0].headers.containsKey('authorization'), isFalse);
  });

  test('MCP and REST over localhost', () async {
    final c = await _container();
    await _set(c, (s) => s.copyWith(confirmChanges: false));
    await c.read(kanbanRepositoryProvider).createProject('Запуск');
    final server = AgentServer(
      gateway: c.read(toolGatewayProvider),
      token: () => 'tok',
      changes: () => c.read(pendingChangesProvider),
    );
    final port = await server.start(port: 0);
    addTearDown(server.stop);

    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    Future<(int, Object?)> post(String path, Object? body, {String token = 'tok'}) async {
      final req = await http.post('127.0.0.1', port, path);
      req.headers.set('authorization', 'Bearer $token');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
    }

    expect((await post('/mcp', {}, token: 'wrong')).$1, 401);

    final (_, init) = await post('/mcp', {
      'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
      'params': {'protocolVersion': '2025-06-18', 'capabilities': {}, 'clientInfo': {'name': 't'}},
    });
    expect(((init! as Map)['result'] as Map)['protocolVersion'], '2025-06-18');

    final (code, _) = await post('/mcp', {'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    expect(code, 202);

    final (_, list) = await post('/mcp', {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
    final tools = (((list! as Map)['result'] as Map)['tools'] as List).map((t) => (t as Map)['name']);
    expect(tools, contains('list_projects'));

    final (_, call) = await post('/mcp', {
      'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call',
      'params': {'name': 'list_projects', 'arguments': {}},
    });
    final result = (call! as Map)['result'] as Map;
    expect(result['isError'], isFalse);
    expect(((result['content'] as List).single as Map)['text'], contains('Запуск'));

    final (restCode, rest) = await post('/api/v1/tools/list_projects', {});
    expect(restCode, 200);
    expect((rest! as Map)['ok'], isTrue);
  });
}
