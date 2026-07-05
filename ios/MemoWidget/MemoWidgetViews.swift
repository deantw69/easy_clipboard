import SwiftUI
import WidgetKit

/// 顯示所選備忘錄:標題 + 待辦清單(未勾選優先,尺寸越大顯示越多)。所有尺寸共用。
struct MemoDetailView: View {
  @Environment(\.widgetFamily) var family
  let memo: MemoSummary?
  /// 是否已選過備忘錄(區分「尚未選」與「所選已被刪除」)。
  let hasSelection: Bool

  /// 各尺寸最多顯示幾列待辦(小型還要留標題空間,故較少)。
  private var maxTodos: Int {
    switch family {
    case .systemSmall: return 4
    case .systemMedium: return 5
    case .systemLarge: return 13
    default: return 4
    }
  }

  var body: some View {
    if let memo = memo {
      let ordered = memo.orderedTodos
      let shown = Array(ordered.prefix(maxTodos))
      let overflow = ordered.count - shown.count
      let fg = Color.memoForeground(memo.color)

      VStack(alignment: .leading, spacing: 6) {
        Text(memo.title.isEmpty ? "(無標題備忘錄)" : memo.title)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(fg.opacity(memo.title.isEmpty ? 0.4 : 0.85))
          .lineLimit(family == .systemSmall ? 1 : 2)

        if shown.isEmpty {
          Spacer(minLength: 0)
          Text("(沒有待辦項目)")
            .font(.system(size: 12))
            .foregroundColor(fg.opacity(0.4))
          Spacer(minLength: 0)
        } else {
          VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, todo in
              TodoRow(todo: todo, fg: fg)
            }
            if overflow > 0 {
              Text("+\(overflow) 項")
                .font(.system(size: 11))
                .foregroundColor(fg.opacity(0.45))
                .padding(.leading, 20)
                .padding(.top, 1)
            }
          }
          Spacer(minLength: 0)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      EmptyStateView(hasSelection: hasSelection)
    }
  }
}

/// 未選備忘錄 / 所選已刪除時的提示。
private struct EmptyStateView: View {
  let hasSelection: Bool

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: hasSelection ? "exclamationmark.triangle" : "hand.tap")
        .font(.system(size: 20))
        .foregroundColor(.secondary)
      Text(hasSelection ? "備忘錄已不存在" : "長按小工具→編輯,選擇備忘錄")
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// 單列待辦:勾選框 + 文字(已完成加刪除線並淡化)。
private struct TodoRow: View {
  let todo: MemoTodoItem
  /// 依底色亮度決定的前景基底色(黑或白)。
  let fg: Color

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: todo.done ? "checkmark.square.fill" : "square")
        .font(.system(size: 13))
        .foregroundColor(fg.opacity(todo.done ? 0.4 : 0.65))
      Text(todo.text.isEmpty ? "—" : todo.text)
        .font(.system(size: 13))
        .strikethrough(todo.done, color: fg.opacity(0.4))
        .foregroundColor(fg.opacity(todo.done ? 0.4 : 0.8))
        .lineLimit(1)
      Spacer(minLength: 0)
    }
  }
}
