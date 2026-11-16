import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import '../settings/settings_controller.dart';

/// Флаг запуска свёрнутым в трей (используется автозапуском).
const minimizedFlag = '--minimized';

bool get isDesktopWindows => !kIsWeb && Platform.isWindows;

/// Настройки поведения окна на Windows.
@immutable
class DesktopSettings {
  const DesktopSettings({this.closeToTray = true, this.launchAtStartup = false});

  final bool closeToTray;
  final bool launchAtStartup;
}

final desktopSettingsProvider =
    NotifierProvider<DesktopSettingsController, DesktopSettings>(
        DesktopSettingsController.new);

class DesktopSettingsController extends Notifier<DesktopSettings> {
  static const _kTray = 'desktop.closeToTray';

  @override
  DesktopSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    if (isDesktopWindows) {
      // Состояние автозапуска хранит сама Windows (реестр).
      // Если автозапуск не настроен (нет окна), плагин бросает исключение.
      Future(launchAtStartup.isEnabled).then((v) {
        if (v != state.launchAtStartup) {
          state = DesktopSettings(closeToTray: state.closeToTray, launchAtStartup: v);
        }
      }).catchError((Object e) => debugPrint('autostart: $e'));
    }
    return DesktopSettings(closeToTray: prefs.getBool(_kTray) ?? true);
  }

  Future<void> setCloseToTray(bool v) async {
    state = DesktopSettings(closeToTray: v, launchAtStartup: state.launchAtStartup);
    await ref.read(sharedPreferencesProvider).setBool(_kTray, v);
  }

  Future<void> setLaunchAtStartup(bool v) async {
    try {
      v ? await launchAtStartup.enable() : await launchAtStartup.disable();
      state = DesktopSettings(closeToTray: state.closeToTray, launchAtStartup: v);
    } catch (e) {
      debugPrint('autostart: $e');
    }
  }
}

/// Окно, трей и автозапуск на Windows.
abstract final class DesktopIntegration {
  static tray.TrayIcon? _trayIcon;
  static bool _quitting = false;

  static Future<void> init(ProviderContainer container, {required bool minimized}) async {
    if (!isDesktopWindows) return;
    final window = WindowManager.instance.getCurrent();
    if (window == null) return;

    window.title = 'beat';
    window.minimumSize = const Size(420, 600).toNative();
    if (minimized) window.hide();

    // Закрытие окна сворачивает приложение в трей, чтобы напоминания продолжали работать.
    window.addListener((event) {
      if (event is WindowCloseRequestedEvent &&
          !_quitting &&
          container.read(desktopSettingsProvider).closeToTray) {
        event.request.cancel();
        window.hide();
      }
    });

    launchAtStartup.setup(
      appName: 'beat',
      appPath: Platform.resolvedExecutable,
      args: const [minimizedFlag],
    );

    try {
      final icon = tray.TrayIcon.create();
      if (icon == null) return;
      _trayIcon = icon;
      icon.icon = tray.ImageAsset.fromAsset('assets/tray_icon.ico');
      icon.setTooltip('beat');

      void show() {
        window.show();
        window.focus();
      }

      final menu = tray.Menu.create()!;
      final open = tray.MenuItem.createWithLabelAndType('Открыть beat', tray.MenuItemType.normal)!;
      open.addListener((e) {
        if (e is tray.MenuItemClickedEvent) show();
      });
      final quit = tray.MenuItem.createWithLabelAndType('Выход', tray.MenuItemType.normal)!;
      quit.addListener((e) {
        if (e is tray.MenuItemClickedEvent) {
          _quitting = true;
          _trayIcon?.dispose();
          window.close();
        }
      });
      menu.addItem(open);
      menu.addSeparator();
      menu.addItem(quit);

      icon.setContextMenu(menu);
      icon.setContextMenuTrigger(tray.ContextMenuTrigger.rightClicked);
      icon.addListener((e) {
        if (e is tray.TrayIconClickedEvent || e is tray.TrayIconDoubleClickedEvent) show();
      });
      icon.setVisible(true);
    } catch (e) {
      debugPrint('tray: $e');
    }
  }
}
