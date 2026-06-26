import 'package:flutter/material.dart';

import 'home_page.dart';
import 'memos_page.dart';

/// 底部分頁殼:剪貼簿/裝置 與 備忘錄 兩個獨立分頁。
/// 用 IndexedStack 保留各分頁狀態(切回來不重建)。
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;

  static const _pages = [HomePage(), MemosPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
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
        ],
      ),
    );
  }
}
