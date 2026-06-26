import Flutter
import Foundation

/// Flutter ↔ 原生的 MethodChannel,轉接到 [LiveActivityManager]。
///
/// 方法:
///   - `isSupported` → Bool
///   - `apply` { isPaused: Bool, isIdle: Bool, deadlineMs: Int?, remainingSeconds: Int, label: String }
///   - `end`   { immediate: Bool }
enum LiveActivityChannel {
    static let name = "easy_clipboard/live_activity"

    static func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "isSupported":
                result(LiveActivityManager.shared.isSupported)

            case "apply":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "bad_args", message: "缺少參數", details: nil))
                    return
                }
                let isPaused = (args["isPaused"] as? Bool) ?? false
                let isIdle = (args["isIdle"] as? Bool) ?? false
                let label = (args["label"] as? String) ?? ""
                let remaining = (args["remainingSeconds"] as? NSNumber)?.doubleValue ?? 0
                // 倒數中用傳入的 deadline;暫停時 deadline 為 nil,以 now + 剩餘秒數補上。
                let deadline: Date
                if let ms = (args["deadlineMs"] as? NSNumber)?.doubleValue {
                    deadline = Date(timeIntervalSince1970: ms / 1000.0)
                } else {
                    deadline = Date().addingTimeInterval(remaining)
                }
                LiveActivityManager.shared.apply(
                    deadline: deadline,
                    isPaused: isPaused,
                    remainingSeconds: remaining,
                    label: label,
                    isIdle: isIdle)
                result(nil)

            case "end":
                let args = call.arguments as? [String: Any]
                let immediate = (args?["immediate"] as? Bool) ?? true
                LiveActivityManager.shared.end(immediate: immediate)
                result(nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}
