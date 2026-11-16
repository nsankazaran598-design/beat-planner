// Снимки экранов для визуальной проверки (не входят в CI).
// Запуск: flutter test test_screens --update-goldens
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:beat/core/data/data_store.dart';
import 'package:beat/core/data/log_storage.dart';
import 'package:beat/core/data/providers.dart';
import 'package:beat/core/settings/settings_controller.dart';
import 'package:beat/core/ui/format.dart';
import 'package:beat/main.dart';
import 'package:beat/modules/my_day/day_model.dart';
import 'package:beat/modules/my_day/day_providers.dart';
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

final _now = DateTime(2026, 11, 16, 12, 15);

Map<String, Object> extraPrefs = {};

Future<ProviderContainer> _seed(ThemeMode mode) async {
  SharedPreferences.setMockInitialValues({'settings.themeMode': mode.name, ...extraPrefs});
  final prefs = await SharedPreferences.getInstance();
  final store = await DataStore.open(MemoryLogStorage());
  final c = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    dataStoreProvider.overrideWithValue(store),
    clockProvider.overrideWithValue(() => _now),
  ]);
  final day = c.read(dayRepositoryProvider);
  final d = DateTime(2026, 11, 16);
  final t = TimeOfDayMinutes.hm;
  final walk = await day.create(title: 'Утренняя прогулка', date: d, start: t(9, 0));
  await day.setDone(walk, true);
  final mail = await day.create(
      title: 'Разобрать почту', date: d, start: t(10, 30), end: t(11, 30));
  await day.setDone(mail, true);
  await day.create(
      title: 'Встреча с командой', date: d, start: t(13, 0), reminder: ReminderOffset.min15);
  await day.create(title: 'Созвон с дизайнером', date: d, start: t(13, 30), end: t(14, 0));
  await day.create(
      title: 'Тренировка', date: d, start: t(16, 0), reminder: ReminderOffset.min15);
  await day.create(title: 'Купить продукты', date: d, note: 'Молоко, хлеб, овощи');
  await day.create(title: 'Позвонить маме', date: addDays(d, 1), start: t(19, 0));
  await day.create(title: 'Стоматолог', date: addDays(d, 3), start: t(11, 0),
      reminder: ReminderOffset.hour1);
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

  Future<void> openDay(WidgetTester t) async {
    await t.tap(find.text('Мой день').first);
    await t.pumpAndSettle();
  }

  testWidgets('day desktop light', (t) => _shot(t, 'day_desktop_light', const Size(1440, 1000), ThemeMode.light, then: openDay));
  testWidgets('day desktop dark', (t) => _shot(t, 'day_desktop_dark', const Size(1440, 1000), ThemeMode.dark, then: openDay));
  testWidgets('day tablet', (t) => _shot(t, 'day_tablet_light', const Size(900, 1000), ThemeMode.light, then: openDay));
  testWidgets('day phone dark', (t) => _shot(t, 'day_phone_dark', const Size(400, 860), ThemeMode.dark, then: (t) async {
        await t.tap(find.byIcon(Icons.today_outlined));
        await t.pumpAndSettle();
      }));
  testWidgets('day week', (t) => _shot(t, 'day_week_light', const Size(1440, 1000), ThemeMode.light, then: (t) async {
        await openDay(t);
        await t.tap(find.text('Неделя'));
        await t.pumpAndSettle();
      }));
  testWidgets('day editor', (t) => _shot(t, 'day_editor_light', const Size(1440, 1000), ThemeMode.light, then: (t) async {
        await openDay(t);
        await t.tap(find.text('Встреча с командой').first);
        await t.pumpAndSettle();
      }));

  testWidgets('reminders desktop', (t) => _shot(t, 'reminders_desktop_light', const Size(1440, 1000), ThemeMode.light, then: (t) async {
        await t.tap(find.text('Напоминания').first);
        await t.pumpAndSettle();
      }));
  testWidgets('reminders phone', (t) => _shot(t, 'reminders_phone_dark', const Size(400, 860), ThemeMode.dark, then: (t) async {
        await t.tap(find.byIcon(Icons.notifications_none));
        await t.pumpAndSettle();
      }));

  testWidgets('sync intro', (t) => _shot(t, 'sync_intro_light', const Size(1440, 1000), ThemeMode.light, then: (t) async {
        await t.tap(find.text('Синхронизация').first);
        await t.pumpAndSettle();
      }));
  testWidgets('sync group', (t) async {
    extraPrefs = {
      'sync.config': jsonEncode({
        'key': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        'name': 'Компьютер · DESKTOP',
        'peers': {
          'p1': {'name': 'Телефон', 'address': '192.168.1.23', 'port': 47820,
                 'lastSync': DateTime.now().subtract(const Duration(minutes: 3)).millisecondsSinceEpoch},
          'p2': {'name': 'Ноутбук', 'address': '192.168.1.40', 'port': 47820},
        },
      }),
    };
    addTearDown(() => extraPrefs = {});
    await _shot(t, 'sync_group_dark', const Size(1440, 1000), ThemeMode.dark, then: (t) async {
      await t.tap(find.text('Синхронизация').first);
      await t.pumpAndSettle();
    });
  });
  testWidgets('phone more', (t) => _shot(t, 'phone_more_light', const Size(400, 860), ThemeMode.light, then: (t) async {
        await t.tap(find.text('Ещё'));
        await t.pumpAndSettle();
      }));
}
