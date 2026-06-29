import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/storage_location.dart';

/// 鬧鐘「群組代碼」:決定這台裝置同步到哪一筆共用倒數(Firestore `timers/{code}`)。
///
/// 同一個人讓自己多台裝置共用,就在每台輸入同一組代碼;別人各自一組,互不干擾。
///
/// 代碼必須撐過「刪 App 重新安裝」(否則每次 debug 重裝都要重設),各平台機制不同:
///   - 桌面(macOS / Windows):存成檔案,放在與備忘錄同一個資料夾
///     ([StorageLocation.baseDir],預設 Downloads/EasyClipboard)。該資料夾靠
///     entitlement 重裝保留,首次隨機產生後重裝可繼承。
///   - iOS(及其他):appSupport / 備忘錄資料夾重裝必清,唯一能撐過重裝的是 Keychain。
///     用 flutter_secure_storage 存,刪 App 重裝預設仍保留 → 同一支手機拿到同一個預設碼。
///
/// 沿用 [StorageLocation] 的「單例 + ChangeNotifier」pattern;[AlarmPage] 監聽變更後
/// 切換 Firestore 監聽的 document。
class AlarmGroup extends ChangeNotifier {
  AlarmGroup._();
  static final AlarmGroup instance = AlarmGroup._();

  static const _key = 'alarm_group';
  static const _secure = FlutterSecureStorage();

  String _code = '';

  /// 目前群組代碼。
  String get code => _code;

  /// 桌面走檔案、其餘走 Keychain。
  bool get _useFile => Platform.isMacOS || Platform.isWindows;

  /// 啟動時載入;無代碼則產生隨機碼(uuid 前 8 碼 hex)並寫入。
  Future<void> load() async {
    final existing = await _read();
    if (existing != null && existing.isNotEmpty) {
      _code = existing;
      return;
    }
    final generated = const Uuid().v4().replaceAll('-', '').substring(0, 8);
    _code = generated;
    await _write(generated);
  }

  /// 變更群組代碼。空字串忽略;normalize 後與目前相同則不動作。
  Future<void> setCode(String code) async {
    final next = code.trim().toLowerCase();
    if (next.isEmpty || next == _code) return;
    _code = next;
    await _write(next);
    notifyListeners();
  }

  Future<File> _file() async {
    final dir = await StorageLocation.instance.baseDir();
    return File(p.join(dir.path, _key));
  }

  Future<String?> _read() async {
    try {
      if (_useFile) {
        final f = await _file();
        if (await f.exists()) return (await f.readAsString()).trim();
        return null;
      }
      return await _secure.read(key: _key);
    } catch (_) {
      return null; // 讀不到當作沒有,改用隨機碼。
    }
  }

  Future<void> _write(String code) async {
    try {
      if (_useFile) {
        await (await _file()).writeAsString(code);
      } else {
        await _secure.write(key: _key, value: code);
      }
    } catch (_) {
      // 寫檔失敗不阻擋使用(記憶體中的代碼仍有效);下次啟動再重試。
    }
  }
}
