import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beat/core/module/module_registry.dart';
import 'package:beat/core/settings/settings_controller.dart';
import 'package:beat/main.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  testWidgets('desktop layout shows sidebar with all modules', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = await _container();
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const BeatApp()));
    await tester.pumpAndSettle();

    expect(find.text('beat'), findsOneWidget);
    expect(find.text('Новая задача'), findsOneWidget);
    for (final label in ['Проекты', 'Мой день', 'Напоминания', 'ИИ', 'Настройки']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('phone layout uses bottom navigation', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = await _container();
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const BeatApp()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
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
