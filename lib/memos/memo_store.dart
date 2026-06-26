import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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

  Memo({
    required this.id,
    this.text = '',
    List<MemoTodo>? todos,
    required this.updatedAt,
    this.deleted = false,
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
      };

  factory Memo.fromJson(Map<String, dynamic> j) => Memo(
        id: j['id'] as String,
        text: (j['text'] as String?) ?? '',
        todos: ((j['todos'] as List?) ?? [])
            .map((e) => MemoTodo.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
        deleted: (j['deleted'] as bool?) ?? false,
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

  /// 對 UI 顯示用:過濾墓碑,依更新時間新到舊排序。
  List<Memo> get visibleMemos {
    final list = _memos.where((m) => !m.deleted).toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'memos.json'));
  }

  /// 啟動時載入。
  Future<void> load() async {
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
    _memos.insert(0, memo);
    _commit();
    return memo;
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
