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

  /// 網址的顯示名稱(選填);僅在備忘錄為固定模式且 [text] 是網址時使用,
  /// 有值時卡片顯示此名稱作為超連結文字,空/null 則顯示網址本身。
  String? label;

  MemoTodo({required this.id, this.text = '', this.done = false, this.label});

  factory MemoTodo.create({String text = ''}) =>
      MemoTodo(id: const Uuid().v4(), text: text);

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'done': done,
    'label': label,
  };

  factory MemoTodo.fromJson(Map<String, dynamic> j) => MemoTodo(
    id: j['id'] as String,
    text: (j['text'] as String?) ?? '',
    done: (j['done'] as bool?) ?? false,
    label: j['label'] as String?,
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

  /// 固定模式:待辦不顯示完成勾勾/刪除線(當純清單),
  /// 且網址待辦可設 [MemoTodo.label] 顯示成具名超連結。預設 false。
  bool fixed;

  Memo({
    required this.id,
    this.text = '',
    List<MemoTodo>? todos,
    required this.updatedAt,
    this.deleted = false,
    this.colorValue,
    this.sortKey = 0,
    this.fixed = false,
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
    'fixed': fixed,
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
    fixed: (j['fixed'] as bool?) ?? false,
  );
}

/// 備忘錄的本地儲存與跨裝置合併。
///
/// 持久化沿用既有「檔案存 appSupport」的 pattern(同 identity / last_target),
/// 不引入資料庫依賴。本地任何變動會寫檔、通知 UI,並透過 [onLocalChange]
/// 通知上層立即向區網其他裝置推送。
class MemoStore extends ChangeNotifier {
  final List<Memo> _memos = [];

  /// 墓碑(`deleted=true`)保留天數:超過此天數的墓碑會在 load / merge 時清除,
  /// 避免 memos.json 無限長大、同步整包越傳越慢。
  ///
  /// 30 天遠大於裝置最長離線間隔:只要所有裝置在 30 天內至少同步過一次,
  /// 墓碑就已在各機生效,清掉不會讓被刪的資料復活;若真有裝置離線超過 30 天
  /// 才回來,其舊資料可能復活——這是刻意取捨(離線越久越罕見)。
  static const int _tombstoneTtlDays = 30;

  /// 本地內容變動時的回呼(AppController 用來觸發即時同步推送)。
  VoidCallback? onLocalChange;

  /// 載入時偵測到資料異常的提示訊息(供 UI 顯示一次性通知);正常為 null。
  /// - memos.json 解析失敗、改用 .bak 還原成功 → 說明已從備份還原。
  /// - 主檔與備份都無法解析 → 說明資料損毀、以空清單啟動(但不覆蓋損毀檔,保留人工搶救機會)。
  final ValueNotifier<String?> loadWarning = ValueNotifier<String?>(null);

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
  /// 桌面(macOS / Windows)改存「使用者下載資料夾下的 syncnest/」,
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
  ///
  /// 損毀防護:先讀主檔 `memos.json`,解析失敗(半寫/外部程式弄壞)再退回
  /// 上一份 known-good 的 `memos.json.bak`;兩者皆無法解析才以空清單啟動,
  /// 並保留損毀主檔(不覆寫)、透過 [loadWarning] 通知 UI,避免資料無聲消失。
  Future<void> load() async {
    await _migrateFromAppSupport();
    final f = await _file();
    final fileExists = await f.exists();
    if (await _tryLoadFrom(f)) {
      // 主檔正常。
    } else if (await _tryLoadFrom(File('${f.path}.bak'))) {
      // 主檔壞了但備份還在:還原並立刻用備份內容重寫主檔(_save 會再滾出新 .bak)。
      loadWarning.value = '備忘錄主檔損毀,已自動從備份還原。';
      await _save();
    } else if (fileExists) {
      // 主檔存在但主檔與備份都無法解析:以空清單啟動,但不覆寫損毀主檔(保留搶救機會)。
      _memos.clear();
      loadWarning.value = '備忘錄資料損毀且無可用備份,已以空清單啟動;'
          '原始檔案未被覆寫,可從其他裝置同步回或手動搶救。';
    }
    // 清掉過期墓碑,順手把縮小後的清單寫回(僅在成功載入且有變動時)。
    if (loadWarning.value == null && _gcTombstones()) await _save();
    notifyListeners();
  }

  /// 嘗試從 [f] 載入並填入 `_memos`;成功(含合法空檔)回 true,不存在/解析失敗回 false。
  /// 失敗時不動 `_memos`,交由呼叫端決定後續退路。
  Future<bool> _tryLoadFrom(File f) async {
    try {
      if (!await f.exists()) return false;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) {
        _memos.clear();
        return true; // 合法的空清單。
      }
      final decoded = _decode(raw);
      _memos
        ..clear()
        ..addAll(decoded);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 原子寫入:先寫 `.tmp`(flush 落地)→ 把現有主檔滾成 `.bak`(視為上次 known-good)
  /// → 再把 `.tmp` 更名為主檔。任一步崩潰都不會留下半寫的 `memos.json`
  /// (要嘛主檔完好、要嘛 .bak 完好、要嘛 .tmp 完好),載入端可逐級退回。
  Future<void> _save() async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(exportJson(), flush: true);
      if (await f.exists()) {
        final bak = File('${f.path}.bak');
        try {
          if (await bak.exists()) await bak.delete();
        } catch (_) {}
        // 主檔更名成 .bak;更名走掉後主檔位置已空,下一步 tmp 更名不會撞既有檔(Windows 相容)。
        try {
          await f.rename(bak.path);
        } catch (_) {
          try {
            await f.copy(bak.path);
          } catch (_) {}
        }
      }
      try {
        await tmp.rename(f.path);
      } catch (_) {
        // 更名失敗退回複製,並清掉殘留 tmp。
        await tmp.copy(f.path);
        try {
          await tmp.delete();
        } catch (_) {}
      }
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
    memo.updatedAt = _monotonicNow(); // 保證新建時間戳不小於本機已知最大值。
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
      _touch(memo);
      changed = true;
    }
    if (changed) _commit();
  }

  /// 套用對某則備忘錄的修改([mutate] 內直接改 memo 欄位),自動 touch。
  void update(String id, void Function(Memo memo) mutate) {
    final memo = _byId(id);
    if (memo == null) return;
    mutate(memo);
    _touch(memo);
    _commit();
  }

  void toggleTodo(String memoId, String todoId) {
    final memo = _byId(memoId);
    if (memo == null) return;
    final idx = memo.todos.indexWhere((t) => t.id == todoId);
    if (idx < 0) return;
    memo.todos[idx].done = !memo.todos[idx].done;
    _touch(memo);
    _commit();
  }

  void delete(String id) {
    final memo = _byId(id);
    if (memo == null) return;
    memo.deleted = true;
    _touch(memo);
    _commit();
  }

  /// 復原剛刪除的備忘錄(取消墓碑);touch 讓復原帶較新時間戳,
  /// 在 LWW 合併時贏過先前同步出去的墓碑。
  void restore(String id) {
    final memo = _byId(id);
    if (memo == null || !memo.deleted) return;
    memo.deleted = false;
    _touch(memo);
    _commit();
  }

  /// 清除過期墓碑:移除 `deleted=true` 且 updatedAt 超過 [_tombstoneTtlDays] 天的記錄。
  /// 回傳是否有移除(供呼叫端決定是否寫檔)。不寫檔、不通知,由呼叫端統一收尾。
  bool _gcTombstones() {
    final cutoff = DateTime.now()
        .subtract(const Duration(days: _tombstoneTtlDays))
        .millisecondsSinceEpoch;
    final before = _memos.length;
    _memos.removeWhere((m) => m.deleted && m.updatedAt < cutoff);
    return _memos.length != before;
  }

  Memo? _byId(String id) {
    final idx = _memos.indexWhere((m) => m.id == id);
    return idx < 0 ? null : _memos[idx];
  }

  /// 單調遞增的時間戳:取 `max(現在, 本機已知最大 updatedAt + 1)`。
  ///
  /// LWW 全靠各機 `DateTime.now()`,若本機時鐘曾被調快、之後又調回(或本來就比
  /// 其他裝置快),直接用 now 可能產生「比自己既有資料還舊」的時間戳,導致新編輯
  /// 被舊資料蓋掉。保證不小於自身最大值可避免本機自我倒退(不動協定、向後相容)。
  int _monotonicNow() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var maxSeen = 0;
    for (final m in _memos) {
      if (m.updatedAt > maxSeen) maxSeen = m.updatedAt;
    }
    return now > maxSeen ? now : maxSeen + 1;
  }

  /// 以單調遞增時間戳更新 [m](取代 `Memo.touch()`,確保本機時間戳不倒退)。
  void _touch(Memo m) => m.updatedAt = _monotonicNow();

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

  String exportJson() => jsonEncode(_memos.map((m) => m.toJson()).toList());

  static List<Memo> _decode(String raw) => (jsonDecode(raw) as List)
      .map((e) => Memo.fromJson(e as Map<String, dynamic>))
      .toList();

  /// 合併對方傳來的完整清單(Last-Write-Wins),寫檔並通知 UI,
  /// 回傳本機合併後的完整 JSON 供同步端點回應。
  ///
  /// 注意:合併進來的是「遠端的變更」,不應再回呼 [onLocalChange](否則
  /// 兩台會無限互推);此處只寫檔 + notifyListeners。
  /// 手動匯入外部備份 JSON:與 [mergeJson] 同樣走 LWW 合併(不覆蓋較新的本機資料),
  /// 但這是使用者主動的本地操作,合併後走 [_commit] 觸發 [onLocalChange] 推送到其他裝置。
  /// 回傳新增/更新的筆數;JSON 格式錯誤回傳 -1。
  int importJson(String incoming) {
    try {
      final remote = _decode(incoming);
      final byId = {for (final m in _memos) m.id: m};
      var applied = 0;
      for (final r in remote) {
        final local = byId[r.id];
        if (local == null || r.updatedAt > local.updatedAt) {
          byId[r.id] = r;
          applied++;
        }
      }
      if (applied > 0) {
        _memos
          ..clear()
          ..addAll(byId.values);
        _gcTombstones();
        _commit();
      }
      return applied;
    } catch (_) {
      return -1;
    }
  }

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
        _gcTombstones();
        _save();
        notifyListeners();
      }
    } catch (_) {
      // 解析失敗忽略,仍回傳本機現況。
    }
    return exportJson();
  }
}
