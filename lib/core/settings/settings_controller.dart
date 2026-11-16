import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.disabledModules = const {},
  });

  final ThemeMode themeMode;
  final Set<String> disabledModules;

  AppSettings copyWith({ThemeMode? themeMode, Set<String>? disabledModules}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        disabledModules: disabledModules ?? this.disabledModules,
      );
}

/// Переопределяется в `main()` уже загруженным экземпляром.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  static const _kTheme = 'settings.themeMode';
  static const _kDisabled = 'settings.disabledModules';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final themeName = prefs.getString(_kTheme);
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == themeName,
        orElse: () => ThemeMode.system,
      ),
      disabledModules: (prefs.getStringList(_kDisabled) ?? const []).toSet(),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_kTheme, mode.name);
  }

  Future<void> setModuleEnabled(String moduleId, bool enabled) async {
    final next = {...state.disabledModules};
    enabled ? next.remove(moduleId) : next.add(moduleId);
    state = state.copyWith(disabledModules: next);
    await _prefs.setStringList(_kDisabled, next.toList()..sort());
  }
}
