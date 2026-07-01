import SwiftUI
import WidgetKit

/// 釘選備忘錄:標題 + 待辦清單(未勾選優先,尺寸越大顯示越多)。所有尺寸共用。
struct PinnedMemoView: View {
  @Environment(\.widgetFamily) var family
  let memo: MemoSummary?

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

      VStack(alignment: .leading, spacing: 6) {
        // 標題列:圖釘 + 備忘錄本文首行(可能為空)。
        HStack(spacing: 4) {
          Image(systemName: "pin.fill")
            .font(.system(size: 11))
            .foregroundColor(.black.opacity(0.5))
          Text(memo.title.isEmpty ? "釘選備忘錄" : memo.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.black.opacity(0.85))
            .lineLimit(family == .systemSmall ? 1 : 2)
          Spacer(minLength: 0)
        }

        if shown.isEmpty && memo.title.isEmpty {
          Spacer(minLength: 0)
          Text("(空白備忘錄)")
            .font(.system(size: 12))
            .foregroundColor(.black.opacity(0.4))
          Spacer(minLength: 0)
        } else {
          VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, todo in
              TodoRow(todo: todo)
            }
            if overflow > 0 {
              Text("+\(overflow) 項")
                .font(.system(size: 11))
                .foregroundColor(.black.opacity(0.45))
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

/// 單列待辦:勾選框 + 文字(已完成加刪除線並淡化)。
private struct TodoRow: View {
  let todo: MemoTodoItem

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: todo.done ? "checkmark.square.fill" : "square")
        .font(.system(size: 13))
        .foregroundColor(.black.opacity(todo.done ? 0.4 : 0.65))
      Text(todo.text.isEmpty ? "—" : todo.text)
        .font(.system(size: 13))
        .strikethrough(todo.done, color: .black.opacity(0.4))
        .foregroundColor(.black.opacity(todo.done ? 0.4 : 0.8))
        .lineLimit(1)
      Spacer(minLength: 0)
    }
  }
}
