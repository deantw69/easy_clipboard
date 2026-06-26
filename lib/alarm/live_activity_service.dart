import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 倒數計時的 iOS Live Activity(動態島)橋接。
///
/// 只在 iOS 有效;其他平台所有方法皆為安全的 no-op。
/// 倒數中由 SwiftUI 的 `Text(timerInterval:)` 自動每秒刷新;暫停時改顯示
/// 凍結的剩餘時間 + 暫停標記。因此只需在「狀態變更」時呼叫 [apply]/[end],
/// 不必每秒更新。
class LiveActivityService {
  LiveActivityService();

  static const MethodChannel _channel =
      MethodChannel('easy_clipboard/live_activity');

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 此裝置是否支援 Live Activity(iOS 16.1+ 且使用者已開啟即時動態)。
  Future<bool> isSupported() async {
    if (!_isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 啟動或更新動態島。
  /// - [isPaused] false:倒數中,以 [deadline] 自動倒數。
  /// - [isPaused] true :暫停,顯示靜止的 [remainingSeconds] + 暫停標記。
  ///
  /// 若已有 Activity 則就地更新(不閃爍),否則啟動新的。
  Future<void> apply({
    required bool isPaused,
    DateTime? deadline,
    required int remainingSeconds,
    String label = '',
  }) async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('apply', {
        'isPaused': isPaused,
        'deadlineMs': deadline?.millisecondsSinceEpoch,
        'remainingSeconds': remainingSeconds,
        'label': label,
      });
    } catch (_) {
      // 使用者關閉即時動態或系統不支援時忽略。
    }
  }

  /// 閒置過渡態:把既有的動態島「就地更新成空白並保持存活」,但**不主動新建**。
  /// 僅用於「時間到後別台同步來的 idle、本機又在背景」——背景無法 `Activity.request`
  /// 新建,但可以 `update`;先把這張卡保住,下一輪 running 進來就能背景 update 貼出
  /// 新倒數。若當下沒有存活中的 Activity 則為 no-op(閒置不該主動冒出一張卡)。
  Future<void> applyIdle({String label = ''}) async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('apply', {
        'isPaused': false,
        'isIdle': true,
        'deadlineMs': null,
        'remainingSeconds': 0,
        'label': label,
      });
    } catch (_) {}
  }

  /// 結束動態島(移除)。停止 / 重設時呼叫,DI 與鎖定畫面卡片一起消失。
  /// 不短路:即使先前已顯示「時間到」,也要能確實清掉(原生 endAll 會遍歷
  /// activities,沒有就 no-op,安全)。
  Future<void> end({required bool immediate}) async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('end', {'immediate': immediate});
    } catch (_) {}
  }
}
