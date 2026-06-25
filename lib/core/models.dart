import 'dart:io';

/// 傳輸內容的種類。第一版支援檔案(圖片/影片/任意檔)與剪貼簿(文字/圖片)。
enum PayloadKind { file, clipboardText, clipboardImage }

/// 區網上的一台裝置。
///
/// [id] 為跨平台穩定識別碼(持久化於本機),未來做雲端同步/衝突解決時沿用。
class DeviceInfo {
  final String id;
  final String name;
  final String platform; // macos / ios / windows
  final String? host; // 區網 IP,發現遠端裝置時才有
  final int port; // 接收端 HTTP server 埠

  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    this.host,
    required this.port,
  });

  bool get isReachable => host != null;

  DeviceInfo copyWith({String? host, int? port}) => DeviceInfo(
        id: id,
        name: name,
        platform: platform,
        host: host ?? this.host,
        port: port ?? this.port,
      );

  /// 本機裝置資訊。[id]/[name] 由上層提供,確保跨啟動穩定。
  static DeviceInfo local({
    required String id,
    required String name,
    required int port,
  }) =>
      DeviceInfo(id: id, name: name, platform: currentPlatform, port: port);

  static String get currentPlatform {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isAndroid) return 'android';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}

/// 一筆傳輸的中繼資料(metadata)。檔案本體另以串流傳送,不放進此物件。
///
/// 統一的 envelope:未來雲端中繼只是換一個 transport 實作,此結構不變。
class TransferEnvelope {
  final String id;
  final PayloadKind kind;
  final String senderDeviceId;
  final DateTime timestamp;

  /// 檔案傳輸時的檔名與位元組大小;剪貼簿文字時可為 null。
  final String? fileName;
  final int? sizeBytes;

  /// MIME 類型(盡力而為),例如 image/jpeg、video/mp4、text/plain。
  final String? mime;

  const TransferEnvelope({
    required this.id,
    required this.kind,
    required this.senderDeviceId,
    required this.timestamp,
    this.fileName,
    this.sizeBytes,
    this.mime,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'senderDeviceId': senderDeviceId,
        'timestamp': timestamp.toIso8601String(),
        if (fileName != null) 'fileName': fileName,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (mime != null) 'mime': mime,
      };

  factory TransferEnvelope.fromJson(Map<String, dynamic> j) => TransferEnvelope(
        id: j['id'] as String,
        kind: PayloadKind.values.byName(j['kind'] as String),
        senderDeviceId: j['senderDeviceId'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        fileName: j['fileName'] as String?,
        sizeBytes: (j['sizeBytes'] as num?)?.toInt(),
        mime: j['mime'] as String?,
      );
}

/// 一次傳入(接收)的紀錄,供 UI 顯示。
class ReceivedItem {
  final TransferEnvelope envelope;

  /// 檔案落地路徑(檔案類型);剪貼簿類型可為 null。
  final String? savedPath;

  /// 剪貼簿文字內容(僅 clipboardText)。
  final String? text;

  const ReceivedItem({required this.envelope, this.savedPath, this.text});
}
