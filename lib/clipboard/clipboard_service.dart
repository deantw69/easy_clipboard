import 'dart:async';
import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

/// 跨平台剪貼簿讀寫(文字 + 圖片)。
///
/// - 桌面(macOS/Windows):可用 [ClipboardWatcher] 輪詢自動偵測文字變化。
/// - iOS:不做背景輪詢(每次讀會跳系統橫幅),改由 UI 的「分享剪貼簿」按鈕手動觸發。
class ClipboardService {
  SystemClipboard? get _clipboard => SystemClipboard.instance;

  bool get isSupported => _clipboard != null;

  Future<String?> readText() async {
    final cb = _clipboard;
    if (cb == null) return null;
    final reader = await cb.read();
    if (!reader.canProvide(Formats.plainText)) return null;
    return reader.readValue(Formats.plainText);
  }

  Future<Uint8List?> readImagePng() async {
    final cb = _clipboard;
    if (cb == null) return null;
    final reader = await cb.read();
    if (!reader.canProvide(Formats.png)) return null;
    final completer = Completer<Uint8List?>();
    reader.getFile(
      Formats.png,
      (file) async {
        try {
          completer.complete(await file.readAll());
        } catch (_) {
          if (!completer.isCompleted) completer.complete(null);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    return completer.future;
  }

  Future<void> writeText(String text) async {
    final cb = _clipboard;
    if (cb == null) return;
    final item = DataWriterItem()..add(Formats.plainText(text));
    await cb.write([item]);
  }

  Future<void> writeImagePng(List<int> bytes) async {
    final cb = _clipboard;
    if (cb == null) return;
    final item = DataWriterItem()
      ..add(Formats.png(Uint8List.fromList(bytes)));
    await cb.write([item]);
  }
}

/// 桌面用的輕量剪貼簿監聽:定時輪詢純文字,內容變化時回呼。
///
/// 僅監聽文字以維持低開銷;圖片同步走手動按鈕。iOS 不應啟用此監聽。
class ClipboardWatcher {
  final ClipboardService _service;
  final Duration interval;
  Timer? _timer;
  String? _lastText;

  ClipboardWatcher(this._service, {this.interval = const Duration(seconds: 2)});

  void start(void Function(String text) onTextChanged) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) async {
      final text = await _service.readText();
      if (text != null && text.isNotEmpty && text != _lastText) {
        _lastText = text;
        onTextChanged(text);
      }
    });
  }

  /// 標記目前內容為「已知」,避免把本機剛寫入的內容又當成變化送出。
  void markSeen(String? text) => _lastText = text;

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
