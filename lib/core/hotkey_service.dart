import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:path_provider/path_provider.dart';

/// 全域快捷鍵(僅 Windows):在任何地方按下即切換主視窗顯示/隱藏(一次呼出一次隱藏)。
///
/// 設定值持久化於 App 支援目錄的 `hotkey.json`(沿用 identity / last_target /
/// last_tab 的「檔案存 appSupport」pattern,不寫登錄)。
class HotkeyService {
  HotkeyService._();
  static final HotkeyService instance = HotkeyService._();

  /// 目前平台是否支援全域快捷鍵設定。
  static bool get supported => !Platform.isAndroid && Platform.isWindows;

  /// 預設快捷鍵:Ctrl + Alt + C。
  static HotKey get defaultHotKey => HotKey(
        key: PhysicalKeyboardKey.keyC,
        modifiers: const [HotKeyModifier.control, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      );

  HotKey? _current;
  void Function()? _onTriggered;

  /// 目前生效的快捷鍵(未載入前回傳預設值)。
  HotKey get current => _current ?? defaultHotKey;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/hotkey.json');
  }

  /// 啟動時載入已存的快捷鍵並註冊;[onTriggered] 在按下時呼叫。
  Future<void> start(void Function() onTriggered) async {
    if (!supported) return;
    _onTriggered = onTriggered;
    // 清掉開發 hot reload 殘留的註冊,避免重複。
    await hotKeyManager.unregisterAll();
    _current = await _load();
    await _register(_current!);
  }

  Future<HotKey> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        return HotKey.fromJson(map);
      }
    } catch (_) {
      // 損毀或格式不符 → 退回預設。
    }
    return defaultHotKey;
  }

  Future<void> _register(HotKey hotKey) async {
    await hotKeyManager.register(
      hotKey,
      keyDownHandler: (_) => _onTriggered?.call(),
    );
  }

  /// 變更快捷鍵:取消舊的、註冊新的、存檔。
  Future<void> update(HotKey hotKey) async {
    if (!supported) return;
    // 強制系統範圍,確保不在前景也能觸發。
    final next = HotKey(
      key: hotKey.key,
      modifiers: hotKey.modifiers,
      scope: HotKeyScope.system,
    );
    await hotKeyManager.unregisterAll();
    _current = next;
    await _register(next);
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(next.toJson()));
    } catch (_) {
      // 寫檔失敗不影響當下已註冊的快捷鍵。
    }
  }
}
