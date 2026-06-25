import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_controller.dart';
import 'features/home_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) {
        final c = AppController();
        c.onImageReceived = (item) async {
          final ctx = navigatorKey.currentContext;
          if (ctx != null) await showReceivedImageDialog(ctx, item, c);
        };
        c.init();
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
