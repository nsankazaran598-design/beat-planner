import 'dart:io';
import 'dart:math';

/// Где лежат журналы событий.
///
/// У каждого устройства свой файл журнала, в который пишет только оно.
/// Чужие журналы появляются при синхронизации, поэтому конфликтов
/// записи в один файл не бывает.
abstract class LogStorage {
  Future<String> loadOrCreateDeviceId();

  /// Все журналы: id устройства → строки.
  Future<Map<String, List<String>>> readLogs();

  Future<void> append(String deviceId, List<String> lines);
}

String generateId([int bytes = 8]) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
}

class FileLogStorage implements LogStorage {
  FileLogStorage(this.root);

  final Directory root;

  Directory get _logDir => Directory('${root.path}${Platform.pathSeparator}log');

  File _logFile(String deviceId) =>
      File('${_logDir.path}${Platform.pathSeparator}$deviceId.jsonl');

  @override
  Future<String> loadOrCreateDeviceId() async {
    final file = File('${root.path}${Platform.pathSeparator}device_id');
    if (await file.exists()) {
      final id = (await file.readAsString()).trim();
      if (id.isNotEmpty) return id;
    }
    await root.create(recursive: true);
    final id = generateId(6);
    await file.writeAsString(id, flush: true);
    return id;
  }

  @override
  Future<Map<String, List<String>>> readLogs() async {
    final result = <String, List<String>>{};
    if (!await _logDir.exists()) return result;
    await for (final entity in _logDir.list()) {
      if (entity is! File || !entity.path.endsWith('.jsonl')) continue;
      final name = entity.uri.pathSegments.last;
      result[name.substring(0, name.length - '.jsonl'.length)] =
          await entity.readAsLines();
    }
    return result;
  }

  @override
  Future<void> append(String deviceId, List<String> lines) async {
    await _logDir.create(recursive: true);
    await _logFile(deviceId).writeAsString(
      '${lines.join('\n')}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

/// Хранилище в памяти — для тестов.
class MemoryLogStorage implements LogStorage {
  MemoryLogStorage({this.deviceId = 'test'});

  final String deviceId;
  final Map<String, List<String>> logs = {};

  @override
  Future<String> loadOrCreateDeviceId() async => deviceId;

  @override
  Future<Map<String, List<String>>> readLogs() async =>
      {for (final e in logs.entries) e.key: [...e.value]};

  @override
  Future<void> append(String deviceId, List<String> lines) async =>
      logs.putIfAbsent(deviceId, () => []).addAll(lines);
}
