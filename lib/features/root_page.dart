import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../alarm/alarm_page.dart';
import 'home_page.dart';
import 'memos_page.dart';

/// 底部分頁殼:剪貼簿/裝置、備忘錄、鬧鐘三個獨立分頁。
/// 用 IndexedStack 保留各分頁狀態(切回來不重建)。
/// 最後選的分頁會記在本機 appSupport 的 last_tab 檔(各裝置分開記),重開還原。
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;

  static const _pages = [HomePage(), MemosPage(), AlarmPage()];

  @override
  void initState() {
    super.initState();
    _loadLastTab();
  }

  Future<File> _lastTabFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'last_tab'));
  }

  Future<void> _loadLastTab() async {
    try {
      final f = await _lastTabFile();
      if (await f.exists()) {
        final i = int.tryParse((await f.readAsString()).trim());
        if (i != null && i >= 0 && i < _pages.length && mounted) {
          setState(() => _index = i);
        }
      }
    } catch (_) {}
  }

  Future<void> _saveLastTab(int i) async {
    try {
      await (await _lastTabFile()).writeAsString('$i');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          _saveLastTab(i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.devices_outlined),
            selectedIcon: Icon(Icons.devices),
            label: '剪貼簿',
          ),
          NavigationDestination(
            icon: Icon(Icons.sticky_note_2_outlined),
            selectedIcon: Icon(Icons.sticky_note_2),
            label: '備忘錄',
          ),
          NavigationDestination(
            icon: Icon(Icons.alarm_outlined),
            selectedIcon: Icon(Icons.alarm),
            label: '鬧鐘',
          ),
        ],
      ),
    );
  }
}
