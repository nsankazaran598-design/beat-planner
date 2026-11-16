import 'package:flutter/widgets.dart';

enum LayoutSize { compact, medium, expanded }

/// Точки перелома: телефон < 600 ≤ планшет < 1100 ≤ десктоп.
abstract final class Breakpoints {
  static const double medium = 600;
  static const double expanded = 1100;

  static LayoutSize of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= expanded) return LayoutSize.expanded;
    if (width >= medium) return LayoutSize.medium;
    return LayoutSize.compact;
  }
}
