import 'package:material_ui/material_ui.dart';

import 'breakpoints.dart';

/// Общая разметка экрана из макета: путь, заголовок, подзаголовок,
/// главное действие справа и содержимое.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.breadcrumb,
    this.subtitle,
    this.action,
    required this.body,
  });

  final String title;
  final String? breadcrumb;
  final String? subtitle;
  final Widget? action;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = Breakpoints.of(context) == LayoutSize.compact;
    final pad = compact ? 16.0 : 32.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, compact ? 12 : 32, pad, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (breadcrumb != null && !compact)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(breadcrumb!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: compact
                            ? theme.textTheme.headlineSmall
                            : theme.textTheme.headlineMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(subtitle!,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 16), action!],
            ],
          ),
          SizedBox(height: compact ? 16 : 24),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Заглушка содержимого для модулей, которые ещё в разработке.
class ComingSoon extends StatelessWidget {
  const ComingSoon({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: scheme.primary),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
