import 'package:flutter/foundation.dart';

/// App 內可被外部(深連結)要求切換的分頁。
///
/// 共通功能只有 [clipboard]、[memo];[alarm] 僅 feat/alarm-tab 分支有對應分頁,
/// main 分支收到 [alarm] 會被 RootPage 忽略(mapping 找不到 index)。
enum AppTab { clipboard, memo, alarm }

/// 跨層要求切換分頁的單一入口。深連結(Widget/推播/動態島)解析後呼叫 [go],
/// RootPage 監聽 [requested] 把目標映射成自己的分頁 index 後切換,再 [consume]。
class TabRouter {
  TabRouter._();
  static final TabRouter instance = TabRouter._();

  /// 最近一次被要求的分頁;null 表示無待處理請求。RootPage 處理完呼叫 [consume] 清空。
  final ValueNotifier<AppTab?> requested = ValueNotifier<AppTab?>(null);

  void go(AppTab tab) => requested.value = tab;

  void consume() => requested.value = null;
}
