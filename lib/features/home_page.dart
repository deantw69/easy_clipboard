import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../core/autostart.dart';
import '../core/models.dart';

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// 第一頁:附近的裝置清單。點選裝置即「連上」並進入該裝置的傳輸頁。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(c.local == null
            ? 'EasyClipboard'
            : '${c.local!.name} · ${c.local!.platform}'),
        actions: [
          if (AutostartService.supported)
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
                if (Platform.isIOS) const _IosNotice(),
                _SectionTitle('附近的裝置 (${c.devices.length})'),
                Expanded(
                  child: c.devices.isEmpty
                      ? const Center(child: Text('搜尋中… 確認在同一個 Wi-Fi'))
                      : ListView(
                          children: [
                            for (final d in c.devices)
                              _DeviceTile(device: d),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
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
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AutostartService.isEnabled().then((v) {
      if (mounted) setState(() => _autostart = v);
    });
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
      content: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('開機自動啟動'),
        subtitle: const Text('登入系統時自動開啟 EasyClipboard'),
        value: _autostart ?? false,
        onChanged: (_autostart == null || _busy) ? null : _toggle,
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

class _DeviceTile extends StatelessWidget {
  final DeviceInfo device;
  const _DeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.devices),
      title: Text(device.name),
      subtitle: Text('${device.platform} · ${device.host}:${device.port}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DevicePage(device: device)),
      ),
    );
  }
}

/// 第二頁:已連上某裝置。上半部為傳送操作,下半部為收到的內容。
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
        const Divider(height: 1),
        _SectionTitle('收到的內容 (${c.received.length})'),
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
            final path = await _pickMediaPath();
            if (path == null || !context.mounted) return;
            await _sendWithProgress(context, c, device, path);
          },
        ),
        ListTile(
          leading: const Icon(Icons.content_paste),
          title: const Text('傳送剪貼簿'),
          onTap: () => c.sendClipboard(device),
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
            c.sendClipboard(device),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
            c.sendClipboard(device),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
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
          child: Text(c.isDesktop ? '在 Finder 顯示' : '存進相簿'),
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
        for (final file in detail.files) {
          if (!context.mounted) return;
          await _sendWithProgress(context, c, widget.device, file.path);
        }
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

/// 依平台選取圖片/影片,回傳本機路徑。
Future<String?> _pickMediaPath() async {
  if (Platform.isIOS || Platform.isAndroid) {
    final x = await ImagePicker().pickMedia();
    return x?.path;
  }
  final res = await FilePicker.pickFiles(type: FileType.media);
  return res?.files.single.path;
}

Future<void> _sendWithProgress(BuildContext context, AppController c,
    DeviceInfo device, String path) async {
  final progress = ValueNotifier<double>(0);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('傳送中…'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, v, _) => LinearProgressIndicator(value: v),
      ),
    ),
  );
  try {
    await c.sendFile(device, path, mime: _guessMime(path),
        onProgress: (v) => progress.value = v);
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
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

class _IosNotice extends StatelessWidget {
  const _IosNotice();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber.withValues(alpha: 0.2),
      padding: const EdgeInsets.all(8),
      child: const Text(
        'iOS 限制:需保持 App 開啟才能收發;剪貼簿須手動按「傳送剪貼簿」。收到圖片時會跳預覽,自行選擇複製到剪貼簿或存進相簿;影片仍直接存入相簿。',
        style: TextStyle(fontSize: 12),
      ),
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
