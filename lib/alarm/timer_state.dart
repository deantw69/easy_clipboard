import 'package:cloud_firestore/cloud_firestore.dart';

/// 計時器狀態。共用於所有裝置,儲存在 Firestore 的 `timers/{timerId}` document。
///
/// 設計重點:雲端只存「絕對到期時間 [deadline]」與「這輪長度 [durationSeconds]」,
/// 而不是每秒倒數的數字。每台裝置讀到後各自在本地算剩餘秒數並排程通知。
///
/// 暫停:時鐘會持續走,所以暫停時不能存 deadline,改存「凍結的剩餘秒數」
/// [pausedSeconds];恢復時各裝置以 `now + pausedSeconds` 重算 deadline。
enum TimerStatus { idle, running, paused }

class TimerState {
  const TimerState({
    required this.durationSeconds,
    required this.deadline,
    required this.status,
    this.pausedSeconds = 0,
    this.label = '',
    this.updatedBy = '',
    this.lastFiredAt,
  });

  /// 這輪倒數的長度(秒)。供「啟動下一次」沿用,即使目前 idle 也保留。
  final int durationSeconds;

  /// 絕對到期時間。null 表示尚未啟動(idle)或暫停中(paused)。
  final DateTime? deadline;

  final TimerStatus status;

  /// 暫停時凍結的剩餘秒數(僅 [TimerStatus.paused] 有意義)。
  final int pausedSeconds;

  /// 計時器名稱(選填)。
  final String label;

  /// 最後更新的裝置代號(方便除錯/顯示)。
  final String updatedBy;

  /// 上一次「時間到」的絕對時刻(跨裝置共用)。null 表示尚未響過。
  final DateTime? lastFiredAt;

  bool get isRunning => status == TimerStatus.running && deadline != null;

  bool get isPaused => status == TimerStatus.paused;

  /// 距離到期還剩多少(永不為負)。
  /// running 依 deadline 計算;paused 回傳凍結值;idle 回傳設定長度。
  Duration remaining(DateTime now) {
    switch (status) {
      case TimerStatus.running:
        if (deadline == null) return Duration(seconds: durationSeconds);
        final diff = deadline!.difference(now);
        return diff.isNegative ? Duration.zero : diff;
      case TimerStatus.paused:
        return Duration(seconds: pausedSeconds < 0 ? 0 : pausedSeconds);
      case TimerStatus.idle:
        return Duration(seconds: durationSeconds);
    }
  }

  /// 預設(尚無資料時的初始狀態):閒置、5 分鐘。
  factory TimerState.initial() => const TimerState(
        durationSeconds: 300,
        deadline: null,
        status: TimerStatus.idle,
      );

  factory TimerState.fromMap(Map<String, dynamic> data) {
    final ts = data['deadline'];
    final fired = data['lastFiredAt'];
    return TimerState(
      durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 300,
      deadline: ts is Timestamp ? ts.toDate() : null,
      status: _statusFromString(data['status'] as String?),
      pausedSeconds: (data['pausedSeconds'] as num?)?.toInt() ?? 0,
      label: (data['label'] as String?) ?? '',
      updatedBy: (data['updatedBy'] as String?) ?? '',
      lastFiredAt: fired is Timestamp ? fired.toDate() : null,
    );
  }

  static TimerStatus _statusFromString(String? s) {
    switch (s) {
      case 'running':
        return TimerStatus.running;
      case 'paused':
        return TimerStatus.paused;
      default:
        return TimerStatus.idle;
    }
  }

  static String statusToString(TimerStatus s) {
    switch (s) {
      case TimerStatus.running:
        return 'running';
      case TimerStatus.paused:
        return 'paused';
      case TimerStatus.idle:
        return 'idle';
    }
  }

  Map<String, dynamic> toMap() => {
        'durationSeconds': durationSeconds,
        'deadline': deadline == null ? null : Timestamp.fromDate(deadline!),
        'status': statusToString(status),
        'pausedSeconds': pausedSeconds,
        'label': label,
        'updatedBy': updatedBy,
        'lastFiredAt':
            lastFiredAt == null ? null : Timestamp.fromDate(lastFiredAt!),
      };

  TimerState copyWith({
    int? durationSeconds,
    DateTime? deadline,
    bool clearDeadline = false,
    TimerStatus? status,
    int? pausedSeconds,
    String? label,
    String? updatedBy,
    DateTime? lastFiredAt,
  }) {
    return TimerState(
      durationSeconds: durationSeconds ?? this.durationSeconds,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      status: status ?? this.status,
      pausedSeconds: pausedSeconds ?? this.pausedSeconds,
      label: label ?? this.label,
      updatedBy: updatedBy ?? this.updatedBy,
      lastFiredAt: lastFiredAt ?? this.lastFiredAt,
    );
  }
}
