import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'alarm_facade/active_alarm_feature.dart';
import 'app_controller.dart';
import 'core/autostart.dart';
import 'core/deep_link.dart';
import 'core/desktop_tray_service.dart';
import 'core/hotkey_service.dart';
import 'core/share_handler.dart';
import 'core/storage_location.dart';
import 'features/home_page.dart';
import 'features/root_page.dart';
import 'memos/memo_store.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final desktopTray = DesktopTrayService();

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // 手機(iOS/Android)鎖定直向;桌面不受影響。
  if (Platform.isIOS || Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  // 開機自啟且使用者選了「自啟時隱藏」→ 啟動即收進系統匣、不彈主視窗。
  final startHidden =
      DesktopTrayService.isDesktop && await AutostartService.shouldStartHidden(args);
  await DesktopTrayService.ensureInitialized(startHidden: startHidden);
  await StorageLocation.instance.load();
  final memoStore = MemoStore()..load();

  // 鬧鐘功能(Firebase + 通知 + 選單列 + Live Activity)收斂在 facade 後;
  // clean 建置的 facade 為 no-op stub,完全不初始化、不引入 firebase(見 CLAUDE.md)。
  // bootstrap 需在 StorageLocation.load() 之後(桌面 AlarmGroup 存同資料夾)。
  final alarmFeature = AlarmFeature();
  await alarmFeature.bootstrap();

  runApp(
    alarmFeature.wrap(
      MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: memoStore),
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

        if (DesktopTrayService.isDesktop) {
          desktopTray.onWindowShown = () => c.refreshDiscovery();
          desktopTray.init();
        }
        if (DesktopTrayService.isWindows) {
          HotkeyService.instance.start(() => desktopTray.toggleWindow());
        }

          return c;
        }),
      ],
      child: const SyncNestApp(),
      ),
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
      // 深色模式:同 seed、跟隨系統。便利貼底色(kMemoColors)為固定淺色,
      // 其上文字維持深色(見 memos_page.dart),不受此主題影響。
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const RootPage(),
    );
  }
}
