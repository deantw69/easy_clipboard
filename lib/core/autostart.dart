import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32_registry/win32_registry.dart';

/// 開機自啟動設定。
///
/// - macOS:透過原生 `SMAppService`(需 macOS 13+),由 method channel 處理。
/// - Windows:寫入 `HKCU\...\CurrentVersion\Run` 登錄機碼,指向目前執行檔。
///
/// 另提供「自啟時隱藏視窗背景執行」子選項([isStartHiddenEnabled] /
/// [setStartHidden]):開啟後由登入啟動時只進系統匣不彈視窗,配合快捷鍵/匣圖示呼出。
class AutostartService {
  static const _channel = MethodChannel('syncnest/autostart');
  static const _runPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'SyncNest';

  /// Windows 登入啟動時附帶的旗標;`main()` 偵測到就啟動即隱藏到系統匣。
  static const hiddenFlag = '--hidden';

  /// 目前平台是否支援開機自啟動設定。
  static bool get supported => Platform.isMacOS || Platform.isWindows;

  /// 是否已啟用開機自啟動。
  static Future<bool> isEnabled() async {
    if (Platform.isMacOS) {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    }
    if (Platform.isWindows) {
      final key = Registry.openPath(RegistryHive.currentUser, path: _runPath);
      try {
        return key.getStringValue(_valueName) != null;
      } finally {
        key.close();
      }
    }
    return false;
  }

  /// 設定是否開機自啟動。Windows 依「自啟時隱藏」旗標決定命令列是否帶 [hiddenFlag]。
  static Future<void> setEnabled(bool enabled) async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod('setEnabled', enabled);
      return;
    }
    if (Platform.isWindows) {
      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: _runPath,
        desiredAccessRights: AccessRights.allAccess,
      );
      try {
        if (enabled) {
          final hidden = await isStartHiddenEnabled();
          key.createValue(RegistryValue.string(
            _valueName,
            _windowsRunCommand(hidden),
          ));
        } else {
          try {
            key.deleteValue(_valueName);
          } catch (_) {
            // 原本就沒有這個值,忽略。
          }
        }
      } finally {
        key.close();
      }
    }
  }

  static String _windowsRunCommand(bool hidden) {
    final exe = '"${Platform.resolvedExecutable}"';
    return hidden ? '$exe $hiddenFlag' : exe;
  }

  // ---- 自啟時隱藏視窗 ----

  /// 「自啟時隱藏」旗標,存 appSupport 純文字檔("1"/"0")。
  static Future<File> _hiddenFlagFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'autostart_hidden'));
  }

  /// 是否啟用「自啟時隱藏視窗」(預設 false)。
  static Future<bool> isStartHiddenEnabled() async {
    try {
      final f = await _hiddenFlagFile();
      if (!await f.exists()) return false;
      return (await f.readAsString()).trim() == '1';
    } catch (_) {
      return false;
    }
  }

  /// 設定「自啟時隱藏視窗」;Windows 下若已啟用開機自啟,連帶更新 Run 命令列旗標。
  static Future<void> setStartHidden(bool value) async {
    try {
      await (await _hiddenFlagFile()).writeAsString(value ? '1' : '0');
    } catch (_) {}
    if (Platform.isWindows && await isEnabled()) {
      // 重寫 Run 值以帶上/移除 --hidden。
      await setEnabled(true);
    }
  }

  /// 本次是否應以隱藏視窗方式啟動(供 `main()` 判斷)。
  /// - Windows:命令列帶 [hiddenFlag](僅登入啟動時才會帶)。
  /// - macOS:確為登入啟動([_wasLaunchedAtLogin])且使用者開了「自啟時隱藏」。
  static Future<bool> shouldStartHidden(List<String> args) async {
    if (Platform.isWindows) {
      return args.contains(hiddenFlag);
    }
    if (Platform.isMacOS) {
      if (!await isStartHiddenEnabled()) return false;
      return await _wasLaunchedAtLogin();
    }
    return false;
  }

  static Future<bool> _wasLaunchedAtLogin() async {
    try {
      return await _channel.invokeMethod<bool>('wasLaunchedAtLogin') ?? false;
    } catch (_) {
      return false;
    }
  }
}
