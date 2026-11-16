import 'package:flutter/foundation.dart';

import 'hlc.dart';
import 'log_storage.dart';
import 'op.dart';

/// Текущее состояние одной сущности, собранное из журнала.
class Record {
  Record(this.entity, this.id);

  final String entity;
  final String id;
  final Map<String, Object?> fields = {};

  /// HLC последнего изменения каждого поля.
  final Map<String, String> clocks = {};

  bool get deleted => fields[Op.deletedField] == true;

  T? get<T>(String field) => fields[field] as T?;
}

/// Запись для пакетного изменения.
typedef Change = ({String entity, String id, Map<String, Object?> fields});

/// Хранилище данных приложения.
///
/// Источник истины — журналы событий всех устройств. Состояние в памяти
/// получается слиянием журналов: для каждого поля побеждает изменение
/// с наибольшим HLC (last-writer-wins). Слияние коммутативно, поэтому
/// порядок, в котором приходят журналы, не важен.
class DataStore extends ChangeNotifier {
  DataStore._(this.deviceId, this._storage) : _clock = HlcClock(deviceId);

  final String deviceId;
  final LogStorage _storage;
  final HlcClock _clock;
  final Map<String, Map<String, Record>> _data = {};
  Future<void> _writes = Future.value();

  static Future<DataStore> open(LogStorage storage) async {
    final deviceId = await storage.loadOrCreateDeviceId();
    final store = DataStore._(deviceId, storage);
    final logs = await storage.readLogs();
    for (final lines in logs.values) {
      for (final line in lines) {
        final op = Op.tryDecode(line);
        if (op != null) store._apply(op);
      }
    }
    return store;
  }

  String newId() => generateId();

  /// Живые (не удалённые) записи сущности.
  Iterable<Record> all(String entity) =>
      (_data[entity]?.values ?? const <Record>[]).where((r) => !r.deleted);

  Record? get(String entity, String id) {
    final r = _data[entity]?[id];
    return r == null || r.deleted ? null : r;
  }

  Future<void> write(String entity, String id, Map<String, Object?> fields) =>
      writeAll([(entity: entity, id: id, fields: fields)]);

  Future<void> delete(String entity, String id) =>
      write(entity, id, {Op.deletedField: true});

  /// Применяет изменения сразу и дописывает их в журнал этого устройства.
  Future<void> writeAll(List<Change> changes) {
    if (changes.isEmpty) return _writes;
    final lines = <String>[];
    for (final c in changes) {
      final op = Op(
        hlc: _clock.tick().toString(),
        entity: c.entity,
        id: c.id,
        fields: c.fields,
      );
      _apply(op);
      lines.add(op.encode());
    }
    notifyListeners();
    return _writes = _writes.then((_) => _storage.append(deviceId, lines));
  }

  /// Принимает изменения с другого устройства (для синхронизации).
  void applyRemote(Iterable<Op> ops) {
    var changed = false;
    for (final op in ops) {
      changed |= _apply(op);
    }
    if (changed) notifyListeners();
  }

  /// Дождаться записи всех изменений на диск.
  Future<void> flush() => _writes;

  bool _apply(Op op) {
    _clock.observe(Hlc.parse(op.hlc));
    final record = _data
        .putIfAbsent(op.entity, () => {})
        .putIfAbsent(op.id, () => Record(op.entity, op.id));
    var changed = false;
    op.fields.forEach((field, value) {
      final current = record.clocks[field];
      if (current == null || op.hlc.compareTo(current) > 0) {
        record.fields[field] = value;
        record.clocks[field] = op.hlc;
        changed = true;
      }
    });
    return changed;
  }
}
