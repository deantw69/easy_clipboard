import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 開機自啟動:透過 SMAppService 註冊/解除本 App 為登入項目(需 macOS 13+)。
    let channel = FlutterMethodChannel(
      name: "easy_clipboard/autostart",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isEnabled":
        if #available(macOS 13.0, *) {
          result(SMAppService.mainApp.status == .enabled)
        } else {
          result(false)
        }
      case "setEnabled":
        let enabled = (call.arguments as? Bool) ?? false
        if #available(macOS 13.0, *) {
          do {
            if enabled {
              try SMAppService.mainApp.register()
            } else {
              try SMAppService.mainApp.unregister()
            }
            result(nil)
          } catch {
            result(FlutterError(
              code: "autostart_failed",
              message: error.localizedDescription,
              details: nil))
          }
        } else {
          result(FlutterError(
            code: "unsupported",
            message: "需要 macOS 13 以上",
            details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
