import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
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
  TextEditingController? _webCustomTitleController;
  bool _useCustomWebTitle = false;
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

  /// 快捷指令：是否在终端中保留窗口（执行后等待）；新建默认开启。
  bool _commandWaitAfterRun = true;

  TextEditingController? _commandTitleController;

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
    } else if (widget.cardIndex == 1) {
      _webCustomTitleController = TextEditingController();
      if (e != null) {
        _primaryController.text = (e.data as String?) ?? '';
        final url = _primaryController.text;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final ct = await widget.userCardStore.getWebCustomTitle(url);
          if (!mounted) return;
          setState(() {
            _useCustomWebTitle = ct != null && ct.isNotEmpty;
            _webCustomTitleController!.text = ct ?? '';
          });
        });
      }
    } else if (widget.cardIndex == 2) {
      _commandTitleController = TextEditingController();
      if (e != null) {
        final d = e.data;
        if (d is Map) {
          _primaryController.text = d['command']?.toString() ?? '';
          _commandWaitAfterRun = d['waitAfterRun'] != false;
          final tit = d['title']?.toString().trim();
          if (tit != null && tit.isNotEmpty) {
            _commandTitleController!.text = tit;
          }
        } else {
          _primaryController.text = (d as String?) ?? '';
          _commandWaitAfterRun = true;
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
    _webCustomTitleController?.dispose();
    _commandTitleController?.dispose();
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

  void _applyHtmlFetchHeaders(HttpClientRequest request) {
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    );
    request.headers.set(
      HttpHeaders.acceptLanguageHeader,
      'zh-CN,zh;q=0.9,en-US,en;q=0.8',
    );
  }

  /// 去掉 UTF-8 BOM，并按 Content-Type / 常见别名解码 HTML。
  String _decodeHtmlBodyBytes(Uint8List raw, String? contentTypeHeader) {
    var bytes = raw;
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      bytes = bytes.sublist(3);
    }

    String? charset;
    if (contentTypeHeader != null && contentTypeHeader.isNotEmpty) {
      final m = RegExp(
        r'charset\s*=\s*([^\s;]+)',
        caseSensitive: false,
      ).firstMatch(contentTypeHeader);
      if (m != null) {
        charset =
            m.group(1)!.replaceAll('"', '').replaceAll("'", '').toLowerCase();
      }
    }

    String tryCharset(String? cs) {
      if (cs == null || cs.isEmpty || cs == 'utf-8' || cs == 'utf8') {
        return utf8.decode(bytes, allowMalformed: true);
      }
      final enc = Encoding.getByName(cs);
      if (enc != null) {
        try {
          return enc.decode(bytes);
        } catch (_) {}
      }
      return utf8.decode(bytes, allowMalformed: true);
    }

    var html = tryCharset(charset);
    if (charset == null || charset.isEmpty) {
      final meta = RegExp(
        r'''<meta\s+charset\s*=\s*['"]?([^'">\s]+)''',
        caseSensitive: false,
      ).firstMatch(html.substring(0, math.min(html.length, 4096)));
      final mc = meta?.group(1)?.toLowerCase();
      if (mc != null && mc.isNotEmpty && mc != 'utf-8' && mc != 'utf8') {
        html = tryCharset(mc);
      }
    }
    return html;
  }

  String _decodeHtmlEntities(String input) {
    var s = input.replaceAll('&nbsp;', ' ');
    s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final hex = m.group(1)!;
      final cp = int.tryParse(hex, radix: 16);
      if (cp == null) return m.group(0)!;
      return String.fromCharCode(cp);
    });
    s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final cp = int.tryParse(m.group(1)!);
      if (cp == null) return m.group(0)!;
      return String.fromCharCode(cp);
    });
    return s
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  /// 从 HTML 中取标题：<title> → og:title → twitter:title。
  String? _extractPageTitle(String html) {
    final patterns = <RegExp>[
      RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true, caseSensitive: false),
      RegExp(
        r'''property\s*=\s*["']og:title["']\s+content\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''content\s*=\s*["']([^"']+)["']\s+property\s*=\s*["']og:title["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''name\s*=\s*["']twitter:title["']\s+content\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      ),
      RegExp(
        r'''content\s*=\s*["']([^"']+)["']\s+name\s*=\s*["']twitter:title["']''',
        caseSensitive: false,
      ),
    ];

    String? raw;
    for (final re in patterns) {
      final m = re.firstMatch(html);
      final s = m?.group(1)?.trim();
      if (s != null && s.isNotEmpty) {
        raw = s;
        break;
      }
    }

    if (raw == null || raw.isEmpty) return null;
    var cleaned =
        raw.replaceAll(RegExp(r'<[^>]+>'), '');
    cleaned =
        _decodeHtmlEntities(cleaned).trim().replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.isEmpty ? null : cleaned;
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
        _applyHtmlFetchHeaders(request);
        pageResponse = await request.close();
      } catch (_) {
        return (title: null, favicon: await _fetchFaviconFallbacks(client, uri));
      }

      final code = pageResponse.statusCode;
      if (code >= 500 || code == 204 || code == 205) {
        await pageResponse.drain<void>();
        return (title: null, favicon: await _fetchFaviconFallbacks(client, uri));
      }

      final ct = pageResponse.headers.value(HttpHeaders.contentTypeHeader);
      final bodyBytesBuilder = BytesBuilder(copy: false);
      await for (final chunk in pageResponse) {
        bodyBytesBuilder.add(chunk);
      }
      final rawBytes = bodyBytesBuilder.takeBytes();
      final bodyStr = _decodeHtmlBodyBytes(rawBytes, ct);
      title = _extractPageTitle(bodyStr);

      Uint8List? favicon;

      final dataUri = RegExp(
        r'''^\s*data:image/[^;]+;base64,([a-zA-Z0-9+/=\s]+)''',
        caseSensitive: false,
      );
      for (final link in RegExp(r'<link\s([^>]+)>', caseSensitive: false).allMatches(bodyStr)) {
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
      client.close(force: true);
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
        final customTrim = _webCustomTitleController?.text.trim() ?? '';
        if (_useCustomWebTitle && customTrim.isEmpty) {
          setState(() => _error = '请填写自定义标题');
          return;
        }
        String? fetchedTitle;
        Uint8List? faviconBytes;
        try {
          final meta = await _fetchWebPageMetadata(primary);
          faviconBytes = meta.favicon;
          if (!_useCustomWebTitle) {
            fetchedTitle = meta.title;
          }
        } catch (_) {}
        if (old != null) {
          await widget.userCardStore.updateWeb(
            oldUrl: old.data as String,
            url: primary,
            fetchedTitle: fetchedTitle,
            faviconBytes: faviconBytes,
            customTitle: _useCustomWebTitle ? customTrim : null,
            removeCustomTitle: !_useCustomWebTitle,
          );
        } else {
          await widget.userCardStore.addWeb(
            url: primary,
            fetchedTitle: fetchedTitle,
            faviconBytes: faviconBytes,
            customTitle: _useCustomWebTitle ? customTrim : null,
          );
        }
        break;
      case 2:
        if (primary.isEmpty) {
          setState(() => _error = '请填写命令内容');
          return;
        }
        final titleOpt = _commandTitleController?.text.trim();
        if (old != null) {
          final od = old.data;
          final oldCmd = od is Map
              ? (od['command'] as String?) ?? ''
              : od as String? ?? '';
          await widget.userCardStore.updateCommand(
            oldCommand: oldCmd,
            command: primary,
            tags: old.tags,
            waitAfterRun: _commandWaitAfterRun,
            title: titleOpt,
          );
        } else {
          await widget.userCardStore.addCommand(
            command: primary,
            waitAfterRun: _commandWaitAfterRun,
            title: titleOpt,
          );
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

  Future<void> _submitSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _save();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
      2 => '输入要在终端中执行的命令',
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
        actions: [
          IconButton(
            tooltip: '保存',
            onPressed: _saving ? null : _submitSave,
            icon: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
          ),
        ],
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
                if (primaryLabel.isNotEmpty && widget.cardIndex != 2) ...[
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
                else if (widget.cardIndex == 1)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _primaryController,
                        maxLines: 1,
                        decoration: InputDecoration(
                          hintText: primaryHint,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('自定义标题'),
                        value: _useCustomWebTitle,
                        onChanged: (v) =>
                            setState(() => _useCustomWebTitle = v),
                      ),
                      if (_useCustomWebTitle && _webCustomTitleController != null)
                        TextField(
                          controller: _webCustomTitleController,
                          decoration: const InputDecoration(
                            labelText: '标题',
                            border: OutlineInputBorder(),
                          ),
                        ),
                    ],
                  )
                else if (widget.cardIndex == 2)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _commandTitleController,
                        decoration: const InputDecoration(
                          labelText: '标题',
                          hintText: '留空则与下方命令正文一致',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        primaryLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _primaryController,
                        maxLines: primaryLines,
                        decoration: InputDecoration(
                          hintText: primaryHint,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '运行方式',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment<bool>(
                                  value: false,
                                  label: Text('执行后关闭'),
                                ),
                                ButtonSegment<bool>(
                                  value: true,
                                  label: Text('执行后等待'),
                                ),
                              ],
                              emptySelectionAllowed: false,
                              showSelectedIcon: false,
                              selected: <bool>{_commandWaitAfterRun},
                              onSelectionChanged: (Set<bool> next) {
                                setState(() => _commandWaitAfterRun = next.first);
                              },
                            ),
                          ),
                        ],
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
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
