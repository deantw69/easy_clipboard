import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/storage_location.dart';

/// 鬧鐘「群組代碼」:決定這台裝置同步到哪一筆共用倒數(Firestore `timers/{code}`)。
///
/// 同一個人讓自己多台裝置共用,就在每台輸入同一組代碼;別人各自一組,互不干擾。
///
/// 代碼必須撐過「刪 App 重新安裝」(否則每次 debug 重裝都要重設),各平台機制不同:
///   - 桌面(macOS / Windows):存成檔案,放在與備忘錄同一個資料夾
///     ([StorageLocation.baseDir],預設 Downloads/SyncNest)。該資料夾靠
///     entitlement 重裝保留,首次隨機產生後重裝可繼承。另在 appSupport 寫一份
///     備援(見 [_backupFile])。
///   - iOS(及其他):appSupport / 備忘錄資料夾重裝必清,唯一能撐過重裝的是 Keychain。
///     用 flutter_secure_storage 存,刪 App 重裝預設仍保留 → 同一支手機拿到同一個預設碼。
///
/// **讀取失敗絕不可當成「沒有代碼」**:那會讓 [load] 產生新碼覆寫掉原本的,代碼
/// 永久消失(症狀:放著半天沒開 App,群組代碼就跑掉)。三態處理見 [_read] 與 [load]。
///
/// 沿用 [StorageLocation] 的「單例 + ChangeNotifier」pattern;[AlarmPage] 監聽變更後
/// 切換 Firestore 監聽的 document。
class AlarmGroup extends ChangeNotifier {
  AlarmGroup._();
  static final AlarmGroup instance = AlarmGroup._();

  static const _key = 'alarm_group';
  static const _secure = FlutterSecureStorage();

  /// iOS Keychain 存取層級。
  ///
  /// 套件預設是 `kSecAttrAccessibleWhenUnlocked`,裝置**鎖定**時讀取會得到
  /// `errSecInteractionNotAllowed` 並拋 PlatformException。鬧鐘到點的本地通知
  /// 常在裝置鎖定時把 App 喚到背景,正好命中此情境。改用 `first_unlock`:
  /// 開機後被解鎖過一次即可讀取,之後再鎖定也讀得到。
  ///
  /// 舊資料相容:套件的 read 查詢不帶 `kSecAttrAccessible`,舊的 item 仍找得到;
  /// [load] 讀到值後會回寫一次,把 item 遷移到新的存取層級。
  static const _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );

  String _code = '';
  bool _loadFailed = false;

  /// 目前群組代碼。[loadFailed] 為 true 時是空字串,不可拿去訂閱 Firestore。
  String get code => _code;

  /// 上次 [load] 是否因「讀取失敗」而沒取得代碼(與「確實還沒有代碼」不同)。
  bool get loadFailed => _loadFailed;

  /// 桌面走檔案、其餘走 Keychain。
  bool get _useFile => Platform.isMacOS || Platform.isWindows;

  /// 啟動時載入。三種結果分開處理:
  ///   - 讀到代碼:採用,並回寫一次(補齊備援檔、遷移 iOS Keychain 存取層級)。
  ///   - 確定沒有代碼(首次啟動):產生隨機碼(uuid 前 8 碼 hex)並寫入。
  ///   - 讀取失敗:維持空碼並標記 [loadFailed],**不產生新碼、不寫入**,
  ///     等 [retryLoad] 在裝置解鎖後重試。
  Future<void> load() async {
    final r = await _read();
    if (r.failed) {
      _loadFailed = true;
      return;
    }
    _loadFailed = false;
    final existing = r.value?.trim() ?? '';
    if (existing.isNotEmpty) {
      _code = existing;
      await _write(existing);
      return;
    }
    final generated = const Uuid().v4().replaceAll('-', '').substring(0, 8);
    _code = generated;
    await _write(generated);
  }

  /// [loadFailed] 時重試讀取,例如冷啟動當下裝置還沒解鎖、回前景時已解鎖。
  /// 取得代碼才 [notifyListeners],讓 [AlarmPage] 重新訂閱正確的 document。
  Future<void> retryLoad() async {
    if (!_loadFailed) return;
    await load();
    if (!_loadFailed && _code.isNotEmpty) notifyListeners();
  }

  /// 變更群組代碼。空字串忽略;normalize 後與目前相同則不動作。
  Future<void> setCode(String code) async {
    final next = code.trim().toLowerCase();
    if (next.isEmpty || next == _code) return;
    _code = next;
    _loadFailed = false;
    await _write(next);
    notifyListeners();
  }

  /// 桌面主檔:與備忘錄同一個資料夾,靠 entitlement 撐過重裝。
  Future<File> _file() async {
    final dir = await StorageLocation.instance.baseDir();
    return File(p.join(dir.path, _key));
  }

  /// 桌面備援檔:appSupport。
  ///
  /// [StorageLocation.baseDir] 在 macOS security-scoped bookmark 解析失敗時會
  /// **靜默退回預設資料夾**,此時主檔讀不到,只靠主檔會誤判成「沒有代碼」。
  /// 備援檔補這個洞;它重裝會被清空,與主檔正好互補。
  Future<File> _backupFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _key));
  }

  /// 讀取代碼。`failed` 為 true 代表**讀取失敗**,呼叫端不可當成「沒有代碼」;
  /// `failed` 為 false 且 `value` 為空才是「確定沒有代碼」。
  Future<({bool failed, String? value})> _read() async {
    if (!_useFile) {
      try {
        final v = await _secure.read(key: _key, iOptions: _iosOptions);
        return (failed: false, value: v);
      } catch (_) {
        return (failed: true, value: null);
      }
    }
    var failed = false;
    try {
      final f = await _file();
      if (await f.exists()) {
        final s = (await f.readAsString()).trim();
        if (s.isNotEmpty) return (failed: false, value: s);
      }
    } catch (_) {
      failed = true;
    }
    try {
      final f = await _backupFile();
      if (await f.exists()) {
        final s = (await f.readAsString()).trim();
        if (s.isNotEmpty) return (failed: false, value: s);
      }
    } catch (_) {
      failed = true;
    }
    return (failed: failed, value: null);
  }

  Future<void> _write(String code) async {
    if (!_useFile) {
      try {
        await _secure.write(key: _key, value: code, iOptions: _iosOptions);
      } catch (_) {
        // 寫入失敗不阻擋使用(記憶體中的代碼仍有效);下次啟動再重試。
      }
      return;
    }
    // 主檔與備援檔各自 try,其一失敗不影響另一個。
    try {
      await (await _file()).writeAsString(code);
    } catch (_) {
      // 同上,不阻擋使用。
    }
    try {
      await (await _backupFile()).writeAsString(code);
    } catch (_) {
      // 同上,不阻擋使用。
    }
  }
}
