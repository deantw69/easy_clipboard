import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tab_router.dart';

/// 串接原生深連結(自訂 scheme `syncnest://`)→ 分頁切換。
///
/// 原生端(ios/Runner/DeepLinkChannel.swift)收到 `syncnest://memo` /
/// `syncnest://alarm` 後:執行中經 MethodChannel `route` 即時推來 host;
/// 冷啟動則先暫存,本服務 [start] 時呼叫 `getInitial` 取回。
/// host → [AppTab] 後交給 [TabRouter]。僅 iOS 生效,其他平台為 no-op。
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  static const _channel = MethodChannel('syncnest/deeplink');

  void start() {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'route') {
        _route(call.arguments as String?);
      }
    });
    // 冷啟動:取回啟動前暫存的深連結。
    _channel.invokeMethod<String>('getInitial').then(_route).catchError((Object e) {
      if (kDebugMode) debugPrint('DeepLink getInitial failed: $e');
    });
  }

  void _route(String? host) {
    switch (host) {
      case 'memo':
        TabRouter.instance.go(AppTab.memo);
      case 'alarm':
        TabRouter.instance.go(AppTab.alarm);
    }
  }
}
