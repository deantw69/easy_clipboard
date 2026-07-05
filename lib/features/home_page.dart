import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../core/autostart.dart';
import '../core/hotkey_service.dart';
import '../core/models.dart';
import '../core/storage_location.dart';
import '../memos/memo_store.dart';

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// 第一頁:上半「附近的裝置」清單、下半「收到的內容」,各佔一半。
/// 收到的內容(`c.received`)本就全域不分裝置,故統一放第一頁。
/// 點裝置:手機跳「傳送圖片/影片 或 剪貼簿」選單;桌面照舊進第二頁傳輸頁。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(c.local == null
            ? 'SyncNest'
            : '${c.local!.name} · ${c.local!.platform}'),
        actions: [
          // 設定鈕只在「有桌面專屬設定項可顯示」時出現(開機自啟/快捷鍵/儲存資料夾)。
          // 手機三者皆 false,設定對話框會是空的,故不顯示齒輪;
          // 「重設備忘錄並重新同步」已移到備忘錄頁右上選單。
          if (AutostartService.supported ||
              HotkeyService.supported ||
              StorageLocation.supported)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '設定',
              onPressed: () => showSettingsDialog(context),
            ),
        ],
      ),
      body: !c.ready
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _SectionTitle('附近的裝置 (${c.devices.length})'),
                      Expanded(
                        child: c.devices.isEmpty
                            ? const Center(
                                child: Text('搜尋中… 確認在同一個 Wi-Fi'))
                            : ListView(
                                children: [
                                  for (final d in c.devices)
                                    _DeviceTile(device: d),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 下半:收到的內容(各佔一半)
                const Expanded(child: _ReceivedSection()),
              ],
            ),
    );
  }
}

/// 「收到的內容」整區:標題+數量+清除鈕+收到清單(空時顯示提示)。
/// 從舊第二頁搬來第一頁,手機/桌面共用。
class _ReceivedSection extends StatelessWidget {
  const _ReceivedSection();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('收到的內容 (${c.received.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (c.received.isNotEmpty)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('清除'),
                  onPressed: () => _confirmClearReceived(context, c),
                ),
            ],
          ),
        ),
        Expanded(
          child: c.received.isEmpty
              ? const Center(child: Text('尚無收到的內容'))
              : ListView(
                  children: [
                    for (final r in c.received) _ReceivedTile(item: r),
                  ],
                ),
        ),
      ],
    );
  }
}

/// 手機版:點裝置後跳出的傳送選單(傳送圖片/影片 或 傳送剪貼簿)。
Future<void> _showSendSheet(BuildContext context, DeviceInfo device) async {
  final c = context.read<AppController>();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('傳送到 ${device.name}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('傳送圖片 / 影片'),
            onTap: () async {
              Navigator.pop(ctx);
              final paths = await _pickMediaPaths();
              if (paths.isEmpty || !context.mounted) return;
              await _sendWithProgress(context, c, device, paths);
            },
          ),
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('傳送剪貼簿'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await c.sendClipboard(device);
                if (context.mounted && c.status != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(c.status!)),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('傳送失敗:$e')),
                  );
                }
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// 設定對話框:目前提供「開機自動啟動」開關(僅桌面平台)。
Future<void> showSettingsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _SettingsDialog(),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  bool? _autostart;
  bool _startHidden = false;
  bool _busy = false;
  HotKey? _hotKey;
  String? _storagePath;

  @override
  void initState() {
    super.initState();
    AutostartService.isEnabled().then((v) {
      if (mounted) setState(() => _autostart = v);
    });
    AutostartService.isStartHiddenEnabled().then((v) {
      if (mounted) setState(() => _startHidden = v);
    });
    if (HotkeyService.supported) {
      _hotKey = HotkeyService.instance.current;
    }
    if (StorageLocation.supported) {
      _refreshStoragePath();
    }
  }

  Future<void> _refreshStoragePath() async {
    final dir = await StorageLocation.instance.baseDir();
    if (mounted) setState(() => _storagePath = dir.path);
  }

  Future<void> _changeStorageDir() async {
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: '選擇儲存資料夾',
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await StorageLocation.instance.setPath(picked);
      await _refreshStoragePath();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已變更儲存資料夾,既有資料已複製過去')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetStorageDir() async {
    setState(() => _busy = true);
    try {
      await StorageLocation.instance.setPath(null);
      await _refreshStoragePath();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeHotKey() async {
    final picked = await showDialog<HotKey>(
      context: context,
      builder: (_) => _HotKeyRecorderDialog(initial: _hotKey),
    );
    if (picked == null) return;
    await HotkeyService.instance.update(picked);
    if (mounted) setState(() => _hotKey = HotkeyService.instance.current);
  }

  Future<void> _toggleStartHidden(bool value) async {
    setState(() => _busy = true);
    try {
      await AutostartService.setStartHidden(value);
      if (mounted) setState(() => _startHidden = value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    try {
      await AutostartService.setEnabled(value);
      final actual = await AutostartService.isEnabled();
      if (mounted) setState(() => _autostart = actual);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('設定失敗:$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('設定'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (AutostartService.supported)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('開機自動啟動'),
              subtitle: const Text('登入系統時自動開啟 SyncNest'),
              value: _autostart ?? false,
              onChanged: (_autostart == null || _busy) ? null : _toggle,
            ),
          // 自啟時隱藏視窗:僅在開機自啟已開啟時顯示。
          if (AutostartService.supported && (_autostart ?? false))
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 16),
              title: const Text('自啟時隱藏視窗'),
              subtitle: const Text('登入啟動時只縮到系統匣背景執行,用快捷鍵/匣圖示呼出'),
              value: _startHidden,
              onChanged: _busy ? null : _toggleStartHidden,
            ),
          if (HotkeyService.supported && _hotKey != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('呼出視窗快捷鍵'),
              subtitle: Text(_hotKeyLabel(_hotKey!)),
              trailing: TextButton(
                onPressed: _changeHotKey,
                child: const Text('變更'),
              ),
            ),
          if (StorageLocation.supported)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('儲存資料夾'),
              subtitle: Text(
                _storagePath ?? '讀取中…',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: _storagePath != null && _storagePath!.length > 30,
              trailing: TextButton(
                onPressed: _busy ? null : _changeStorageDir,
                child: const Text('變更'),
              ),
            ),
          if (StorageLocation.supported &&
              StorageLocation.instance.customPath != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _busy ? null : _resetStorageDir,
                child: const Text('還原預設位置'),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

/// 把 [HotKey] 轉成可讀標籤,例如 `Ctrl + Alt + C`。
String _hotKeyLabel(HotKey h) {
  String mod(HotKeyModifier m) => switch (m) {
        HotKeyModifier.control => 'Ctrl',
        HotKeyModifier.alt => 'Alt',
        HotKeyModifier.shift => 'Shift',
        HotKeyModifier.meta => 'Win',
        HotKeyModifier.capsLock => 'CapsLock',
        HotKeyModifier.fn => 'Fn',
      };
  final parts = [...(h.modifiers ?? const []).map(mod)];
  var keyName = h.logicalKey.keyLabel;
  if (keyName.isEmpty) keyName = h.physicalKey.debugName ?? '?';
  parts.add(keyName);
  return parts.join(' + ');
}

/// 錄製快捷鍵的小對話框。要求至少一個修飾鍵(Ctrl/Alt/Shift/Win)才可儲存。
class _HotKeyRecorderDialog extends StatefulWidget {
  final HotKey? initial;
  const _HotKeyRecorderDialog({this.initial});

  @override
  State<_HotKeyRecorderDialog> createState() => _HotKeyRecorderDialogState();
}

class _HotKeyRecorderDialogState extends State<_HotKeyRecorderDialog> {
  HotKey? _recorded;

  bool get _valid =>
      _recorded != null && (_recorded!.modifiers?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final preview = _recorded ?? widget.initial;
    return AlertDialog(
      title: const Text('設定快捷鍵'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('直接按下想要的組合鍵(需含 Ctrl / Alt / Shift / Win)'),
          const SizedBox(height: 16),
          HotKeyRecorder(
            initalHotKey: widget.initial,
            onHotKeyRecorded: (h) => setState(() => _recorded = h),
          ),
          const SizedBox(height: 12),
          Text(
            preview == null ? '尚未錄製' : _hotKeyLabel(preview),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_recorded != null && !_valid)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                '至少要有一個修飾鍵',
                style: TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _valid ? () => Navigator.pop(context, _recorded) : null,
          child: const Text('儲存'),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DeviceInfo device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final reachable = device.isReachable;
    final subtitle = reachable
        ? '${device.platform} · ${device.host}:${device.port}'
        : '${device.platform} · 尚未解析';
    final disabledColor = Theme.of(context).disabledColor;
    return ListTile(
      leading: Stack(
        alignment: Alignment.bottomRight,
        children: [
          const Icon(Icons.devices),
          // 在線狀態小圓點:已解析綠、未解析灰。
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: reachable ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).canvasColor,
                width: 1.5,
              ),
            ),
          ),
        ],
      ),
      title: Text(
        device.name,
        style: reachable ? null : TextStyle(color: disabledColor),
      ),
      subtitle: Text(
        subtitle,
        style: reachable ? null : TextStyle(color: disabledColor),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: reachable ? null : disabledColor,
      ),
      // 手機:跳傳送選單;桌面:照舊進第二頁(保留拖曳/⌘Ctrl+V)。
      // 未解析裝置禁點,點擊(ListTile enabled=false 已擋)不做事;
      // 但仍給 onTap 提示以防某些平台仍可觸發。
      onTap: reachable
          ? () => _isDesktop
              ? Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DevicePage(device: device)),
                )
              : _showSendSheet(context, device)
          : () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('裝置尚未解析,請稍候或重新整理'),
                  duration: Duration(seconds: 2),
                ),
              ),
    );
  }
}

/// 第二頁(僅桌面):已連上某裝置的傳送頁。收到的內容已移至第一頁。
///
/// 桌面額外支援:Cmd/Ctrl+V 直接傳出剪貼簿、拖曳圖片/影片到視窗放開即傳出。
class DevicePage extends StatelessWidget {
  final DeviceInfo device;
  const DevicePage({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    Widget body = Column(
      children: [
        if (c.status != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(c.status!,
                style: const TextStyle(color: Colors.teal)),
          ),
        const _SectionTitle('傳送'),
        _SendActions(device: device),
        if (_isDesktop) const _DesktopHint(),
        // 撐滿剩餘空間,讓拖曳區涵蓋整個視窗。
        const Expanded(child: SizedBox.expand()),
      ],
    );

    if (_isDesktop) {
      body = _DesktopShortcuts(
        device: device,
        child: _DropZone(device: device, child: body),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('已連上 ${device.name}'),
        leading: const BackButton(),
      ),
      body: body,
    );
  }
}

/// 清除收到的內容:跳確認對話框,確認後刪除暫存檔釋放容量。
Future<void> _confirmClearReceived(
    BuildContext context, AppController c) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('清除收到的內容'),
      content: const Text('將刪除已收到並暫存於本機的檔案以釋放容量,此動作無法復原。\n'
          '(已存進相簿的圖片/影片不受影響。)'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('清除'),
        ),
      ],
    ),
  );
  if (ok == true) await c.clearReceived();
}

/// 傳送按鈕:圖片/影片、剪貼簿。
class _SendActions extends StatelessWidget {
  final DeviceInfo device;
  const _SendActions({required this.device});

  @override
  Widget build(BuildContext context) {
    final c = context.read<AppController>();
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.photo_library),
          title: const Text('傳送圖片 / 影片'),
          onTap: () async {
            final paths = await _pickMediaPaths();
            if (paths.isEmpty || !context.mounted) return;
            await _sendWithProgress(context, c, device, paths);
          },
        ),
        ListTile(
          leading: const Icon(Icons.content_paste),
          title: const Text('傳送剪貼簿'),
          onTap: () => _sendClipboardWithFeedback(context, c, device),
        ),
      ],
    );
  }
}

/// 桌面:攔截 Cmd/Ctrl+V,直接把目前剪貼簿(圖片優先,否則文字)傳出。
class _DesktopShortcuts extends StatelessWidget {
  final DeviceInfo device;
  final Widget child;
  const _DesktopShortcuts({required this.device, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.read<AppController>();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () =>
            _sendClipboardWithFeedback(context, c, device),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
            _sendClipboardWithFeedback(context, c, device),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

// ---- 系統分享選單(iOS Share Extension)送出流程 ----

/// 處理一批從系統分享進來的內容:先嘗試自動送上次裝置,找不到再跳裝置選單,
/// 選定後依序送出。
Future<void> runShareFlow(
    BuildContext context, AppController c, List<SharedPayload> payloads) async {
  // 分享進來的全是網址時,先問要加入備忘錄還是傳到裝置(剪貼簿)。
  if (payloads.isNotEmpty &&
      payloads.every((p) => p.kind == SharedKind.url)) {
    final dest = await _showUrlDestinationDialog(context);
    if (dest == null || !context.mounted) return;
    if (dest == _UrlDest.memo) {
      await _addUrlsToMemo(context, c, payloads);
      return;
    }
    // _UrlDest.clipboard → 繼續下方原本的傳送流程。
  }
  DeviceInfo? target;
  if (c.lastTargetId != null) {
    target = await _resolveLastTargetWithDialog(context, c);
  }
  if (!context.mounted) return;
  target ??= await showShareTargetPicker(context, payloads);
  if (target == null || !context.mounted) return;
  await _sendSharedBatch(context, c, target, payloads);
}

/// 分享網址的去向。
enum _UrlDest { memo, clipboard }

/// 詢問分享進來的網址要「加入備忘錄」還是「傳到裝置(剪貼簿)」。
Future<_UrlDest?> _showUrlDestinationDialog(BuildContext context) {
  return showDialog<_UrlDest>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('收到網址'),
      content: const Text('要把網址加入備忘錄,還是傳到其他裝置?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, _UrlDest.clipboard),
          child: const Text('傳到裝置'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, _UrlDest.memo),
          child: const Text('加入備忘錄'),
        ),
      ],
    ),
  );
}

/// 選一則(或新建)備忘錄,把網址加為它的待辦項目。
Future<void> _addUrlsToMemo(
    BuildContext context, AppController c, List<SharedPayload> payloads) async {
  final urls = payloads.map((p) => p.value).toList();
  final target = await showModalBottomSheet<Memo>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('加入到備忘錄…',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新增備忘錄'),
            onTap: () => Navigator.pop(ctx, c.memos.add()),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final m in c.memos.visibleMemos)
                  ListTile(
                    leading: const Icon(Icons.sticky_note_2_outlined),
                    title: Text(
                      m.text.trim().isNotEmpty
                          ? m.text
                          : (m.todos.isNotEmpty
                              ? m.todos.first.text
                              : '(空白備忘錄)'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.pop(ctx, m),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  if (target == null) return;
  c.memos.update(target.id, (m) {
    for (final url in urls) {
      m.todos.add(MemoTodo.create(text: url));
    }
  });
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已加入備忘錄')),
    );
  }
}

/// 顯示「搜尋上次裝置中」對話框,同時在背景輪詢等該裝置上線;找到回傳,逾時回 null。
Future<DeviceInfo?> _resolveLastTargetWithDialog(
    BuildContext context, AppController c) async {
  final future = c.resolveLastTarget();
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Expanded(child: Text('搜尋上次傳送的裝置…')),
        ],
      ),
    ),
  );
  final target = await future;
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  return target;
}

/// 跳出裝置選單(隨探索即時更新),讓使用者選擇要把分享內容送到哪台。
Future<DeviceInfo?> showShareTargetPicker(
    BuildContext context, List<SharedPayload> payloads) {
  return showModalBottomSheet<DeviceInfo>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Consumer<AppController>(
      builder: (ctx, c, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('傳送${_sharedSummary(payloads)}到…',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            if (c.devices.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Row(
                  children: [
                    SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Expanded(child: Text('搜尋附近裝置… 確認在同一個 Wi-Fi')),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final d in c.devices)
                      ListTile(
                        leading: const Icon(Icons.devices),
                        title: Text(d.name),
                        subtitle: Text('${d.platform} · ${d.host}'),
                        onTap: () => Navigator.pop(ctx, d),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

String _sharedSummary(List<SharedPayload> payloads) {
  if (payloads.length > 1) return '${payloads.length} 個項目';
  switch (payloads.first.kind) {
    case SharedKind.image:
      return '圖片';
    case SharedKind.text:
      return '文字';
    case SharedKind.url:
      return '網址';
  }
}

Future<void> _sendSharedBatch(BuildContext context, AppController c,
    DeviceInfo target, List<SharedPayload> payloads) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 16),
          Expanded(child: Text('傳送中…')),
        ],
      ),
    ),
  );
  // 同一批的圖片數量:>1 時接收端不跳彈窗。
  final imageCount =
      payloads.where((p) => p.kind == SharedKind.image).length;
  String? error;
  try {
    for (final p in payloads) {
      await c.sendShared(target, p, batchCount: imageCount);
    }
  } catch (e) {
    error = '$e';
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(error == null
              ? '已傳送到 ${target.name}'
              : '傳送失敗:$error')),
    );
  }
}

/// 接收方:收到網址時詢問是否在瀏覽器開啟。
Future<void> showReceivedUrlDialog(BuildContext context, String url) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('收到網址'),
      content: Text(url),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            Clipboard.setData(ClipboardData(text: url));
          },
          child: const Text('複製'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            final uri = Uri.tryParse(url);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text('在瀏覽器開啟'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('關閉'),
        ),
      ],
    ),
  );
}

/// 接收方:收到圖片時跳出預覽,由本機決定複製到剪貼簿或儲存。
Future<void> showReceivedImageDialog(
    BuildContext context, ReceivedItem item, AppController c) async {
  final path = item.savedPath;
  if (path == null) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('收到圖片'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360, maxWidth: 360),
        child: Image.file(File(path), fit: BoxFit.contain),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            c.copyReceivedImage(item);
          },
          child: const Text('複製到剪貼簿'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            if (c.isDesktop) {
              c.revealReceivedImage(item);
            } else {
              c.saveReceivedImageToGallery(item);
            }
          },
          child: Text(c.isDesktop
              ? (Platform.isWindows ? '在檔案總管顯示' : '在 Finder 顯示')
              : '存進相簿'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('關閉'),
        ),
      ],
    ),
  );
}

/// 桌面:拖曳檔案到視窗放開即傳出。
class _DropZone extends StatefulWidget {
  final DeviceInfo device;
  final Widget child;
  const _DropZone({required this.device, required this.child});

  @override
  State<_DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<_DropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final c = context.read<AppController>();
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        final paths = [for (final f in detail.files) f.path];
        if (paths.isEmpty || !context.mounted) return;
        await _sendWithProgress(context, c, widget.device, paths);
      },
      child: Container(
        decoration: _dragging
            ? BoxDecoration(
                border: Border.all(color: Colors.teal, width: 3),
                color: Colors.teal.withValues(alpha: 0.05),
              )
            : null,
        child: widget.child,
      ),
    );
  }
}

class _DesktopHint extends StatelessWidget {
  const _DesktopHint();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '提示:按 ⌘/Ctrl + V 直接傳出剪貼簿;或把圖片/影片拖曳到此視窗放開即傳出。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      );
}

/// 依平台選取圖片/影片(可多選),回傳本機路徑清單。
Future<List<String>> _pickMediaPaths() async {
  if (Platform.isIOS || Platform.isAndroid) {
    final xs = await ImagePicker().pickMultipleMedia();
    return [for (final x in xs) x.path];
  }
  final res =
      await FilePicker.pickFiles(type: FileType.media, allowMultiple: true);
  if (res == null) return const [];
  return [
    for (final f in res.files)
      if (f.path != null) f.path!,
  ];
}

/// 依序傳送一批檔案,並顯示進度。批次(>1)會在每個檔的 envelope 標記
/// batchCount,讓接收方收多張圖片時不跳彈窗。
Future<void> _sendWithProgress(BuildContext context, AppController c,
    DeviceInfo device, List<String> paths) async {
  if (paths.isEmpty) return;
  final progress = ValueNotifier<double>(0);
  final index = ValueNotifier<int>(0);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: ValueListenableBuilder<int>(
        valueListenable: index,
        builder: (_, i, _) => Text(
            paths.length > 1 ? '傳送中… (${i + 1}/${paths.length})' : '傳送中…'),
      ),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, v, _) => LinearProgressIndicator(value: v),
      ),
    ),
  );
  String? error;
  try {
    for (var i = 0; i < paths.length; i++) {
      index.value = i;
      progress.value = 0;
      await c.sendFile(device, paths[i],
          mime: _guessMime(paths[i]),
          batchCount: paths.length,
          onProgress: (v) => progress.value = v);
    }
  } catch (e) {
    error = '$e';
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  if (context.mounted && error != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('傳送失敗:$error')),
    );
  }
}

/// 傳送剪貼簿並在失敗時以 SnackBar 回饋(成功訊息走 [AppController.status] 橫幅)。
Future<void> _sendClipboardWithFeedback(
    BuildContext context, AppController c, DeviceInfo device) async {
  try {
    await c.sendClipboard(device);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('傳送失敗:$e')),
      );
    }
  }
}

String? _guessMime(String path) {
  final ext = path.toLowerCase().split('.').last;
  const map = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'm4v': 'video/x-m4v',
    'avi': 'video/x-msvideo',
  };
  return map[ext];
}

class _ReceivedTile extends StatelessWidget {
  final ReceivedItem item;
  const _ReceivedTile({required this.item});

  bool get _isImage =>
      item.envelope.kind == PayloadKind.clipboardImage ||
      (item.envelope.kind == PayloadKind.file &&
          (item.envelope.mime?.startsWith('image/') ?? false));

  @override
  Widget build(BuildContext context) {
    final env = item.envelope;
    if (env.kind == PayloadKind.url) {
      return ListTile(
        leading: const Icon(Icons.link),
        title: const Text('收到網址'),
        subtitle: Text(item.text ?? '',
            maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: item.text == null
            ? null
            : () => showReceivedUrlDialog(context, item.text!),
      );
    }
    if (env.kind == PayloadKind.clipboardText) {
      return ListTile(
        leading: const Icon(Icons.text_snippet),
        title: const Text('剪貼簿文字(已寫入本機剪貼簿)'),
        subtitle: Text(item.text ?? '',
            maxLines: 2, overflow: TextOverflow.ellipsis),
      );
    }
    if (_isImage && item.savedPath != null) {
      final c = context.read<AppController>();
      return ListTile(
        leading: SizedBox(
          width: 48,
          height: 48,
          child: Image.file(File(item.savedPath!), fit: BoxFit.cover),
        ),
        title: const Text('收到圖片'),
        subtitle: const Text('點此選擇複製到剪貼簿或儲存'),
        onTap: () => showReceivedImageDialog(context, item, c),
      );
    }
    final savedToGallery = Platform.isIOS &&
        (env.mime?.startsWith('image/') == true ||
            env.mime?.startsWith('video/') == true);
    return ListTile(
      leading: const Icon(Icons.insert_drive_file),
      title: Text(env.fileName ?? '檔案'),
      subtitle: Text(savedToGallery ? '已存入相簿' : (item.savedPath ?? '')),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      );
}
