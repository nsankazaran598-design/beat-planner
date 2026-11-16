import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data_store.dart';

/// Переопределяется в `main()` открытым хранилищем.
final dataStoreProvider = Provider<DataStore>(
  (ref) => throw UnimplementedError('dataStoreProvider not overridden'),
);

/// Снимок хранилища. При каждом изменении данных создаётся новый
/// объект, поэтому зависимые провайдеры пересчитываются.
class DataSnapshot {
  DataSnapshot(this.store);
  final DataStore store;
}

/// Модули строят свои провайдеры поверх него.
final dataSnapshotProvider = Provider<DataSnapshot>((ref) {
  final store = ref.watch(dataStoreProvider);
  void onChange() => ref.invalidateSelf();
  store.addListener(onChange);
  ref.onDispose(() => store.removeListener(onChange));
  return DataSnapshot(store);
});

/// Папка с данными приложения (null — в тестах).
final dataDirProvider = Provider<String?>((ref) => null);
