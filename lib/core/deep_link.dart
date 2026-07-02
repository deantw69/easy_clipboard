import 'dart:io';

import 'package:flutter/services.dart';

import 'tab_router.dart';

/// 串接深連結(自訂 scheme `syncnest://`)→ 分頁切換。
///
/// 接收改由**原生 SceneDelegate 覆寫**(`ios/Runner/SceneDelegate.swift` +
/// `DeepLinkChannel.swift`)處理:app_links 在本 App 的 implicit-engine +
/// `FlutterSceneDelegate` 架構下抓不到「冷啟動」與 Live Activity 的 URL(只實作了執行中的
/// `application:openURL:`)。改在 SceneDelegate 覆寫 `scene(_:willConnectTo:)`(冷啟動)/
/// `scene(_:openURLContexts:)`(執行中)取 URL,經 MethodChannel 送上來。
///
/// - 執行中:原生經 method `onLink` 推 URL 上來。
/// - 冷啟動:原生存起來,`start()` 時以 method `getInitialLink` 取回。
///
/// URL host(`memo`/`alarm`)→ [AppTab] 交給 [TabRouter]。僅 iOS 生效。
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  static const MethodChannel _channel = MethodChannel('syncnest/deep_link');

  Future<void> start() async {
    if (!Platform.isIOS) return;
    // 執行中收到的深連結(widget / Live Activity / 動態島 tap)。
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink' && call.arguments is String) {
        _route(Uri.parse(call.arguments as String));
      }
    });
    // App 由深連結冷啟動時的初始 URL。
    try {
      final initial = await _channel.invokeMethod<String>('getInitialLink');
      if (initial != null) _route(Uri.parse(initial));
    } catch (_) {
      // 取不到初始連結時忽略(非冷啟動或無 URL)。
    }
  }

  void _route(Uri uri) {
    switch (uri.host) {
      case 'memo':
        TabRouter.instance.go(AppTab.memo);
      case 'alarm':
        TabRouter.instance.go(AppTab.alarm);
    }
  }
}
