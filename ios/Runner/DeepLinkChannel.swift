import Flutter
import UIKit

/// 深連結(自訂 scheme `syncnest://`)的 channel/儲存端——取代 `app_links`
/// (它在本 App 的 implicit-engine + `FlutterSceneDelegate` 架構下抓不到「冷啟動」與
/// Live Activity 的 URL,只實作了執行中的 `application:openURL:`)。
///
/// 實際的 scene URL 由 [SceneDelegate] 覆寫 UIKit 的 `scene(_:willConnectTo:options:)`
/// (冷啟動)與 `scene(_:openURLContexts:)`(執行中)捕捉後餵進本類——那是保證會被 UIKit
/// 呼叫的入口,不靠 plugin 轉發、也不碰 Flutter 私有的 scene 協定(避開選擇器撞名的編譯雷)。
///
/// - 冷啟動:URL 存進 `initialLink`(此時 Flutter engine/channel 可能尚未就緒),
///   Dart 端 `start()` 時以 method `getInitialLink` 取回。
/// - 執行中:立刻經 method `onLink` 推給 Dart。
final class DeepLinkChannel: NSObject, FlutterPlugin {
  static let shared = DeepLinkChannel()

  private var channel: FlutterMethodChannel?
  /// 冷啟動時捕捉到的首個 URL,供 Dart `getInitialLink` 取回。
  private var initialLink: String?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "syncnest/deep_link",
      binaryMessenger: registrar.messenger())
    shared.channel = channel
    registrar.addMethodCallDelegate(shared, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getInitialLink":
      result(initialLink)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 冷啟動捕捉(SceneDelegate 於 willConnect 呼叫):只存,不推(channel 可能還沒好)。
  func setInitialLink(_ url: URL) {
    initialLink = url.absoluteString
    NSLog("[DeepLink] willConnect(cold): \(url.absoluteString)")
  }

  /// 執行中捕捉(SceneDelegate 於 openURLContexts 呼叫):立刻推給 Dart。
  func emit(_ url: URL) {
    NSLog("[DeepLink] openURLContexts(hot): \(url.absoluteString)")
    channel?.invokeMethod("onLink", arguments: url.absoluteString)
  }
}
