import 'dart:io' show Platform;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'window_bounds_service.dart';

/// 桌面(macOS / Windows)系統匣整合:
/// - Windows:最小化 / 關閉視窗 → 隱藏到右下角系統匣。
/// - macOS:關閉視窗 → 隱藏到狀態列(最小化維持系統慣例進 Dock);
///   點 Dock 圖示也能叫回視窗(AppDelegate.applicationShouldHandleReopen)。
/// - 系統匣圖示:左鍵點擊還原視窗;右鍵叫出選單。
class DesktopTrayService with TrayListener, WindowListener {
  bool _started = false;

  /// 全域單例參照(main 建立的那個),供其他模組(如鬧鐘到點)叫回視窗。
  static DesktopTrayService? instance;

  DesktopTrayService() {
    instance = this;
  }

  VoidCallback? onWindowShown;

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// macOS / Windows 都會初始化 window_manager(視窗 frame 記憶需要)。
  static bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows);

  /// [startHidden] 為 true(開機自啟且選了「自啟時隱藏」)時不彈視窗,
  /// 直接維持隱藏於系統匣,靠 tray 圖示/全域快捷鍵呼出。
  static Future<void> ensureInitialized({bool startHidden = false}) async {
    if (!isDesktop) return;
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(480, 640),
      // 最小 480:低於此寬備忘錄卡片的收合鈕、待辦 Checkbox/複製鈕會擠壓重疊。
      minimumSize: Size(480, 480),
      center: true,
      title: 'SyncNest',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      // 還原上次關閉前的視窗位置/長寬(沒有存檔則用上面預設),show 之前套用避免閃尺寸。
      await WindowBoundsService.instance.applySavedBounds();
      if (startHidden) {
        // 維持隱藏(waitUntilReadyToShow 前視窗本就未顯示),仍開始追蹤 bounds。
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
      WindowBoundsService.instance.startTracking();
    });
  }

  Future<void> init() async {
    if (!isDesktop || _started) return;
    try {
      await windowManager.setPreventClose(true);
      windowManager.addListener(this);
      trayManager.addListener(this);

      if (Platform.isMacOS) {
        // 狀態列用 template image(黑+alpha),系統依深淺色自動反白。
        await trayManager.setIcon(
          'assets/icon/tray_icon_macos.png',
          isTemplate: true,
        );
      } else {
        await trayManager.setIcon('assets/icon/tray_icon.ico');
      }
      await trayManager.setToolTip('SyncNest');

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

  /// 到點提醒用:把主視窗叫回最前面(Windows 背景到點時無 OS 排程通知,
  /// 靠此讓縮在系統匣/最小化的視窗自動彈回,配合響鈴與通知氣泡)。
  Future<void> bringToForeground() async {
    if (!isDesktop) return;
    await showWindow();
  }

  /// 全域快捷鍵用:在前景時隱藏到系統匣,否則叫到最前面(一次呼出一次隱藏)。
  Future<void> toggleWindow() async {
    final visible = await windowManager.isVisible();
    final minimized = await windowManager.isMinimized();
    final focused = await windowManager.isFocused();
    if (visible && !minimized && focused) {
      await windowManager.hide();
    } else {
      await showWindow();
    }
  }

  Future<void> _exitApp() async {
    await windowManager.setPreventClose(false);
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
    if (Platform.isMacOS) {
      // macOS 的 close() 只關視窗不結束 App(delegate 對最後視窗關閉回 false),
      // 要用 destroy()(NSApp.terminate)才會真正退出。
      await windowManager.destroy();
    } else {
      await windowManager.close();
    }
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
  void onWindowMinimize() async {
    // macOS 最小化維持系統慣例(進 Dock);Windows 最小化即收進系統匣。
    if (isWindows) await windowManager.hide();
  }
}
