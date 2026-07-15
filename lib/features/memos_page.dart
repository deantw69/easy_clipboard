import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../memos/memo_store.dart';

/// 桌面平台(滑鼠環境)才顯示 hover 浮現的拖曳把手/刪除鈕。
bool get _isDesktopPlatform =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// 判斷待辦文字是否為網址(以 http(s):// 開頭)。
bool _isUrl(String text) {
  final t = text.trim();
  if (!t.startsWith('http://') && !t.startsWith('https://')) return false;
  final uri = Uri.tryParse(t);
  return uri != null && uri.hasAuthority;
}

Future<void> _openUrl(String text) async {
  final uri = Uri.tryParse(text.trim());
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// 便利貼固定色票(淺色系)。第一個為預設黃。
const Color _defaultMemoColor = Color(0xFFFFF8C4);
const List<Color> kMemoColors = [
  _defaultMemoColor, // 黃(預設)
  Color(0xFFFFD9DE), // 粉紅
  Color(0xFFCDE7FF), // 藍
  Color(0xFFD4F4D2), // 綠
  Color(0xFFFFE0BD), // 橘
  Color(0xFFE6D9FF), // 紫
];

/// 與 kMemoColors 對應的顏色名稱(無障礙 Semantics 用)。
const List<String> kMemoColorNames = ['黃', '粉紅', '藍', '綠', '橘', '紫'];

Color _memoColorOf(Memo memo) =>
    memo.colorValue != null ? Color(memo.colorValue!) : _defaultMemoColor;

/// 卡片實際底色:深色模式把固定淺色票壓暗,避免在深色 UI 上過亮刺眼,
/// 仍保持足夠淺以襯托黑色文字/刪除線。淺色模式維持原色。
Color _memoCardColor(Memo memo, Brightness brightness) {
  final base = _memoColorOf(memo);
  return brightness == Brightness.dark
      ? Color.lerp(base, Colors.black, 0.32)!
      : base;
}

/// 備忘錄分頁:便利貼風格的列表。點卡片編輯、勾選待辦、右上角新增、可拖曳排序。
class MemosPage extends StatefulWidget {
  const MemosPage({super.key});

  @override
  State<MemosPage> createState() => _MemosPageState();
}

class _MemosPageState extends State<MemosPage> {
  // 收合狀態(只存本機,不同步)。
  final Set<String> _collapsed = {};
  bool _busy = false;

  /// 重設本機備忘錄,改以其他裝置為準重新拉取。
  Future<void> _resetAndResync() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重設備忘錄並重新同步'),
        content: const Text(
          '會清空「這台裝置」上的所有備忘錄,改從其他裝置重新拉取,以其他裝置為準還原。\n\n'
          '適用於本機資料異常(例如重裝前未同步、又在舊狀態上編輯過)時。\n\n'
          '請先確認:要當作來源的裝置已開啟、且與本機在同一區網,'
          '否則本機會被清空且拉不回資料。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重設並同步'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await context.read<AppController>().resetMemosAndResync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              n > 0 ? '已重設,從 $n 台裝置重新同步' : '已重設,但目前找不到其他裝置可拉取(本機暫為空)',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 設定同步群組碼:只有填相同碼的裝置才會自動同步備忘錄。
  Future<void> _changeGroupCode() async {
    final c = context.read<AppController>();
    final controller = TextEditingController(text: c.groupCode);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('同步群組碼'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '只有填相同群組碼的裝置才會自動同步備忘錄。\n'
              '留空 = 與所有同網裝置同步(預設)。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '例如:home',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await c.updateGroupCode(result);
      if (mounted && c.memoSyncFailing) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('群組碼已更新,但目前無法與其他裝置同步')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 匯出全部備忘錄為 JSON 檔(手動備份)。桌面選存檔位置後自行寫入;
  /// 行動裝置透過 file_picker 直接帶 bytes 存檔。
  Future<void> _exportMemos() async {
    final store = context.read<MemoStore>();
    final messenger = ScaffoldMessenger.of(context);
    final jsonStr = store.exportJson();
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));
    final now = DateTime.now();
    final stamp = '${now.year}${_two(now.month)}${_two(now.day)}'
        '_${_two(now.hour)}${_two(now.minute)}';
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: '匯出備忘錄',
        fileName: 'syncnest_memos_$stamp.json',
        // 行動裝置需帶 bytes 才會實際寫檔;桌面回傳路徑後由我們自行寫入。
        bytes: _isDesktopPlatform ? null : bytes,
      );
      if (path == null) return; // 使用者取消。
      if (_isDesktopPlatform) await File(path).writeAsString(jsonStr);
      messenger.showSnackBar(const SnackBar(content: Text('已匯出備忘錄')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('匯出失敗:$e')));
    }
  }

  /// 匯入 JSON 備份:走 LWW 合併(不覆蓋較新的本機資料),合併後自動推送同步。
  Future<void> _importMemos() async {
    final store = context.read<MemoStore>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: '匯入備忘錄',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return; // 取消。
      final f = result.files.single;
      final content = f.bytes != null
          ? utf8.decode(f.bytes!)
          : await File(f.path!).readAsString();
      final n = store.importJson(content);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(n < 0
            ? '匯入失敗:檔案格式不正確'
            : n == 0
                ? '匯入完成,沒有需要更新的備忘錄'
                : '已匯入/更新 $n 則備忘錄'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('匯入失敗:$e')));
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 同步警告(失敗/時鐘偏移)的說明對話框。
  Future<void> _showSyncWarning(AppController app) async {
    final buf = StringBuffer();
    if (app.memoSyncFailing) {
      buf.writeln('目前無法與其他裝置同步備忘錄。');
      buf.writeln('上次成功同步:${_fmtAgo(app.lastMemoSyncAt)}。');
      buf.writeln('請確認其他裝置已開啟、且與本機在同一區網。');
    }
    final skew = app.clockSkew;
    if (skew != null) {
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln('偵測到與其他裝置的系統時鐘相差約 ${skew.inMinutes.abs()} 分鐘。');
      buf.writeln('時鐘偏差可能導致同步時,較新的編輯被較舊的資料覆蓋。');
      buf.writeln('建議校正本機或對方裝置的系統時間(開啟自動對時)。');
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('同步狀態'),
        content: Text(buf.toString().trimRight()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  static String _fmtAgo(DateTime? t) {
    if (t == null) return '尚無成功紀錄';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '剛剛';
    if (d.inMinutes < 60) return '${d.inMinutes} 分鐘前';
    if (d.inHours < 24) return '${d.inHours} 小時前';
    return '${d.inDays} 天前';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MemoStore>();
    final app = context.watch<AppController>();
    final memos = store.visibleMemos;
    final showSyncWarning = app.memoSyncFailing || app.clockSkew != null;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('備忘錄'),
        actions: [
          if (showSyncWarning)
            IconButton(
              icon: const Icon(Icons.sync_problem, color: Colors.amber),
              tooltip: app.clockSkew != null ? '裝置時鐘偏移' : '同步異常',
              onPressed: () => _showSyncWarning(app),
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增備忘錄',
            onPressed: () => _openEditor(context, store, null),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            enabled: !_busy,
            onSelected: (value) {
              if (value == 'reset') _resetAndResync();
              if (value == 'group') _changeGroupCode();
              if (value == 'export') _exportMemos();
              if (value == 'import') _importMemos();
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'group',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.group_work_outlined),
                  title: Text('同步群組碼'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'export',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.upload_file),
                  title: Text('匯出備忘錄'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'import',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download),
                  title: Text('匯入備忘錄'),
                ),
              ),
              const PopupMenuItem<String>(
                value: 'reset',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.sync_problem, color: Colors.redAccent),
                  title: Text('重設備忘錄並重新同步'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: memos.isEmpty
          ? const Center(child: Text('還沒有備忘錄,點右上角 + 新增'))
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: memos.length,
              // 桌面端不顯示預設的兩條橫槓拖曳把手,改用整列長按拖曳(與手機一致)。
              buildDefaultDragHandles: false,
              // 拖曳浮起時只保留卡片本身的陰影並微放大,強化「正在拖曳」回饋。
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: Transform.scale(scale: 1.02, child: child),
              ),
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex -= 1;
                final ids = memos.map((m) => m.id).toList();
                final moved = ids.removeAt(oldIndex);
                ids.insert(newIndex, moved);
                store.reorder(ids);
              },
              itemBuilder: (_, i) {
                final memo = memos[i];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(memo.id),
                  index: i,
                  child: _MemoCard(
                    memo: memo,
                    index: i,
                    collapsed: _collapsed.contains(memo.id),
                    onToggleCollapse: () => setState(() {
                      if (!_collapsed.add(memo.id)) _collapsed.remove(memo.id);
                    }),
                  ),
                );
              },
            ),
    );
  }
}

/// 便利貼卡片:顯示文字與待辦勾選;點卡片進編輯。
/// 向左滑露出固定寬度的刪除鈕(仿 Line);桌面滑鼠 hover 另浮現拖曳把手與刪除鈕。
/// 刪除立即生效,SnackBar 提供 5 秒「復原」;右上角可收合/展開,收合時標題截為單行。
class _MemoCard extends StatefulWidget {
  final Memo memo;
  final int index;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  const _MemoCard({
    required this.memo,
    required this.index,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  @override
  State<_MemoCard> createState() => _MemoCardState();
}

class _MemoCardState extends State<_MemoCard> {
  bool _hovered = false;

  /// 立即刪除並以 SnackBar 提供復原(取代原本的確認對話框)。
  void _deleteWithUndo() {
    final store = context.read<MemoStore>();
    final messenger = ScaffoldMessenger.of(context);
    final id = widget.memo.id;
    store.delete(id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('已刪除備忘錄'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '復原',
            onPressed: () => store.restore(id),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<MemoStore>();
    final memo = widget.memo;
    final collapsed = widget.collapsed;
    final hasBody = memo.todos.isNotEmpty;
    final hasText = memo.text.trim().isNotEmpty;
    return _SwipeRevealDelete(
      onDelete: _deleteWithUndo,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Card(
          color: _memoCardColor(memo, Theme.of(context).brightness),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: InkWell(
            onTap: () => _openEditor(context, store, memo),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題列 + hover 操作鈕 + 收合/展開鈕。
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: hasText
                            ? Text(
                                memo.text,
                                // 收合時只留單行標題,避免超長文字撐開卡片。
                                maxLines: collapsed ? 1 : null,
                                overflow: collapsed
                                    ? TextOverflow.ellipsis
                                    : null,
                                style: const TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      // 桌面 hover 才浮現:明確的拖曳把手與刪除鈕
                      // (touch 裝置維持長按拖曳、左滑刪除)。
                      // maintainSize 保留空間,避免 hover 時版面跳動。
                      if (_isDesktopPlatform)
                        Visibility(
                          visible: _hovered,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ReorderableDragStartListener(
                                index: widget.index,
                                child: const MouseRegion(
                                  cursor: SystemMouseCursors.grab,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 2,
                                      vertical: 2,
                                    ),
                                    child: Icon(
                                      Icons.drag_indicator,
                                      size: 18,
                                      color: Colors.black38,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 22,
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.black45,
                                  ),
                                  tooltip: '刪除',
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 24,
                                  ),
                                  onPressed: _deleteWithUndo,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (hasBody)
                        SizedBox(
                          height: 22,
                          child: IconButton(
                            icon: Icon(
                              collapsed ? Icons.expand_more : Icons.expand_less,
                              size: 20,
                              color: Colors.black45,
                            ),
                            tooltip: collapsed ? '展開' : '收合',
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 28,
                            ),
                            onPressed: widget.onToggleCollapse,
                          ),
                        ),
                    ],
                  ),
                  if (!collapsed)
                    for (final todo in memo.todos)
                      Builder(
                        builder: (context) {
                          final isUrl = _isUrl(todo.text);
                          final fixed = memo.fixed;
                          // 固定模式且網址有名稱時,顯示名稱作為超連結文字。
                          final label = todo.label?.trim() ?? '';
                          final display = fixed && isUrl && label.isNotEmpty
                              ? label
                              : todo.text;
                          // 固定模式視為純清單:不理會 done(不畫刪除線)。
                          final struck = !fixed && todo.done;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                // 固定模式不顯示勾勾,改用項目符號;否則顯示可點選的 checkbox。
                                if (fixed)
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
                                    child: Text(
                                      '•',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  )
                                else
                                  Semantics(
                                    checked: todo.done,
                                    label:
                                        todo.done ? '取消標記完成' : '標記完成',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () =>
                                          store.toggleTodo(memo.id, todo.id),
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Icon(
                                          todo.done
                                              ? Icons.check_box
                                              : Icons.check_box_outline_blank,
                                          size: 20,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Builder(
                                    builder: (_) {
                                      final baseStyle = TextStyle(
                                        color: isUrl
                                            ? Colors.blue.shade700
                                            : Colors.black87,
                                        decoration: struck
                                            ? TextDecoration.lineThrough
                                            : (isUrl
                                                  ? TextDecoration.underline
                                                  : null),
                                        decorationColor: isUrl
                                            ? Colors.blue.shade700
                                            : Colors.black,
                                        decorationThickness: struck ? 2 : 1,
                                      );
                                      if (!isUrl) {
                                        return Text(
                                          display,
                                          style: baseStyle,
                                        );
                                      }
                                      return Text.rich(
                                        TextSpan(
                                          text: display,
                                          style: baseStyle,
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () => _openUrl(todo.text),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                // 只有網址才顯示右側複製鈕。
                                if (isUrl) ...[
                                  const SizedBox(width: 6),
                                  // 用 InkWell 而非 IconButton:IconButton 會套用
                                  // Material 最小點擊區塊(tap target)padding 撐高列高。
                                  Tooltip(
                                    message: '複製',
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(4),
                                      onTap: () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: todo.text),
                                        );
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('已複製'),
                                            ),
                                          );
                                        }
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.copy,
                                          size: 18,
                                          color: Colors.black45,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 向左滑露出固定寬度的紅色刪除鈕;點紅色區觸發 [onDelete]
/// (立即刪除,復原機制由呼叫端的 SnackBar 提供)。
/// 紅色鈕與卡片同高同圓角貼齊,避免露出多餘白邊。
class _SwipeRevealDelete extends StatefulWidget {
  final Widget child;
  final VoidCallback onDelete;
  const _SwipeRevealDelete({required this.child, required this.onDelete});

  @override
  State<_SwipeRevealDelete> createState() => _SwipeRevealDeleteState();
}

class _SwipeRevealDeleteState extends State<_SwipeRevealDelete>
    with SingleTickerProviderStateMixin {
  static const double _revealWidth = 76;
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  Animation<double>? _anim;
  double _dx = 0;

  void _animateTo(double target) {
    _anim = Tween<double>(begin: _dx, end: target).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    )..addListener(() => setState(() => _dx = _anim!.value));
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 紅色刪除鈕(與卡片相同 vertical margin / 圓角,貼齊不留白邊)。
        // 收合狀態(_dx==0)不繪製,避免卡片右側圓角透出紅色。
        if (_dx != 0)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: widget.onDelete,
                  child: Container(
                    width: _revealWidth,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        GestureDetector(
          onHorizontalDragUpdate: (d) => setState(() {
            _dx = (_dx + d.delta.dx).clamp(-_revealWidth, 0.0);
          }),
          onHorizontalDragEnd: (_) =>
              _animateTo(_dx < -_revealWidth / 2 ? -_revealWidth : 0),
          child: Transform.translate(
            offset: Offset(_dx, 0),
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

/// 開啟編輯器([memo] 為 null 表示新增)。
Future<void> _openEditor(
  BuildContext context,
  MemoStore store,
  Memo? memo,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _MemoEditor(store: store, memo: memo),
  );
}

class _MemoEditor extends StatefulWidget {
  final MemoStore store;
  final Memo? memo;
  const _MemoEditor({required this.store, this.memo});

  @override
  State<_MemoEditor> createState() => _MemoEditorState();
}

class _MemoEditorState extends State<_MemoEditor> {
  late final TextEditingController _text;
  // 編輯時用暫存的待辦清單,按「儲存」才寫回。
  late final List<MemoTodo> _todos;
  final List<TextEditingController> _todoCtrls = [];
  // 網址名稱(固定模式用),與 _todos 一一對應。
  final List<TextEditingController> _labelCtrls = [];
  final List<FocusNode> _todoNodes = [];
  late int? _colorValue;
  late bool _fixed;

  // 最後一筆被刪的待辦,供編輯器內「復原」(5 秒後失效)。
  MemoTodo? _removedTodo;
  int _removedIndex = 0;
  Timer? _undoTimer;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.memo?.text ?? '');
    _colorValue = widget.memo?.colorValue;
    _fixed = widget.memo?.fixed ?? false;
    _todos = widget.memo == null
        ? []
        : widget.memo!.todos
              .map((t) =>
                  MemoTodo(id: t.id, text: t.text, done: t.done, label: t.label))
              .toList();
    for (final t in _todos) {
      _todoCtrls.add(TextEditingController(text: t.text));
      _labelCtrls.add(TextEditingController(text: t.label ?? ''));
      _todoNodes.add(FocusNode());
    }
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _text.dispose();
    for (final c in _todoCtrls) {
      c.dispose();
    }
    for (final c in _labelCtrls) {
      c.dispose();
    }
    for (final n in _todoNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _addTodo() {
    setState(() {
      _todos.add(MemoTodo.create());
      _todoCtrls.add(TextEditingController());
      _labelCtrls.add(TextEditingController());
      _todoNodes.add(FocusNode());
    });
    // 等新列 build 完成後聚焦,配合 Enter 連續輸入。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _todoNodes.isNotEmpty) _todoNodes.last.requestFocus();
    });
  }

  /// Enter:非最後一列跳到下一列;最後一列有內容則新增下一列。
  void _submitTodo(int i) {
    if (i < _todos.length - 1) {
      _todoNodes[i + 1].requestFocus();
    } else if (_todoCtrls[i].text.trim().isNotEmpty) {
      _addTodo();
    }
  }

  /// 立即移除待辦,保留一筆可在編輯器內「復原」。
  void _removeTodo(int i) {
    _undoTimer?.cancel();
    final removed = _todos[i]
      ..text = _todoCtrls[i].text
      ..label = _labelCtrls[i].text;
    setState(() {
      _todos.removeAt(i);
      _todoCtrls.removeAt(i).dispose();
      _labelCtrls.removeAt(i).dispose();
      _todoNodes.removeAt(i).dispose();
      _removedTodo = removed;
      _removedIndex = i;
    });
    _undoTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _removedTodo = null);
    });
  }

  void _undoRemoveTodo() {
    final t = _removedTodo;
    if (t == null) return;
    _undoTimer?.cancel();
    setState(() {
      final i = _removedIndex.clamp(0, _todos.length);
      _todos.insert(i, t);
      _todoCtrls.insert(i, TextEditingController(text: t.text));
      _labelCtrls.insert(i, TextEditingController(text: t.label ?? ''));
      _todoNodes.insert(i, FocusNode());
      _removedTodo = null;
    });
  }

  void _save() {
    // 同步暫存待辦的文字與網址名稱。
    for (var i = 0; i < _todos.length; i++) {
      _todos[i].text = _todoCtrls[i].text;
      final label = _labelCtrls[i].text.trim();
      _todos[i].label = label.isEmpty ? null : label;
    }
    final todos = _todos.where((t) => t.text.trim().isNotEmpty).toList();
    final text = _text.text;
    if (widget.memo == null) {
      if (text.trim().isEmpty && todos.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      final memo = widget.store.add(text: text);
      widget.store.update(memo.id, (m) {
        m.todos = todos;
        m.colorValue = _colorValue;
        m.fixed = _fixed;
      });
    } else {
      widget.store.update(widget.memo!.id, (m) {
        m.text = text;
        m.todos = todos;
        m.colorValue = _colorValue;
        m.fixed = _fixed;
      });
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // 依螢幕自適應:桌面大螢幕加寬(上限 560),小螢幕扣掉 dialog 內外邊距;
    // 高度限制在螢幕 6 成,避免長待辦清單把動作按鈕擠出畫面。
    final size = MediaQuery.sizeOf(context);
    final width = math.min(560.0, math.max(280.0, size.width - 144));
    final maxHeight = math.max(200.0, size.height * 0.6);
    return AlertDialog(
      title: Text(widget.memo == null ? '新增備忘錄' : '編輯備忘錄'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 色票選擇。
                Wrap(
                  spacing: 10,
                  children: [
                    for (final (i, c) in kMemoColors.indexed)
                      _ColorSwatch(
                        color: c,
                        label: kMemoColorNames[i],
                        selected:
                            (_colorValue ?? _defaultMemoColor.toARGB32()) ==
                            c.toARGB32(),
                        onTap: () => setState(
                          () => _colorValue =
                              c.toARGB32() == _defaultMemoColor.toARGB32()
                              ? null
                              : c.toARGB32(),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // 固定模式:待辦當純清單顯示(無勾勾/刪除線),網址可設名稱。
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('固定模式'),
                  subtitle: const Text('清單不顯示勾勾,網址可設名稱超連結'),
                  value: _fixed,
                  onChanged: (v) => setState(() => _fixed = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _text,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: '內容',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < _todos.length; i++)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _todoCtrls[i],
                              focusNode: _todoNodes[i],
                              textInputAction: TextInputAction.next,
                              // 覆寫預設行為:Enter 跳下一列或在最後一列連續新增。
                              onEditingComplete: () => _submitTodo(i),
                              // 固定模式下即時顯示/隱藏網址名稱欄。
                              onChanged: _fixed ? (_) => setState(() {}) : null,
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: _fixed ? '項目 / 網址' : '待辦項目',
                              ),
                            ),
                          ),
                          // 排除 Tab 焦點,讓 Tab 只在待辦欄位間跳。
                          ExcludeFocus(
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              tooltip: '刪除待辦',
                              onPressed: () => _removeTodo(i),
                            ),
                          ),
                        ],
                      ),
                      // 固定模式且該列是網址時,顯示選填的名稱欄。
                      if (_fixed && _isUrl(_todoCtrls[i].text))
                        Padding(
                          padding: const EdgeInsets.only(left: 12, right: 48),
                          child: TextField(
                            controller: _labelCtrls[i],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.link, size: 18),
                              prefixIconConstraints:
                                  BoxConstraints(minWidth: 28),
                              hintText: '連結名稱(選填)',
                            ),
                          ),
                        ),
                    ],
                  ),
                if (_removedTodo != null)
                  Row(
                    children: [
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _removedTodo!.text.trim().isEmpty
                              ? '已刪除待辦'
                              : '已刪除「${_removedTodo!.text.trim()}」',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      TextButton(
                        onPressed: _undoRemoveTodo,
                        child: const Text('復原'),
                      ),
                    ],
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('新增待辦'),
                    onPressed: _addTodo,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('儲存')),
      ],
    );
  }
}

/// 可點選的圓形色票,選中時顯示外框。
class _ColorSwatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ColorSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '選擇顏色 $label',
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.black87 : Colors.black26,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 18, color: Colors.black54)
            : null,
        ),
      ),
    );
  }
}
