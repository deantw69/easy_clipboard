import 'package:cloud_firestore/cloud_firestore.dart';

import 'timer_state.dart';

/// 封裝對 Firestore 中單一共用計時器 document 的讀寫與即時監聽。
///
/// 現階段使用固定的 [timerId]("shared"),所有裝置共用同一筆。
/// 未來擴充多使用者時,只需把 collection 改為 `users/{uid}/timers` 並傳入動態 id。
class TimerRepository {
  TimerRepository({
    FirebaseFirestore? firestore,
    this.timerId = 'shared',
    required this.deviceId,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String timerId;

  /// 本裝置代號,寫入 updatedBy 方便辨識來源。
  final String deviceId;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('timers').doc(timerId);

  /// 即時監聽共用狀態。document 不存在時回傳初始狀態。
  ///
  /// 一併回傳 [fromCache]:該筆 snapshot 是否來自本機快取(尚未經伺服器確認)。
  /// 開機 / 重連時 Firestore 會先吐快取的舊狀態、稍後才送伺服器最新狀態,
  /// 呼叫端可據此避免對「快取舊狀態」誤觸發響鈴 / 通知(見 home_page `_onState`)。
  Stream<({TimerState state, bool fromCache})> watch() {
    return _doc.snapshots().map((snap) {
      final data = snap.data();
      final state = data == null ? TimerState.initial() : TimerState.fromMap(data);
      return (state: state, fromCache: snap.metadata.isFromCache);
    });
  }

  /// 設定倒數長度(秒),維持閒置狀態、清除既有到期時間。
  Future<void> setDuration(int seconds) async {
    await _doc.set({
      'durationSeconds': seconds < 0 ? 0 : seconds,
      'deadline': null,
      'status': 'idle',
      'pausedSeconds': 0,
      'updatedBy': deviceId,
    }, SetOptions(merge: true));
  }

  /// 啟動(或啟動下一次):以伺服器時間 + 長度 算出絕對到期時間。
  ///
  /// 用 [FieldValue.serverTimestamp] 寫入啟動時刻再加 [durationSeconds],
  /// 避免各裝置時鐘不同步造成的偏差 — 這裡用兩步:先讀長度,再寫 deadline。
  Future<void> start({int? durationSeconds}) async {
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(_doc);
      final current =
          snap.data() == null ? TimerState.initial() : TimerState.fromMap(snap.data()!);
      final seconds = durationSeconds ?? current.durationSeconds;
      // 以客戶端時間計算 deadline。為降低時鐘偏差影響,deadline 是絕對時間,
      // 所有裝置依此倒數;輕微偏差(數百毫秒)對倒數計時可接受。
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      tx.set(
        _doc,
        {
          'durationSeconds': seconds,
          'deadline': Timestamp.fromDate(deadline),
          'status': 'running',
          'pausedSeconds': 0,
          'updatedBy': deviceId,
        },
        SetOptions(merge: true),
      );
    });
  }

  /// 暫停:記下目前剩餘秒數、清除 deadline(時鐘會持續走故不能留 deadline)。
  Future<void> pause() async {
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(_doc);
      if (snap.data() == null) return;
      final current = TimerState.fromMap(snap.data()!);
      if (!current.isRunning) return; // 只有倒數中才可暫停
      final remaining = current.remaining(DateTime.now()).inSeconds;
      tx.set(
        _doc,
        {
          'deadline': null,
          'status': 'paused',
          'pausedSeconds': remaining,
          'updatedBy': deviceId,
        },
        SetOptions(merge: true),
      );
    });
  }

  /// 恢復:以 `now + 凍結剩餘秒數` 重算 deadline,回到倒數中。
  Future<void> resume() async {
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(_doc);
      if (snap.data() == null) return;
      final current = TimerState.fromMap(snap.data()!);
      if (!current.isPaused) return;
      final deadline =
          DateTime.now().add(Duration(seconds: current.pausedSeconds));
      tx.set(
        _doc,
        {
          'deadline': Timestamp.fromDate(deadline),
          'status': 'running',
          'pausedSeconds': 0,
          'updatedBy': deviceId,
        },
        SetOptions(merge: true),
      );
    });
  }

  /// 加 / 減時間([delta] 秒,可為負)。依狀態作用:
  ///   - running:平移 deadline(下限為「現在」,即剩餘不低於 0)。
  ///   - paused :加減凍結剩餘秒數(下限 0)。
  ///   - idle   :加減預設倒數長度(下限 0)。
  Future<void> addSeconds(int delta) async {
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(_doc);
      final current = snap.data() == null
          ? TimerState.initial()
          : TimerState.fromMap(snap.data()!);
      final now = DateTime.now();

      switch (current.status) {
        case TimerStatus.running:
          if (current.deadline == null) return;
          var newDeadline = current.deadline!.add(Duration(seconds: delta));
          if (newDeadline.isBefore(now)) newDeadline = now; // 不低於 0
          tx.set(
            _doc,
            {
              'deadline': Timestamp.fromDate(newDeadline),
              'updatedBy': deviceId,
            },
            SetOptions(merge: true),
          );
          break;
        case TimerStatus.paused:
          final next = current.pausedSeconds + delta;
          tx.set(
            _doc,
            {
              'pausedSeconds': next < 0 ? 0 : next,
              'updatedBy': deviceId,
            },
            SetOptions(merge: true),
          );
          break;
        case TimerStatus.idle:
          final next = current.durationSeconds + delta;
          tx.set(
            _doc,
            {
              'durationSeconds': next < 0 ? 0 : next,
              'updatedBy': deviceId,
            },
            SetOptions(merge: true),
          );
          break;
      }
    });
  }

  /// 記錄「上次時間到」的時刻(跨裝置共用)。各裝置響鈴時皆會呼叫,
  /// 但寫入的是同一個 deadline 絕對時間,故為冪等;若雲端已是同值則略過避免多餘寫入。
  Future<void> recordFired(DateTime firedAt) async {
    final snap = await _doc.get();
    final current = snap.data();
    if (current != null) {
      final existing = current['lastFiredAt'];
      if (existing is Timestamp &&
          existing.toDate().isAtSameMomentAs(firedAt)) {
        return; // 已記錄相同時刻,不重複寫
      }
    }
    await _doc.set({
      'lastFiredAt': Timestamp.fromDate(firedAt),
      'updatedBy': deviceId,
    }, SetOptions(merge: true));
  }

  /// 停止 / 重設:回到閒置,清除到期時間(保留長度供下次使用)。
  Future<void> stop() async {
    await _doc.set({
      'deadline': null,
      'status': 'idle',
      'pausedSeconds': 0,
      'updatedBy': deviceId,
    }, SetOptions(merge: true));
  }
}
