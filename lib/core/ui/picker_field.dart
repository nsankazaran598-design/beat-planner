import 'package:material_ui/material_ui.dart';

/// Поле формы, которое по нажатию открывает выбор даты или времени.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
    this.enabled = true,
  });

  final String label;

  /// Текст значения; null — поле пустое.
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          enabled: enabled,
          suffixIcon: value != null && onClear != null && enabled
              ? IconButton(
                  tooltip: 'Очистить',
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 18),
                )
              : null,
        ),
        child: Text(value ?? ''),
      ),
    );
  }
}

Future<TimeOfDay?> pickTime(BuildContext context, TimeOfDay initial) => showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
