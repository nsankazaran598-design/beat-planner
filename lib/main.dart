import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/data/data_store.dart';
import 'core/desktop/desktop.dart';
import 'core/data/log_storage.dart';
import 'core/data/providers.dart';
import 'core/module/module_registry.dart';
import 'core/router.dart';
import 'core/settings/settings_controller.dart';
import 'core/theme/app_theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final supportDir = await getApplicationSupportDirectory();
  final store = await DataStore.open(
    FileLogStorage(Directory('${supportDir.path}${Platform.pathSeparator}data')),
  );
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dataStoreProvider.overrideWithValue(store),
    ],
  );
  await DesktopIntegration.init(container, minimized: args.contains(minimizedFlag));
  for (final m in container.read(enabledModulesProvider)) {
    await m.init(container);
  }
  runApp(UncontrolledProviderScope(container: container, child: const BeatApp()));
}

class BeatApp extends ConsumerWidget {
  const BeatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'beat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
