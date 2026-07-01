import SwiftUI
import WidgetKit

/// 小尺寸:單張釘選備忘錄。
struct PinnedMemoView: View {
  let memo: MemoSummary?

  var body: some View {
    if let memo = memo {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 4) {
          Image(systemName: "pin.fill")
            .font(.system(size: 11))
            .foregroundColor(.black.opacity(0.5))
          Text("釘選")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.black.opacity(0.5))
          Spacer()
        }
        Text(memo.title)
          .font(.system(size: 15, weight: .medium))
          .foregroundColor(.black.opacity(0.85))
          .lineLimit(4)
        Spacer(minLength: 0)
        if memo.todoCount > 0 {
          Text("待辦 \(memo.doneCount)/\(memo.todoCount)")
            .font(.system(size: 11))
            .foregroundColor(.black.opacity(0.55))
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      VStack(spacing: 6) {
        Image(systemName: "pin.slash")
          .font(.system(size: 20))
          .foregroundColor(.secondary)
        Text("尚未釘選備忘錄")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

/// 中/大尺寸:最近幾筆備忘錄清單。
struct RecentMemoListView: View {
  @Environment(\.widgetFamily) var family
  let data: MemoWidgetData

  private var maxRows: Int { family == .systemLarge ? 6 : 3 }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("SyncNest 備忘錄")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.primary)
        Spacer()
      }
      .padding(.bottom, 6)

      if data.recent.isEmpty {
        Spacer()
        Text("目前沒有備忘錄")
          .font(.system(size: 13))
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
        Spacer()
      } else {
        ForEach(Array(data.recent.prefix(maxRows).enumerated()), id: \.offset) { _, memo in
          HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
              .fill(Color.fromMemoARGB(memo.color))
              .frame(width: 4, height: 22)
            Text(memo.title)
              .font(.system(size: 13))
              .foregroundColor(.primary)
              .lineLimit(1)
            Spacer(minLength: 0)
            if memo.todoCount > 0 {
              Text("\(memo.doneCount)/\(memo.todoCount)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
          }
          .padding(.vertical, 5)
        }
        Spacer(minLength: 0)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
