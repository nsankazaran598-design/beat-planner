import 'package:material_ui/material_ui.dart';

import '../../core/module/app_module.dart';
import '../../core/shell/page_scaffold.dart';

class MyDayModule extends AppModule {
  const MyDayModule();

  @override
  String get id => 'my_day';
  @override
  String get title => 'Мой день';
  @override
  String get description => 'Личные задачи и события на конкретную дату и время';

  @override
  List<ModuleDestination> get destinations => [
        ModuleDestination(
          path: '/day',
          label: 'Мой день',
          icon: Icons.today_outlined,
          selectedIcon: Icons.today,
          order: 20,
          builder: (_) => const PageScaffold(
            breadcrumb: 'Личное пространство / Расписание',
            title: 'Мой день',
            body: ComingSoon(
              icon: Icons.today_outlined,
              text: 'Расписание дня появится в v0.3',
            ),
          ),
        ),
      ];
}
