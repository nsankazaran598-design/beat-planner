import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_settings.dart';
import 'tool_gateway.dart';

const agentApiPort = 47830;
const _serverVersion = '0.6.0';
const _mcpVersions = ['2025-11-25', '2025-06-18', '2025-03-26'];

/// Локальный сервер для внешних агентов (Claude Code, Cursor, скрипты).
///
/// * `POST /mcp` — MCP (Streamable HTTP, ответы JSON): initialize, ping,
///   tools/list, tools/call.
/// * REST: `GET /api/v1/tools`, `POST /api/v1/tools/<name>`,
///   `GET /api/v1/changes`.
///
/// Слушает только 127.0.0.1 и требует `Authorization: Bearer <токен>`.
class AgentServer {
  AgentServer({required this.gateway, required this.token, required this.changes});

  final ToolGateway gateway;
  final String Function() token;
  final List<PendingChange> Function() changes;

  HttpServer? _server;
  int? get port => _server?.port;

  Future<int> start({int port = agentApiPort}) async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server = s;
    s.listen(_handle);
    return s.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      // Защита от DNS-rebinding: браузерные запросы — только с localhost.
      final origin = req.headers.value('origin');
      if (origin != null) {
        final host = Uri.tryParse(origin)?.host;
        if (host != 'localhost' && host != '127.0.0.1') {
          return _json(res, 403, {'error': 'Origin not allowed'});
        }
      }
      final auth = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
      if (auth != 'Bearer ${token()}') {
        return _json(res, 401, {'error': 'Нужен заголовок Authorization: Bearer <токен>'});
      }

      final path = req.uri.path;
      if (path == '/mcp') {
        if (req.method != 'POST') return _json(res, 405, {'error': 'Use POST'});
        return await _mcp(req, res);
      }
      if (path == '/api/v1/tools' && req.method == 'GET') {
        return _json(res, 200, [
          for (final t in gateway.availableTools(external: true))
            {
              'name': t.name,
              'description': t.description,
              'parameters': t.parameters,
              'read_only': t.readOnly,
            },
        ]);
      }
      if (path.startsWith('/api/v1/tools/') && req.method == 'POST') {
        final name = path.substring('/api/v1/tools/'.length);
        final body = await utf8.decoder.bind(req).join();
        final args = body.trim().isEmpty
            ? <String, Object?>{}
            : Map<String, Object?>.from(jsonDecode(body) as Map);
        final out = await gateway.call(name, args, ChangeSource.external);
        return _json(res, out.isError ? 400 : 200, {
          'ok': !out.isError,
          if (out.isError) 'error': out.data else 'result': out.data,
        });
      }
      if (path == '/api/v1/changes' && req.method == 'GET') {
        return _json(res, 200, [for (final c in changes()) c.toJson()]);
      }
      return _json(res, 404, {'error': 'Not found'});
    } catch (e) {
      debugPrint('agent server: $e');
      return _json(res, 400, {'error': '$e'});
    }
  }

  Future<void> _mcp(HttpRequest req, HttpResponse res) async {
    final body = jsonDecode(await utf8.decoder.bind(req).join());
    if (body is List) {
      final replies = [
        for (final m in body) ?await _rpc(Map<String, Object?>.from(m as Map)),
      ];
      if (replies.isEmpty) return _empty(res, 202);
      return _json(res, 200, replies);
    }
    final reply = await _rpc(Map<String, Object?>.from(body as Map));
    if (reply == null) return _empty(res, 202);
    return _json(res, 200, reply);
  }

  /// Один JSON-RPC запрос. null — для уведомлений (без id).
  Future<Map<String, Object?>?> _rpc(Map<String, Object?> m) async {
    final id = m['id'];
    final method = m['method'] as String?;
    final params = Map<String, Object?>.from((m['params'] as Map?) ?? const {});
    if (id == null) return null;

    Map<String, Object?> ok(Object? result) => {'jsonrpc': '2.0', 'id': id, 'result': result};
    Map<String, Object?> err(int code, String message) =>
        {'jsonrpc': '2.0', 'id': id, 'error': {'code': code, 'message': message}};

    switch (method) {
      case 'initialize':
        final asked = params['protocolVersion'] as String?;
        return ok({
          'protocolVersion': _mcpVersions.contains(asked) ? asked : _mcpVersions.first,
          'capabilities': {'tools': {'listChanged': false}},
          'serverInfo': {'name': 'beat', 'version': _serverVersion},
          'instructions': 'Планировщик beat: проекты Kanban и личное расписание. '
              'Изменения могут требовать подтверждения пользователя в приложении — '
              'тогда инструмент вернёт change_id, статус проверяйте через get_change_status.',
        });
      case 'ping':
        return ok({});
      case 'tools/list':
        return ok({
          'tools': [
            for (final t in gateway.availableTools(external: true))
              {
                'name': t.name,
                'description': t.description,
                'inputSchema': t.parameters,
                'annotations': {'readOnlyHint': t.readOnly},
              },
          ],
        });
      case 'tools/call':
        final name = params['name'] as String? ?? '';
        final args = Map<String, Object?>.from((params['arguments'] as Map?) ?? const {});
        final out = await gateway.call(name, args, ChangeSource.external);
        final text = out.data is String ? out.data! as String : jsonEncode(out.data);
        return ok({
          'content': [
            {'type': 'text', 'text': text},
          ],
          'isError': out.isError,
        });
      default:
        return err(-32601, 'Method not found: $method');
    }
  }

  static void _json(HttpResponse res, int status, Object? body) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    res.close();
  }

  static void _empty(HttpResponse res, int status) {
    res.statusCode = status;
    res.close();
  }
}

/// Состояние локального API.
@immutable
class AgentServerState {
  const AgentServerState({this.port, this.error});
  final int? port;
  final String? error;
  bool get running => port != null;
}

final agentServerProvider =
    NotifierProvider<AgentServerController, AgentServerState>(AgentServerController.new);

/// Запускает/останавливает сервер по настройке «Локальный API и MCP».
class AgentServerController extends Notifier<AgentServerState> {
  AgentServer? _server;

  @override
  AgentServerState build() {
    ref.onDispose(() => _server?.stop());
    ref.listen(aiSettingsProvider.select((s) => s.apiEnabled), (_, on) => _apply(on));
    return const AgentServerState();
  }

  Future<void> init() => _apply(ref.read(aiSettingsProvider).apiEnabled);

  Future<void> _apply(bool enabled) async {
    if (!enabled) {
      await _server?.stop();
      _server = null;
      state = const AgentServerState();
      return;
    }
    if (_server != null) return;
    final server = AgentServer(
      gateway: ref.read(toolGatewayProvider),
      token: () => ref.read(aiSettingsProvider).apiToken,
      changes: () => ref.read(pendingChangesProvider),
    );
    try {
      final port = await server.start();
      _server = server;
      state = AgentServerState(port: port);
    } catch (e) {
      state = AgentServerState(error: 'Порт $agentApiPort занят или недоступен');
    }
  }
}
