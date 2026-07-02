import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 冷啟動通知點擊:必須在最早的 launch 就把 UNUserNotificationCenter delegate 掛上,
    // 否則 implicit-engine 架構下 plugin(flutter_local_notifications)註冊太晚,
    // iOS 在冷啟動當下投遞的通知回應會因當時沒有 delegate 而遺失 →
    // getNotificationAppLaunchDetails().didNotificationLaunchApp 回 false、分頁不切。
    // AppDelegate 繼承 FlutterAppDelegate,已實作 didReceiveNotificationResponse 並轉發給 plugin。
    UNUserNotificationCenter.current().delegate = self
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

    // 深連結(syncnest://):用官方 scene lifecycle 擴充點接收冷啟動/執行中 URL,
    // 取代抓不到冷啟動的 app_links(見 DeepLinkChannel.swift 註解)。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DeepLinkChannel") {
      DeepLinkChannel.register(with: registrar)
    }
  }
}
