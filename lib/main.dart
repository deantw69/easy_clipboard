import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_controller.dart';
import 'core/desktop_tray_service.dart';
import 'core/share_handler.dart';
import 'features/home_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();
final desktopTray = DesktopTrayService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopTrayService.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) {
        final c = AppController();
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
        }

        return c;
      },
      child: const EasyClipboardApp(),
    ),
  );
}

class EasyClipboardApp extends StatelessWidget {
  const EasyClipboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyClipboard',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
