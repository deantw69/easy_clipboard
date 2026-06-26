import 'package:flutter/foundation.dart';

import 'alarm_sound_service.dart';
import 'live_activity_service.dart';
import 'menu_bar_service.dart';
import 'notification_service.dart';
import 'timer_repository.dart';

/// 鬧鐘(倒數計時)分頁所需服務的容器,於 main() 建立並以 Provider 注入。
/// [AlarmPage] 從 context 取用,生命週期與 App 一致(IndexedStack 不重建)。
class AlarmServices {
  AlarmServices({
    required this.repository,
    required this.notifications,
    required this.alarm,
    required this.menuBar,
    required this.liveActivity,
  });

  final TimerRepository repository;
  final NotificationService notifications;
  final AlarmSoundService alarm;
  final MenuBarService menuBar;
  final LiveActivityService liveActivity;
}

/// 簡單的裝置代號(顯示在「最後操作」),用平台名稱即可。
String alarmDeviceLabel() {
  if (kIsWeb) return 'Web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'Android';
    case TargetPlatform.iOS:
      return 'iPhone';
    case TargetPlatform.macOS:
      return 'Mac';
    case TargetPlatform.windows:
      return 'Windows';
    default:
      return defaultTargetPlatform.name;
  }
}
