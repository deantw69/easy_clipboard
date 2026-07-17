import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// macOS 選單列(狀態列)倒數顯示開關。
///
/// 僅 macOS 有意義:是否在狀態列的 SyncNest statusItem 上疊倒數文字
/// (實際疊字由 `MenuBarService` 負責,本類只管「要不要顯示」的偏好)。
/// 預設開啟;旗標存 appSupport 純文字檔("1"/"0"),依既有設定持久化 pattern。
class MenuBarPref extends ChangeNotifier {
  MenuBarPref._();
  static final MenuBarPref instance = MenuBarPref._();

  /// 目前平台是否適用此設定(僅 macOS)。
  static bool get supported => !kIsWeb && Platform.isMacOS;

  bool _showTimer = true;

  /// 是否在狀態列顯示倒數(預設 true)。
  bool get showTimer => _showTimer;

  Future<File> _flagFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'menu_bar_timer'));
  }

  /// 啟動時載入設定;讀不到(首次)維持預設 true。
  Future<void> load() async {
    if (!supported) return;
    try {
      final f = await _flagFile();
      if (await f.exists()) {
        _showTimer = (await f.readAsString()).trim() != '0';
      }
    } catch (_) {}
  }

  /// 設定是否顯示,寫檔並通知監聽者即時反應。
  Future<void> setShowTimer(bool value) async {
    if (_showTimer == value) return;
    _showTimer = value;
    notifyListeners();
    try {
      await (await _flagFile()).writeAsString(value ? '1' : '0');
    } catch (_) {}
  }
}
