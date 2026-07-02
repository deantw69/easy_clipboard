import WidgetKit
import SwiftUI
import AppIntents

struct MemoEntry: TimelineEntry {
  let date: Date
  let memo: MemoSummary?
  /// 使用者是否已在設定挑過備忘錄(用來區分「尚未選」與「選到的已被刪除」)。
  let hasSelection: Bool
}

struct MemoProvider: AppIntentTimelineProvider {
  typealias Entry = MemoEntry
  typealias Intent = SelectMemoIntent

  func placeholder(in context: Context) -> MemoEntry {
    MemoEntry(date: Date(), memo: MemoWidgetData.sampleMemo, hasSelection: true)
  }

  func snapshot(for configuration: SelectMemoIntent, in context: Context) async -> MemoEntry {
    if context.isPreview {
      return MemoEntry(date: Date(), memo: MemoWidgetData.sampleMemo, hasSelection: true)
    }
    return resolve(configuration)
  }

  func timeline(for configuration: SelectMemoIntent, in context: Context) async -> Timeline<MemoEntry> {
    // 內容變動時主 App 會呼叫 reloadAllTimelines,故這裡不需定時刷新。
    Timeline(entries: [resolve(configuration)], policy: .never)
  }

  private func resolve(_ configuration: SelectMemoIntent) -> MemoEntry {
    let data = MemoWidgetStore.load()
    let selectedId = configuration.memo?.id
    let memo = selectedId.flatMap { data.memo(id: $0) }
    return MemoEntry(date: Date(), memo: memo, hasSelection: selectedId != nil)
  }
}

struct MemoWidgetEntryView: View {
  var entry: MemoEntry

  var body: some View {
    MemoDetailView(memo: entry.memo, hasSelection: entry.hasSelection)
      .widgetBackground(
        entry.memo == nil
          ? Color(.systemBackground)
          : Color.fromMemoARGB(entry.memo?.color)
      )
      // 點擊 Widget 回 App 並切到備忘錄分頁。
      .widgetURL(URL(string: "syncnest://memo"))
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
    AppIntentConfiguration(kind: kind, intent: SelectMemoIntent.self, provider: MemoProvider()) { entry in
      MemoWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("SyncNest 備忘錄")
    .description("選擇要顯示的備忘錄;可放多個各顯示不同備忘錄。")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
