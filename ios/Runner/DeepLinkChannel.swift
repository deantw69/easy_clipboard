import Flutter
import UIKit

/// 處理自訂 URL scheme `syncnest://` 的深連結,轉發給 Dart 端切換分頁。
///
/// 來源:主畫面 Widget 點擊(`syncnest://memo`)、鬧鐘推播/動態島點擊
/// (`syncnest://alarm`,僅 feat/alarm-tab 分支會送)。
///
/// **scene 架構(iOS 13+)下的收 URL 方式**:本 App 用 `FlutterSceneDelegate`,
/// scene 的冷啟動(`scene:willConnectToSession:options:`)與熱啟動
/// (`scene:openURLContexts:`)URL 事件,plugin 必須透過
/// `registrar.addSceneDelegate` 註冊為 `FlutterSceneLifeCycleDelegate` 才收得到;
/// 只靠 `addApplicationDelegate` + `application(_:open:)` 在 scene App 不保證被轉發。
/// 故兩者都註冊(application delegate 作為保險路徑)。
///
/// **冷啟動時序**:`channel` 早在 engine 初始化(`register`)就建立,但 Dart 端要到
/// 首幀後才 `setMethodCallHandler`,期間 `invokeMethod` 會遺失。故 Dart 未就緒
/// (`dartReady==false`)前一律把 host 暫存 `pending`,由 Dart 端 `getInitial` 取回。
class DeepLinkChannel: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  static let channelName = "syncnest/deeplink"

  private static var channel: FlutterMethodChannel?
  /// Dart handler 就緒前(冷啟動)先暫存路由目標(host,如 "memo"/"alarm")。
  private static var pending: String?
  /// Dart 端是否已註冊 handler(呼叫過 `getInitial` 即視為就緒)。
  private static var dartReady = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let ch = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "getInitial":
        dartReady = true
        let route = pending
        pending = nil
        result(route)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch

    let instance = DeepLinkChannel()
    registrar.addApplicationDelegate(instance)
    if #available(iOS 13.0, *) {
      registrar.addSceneDelegate(instance)
    }
  }

  // MARK: - Application delegate 路徑(保險)

  func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return DeepLinkChannel.handle(url)
  }

  // MARK: - Scene delegate 路徑(scene App 主要路徑)

  /// 熱啟動:App 已在背景執行時收到深連結。
  @available(iOS 13.0, *)
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var handled = false
    for context in URLContexts where DeepLinkChannel.handle(context.url) {
      handled = true
    }
    return handled
  }

  /// 冷啟動:App 由深連結喚醒,URL 在 connectionOptions 內。
  @available(iOS 13.0, *)
  @objc(scene:willConnectToSession:options:)
  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) -> Bool {
    var handled = false
    for context in connectionOptions.urlContexts where DeepLinkChannel.handle(context.url) {
      handled = true
    }
    return handled
  }

  // MARK: - 共用處理

  /// 只接受已知 scheme;回傳是否由本 plugin 處理。
  @discardableResult
  private static func handle(_ url: URL) -> Bool {
    guard url.scheme == "syncnest", let host = url.host, !host.isEmpty else { return false }
    if dartReady, let ch = channel {
      ch.invokeMethod("route", arguments: host)
    } else {
      // Dart handler 尚未就緒(冷啟動),暫存待 getInitial 取回。
      pending = host
    }
    return true
  }
}
