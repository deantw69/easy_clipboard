import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../alarm/alarm_group.dart';
import '../alarm/alarm_page.dart';
import '../alarm/alarm_services.dart';
import '../alarm/alarm_sound_service.dart';
import '../alarm/live_activity_service.dart';
import '../alarm/menu_bar_service.dart';
import '../alarm/notification_service.dart';
import '../alarm/timer_repository.dart';
import '../core/tab_router.dart';
import '../firebase_options.dart';

/// 鬧鐘功能 facade(full 版實作)。
///
/// 這是「含鬧鐘」建置唯一 import `lib/alarm/*` 與 `firebase_*` 的入口;
/// clean 版由 [active_alarm_feature.dart] 改 export 到 [alarm_feature_stub.dart],
/// 使 clean 編譯時完全不 reference 到 firebase/alarm 符號,連 pod 都不進 binary。
/// 詳見 CLAUDE.md「雙建置(full/clean)」。
class AlarmFeature {
  AlarmServices? _services;

  bool get hasAlarmTab => true;

  /// 初始化鬧鐘所需服務(Firebase / 通知 / 選單列 / Live Activity)。
  /// 需在 `StorageLocation.load()` 之後呼叫(AlarmGroup 桌面存同資料夾)。
  Future<void> bootstrap() async {
    // 群組代碼要先有 baseDir(桌面存備忘錄同資料夾)。
    await AlarmGroup.instance.load();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final notifications = NotificationService();
    // 點擊鬧鐘通知(前景/背景/冷啟動)→ 切到鬧鐘分頁。
    notifications.onTapAlarm = () => TabRouter.instance.go(AppTab.alarm);
    await notifications.init();
    unawaited(notifications.handleLaunchTap());
    final menuBar = MenuBarService();
    await menuBar.init();
    _services = AlarmServices(
      repository: TimerRepository(
        deviceId: alarmDeviceLabel(),
        timerId: AlarmGroup.instance.code,
      ),
      notifications: notifications,
      alarm: AlarmSoundService(),
      menuBar: menuBar,
      liveActivity: LiveActivityService(),
    );
    // 通知權限放最後,不卡啟動流程。
    unawaited(notifications.requestPermissions());
  }

  /// 用鬧鐘服務的 Provider 包住 [child](clean 版原樣回傳)。
  Widget wrap(Widget child) => _services == null
      ? child
      : Provider<AlarmServices>.value(value: _services!, child: child);

  /// 第三分頁的頁面(clean 版回 null)。
  Widget? tabPage() => const AlarmPage();

  /// 第三分頁的 NavigationDestination(clean 版回 null)。
  NavigationDestination? tabDestination() => const NavigationDestination(
        icon: Icon(Icons.alarm_outlined),
        selectedIcon: Icon(Icons.alarm),
        label: '鬧鐘',
      );
}
