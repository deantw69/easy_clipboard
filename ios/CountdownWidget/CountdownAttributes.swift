import ActivityKit
import Foundation

/// Live Activity 的資料定義。
///
/// 這個檔案會同時被「Runner App」與「CountdownWidget Extension」兩個 target 編譯,
/// 因此 App 端啟動 Activity 與 Widget 端繪製畫面共用同一份型別。
///
/// 設計重點:動態的 [ContentState] 只放「絕對到期時間 deadline」與名稱,
/// 倒數的數字交給 SwiftUI 的 `Text(timerInterval:)` 由系統每秒自動更新,
/// App 不需要每秒推播 —— 與內建計時器 App 行為一致,也符合「免維護」原則。
@available(iOS 16.1, *)
struct CountdownAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 絕對到期時間。倒數中時 SwiftUI 依此自動倒數。
        var deadline: Date
        /// 計時器名稱(可為空字串)。
        var label: String
        /// 是否暫停中。暫停時不自動倒數,改顯示 [remainingSeconds] 的靜止時間。
        var isPaused: Bool
        /// 暫停時凍結的剩餘秒數(僅 isPaused 時有意義)。
        var remainingSeconds: Double
        /// 是否為「閒置/已停止」過渡態:只在「時間到後別台同步來的 idle、本機又在背景」
        /// 時用來把 Activity 保持 .active(顯示空白),好讓下一輪 running 能背景 update
        /// 貼出(背景無法 request 新 Activity)。畫面不顯示倒數也不顯示時間到。
        var isIdle: Bool = false
    }

    /// 固定屬性(本 App 不變),保留欄位供未來擴充。
    var timerName: String
}
