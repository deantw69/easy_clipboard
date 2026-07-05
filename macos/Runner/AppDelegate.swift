import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 本次是否由登入項目(SMAppService)自動啟動;供「自啟時隱藏視窗」判斷。
  /// 需在啟動當下抓 open-application AppleEvent 的 keyAELaunchedAsLogInItem,
  /// 該事件之後就取不到,故在 finishLaunching 時就快取。
  static var launchedAtLogin = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let event = NSAppleEventManager.shared().currentAppleEvent,
       event.eventID == AEEventID(kAEOpenApplication),
       event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
         == keyAELaunchedAsLogInItem {
      AppDelegate.launchedAtLogin = true
    }
    super.applicationDidFinishLaunching(notification)
  }

  // 必須回 false:視窗隱藏到狀態列(orderOut)仍會觸發此檢查,回 true 會讓
  // 點紅點關窗直接結束 App。真正退出走 tray 選單「結束」(windowManager.destroy)或 Cmd+Q。
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // 視窗隱藏到狀態列(tray)後,點 Dock 圖示要能叫回主視窗。
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(self)
    }
    return true
  }
}
