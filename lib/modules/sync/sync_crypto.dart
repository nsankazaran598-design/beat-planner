import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Ключ группы синхронизации (AES-256).
///
/// Устройства с одним ключом — одна группа: они узнают друг друга
/// и могут расшифровать данные друг друга. Ключ передаётся только
/// через QR-код / код подключения.
class GroupKey {
  GroupKey(this.bytes) : assert(bytes.length == 32);

  factory GroupKey.generate() {
    final r = Random.secure();
    return GroupKey(Uint8List.fromList(List.generate(32, (_) => r.nextInt(256))));
  }

  factory GroupKey.fromBase64(String s) => GroupKey(base64Url.decode(s));

  final Uint8List bytes;

  String toBase64() => base64Url.encode(bytes);

  static final _aes = AesGcm.with256bits();

  /// Открытый идентификатор группы для объявлений в сети (не раскрывает ключ).
  Future<String> groupId() async {
    final h = await Sha256().hash([...utf8.encode('beat-group:'), ...bytes]);
    return h.bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Шифрует JSON-объект: nonce(12) | шифротекст | MAC(16).
  Future<Uint8List> seal(Map<String, Object?> json) async {
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(json)),
      secretKey: SecretKey(bytes),
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// Расшифровывает и проверяет подлинность. Бросает [SecretBoxAuthenticationError],
  /// если сообщение подделано или зашифровано другим ключом.
  Future<Map<String, Object?>> open(List<int> data) async {
    final box = SecretBox.fromConcatenation(data, nonceLength: 12, macLength: 16);
    final plain = await _aes.decrypt(box, secretKey: SecretKey(bytes));
    return jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
  }
}
