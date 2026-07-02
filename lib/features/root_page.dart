import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../alarm/alarm_page.dart';
import '../core/tab_router.dart';
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

  /// 已因深連結切過分頁後,就不讓 last_tab 還原覆蓋(避免搶回)。
  bool _routedByLink = false;

  static const _pages = [HomePage(), MemosPage(), AlarmPage()];

  /// [AppTab] → 本分支的分頁 index;沒有對應分頁回 null。
  int? _indexForTab(AppTab tab) {
    switch (tab) {
      case AppTab.clipboard:
        return 0;
      case AppTab.memo:
        return 1;
      case AppTab.alarm:
        return 2;
    }
  }

  @override
  void initState() {
    super.initState();
    // 冷啟動時深連結/通知可能在 mount 前就設好目標;此時還在 build 階段不能 setState,
    // 直接指定初始 index(並標記 _routedByLink,讓 _loadLastTab 不搶回)。
    final pending = TabRouter.instance.requested.value;
    final i = pending == null ? null : _indexForTab(pending);
    if (i != null) {
      _index = i;
      _routedByLink = true;
      TabRouter.instance.consume();
    }
    _loadLastTab();
    TabRouter.instance.requested.addListener(_onTabRequested);
  }

  @override
  void dispose() {
    TabRouter.instance.requested.removeListener(_onTabRequested);
    super.dispose();
  }

  void _onTabRequested() {
    final tab = TabRouter.instance.requested.value;
    if (tab == null) return;
    final i = _indexForTab(tab);
    if (i != null && mounted) {
      _routedByLink = true;
      setState(() => _index = i);
    }
    TabRouter.instance.consume();
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
        // 深連結已指定分頁時不還原上次分頁,避免搶回。
        if (i != null && i >= 0 && i < _pages.length && mounted && !_routedByLink) {
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
