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

    // 自訂儲存資料夾:沙盒下用 security-scoped bookmark 持久化使用者選的資料夾,
    // 讓 App 重啟後仍能存取(否則 user-selected 權限只在本次執行期間有效)。
    let bookmarkChannel = FlutterMethodChannel(
      name: "easy_clipboard/storage_bookmark",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    bookmarkChannel.setMethodCallHandler { call, result in
      let key = "storage_bookmark"
      switch call.method {
      case "save":
        guard let path = call.arguments as? String else {
          result(false)
          return
        }
        let url = URL(fileURLWithPath: path)
        do {
          let data = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil)
          UserDefaults.standard.set(data, forKey: key)
          _ = url.startAccessingSecurityScopedResource()
          result(true)
        } catch {
          result(false)
        }
      case "resolve":
        guard let data = UserDefaults.standard.data(forKey: key) else {
          result(nil)
          return
        }
        var stale = false
        do {
          let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale)
          if url.startAccessingSecurityScopedResource() {
            result(url.path)
          } else {
            result(nil)
          }
        } catch {
          result(nil)
        }
      case "clear":
        UserDefaults.standard.removeObject(forKey: key)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
