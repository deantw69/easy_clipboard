import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  Timer? _refreshTimer;

  List<DeviceInfo> devices = [];
  final List<ReceivedItem> received = [];
  String? status;
  bool ready = false;

  /// 收到圖片時由 UI 設定:跳出預覽,讓接收方決定要複製到剪貼簿或儲存。
  Future<void> Function(ReceivedItem item)? onImageReceived;

  /// 收到網址時由 UI 設定:詢問是否在瀏覽器開啟。
  Future<void> Function(String url)? onUrlReceived;

  /// 上次傳送的目標裝置 id(持久化),分享時優先自動送到這台。
  String? _lastTargetId;
  String? get lastTargetId => _lastTargetId;

  DeviceInfo? get local => _local;
  bool get isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  Future<void> init() async {
    _lastTargetId = await _loadLastTarget();
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

    // 桌面端定時重新掃描,解決 iOS 切背景再回來後找不到的問題。
    if (isDesktop) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _discovery.refresh(),
      );
    }

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

  /// 手動觸發 mDNS 重新掃描（從系統匣還原視窗時使用）。
  void refreshDiscovery() {
    if (ready) _discovery.refresh();
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
    if (env.kind == PayloadKind.url) {
      // 網址:寫入清單並交給 UI 詢問是否在瀏覽器開啟。
      received.insert(0, item);
      notifyListeners();
      if (item.text != null) await onUrlReceived?.call(item.text!);
      return;
    } else if (env.kind == PayloadKind.clipboardText) {
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

  // ---- 系統分享選單(iOS Share Extension) ----

  /// 把一筆從系統分享進來的內容送到 [target],成功後記住此目標裝置。
  Future<void> sendShared(DeviceInfo target, SharedPayload payload) async {
    switch (payload.kind) {
      case SharedKind.image:
        await _transport!
            .sendFile(target, payload.value, mime: _guessImageMime(payload.value));
        _setStatus('已傳送圖片到 ${target.name}');
      case SharedKind.text:
        await _transport!.sendClipboardText(target, payload.value);
        _setStatus('已傳送文字到 ${target.name}');
      case SharedKind.url:
        await _transport!.sendUrl(target, payload.value);
        _setStatus('已傳送網址到 ${target.name}');
    }
    await _saveLastTarget(target.id);
  }

  /// 嘗試解析「上次傳送的目標裝置」。剛從分享冷啟動時 mDNS 尚未掃到裝置,
  /// 因此在 [timeout] 內輪詢等待該裝置出現且可連線;逾時回傳 null,由 UI 跳選單。
  Future<DeviceInfo?> resolveLastTarget(
      {Duration timeout = const Duration(seconds: 6)}) async {
    final id = _lastTargetId;
    if (id == null) return null;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      for (final d in devices) {
        if (d.id == id && d.isReachable) return d;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  String? _guessImageMime(String path) {
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'heic': 'image/heic',
      'heif': 'image/heif',
      'webp': 'image/webp',
    };
    return map[p.extension(path).replaceFirst('.', '').toLowerCase()];
  }

  Future<File> _lastTargetFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'last_target'));
  }

  Future<String?> _loadLastTarget() async {
    try {
      final f = await _lastTargetFile();
      if (await f.exists()) {
        final s = (await f.readAsString()).trim();
        if (s.isNotEmpty) return s;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _saveLastTarget(String id) async {
    _lastTargetId = id;
    try {
      await (await _lastTargetFile()).writeAsString(id);
    } catch (_) {}
  }

  /// 清除收到的內容:刪除已落地的暫存檔並清空清單,釋放裝置容量。
  ///
  /// 除了清單裡記錄的 [ReceivedItem.savedPath],也順手掃描整個接收目錄,
  /// 把之前啟動殘留、已不在清單中的檔案一併刪掉。
  Future<void> clearReceived() async {
    for (final item in received) {
      final path = item.savedPath;
      if (path == null) continue;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {
        // 單檔刪除失敗不影響其餘清理。
      }
    }
    var count = received.length;
    try {
      final dir = await LanTransport.receivedDir();
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            try {
              await entity.delete();
              count++;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    received.clear();
    _setStatus(count > 0 ? '已清除收到的內容' : '沒有可清除的內容');
    notifyListeners();
  }

  void _setStatus(String s) {
    status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _discovery.stop();
    _transport?.stop();
    super.dispose();
  }
}
