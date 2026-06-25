import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../app_controller.dart';
import '../features/home_page.dart';
import 'models.dart';

/// 串接 iOS 系統分享選單(Share Extension)→ 送出流程。
///
/// 冷啟動(getInitialMedia)與執行中(getMediaStream)兩條路都接;收到內容後
/// 轉成 [SharedPayload],交給 UI 的 [runShareFlow] 自動送上次裝置或跳裝置選單。
class ShareHandler {
  final AppController controller;
  final GlobalKey<NavigatorState> navigatorKey;

  StreamSubscription<List<SharedMediaFile>>? _sub;

  ShareHandler({required this.controller, required this.navigatorKey});

  void start() {
    // App 已在執行時的分享。
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handle,
      onError: (_) {},
    );
    // App 由分享冷啟動。
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handle(files);
      ReceiveSharingIntent.instance.reset();
    });
  }

  void dispose() {
    _sub?.cancel();
  }

  Future<void> _handle(List<SharedMediaFile> files) async {
    final payloads = <SharedPayload>[];
    for (final f in files) {
      switch (f.type) {
        case SharedMediaType.image:
          payloads.add(SharedPayload(SharedKind.image, f.path));
        case SharedMediaType.url:
          payloads.add(SharedPayload(SharedKind.url, f.path));
        case SharedMediaType.text:
          payloads.add(SharedPayload(SharedKind.text, f.path));
        case SharedMediaType.video:
        case SharedMediaType.file:
          // 目前不接受影片/任意檔的分享。
          break;
      }
    }
    if (payloads.isEmpty) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    await runShareFlow(ctx, controller, payloads);
  }
}
