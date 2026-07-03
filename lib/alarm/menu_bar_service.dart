import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

/// 在 macOS 選單列(menu bar)顯示倒數時間與狀態。
///
/// 僅支援 macOS;其他平台所有方法皆為 no-op。
///
/// **注意**:選單列的 statusItem 由共通的 `DesktopTrayService` 統一建立與擁有
/// (圖示、右鍵選單、點擊還原視窗)。trayManager 是單例、macOS 只有一個
/// statusItem,故本服務**不再自建圖示/tooltip、也不 destroy**——只負責在既有
/// statusItem 上疊倒數文字(`setTitle`),避免兩者互相覆蓋。
class MenuBarService {
  /// 僅 macOS 啟用。
  bool get _enabled => !kIsWeb && Platform.isMacOS;

  /// no-op:statusItem 由 `DesktopTrayService.init()` 建立。保留方法維持呼叫端相容。
  Future<void> init() async {}

  /// 更新選單列顯示的文字(例如「⏰ 04:59 倒數中」)。空字串則只剩圖示。
  Future<void> setTitle(String title) async {
    if (!_enabled) return;
    try {
      await trayManager.setTitle(title);
    } catch (_) {}
  }

  /// 不 destroy 共用 statusItem(生命週期由 `DesktopTrayService` 管);只清掉倒數文字。
  Future<void> dispose() async {
    if (!_enabled) return;
    try {
      await trayManager.setTitle('');
    } catch (_) {}
  }
}
