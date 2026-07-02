import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // 註冊主畫面 Widget(MemoWidget)橋接 channel。
    WidgetBridgeChannel.register(with: engineBridge.pluginRegistry)

    // 深連結(syncnest://):scene URL 由 SceneDelegate 覆寫捕捉後餵給此 channel。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeepLinkChannel") {
      DeepLinkChannel.register(with: registrar)
    }
  }
}
