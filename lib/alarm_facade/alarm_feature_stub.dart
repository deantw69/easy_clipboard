import 'package:flutter/material.dart';

/// 鬧鐘功能 facade(clean 版 stub)。
///
/// 完全不 import 任何 firebase/alarm 套件,使 clean 建置的編譯圖不含這些符號,
/// 對應的 native pod / plugin registrant 亦不生成(見 CLAUDE.md「雙建置」)。
/// 介面須與 [alarm_feature.dart] 的 `AlarmFeature` 一致。
class AlarmFeature {
  bool get hasAlarmTab => false;

  Future<void> bootstrap() async {}

  Widget wrap(Widget child) => child;

  Widget? tabPage() => null;

  NavigationDestination? tabDestination() => null;
}
