import 'package:material_ui/material_ui.dart';

/// Пункт навигации, который модуль добавляет в меню приложения.
class ModuleDestination {
  const ModuleDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
    this.order = 100,
  });

  /// Путь экрана, например `/kanban`.
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;

  /// Чем меньше число, тем выше пункт в меню.
  final int order;
}

/// Базовый контракт функционального модуля.
///
/// Чтобы добавить функцию в приложение, создайте класс-наследник
/// и зарегистрируйте его в `lib/modules/modules.dart`. Чтобы убрать —
/// удалите строку регистрации (или выключите модуль в настройках,
/// если [canDisable] == true).
abstract class AppModule {
  const AppModule();

  /// Стабильный идентификатор, хранится в настройках и в данных синхронизации.
  String get id;

  /// Название для экрана настроек модулей.
  String get title;

  /// Короткое описание для экрана настроек модулей.
  String get description;

  /// Можно ли выключить модуль пользователю.
  bool get canDisable => true;

  /// Включён ли модуль при первом запуске.
  bool get enabledByDefault => true;

  /// Экраны модуля, которые попадают в навигацию.
  List<ModuleDestination> get destinations => const [];

  /// Секция в боковом меню десктопа (например, «Мои проекты»).
  WidgetBuilder? get sidebarSection => null;

  /// Обработчик кнопки «Новая задача» в оболочке. Если её предлагают
  /// несколько модулей, побеждает модуль текущего экрана, иначе первый.
  Future<void> Function(BuildContext context)? get quickAdd => null;

  /// Вызывается один раз при старте приложения, если модуль включён.
  Future<void> init() async {}
}
