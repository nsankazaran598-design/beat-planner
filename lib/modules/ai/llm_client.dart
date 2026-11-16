import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/agent/agent_tool.dart';
import 'ai_settings.dart';

/// Вызов инструмента, который запросила модель.
class ToolCall {
  const ToolCall({required this.id, required this.name, required this.args});
  final String id;
  final String name;
  final Map<String, Object?> args;
}

/// Результат вызова, который возвращается модели.
class ToolResultMsg {
  const ToolResultMsg({required this.callId, required this.content, this.isError = false});
  final String callId;
  final String content;
  final bool isError;
}

/// Ответ модели за один шаг.
class LlmTurn {
  const LlmTurn({required this.text, required this.calls, this.refused = false});
  final String text;
  final List<ToolCall> calls;
  final bool refused;
}

class LlmException implements Exception {
  const LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Диалог с моделью. Хранит историю в формате провайдера —
/// так ответы модели (включая служебные блоки) возвращаются без изменений.
abstract class LlmSession {
  Future<LlmTurn> send({String? userText, List<ToolResultMsg> toolResults = const []});

  static LlmSession create({
    required AiSettings settings,
    required String apiKey,
    required String system,
    required List<AgentTool> tools,
  }) =>
      switch (settings.provider) {
        AiProvider.anthropic => AnthropicSession(settings, apiKey, system, tools),
        AiProvider.openai => OpenAiSession(settings, apiKey, system, tools),
      };
}

Future<Map<String, Object?>> _postJson(
  Uri uri,
  Map<String, String> headers,
  Map<String, Object?> body, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    headers.forEach(req.headers.set);
    req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(timeout);
    final text = await res.transform(utf8.decoder).join().timeout(timeout);
    Map<String, Object?>? json;
    try {
      json = jsonDecode(text) as Map<String, Object?>;
    } catch (_) {}
    if (res.statusCode >= 400) {
      final err = json?['error'];
      final msg = err is Map ? err['message'] : (err ?? text);
      throw LlmException('HTTP ${res.statusCode}: $msg');
    }
    if (json == null) throw const LlmException('Ответ сервера не похож на JSON');
    return json;
  } on SocketException catch (e) {
    throw LlmException('Нет соединения с ${uri.host}: ${e.message}');
  } on TimeoutException {
    throw const LlmException('Сервер не ответил вовремя');
  } finally {
    client.close(force: true);
  }
}

String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// Anthropic Messages API (прямой HTTP: официального SDK для Dart нет).
class AnthropicSession implements LlmSession {
  AnthropicSession(this.settings, this.apiKey, this.system, this.tools);

  final AiSettings settings;
  final String apiKey;
  final String system;
  final List<AgentTool> tools;
  final List<Map<String, Object?>> _messages = [];

  static const _version = '2026-10-21';

  /// Модели, для которых включаем серверный fallback при отказе.
  static bool _supportsFallback(String model) =>
      model.startsWith('claude-opus-5') ||
      model.startsWith('claude-fable-5') ||
      model == 'claude-sonnet-5-5';

  @override
  Future<LlmTurn> send({String? userText, List<ToolResultMsg> toolResults = const []}) async {
    if (toolResults.isNotEmpty) {
      _messages.add({
        'role': 'user',
        'content': [
          for (final r in toolResults)
            {
              'type': 'tool_result',
              'tool_use_id': r.callId,
              'content': r.content,
              if (r.isError) 'is_error': true,
            },
        ],
      });
    }
    if (userText != null) _messages.add({'role': 'user', 'content': userText});

    final fallback = _supportsFallback(settings.model);
    final res = await _postJson(
      Uri.parse('${_trimSlash(settings.baseUrl)}/v1/messages'),
      {
        'x-api-key': apiKey,
        'anthropic-version': _version,
        if (fallback) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      },
      {
        'model': settings.model,
        'max_tokens': 16000,
        'system': system,
        if (tools.isNotEmpty)
          'tools': [
            for (final t in tools)
              {'name': t.name, 'description': t.description, 'input_schema': t.parameters},
          ],
        'messages': _messages,
        if (fallback) 'fallbacks': 'default',
      },
    );

    final content = (res['content'] as List?) ?? const [];
    // Ответ целиком (с блоками thinking) — обратно в историю без изменений.
    _messages.add({'role': 'assistant', 'content': content});

    if (res['stop_reason'] == 'refusal') {
      return const LlmTurn(text: 'Модель отказалась отвечать на этот запрос.', calls: [], refused: true);
    }
    final text = StringBuffer();
    final calls = <ToolCall>[];
    for (final b in content.cast<Map>()) {
      switch (b['type']) {
        case 'text':
          text.write(b['text']);
        case 'tool_use':
          calls.add(ToolCall(
            id: b['id'] as String,
            name: b['name'] as String,
            args: Map<String, Object?>.from((b['input'] as Map?) ?? const {}),
          ));
      }
    }
    if (res['stop_reason'] == 'max_tokens' && calls.isEmpty) {
      text.write('\n\n(Ответ обрезан по длине.)');
    }
    return LlmTurn(text: text.toString().trim(), calls: calls);
  }
}

/// OpenAI-совместимый Chat Completions API (LM Studio, Ollama, OpenRouter…).
class OpenAiSession implements LlmSession {
  OpenAiSession(this.settings, this.apiKey, String system, this.tools)
      : _messages = [
          {'role': 'system', 'content': system},
        ];

  final AiSettings settings;
  final String apiKey;
  final List<AgentTool> tools;
  final List<Map<String, Object?>> _messages;

  @override
  Future<LlmTurn> send({String? userText, List<ToolResultMsg> toolResults = const []}) async {
    for (final r in toolResults) {
      _messages.add({'role': 'tool', 'tool_call_id': r.callId, 'content': r.content});
    }
    if (userText != null) _messages.add({'role': 'user', 'content': userText});

    final res = await _postJson(
      Uri.parse('${_trimSlash(settings.baseUrl)}/chat/completions'),
      {if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey'},
      {
        'model': settings.model,
        'messages': _messages,
        if (tools.isNotEmpty)
          'tools': [
            for (final t in tools)
              {
                'type': 'function',
                'function': {
                  'name': t.name,
                  'description': t.description,
                  'parameters': t.parameters,
                },
              },
          ],
      },
    );
    final choices = res['choices'] as List?;
    if (choices == null || choices.isEmpty) throw const LlmException('Пустой ответ модели');
    final msg = Map<String, Object?>.from((choices.first as Map)['message'] as Map);
    _messages.add(msg);

    final calls = <ToolCall>[];
    for (final c in (msg['tool_calls'] as List?) ?? const []) {
      final f = (c as Map)['function'] as Map;
      Map<String, Object?> args;
      try {
        final raw = f['arguments'];
        args = raw is String && raw.isNotEmpty
            ? Map<String, Object?>.from(jsonDecode(raw) as Map)
            : raw is Map
                ? Map<String, Object?>.from(raw)
                : {};
      } catch (_) {
        args = {};
      }
      calls.add(ToolCall(id: '${c['id']}', name: f['name'] as String, args: args));
    }
    return LlmTurn(text: ((msg['content'] as String?) ?? '').trim(), calls: calls);
  }
}

/// Проверка подключения: короткий запрос без инструментов.
Future<String> testConnection(AiSettings s, String apiKey) async {
  if (s.model.trim().isEmpty) throw const LlmException('Укажите модель');
  if (s.provider == AiProvider.anthropic && apiKey.isEmpty) {
    throw const LlmException('Укажите API-ключ');
  }
  final session = LlmSession.create(
    settings: s,
    apiKey: apiKey,
    system: 'Ответь одним словом.',
    tools: const [],
  );
  final t = await session.send(userText: 'Скажи «готово».');
  return t.text.isEmpty ? 'Модель ответила' : t.text;
}
