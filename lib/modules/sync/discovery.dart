import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'sync_protocol.dart';

/// Объявление устройства в сети.
class Beacon {
  const Beacon({
    required this.groupId,
    required this.deviceId,
    required this.port,
    required this.address,
  });

  final String groupId;
  final String deviceId;
  final int port;
  final String address;
}

/// Поиск устройств своей группы в локальной сети через UDP-broadcast.
///
/// Объявление содержит только открытый id группы (хэш ключа), id
/// устройства и порт — без данных и без ключа.
class LanDiscovery {
  LanDiscovery({required this.groupId, required this.deviceId, required this.port});

  final String groupId;
  final String deviceId;
  final int Function() port;

  RawDatagramSocket? _socket;
  Timer? _timer;
  final _found = StreamController<Beacon>.broadcast();

  Stream<Beacon> get found => _found.stream;

  Future<void> start({Duration every = const Duration(seconds: 10)}) async {
    try {
      final s = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
      );
      s.broadcastEnabled = true;
      s.listen((event) {
        if (event != RawSocketEvent.read) return;
        final d = s.receive();
        if (d == null) return;
        try {
          final m = jsonDecode(utf8.decode(d.data)) as Map<String, Object?>;
          if (m['beat'] != 1 || m['g'] != groupId || m['d'] == deviceId) return;
          _found.add(Beacon(
            groupId: groupId,
            deviceId: m['d']! as String,
            port: (m['p'] as num).toInt(),
            address: d.address.address,
          ));
        } catch (_) {}
      });
      _socket = s;
      announce();
      _timer = Timer.periodic(every, (_) => announce());
    } catch (e) {
      debugPrint('discovery: $e');
    }
  }

  /// Разослать объявление о себе (сразу, не дожидаясь таймера).
  void announce() {
    final s = _socket;
    if (s == null) return;
    final data = utf8.encode(jsonEncode({'beat': 1, 'g': groupId, 'd': deviceId, 'p': port()}));
    try {
      s.send(data, InternetAddress('255.255.255.255'), discoveryPort);
    } catch (e) {
      debugPrint('discovery send: $e');
    }
  }

  void stop() {
    _timer?.cancel();
    _socket?.close();
    _socket = null;
  }
}

/// IPv4-адреса этого устройства в локальной сети.
Future<List<String>> localAddresses() async {
  try {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in list)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a.address,
    ];
  } catch (_) {
    return const [];
  }
}
