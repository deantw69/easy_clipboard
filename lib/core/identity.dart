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

  /// iOS Keychain 存取層級。
  ///
  /// 套件預設是 `kSecAttrAccessibleWhenUnlocked`,裝置**鎖定**時讀取會得到
  /// `errSecInteractionNotAllowed` 並拋 PlatformException,群組碼就會被誤判成
  /// 「未設定」(備忘錄變成與全網裝置互通)。改用 `first_unlock`:開機後被解鎖過
  /// 一次即可讀取。舊 item 靠 [readGroupCode] 讀到值後回寫一次完成遷移。
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

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

  /// 桌面備援檔(appSupport)。
  ///
  /// [StorageLocation.baseDir] 在 macOS security-scoped bookmark 解析失敗時會
  /// **靜默退回預設資料夾**,此時主檔讀不到,只靠主檔會誤判成「未設定」。
  /// 備援檔補這個洞;它重裝會被清空,與主檔正好互補。非桌面平台不需要
  /// (主檔本來就在 appSupport)。
  static Future<File> _backupGroupFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _groupKey));
  }

  /// 讀取同步群組碼。`failed` 為 true 代表**讀取失敗**,呼叫端不可當成「未設定」;
  /// `failed` 為 false 且 `value` 為空才是「確實未設定」(與全網裝置互通)。
  ///
  /// 讀到值時順手回寫一次,補齊備援檔並把 iOS Keychain item 遷移到 [_iosOptions]。
  static Future<({bool failed, String value})> readGroupCode() async {
    if (_useKeychain) {
      String? v;
      try {
        v = await _secure.read(key: _groupKey, iOptions: _iosOptions);
      } catch (_) {
        return (failed: true, value: '');
      }
      final code = v?.trim() ?? '';
      if (code.isNotEmpty) await saveGroupCode(code);
      return (failed: false, value: code);
    }
    var failed = false;
    try {
      final f = await _groupFile();
      if (await f.exists()) {
        final s = (await f.readAsString()).trim();
        if (s.isNotEmpty) {
          if (_useBaseDir) await saveGroupCode(s);
          return (failed: false, value: s);
        }
      }
    } catch (_) {
      failed = true;
    }
    if (_useBaseDir) {
      try {
        final f = await _backupGroupFile();
        if (await f.exists()) {
          final s = (await f.readAsString()).trim();
          if (s.isNotEmpty) return (failed: false, value: s);
        }
      } catch (_) {
        failed = true;
      }
    }
    return (failed: failed, value: '');
  }

  final String deviceId;
  final String deviceName;

  /// 同步群組碼。空字串=未設定(與所有同網裝置互通);持久化於 `sync_group`。
  final String groupCode;

  /// 群組碼是否**讀取失敗**(與 [groupCode] 為空的「確實未設定」不同)。
  ///
  /// 為 true 時 [groupCode] 不可信,拿去比對會把本機當成「未設定」而與全網裝置
  /// 互通。呼叫端(AppController)應暫停同步並在裝置解鎖後重試 [readGroupCode]。
  final bool groupLoadFailed;

  const Identity({
    required this.deviceId,
    required this.deviceName,
    this.groupCode = '',
    this.groupLoadFailed = false,
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
    final group = await readGroupCode();
    return Identity(
      deviceId: id,
      deviceName: await _defaultName(),
      groupCode: group.value,
      groupLoadFailed: group.failed,
    );
  }

  /// 寫入同步群組碼。空字串會清除(回到未設定)。iOS 走 Keychain、桌面走 baseDir 檔案、其餘走 appSupport。
  static Future<void> saveGroupCode(String code) async {
    final trimmed = code.trim();
    if (_useKeychain) {
      try {
        if (trimmed.isEmpty) {
          await _secure.delete(key: _groupKey, iOptions: _iosOptions);
        } else {
          await _secure.write(
            key: _groupKey,
            value: trimmed,
            iOptions: _iosOptions,
          );
        }
      } catch (_) {
        // 寫入失敗不阻擋使用;記憶體中的代碼仍有效,下次再重試。
      }
      return;
    }
    // 桌面主檔與備援檔各自 try,其一失敗不影響另一個。
    try {
      final groupFile = await _groupFile();
      if (trimmed.isEmpty) {
        if (await groupFile.exists()) await groupFile.delete();
      } else {
        await groupFile.writeAsString(trimmed);
      }
    } catch (_) {
      // 同上,不阻擋使用。
    }
    if (!_useBaseDir) return; // 非桌面:主檔已在 appSupport,無須備援。
    try {
      final backup = await _backupGroupFile();
      if (trimmed.isEmpty) {
        if (await backup.exists()) await backup.delete();
      } else {
        await backup.writeAsString(trimmed);
      }
    } catch (_) {
      // 同上,不阻擋使用。
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
