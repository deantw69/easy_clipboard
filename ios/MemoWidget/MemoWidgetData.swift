import SwiftUI

/// 與主 App 共享的資料契約(見 Runner/WidgetBridgeChannel.swift)。
/// 從 App Group UserDefaults 的 `memo_widget_data`(JSON Data)解碼。
struct MemoSummary: Codable, Hashable {
  let title: String
  let color: Int?
  let todoCount: Int
  let doneCount: Int
}

struct MemoWidgetData: Codable {
  let pinned: MemoSummary?
  let recent: [MemoSummary]

  static let empty = MemoWidgetData(pinned: nil, recent: [])

  /// 提供 Widget 預覽/佔位用的假資料。
  static let sample = MemoWidgetData(
    pinned: MemoSummary(title: "買牛奶、雞蛋、麵包", color: nil, todoCount: 3, doneCount: 1),
    recent: [
      MemoSummary(title: "買牛奶、雞蛋、麵包", color: nil, todoCount: 3, doneCount: 1),
      MemoSummary(title: "週五交報告", color: 0xFFB3E5FC, todoCount: 0, doneCount: 0),
      MemoSummary(title: "回覆客戶信件", color: 0xFFC8E6C9, todoCount: 2, doneCount: 2),
    ]
  )
}

enum MemoWidgetStore {
  static let appGroupId = "group.com.philio.syncNest"
  static let dataKey = "memo_widget_data"

  static func load() -> MemoWidgetData {
    guard let data = UserDefaults(suiteName: appGroupId)?.data(forKey: dataKey),
          let decoded = try? JSONDecoder().decode(MemoWidgetData.self, from: data) else {
      return .empty
    }
    return decoded
  }
}

extension Color {
  /// 把備忘錄的 ARGB int 轉成 Color;nil 用預設便利貼黃。
  static func fromMemoARGB(_ argb: Int?) -> Color {
    guard let v = argb else {
      return Color(red: 1.0, green: 0.9, blue: 0.4)
    }
    let a = Double((v >> 24) & 0xFF) / 255.0
    let r = Double((v >> 16) & 0xFF) / 255.0
    let g = Double((v >> 8) & 0xFF) / 255.0
    let b = Double(v & 0xFF) / 255.0
    return Color(.sRGB, red: r, green: g, blue: b, opacity: a == 0 ? 1 : a)
  }
}
