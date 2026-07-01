import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../memos/memo_store.dart';

/// 把備忘錄摘要推送到 iOS 主畫面 Widget(經 App Group 共享)。
///
/// 原生端(WidgetBridgeChannel.swift)收到後寫入
/// `UserDefaults(suiteName: "group.com.philio.syncNest")` 的 `memo_widget_data`,
/// 再呼叫 `WidgetCenter.reloadAllTimelines()` 讓 Widget 重新載入。
///
/// 僅 iOS 有效;其他平台呼叫為 no-op。監聽 [MemoStore] 的任何變動
/// (本地編輯或遠端同步合併),都會重新推一次最新內容。
class WidgetBridge {
  WidgetBridge._();
  static final WidgetBridge instance = WidgetBridge._();

  static const _channel = MethodChannel('syncnest/widget');

  MemoStore? _store;

  /// 開始監聽 [store] 並立即推一次目前內容。僅 iOS 生效。
  void attach(MemoStore store) {
    if (!Platform.isIOS) return;
    _store = store;
    store.addListener(_push);
    _push();
  }

  void _push() {
    final store = _store;
    if (store == null) return;
    // 送出完整清單:widget 各實例經 AppIntent 依 id 挑選要顯示哪一則。
    final payload = <String, dynamic>{
      'memos': store.visibleMemos.map(_summary).toList(),
    };
    _channel.invokeMethod('update', payload).catchError((Object e) {
      // Widget 不是關鍵路徑,推送失敗不影響 App。
      if (kDebugMode) debugPrint('WidgetBridge update failed: $e');
    });
  }

  /// 把一則備忘錄壓成 Widget 顯示用的欄位:id + 標題 + 待辦(文字/勾選)。
  /// 待辦順序原樣送出,由 Widget 端決定「未勾選優先」與截斷。
  Map<String, dynamic> _summary(Memo m) {
    return {
      'id': m.id,
      'title': m.text.trim().split('\n').first,
      'color': m.colorValue,
      'todos': m.todos
          .map((t) => {'text': t.text.trim(), 'done': t.done})
          .toList(),
    };
  }
}
