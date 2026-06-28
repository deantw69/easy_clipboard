import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 桌面整合:
/// - 最小化 / 關閉視窗 → 隱藏到右下角系統匣。
/// - 系統匣圖示:左鍵點擊還原視窗;右鍵叫出選單。
class DesktopTrayService with TrayListener, WindowListener {
  bool _started = false;

  VoidCallback? onWindowShown;

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  static Future<void> ensureInitialized() async {
    if (!isWindows) return;
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(420, 640),
      center: true,
      title: 'Easy Clipboard',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  Future<void> init() async {
    if (!isWindows || _started) return;
    try {
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
      trayManager.addListener(this);

      await trayManager.setIcon('assets/icon/tray_icon.ico');
      await trayManager.setToolTip('Easy Clipboard');

      await _rebuildMenu();
      _started = true;
    } catch (_) {}
  }

  Future<void> _rebuildMenu() async {
    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: '顯示視窗'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '結束'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  /// 把主視窗叫到最前面(系統匣點擊、全域快捷鍵共用)。
  Future<void> showWindow() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
    onWindowShown?.call();
  }

  Future<void> _exitApp() async {
    await windowManager.setPreventClose(false);
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.close();
  }

  // ---- TrayListener ----

  @override
  void onTrayIconMouseDown() => showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
      case 'exit':
        _exitApp();
    }
  }

  // ---- WindowListener ----

  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    }
  }

  @override
  void onWindowMinimize() async => await windowManager.hide();
}
