import Flutter
import UIKit

/// 處理自訂 URL scheme `syncnest://` 的深連結,轉發給 Dart 端切換分頁。
///
/// 來源:主畫面 Widget 點擊(`syncnest://memo`)、鬧鐘推播/動態島點擊
/// (`syncnest://alarm`,僅 feat/alarm-tab 分支會送)。
///
/// 註冊成 Flutter plugin 的 application delegate(`addApplicationDelegate`),
/// 讓 `FlutterSceneDelegate` 把 scene 的冷/熱啟動 URL 自動轉發到
/// `application(_:open:options:)`——與 receive_sharing_intent 相同機制,
/// 故不需(也不該)去覆寫 SceneDelegate,避免破壞既有分享流程。
///
/// 冷啟動時 URL 可能早於 Dart 端註冊 handler 抵達,先暫存於 `pending`,
/// 待 Dart 端啟動後呼叫 `getInitial` 取回並清空;執行中則即時經 `route` 推送。
class DeepLinkChannel: NSObject, FlutterPlugin {
  static let channelName = "syncnest/deeplink"

  private static var channel: FlutterMethodChannel?
  /// 冷啟動時尚無 Dart handler,先暫存路由目標(host,如 "memo"/"alarm")。
  private static var pending: String?

  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "DeepLink") else { return }
    let ch = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "getInitial":
        let route = pending
        pending = nil
        result(route)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
    registrar.addApplicationDelegate(DeepLinkChannel())
  }

  /// scene 的冷啟動(willConnect)與熱啟動(openURLContexts)URL 都由
  /// FlutterSceneDelegate 轉發到這裡。
  func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return DeepLinkChannel.handle(url)
  }

  /// 只接受已知 scheme;回傳是否由本 plugin 處理。
  @discardableResult
  private static func handle(_ url: URL) -> Bool {
    guard url.scheme == "syncnest", let host = url.host, !host.isEmpty else { return false }
    if let ch = channel {
      ch.invokeMethod("route", arguments: host)
    } else {
      // Dart 尚未就緒(冷啟動),暫存待 getInitial 取回。
      pending = host
    }
    return true
  }
}
