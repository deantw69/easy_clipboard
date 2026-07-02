import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'alarm/alarm_group.dart';
import 'alarm/alarm_services.dart';
import 'alarm/alarm_sound_service.dart';
import 'alarm/live_activity_service.dart';
import 'alarm/menu_bar_service.dart';
import 'alarm/notification_service.dart';
import 'alarm/timer_repository.dart';
import 'app_controller.dart';
import 'core/deep_link.dart';
import 'core/desktop_tray_service.dart';
import 'core/hotkey_service.dart';
import 'core/share_handler.dart';
import 'core/storage_location.dart';
import 'core/tab_router.dart';
import 'features/home_page.dart';
import 'features/root_page.dart';
import 'firebase_options.dart';
import 'memos/memo_store.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final desktopTray = DesktopTrayService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 手機(iOS/Android)鎖定直向;桌面不受影響。
  if (Platform.isIOS || Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  await DesktopTrayService.ensureInitialized();
  await StorageLocation.instance.load();
  // 群組代碼要先有 baseDir(桌面存備忘錄同資料夾),故在 StorageLocation 之後載入。
  await AlarmGroup.instance.load();
  final memoStore = MemoStore()..load();

  // 鬧鐘(倒數計時)分頁:Firebase + 通知 + 選單列。
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
  final alarmServices = AlarmServices(
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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: memoStore),
        Provider<AlarmServices>.value(value: alarmServices),
        ChangeNotifierProvider<AppController>(create: (_) {
          final c = AppController(memos: memoStore);
          c.onImageReceived = (item) async {
          final ctx = navigatorKey.currentContext;
          if (ctx != null) await showReceivedImageDialog(ctx, item, c);
        };
        c.onUrlReceived = (url) async {
          final ctx = navigatorKey.currentContext;
          if (ctx != null) await showReceivedUrlDialog(ctx, url);
        };
        c.init();

        if (Platform.isIOS) {
          final handler =
              ShareHandler(controller: c, navigatorKey: navigatorKey);
          WidgetsBinding.instance.addPostFrameCallback((_) => handler.start());
        }

        if (DesktopTrayService.isWindows) {
          desktopTray.onWindowShown = () => c.refreshDiscovery();
          desktopTray.init();
          HotkeyService.instance.start(() => desktopTray.toggleWindow());
        }

          return c;
        }),
      ],
      child: const SyncNestApp(),
    ),
  );

  // 深連結(Widget/動態島)接收:儘早訂閱串流並取回冷啟動初始連結。
  // 冷啟動時 TabRouter 目標可能在 RootPage mount 前就設好,由 RootPage.initState 補套用。
  if (Platform.isIOS) {
    DeepLinkService.instance.start();
  }
}

class SyncNestApp extends StatelessWidget {
  const SyncNestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SyncNest',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const RootPage(),
    );
  }
}
