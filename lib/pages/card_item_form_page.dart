import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
  bool _saving = false;
  String? _error;

  TextEditingController? _accountName;
  TextEditingController? _accountUserName;
  TextEditingController? _accountPassword;
  TextEditingController? _tokenAccountName;
  TextEditingController? _tokenValue;
  TextEditingController? _noteTitle;
  TextEditingController? _noteContent;
  String _noteKind = NoteKind.note;
  String? _editingNoteId;

  bool get _isEditing => widget.editingItem != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editingItem;
    if (widget.cardIndex == 3) {
      _accountName = TextEditingController();
      _accountUserName = TextEditingController();
      _accountPassword = TextEditingController();
      _tokenAccountName = TextEditingController();
      _tokenValue = TextEditingController();
      _noteTitle = TextEditingController();
      _noteContent = TextEditingController();
      if (e != null) {
        try {
          final raw = e.data;
          final Map<String, dynamic> m = raw is String
              ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
              : Map<String, dynamic>.from(raw as Map);
          _editingNoteId = m['id']?.toString();
          _noteKind = m['kind']?.toString() ?? NoteKind.note;
          switch (_noteKind) {
            case NoteKind.account:
              _accountName!.text = m['accountName']?.toString() ?? '';
              _accountUserName!.text = m['userName']?.toString() ?? '';
              _accountPassword!.text = m['password']?.toString() ?? '';
              break;
            case NoteKind.token:
              _tokenAccountName!.text = m['accountName']?.toString() ?? '';
              _tokenValue!.text = m['tokenValue']?.toString() ?? '';
              break;
            default:
              _noteTitle!.text = m['title']?.toString() ?? '';
              _noteContent!.text = m['noteContent']?.toString() ?? '';
          }
        } catch (_) {
          _noteContent!.text = e.data?.toString() ?? '';
          _noteKind = NoteKind.note;
        }
      }
    } else if (e != null) {
      _primaryController.text = (e.data as String?) ?? '';
    }
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _primaryController.dispose();
    _accountName?.dispose();
    _accountUserName?.dispose();
    _accountPassword?.dispose();
    _tokenAccountName?.dispose();
    _tokenValue?.dispose();
    _noteTitle?.dispose();
    _noteContent?.dispose();
    super.dispose();
  }

  bool _onHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!mounted) return false;
    Navigator.of(context).pop(false);
    return true;
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

  static const _httpUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  void _configureHttpClient(HttpClient client) {
    client.userAgent = _httpUserAgent;
  }

  Uri _faviconIcoUri(Uri pageUri) {
    return Uri(
      scheme: pageUri.scheme.isEmpty ? 'https' : pageUri.scheme,
      host: pageUri.host,
      port: pageUri.hasPort ? pageUri.port : null,
      path: '/favicon.ico',
    );
  }

  /// 简单排除误把 HTML 当图标的情况。
  bool _looksLikeImageBytes(Uint8List bytes) {
    if (bytes.length < 24) return bytes.isNotEmpty;
    final head = String.fromCharCodes(bytes.sublist(0, math.min(64, bytes.length))).toLowerCase();
    if (head.contains('<!doctype') ||
        head.contains('<html') ||
        head.trimLeft().startsWith('<?xml')) {
      return false;
    }
    // ICO / PNG / GIF / JPEG / WEBP 魔数
    if (bytes.length >= 4 &&
        bytes[0] == 0x00 &&
        bytes[1] == 0x00 &&
        bytes[2] == 0x01 &&
        bytes[3] == 0x00) {
      return true;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return true;
    }
    if (bytes.length >= 3 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return true;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return true;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return true; // RIFF / WEBP
    }
    return true;
  }

  Future<Uint8List?> _readResponseBytes(HttpClientResponse response) async {
    if (response.statusCode != 200) return null;
    final bytes = await response.fold<Uint8List>(
      Uint8List(0),
      (prev, chunk) => Uint8List.fromList([...prev, ...chunk]),
    );
    if (bytes.isEmpty) return null;
    if (!_looksLikeImageBytes(bytes)) return null;
    return bytes;
  }

  Future<Uint8List?> _getBytesFromUrl(HttpClient client, Uri uri) async {
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      return _readResponseBytes(response);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _fetchFaviconFallbacks(HttpClient client, Uri pageUri) async {
    final host = pageUri.host;
    if (host.isEmpty) return null;
    Uint8List? b = await _getBytesFromUrl(
      client,
      Uri.parse('https://icons.duckduckgo.com/ip3/$host.ico'),
    );
    if (b != null) return b;
    b = await _getBytesFromUrl(
      client,
      Uri.parse('https://www.google.com/s2/favicons?domain=$host&sz=64'),
    );
    return b;
  }

  /// 一次拉取页面：解析 title，并尽量解析 link/icon 或尝试 /favicon.ico，再回退第三方图标服务。
  Future<({String? title, Uint8List? favicon})> _fetchWebPageMetadata(String url) async {
    final uri = Uri.parse(url);
    if (uri.host.isEmpty) {
      return (title: null, favicon: null);
    }

    final client = HttpClient();
    _configureHttpClient(client);
    try {
      String? title;
      HttpClientResponse? pageResponse;
      try {
        final request = await client.getUrl(uri);
        pageResponse = await request.close();
      } catch (_) {
        return (title: null, favicon: await _fetchFaviconFallbacks(client, uri));
      }

      if (pageResponse.statusCode != 200) {
        await pageResponse.drain<void>();
        return (title: null, favicon: await _fetchFaviconFallbacks(client, uri));
      }

      final body = await pageResponse.transform(utf8.decoder).join();
      final m = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false)
          .firstMatch(body);
      final rawTitle = m?.group(1)?.trim();
      title = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : null;

      Uint8List? favicon;

      final dataUri = RegExp(
        r'''^\s*data:image/[^;]+;base64,([a-zA-Z0-9+/=\s]+)''',
        caseSensitive: false,
      );
      for (final link in RegExp(r'<link\s([^>]+)>', caseSensitive: false).allMatches(body)) {
        final attrs = link.group(1)!;
        final relLower = attrs.toLowerCase();
        if (!relLower.contains('icon')) continue;
        if (relLower.contains('mask-icon') && !relLower.contains('apple-touch')) {
          continue;
        }
        final hrefM =
            RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false).firstMatch(attrs);
        final href = hrefM?.group(1)?.trim();
        if (href == null || href.isEmpty) continue;

        final hrefDecoded = href.replaceAll('&amp;', '&');

        if (hrefDecoded.toLowerCase().startsWith('data:')) {
          final dm = dataUri.firstMatch(hrefDecoded);
          if (dm != null) {
            try {
              final raw = dm.group(1)!.replaceAll(RegExp(r'\s'), '');
              final decoded = base64Decode(raw);
              if (decoded.isNotEmpty && _looksLikeImageBytes(decoded)) {
                favicon = decoded;
                break;
              }
            } catch (_) {}
          }
          continue;
        }

        final iconUri = uri.resolve(hrefDecoded);
        favicon = await _getBytesFromUrl(client, iconUri);
        if (favicon != null) break;
      }

      favicon ??= await _getBytesFromUrl(client, _faviconIcoUri(uri));
      favicon ??= await _fetchFaviconFallbacks(client, uri);

      return (title: title, favicon: favicon);
    } finally {
      client.close();
    }
  }

  Widget _buildNoteTypeForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('类型', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: NoteKind.account, label: Text('账户')),
            ButtonSegment(value: NoteKind.token, label: Text('Token')),
            ButtonSegment(value: NoteKind.note, label: Text('笔记')),
          ],
          selected: {_noteKind},
          onSelectionChanged: (s) => setState(() => _noteKind = s.first),
        ),
        const SizedBox(height: 16),
        ...switch (_noteKind) {
          NoteKind.account => [
              TextField(
                controller: _accountName!,
                decoration: const InputDecoration(
                  labelText: '账户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _accountUserName!,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _accountPassword!,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          NoteKind.token => [
              TextField(
                controller: _tokenAccountName!,
                decoration: const InputDecoration(
                  labelText: '账户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tokenValue!,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Token 值',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          _ => [
              TextField(
                controller: _noteTitle!,
                decoration: const InputDecoration(
                  labelText: '标题',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteContent!,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '内容',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
        },
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
    });
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
          );
        } else {
          await widget.userCardStore.addApp(path: primary);
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
        String? fetchedTitle;
        Uint8List? faviconBytes;
        try {
          final meta = await _fetchWebPageMetadata(primary);
          fetchedTitle = meta.title;
          faviconBytes = meta.favicon;
        } catch (_) {}
        if (old != null) {
          await widget.userCardStore.updateWeb(
            oldUrl: old.data as String,
            url: primary,
            fetchedTitle: fetchedTitle,
            faviconBytes: faviconBytes,
          );
        } else {
          await widget.userCardStore.addWeb(
            url: primary,
            fetchedTitle: fetchedTitle,
            faviconBytes: faviconBytes,
          );
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
          );
        } else {
          await widget.userCardStore.addCommand(command: primary);
        }
        break;
      case 3:
        final tags = old?.tags ?? const <String>[];
        final map = <String, dynamic>{'kind': _noteKind, 'tags': tags};
        switch (_noteKind) {
          case NoteKind.account:
            final an = _accountName!.text.trim();
            final un = _accountUserName!.text.trim();
            final pw = _accountPassword!.text;
            if (an.isEmpty || un.isEmpty || pw.isEmpty) {
              setState(() => _error = '请填写账户名、用户名和密码');
              return;
            }
            map['accountName'] = an;
            map['userName'] = un;
            map['password'] = pw;
            break;
          case NoteKind.token:
            final ta = _tokenAccountName!.text.trim();
            final tv = _tokenValue!.text.trim();
            if (ta.isEmpty || tv.isEmpty) {
              setState(() => _error = '请填写账户名和 Token');
              return;
            }
            map['accountName'] = ta;
            map['tokenValue'] = tv;
            break;
          default:
            final nt = _noteTitle!.text.trim();
            final nc = _noteContent!.text;
            if (nc.trim().isEmpty) {
              setState(() => _error = '请填写笔记内容');
              return;
            }
            map['title'] = nt;
            map['noteContent'] = nc;
        }
        if (old != null) {
          final id = _editingNoteId;
          if (id == null || id.isEmpty) {
            setState(() => _error = '无法保存：缺少笔记标识');
            return;
          }
          await widget.userCardStore.updateNote(id: id, fields: map);
        } else {
          await widget.userCardStore.addNoteEntry(map);
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
      _ => '',
    };
    final primaryHint = switch (widget.cardIndex) {
      0 => r'例如 C:\Program Files\App\app.exe',
      1 => 'https://',
      2 => '将交由 cmd /c 执行',
      _ => '',
    };
    final primaryLines = widget.cardIndex == 2 ? 5 : 1;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('${_isEditing ? '编辑' : '新建'} · ${widget.cardTitle}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColorsWithAlpha(widget.gradient),
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(color: Colors.transparent.withAlpha(200)),
              ),
            ),
            ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (primaryLabel.isNotEmpty) ...[
                  Text(primaryLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                ],
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
                else if (widget.cardIndex == 3)
                  _buildNoteTypeForm()
                else
                  TextField(
                    controller: _primaryController,
                    maxLines: primaryLines,
                    decoration: InputDecoration(
                      hintText: primaryHint,
                      border: const OutlineInputBorder(),
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
          ],
        ),
      ),
    );
  }
}
