import 'dart:io';

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
    return Identity(deviceId: id, deviceName: _defaultName());
  }

  static String _defaultName() {
    final host = Platform.localHostname;
    if (host.isNotEmpty) return host;
    return '${Platform.operatingSystem}-device';
  }
}
