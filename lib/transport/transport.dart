import '../core/models.dart';

/// 傳送失敗時對外拋出的例外,[message] 已是可直接顯示的繁中訊息。
///
/// 傳輸層(如 [LanTransport])把底層 DioException/SocketException 分類轉成
/// 使用者看得懂的說明,UI 只需 `catch` 後把 [message] 丟給 SnackBar。
class TransferException implements Exception {
  final String message;
  TransferException(this.message);
  @override
  String toString() => message;
}

/// 傳輸層抽象。第一版為區網直傳([LanTransport]);
/// 未來雲端中繼只需新增 cloud_relay_transport.dart 實作此介面。
abstract class Transport {
  /// 啟動接收端。收到資料時呼叫 [onReceived]。
  ///
  /// [onMemoSync] 處理對端的備忘錄同步請求:傳入對方完整清單 JSON,
  /// 回傳本機合併後的完整清單 JSON(一次往返讓雙方收斂)。
  Future<void> start(
    DeviceInfo local,
    void Function(ReceivedItem) onReceived, {
    Future<String> Function(String incomingJson)? onMemoSync,
  });

  /// 傳送檔案(圖片/影片/任意檔)。[onProgress] 回報 0.0~1.0。
  Future<void> sendFile(
    DeviceInfo target,
    String filePath, {
    String? mime,
    int? batchCount,
    void Function(double progress)? onProgress,
  });

  /// 傳送剪貼簿純文字。
  Future<void> sendClipboardText(DeviceInfo target, String text);

  /// 傳送網址。接收端會詢問是否在瀏覽器開啟。
  Future<void> sendUrl(DeviceInfo target, String url);

  /// 傳送剪貼簿圖片(PNG 位元組)。
  Future<void> sendClipboardImage(DeviceInfo target, List<int> pngBytes);

  /// 與 [target] 同步備忘錄:送出本機完整清單 [localJson],
  /// 回傳對方合併後的完整清單 JSON。
  Future<String> syncMemos(DeviceInfo target, String localJson);

  /// 更新本機裝置資訊(例如群組碼變更後),讓接收端比對用最新值。
  void updateLocal(DeviceInfo local);

  Future<void> stop();
}
