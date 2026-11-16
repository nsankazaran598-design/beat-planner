import 'package:material_ui/material_ui.dart';

/// Темы приложения.
///
/// Светлая — токены Material 3 из макета Figma.
/// Тёмная — «болотная»: тёмные оливковые поверхности и моховый акцент.
abstract final class AppTheme {
  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF6750A4),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEADDFF),
    onPrimaryContainer: Color(0xFF4F378A),
    secondary: Color(0xFF625B71),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE8DEF8),
    onSecondaryContainer: Color(0xFF4A4459),
    tertiary: Color(0xFF7D5260),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFFFD8E4),
    onTertiaryContainer: Color(0xFF633B48),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF8C1D18),
    surface: Color(0xFFFEF7FF),
    onSurface: Color(0xFF1D1B20),
    onSurfaceVariant: Color(0xFF49454F),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F2FA),
    surfaceContainer: Color(0xFFF3EDF7),
    surfaceContainerHigh: Color(0xFFECE6F0),
    surfaceContainerHighest: Color(0xFFE6E0E9),
    outline: Color(0xFF79747E),
    outlineVariant: Color(0xFFCAC4D0),
    inverseSurface: Color(0xFF322F35),
    onInverseSurface: Color(0xFFF5EFF7),
    inversePrimary: Color(0xFFD0BCFF),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static const _swampScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFA9C784),
    onPrimary: Color(0xFF1C3008),
    primaryContainer: Color(0xFF3A4F25),
    onPrimaryContainer: Color(0xFFC8E6A2),
    secondary: Color(0xFFBDCBAB),
    onSecondary: Color(0xFF28341C),
    secondaryContainer: Color(0xFF34402B),
    onSecondaryContainer: Color(0xFFD8E7C5),
    tertiary: Color(0xFF9FCFC4),
    onTertiary: Color(0xFF02372F),
    tertiaryContainer: Color(0xFF1F4E45),
    onTertiaryContainer: Color(0xFFBBECE0),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF12170F),
    onSurface: Color(0xFFE0E5D7),
    onSurfaceVariant: Color(0xFFC2C9B6),
    surfaceContainerLowest: Color(0xFF0D110A),
    surfaceContainerLow: Color(0xFF1A2016),
    surfaceContainer: Color(0xFF1E251A),
    surfaceContainerHigh: Color(0xFF283024),
    surfaceContainerHighest: Color(0xFF333B2E),
    outline: Color(0xFF8C9481),
    outlineVariant: Color(0xFF424A3A),
    inverseSurface: Color(0xFFE0E5D7),
    onInverseSurface: Color(0xFF2E342A),
    inversePrimary: Color(0xFF4F6A33),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
  );

  static ThemeData get light => _build(_lightScheme);
  static ThemeData get dark => _build(_swampScheme);

  static ThemeData _build(ColorScheme scheme) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Roboto из макета; на Windows иначе был бы Segoe UI.
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
    );
    return base.copyWith(
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        tileHeight: 56,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
      ),
    );
  }
}
