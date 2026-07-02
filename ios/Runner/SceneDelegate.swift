import Flutter
import UIKit

/// 深連結:覆寫 UIKit scene 入口捕捉 `syncnest://` URL,餵給 [DeepLinkChannel]。
/// 這是保證會被 UIKit 呼叫的入口,補上 app_links 收不到的冷啟動 / Live Activity URL。
/// 一律先呼 `super` 保住 Flutter 的 scene 設定,再取 URL。
class SceneDelegate: FlutterSceneDelegate {

  /// 冷啟動:App 未執行時由深連結啟動,URL 在 connectionOptions.URLContexts。
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let url = connectionOptions.urlContexts.first?.url {
      DeepLinkChannel.shared.setInitialLink(url)
    }
  }

  /// 執行中(熱啟動 / 從背景喚醒):widget、Live Activity/動態島的 .widgetURL tap 走這裡。
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    if let url = URLContexts.first?.url {
      DeepLinkChannel.shared.emit(url)
    }
  }
}
