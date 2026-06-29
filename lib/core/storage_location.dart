import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 桌面版(macOS / Windows)的資料儲存位置。
///
/// 預設沿用「使用者下載資料夾下的 EasyClipboard/」(見 memo_store 的說明:
/// 重裝 App 不會被清掉)。使用者可在設定中改選其他資料夾,選定值以純文字
/// 持久化於 appSupport 的 `storage_dir`(沿用 identity / last_target /
/// hotkey.json 的「小設定檔存 appSupport」pattern)。
///
/// memos.json 與接收到的圖片都改向本服務查詢 [baseDir],兩者落在同一資料夾。
class StorageLocation extends ChangeNotifier {
  StorageLocation._();
  static final StorageLocation instance = StorageLocation._();

  String? _customPath;

  /// macOS 沙盒用:把使用者選的資料夾以 security-scoped bookmark 持久化,
  /// 讓重啟後仍能存取(Windows 無沙盒、不需要)。
  static const MethodChannel _bookmark =
      MethodChannel('easy_clipboard/storage_bookmark');

  /// 目前的自訂路徑(null 表示用預設)。
  String? get customPath => _customPath;

  /// 只在桌面平台支援自訂。
  static bool get supported => Platform.isMacOS || Platform.isWindows;

  Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'storage_dir'));
  }

  /// 啟動時載入自訂路徑。
  ///
  /// macOS 還會用 bookmark 重新取得沙盒存取權(`startAccessingSecurityScopedResource`),
  /// bookmark 解析成功就以其回傳路徑為準;失敗(資料夾已移除/無權限)則退回預設。
  Future<void> load() async {
    try {
      final f = await _configFile();
      if (await f.exists()) {
        final s = (await f.readAsString()).trim();
        if (s.isNotEmpty) _customPath = s;
      }
    } catch (_) {
      // 讀不到就當作沒有自訂,走預設。
    }
    if (Platform.isMacOS && _customPath != null) {
      try {
        final resolved = await _bookmark.invokeMethod<String>('resolve');
        if (resolved != null && resolved.isNotEmpty) {
          _customPath = resolved;
        } else {
          _customPath = null; // 無法取得存取權,退回預設避免讀寫失敗。
        }
      } catch (_) {
        _customPath = null;
      }
    }
  }

  /// 無自訂時的預設資料夾:桌面 Downloads/EasyClipboard,其餘 appSupport。
  Future<Directory> defaultDir() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return Directory(p.join(downloads.path, 'EasyClipboard'));
      }
    }
    return getApplicationSupportDirectory();
  }

  /// 目前實際使用的資料夾(已確保建立)。
  /// 自訂路徑不可用(例如外接碟被拔除)時自動退回預設。
  Future<Directory> baseDir() async {
    Directory dir;
    if (supported && _customPath != null && _customPath!.isNotEmpty) {
      dir = Directory(_customPath!);
    } else {
      dir = await defaultDir();
    }
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      final fallback = await defaultDir();
      if (!await fallback.exists()) await fallback.create(recursive: true);
      return fallback;
    }
  }

  /// 變更儲存資料夾。傳 null 還原預設。
  ///
  /// 會把舊資料夾內的檔案(memos.json、圖片等)複製到新資料夾;新資料夾
  /// 已有同名檔則跳過、不覆蓋(memos.json 之後仍會靠區網同步合併收斂)。
  Future<void> setPath(String? path) async {
    final oldDir = await baseDir();
    _customPath = (path != null && path.isNotEmpty) ? path : null;
    final f = await _configFile();
    if (_customPath == null) {
      if (await f.exists()) await f.delete();
    } else {
      await f.writeAsString(_customPath!);
    }
    // macOS:存/清 security-scoped bookmark,讓重啟後仍能存取。
    if (Platform.isMacOS) {
      try {
        if (_customPath == null) {
          await _bookmark.invokeMethod<bool>('clear');
        } else {
          await _bookmark.invokeMethod<bool>('save', _customPath);
        }
      } catch (_) {
        // bookmark 失敗不阻擋本次設定(本次執行期間仍可存取)。
      }
    }
    final newDir = await baseDir();
    if (oldDir.path != newDir.path) {
      await _migrate(oldDir, newDir);
    }
    notifyListeners();
  }

  /// 把 [from] 內的檔案複製到 [to](不覆蓋已存在的同名檔)。
  Future<void> _migrate(Directory from, Directory to) async {
    try {
      if (!await from.exists()) return;
      await for (final entity in from.list()) {
        if (entity is! File) continue;
        final dest = File(p.join(to.path, p.basename(entity.path)));
        if (await dest.exists()) continue;
        await entity.copy(dest.path);
      }
    } catch (_) {
      // 搬移失敗不影響後續讀寫(會直接寫到新資料夾)。
    }
  }
}
