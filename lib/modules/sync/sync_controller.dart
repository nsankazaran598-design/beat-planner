import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/providers.dart';
import '../../core/secrets.dart';
import '../../core/settings/settings_controller.dart';
import 'discovery.dart';
import 'sync_crypto.dart';
import 'sync_protocol.dart';
import 'sync_transport.dart';

/// Известное устройство группы.
@immutable
class SyncPeer {
  const SyncPeer({
    required this.id,
    required this.name,
    this.address,
    this.port = syncPort,
    this.lastSync,
    this.lastSeen,
    this.error,
    this.syncing = false,
  });

  final String id;
  final String name;
  final String? address;
  final int port;
  final DateTime? lastSync;
  final DateTime? lastSeen;
  final String? error;
  final bool syncing;

  SyncPeer copyWith({
    String? name,
    String? address,
    int? port,
    DateTime? lastSync,
    DateTime? lastSeen,
    String? error,
    bool clearError = false,
    bool? syncing,
  }) =>
      SyncPeer(
        id: id,
        name: name ?? this.name,
        address: address ?? this.address,
        port: port ?? this.port,
        lastSync: lastSync ?? this.lastSync,
        lastSeen: lastSeen ?? this.lastSeen,
        error: clearError ? null : (error ?? this.error),
        syncing: syncing ?? this.syncing,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'address': address,
        'port': port,
        'lastSync': lastSync?.millisecondsSinceEpoch,
      };

  static SyncPeer fromJson(String id, Map<String, Object?> j) => SyncPeer(
        id: id,
        name: (j['name'] as String?) ?? 'Устройство',
        address: j['address'] as String?,
        port: (j['port'] as num?)?.toInt() ?? syncPort,
        lastSync: j['lastSync'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['lastSync'] as num).toInt()),
      );
}

@immutable
class SyncState {
  const SyncState({
    this.groupKey,
    required this.deviceName,
    this.peers = const [],
    this.running = false,
    this.port,
    this.addresses = const [],
  });

  final String? groupKey;
  final String deviceName;
  final List<SyncPeer> peers;
  final bool running;
  final int? port;
  final List<String> addresses;

  bool get inGroup => groupKey != null;

  SyncState copyWith({
    String? groupKey,
    bool clearGroup = false,
    String? deviceName,
    List<SyncPeer>? peers,
    bool? running,
    int? port,
    List<String>? addresses,
  }) =>
      SyncState(
        groupKey: clearGroup ? null : (groupKey ?? this.groupKey),
        deviceName: deviceName ?? this.deviceName,
        peers: peers ?? this.peers,
        running: running ?? this.running,
        port: port ?? this.port,
        addresses: addresses ?? this.addresses,
      );
}

String defaultDeviceName() {
  if (kIsWeb) return 'Браузер';
  try {
    if (Platform.isAndroid) return 'Телефон';
    if (Platform.isWindows) return 'Компьютер · ${Platform.localHostname}';
  } catch (_) {}
  return 'Устройство';
}

final syncControllerProvider =
    NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Управляет группой синхронизации и обменом с устройствами.
class SyncController extends Notifier<SyncState> {
  static const _kConfig = 'sync.config';
  static const _kKeySecret = 'sync.groupKey';

  /// Есть ли группа (сам ключ — в защищённом хранилище).
  bool _hasGroup = false;
  bool _keyLoaded = false;

  SyncTransport? _transport;
  LanDiscovery? _discovery;
  StreamSubscription<Beacon>? _beacons;
  Timer? _periodic;
  Timer? _debounce;
  VoidCallback? _storeListener;
  bool _applyingRemote = false;

  @override
  SyncState build() {
    ref.onDispose(() => _stopRuntime(updateState: false));
    final raw = ref.read(sharedPreferencesProvider).getString(_kConfig);
    if (raw == null) return SyncState(deviceName: defaultDeviceName());
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      final peers = (j['peers'] as Map?) ?? const {};
      _hasGroup = j['inGroup'] == true || j['key'] != null;
      return SyncState(
        // Старые версии хранили ключ прямо в настройках — он переедет при сохранении.
        groupKey: j['key'] as String?,
        deviceName: (j['name'] as String?) ?? defaultDeviceName(),
        peers: [
          for (final e in peers.entries)
            SyncPeer.fromJson(e.key as String, Map<String, Object?>.from(e.value as Map)),
        ],
      );
    } catch (_) {
      return SyncState(deviceName: defaultDeviceName());
    }
  }

  Future<void> _save() async {
    await ref.read(secretStoreProvider).write(_kKeySecret, state.groupKey);
    _hasGroup = state.inGroup;
    await ref.read(sharedPreferencesProvider).setString(
          _kConfig,
          jsonEncode({
            'inGroup': state.inGroup,
            'name': state.deviceName,
            'peers': {for (final p in state.peers) p.id: p.toJson()},
          }),
        );
  }

  /// Загружает ключ группы из защищённого хранилища (один раз).
  Future<void> _loadKey() async {
    if (_keyLoaded) return;
    _keyLoaded = true;
    if (state.groupKey != null) {
      await _save(); // перенос ключа из старых настроек
      return;
    }
    if (!_hasGroup) return;
    final key = await ref.read(secretStoreProvider).read(_kKeySecret);
    if (key != null) state = state.copyWith(groupKey: key);
  }

  PeerHello _hello() => PeerHello(
        deviceId: ref.read(dataStoreProvider).deviceId,
        name: state.deviceName,
        port: state.port ?? syncPort,
      );

  // ---------- Группа ----------

  /// Создаёт группу (если её нет) и возвращает код подключения.
  Future<PairingCode> pairingCode() async {
    await _loadKey();
    if (!state.inGroup) {
      state = state.copyWith(groupKey: GroupKey.generate().toBase64());
      await _save();
      await start();
    }
    final addresses = await localAddresses();
    state = state.copyWith(addresses: addresses);
    return PairingCode(
      groupKey: state.groupKey!,
      deviceId: ref.read(dataStoreProvider).deviceId,
      deviceName: state.deviceName,
      addresses: addresses,
      port: state.port ?? syncPort,
    );
  }

  /// Подключается к группе по коду и сразу синхронизируется с пригласившим.
  Future<String?> join(PairingCode code) async {
    final myId = ref.read(dataStoreProvider).deviceId;
    if (code.deviceId == myId) return 'Это код этого же устройства';
    _stopRuntime();
    state = state.copyWith(groupKey: code.groupKey);
    _upsertPeer(SyncPeer(
      id: code.deviceId,
      name: code.deviceName,
      address: code.addresses.firstOrNull,
      port: code.port,
    ));
    await _save();
    await start();
    // Пробуем все адреса из кода, пока один не ответит.
    for (final a in code.addresses) {
      final ok = await _syncPeer(code.deviceId, address: a, port: code.port);
      if (ok) return null;
    }
    return code.addresses.isEmpty
        ? null
        : 'Не удалось связаться с «${code.deviceName}». Проверьте, что устройства '
            'в одной сети — синхронизация повторится автоматически.';
  }

  Future<void> leaveGroup() async {
    _stopRuntime();
    state = SyncState(deviceName: state.deviceName);
    await _save();
  }

  Future<void> rename(String name) async {
    state = state.copyWith(deviceName: name);
    await _save();
  }

  Future<void> forgetPeer(String id) async {
    state = state.copyWith(peers: [for (final p in state.peers) if (p.id != id) p]);
    await _save();
  }

  // ---------- Работа ----------

  /// Запускает сервер, поиск и периодический обмен (если есть группа).
  Future<void> start() async {
    await _loadKey();
    if (!state.inGroup || state.running) return;
    final store = ref.read(dataStoreProvider);
    final key = GroupKey.fromBase64(state.groupKey!);
    final transport = SyncTransport(store: store, key: key, hello: _hello);
    try {
      final port = await transport.start(onPeer: _onPeerContact);
      _transport = transport;
      state = state.copyWith(running: true, port: port, addresses: await localAddresses());
    } catch (e) {
      debugPrint('sync server failed: $e');
      return;
    }

    final discovery = LanDiscovery(
      groupId: await key.groupId(),
      deviceId: store.deviceId,
      port: () => state.port ?? syncPort,
    );
    _discovery = discovery;
    _beacons = discovery.found.listen(_onBeacon);
    await discovery.start();

    // Изменения данных → обмен через пару секунд (пачкой).
    void onChange() {
      if (_applyingRemote) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), syncAll);
    }

    store.addListener(onChange);
    _storeListener = () => store.removeListener(onChange);
    _periodic = Timer.periodic(const Duration(minutes: 1), (_) => syncAll());
    unawaited(syncAll());
  }

  void _stopRuntime({bool updateState = true}) {
    _debounce?.cancel();
    _periodic?.cancel();
    _beacons?.cancel();
    _discovery?.stop();
    _storeListener?.call();
    _storeListener = null;
    _transport?.stop();
    _transport = null;
    _discovery = null;
    if (updateState && state.running) state = state.copyWith(running: false);
  }

  /// Обмен со всеми известными устройствами.
  Future<void> syncAll() async {
    await Future.wait([for (final p in state.peers) _syncPeer(p.id)]);
  }

  void _onBeacon(Beacon b) {
    final known = state.peers.where((p) => p.id == b.deviceId).firstOrNull;
    _upsertPeer((known ?? SyncPeer(id: b.deviceId, name: 'Устройство'))
        .copyWith(address: b.address, port: b.port, lastSeen: DateTime.now()));
    // Новое или давно не синхронизированное устройство — обмениваемся сразу.
    final last = known?.lastSync;
    if (last == null || DateTime.now().difference(last) > const Duration(seconds: 30)) {
      unawaited(_syncPeer(b.deviceId));
    }
  }

  /// Кто-то сам пришёл к нам: запоминаем его адрес и имя.
  void _onPeerContact(PeerHello peer, String address) {
    final known = state.peers.where((p) => p.id == peer.deviceId).firstOrNull;
    _upsertPeer((known ?? SyncPeer(id: peer.deviceId, name: peer.name)).copyWith(
      name: peer.name,
      address: address.isEmpty ? null : address,
      port: peer.port,
      lastSeen: DateTime.now(),
      lastSync: DateTime.now(),
      clearError: true,
    ));
    unawaited(_save());
  }

  Future<bool> _syncPeer(String id, {String? address, int? port}) async {
    final t = _transport;
    final peer = state.peers.where((p) => p.id == id).firstOrNull;
    final host = address ?? peer?.address;
    if (t == null || peer == null || host == null || peer.syncing) return false;
    _upsertPeer(peer.copyWith(syncing: true));
    try {
      _applyingRemote = true;
      final r = await t.syncWith(host, port ?? peer.port);
      _upsertPeer(_peer(id)!.copyWith(
        name: r.peer.name,
        address: host,
        port: r.peer.port,
        lastSync: DateTime.now(),
        lastSeen: DateTime.now(),
        syncing: false,
        clearError: true,
      ));
      await _save();
      return true;
    } catch (e) {
      _upsertPeer(_peer(id)!.copyWith(syncing: false, error: _describe(e)));
      return false;
    } finally {
      _applyingRemote = false;
    }
  }

  SyncPeer? _peer(String id) => state.peers.where((p) => p.id == id).firstOrNull;

  void _upsertPeer(SyncPeer p) {
    final list = [...state.peers];
    final i = list.indexWhere((x) => x.id == p.id);
    i < 0 ? list.add(p) : list[i] = p;
    state = state.copyWith(peers: list);
  }

  static String _describe(Object e) {
    if (e is SocketException || e is TimeoutException) return 'Не в сети';
    if (e is HttpException && e.message.contains('403')) return 'Другая группа';
    return 'Ошибка обмена';
  }
}
