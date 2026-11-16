import 'package:beat/core/data/data_store.dart';
import 'package:beat/core/data/log_storage.dart';
import 'dart:convert';

import 'package:beat/core/data/providers.dart';
import 'package:beat/core/secrets.dart';
import 'package:beat/core/settings/settings_controller.dart';
import 'package:beat/modules/sync/sync_controller.dart';
import 'package:beat/modules/sync/sync_crypto.dart';
import 'package:beat/modules/sync/sync_protocol.dart';
import 'package:beat/modules/sync/sync_transport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<DataStore> device(String id) => DataStore.open(MemoryLogStorage(deviceId: id));

void main() {
  group('DataStore log exchange', () {
    test('vector and linesSince', () async {
      final a = await device('a');
      await a.write('task', '1', {'title': 'x'});
      await a.write('task', '2', {'title': 'y'});
      expect(a.vector, {'a': 2});
      expect(a.linesSince({'a': 1})['a']!.from, 1);
      expect(a.linesSince({'a': 1})['a']!.lines.length, 1);
      expect(a.linesSince({'a': 2}), isEmpty);
    });

    test('mergeRemote skips overlap, rejects gaps, ignores own log', () async {
      final a = await device('a');
      for (var i = 0; i < 3; i++) {
        await a.write('task', '$i', {'title': 't$i'});
      }
      final all = a.linesSince(const {})['a']!.lines;
      final b = await device('b');

      expect(await b.mergeRemote({'a': (from: 2, lines: all.sublist(2))}), 0, reason: 'gap');
      expect(await b.mergeRemote({'a': (from: 0, lines: all.sublist(0, 2))}), 2);
      expect(await b.mergeRemote({'a': (from: 1, lines: all.sublist(1))}), 1, reason: 'overlap');
      expect(b.vector['a'], 3);
      expect(b.all('task').length, 3);
      expect(await b.mergeRemote({'b': (from: 0, lines: all)}), 0, reason: 'own log');
    });
  });

  group('crypto and pairing code', () {
    test('seal/open roundtrip; wrong key fails', () async {
      final k = GroupKey.generate();
      final sealed = await k.seal({'hello': 'мир'});
      expect(await k.open(sealed), {'hello': 'мир'});
      expect(() => GroupKey.generate().open(sealed), throwsA(anything));
      expect(await k.groupId(), await GroupKey(k.bytes).groupId());
    });

    test('pairing code roundtrip', () {
      final code = PairingCode(
        groupKey: GroupKey.generate().toBase64(),
        deviceId: 'abc',
        deviceName: 'Компьютер',
        addresses: const ['192.168.1.5', '10.0.0.2'],
        port: 47820,
      );
      final parsed = PairingCode.tryParse(code.encode())!;
      expect(parsed.deviceName, 'Компьютер');
      expect(parsed.addresses, ['192.168.1.5', '10.0.0.2']);
      expect(parsed.groupKey, code.groupKey);
      expect(PairingCode.tryParse('https://example.com'), isNull);
    });
  });

  group('transport over localhost', () {
    final key = GroupKey.generate();

    Future<SyncTransport> node(DataStore s, String name) async {
      final t = SyncTransport(
        store: s,
        key: key,
        hello: () => PeerHello(deviceId: s.deviceId, name: name, port: 0),
      );
      await t.start(port: 0, onPeer: (_, _) {});
      return t;
    }

    test('two devices converge, a third gets everything via the second', () async {
      final a = await device('a');
      final b = await device('b');
      final c = await device('c');
      final ta = await node(a, 'A');
      final tb = await node(b, 'B');
      final tc = await node(c, 'C');
      addTearDown(() async {
        await ta.stop();
        await tb.stop();
        await tc.stop();
      });

      await a.write('task', 't1', {'title': 'с ноутбука'});
      await b.write('task', 't2', {'title': 'с телефона'});
      // Одновременная правка одного поля: побеждает более поздняя.
      await a.write('task', 'shared', {'title': 'A'});
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await b.write('task', 'shared', {'title': 'B'});

      final r = await tb.syncWith('127.0.0.1', ta.port!);
      expect(r.peer.name, 'A');
      expect(r.received, 2);
      expect(r.sent, 2);

      for (final s in [a, b]) {
        expect(s.get('task', 't1')?.get<String>('title'), 'с ноутбука');
        expect(s.get('task', 't2')?.get<String>('title'), 'с телефона');
        expect(s.get('task', 'shared')?.get<String>('title'), 'B');
      }

      await tc.syncWith('127.0.0.1', tb.port!);
      expect(c.all('task').length, 3);
      expect(c.vector, {'a': 2, 'b': 2});

      // Повторный обмен ничего не передаёт.
      final again = await tb.syncWith('127.0.0.1', ta.port!);
      expect(again.received + again.sent, 0);
    });

    test('a device with another key is rejected', () async {
      final a = await device('a');
      final ta = await node(a, 'A');
      addTearDown(ta.stop);
      final stranger = SyncTransport(
        store: await device('x'),
        key: GroupKey.generate(),
        hello: () => const PeerHello(deviceId: 'x', name: 'X', port: 0),
      );
      await a.write('task', 'secret', {'title': 'secret'});
      await expectLater(stranger.syncWith('127.0.0.1', ta.port!), throwsA(anything));
    });
  });

  test('group key moves from settings to secure storage', () async {
    final key = GroupKey.generate().toBase64();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'sync.config': jsonEncode({'key': key, 'name': 'ПК', 'peers': {}}),
    });
    final prefs = await SharedPreferences.getInstance();
    final secrets = MemorySecretStore();
    final c = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dataStoreProvider.overrideWithValue(await device('a')),
      secretStoreProvider.overrideWithValue(secrets),
    ]);
    addTearDown(c.dispose);

    expect(c.read(syncControllerProvider).groupKey, key);
    await c.read(syncControllerProvider.notifier).rename('Компьютер');
    expect(await secrets.read('sync.groupKey'), key);
    final saved = jsonDecode(prefs.getString('sync.config')!) as Map;
    expect(saved.containsKey('key'), isFalse);
    expect(saved['inGroup'], isTrue);
  });
}
