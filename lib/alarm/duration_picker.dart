import 'package:flutter/material.dart';

/// 簡單的時 / 分 / 秒選擇器,用滾輪挑選倒數長度。
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
