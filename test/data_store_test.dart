import 'package:beat/core/data/data_store.dart';
import 'package:beat/core/data/hlc.dart';
import 'package:beat/core/data/log_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HLC strings order like the clocks', () {
    final clock = HlcClock('a', now: () => 1000);
    final h1 = clock.tick();
    final h2 = clock.tick();
    expect(h1.compareTo(h2), lessThan(0));
    expect(Hlc.parse(h2.toString()), h2);
  });

  test('state survives reopening from the log', () async {
    final storage = MemoryLogStorage(deviceId: 'a');
    final s1 = await DataStore.open(storage);
    await s1.write('task', 't1', {'title': 'Купить молоко'});
    await s1.write('task', 't1', {'title': 'Купить кефир'});
    await s1.write('task', 't2', {'title': 'Удалить меня'});
    await s1.delete('task', 't2');
    await s1.flush();

    final s2 = await DataStore.open(storage);
    expect(s2.get('task', 't1')?.get<String>('title'), 'Купить кефир');
    expect(s2.get('task', 't2'), isNull);
    expect(s2.all('task').length, 1);
  });

  test('two devices merge field by field, last writer wins', () async {
    final a = MemoryLogStorage(deviceId: 'a');
    final b = MemoryLogStorage(deviceId: 'b');
    final storeA = await DataStore.open(a);
    await storeA.write('task', 't', {'title': 'Исходное', 'category': 'Х'});
    await storeA.flush();

    // B получает журнал A.
    b.logs['a'] = [...a.logs['a']!];
    final storeB = await DataStore.open(b);

    // Одновременные правки разных полей на разных устройствах.
    await storeA.write('task', 't', {'title': 'Новое название'});
    await storeB.write('task', 't', {'category': 'Дизайн'});
    await storeA.flush();
    await storeB.flush();

    // Обмен журналами в обе стороны.
    a.logs['b'] = [...b.logs['b']!];
    b.logs['a'] = [...a.logs['a']!];
    final mergedA = await DataStore.open(a);
    final mergedB = await DataStore.open(b);

    for (final s in [mergedA, mergedB]) {
      final r = s.get('task', 't')!;
      expect(r.get<String>('title'), 'Новое название');
      expect(r.get<String>('category'), 'Дизайн');
    }
  });

  test('corrupted log lines are skipped', () async {
    final storage = MemoryLogStorage(deviceId: 'a');
    final s1 = await DataStore.open(storage);
    await s1.write('task', 't1', {'title': 'ok'});
    await s1.flush();
    storage.logs['a']!.add('{"h":"0001-');
    final s2 = await DataStore.open(storage);
    expect(s2.get('task', 't1')?.get<String>('title'), 'ok');
  });
}
