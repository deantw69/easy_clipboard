import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// 封裝 ActivityKit:啟動 / 更新 / 結束倒數計時的 Live Activity(動態島)。
///
/// 只在 iOS 16.1+ 且使用者開啟「即時動態」時運作;其餘情況皆為安全的 no-op。
/// 倒數中由 Widget 端用 `Text(timerInterval:)` 自動刷新;暫停時改顯示靜止的
/// 剩餘時間。本類別只在狀態變更時被呼叫,不需每秒更新。
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    /// 本 App 是否能使用 Live Activity(系統版本 + 使用者設定)。
    var isSupported: Bool {
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    /// 啟動或更新倒數 Live Activity。
    /// - 已有進行中的 Activity → 就地更新(不閃爍)。
    /// - 沒有 → 啟動新的。
    /// - isPaused=true 時暫停自動倒數,顯示 remainingSeconds 的靜止時間。
    func apply(deadline: Date, isPaused: Bool, remainingSeconds: Double, label: String, isIdle: Bool = false) {
        guard #available(iOS 16.1, *), isSupported else { return }

        let state = CountdownAttributes.ContentState(
            deadline: deadline,
            label: label,
            isPaused: isPaused,
            remainingSeconds: remainingSeconds,
            isIdle: isIdle)
        // 暫停 / 已到期(時間到)/ 閒置過渡態 都不設 staleDate:避免被系統判定過期而自動
        // 消失 —— 這些狀態要持續顯示直到使用者停止 / 下一輪。倒數中才設為 deadline,讓
        // 系統在到期瞬間自動重繪成「時間到」。
        let staleDate: Date? = (isPaused || isIdle || deadline <= Date()) ? nil : deadline

        // 只把「仍在顯示中(active)」的 Activity 視為可更新對象。
        // 已淡出結束(ended/dismissed)的 Activity 會殘留在 activities 清單裡,
        // 若誤拿它去 update 會悄悄沒反應 → 新一輪倒數貼不出來(間歇性「動態島不顯示」)。
        let liveActivity = Activity<CountdownAttributes>.activities
            .first { $0.activityState == .active }

        // 閒置過渡態:只「就地更新」既有的 active Activity 以保住它(供下一輪背景 update),
        // 沒有就不新建(閒置不該主動冒出一張卡)。
        if isIdle {
            if let activity = liveActivity {
                Task {
                    if #available(iOS 16.2, *) {
                        await activity.update(ActivityContent(state: state, staleDate: nil))
                    } else {
                        await activity.update(using: state)
                    }
                }
            }
            return
        }

        if let activity = liveActivity {
            Task {
                if #available(iOS 16.2, *) {
                    await activity.update(ActivityContent(state: state, staleDate: staleDate))
                } else {
                    await activity.update(using: state)
                }
            }
        } else {
            // 先清掉殘留的非 active Activity,避免殭屍堆疊或下次又撈到它。
            for stale in Activity<CountdownAttributes>.activities {
                Task { await stale.end(dismissalPolicy: .immediate) }
            }
            let attributes = CountdownAttributes(timerName: label.isEmpty ? "倒數計時" : label)
            do {
                if #available(iOS 16.2, *) {
                    let content = ActivityContent(state: state, staleDate: staleDate)
                    _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                } else {
                    _ = try Activity.request(attributes: attributes, contentState: state, pushType: nil)
                }
            } catch {
                NSLog("LiveActivity apply failed: \(error.localizedDescription)")
            }
        }
    }

    /// 結束所有倒數 Live Activity。
    /// - immediate=true:手動「停止」,立即從畫面移除。
    /// - immediate=false:倒數歸零,先更新為已到期顯示「時間到」後由系統淡出。
    func end(immediate: Bool) {
        guard #available(iOS 16.1, *) else { return }
        if immediate {
            endAll(dismiss: .immediate, markDone: false)
        } else {
            endAll(dismiss: .default, markDone: true)
        }
    }

    // MARK: - Private

    @available(iOS 16.1, *)
    private func endAll(dismiss policy: ActivityUIDismissalPolicy, markDone: Bool) {
        for activity in Activity<CountdownAttributes>.activities {
            Task {
                if markDone {
                    // 把 deadline 拉到「現在」、解除暫停,Widget 立即判定為已到期 → 顯示「時間到」。
                    let done = CountdownAttributes.ContentState(
                        deadline: Date(),
                        label: activity.attributes.timerName,
                        isPaused: false,
                        remainingSeconds: 0)
                    if #available(iOS 16.2, *) {
                        await activity.update(ActivityContent(state: done, staleDate: nil))
                    } else {
                        await activity.update(using: done)
                    }
                }
                await activity.end(dismissalPolicy: policy)
            }
        }
    }
}
