import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面視窗的「位置 + 長寬」記憶(僅 macOS / Windows):
/// 啟動時還原上次關閉前的視窗 frame,執行中去抖存檔。
///
/// 設定值持久化於 App 支援目錄的 `window_bounds.json`(沿用 identity /
/// last_target / hotkey 的「檔案存 appSupport」pattern,各裝置分開記)。
class WindowBoundsService with WindowListener {
  WindowBoundsService._();
  static final WindowBoundsService instance = WindowBoundsService._();

  static bool get supported =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows);

  /// 視窗最小可接受尺寸(避免存到被縮到看不見的 frame)。
  static const Size _minSize = Size(360, 480);

  /// 允許視窗超出可見區域邊界的寬容量(px):讓貼邊/略微超出的擺放位置
  /// 也能被保留,而不會被硬拉回畫面內。
  static const double _overflowMargin = 100;

  Timer? _saveDebounce;

  /// 讀取已存的 bounds(夾限在目前可見螢幕內);沒有或失效則回傳 null。
  Future<Rect?> loadBounds() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final rect = Rect.fromLTWH(
        (m['x'] as num).toDouble(),
        (m['y'] as num).toDouble(),
        (m['width'] as num).toDouble(),
        (m['height'] as num).toDouble(),
      );
      return _clampToVisible(rect);
    } catch (_) {
      return null;
    }
  }

  /// 啟動 show 之前套用上次的 frame;沒有存檔就維持預設 [WindowOptions]。
  Future<void> applySavedBounds() async {
    final rect = await loadBounds();
    if (rect == null) return;
    await windowManager.setBounds(rect);
  }

  /// 開始監聽視窗移動/縮放並去抖存檔。
  void startTracking() {
    if (!supported) return;
    windowManager.addListener(this);
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/window_bounds.json');
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    try {
      // 最小化/隱藏時的 bounds 不可靠,跳過。
      if (await windowManager.isMinimized()) return;
      if (!await windowManager.isVisible()) return;
      final b = await windowManager.getBounds();
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'x': b.left,
        'y': b.top,
        'width': b.width,
        'height': b.height,
      }));
    } catch (_) {}
  }

  /// 把存檔的 frame 夾限到「某個螢幕的可見區域」內,避免螢幕拔除/解析度變動
  /// 後視窗開到畫面外。找不到任何相交螢幕則退回主螢幕置中。
  Future<Rect> _clampToVisible(Rect rect) async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      final primary = await screenRetriever.getPrimaryDisplay();

      // 用「完整螢幕」而非可見區域(visibleSize)當邊界:可見區域會扣掉
      // Windows 工作列 / macOS Dock,導致視窗底部永遠貼不到螢幕真正邊緣。
      // 以完整螢幕為界,再加 _overflowMargin,才能貼底/略微超出。
      Rect areaOf(Display d) {
        final vp = d.visiblePosition ?? const Offset(0, 0);
        return Rect.fromLTWH(vp.dx, vp.dy, d.size.width, d.size.height);
      }

      // 視窗中心落在哪個螢幕,就以那個螢幕的可見區域為界。
      final center = rect.center;
      Rect? area;
      for (final d in displays) {
        final a = areaOf(d);
        if (a.contains(center)) {
          area = a;
          break;
        }
      }
      area ??= areaOf(primary);

      var w = rect.width.clamp(_minSize.width, area.width);
      var h = rect.height.clamp(_minSize.height, area.height);
      // 位置夾限放寬 _overflowMargin:允許略微超出螢幕邊界。
      var x = rect.left.clamp(
          area.left - _overflowMargin, area.right - w + _overflowMargin);
      var y = rect.top.clamp(
          area.top - _overflowMargin, area.bottom - h + _overflowMargin);
      return Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());
    } catch (_) {
      // 取不到螢幕資訊就照原樣(至少保住尺寸下限)。
      final w = rect.width < _minSize.width ? _minSize.width : rect.width;
      final h = rect.height < _minSize.height ? _minSize.height : rect.height;
      return Rect.fromLTWH(rect.left, rect.top, w, h);
    }
  }

  // ---- WindowListener ----

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();
}
