import 'dart:io';

import 'package:flutter/services.dart';
import 'package:win32_registry/win32_registry.dart';

/// 開機自啟動設定。
///
/// - macOS:透過原生 `SMAppService`(需 macOS 13+),由 method channel 處理。
/// - Windows:寫入 `HKCU\...\CurrentVersion\Run` 登錄機碼,指向目前執行檔。
class AutostartService {
  static const _channel = MethodChannel('easy_clipboard/autostart');
  static const _runPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'EasyClipboard';

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

  /// 設定是否開機自啟動。
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
          key.createValue(RegistryValue.string(
            _valueName,
            '"${Platform.resolvedExecutable}"',
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
}
