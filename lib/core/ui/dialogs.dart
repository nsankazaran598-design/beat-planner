import 'package:material_ui/material_ui.dart';

import '../shell/breakpoints.dart';

/// Показывает [child] диалогом на десктопе и шторкой снизу на телефоне.
Future<T?> showAdaptiveSheet<T>(BuildContext context, WidgetBuilder builder) {
  if (Breakpoints.of(context) == LayoutSize.compact) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: builder(ctx),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: builder(ctx),
      ),
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String action = 'Удалить',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return result ?? false;
}

/// Диалог с одним или двумя текстовыми полями. Возвращает значения полей.
Future<List<String>?> promptText(
  BuildContext context, {
  required String title,
  required List<String> labels,
  List<String> initial = const [],
  String action = 'Сохранить',
}) {
  final controllers = [
    for (var i = 0; i < labels.length; i++)
      TextEditingController(text: i < initial.length ? initial[i] : ''),
  ];
  return showDialog<List<String>>(
    context: context,
    builder: (ctx) {
      void submit() {
        if (controllers.first.text.trim().isEmpty) return;
        Navigator.pop(ctx, [for (final c in controllers) c.text.trim()]);
      }

      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                TextField(
                  controller: controllers[i],
                  autofocus: i == 0,
                  decoration: InputDecoration(labelText: labels[i]),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: submit, child: Text(action)),
        ],
      );
    },
  );
}
