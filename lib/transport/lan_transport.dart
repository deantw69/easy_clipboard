import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' hide Response;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:uuid/uuid.dart';

import '../core/models.dart';
import '../core/storage_location.dart';
import 'transport.dart';

/// 區網直傳:接收端跑 shelf HTTP server,傳送端用 dio 串流上傳。
///
/// 協定(沿用 LocalSend 的「接收端開 server」模型,第一版簡化為單段上傳):
///   - GET  /info       → 回傳本機裝置 JSON(供連線前確認)
///   - POST /file       → header `x-envelope` 帶 metadata,body 為檔案串流(邊收邊寫)
///   - POST /clipboard  → header `x-envelope` 帶 metadata,body 為文字/PNG 位元組
const _defaultPort = 53318;
const _envelopeHeader = 'x-envelope';
const _groupHeader = 'x-group-code';
// 同步時雙方互帶當下 epoch 毫秒,用來偵測系統時鐘偏移(向後相容:舊版不帶即略過)。
const _syncTimeHeader = 'x-sync-time';

class LanTransport implements Transport {
  final int port;
  LanTransport({this.port = _defaultPort});

  HttpServer? _server;
  DeviceInfo? _local;
  // connectTimeout:連不上對方時盡快失敗(而非卡到預設 30 分)。
  // sendTimeout:dio 以「距上次送出 bytes 的間隔」計時,故這是「傳輸停滯」的
  // 偵測門檻——對方傳到一半離線時 30 秒無進展即中止,不再無限卡進度條。
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 30),
  ));

  Future<String> Function(String incomingJson)? _onMemoSync;
  void Function(Duration offset)? _onClockSkew;

  @override
  set onClockSkew(void Function(Duration offset)? cb) => _onClockSkew = cb;

  @override
  Future<void> start(
    DeviceInfo local,
    void Function(ReceivedItem) onReceived, {
    Future<String> Function(String incomingJson)? onMemoSync,
  }) async {
    _local = local;
    _onMemoSync = onMemoSync;
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler((req) => _route(req, onReceived));
    // 綁定到 anyIPv4,讓區網其他裝置可連入。
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  }

  Future<Response> _route(
      Request req, void Function(ReceivedItem) onReceived) async {
    if (req.method == 'POST' && req.url.path == 'memos/sync') {
      // 群組碼二次防線:不符就拒絕,避免舊 TXT/時序問題誤合併。
      if ((req.headers[_groupHeader] ?? '') != (_local?.groupCode ?? '')) {
        return Response(403, body: 'group mismatch');
      }
      final cb = _onMemoSync;
      if (cb == null) return Response(503, body: 'memo sync unavailable');
      final merged = await cb(await req.readAsString());
      // 接收端時鐘偏移偵測:比對對方送出時間與本機當下(含極小的單向延遲,可忽略)。
      final ct = int.tryParse(req.headers[_syncTimeHeader] ?? '');
      if (ct != null) {
        _onClockSkew?.call(
            Duration(milliseconds: ct - DateTime.now().millisecondsSinceEpoch));
      }
      return Response.ok(merged, headers: {
        'content-type': 'application/json',
        _syncTimeHeader: '${DateTime.now().millisecondsSinceEpoch}',
      });
    }
    if (req.method == 'GET' && req.url.path == 'info') {
      final l = _local!;
      return Response.ok(
        jsonEncode({'id': l.id, 'name': l.name, 'platform': l.platform}),
        headers: {'content-type': 'application/json'},
      );
    }
    if (req.method == 'POST' && req.url.path == 'file') {
      return _receiveFile(req, onReceived);
    }
    if (req.method == 'POST' && req.url.path == 'clipboard') {
      return _receiveClipboard(req, onReceived);
    }
    return Response.notFound('not found');
  }

  Future<Response> _receiveFile(
      Request req, void Function(ReceivedItem) onReceived) async {
    final env = _decodeEnvelope(req);
    if (env == null) return Response(400, body: 'missing envelope');

    final dir = await _saveDir();
    final fileName = env.fileName ?? '${env.id}.bin';
    final outPath = _uniquePath(dir, fileName);
    if (!await _writeBodyVerified(req, env, outPath)) {
      return Response(400, body: 'incomplete transfer');
    }
    onReceived(ReceivedItem(envelope: env, savedPath: outPath));
    return Response.ok('ok');
  }

  Future<Response> _receiveClipboard(
      Request req, void Function(ReceivedItem) onReceived) async {
    final env = _decodeEnvelope(req);
    if (env == null) return Response(400, body: 'missing envelope');

    if (env.kind == PayloadKind.clipboardText || env.kind == PayloadKind.url) {
      final text = await req.readAsString();
      onReceived(ReceivedItem(envelope: env, text: text));
    } else {
      // clipboardImage:存成 PNG 檔,交給上層寫入系統剪貼簿。
      final dir = await _saveDir();
      final outPath = _uniquePath(dir, env.fileName ?? '${env.id}.png');
      if (!await _writeBodyVerified(req, env, outPath)) {
        return Response(400, body: 'incomplete transfer');
      }
      onReceived(ReceivedItem(envelope: env, savedPath: outPath));
    }
    return Response.ok('ok');
  }

  /// 邊收邊寫入 [outPath],並在完成後校驗完整性。
  ///
  /// 回傳 true=完整落地;false=傳輸中斷或大小不符(已刪掉半寫檔,不入庫)。
  /// 校驗依 envelope 的 `sizeBytes`——舊版不帶此欄位時退化為只擋「中途斷線」
  /// (串流拋例外),不比對大小,維持雙端協定向後相容。
  static Future<bool> _writeBodyVerified(
      Request req, TransferEnvelope env, String outPath) async {
    final sink = File(outPath).openWrite();
    var written = 0;
    var completed = false;
    try {
      // 邊收邊寫,不把整個檔案讀進記憶體(大影片不會 OOM)。
      await for (final chunk in req.read()) {
        written += chunk.length;
        sink.add(chunk);
      }
      await sink.flush();
      completed = true;
    } catch (_) {
      // 傳輸中斷:截斷檔不入庫。
    } finally {
      await sink.close();
    }
    final expected = env.sizeBytes;
    final ok = completed && (expected == null || written == expected);
    if (!ok) {
      try {
        await File(outPath).delete();
      } catch (_) {}
    }
    return ok;
  }

  // ---- 傳送端 ----

  @override
  Future<void> sendFile(
    DeviceInfo target,
    String filePath, {
    String? mime,
    int? batchCount,
    void Function(double)? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    final size = await file.length();
    // 把抽象取消權杖綁定到 dio 的 CancelToken;取消時 dio 拋 cancel 型例外,
    // 經 _guarded → _classifyDioError 轉成「已取消傳送」。
    final dioToken = CancelToken();
    cancelToken?.onCancel = dioToken.cancel;
    final env = TransferEnvelope(
      id: const Uuid().v4(),
      kind: PayloadKind.file,
      senderDeviceId: _local!.id,
      timestamp: DateTime.now(),
      fileName: p.basename(filePath),
      sizeBytes: size,
      mime: mime,
      batchCount: batchCount,
    );
    await _guarded(() => _dio.post(
          _url(target, 'file'),
          data: file.openRead(), // 串流上傳
          cancelToken: dioToken,
          options: Options(
            headers: {
              _envelopeHeader: _encodeEnvelope(env),
              Headers.contentLengthHeader: size,
            },
            contentType: mime ?? 'application/octet-stream',
          ),
          onSendProgress: (sent, total) {
            if (total > 0) onProgress?.call(sent / total);
          },
        ));
  }

  @override
  Future<void> sendClipboardText(DeviceInfo target, String text) async {
    final env = TransferEnvelope(
      id: const Uuid().v4(),
      kind: PayloadKind.clipboardText,
      senderDeviceId: _local!.id,
      timestamp: DateTime.now(),
      mime: 'text/plain',
    );
    await _guarded(() => _dio.post(
          _url(target, 'clipboard'),
          data: text,
          options: Options(
            headers: {_envelopeHeader: _encodeEnvelope(env)},
            contentType: 'text/plain; charset=utf-8',
          ),
        ));
  }

  @override
  Future<void> sendUrl(DeviceInfo target, String url) async {
    final env = TransferEnvelope(
      id: const Uuid().v4(),
      kind: PayloadKind.url,
      senderDeviceId: _local!.id,
      timestamp: DateTime.now(),
      mime: 'text/uri-list',
    );
    await _guarded(() => _dio.post(
          _url(target, 'clipboard'),
          data: url,
          options: Options(
            headers: {_envelopeHeader: _encodeEnvelope(env)},
            contentType: 'text/plain; charset=utf-8',
          ),
        ));
  }

  @override
  Future<void> sendClipboardImage(DeviceInfo target, List<int> pngBytes) async {
    final env = TransferEnvelope(
      id: const Uuid().v4(),
      kind: PayloadKind.clipboardImage,
      senderDeviceId: _local!.id,
      timestamp: DateTime.now(),
      fileName: 'clipboard.png',
      sizeBytes: pngBytes.length,
      mime: 'image/png',
    );
    await _guarded(() => _dio.post(
          _url(target, 'clipboard'),
          data: Stream.value(pngBytes),
          options: Options(
            headers: {
              _envelopeHeader: _encodeEnvelope(env),
              Headers.contentLengthHeader: pngBytes.length,
            },
            contentType: 'image/png',
          ),
        ));
  }

  @override
  Future<String> syncMemos(DeviceInfo target, String localJson) async {
    final myTime = DateTime.now().millisecondsSinceEpoch;
    final res = await _dio.post(
      _url(target, 'memos/sync'),
      data: localJson,
      options: Options(
        contentType: 'application/json; charset=utf-8',
        responseType: ResponseType.plain,
        headers: {
          _groupHeader: _local?.groupCode ?? '',
          _syncTimeHeader: '$myTime',
        },
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    // 傳送端時鐘偏移偵測:用送出/收到的中點時間抵銷來回延遲後,比對對端時間。
    final st = int.tryParse(res.headers.value(_syncTimeHeader) ?? '');
    if (st != null && _onClockSkew != null) {
      final mid = (myTime + DateTime.now().millisecondsSinceEpoch) ~/ 2;
      _onClockSkew!(Duration(milliseconds: st - mid));
    }
    return res.data as String;
  }

  @override
  void updateLocal(DeviceInfo local) => _local = local;

  @override
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ---- helpers ----

  /// 包住 dio 送出動作,把底層 DioException/StateError 轉成 [TransferException]
  /// (訊息為可直接顯示的繁中),讓所有傳送路徑的失敗回饋一致。
  Future<T> _guarded<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      throw TransferException(_classifyDioError(e));
    } on StateError catch (e) {
      // _url 在 host 未解析時拋出,訊息本身已是繁中。
      throw TransferException(e.message);
    }
  }

  /// 把 DioException 分類成使用者看得懂的繁中訊息。
  static String _classifyDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return '連線逾時,對方可能不在線或網路不穩';
      case DioExceptionType.sendTimeout:
        return '傳送逾時,請確認網路連線';
      case DioExceptionType.receiveTimeout:
        return '等待對方回應逾時,請重試';
      case DioExceptionType.cancel:
        return '已取消傳送';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 403) return '對方拒絕連線(同步群組碼不符)';
        return '對方回應錯誤(HTTP $code)';
      case DioExceptionType.badCertificate:
        return '憑證驗證失敗';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        final inner = e.error;
        if (inner is SocketException) {
          final os = inner.osError?.errorCode;
          // 連線被拒:對方 App 未開或防火牆擋住(mac/Linux 61、Windows 10061)。
          if (os == 61 || os == 10061) return '連線被拒,對方 App 可能未開啟';
          // 主機不可達(mac 65/51、Windows 10065/10051)。
          if (os == 65 || os == 51 || os == 10065 || os == 10051) {
            return '找不到對方裝置,請確認雙方在同一區網';
          }
          return '網路連線失敗,請確認雙方在同一區網';
        }
        return '傳送失敗:${e.message ?? e.type.name}';
    }
  }

  String _url(DeviceInfo t, String path) {
    final host = t.host;
    // host 未解析(mDNS 尚未拿到 IP)時直接擋下,避免組出 http://null:port
    // 這種必然逾時的請求,讓上層 try-catch 立即以清楚訊息回報。
    if (host == null || host.isEmpty) {
      throw StateError('裝置尚未解析,請稍候或重新整理');
    }
    return 'http://$host:${t.port}/$path';
  }

  static String _encodeEnvelope(TransferEnvelope env) =>
      base64Url.encode(utf8.encode(jsonEncode(env.toJson())));

  static TransferEnvelope? _decodeEnvelope(Request req) {
    final raw = req.headers[_envelopeHeader];
    if (raw == null) return null;
    final json = jsonDecode(utf8.decode(base64Url.decode(raw)))
        as Map<String, dynamic>;
    return TransferEnvelope.fromJson(json);
  }

  /// 對外公開接收檔案的落地目錄,供清除暫存時掃描。
  static Future<Directory> receivedDir() => _saveDir();

  /// 接收檔案的落地目錄。桌面用 StorageLocation(預設 Downloads/SyncNest,
  /// 可由使用者改選),行動裝置用 App 文件目錄。
  static Future<Directory> _saveDir() async {
    if (Platform.isMacOS || Platform.isWindows) {
      return StorageLocation.instance.baseDir();
    }
    Directory base;
    if (Platform.isLinux) {
      base = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory(p.join(base.path, 'SyncNest'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _uniquePath(Directory dir, String fileName) {
    var candidate = p.join(dir.path, fileName);
    if (!File(candidate).existsSync()) return candidate;
    final name = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    var i = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(dir.path, '$name ($i)$ext');
      i++;
    }
    return candidate;
  }
}
