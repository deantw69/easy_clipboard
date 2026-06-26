import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

/// 在 macOS 選單列(menu bar)顯示倒數時間與狀態。
///
/// 僅支援 macOS;其他平台所有方法皆為 no-op。
class MenuBarService {
  bool _started = false;

  /// 僅 macOS 啟用。
  bool get _enabled => !kIsWeb && Platform.isMacOS;

  /// 建立選單列項目(圖示)。失敗不影響 App。
  Future<void> init() async {
    if (!_enabled || _started) return;
    try {
      await trayManager.setIcon(
        'assets/icon/tray_icon.png',
        isTemplate: true, // 黑色 template,自動適應深淺色選單列
      );
      await trayManager.setToolTip('跨平台鬧鐘');
      _started = true;
    } catch (_) {
      // 選單列建立失敗就略過(不影響主功能)。
    }
  }

  /// 更新選單列顯示的文字(例如「⏰ 04:59 倒數中」)。空字串則只剩圖示。
  Future<void> setTitle(String title) async {
    if (!_enabled || !_started) return;
    try {
      await trayManager.setTitle(title);
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (!_enabled || !_started) return;
    try {
      await trayManager.destroy();
    } catch (_) {}
    _started = false;
  }
}
