import SwiftUI
import WidgetKit

/// Widget Extension 進入點。本 App 只用 Live Activity(動態島),
/// 不含主畫面 Home Screen widget。
@main
struct CountdownWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            CountdownLiveActivity()
        }
    }
}
