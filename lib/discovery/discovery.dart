import '../core/models.dart';

/// 裝置發現/廣播的抽象介面。
///
/// 第一版用區網 mDNS([NsdDiscovery]);未來可新增 cloud_presence.dart
/// 提供雲端在線狀態,UI 與服務層不需更動。
abstract class DiscoveryService {
  /// 在網路上廣播本機裝置,讓其他裝置可以找到。
  Future<void> register(DeviceInfo local);

  /// 開始瀏覽其他裝置。透過 [onChanged] 回報目前可見的裝置清單(已去除本機)。
  Future<void> start(void Function(List<DeviceInfo> devices) onChanged);

  /// 停止瀏覽並取消廣播。
  Future<void> stop();
}
