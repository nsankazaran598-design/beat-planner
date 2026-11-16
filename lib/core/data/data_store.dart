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

/// Кусок журнала одного устройства, начиная со строки [from].
typedef LogSlice = ({int from, List<String> lines});

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

  /// Сырые строки журналов всех устройств (для синхронизации).
  final Map<String, List<String>> _lines = {};
  Future<void> _writes = Future.value();

  static Future<DataStore> open(LogStorage storage) async {
    final deviceId = await storage.loadOrCreateDeviceId();
    final store = DataStore._(deviceId, storage);
    final logs = await storage.readLogs();
    for (final e in logs.entries) {
      store._lines[e.key] = [...e.value];
      for (final line in e.value) {
        final op = Op.tryDecode(line);
        if (op != null) store._apply(op);
      }
    }
    return store;
  }

  // ---------- Синхронизация ----------

  /// Сколько строк журнала каждого устройства есть здесь.
  Map<String, int> get vector => {for (final e in _lines.entries) e.key: e.value.length};

  /// Строки, которых нет у собеседника с вектором [remote]:
  /// id устройства → (с какой строки, строки).
  Map<String, LogSlice> linesSince(Map<String, int> remote) => {
        for (final e in _lines.entries)
          if (e.value.length > (remote[e.key] ?? 0))
            e.key: (
              from: remote[e.key] ?? 0,
              lines: e.value.sublist(remote[e.key] ?? 0),
            ),
      };

  /// Принимает строки чужих журналов. Перекрывающиеся строки пропускаются,
  /// а кусок с «дырой» (начинается дальше, чем у нас есть) отбрасывается —
  /// он придёт целиком в следующий раз. Возвращает число новых строк.
  Future<int> mergeRemote(Map<String, LogSlice> slices) async {
    var added = 0;
    var changed = false;
    for (final e in slices.entries) {
      // Свой журнал пишет только это устройство.
      if (e.key == deviceId) continue;
      final have = _lines[e.key]?.length ?? 0;
      final slice = e.value;
      if (slice.from > have) continue;
      final skip = have - slice.from;
      if (skip >= slice.lines.length) continue;
      final fresh = slice.lines.sublist(skip);
      _lines.putIfAbsent(e.key, () => []).addAll(fresh);
      final device = e.key;
      _writes = _writes.then((_) => _storage.append(device, fresh));
      for (final line in fresh) {
        final op = Op.tryDecode(line);
        if (op != null) changed |= _apply(op);
      }
      added += fresh.length;
    }
    if (changed) notifyListeners();
    await _writes;
    return added;
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
    _lines.putIfAbsent(deviceId, () => []).addAll(lines);
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
