import '../core/models.dart';

/// 傳輸層抽象。第一版為區網直傳([LanTransport]);
/// 未來雲端中繼只需新增 cloud_relay_transport.dart 實作此介面。
abstract class Transport {
  /// 啟動接收端。收到資料時呼叫 [onReceived]。
  Future<void> start(DeviceInfo local, void Function(ReceivedItem) onReceived);

  /// 傳送檔案(圖片/影片/任意檔)。[onProgress] 回報 0.0~1.0。
  Future<void> sendFile(
    DeviceInfo target,
    String filePath, {
    String? mime,
    void Function(double progress)? onProgress,
  });

  /// 傳送剪貼簿純文字。
  Future<void> sendClipboardText(DeviceInfo target, String text);

  /// 傳送剪貼簿圖片(PNG 位元組)。
  Future<void> sendClipboardImage(DeviceInfo target, List<int> pngBytes);

  Future<void> stop();
}
