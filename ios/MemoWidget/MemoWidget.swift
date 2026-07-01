import WidgetKit
import SwiftUI

struct MemoEntry: TimelineEntry {
  let date: Date
  let data: MemoWidgetData
}

struct MemoProvider: TimelineProvider {
  func placeholder(in context: Context) -> MemoEntry {
    MemoEntry(date: Date(), data: .sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (MemoEntry) -> Void) {
    let data = context.isPreview ? .sample : MemoWidgetStore.load()
    completion(MemoEntry(date: Date(), data: data))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<MemoEntry>) -> Void) {
    let entry = MemoEntry(date: Date(), data: MemoWidgetStore.load())
    // 內容變動時主 App 會呼叫 reloadAllTimelines,故這裡不需定時刷新。
    completion(Timeline(entries: [entry], policy: .never))
  }
}

struct MemoWidgetEntryView: View {
  @Environment(\.widgetFamily) var family
  var entry: MemoEntry

  var body: some View {
    switch family {
    case .systemSmall:
      PinnedMemoView(memo: entry.data.pinned)
        .widgetBackground(Color.fromMemoARGB(entry.data.pinned?.color))
    default:
      RecentMemoListView(data: entry.data)
        .widgetBackground(Color(.systemBackground))
    }
  }
}

/// iOS 17 要求 Widget 用 containerBackground 宣告背景;iOS 16 退回一般 background。
extension View {
  @ViewBuilder
  func widgetBackground<Background: View>(_ background: Background) -> some View {
    if #available(iOS 17.0, *) {
      containerBackground(for: .widget) { background }
    } else {
      self.background(background)
    }
  }
}

struct MemoWidget: Widget {
  let kind: String = "MemoWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: MemoProvider()) { entry in
      MemoWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("SyncNest 備忘錄")
    .description("顯示釘選的備忘錄與最近幾筆。")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
