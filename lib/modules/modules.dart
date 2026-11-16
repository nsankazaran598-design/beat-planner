import '../core/module/app_module.dart';
import 'ai/ai_module.dart';
import 'kanban/kanban_module.dart';
import 'my_day/my_day_module.dart';
import 'reminders/reminders_module.dart';
import 'settings/settings_module.dart';

/// Единственное место, где модули подключаются к приложению.
/// Добавить функцию — добавить строку; убрать — удалить строку.
const List<AppModule> registeredModules = [
  KanbanModule(),
  MyDayModule(),
  RemindersModule(),
  AiModule(),
  SettingsModule(),
];
