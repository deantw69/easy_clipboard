import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
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
