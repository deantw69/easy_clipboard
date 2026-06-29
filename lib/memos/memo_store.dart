import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/storage_location.dart';

/// 備忘錄裡的一筆待辦項目。
class MemoTodo {
  final String id;
  String text;
  bool done;

  MemoTodo({required this.id, this.text = '', this.done = false});

  factory MemoTodo.create({String text = ''}) =>
      MemoTodo(id: const Uuid().v4(), text: text);

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};

  factory MemoTodo.fromJson(Map<String, dynamic> j) => MemoTodo(
        id: j['id'] as String,
        text: (j['text'] as String?) ?? '',
        done: (j['done'] as bool?) ?? false,
      );
}

/// 一則備忘錄(便利貼)。
///
/// [updatedAt] 為 epoch 毫秒,作為跨裝置合併的 Last-Write-Wins 依據;
/// [deleted] 為墓碑標記,刪除後仍保留此記錄,避免被舊資料復活。
class Memo {
  final String id;
  String text;
  List<MemoTodo> todos;
  int updatedAt;
  bool deleted;

  /// 便利貼底色(ARGB int);null 表示用預設黃。
  int? colorValue;

  /// 列表排序鍵(升冪,小者在上);拖曳排序時改寫。預設 0。
  int sortKey;

  Memo({
    required this.id,
    this.text = '',
    List<MemoTodo>? todos,
    required this.updatedAt,
    this.deleted = false,
    this.colorValue,
    this.sortKey = 0,
  }) : todos = todos ?? [];

  factory Memo.create({String text = ''}) => Memo(
        id: const Uuid().v4(),
        text: text,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  /// 更新內容後呼叫,刷新 updatedAt(同步合併依此判斷新舊)。
  void touch() => updatedAt = DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'todos': todos.map((t) => t.toJson()).toList(),
        'updatedAt': updatedAt,
        'deleted': deleted,
        'colorValue': colorValue,
        'sortKey': sortKey,
      };

  factory Memo.fromJson(Map<String, dynamic> j) => Memo(
        id: j['id'] as String,
        text: (j['text'] as String?) ?? '',
        todos: ((j['todos'] as List?) ?? [])
            .map((e) => MemoTodo.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        deleted: (j['deleted'] as bool?) ?? false,
        colorValue: (j['colorValue'] as num?)?.toInt(),
        sortKey: (j['sortKey'] as num?)?.toInt() ?? 0,
      );
}

/// 備忘錄的本地儲存與跨裝置合併。
///
/// 持久化沿用既有「檔案存 appSupport」的 pattern(同 identity / last_target),
/// 不引入資料庫依賴。本地任何變動會寫檔、通知 UI,並透過 [onLocalChange]
/// 通知上層立即向區網其他裝置推送。
class MemoStore extends ChangeNotifier {
  final List<Memo> _memos = [];

  /// 本地內容變動時的回呼(AppController 用來觸發即時同步推送)。
  VoidCallback? onLocalChange;

  /// 對 UI 顯示用:過濾墓碑,先依 sortKey 升冪(拖曳排序),
  /// sortKey 相同(如尚未排序過的舊資料)再依 updatedAt 新到舊。
  List<Memo> get visibleMemos {
    final list = _memos.where((m) => !m.deleted).toList();
    list.sort((a, b) {
      final c = a.sortKey.compareTo(b.sortKey);
      return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  /// 備忘錄資料夾。
  ///
  /// 桌面(macOS / Windows)改存「使用者下載資料夾下的 easy_clipboard/」,
  /// 而非 appSupport——後者在 macOS 是沙盒 Container,重裝 App 會被清掉。
  /// macOS entitlement 已開 `files.downloads.read-write`,故沙盒下可寫入 Downloads。
  /// iOS 等其他平台維持 appSupport(重裝必清,改位置也救不了,靠雲端/區網同步補回)。
  Future<Directory> _dataDir() => StorageLocation.instance.baseDir();

  Future<File> _file() async {
    final dir = await _dataDir();
    return File(p.join(dir.path, 'memos.json'));
  }

  /// 把舊版存在 appSupport 的 memos.json 搬到新位置(只搬一次)。
  /// 新位置已有檔案就跳過,避免覆蓋。
  Future<void> _migrateFromAppSupport() async {
    try {
      if (!(Platform.isMacOS || Platform.isWindows)) return;
      final newFile = await _file();
      if (await newFile.exists()) return;
      final oldDir = await getApplicationSupportDirectory();
      final oldFile = File(p.join(oldDir.path, 'memos.json'));
      if (await oldFile.exists()) {
        await newFile.writeAsString(await oldFile.readAsString());
      }
    } catch (_) {
      // 搬移失敗不阻擋啟動,當作新裝置從空清單開始。
    }
  }

  /// 啟動時載入。
  Future<void> load() async {
    await _migrateFromAppSupport();
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = await f.readAsString();
        if (raw.trim().isNotEmpty) {
          _memos
            ..clear()
            ..addAll(_decode(raw));
        }
      }
    } catch (_) {
      // 讀取/解析失敗時以空清單啟動,不阻擋 App。
    }
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await (await _file()).writeAsString(exportJson());
    } catch (_) {}
  }

  /// 本地變動的共同收尾:寫檔、通知 UI、觸發推送。
  void _commit() {
    _save();
    notifyListeners();
    onLocalChange?.call();
  }

  // ---- 本地 CRUD ----

  Memo add({String text = ''}) {
    final memo = Memo.create(text: text);
    // 置頂:取目前非刪除 memo 的最小 sortKey 再減 1。
    final minKey = _memos
        .where((m) => !m.deleted)
        .fold<int>(0, (min, m) => m.sortKey < min ? m.sortKey : min);
    memo.sortKey = minKey - 1;
    _memos.insert(0, memo);
    _commit();
    return memo;
  }

  /// 依使用者拖曳後的新順序([orderedIds] 為可見 memo 由上到下的 id),
  /// 重新指派 sortKey;有變動的 touch() 以同步到其他裝置,只 commit 一次。
  void reorder(List<String> orderedIds) {
    var changed = false;
    for (var i = 0; i < orderedIds.length; i++) {
      final memo = _byId(orderedIds[i]);
      if (memo == null || memo.sortKey == i) continue;
      memo.sortKey = i;
      memo.touch();
      changed = true;
    }
    if (changed) _commit();
  }

  /// 套用對某則備忘錄的修改([mutate] 內直接改 memo 欄位),自動 touch。
  void update(String id, void Function(Memo memo) mutate) {
    final memo = _byId(id);
    if (memo == null) return;
    mutate(memo);
    memo.touch();
    _commit();
  }

  void toggleTodo(String memoId, String todoId) {
    final memo = _byId(memoId);
    if (memo == null) return;
    final idx = memo.todos.indexWhere((t) => t.id == todoId);
    if (idx < 0) return;
    memo.todos[idx].done = !memo.todos[idx].done;
    memo.touch();
    _commit();
  }

  void delete(String id) {
    final memo = _byId(id);
    if (memo == null) return;
    memo.deleted = true;
    memo.touch();
    _commit();
  }

  Memo? _byId(String id) {
    final idx = _memos.indexWhere((m) => m.id == id);
    return idx < 0 ? null : _memos[idx];
  }

  /// 清空本機所有備忘錄(連墓碑一併移除),寫入空清單。
  ///
  /// 供「重設並從其他裝置重新拉取」使用:清空後本機**不帶任何墓碑或時間戳**,
  /// 因此隨後的同步只會從對端「拉回」資料,而不會把本機被污染的舊狀態推回去
  /// (墓碑帶新時間戳會反向覆蓋對端,空清單則完全不參與 LWW)。
  ///
  /// 刻意**不呼叫** [onLocalChange]:一來避免把清空當成本地變更而觸發推送,
  /// 二來空清單即使被推出,對端 [mergeJson] 也不會刪掉任何資料,無副作用。
  Future<void> clearLocal() async {
    _memos.clear();
    await _save();
    notifyListeners();
  }

  // ---- 同步 ----

  String exportJson() =>
      jsonEncode(_memos.map((m) => m.toJson()).toList());

  static List<Memo> _decode(String raw) => (jsonDecode(raw) as List)
      .map((e) => Memo.fromJson(e as Map<String, dynamic>))
      .toList();

  /// 合併對方傳來的完整清單(Last-Write-Wins),寫檔並通知 UI,
  /// 回傳本機合併後的完整 JSON 供同步端點回應。
  ///
  /// 注意:合併進來的是「遠端的變更」,不應再回呼 [onLocalChange](否則
  /// 兩台會無限互推);此處只寫檔 + notifyListeners。
  String mergeJson(String incoming) {
    try {
      final remote = _decode(incoming);
      final byId = {for (final m in _memos) m.id: m};
      var changed = false;
      for (final r in remote) {
        final local = byId[r.id];
        if (local == null || r.updatedAt > local.updatedAt) {
          byId[r.id] = r;
          changed = true;
        }
      }
      if (changed) {
        _memos
          ..clear()
          ..addAll(byId.values);
        _save();
        notifyListeners();
      }
    } catch (_) {
      // 解析失敗忽略,仍回傳本機現況。
    }
    return exportJson();
  }
}
