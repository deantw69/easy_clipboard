import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'clipboard/clipboard_service.dart';
import 'core/identity.dart';
import 'core/models.dart';
import 'core/widget_bridge.dart';
import 'discovery/discovery.dart';
import 'discovery/nsd_discovery.dart';
import 'memos/memo_store.dart';
import 'transport/lan_transport.dart';
import 'transport/transport.dart';

/// App 的中央狀態與服務協調者。把身分、發現、傳輸、剪貼簿串起來。
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  final DiscoveryService _discovery = NsdDiscovery();
  final ClipboardService clipboard = ClipboardService();

  /// 備忘錄資料層(由 main 的 MultiProvider 建立後注入)。
  final MemoStore memos;

  AppController({required this.memos});

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
      groupCode: identity.groupCode,
    );
    // transport 啟動時用的是占位資訊(空群組碼),補上正式群組碼供 server 比對。
    _transport!.updateLocal(_local!);
    _transport!.onClockSkew = _onClockSkew;

    await _discovery.register(_local!);
    await _discovery.start((list) {
      devices = list;
      notifyListeners();
      // 有裝置出現/變動時,順手同步備忘錄。
      syncMemosWithAll();
    });

    // 本地備忘錄變動時,立即推送到區網其他裝置。
    memos.onLocalChange = () => syncMemosWithAll();

    // iOS:任何備忘錄變動(本地或遠端合併)都同步一份摘要給主畫面 Widget。
    WidgetBridge.instance.attach(memos);

    WidgetsBinding.instance.addObserver(this);

    // 桌面端定時重新掃描,解決 iOS 切背景再回來後找不到的問題。
    if (isDesktop) {
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) {
          _discovery.refresh();
          syncMemosWithAll();
        },
      );
    }

    ready = true;
    notifyListeners();
  }

  // ---- 備忘錄同步 ----

  bool _syncing = false;

  /// 時鐘偏移門檻:與對端系統時間相差超過此值時提示使用者校時
  /// (LWW 全靠各機 `DateTime.now()`,時鐘偏差會讓新編輯被舊資料覆蓋)。
  static const _clockSkewThreshold = Duration(minutes: 2);

  DateTime? _lastMemoSyncAt;
  bool _memoSyncFailing = false;
  int _memoSyncFailStreak = 0;

  /// 連續整批失敗達此次數才判定 [memoSyncFailing](避免切前景/改群組碼瞬間/
  /// 對端短暫忙碌造成的單次瞬時失敗就亮警示);任一次成功立即歸零清除。
  static const _memoSyncFailThreshold = 3;
  Duration? _clockSkew;

  /// 上次成功同步備忘錄的時間(任一裝置成功即更新);從未成功為 null。
  DateTime? get lastMemoSyncAt => _lastMemoSyncAt;

  /// 最近一次同步:有可同步的裝置(同群組且可連線)卻全部失敗。
  bool get memoSyncFailing => _memoSyncFailing;

  /// 與對端系統時鐘的偏移(對端時間 - 本機時間);未超過門檻為 null。
  Duration? get clockSkew => _clockSkew;

  /// 與目前可連線的所有裝置同步備忘錄(Last-Write-Wins)。
  ///
  /// 單一往返:送出本機完整清單,對方合併後回傳其清單,本機再合併。
  /// 加 [_syncing] 旗標去抖,避免多個觸發點短時間內重複跑;離線/逾時忽略。
  ///
  /// 同步結果供 UI 顯示:連續整批失敗達 [_memoSyncFailThreshold] 次才把
  /// [memoSyncFailing] 置真(任一次成功立即歸零),讓使用者知道兩台其實早已
  /// 沒在同步,又不會被切前景/改群組碼瞬間的單次瞬時失敗誤報(過去這裡全吞例外)。
  Future<void> syncMemosWithAll() async {
    if (!ready || _syncing) return;
    _syncing = true;
    try {
      final myGroup = _local?.groupCode ?? '';
      final targets = devices
          .where((d) => d.isReachable && d.groupCode == myGroup)
          .toList();
      if (targets.isEmpty) return; // 沒有可同步的對象:不算失敗,維持現狀。
      var anySuccess = false;
      for (final d in targets) {
        try {
          final remote = await _transport!.syncMemos(d, memos.exportJson());
          memos.mergeJson(remote);
          anySuccess = true;
        } catch (_) {
          // 單台離線/逾時不影響其餘裝置。
        }
      }
      if (anySuccess) {
        _lastMemoSyncAt = DateTime.now();
        _memoSyncFailStreak = 0;
      } else {
        _memoSyncFailStreak++;
      }
      // 任一次成功即清除;需連續失敗達門檻才亮,濾掉瞬時抖動。
      final failing = _memoSyncFailStreak >= _memoSyncFailThreshold;
      if (failing != _memoSyncFailing) {
        _memoSyncFailing = failing;
        notifyListeners();
      }
    } finally {
      _syncing = false;
    }
  }

  /// 傳輸層偵測到與對端時鐘偏移時的回呼:超過門檻才記錄並通知 UI,
  /// 只在「有/無」跨越門檻時 notify,避免每次同步都重繪。
  void _onClockSkew(Duration offset) {
    final over = offset.abs() > _clockSkewThreshold ? offset : null;
    final changed = (over == null) != (_clockSkew == null);
    _clockSkew = over;
    if (changed) notifyListeners();
  }

  /// 目前的同步群組碼(空字串=未設定,與所有同網裝置互通)。
  String get groupCode => _local?.groupCode ?? '';

  /// 變更同步群組碼:持久化、更新本機資訊與 mDNS 廣播,並重新同步一次。
  Future<void> updateGroupCode(String code) async {
    final trimmed = code.trim();
    await Identity.saveGroupCode(trimmed);
    final local = _local;
    if (local == null) return;
    _local = local.copyWith(groupCode: trimmed);
    _transport?.updateLocal(_local!);
    await _discovery.register(_local!); // 重新通告,帶上新的群組碼 TXT
    notifyListeners();
    await syncMemosWithAll();
  }

  /// 重設本機備忘錄並從其他裝置重新拉取。
  ///
  /// 用於本機資料已被污染(例如重裝前未同步、又在舊狀態上編輯/刪除過)時:
  /// 先清空本機(不留墓碑、不留時間戳),再向所有可連線裝置同步,
  /// 結果是純粹「以其他裝置為主」把資料拉回,本機的污染不會反向覆蓋對端。
  ///
  /// 回傳同步當下可連線的裝置數;為 0 時代表沒有對端可拉(本機會變空)。
  Future<int> resetMemosAndResync() async {
    await memos.clearLocal();
    final reachable = devices.where((d) => d.isReachable).length;
    await syncMemosWithAll();
    return reachable;
  }

  /// App 回到前景時重發通告並重啟探索。
  ///
  /// 解決 mDNS 單向探索失效:iOS 進背景會停止回應查詢,對端(尤其 macOS 的被動
  /// 探索)會抓不到本機;回前景重新 register/discovery 可讓雙方重新看到彼此。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ready) {
      _discovery.refresh();
      syncMemosWithAll();
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
          onMemoSync: (incoming) async => memos.mergeJson(incoming),
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
    } else if (_isImage(env) && (env.batchCount ?? 1) <= 1) {
      // 單張圖片:跳預覽讓接收方決定複製到剪貼簿或儲存。
      received.insert(0, item);
      notifyListeners();
      await onImageReceived?.call(item);
      return;
    } else {
      // 影片等其他檔,或一次傳來的多張圖片(批次):不跳彈窗,直接落地/存相簿。
      await _maybeSaveToGallery(item);
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
    try {
      final bytes = await File(path).readAsBytes();
      await clipboard.writeImagePng(bytes);
      _setStatus('已複製圖片到剪貼簿');
    } catch (_) {
      _setStatus('複製圖片失敗:檔案可能已損毀或遺失');
    }
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
      {String? mime,
      int? batchCount,
      void Function(double)? onProgress,
      TransferCancelToken? cancelToken}) async {
    await _transport!.sendFile(target, path,
        mime: mime,
        batchCount: batchCount,
        onProgress: onProgress,
        cancelToken: cancelToken);
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
  Future<void> sendShared(DeviceInfo target, SharedPayload payload,
      {int? batchCount}) async {
    switch (payload.kind) {
      case SharedKind.image:
        await _transport!.sendFile(target, payload.value,
            mime: _guessImageMime(payload.value), batchCount: batchCount);
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
        // 桌面接收資料夾與 baseDir 同一處,memos.json / alarm_group / sync_group
        // 也住這裡,清除收到的內容時要跳過這些設定檔,別把備忘錄、鬧鐘代碼、
        // 同步群組碼一起刪了。
        const protected = {'memos.json', 'alarm_group', 'sync_group'};
        await for (final entity in dir.list()) {
          if (entity is File) {
            if (protected.contains(p.basename(entity.path))) continue;
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

  Timer? _statusTimer;

  /// 狀態訊息自動清除的延遲。這些訊息都是「某次操作的結果」,
  /// 掛久了看不出屬於哪次操作,故一段時間後自動清空。
  static const _statusClearDelay = Duration(seconds: 4);

  void _setStatus(String s) {
    status = s;
    notifyListeners();
    _statusTimer?.cancel();
    _statusTimer = Timer(_statusClearDelay, () {
      status = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _discovery.stop();
    _transport?.stop();
    super.dispose();
  }
}
