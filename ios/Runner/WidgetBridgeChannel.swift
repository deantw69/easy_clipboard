import Flutter
import WidgetKit

/// 接收 Dart 端(lib/core/widget_bridge.dart)推來的備忘錄摘要,
/// 寫進 App Group 供主畫面 Widget(MemoWidget)讀取,並要求 Widget 重新載入。
///
/// 資料契約(App Group `group.dev.deantw69.syncNest`,key `memo_widget_data`,存 JSON Data):
///   { "pinned": Summary | null, "recent": [Summary, ...] }
///   Summary = { "title": String, "color": Int?, "todoCount": Int, "doneCount": Int }
enum WidgetBridgeChannel {
  static let appGroupId = "group.dev.deantw69.syncNest"
  static let dataKey = "memo_widget_data"

  static func register(with registry: FlutterPluginRegistry) {
    guard let messenger = registry.registrar(forPlugin: "WidgetBridge")?.messenger() else {
      return
    }
    let channel = FlutterMethodChannel(name: "syncnest/widget", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "update":
        handleUpdate(call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func handleUpdate(_ args: Any?, result: FlutterResult) {
    guard let dict = args as? [String: Any],
          let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
          let defaults = UserDefaults(suiteName: appGroupId) else {
      result(false)
      return
    }
    defaults.set(data, forKey: dataKey)
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
    result(true)
  }
}
