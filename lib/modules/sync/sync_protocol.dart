import 'dart:convert';

import '../../core/data/data_store.dart';

/// Порт сервера синхронизации (TCP) и порт объявлений (UDP).
const syncPort = 47820;
const discoveryPort = 47821;

/// Код подключения: то же, что в QR-коде.
/// `beat1:<base64url(JSON)>` с ключом группы и адресами пригласившего.
class PairingCode {
  const PairingCode({
    required this.groupKey,
    required this.deviceId,
    required this.deviceName,
    required this.addresses,
    required this.port,
  });

  static const prefix = 'beat1:';

  final String groupKey;
  final String deviceId;
  final String deviceName;
  final List<String> addresses;
  final int port;

  String encode() => prefix +
      base64Url.encode(utf8.encode(jsonEncode({
        'g': groupKey,
        'd': deviceId,
        'n': deviceName,
        'a': addresses,
        'p': port,
      })));

  static PairingCode? tryParse(String raw) {
    final s = raw.trim();
    if (!s.startsWith(prefix)) return null;
    try {
      final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(s.substring(prefix.length)))))
          as Map<String, Object?>;
      return PairingCode(
        groupKey: j['g']! as String,
        deviceId: j['d']! as String,
        deviceName: (j['n'] as String?) ?? 'Устройство',
        addresses: [for (final a in (j['a'] as List? ?? const [])) a as String],
        port: (j['p'] as num?)?.toInt() ?? syncPort,
      );
    } catch (_) {
      return null;
    }
  }
}

Map<String, Object?> encodeSlices(Map<String, LogSlice> slices) => {
      for (final e in slices.entries) e.key: {'from': e.value.from, 'lines': e.value.lines},
    };

Map<String, LogSlice> decodeSlices(Object? json) {
  if (json is! Map) return const {};
  return {
    for (final e in json.entries)
      e.key as String: (
        from: ((e.value as Map)['from'] as num).toInt(),
        lines: [for (final l in (e.value as Map)['lines'] as List) l as String],
      ),
  };
}

Map<String, int> decodeVector(Object? json) => json is Map
    ? {for (final e in json.entries) e.key as String: (e.value as num).toInt()}
    : const {};

/// Сведения об устройстве, которые передаются при каждом обмене.
class PeerHello {
  const PeerHello({required this.deviceId, required this.name, required this.port});

  final String deviceId;
  final String name;
  final int port;

  Map<String, Object?> toJson() => {'id': deviceId, 'name': name, 'port': port};

  static PeerHello fromJson(Object? j) {
    final m = j! as Map;
    return PeerHello(
      deviceId: m['id']! as String,
      name: (m['name'] as String?) ?? 'Устройство',
      port: (m['port'] as num?)?.toInt() ?? syncPort,
    );
  }
}
