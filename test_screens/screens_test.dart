// Снимки экранов для визуальной проверки (не входят в CI).
// Запуск: flutter test test_screens --update-goldens
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:beat/core/data/data_store.dart';
import 'package:beat/core/data/log_storage.dart';
import 'package:beat/core/data/providers.dart';
import 'package:beat/core/settings/settings_controller.dart';
import 'package:beat/main.dart';
import 'package:beat/modules/kanban/kanban_model.dart';
import 'package:beat/modules/kanban/kanban_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  ByteData read(String f) =>
      ByteData.view(Uint8List.fromList(File('$dir/$f').readAsBytesSync()).buffer);
  final roboto = FontLoader('Roboto');
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
    roboto.addFont(Future.value(read(f)));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(read('materialicons-regular.otf'))))
      .load();
}

Future<ProviderContainer> _seed(ThemeMode mode) async {
  SharedPreferences.setMockInitialValues({'settings.themeMode': mode.name});
  final prefs = await SharedPreferences.getInstance();
  final store = await DataStore.open(MemoryLogStorage());
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    dataStoreProvider.overrideWithValue(store),
  ]);
  final repo = c.read(kanbanRepositoryProvider);
  final p = await repo.createProject('Запуск продукта',
      description: 'От идеи до релиза — всё на одной доске');
  await repo.createProject('Рабочие задачи');
  await repo.createProject('Личное');
  final [todo, doing, done] = repo.columns(p);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  Future<void> add(String col, String title, String cat, String desc,
          {int? dueIn, TaskPriority pr = TaskPriority.normal}) =>
      repo.createTask(
          projectId: p,
          columnId: col,
          title: title,
          category: cat,
          description: desc,
          priority: pr,
          due: dueIn == null ? null : today.add(Duration(days: dueIn)));
  await add(todo.id, 'Собрать обратную связь', 'Исследование',
      '5 интервью с пользователями.', dueIn: 2);
  await add(todo.id, 'Продумать онбординг', 'Дизайн', 'Первый вход без лишних шагов.',
      dueIn: 3);
  await add(todo.id, 'Подготовить тексты', 'Контент', 'Заголовки и пустые состояния.',
      dueIn: 4);
  await add(doing.id, 'Главный экран', '', 'Доработать макет и состояния.',
      dueIn: 0, pr: TaskPriority.high);
  await add(doing.id, 'Подключение API', 'Разработка', 'Проверить запросы к ИИ.',
      dueIn: 2, pr: TaskPriority.urgent);
  await add(done.id, 'Карта сценариев', 'Исследование', 'Основные пути согласованы.');
  await add(done.id, 'Структура проекта', 'Разработка', 'Рабочее пространство готово.',
      dueIn: -2);
  return c;
}

Future<void> _shot(WidgetTester tester, String name, Size size, ThemeMode mode,
    {Future<void> Function(WidgetTester)? then}) async {
  await _loadFonts();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = await _seed(mode);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const BeatApp()));
  await tester.pumpAndSettle();
  if (then != null) await then(tester);
  await expectLater(find.byType(BeatApp), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  testWidgets('desktop light', (t) => _shot(t, 'desktop_light', const Size(1440, 1000), ThemeMode.light));
  testWidgets('desktop dark', (t) => _shot(t, 'desktop_dark', const Size(1440, 1000), ThemeMode.dark));
  testWidgets('tablet dark', (t) => _shot(t, 'tablet_dark', const Size(900, 1000), ThemeMode.dark));
  testWidgets('phone light', (t) => _shot(t, 'phone_light', const Size(400, 860), ThemeMode.light));
  testWidgets('phone dark', (t) => _shot(t, 'phone_dark', const Size(400, 860), ThemeMode.dark));
  testWidgets('editor', (t) => _shot(t, 'editor_light', const Size(1440, 1000), ThemeMode.light,
      then: (t) async {
        await t.tap(find.text('Главный экран'));
        await t.pumpAndSettle();
      }));
  testWidgets('phone editor', (t) => _shot(t, 'phone_editor_dark', const Size(400, 860), ThemeMode.dark,
      then: (t) async {
        await t.tap(find.byTooltip('Новая задача'));
        await t.pumpAndSettle();
      }));
}
