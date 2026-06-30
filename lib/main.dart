import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'alarm/alarm_group.dart';
import 'alarm/alarm_services.dart';
import 'alarm/alarm_sound_service.dart';
import 'alarm/live_activity_service.dart';
import 'alarm/menu_bar_service.dart';
import 'alarm/notification_service.dart';
import 'alarm/timer_repository.dart';
import 'app_controller.dart';
import 'core/desktop_tray_service.dart';
import 'core/hotkey_service.dart';
import 'core/share_handler.dart';
import 'core/storage_location.dart';
import 'features/home_page.dart';
import 'features/root_page.dart';
import 'firebase_options.dart';
import 'memos/memo_store.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final desktopTray = DesktopTrayService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  await notifications.init();
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
          WidgetsBinding.instance
              .addPostFrameCallback((_) => handler.start());
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
