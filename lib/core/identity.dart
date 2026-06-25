import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 本機裝置身分:跨啟動穩定的 deviceId 與顯示名稱,持久化於 App 支援目錄。
class Identity {
  final String deviceId;
  final String deviceName;

  const Identity({required this.deviceId, required this.deviceName});

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
    return Identity(deviceId: id, deviceName: await _defaultName());
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
