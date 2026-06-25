import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

import 'clipboard/clipboard_service.dart';
import 'core/identity.dart';
import 'core/models.dart';
import 'discovery/discovery.dart';
import 'discovery/nsd_discovery.dart';
import 'transport/lan_transport.dart';
import 'transport/transport.dart';

/// App 的中央狀態與服務協調者。把身分、發現、傳輸、剪貼簿串起來。
class AppController extends ChangeNotifier {
  final DiscoveryService _discovery = NsdDiscovery();
  final ClipboardService clipboard = ClipboardService();

  Transport? _transport;
  DeviceInfo? _local;

  List<DeviceInfo> devices = [];
  final List<ReceivedItem> received = [];
  String? status;
  bool ready = false;

  DeviceInfo? get local => _local;
  bool get isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<void> init() async {
    final identity = await Identity.load();
    final port = await _bindTransport(identity);
    _local = DeviceInfo.local(
      id: identity.deviceId,
      name: identity.deviceName,
      port: port,
    );

    await _discovery.register(_local!);
    await _discovery.start((list) {
      devices = list;
      notifyListeners();
    });

    ready = true;
    notifyListeners();
  }

  /// 嘗試在一段埠範圍內啟動接收端,回傳實際使用的埠。
  Future<int> _bindTransport(Identity identity) async {
    for (var port = 53318; port < 53338; port++) {
      try {
        final t = LanTransport(port: port);
        // 先用占位本機資訊啟動,稍後 init 會建立正式 _local。
        await t.start(
          DeviceInfo.local(
              id: identity.deviceId, name: identity.deviceName, port: port),
          _onReceived,
        );
        _transport = t;
        return port;
      } on SocketException {
        continue;
      }
    }
    throw StateError('找不到可用的埠來啟動接收端');
  }

  Future<void> _onReceived(ReceivedItem item) async {
    switch (item.envelope.kind) {
      case PayloadKind.clipboardText:
        if (item.text != null) await clipboard.writeText(item.text!);
        break;
      case PayloadKind.clipboardImage:
        if (item.savedPath != null) {
          final bytes = await File(item.savedPath!).readAsBytes();
          await clipboard.writeImagePng(bytes);
        }
        break;
      case PayloadKind.file:
        await _maybeSaveToGallery(item);
        break;
    }
    received.insert(0, item);
    notifyListeners();
  }

  /// iOS:收到的圖片 / 影片直接存進系統相簿,而非只留在 App 目錄。
  Future<void> _maybeSaveToGallery(ReceivedItem item) async {
    if (!Platform.isIOS) return;
    final path = item.savedPath;
    final mime = item.envelope.mime ?? '';
    if (path == null) return;
    try {
      if (mime.startsWith('image/')) {
        await Gal.putImage(path);
        _setStatus('已存入相簿:${item.envelope.fileName ?? '圖片'}');
      } else if (mime.startsWith('video/')) {
        await Gal.putVideo(path);
        _setStatus('已存入相簿:${item.envelope.fileName ?? '影片'}');
      }
    } on GalException catch (e) {
      _setStatus('存入相簿失敗:${e.type.message}');
    }
  }

  // ---- 對 UI 的操作 ----

  Future<void> sendFile(DeviceInfo target, String path,
      {String? mime, void Function(double)? onProgress}) async {
    await _transport!
        .sendFile(target, path, mime: mime, onProgress: onProgress);
    _setStatus('已傳送檔案到 ${target.name}');
  }

  Future<void> sendClipboard(DeviceInfo target) async {
    final png = await clipboard.readImagePng();
    if (png != null) {
      await _transport!.sendClipboardImage(target, png);
      _setStatus('已傳送剪貼簿圖片到 ${target.name}');
      return;
    }
    final text = await clipboard.readText();
    if (text != null && text.isNotEmpty) {
      await _transport!.sendClipboardText(target, text);
      _setStatus('已傳送剪貼簿文字到 ${target.name}');
      return;
    }
    _setStatus('剪貼簿沒有可傳送的內容');
  }

  void _setStatus(String s) {
    status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _discovery.stop();
    _transport?.stop();
    super.dispose();
  }
}
