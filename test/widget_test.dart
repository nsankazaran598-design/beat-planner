import 'package:beat/core/data/data_store.dart';
import 'package:beat/core/data/log_storage.dart';
import 'package:beat/core/data/providers.dart';
import 'package:beat/core/module/module_registry.dart';
import 'package:beat/core/settings/settings_controller.dart';
import 'package:beat/main.dart';
import 'package:beat/modules/kanban/kanban_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = await DataStore.open(MemoryLogStorage());
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dataStoreProvider.overrideWithValue(store),
    ],
  );
}

Future<ProviderContainer> _pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = await _container();
  await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const BeatApp()));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('desktop layout shows sidebar with all modules', (tester) async {
    await _pumpApp(tester, const Size(1440, 1000));
    expect(find.text('beat'), findsOneWidget);
    expect(find.text('Новая задача'), findsOneWidget);
    expect(find.text('МОИ ПРОЕКТЫ'), findsOneWidget);
    for (final label in ['Проекты', 'Мой день', 'Напоминания', 'ИИ и подключения', 'Синхронизация', 'Настройки']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('phone layout uses bottom navigation', (tester) async {
    await _pumpApp(tester, const Size(400, 850));
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('empty state lets you create a project', (tester) async {
    final c = await _pumpApp(tester, const Size(1440, 1000));
    expect(find.text('Пока нет проектов'), findsOneWidget);

    await tester.tap(find.text('Создать проект'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Запуск продукта');
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();

    expect(c.read(projectsProvider).single.name, 'Запуск продукта');
    expect(find.text('К выполнению'), findsOneWidget);
    expect(find.text('В работе'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);
  });

  testWidgets('adding a task shows a card on the board', (tester) async {
    final c = await _pumpApp(tester, const Size(1440, 1000));
    final repo = c.read(kanbanRepositoryProvider);
    await repo.createProject('P');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Добавить задачу'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Собрать обратную связь');
    await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
    await tester.pumpAndSettle();

    expect(find.text('Собрать обратную связь'), findsOneWidget);
  });

  testWidgets('scheduling an item in My Day', (tester) async {
    await _pumpApp(tester, const Size(1440, 1000));
    await tester.tap(find.text('Мой день').first);
    await tester.pumpAndSettle();
    expect(find.text('На этот день ничего не запланировано'), findsOneWidget);

    await tester.tap(find.text('Запланировать').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).first,
        'Купить продукты');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
    await tester.pumpAndSettle();

    expect(find.text('Купить продукты'), findsOneWidget);
    expect(find.text('Запланировано 1 дело'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('Запланировано 1 дело · 1 уже выполнено'), findsOneWidget);
  });

  test('disabling a module removes it from navigation', () async {
    final c = await _container();
    expect(c.read(destinationsProvider).any((d) => d.path == '/ai'), isTrue);
    await c.read(settingsProvider.notifier).setModuleEnabled('ai', false);
    expect(c.read(destinationsProvider).any((d) => d.path == '/ai'), isFalse);
  });

  test('settings module cannot be disabled', () async {
    final c = await _container();
    await c.read(settingsProvider.notifier).setModuleEnabled('settings', false);
    expect(c.read(destinationsProvider).any((d) => d.path == '/settings'), isTrue);
  });
}
