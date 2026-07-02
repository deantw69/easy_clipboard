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

    // 註冊 Live Activity(動態島)channel。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityChannel") {
      LiveActivityChannel.register(messenger: registrar.messenger())
    }

    // 註冊主畫面 Widget(MemoWidget)橋接 channel。
    WidgetBridgeChannel.register(with: engineBridge.pluginRegistry)
    DeepLinkChannel.register(with: engineBridge.pluginRegistry)
  }
}
