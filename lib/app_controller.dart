import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';

import 'clipboard/clipboard_service.dart';
import 'core/identity.dart';
import 'core/models.dart';
import 'discovery/discovery.dart';
import 'discovery/nsd_discovery.dart';
import 'transport/lan_transport.dart';
import 'transport/transport.dart';

/// App 的中央狀態與服務協調者。把身分、發現、傳輸、剪貼簿串起來。
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  final DiscoveryService _discovery = NsdDiscovery();
  final ClipboardService clipboard = ClipboardService();

  Transport? _transport;
  DeviceInfo? _local;

  List<DeviceInfo> devices = [];
  final List<ReceivedItem> received = [];
  String? status;
  bool ready = false;

  /// 收到圖片時由 UI 設定:跳出預覽,讓接收方決定要複製到剪貼簿或儲存。
  Future<void> Function(ReceivedItem item)? onImageReceived;

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

    WidgetsBinding.instance.addObserver(this);

    ready = true;
    notifyListeners();
  }

  /// App 回到前景時重發通告並重啟探索。
  ///
  /// 解決 mDNS 單向探索失效:iOS 進背景會停止回應查詢,對端(尤其 macOS 的被動
  /// 探索)會抓不到本機;回前景重新 register/discovery 可讓雙方重新看到彼此。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ready) {
      _discovery.refresh();
    }
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
    final env = item.envelope;
    if (env.kind == PayloadKind.clipboardText) {
      if (item.text != null) await clipboard.writeText(item.text!);
    } else if (_isImage(env)) {
      // 圖片一律交給接收方決定:跳預覽,選複製到剪貼簿或儲存。
      received.insert(0, item);
      notifyListeners();
      await onImageReceived?.call(item);
      return;
    } else {
      await _maybeSaveToGallery(item); // 影片等其他檔
    }
    received.insert(0, item);
    notifyListeners();
  }

  bool _isImage(TransferEnvelope env) {
    if (env.kind == PayloadKind.clipboardImage) return true;
    return env.kind == PayloadKind.file &&
        (env.mime?.startsWith('image/') ?? false);
  }

  /// 接收方:把收到的圖片複製到本機剪貼簿。
  Future<void> copyReceivedImage(ReceivedItem item) async {
    final path = item.savedPath;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    await clipboard.writeImagePng(bytes);
    _setStatus('已複製圖片到剪貼簿');
  }

  /// 接收方(行動裝置):把收到的圖片存進系統相簿。
  Future<void> saveReceivedImageToGallery(ReceivedItem item) async {
    final path = item.savedPath;
    if (path == null) return;
    try {
      await Gal.putImage(path);
      _setStatus('已存入相簿');
    } on GalException catch (e) {
      _setStatus('存入相簿失敗:${e.type.message}');
    }
  }

  /// 接收方(桌面):在檔案總管 / Finder 中顯示收到的檔案。
  Future<void> revealReceivedImage(ReceivedItem item) async {
    final path = item.savedPath;
    if (path == null) return;
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
    _setStatus('已在檔案總管顯示');
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
    WidgetsBinding.instance.removeObserver(this);
    _discovery.stop();
    _transport?.stop();
    super.dispose();
  }
}
