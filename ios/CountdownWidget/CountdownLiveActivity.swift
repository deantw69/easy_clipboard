import ActivityKit
import SwiftUI
import WidgetKit

/// 倒數計時的 Live Activity / 動態島畫面。
///
/// - 動態島(iPhone 14 Pro 以上):compact / minimal / expanded 三種樣態。
/// - 其他 iPhone:顯示於鎖定畫面與通知中心(同一份 lock screen 畫面)。
///
/// 倒數數字一律用 `Text(timerInterval:countsDown:)`,由系統自動每秒刷新;
/// 到期後(now >= deadline,或 Activity 變 stale)改顯示「時間到」。
@available(iOS 16.1, *)
struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownAttributes.self) { context in
            // 鎖定畫面 / 橫幅。
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // 展開區:系統忽略 .widgetURL,必須用 Link 才能點擊回 App(切鬧鐘分頁)。
                DynamicIslandExpandedRegion(.leading) {
                    Link(destination: URL(string: "syncnest://alarm")!) {
                        Label {
                            Text(context.state.label.isEmpty ? "倒數計時" : context.state.label)
                                .font(.headline)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "timer")
                                .foregroundStyle(.cyan)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Link(destination: URL(string: "syncnest://alarm")!) {
                        countdownText(context, font: .system(size: 30, weight: .semibold))
                            .frame(maxWidth: 110)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Link(destination: URL(string: "syncnest://alarm")!) {
                        Text(statusLine(context))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                // 固定窄寬度:running / paused、長短倒數都一致,無多餘空白。
                // Text(timerInterval:) 會為最壞情況預留寬度,故不用 maxWidth(會撐很寬),
                // 改用剛好容納 M:SS / MM:SS 的固定寬;H:MM:SS 由 minimumScaleFactor 稍微縮小。
                countdownText(context, font: .system(size: 13, weight: .semibold))
                    .frame(width: 42)
            } minimal: {
                Group {
                    if context.state.isIdle {
                        Image(systemName: "timer")
                            .foregroundStyle(.secondary)
                    } else if isDone(context) {
                        Image(systemName: "timer")
                            .foregroundStyle(.cyan)
                    } else if context.state.isPaused {
                        Image(systemName: "pause.fill")
                            .foregroundStyle(.cyan)
                    } else {
                        countdownText(context, font: .system(size: 13, weight: .semibold))
                            .frame(maxWidth: 44)
                    }
                }
            }
            // compact/minimal 的深連結必須套在 DynamicIsland 實例這層(非各子 view 內),
            // 才會生效;展開區另用 Link(見上)。
            .widgetURL(URL(string: "syncnest://alarm"))
            .keylineTint(.cyan)
        }
    }
}

/// 鎖定畫面 / 通知中心的版面。
@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<CountdownAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 34))
                .foregroundStyle(.cyan)
            // 標題:倒數中 / 已暫停 / 時間到。
            Text(titleText(context))
                .font(.headline)
                .lineLimit(1)
            Spacer()
            // 時間到 / 閒置只顯示 icon(不顯示數字);倒數中 / 暫停才顯示時間。
            if !isDone(context) && !context.state.isIdle {
                if context.state.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                countdownText(context, font: .system(size: 38, weight: .bold))
            }
        }
        .padding(16)
        // 點鎖定畫面 / 通知中心橫幅回 App 切鬧鐘分頁。
        .widgetURL(URL(string: "syncnest://alarm"))
    }
}

/// 鎖定畫面 / 展開的標題文字。
@available(iOS 16.1, *)
private func titleText(_ context: ActivityViewContext<CountdownAttributes>) -> String {
    if context.state.isIdle { return "" }
    if isDone(context) { return "時間到" }
    if context.state.isPaused { return "已暫停" }
    return "倒數中"
}

/// 是否已到期(暫停中不算到期)。staleDate 設為 deadline,系統會在到期瞬間
/// 重繪;此時 deadline <= now 成立,即視為結束。
@available(iOS 16.1, *)
private func isDone(_ context: ActivityViewContext<CountdownAttributes>) -> Bool {
    !context.state.isPaused && context.state.deadline <= Date()
}

/// 狀態說明文字。
@available(iOS 16.1, *)
private func statusLine(_ context: ActivityViewContext<CountdownAttributes>) -> String {
    if context.state.isIdle { return "" }
    if context.state.isPaused { return "已暫停" }
    return isDone(context) ? "倒數計時結束" : "倒數中…"
}

/// 倒數文字:
///   - 暫停中:顯示凍結的剩餘時間(靜止)。
///   - 已到期:顯示「時間到」。
///   - 倒數中:用系統自動倒數。
@available(iOS 16.1, *)
@ViewBuilder
private func countdownText(
    _ context: ActivityViewContext<CountdownAttributes>,
    font: Font
) -> some View {
    if context.state.isIdle {
        // 閒置過渡態:不顯示任何時間(卡片僅為了保住 Activity 供下一輪 update)。
        EmptyView()
    } else if context.state.isPaused {
        Text(formatRemaining(context.state.remainingSeconds))
            .font(font)
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    } else if isDone(context) {
        Text("時間到")
            .font(font)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    } else {
        Text(timerInterval: Date()...context.state.deadline, countsDown: true)
            .font(font)
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .multilineTextAlignment(.trailing)
    }
}

/// 將剩餘秒數格式化為 H:MM:SS(未滿一小時則 M:SS),供暫停時靜止顯示。
private func formatRemaining(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
}
