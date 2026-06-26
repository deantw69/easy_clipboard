import 'package:audioplayers/audioplayers.dart';

/// 實際播放鬧鈴音檔(循環),不依賴 OS 通知音 —— 確保時間到時一定會響。
///
/// 通知負責視覺提示與背景觸發;此服務負責 App 在前景時保證出聲。
class AlarmSoundService {
  final AudioPlayer _player = AudioPlayer();
  bool _ringing = false;

  /// 開始循環響鈴。重複呼叫不會疊加。
  Future<void> start() async {
    if (_ringing) return;
    _ringing = true;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.play(AssetSource('sounds/alarm.wav'));
  }

  /// 停止響鈴。一律真的去停 player(不靠 _ringing 早退),避免 _ringing 狀態
  /// 不同步時空振、導致聲音停不掉(殘響)。
  Future<void> stop() async {
    _ringing = false;
    try {
      await _player.stop();
    } catch (_) {
      // 尚未播放 / 已停止時忽略。
    }
  }

  bool get isRinging => _ringing;

  Future<void> dispose() => _player.dispose();
}
