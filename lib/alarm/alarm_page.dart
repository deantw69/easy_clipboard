import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/desktop_tray_service.dart';
import 'alarm_group.dart';
import 'alarm_services.dart';
import 'duration_picker.dart';
import 'timer_state.dart';

/// 鬧鐘分頁:顯示跨裝置共用倒數、設定時間、啟動 / 暫停 / 停止。
/// 服務(Firestore / 通知 / 響鈴 / 動態島 / 選單列)由 [AlarmServices] Provider 提供。
class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> with WidgetsBindingObserver {
  late final AlarmServices _services;

  StreamSubscription<({TimerState state, bool fromCache})>? _sub;
  Timer? _ticker;

  TimerState _state = TimerState.initial();

  /// 記住上一次見到的 deadline,用來判斷是否需要重排通知。
  DateTime? _scheduledFor;

  /// 本輪是否已觸發前景「時間到」通知,避免重複。
  bool _firedThisRound = false;

  /// 停止鈕處理中(等 Firestore 寫入):禁用按鈕、顯示 loading,防重複點擊。
  bool _stopping = false;

  /// 用於顯示的「現在時間」,每秒更新。
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _services = context.read<AlarmServices>();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
    AlarmGroup.instance.addListener(_onGroupChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  /// 訂閱目前群組代碼對應的 Firestore document。
  void _subscribe() {
    _sub = _services.repository
        .watch()
        .listen((e) => _onState(e.state, fromCache: e.fromCache));
  }

  /// 群組代碼變更:切到新 document、重訂閱、清掉舊群組的殘留(避免舊倒數的鈴/通知還響)。
  Future<void> _onGroupChanged() async {
    _services.repository.setTimerId(AlarmGroup.instance.code);
    await _sub?.cancel();
    // 取消舊群組殘留的排程通知 / 響鈴 / 動態島,並重置本輪觸發旗標。
    await _services.notifications.cancelAll();
    await _services.alarm.stop();
    await _services.liveActivity.end(immediate: true);
    _scheduledFor = null;
    _firedThisRound = false;
    if (mounted) setState(() => _state = TimerState.initial());
    _subscribe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AlarmGroup.instance.removeListener(_onGroupChanged);
    _sub?.cancel();
    _ticker?.cancel();
    // alarm / menuBar 為 App 生命週期共用單例(Provider 持有),此處不 dispose。
    super.dispose();
  }

  /// 回到前景時重新同步 Live Activity。
  /// iOS 的 Live Activity 只能在 App 前景 active 時「啟動」(`Activity.request`),
  /// App 啟動瞬間 / 背景時收到的狀態變更可能起動失敗;前景復帰時補貼一次,
  /// 確保動態島不會因為時機而漏顯示(其他平台 no-op)。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncLiveActivity(_state, DateTime.now());
    }
  }

  /// Firestore 狀態變更:更新畫面、重排本地通知、同步動態島。
  ///
  /// [fromCache] 為 true 表示此筆來自本機快取、尚未經伺服器確認。開機 / 重連時
  /// Firestore 會先送快取的「舊狀態」(可能是關機前那輪 running、deadline 已過),
  /// 不可據此觸發響鈴 / 通知 —— 等伺服器確認的最新狀態到了再決定(見下方觸發守衛)。
  Future<void> _onState(TimerState state, {bool fromCache = false}) async {
    // 只有「倒數中」才有需要排程通知的有效 deadline(暫停/閒置皆視為無)。
    final prevDeadline =
        _state.status == TimerStatus.running ? _state.deadline : null;
    // 進來前是否正顯示「時間到」(running 且 deadline 已過)。用來判斷:若緊接著
    // 收到別台同步來的 idle,很可能是要開「下一輪」——此時若本機在背景,保住 Activity
    // 走 update(背景無法 request 新的),見下方 _syncLiveActivity 的 keepIdleActive。
    final wasShowingDone = _state.status == TimerStatus.running &&
        _state.deadline != null &&
        !_state.deadline!.isAfter(DateTime.now());
    setState(() => _state = state);
    _updateMenuBar();

    // 回到閒置(任一裝置按停止/重設)→ 先立即停止響鈴。放在最前面,
    // 不要排在 notifications.cancelAll() 之後 —— 那個 await 在某些平台(macOS)
    // 若變慢或拋例外,會讓後面的 alarm.stop() 沒被執行,造成響鈴停不掉(殘響)。
    if (state.status == TimerStatus.idle) {
      await _services.alarm.stop();
    }

    final now = DateTime.now();
    final newDeadline =
        state.status == TimerStatus.running ? state.deadline : null;

    // deadline 變了(暫停 / 停止 / 加減時間 / 重新啟動)→ 取消舊的、視情況排新的。
    if (newDeadline != prevDeadline || newDeadline != _scheduledFor) {
      await _services.notifications.cancelAll();
      _scheduledFor = null;
      _firedThisRound = false;

      if (newDeadline != null) {
        // 新的倒數 deadline → 先停掉上一輪可能還在響的鈴。
        await _services.alarm.stop();
        final ok = await _services.notifications.scheduleAt(newDeadline);
        if (ok) _scheduledFor = newDeadline;
      }
    }

    // 倒數中但此刻已過期(極短倒數 / 減時間到 0)→ 立即觸發響鈴。
    // 守衛(避免開機誤響/誤通知):
    //  - !fromCache:只在伺服器確認過的狀態才觸發。開機先到的快取舊狀態(關機前
    //    那輪 running、deadline 已過)不算數;真正的最新狀態(別裝置已停止/開新輪)
    //    隨後會以伺服器 snapshot 送達,屆時不會是「已過期」就不會誤觸發。
    //  - !_firedForDeadline:該 deadline 已被(任一裝置)響過(lastFiredAt 已記錄),
    //    不重複響 —— 例如別裝置早已響過、本機開機才同步到的那輪。
    if (state.status == TimerStatus.running &&
        !_firedThisRound &&
        !fromCache &&
        !_firedForDeadline(state) &&
        state.deadline != null &&
        !state.deadline!.isAfter(now)) {
      await _fireAlarm();
      return; // _fireAlarm 會處理動態島
    }

    // 「時間到 → 別台同步來的 idle」且本機在背景時,保住 Activity(改 update 空白卡)而非
    // end,讓緊接著的下一輪 running 能背景 update 貼出。前景時 request 可成功,照舊 end。
    final inForeground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final keepIdleActive = state.status == TimerStatus.idle &&
        wasShowingDone &&
        !inForeground;
    await _syncLiveActivity(state, now, keepIdleActive: keepIdleActive);
  }

  /// 依目前狀態同步 iOS 動態島(其他平台 no-op)。
  /// [keepIdleActive] 為 true 時,idle 不 end 而是保住既有 Activity(見 _onState)。
  Future<void> _syncLiveActivity(TimerState state, DateTime now,
      {bool keepIdleActive = false}) async {
    switch (state.status) {
      case TimerStatus.running:
        await _services.liveActivity.apply(
          isPaused: false,
          deadline: state.deadline,
          remainingSeconds: state.remaining(now).inSeconds,
          label: state.label,
        );
        break;
      case TimerStatus.paused:
        await _services.liveActivity.apply(
          isPaused: true,
          remainingSeconds: state.remaining(now).inSeconds,
          label: state.label,
        );
        break;
      case TimerStatus.idle:
        if (keepIdleActive) {
          await _services.liveActivity.applyIdle(label: state.label);
        } else {
          await _services.liveActivity.end(immediate: true);
        }
        break;
    }
  }

  /// 每秒 tick:更新顯示;若前景中倒數歸零,觸發響鈴 + 通知。
  Future<void> _onTick() async {
    setState(() => _now = DateTime.now());
    _updateMenuBar();

    if (_state.isRunning &&
        !_firedThisRound &&
        _state.deadline != null &&
        !_state.deadline!.isAfter(_now)) {
      await _fireAlarm();
    }
  }

  /// 更新 macOS 選單列文字(其他平台為 no-op)。
  void _updateMenuBar() {
    final remaining = _state.remaining(_now);
    String title;
    switch (_state.status) {
      case TimerStatus.running:
        title = remaining == Duration.zero ? '時間到' : _fmt(remaining);
        break;
      case TimerStatus.paused:
        title = '⏸ ${_fmt(remaining)}'; // 暫停標記 + 凍結剩餘時間
        break;
      case TimerStatus.idle:
        title = ''; // 閒置時只留圖示
        break;
    }
    _services.menuBar.setTitle(title);
  }

  /// 這個 [state] 的當前 deadline 是否已被(任一裝置)響過。
  /// `lastFiredAt` 跨裝置共用,記錄上次「時間到」的 deadline 絕對時刻;
  /// 若 lastFiredAt 已不早於目前 deadline,代表這一輪已經響過,不該再響。
  bool _firedForDeadline(TimerState state) {
    final fired = state.lastFiredAt;
    final deadline = state.deadline;
    if (fired == null || deadline == null) return false;
    return !fired.isBefore(deadline);
  }

  /// 時間到:播放響鈴(保證出聲)+ 顯示通知。
  ///
  /// 通知依平台分流,避免重複:
  ///  - **支援排程的平台(iOS / macOS / Android)**:時間到的通知由先前 [scheduleAt]
  ///    排的 OS 排程通知負責(App 在背景/被關掉也會照響)。這裡**不再** `showNow`——
  ///    背景已響過一次後,重開 App 時 Firestore 送回「running 且 deadline 已過」會
  ///    走到這裡,再 `showNow` 就會彈出第二個一模一樣的通知(使用者回報的重複通知)。
  ///    OS 排程通知已投遞,`cancelAll` 也無法取消它。
  ///  - **無排程能力的平台(Windows)**:沒有 OS 排程通知,必須在此 `showNow` 補上。
  Future<void> _fireAlarm() async {
    _firedThisRound = true;
    // 記錄「上次時間到」的時刻(用該輪 deadline 為準,跨裝置一致;極短倒數無 deadline 時退用現在)。
    await _services.repository.recordFired(_state.deadline ?? DateTime.now());
    if (!_services.notifications.supportsScheduling) {
      await _services.notifications.showNow();
      // Windows 等無背景排程的桌面平台:App 還在執行但視窗可能已縮到系統匣/最小化,
      // 到點把視窗叫回最前面(通知氣泡 + 響鈴已於上下觸發),確保使用者看得到。
      await DesktopTrayService.instance?.bringToForeground();
    }
    // 動態島 / 鎖定畫面顯示「時間到」並維持(deadline 已過 → widget 顯示時間到,
    // staleDate=nil 不會自動消失);直到使用者按停止才 end 移除。
    await _syncLiveActivity(_state, DateTime.now());
    // 開始響鈴前再確認:目前 _state 仍是「running 且 deadline 已過(就是這一輪到期)」。
    // 開機 / 開 App 時 Firestore 會先送快取的舊狀態(上一輪 running、deadline 已過)
    // 再送伺服器最新狀態,兩個 _onState 會交錯;若最新已是 idle(被停止)或已開始
    // 新一輪(deadline 在未來),都不可響鈴 —— 否則會在新計時中突然響起、或一直響
    // (新一輪也是 running,只檢查 status 會漏掉)。此檢查與 start 之間不留 await。
    final now = DateTime.now();
    if (_state.status != TimerStatus.running ||
        _state.deadline == null ||
        _state.deadline!.isAfter(now)) {
      return;
    }
    await _services.alarm.start();
  }

  /// 停止:先立即靜音(本機,不等 Firestore),再 await 同步停止狀態到其他裝置。
  /// 寫入期間禁用按鈕(`_stopping`)避免重複點擊;Firestore 失敗顯示 SnackBar。
  Future<void> _handleStop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    // 立即靜音(本機),不受下方 Firestore 寫入成敗影響。
    await _services.alarm.stop();
    try {
      await _services.repository.stop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('停止失敗,請確認網路後重試')),
        );
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// 格式化絕對時刻為「HH:mm:ss」;非今天則加上「M/D」前綴。
  String _fmtClock(DateTime t) {
    final local = t.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    final time = '$hh:$mm:$ss';
    final now = _now.toLocal();
    final sameDay =
        local.year == now.year && local.month == now.month && local.day == now.day;
    return sameDay ? time : '${local.month}/${local.day} $time';
  }

  /// 檢視 / 複製 / 變更群組代碼。相同代碼的裝置共用同一筆倒數。
  Future<void> _editGroupCode() async {
    final controller = TextEditingController(text: AlarmGroup.instance.code);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('群組代碼'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '在你的每台裝置輸入「相同代碼」即可共用同一個倒數;不同代碼互不影響。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '代碼',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: '複製',
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: controller.text));
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('已複製代碼')),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    if (saved != null) await AlarmGroup.instance.setCode(saved);
  }

  /// 啟動倒數。Windows 首次啟動時先跳一次性說明(需保持 App 執行才會提醒)。
  Future<void> _handleStart() async {
    await _maybeShowWindowsNotice();
    await _services.repository.start();
  }

  /// Windows 專屬一次性說明:提醒使用者本平台不支援 App 關閉後背景排程通知,
  /// 需保持執行(可縮到系統匣)才會到點提醒。旗標存 appSupport 只顯示一次。
  Future<void> _maybeShowWindowsNotice() async {
    if (!Platform.isWindows) return;
    File? flag;
    try {
      final dir = await getApplicationSupportDirectory();
      flag = File(p.join(dir.path, 'alarm_win_notice_shown'));
      if (await flag.exists()) return;
    } catch (_) {
      return; // 讀取失敗就不強跳,避免每次都彈。
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Windows 提醒說明'),
        content: const Text(
          'Windows 無法在 App 關閉後於背景排程通知。\n\n'
          '請讓 SyncNest 保持執行(可縮到系統匣),時間到才會跳通知、'
          '響鈴並自動把視窗叫回前景。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
    try {
      await flag.writeAsString('1');
    } catch (_) {}
  }

  Future<void> _pickDuration() async {
    final picked = await DurationPickerSheet.show(
      context,
      Duration(seconds: _state.durationSeconds),
    );
    if (picked != null) {
      await _services.repository.setDuration(picked.inSeconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _state.remaining(_now);
    final status = _state.status;
    final running = status == TimerStatus.running;

    // 深色模式把主要按鈕(啟動/暫停/繼續)壓暗一點,避免預設亮青在深色 UI 上過刺眼;
    // 連帶把文字改白確保壓暗底色後仍有對比。淺色模式維持預設(null)。
    final cs = Theme.of(context).colorScheme;
    final darkFilledStyle = Theme.of(context).brightness == Brightness.dark
        ? FilledButton.styleFrom(
            backgroundColor: Color.lerp(cs.primary, Colors.black, 0.28)!,
            foregroundColor: Colors.white,
          )
        : null;

    final String statusText;
    switch (status) {
      case TimerStatus.running:
        statusText = '倒數中…';
        break;
      case TimerStatus.paused:
        statusText = '已暫停';
        break;
      case TimerStatus.idle:
        statusText = remaining == Duration.zero ? '已歸零' : '已設定,待啟動';
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('鬧鐘'),
        actions: [
          IconButton(
            tooltip: '群組代碼',
            icon: const Icon(Icons.group_work_outlined),
            onPressed: _editGroupCode,
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 固定 72 大字;放大系統字級時用 FittedBox 縮放避免窄螢幕橫向破版。
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _fmt(remaining),
                  style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              statusText,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_state.updatedBy.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('最後操作:${_state.updatedBy}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            if (_state.lastFiredAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('上次時間到:${_fmtClock(_state.lastFiredAt!)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 32),
            // 加 / 減時間(倒數中、暫停、待啟動皆可用)。
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _services.repository.addSeconds(-60),
                  icon: const Icon(Icons.remove),
                  label: const Text('1 分'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => _services.repository.addSeconds(60),
                  icon: const Icon(Icons.add),
                  label: const Text('1 分'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 主要操作(依狀態)。
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (status == TimerStatus.idle) ...[
                  OutlinedButton.icon(
                    onPressed: _pickDuration,
                    icon: const Icon(Icons.timer),
                    label: const Text('設定時間'),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    style: darkFilledStyle,
                    onPressed: _handleStart,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('啟動'),
                  ),
                ] else ...[
                  if (running)
                    FilledButton.icon(
                      style: darkFilledStyle,
                      onPressed: () => _services.repository.pause(),
                      icon: const Icon(Icons.pause),
                      label: const Text('暫停'),
                    )
                  else
                    FilledButton.icon(
                      style: darkFilledStyle,
                      onPressed: () => _services.repository.resume(),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('繼續'),
                    ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: _stopping ? null : _handleStop,
                    icon: _stopping
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.stop),
                    label: const Text('停止'),
                  ),
                ],
              ],
            ),
            if (!_services.notifications.supportsScheduling)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  '需保持 App 執行(可縮到系統匣)才會到點提醒;關閉後不會背景通知',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
