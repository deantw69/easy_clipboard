import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'storage_location.dart';

/// 本機裝置身分:跨啟動穩定的 deviceId 與顯示名稱,持久化於 App 支援目錄。
class Identity {
  static const _groupKey = 'sync_group';
  static const _secure = FlutterSecureStorage();

  /// 群組碼必須撐過「刪 App 重裝」,各平台機制不同(與鬧鐘 [AlarmGroup] 一致):
  ///   - iOS:appSupport 重裝必清,改存 Keychain。
  ///   - 桌面(macOS/Windows):存成檔案,放在與備忘錄同一個資料夾
  ///     ([StorageLocation.baseDir],預設 Downloads/SyncNest),靠 entitlement 重裝保留。
  ///   - 其餘(Android 等):沿用 appSupport 檔案。
  static bool get _useKeychain => Platform.isIOS;
  static bool get _useBaseDir => Platform.isMacOS || Platform.isWindows;

  /// 桌面群組碼檔案(baseDir);其餘平台用 appSupport。
  static Future<File> _groupFile() async {
    final dir = _useBaseDir
        ? await StorageLocation.instance.baseDir()
        : await getApplicationSupportDirectory();
    return File(p.join(dir.path, _groupKey));
  }

  final String deviceId;
  final String deviceName;

  /// 同步群組碼。空字串=未設定(與所有同網裝置互通);持久化於 `sync_group`。
  final String groupCode;

  const Identity({
    required this.deviceId,
    required this.deviceName,
    this.groupCode = '',
  });

  static Future<Identity> load() async {
    final dir = await getApplicationSupportDirectory();
    final idFile = File('${dir.path}/device_id');
    String id;
    if (await idFile.exists()) {
      id = (await idFile.readAsString()).trim();
    } else {
      id = const Uuid().v4();
      await idFile.writeAsString(id);
    }
    String group = '';
    if (_useKeychain) {
      try {
        group = (await _secure.read(key: _groupKey))?.trim() ?? '';
      } catch (_) {
        group = '';
      }
    } else {
      final groupFile = await _groupFile();
      group = await groupFile.exists()
          ? (await groupFile.readAsString()).trim()
          : '';
    }
    return Identity(
      deviceId: id,
      deviceName: await _defaultName(),
      groupCode: group,
    );
  }

  /// 寫入同步群組碼。空字串會清除(回到未設定)。iOS 走 Keychain、桌面走 baseDir 檔案、其餘走 appSupport。
  static Future<void> saveGroupCode(String code) async {
    final trimmed = code.trim();
    if (_useKeychain) {
      try {
        if (trimmed.isEmpty) {
          await _secure.delete(key: _groupKey);
        } else {
          await _secure.write(key: _groupKey, value: trimmed);
        }
      } catch (_) {
        // 寫入失敗不阻擋使用;記憶體中的代碼仍有效,下次再重試。
      }
      return;
    }
    final groupFile = await _groupFile();
    if (trimmed.isEmpty) {
      if (await groupFile.exists()) await groupFile.delete();
    } else {
      await groupFile.writeAsString(trimmed);
    }
  }

  /// 取得好辨別的裝置名稱。
  ///
  /// 以前直接用 [Platform.localHostname],但 iOS 通常回傳 "localhost",
  /// 對端就只看到 "localhost",難以分辨是哪一台。改用 device_info_plus 取裝置
  /// 自身名稱(macOS 用使用者設定的電腦名稱、iOS 用裝置名稱),取不到才退回原本邏輯。
  static Future<String> _defaultName() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isMacOS) {
        final mac = await info.macOsInfo;
        if (mac.computerName.trim().isNotEmpty) return mac.computerName.trim();
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        final name = ios.name.trim();
        if (name.isNotEmpty && name.toLowerCase() != 'localhost') return name;
        if (ios.model.trim().isNotEmpty) return ios.model.trim();
      } else if (Platform.isAndroid) {
        final a = await info.androidInfo;
        final label = '${a.manufacturer} ${a.model}'.trim();
        if (label.isNotEmpty) return label;
      }
    } catch (_) {
      // 取不到就走下面的退回邏輯。
    }
    final host = Platform.localHostname;
    if (host.isNotEmpty && host.toLowerCase() != 'localhost') return host;
    return '${Platform.operatingSystem}-device';
  }
}
