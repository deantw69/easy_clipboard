import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../memos/memo_store.dart';

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

Color _memoColorOf(Memo memo) =>
    memo.colorValue != null ? Color(memo.colorValue!) : _defaultMemoColor;

/// 備忘錄分頁:便利貼風格的列表。點卡片編輯、勾選待辦、右上角新增、可拖曳排序。
class MemosPage extends StatefulWidget {
  const MemosPage({super.key});

  @override
  State<MemosPage> createState() => _MemosPageState();
}

class _MemosPageState extends State<MemosPage> {
  // 收合狀態(只存本機,不同步)。
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final store = context.watch<MemoStore>();
    final memos = store.visibleMemos;
    return Scaffold(
      appBar: AppBar(
        title: const Text('備忘錄'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增備忘錄',
            onPressed: () => _openEditor(context, store, null),
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
              // 拖曳浮起時只保留卡片本身的陰影,避免出現多餘白邊。
              proxyDecorator: (child, index, animation) => Material(
                color: Colors.transparent,
                elevation: 6,
                borderRadius: BorderRadius.circular(12),
                child: child,
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
/// 向左滑露出固定寬度的刪除鈕(仿 Line),點紅色區才跳確認;右上角可收合/展開。
class _MemoCard extends StatelessWidget {
  final Memo memo;
  final bool collapsed;
  final VoidCallback onToggleCollapse;
  const _MemoCard({
    required this.memo,
    required this.collapsed,
    required this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.read<MemoStore>();
    final hasBody = memo.todos.isNotEmpty;
    final hasText = memo.text.trim().isNotEmpty;
    return _SwipeRevealDelete(
      onDelete: () async {
        final ok = await _confirmDelete(context);
        if (ok) store.delete(memo.id);
        return ok;
      },
      child: Card(
        color: _memoColorOf(memo),
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          onTap: () => _openEditor(context, store, memo),
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 標題列 + 收合/展開鈕(原刪除鈕位置)。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: hasText
                          ? Text(
                              memo.text,
                              style: const TextStyle(
                                  fontSize: 15, color: Colors.black87),
                            )
                          : const SizedBox.shrink(),
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
                          constraints:
                              const BoxConstraints.tightFor(width: 28),
                          onPressed: onToggleCollapse,
                        ),
                      ),
                  ],
                ),
                if (!collapsed)
                  for (final todo in memo.todos)
                    Builder(builder: (context) {
                      final isUrl = _isUrl(todo.text);
                      return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          // 只有 checkbox 可點選勾選。
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => store.toggleTodo(memo.id, todo.id),
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
                          const SizedBox(width: 6),
                          Expanded(
                            child: Builder(
                              builder: (_) {
                                final baseStyle = TextStyle(
                                  color:
                                      isUrl ? Colors.blue.shade700 : Colors.black87,
                                  decoration: todo.done
                                      ? TextDecoration.lineThrough
                                      : (isUrl
                                          ? TextDecoration.underline
                                          : null),
                                  decorationColor:
                                      isUrl ? Colors.blue.shade700 : null,
                                );
                                if (!isUrl) {
                                  return Text(todo.text, style: baseStyle);
                                }
                                return Text.rich(
                                  TextSpan(
                                    text: todo.text,
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
                            IconButton(
                              icon: const Icon(Icons.copy,
                                  size: 18, color: Colors.black45),
                              tooltip: '複製',
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              constraints:
                                  const BoxConstraints.tightFor(width: 24),
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: todo.text));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已複製')),
                                  );
                                }
                              },
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    );
                    }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 向左滑露出固定寬度的紅色刪除鈕;點紅色區才觸發 [onDelete](回傳是否已刪除)。
/// 紅色鈕與卡片同高同圓角貼齊,避免露出多餘白邊。
class _SwipeRevealDelete extends StatefulWidget {
  final Widget child;
  final Future<bool> Function() onDelete;
  const _SwipeRevealDelete({required this.child, required this.onDelete});

  @override
  State<_SwipeRevealDelete> createState() => _SwipeRevealDeleteState();
}

class _SwipeRevealDeleteState extends State<_SwipeRevealDelete>
    with SingleTickerProviderStateMixin {
  static const double _revealWidth = 76;
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180));
  Animation<double>? _anim;
  double _dx = 0;

  void _animateTo(double target) {
    _anim = Tween<double>(begin: _dx, end: target).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut))
      ..addListener(() => setState(() => _dx = _anim!.value));
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleDelete() async {
    final deleted = await widget.onDelete();
    if (!deleted && mounted) _animateTo(0); // 取消則收回
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
                onTap: _handleDelete,
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

/// 刪除前確認。
Future<bool> _confirmDelete(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('刪除備忘錄'),
      content: const Text('確定要刪除這則備忘錄嗎?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('刪除'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 刪除待辦前確認。
Future<bool> _confirmRemoveTodo(BuildContext context, String text) async {
  final label = text.trim();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('刪除待辦'),
      content: Text(label.isEmpty ? '確定要刪除這個待辦項目嗎?' : '確定要刪除「$label」嗎?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('刪除'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// 開啟編輯器([memo] 為 null 表示新增)。
Future<void> _openEditor(
    BuildContext context, MemoStore store, Memo? memo) async {
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
  late int? _colorValue;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.memo?.text ?? '');
    _colorValue = widget.memo?.colorValue;
    _todos = widget.memo == null
        ? []
        : widget.memo!.todos
            .map((t) => MemoTodo(id: t.id, text: t.text, done: t.done))
            .toList();
    for (final t in _todos) {
      _todoCtrls.add(TextEditingController(text: t.text));
    }
  }

  @override
  void dispose() {
    _text.dispose();
    for (final c in _todoCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addTodo() {
    setState(() {
      _todos.add(MemoTodo.create());
      _todoCtrls.add(TextEditingController());
    });
  }

  Future<void> _removeTodo(int i) async {
    // 同步最新文字以顯示在確認對話框。
    _todos[i].text = _todoCtrls[i].text;
    final ok = await _confirmRemoveTodo(context, _todos[i].text);
    if (!ok || !mounted) return;
    setState(() {
      _todos.removeAt(i);
      _todoCtrls.removeAt(i).dispose();
    });
  }

  void _save() {
    // 同步暫存待辦的文字。
    for (var i = 0; i < _todos.length; i++) {
      _todos[i].text = _todoCtrls[i].text;
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
      });
    } else {
      widget.store.update(widget.memo!.id, (m) {
        m.text = text;
        m.todos = todos;
        m.colorValue = _colorValue;
      });
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.memo == null ? '新增備忘錄' : '編輯備忘錄'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 色票選擇。
              Wrap(
                spacing: 10,
                children: [
                  for (final c in kMemoColors)
                    _ColorSwatch(
                      color: c,
                      selected:
                          (_colorValue ?? _defaultMemoColor.toARGB32()) ==
                              c.toARGB32(),
                      onTap: () => setState(() => _colorValue =
                          c.toARGB32() == _defaultMemoColor.toARGB32()
                              ? null
                              : c.toARGB32()),
                    ),
                ],
              ),
              const SizedBox(height: 12),
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _todoCtrls[i],
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '待辦項目',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => _removeTodo(i),
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
  final bool selected;
  final VoidCallback onTap;
  const _ColorSwatch(
      {required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
    );
  }
}
