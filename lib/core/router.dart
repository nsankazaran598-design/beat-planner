import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'module/module_registry.dart';
import 'shell/adaptive_shell.dart';

/// Роутер собирается из экранов включённых модулей и
/// пересобирается, когда модуль включают или выключают.
final routerProvider = Provider<GoRouter>((ref) {
  final destinations = ref.watch(destinationsProvider);
  final paths = destinations.map((d) => d.path).toList();
  final home = paths.first;
  final last = ref.read(_lastLocationProvider);

  final router = GoRouter(
    initialLocation: last.value ?? home,
    redirect: (context, state) {
      final loc = state.uri.path;
      final known = paths.any((p) => loc.startsWith(p));
      return known ? null : home;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AdaptiveShell(location: state.uri.path, child: child),
        routes: [
          for (final d in destinations)
            GoRoute(
              path: d.path,
              pageBuilder: (context, state) => NoTransitionPage(
                key: ValueKey(d.path),
                child: Builder(builder: d.builder),
              ),
            ),
        ],
      ),
    ],
  );

  void remember() =>
      last.value = router.routerDelegate.currentConfiguration.uri.path;
  router.routerDelegate.addListener(remember);
  ref.onDispose(() {
    router.routerDelegate.removeListener(remember);
    router.dispose();
  });
  return router;
});

/// Текущий путь переживает пересборку роутера.
class _LocationHolder {
  String? value;
}

final _lastLocationProvider = Provider<_LocationHolder>((ref) => _LocationHolder());
