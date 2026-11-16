import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/data/log_storage.dart' show generateId;
import '../../core/settings/settings_controller.dart';

enum AiProvider {
  anthropic('Anthropic (Claude)', 'https://api.anthropic.com', 'claude-opus-5-5'),
  openai('OpenAI-совместимый (LM Studio, Ollama, OpenRouter…)',
      'http://localhost:1234/v1', '');

  const AiProvider(this.label, this.defaultUrl, this.defaultModel);
  final String label;
  final String defaultUrl;
  final String defaultModel;
}

/// Настройки ИИ на этом устройстве (не синхронизируются).
@immutable
class AiSettings {
  const AiSettings({
    this.provider = AiProvider.anthropic,
    this.baseUrl = 'https://api.anthropic.com',
    this.model = 'claude-opus-5-5',
    this.readTasks = true,
    this.allowChanges = true,
    this.confirmChanges = true,
    this.personalAccess = false,
    this.apiEnabled = false,
    this.apiToken = '',
  });

  final AiProvider provider;
  final String baseUrl;
  final String model;

  // Разрешения (макет «Совместная работа»).
  final bool readTasks;
  final bool allowChanges;
  final bool confirmChanges;
  final bool personalAccess;

  /// Локальный REST API и MCP-сервер для внешних агентов.
  final bool apiEnabled;
  final String apiToken;

  AiSettings copyWith({
    AiProvider? provider,
    String? baseUrl,
    String? model,
    bool? readTasks,
    bool? allowChanges,
    bool? confirmChanges,
    bool? personalAccess,
    bool? apiEnabled,
    String? apiToken,
  }) =>
      AiSettings(
        provider: provider ?? this.provider,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        readTasks: readTasks ?? this.readTasks,
        allowChanges: allowChanges ?? this.allowChanges,
        confirmChanges: confirmChanges ?? this.confirmChanges,
        personalAccess: personalAccess ?? this.personalAccess,
        apiEnabled: apiEnabled ?? this.apiEnabled,
        apiToken: apiToken ?? this.apiToken,
      );

  Map<String, Object?> toJson() => {
        'provider': provider.name,
        'baseUrl': baseUrl,
        'model': model,
        'readTasks': readTasks,
        'allowChanges': allowChanges,
        'confirmChanges': confirmChanges,
        'personalAccess': personalAccess,
        'apiEnabled': apiEnabled,
        'apiToken': apiToken,
      };

  static AiSettings fromJson(Map<String, Object?> j) {
    const d = AiSettings();
    return AiSettings(
      provider: AiProvider.values.firstWhere((p) => p.name == j['provider'],
          orElse: () => d.provider),
      baseUrl: (j['baseUrl'] as String?) ?? d.baseUrl,
      model: (j['model'] as String?) ?? d.model,
      readTasks: (j['readTasks'] as bool?) ?? d.readTasks,
      allowChanges: (j['allowChanges'] as bool?) ?? d.allowChanges,
      confirmChanges: (j['confirmChanges'] as bool?) ?? d.confirmChanges,
      personalAccess: (j['personalAccess'] as bool?) ?? d.personalAccess,
      apiEnabled: (j['apiEnabled'] as bool?) ?? d.apiEnabled,
      apiToken: (j['apiToken'] as String?) ?? d.apiToken,
    );
  }
}

final aiSettingsProvider =
    NotifierProvider<AiSettingsController, AiSettings>(AiSettingsController.new);

class AiSettingsController extends Notifier<AiSettings> {
  static const _key = 'ai.settings';

  @override
  AiSettings build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(_key);
    var s = const AiSettings();
    if (raw != null) {
      try {
        s = AiSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
      } catch (_) {}
    }
    if (s.apiToken.isEmpty) s = s.copyWith(apiToken: generateId(24));
    return s;
  }

  Future<void> update(AiSettings s) async {
    state = s;
    await ref.read(sharedPreferencesProvider).setString(_key, jsonEncode(s.toJson()));
  }

  Future<void> regenerateToken() => update(state.copyWith(apiToken: generateId(24)));
}

/// Хранилище API-ключа провайдера: системное (Credential Manager /
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

const apiKeySecret = 'ai.apiKey';

/// Ключ API провайдера (загружается асинхронно).
final aiApiKeyProvider = FutureProvider<String?>(
  (ref) => ref.watch(secretStoreProvider).read(apiKeySecret),
);
