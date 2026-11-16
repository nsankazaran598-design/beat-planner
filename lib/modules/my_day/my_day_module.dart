import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/module/app_module.dart';
import 'day_page.dart';
import 'day_providers.dart';
import 'widgets/day_item_editor.dart';

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
          builder: (_) => const DayPage(),
        ),
      ];

  @override
  Future<void> Function(BuildContext context)? get quickAdd => (context) {
        final date = ProviderScope.containerOf(context, listen: false)
            .read(selectedDateProvider);
        return showDayItemEditor(context, date: date);
      };
}
