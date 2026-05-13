import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cards/base_card.dart';
import '../services/user_card_store.dart';

/// 各卡片共用的「新建 / 编辑」表单；Esc 关闭当前路由
class CardItemFormPage extends StatefulWidget {
  final int cardIndex;
  final List<Color> gradient;
  final String cardTitle;
  final UserCardStore userCardStore;
  final CardItem? editingItem;

  const CardItemFormPage({
    super.key,
    required this.cardIndex,
    required this.gradient,
    required this.cardTitle,
    required this.userCardStore,
    this.editingItem,
  });

  @override
  State<CardItemFormPage> createState() => _CardItemFormPageState();
}

class _CardItemFormPageState extends State<CardItemFormPage> {
  final _primaryController = TextEditingController();
  final _tagsController = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.editingItem != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editingItem;
    if (e != null) {
      _primaryController.text = (e.data as String?) ?? '';
      _tagsController.text = e.tags.join(', ');
    }
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _primaryController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!mounted) return false;
    Navigator.of(context).pop(false);
    return true;
  }

  List<String> _parseTags() {
    return _tagsController.text
        .split(RegExp(r'[,，\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _pickExe() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe', 'bat', 'cmd', 'lnk', 'msi'],
    );
    if (r != null && r.files.isNotEmpty) {
      final p = r.files.single.path;
      if (p != null) _primaryController.text = p;
    }
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
    });
    final tags = _parseTags();
    final primary = _primaryController.text.trim();
    final old = widget.editingItem;

    switch (widget.cardIndex) {
      case 0:
        if (primary.isEmpty) {
          setState(() => _error = '请填写可执行文件路径');
          return;
        }
        final oldPath = old?.data as String?;
        if (oldPath == null || primary != oldPath) {
          if (!File(primary).existsSync()) {
            setState(() => _error = '文件不存在');
            return;
          }
        }
        if (old != null) {
          await widget.userCardStore.updateApp(
            oldPath: old.data as String,
            path: primary,
            tags: tags,
          );
        } else {
          await widget.userCardStore.addApp(path: primary, tags: tags);
        }
        break;
      case 1:
        if (primary.isEmpty) {
          setState(() => _error = '请填写网页 URL');
          return;
        }
        final u = primary.toLowerCase();
        if (!u.startsWith('http://') && !u.startsWith('https://')) {
          setState(() => _error = 'URL 需以 http:// 或 https:// 开头');
          return;
        }
        if (old != null) {
          await widget.userCardStore.updateWeb(
            oldUrl: old.data as String,
            url: primary,
            tags: tags,
          );
        } else {
          await widget.userCardStore.addWeb(url: primary, tags: tags);
        }
        break;
      case 2:
        if (primary.isEmpty) {
          setState(() => _error = '请填写命令内容');
          return;
        }
        if (old != null) {
          await widget.userCardStore.updateCommand(
            oldCommand: old.data as String,
            command: primary,
            tags: tags,
          );
        } else {
          await widget.userCardStore.addCommand(command: primary, tags: tags);
        }
        break;
      case 3:
        if (primary.isEmpty) {
          setState(() => _error = '请填写笔记内容');
          return;
        }
        if (old != null) {
          await widget.userCardStore.updateNote(
            oldContent: old.data as String,
            content: primary,
            tags: tags,
          );
        } else {
          await widget.userCardStore.addNote(content: primary, tags: tags);
        }
        break;
      default:
        return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final primaryLabel = switch (widget.cardIndex) {
      0 => '可执行文件路径',
      1 => '网页 URL',
      2 => '命令内容',
      3 => '笔记内容',
      _ => '',
    };
    final primaryHint = switch (widget.cardIndex) {
      0 => r'例如 C:\Program Files\App\app.exe',
      1 => 'https://',
      2 => '将交由 cmd /c 执行',
      3 => '支持多行',
      _ => '',
    };
    final primaryLines = widget.cardIndex == 2 || widget.cardIndex == 3 ? 5 : 1;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_isEditing ? '编辑' : '新建'} · ${widget.cardTitle}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(primaryLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (widget.cardIndex == 0)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _primaryController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: primaryHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _pickExe,
                  icon: const Icon(Icons.folder_open),
                  tooltip: '浏览文件',
                ),
              ],
            )
          else
            TextField(
              controller: _primaryController,
              maxLines: primaryLines,
              decoration: InputDecoration(
                hintText: primaryHint,
                border: const OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 20),
          const Text('Tags', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _tagsController,
            decoration: const InputDecoration(
              hintText: '多个标签可用逗号或空格分隔',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await _save();
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
