import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Хранилище секретов (ключи API, ключ группы синхронизации): системное (Credential Manager /
/// Android Keystore), в тестах — память.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class MemorySecretStore implements SecretStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String? value) async =>
      value == null ? _m.remove(key) : _m[key] = value;
}

class SystemSecretStore implements SecretStore {
  final _s = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) async {
    try {
      return await _s.read(key: key);
    } catch (e) {
      debugPrint('secure storage: $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, String? value) =>
      value == null || value.isEmpty ? _s.delete(key: key) : _s.write(key: key, value: value);
}

final secretStoreProvider = Provider<SecretStore>((ref) {
  final test = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
  return test ? MemorySecretStore() : SystemSecretStore();
});

