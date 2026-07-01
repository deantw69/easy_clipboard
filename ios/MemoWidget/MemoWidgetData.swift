import SwiftUI

/// 與主 App 共享的資料契約(見 Runner/WidgetBridgeChannel.swift)。
/// 從 App Group UserDefaults 的 `memo_widget_data`(JSON Data)解碼。
struct MemoTodoItem: Codable, Hashable {
  let text: String
  let done: Bool
}

struct MemoSummary: Codable, Hashable, Identifiable {
  let id: String
  let title: String
  let color: Int?
  let todos: [MemoTodoItem]

  /// 未勾選優先,已勾選排後(各自維持原順序);供 Widget 顯示與截斷用。
  var orderedTodos: [MemoTodoItem] {
    todos.filter { !$0.done } + todos.filter { $0.done }
  }

  /// 標題為空時的顯示名(供選單/標題列)。
  var displayName: String {
    title.isEmpty ? "(無標題備忘錄)" : title
  }
}

struct MemoWidgetData: Codable {
  let memos: [MemoSummary]

  static let empty = MemoWidgetData(memos: [])

  func memo(id: String) -> MemoSummary? {
    memos.first { $0.id == id }
  }

  /// 提供 Widget 預覽/佔位用的假資料。
  static let sample = MemoWidgetData(memos: [
    MemoSummary(
      id: "sample-1",
      title: "週末採買",
      color: nil,
      todos: [
        MemoTodoItem(text: "買牛奶", done: false),
        MemoTodoItem(text: "雞蛋一盒", done: false),
        MemoTodoItem(text: "麵包", done: false),
        MemoTodoItem(text: "領包裹", done: true),
      ]
    ),
    MemoSummary(
      id: "sample-2",
      title: "工作待辦",
      color: 0xFFB3E5FC,
      todos: [
        MemoTodoItem(text: "回覆客戶信件", done: false),
        MemoTodoItem(text: "週五交報告", done: false),
      ]
    ),
  ])

  static var sampleMemo: MemoSummary { sample.memos[0] }
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
