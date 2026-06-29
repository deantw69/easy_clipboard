import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 簡單的時 / 分 / 秒選擇器。桌面(macOS/Windows)用數字框+步進鈕,
/// 其餘平台用滾輪挑選倒數長度。
class DurationPickerSheet extends StatefulWidget {
  const DurationPickerSheet({super.key, required this.initial});

  final Duration initial;

  /// 以 modal bottom sheet 呈現,回傳選定的 Duration(取消則 null)。
  static Future<Duration?> show(BuildContext context, Duration initial) {
    return showModalBottomSheet<Duration>(
      context: context,
      builder: (_) => DurationPickerSheet(initial: initial),
    );
  }

  @override
  State<DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<DurationPickerSheet> {
  late int _hours = widget.initial.inHours;
  late int _minutes = widget.initial.inMinutes.remainder(60);
  late int _seconds = widget.initial.inSeconds.remainder(60);

  bool get _isDesktop => Platform.isMacOS || Platform.isWindows;

  late final TextEditingController _hCtrl =
      TextEditingController(text: _hours.toString().padLeft(2, '0'));
  late final TextEditingController _mCtrl =
      TextEditingController(text: _minutes.toString().padLeft(2, '0'));
  late final TextEditingController _sCtrl =
      TextEditingController(text: _seconds.toString().padLeft(2, '0'));

  @override
  void dispose() {
    _hCtrl.dispose();
    _mCtrl.dispose();
    _sCtrl.dispose();
    super.dispose();
  }

  /// 桌面用:數字輸入框 + 上下步進鈕。
  Widget _stepperField({
    required int count,
    required int value,
    required String label,
    required TextEditingController controller,
    required ValueChanged<int> onChanged,
  }) {
    void set(int v) {
      final next = ((v % count) + count) % count; // 環狀,負數補回
      controller.text = next.toString().padLeft(2, '0');
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
      onChanged(next);
    }

    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 64,
                child: TextField(
                  controller: controller,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (t) {
                    final v = int.tryParse(t) ?? 0;
                    final clamped = v.clamp(0, count - 1);
                    onChanged(clamped);
                    if (v != clamped) {
                      controller.text = clamped.toString();
                      controller.selection = TextSelection.collapsed(
                          offset: controller.text.length);
                    }
                  },
                ),
              ),
              Column(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 28),
                    icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                    onPressed: () =>
                        set((int.tryParse(controller.text) ?? value) + 1),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 28),
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                    onPressed: () =>
                        set((int.tryParse(controller.text) ?? value) - 1),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _wheel({
    required int count,
    required int value,
    required String label,
    required ValueChanged<int> onChanged,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(
            height: 160,
            child: ListWheelScrollView.useDelegate(
              controller: FixedExtentScrollController(initialItem: value),
              itemExtent: 40,
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: onChanged,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: count,
                builder: (_, i) => Center(
                  child: Text(i.toString().padLeft(2, '0'),
                      style: const TextStyle(fontSize: 24)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('設定倒數時間',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_isDesktop)
              Row(
                children: [
                  _stepperField(
                      count: 24,
                      value: _hours,
                      label: '時',
                      controller: _hCtrl,
                      onChanged: (v) => _hours = v),
                  _stepperField(
                      count: 60,
                      value: _minutes,
                      label: '分',
                      controller: _mCtrl,
                      onChanged: (v) => _minutes = v),
                  _stepperField(
                      count: 60,
                      value: _seconds,
                      label: '秒',
                      controller: _sCtrl,
                      onChanged: (v) => _seconds = v),
                ],
              )
            else
              Row(
                children: [
                  _wheel(
                      count: 24,
                      value: _hours,
                      label: '時',
                      onChanged: (v) => _hours = v),
                  _wheel(
                      count: 60,
                      value: _minutes,
                      label: '分',
                      onChanged: (v) => _minutes = v),
                  _wheel(
                      count: 60,
                      value: _seconds,
                      label: '秒',
                      onChanged: (v) => _seconds = v),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final d = Duration(
                        hours: _hours, minutes: _minutes, seconds: _seconds);
                    Navigator.pop(context, d == Duration.zero ? null : d);
                  },
                  child: const Text('確定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
