import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../memos/memo_store.dart';

/// 備忘錄分頁:便利貼風格的列表。點卡片編輯、勾選待辦、右上角新增。
class MemosPage extends StatelessWidget {
  const MemosPage({super.key});

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
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: memos.length,
              itemBuilder: (_, i) => _MemoCard(memo: memos[i]),
            ),
    );
  }
}

/// 便利貼卡片:顯示文字與待辦勾選;點卡片進編輯。
class _MemoCard extends StatelessWidget {
  final Memo memo;
  const _MemoCard({required this.memo});

  @override
  Widget build(BuildContext context) {
    final store = context.read<MemoStore>();
    return Card(
      color: const Color(0xFFFFF8C4), // 便利貼黃
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: () => _openEditor(context, store, memo),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (memo.text.trim().isNotEmpty)
                      Text(
                        memo.text,
                        style: const TextStyle(
                            fontSize: 15, color: Colors.black87),
                      ),
                    for (final todo in memo.todos)
                      InkWell(
                        onTap: () => store.toggleTodo(memo.id, todo.id),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                todo.done
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                size: 20,
                                color: Colors.black54,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  todo.text,
                                  style: TextStyle(
                                    color: Colors.black87,
                                    decoration: todo.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: Colors.black45),
                tooltip: '刪除',
                onPressed: () => store.delete(memo.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.memo?.text ?? '');
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

  void _removeTodo(int i) {
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
      widget.store.update(memo.id, (m) => m.todos = todos);
    } else {
      widget.store.update(widget.memo!.id, (m) {
        m.text = text;
        m.todos = todos;
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
            children: [
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
                    const Icon(Icons.check_box_outline_blank,
                        size: 20, color: Colors.black38),
                    const SizedBox(width: 6),
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
