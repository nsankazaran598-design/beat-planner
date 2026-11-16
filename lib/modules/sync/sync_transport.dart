import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../core/data/data_store.dart';
import 'sync_crypto.dart';
import 'sync_protocol.dart';

/// Результат обмена с одним устройством.
class SyncResult {
  const SyncResult({required this.peer, required this.received, required this.sent});

  final PeerHello peer;
  final int received;
  final int sent;
}

typedef PeerSeen = void Function(PeerHello peer, String address);

/// Обмен журналами по HTTP внутри локальной сети.
///
/// Каждое тело запроса и ответа зашифровано AES-GCM ключом группы,
/// поэтому без ключа нельзя ни прочитать данные, ни подсунуть свои.
///
/// Протокол (клиент → сервер):
/// 1. `POST /v1/hello {peer, vector}` → `{peer, vector, slices}` —
///    клиент получает строки, которых у него нет;
/// 2. `POST /v1/push {peer, slices}` → `{added}` — отдаёт строки,
///    которых нет у сервера.
class SyncTransport {
  SyncTransport({required this.store, required this.key, required this.hello});

  final DataStore store;
  final GroupKey key;

  /// Сведения об этом устройстве (имя может меняться).
  final PeerHello Function() hello;

  HttpServer? _server;

  int? get port => _server?.port;

  /// Запускает сервер. Если порт занят — берёт любой свободный.
  Future<int> start({int port = syncPort, required PeerSeen onPeer}) async {
    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: false);
    } on SocketException {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _server = server;
    server.listen((req) => _handle(req, onPeer));
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req, PeerSeen onPeer) async {
    final res = req.response;
    try {
      if (req.method != 'POST') {
        res.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final body = await _readBody(req);
      final msg = await key.open(body);
      final peer = PeerHello.fromJson(msg['peer']);
      if (peer.deviceId == store.deviceId) {
        res.statusCode = HttpStatus.conflict;
        return;
      }
      onPeer(peer, req.connectionInfo?.remoteAddress.address ?? '');

      Map<String, Object?> reply;
      switch (req.uri.path) {
        case '/v1/hello':
          final remote = decodeVector(msg['vector']);
          reply = {
            'peer': hello().toJson(),
            'vector': store.vector,
            'slices': encodeSlices(store.linesSince(remote)),
          };
        case '/v1/push':
          final added = await store.mergeRemote(decodeSlices(msg['slices']));
          reply = {'added': added};
        default:
          res.statusCode = HttpStatus.notFound;
          return;
      }
      res.headers.contentType = ContentType.binary;
      res.add(await key.seal(reply));
    } catch (e) {
      // Чужой ключ, мусор или обрыв — не раскрываем подробностей.
      debugPrint('sync server: $e');
      res.statusCode = HttpStatus.forbidden;
    } finally {
      await res.close();
    }
  }

  /// Полный обмен с устройством по адресу [host]:[port].
  Future<SyncResult> syncWith(String host, int port,
      {Duration timeout = const Duration(seconds: 20)}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final helloReply = await _post(client, host, port, '/v1/hello', {
        'peer': hello().toJson(),
        'vector': store.vector,
      }).timeout(timeout);
      final peer = PeerHello.fromJson(helloReply['peer']);
      final received = await store.mergeRemote(decodeSlices(helloReply['slices']));

      final remoteVector = decodeVector(helloReply['vector']);
      final outgoing = store.linesSince(remoteVector);
      var sent = 0;
      if (outgoing.isNotEmpty) {
        await _post(client, host, port, '/v1/push', {
          'peer': hello().toJson(),
          'slices': encodeSlices(outgoing),
        }).timeout(timeout);
        sent = outgoing.values.fold(0, (n, s) => n + s.lines.length);
      }
      return SyncResult(peer: peer, received: received, sent: sent);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, Object?>> _post(
    HttpClient client,
    String host,
    int port,
    String path,
    Map<String, Object?> body,
  ) async {
    final req = await client.post(host, port, path);
    req.headers.contentType = ContentType.binary;
    req.add(await key.seal(body));
    final res = await req.close();
    final bytes = await _readBody(res);
    if (res.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${res.statusCode}', uri: Uri(host: host, port: port, path: path));
    }
    return key.open(bytes);
  }

  static Future<Uint8List> _readBody(Stream<List<int>> s) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in s) {
      b.add(chunk);
      if (b.length > 64 * 1024 * 1024) throw const HttpException('body too large');
    }
    return b.takeBytes();
  }
}
