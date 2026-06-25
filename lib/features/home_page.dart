import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_controller.dart';
import '../core/models.dart';

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
      ),
      body: !c.ready
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (Platform.isIOS) const _IosNotice(),
                if (c.status != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(c.status!,
                        style: const TextStyle(color: Colors.teal)),
                  ),
                _SectionTitle('附近的裝置 (${c.devices.length})'),
                Expanded(
                  flex: 2,
                  child: c.devices.isEmpty
                      ? const Center(child: Text('搜尋中… 確認在同一個 Wi-Fi'))
                      : ListView(
                          children: [
                            for (final d in c.devices)
                              _DeviceTile(device: d),
                          ],
                        ),
                ),
                const Divider(height: 1),
                _SectionTitle('收到的內容 (${c.received.length})'),
                Expanded(
                  flex: 1,
                  child: ListView(
                    children: [
                      for (final r in c.received) _ReceivedTile(item: r),
                    ],
                  ),
                ),
              ],
            ),
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
      onTap: () => _showActions(context, device),
    );
  }

  void _showActions(BuildContext context, DeviceInfo device) {
    final c = context.read<AppController>();
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('傳送圖片 / 影片'),
              onTap: () async {
                Navigator.pop(context);
                await _pickAndSend(context, c, device);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('傳送剪貼簿'),
              onTap: () async {
                Navigator.pop(context);
                await c.sendClipboard(device);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSend(
      BuildContext context, AppController c, DeviceInfo device) async {
    final path = await _pickMediaPath();
    if (path == null) return;
    if (!context.mounted) return;
    await _sendWithProgress(context, c, device, path);
  }
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

  @override
  Widget build(BuildContext context) {
    final env = item.envelope;
    switch (env.kind) {
      case PayloadKind.clipboardText:
        return ListTile(
          leading: const Icon(Icons.text_snippet),
          title: const Text('剪貼簿文字(已寫入本機剪貼簿)'),
          subtitle: Text(item.text ?? '',
              maxLines: 2, overflow: TextOverflow.ellipsis),
        );
      case PayloadKind.clipboardImage:
        return ListTile(
          leading: const Icon(Icons.image),
          title: const Text('剪貼簿圖片(已寫入本機剪貼簿)'),
          subtitle: Text(item.savedPath ?? ''),
        );
      case PayloadKind.file:
        return ListTile(
          leading: const Icon(Icons.insert_drive_file),
          title: Text(env.fileName ?? '檔案'),
          subtitle: Text(item.savedPath ?? ''),
        );
    }
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
        'iOS 限制:需保持 App 開啟才能收發;剪貼簿須手動按「傳送剪貼簿」。',
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
