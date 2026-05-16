import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../cards/base_card.dart';
import 'app_settings.dart';
import 'hybrid_search/hybrid_search_engine.dart';

/// 笔记条目类型（与 JSON 中 kind 字段一致）
abstract final class NoteKind {
  static const account = 'account';
  static const token = 'token';
  static const note = 'note';
}

/// 持久化各卡片中用户通过「新建」添加的条目
class UserCardStore {
  UserCardStore({required this.appSettings, this.onAfterPersist});

  final AppSettings appSettings;

  /// 在 [_saveRoot] 写入成功后调用（如云同步防抖上传）；云合并导入时会暂时抑制。
  void Function()? onAfterPersist;

  bool _suppressAfterPersist = false;

  /// 云同步涉及的 `user_entries.json` 顶层键（不含快捷应用 `apps`）。
  static const List<String> cloudSyncSectionKeys = [
    'web',
    'commands',
    'notes',
  ];

  File get _file => File(appSettings.userEntriesPath);

  Future<Map<String, dynamic>> _loadRoot() async {
    if (!await _file.exists()) {
      return _emptyRoot();
    }
    try {
      final raw = await _file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _normalizeRoot(decoded);
      }
    } catch (_) {}
    return _emptyRoot();
  }

  Map<String, dynamic> _emptyRoot() => {
        'apps': <dynamic>[],
        'web': <dynamic>[],
        'commands': <dynamic>[],
        'notes': <dynamic>[],
      };

  Map<String, dynamic> _normalizeRoot(Map<String, dynamic> m) {
    for (final k in ['apps', 'web', 'commands', 'notes']) {
      if (m[k] is! List) m[k] = [];
    }
    return m;
  }

  Future<void> _saveRoot(Map<String, dynamic> root) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(const JsonEncoder.withIndent('  ').convert(root));
    if (!_suppressAfterPersist) {
      onAfterPersist?.call();
    }
  }

  static List<String> _tagsFromJson(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  static String _basename(String path) {
    final i = path.replaceAll('/', r'\').lastIndexOf(r'\');
    return i < 0 ? path : path.substring(i + 1);
  }

  Future<List<CardItem>> loadAppCardItems() async {
    final root = await _loadRoot();
    final list = root['apps'] as List<dynamic>;
    final out = <CardItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final path = e['path'] as String? ?? '';
      if (path.isEmpty) continue;
      final tags = _tagsFromJson(e['tags']);
      final title = _basename(path);
      out.add(CardItem(
        title: title,
        subtitle: tags.isEmpty ? null : tags.join(', '),
        icon: Icons.launch,
        data: path,
        iconPath: path,
        isUserEntry: true,
        tags: tags,
      ));
    }
    return out;
  }

  Future<List<CardItem>> searchAppsMatching(String query) async {
    final items = await loadAppCardItems();
    return HybridSearch.sortCardItems(query, items);
  }

  Future<void> addApp({required String path, List<String> tags = const []}) async {
    final root = await _loadRoot();
    (root['apps'] as List<dynamic>).add({
      'path': path,
      'tags': tags,
    });
    await _saveRoot(root);
  }

  Future<List<CardItem>> loadWebCardItems() async {
    final root = await _loadRoot();
    final list = root['web'] as List<dynamic>;
    final out = <CardItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final url = e['url'] as String? ?? '';
      if (url.isEmpty) continue;
      final tags = _tagsFromJson(e['tags']);
      Uri? uri;
      try {
        uri = Uri.parse(url);
      } catch (_) {}
      final host = uri?.host.isNotEmpty == true ? uri!.host : url;
      final custom = (e['customTitle'] as String?)?.trim();
      final fetched = (e['fetchedTitle'] as String?)?.trim();
      final title = (custom != null && custom.isNotEmpty)
          ? custom
          : (fetched != null && fetched.isNotEmpty)
              ? fetched
              : host;
      final faviconBase64 = e['faviconBase64'] as String?;
      final iconBytes = (faviconBase64 != null && faviconBase64.isNotEmpty)
          ? base64Decode(faviconBase64)
          : null;
      out.add(CardItem(
        title: title,
        subtitle: tags.isEmpty ? url : '${tags.join(', ')}\n$url',
        icon: Icons.public,
        data: url,
        iconBytes: iconBytes,
        isUserEntry: true,
        tags: tags,
      ));
    }
    return out;
  }

  Future<void> addWeb({
    required String url,
    List<String> tags = const [],
    String? fetchedTitle,
    Uint8List? faviconBytes,
    String? customTitle,
  }) async {
    final root = await _loadRoot();
    final entry = <String, dynamic>{
      'url': url,
      'tags': tags,
    };
    if (fetchedTitle != null && fetchedTitle.isNotEmpty) {
      entry['fetchedTitle'] = fetchedTitle;
    }
    if (faviconBytes != null && faviconBytes.isNotEmpty) {
      entry['faviconBase64'] = base64Encode(faviconBytes);
    }
    if (customTitle != null && customTitle.isNotEmpty) {
      entry['customTitle'] = customTitle.trim();
    }
    (root['web'] as List<dynamic>).add(entry);
    await _saveRoot(root);
  }

  /// 读取网页条目中用户自定义标题（若无则 null）。
  Future<String?> getWebCustomTitle(String url) async {
    final root = await _loadRoot();
    for (final raw in root['web'] as List<dynamic>) {
      if (raw is Map && (raw['url'] as String?) == url) {
        final c = raw['customTitle']?.toString().trim();
        if (c != null && c.isNotEmpty) return c;
        return null;
      }
    }
    return null;
  }

  Future<List<CardItem>> loadCommandCardItems() async {
    final root = await _loadRoot();
    final list = root['commands'] as List<dynamic>;
    final out = <CardItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final cmd = e['command'] as String? ?? '';
      if (cmd.isEmpty) continue;
      final tags = _tagsFromJson(e['tags']);
      final waitAfterRun = e['waitAfterRun'] != false;
      final customTitle = (e['title'] as String?)?.trim();
      String title;
      if (customTitle != null && customTitle.isNotEmpty) {
        title = customTitle;
      } else {
        title = cmd.split(RegExp(r'[\r\n]')).first.trim();
      }
      if (title.length > 48) title = '${title.substring(0, 45)}…';
      out.add(CardItem(
        title: title,
        subtitle: tags.isEmpty ? null : tags.join(', '),
        icon: Icons.terminal,
        data: <String, dynamic>{
          'command': cmd,
          'waitAfterRun': waitAfterRun,
          if (customTitle != null && customTitle.isNotEmpty) 'title': customTitle,
        },
        isUserEntry: true,
        tags: tags,
      ));
    }
    return out;
  }

  Future<void> addCommand({
    required String command,
    List<String> tags = const [],
    bool waitAfterRun = true,
    String? title,
  }) async {
    final root = await _loadRoot();
    final entry = <String, dynamic>{
      'command': command,
      'tags': tags,
      'waitAfterRun': waitAfterRun,
    };
    final t = title?.trim();
    if (t != null && t.isNotEmpty) {
      entry['title'] = t;
    }
    (root['commands'] as List<dynamic>).add(entry);
    await _saveRoot(root);
  }

  static final _noteRandom = Random();

  String _allocateNoteId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${_noteRandom.nextInt(1 << 30)}';

  /// 将旧版仅含 content 的笔记迁为带 id、kind 的结构。
  Future<void> _migrateNotesIfNeeded(Map<String, dynamic> root) async {
    final list = root['notes'] as List<dynamic>;
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      final raw = list[i];
      if (raw is! Map) continue;
      final e = Map<String, dynamic>.from(raw);
      final id = e['id']?.toString();
      if (id == null || id.isEmpty) {
        e['id'] = _allocateNoteId();
        changed = true;
      }
      final kind = e['kind']?.toString();
      if (kind == null || kind.isEmpty) {
        final content = e['content']?.toString() ?? '';
        e['kind'] = NoteKind.note;
        e['noteContent'] = content;
        var t = content.split(RegExp(r'[\r\n]')).first.trim();
        if (t.length > 40) t = '${t.substring(0, 37)}…';
        e['title'] = t;
        e.remove('content');
        changed = true;
      }
      list[i] = e;
    }
    if (changed) {
      await _saveRoot(root);
    }
  }

  Future<List<CardItem>> loadNoteCardItems() async {
    final root = await _loadRoot();
    await _migrateNotesIfNeeded(root);
    final list = root['notes'] as List<dynamic>;
    final out = <CardItem>[];
    for (final raw in list) {
      if (raw is! Map) continue;
      final e = Map<String, dynamic>.from(raw);
      final id = e['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final kind = e['kind']?.toString() ?? NoteKind.note;
      final tags = _tagsFromJson(e['tags']);

      late final String title;
      late final String? subtitle;
      late final IconData iconData;

      switch (kind) {
        case NoteKind.account:
          final an = e['accountName']?.toString().trim() ?? '';
          final un = e['userName']?.toString().trim() ?? '';
          title = an.isEmpty ? '（无账户名）' : an;
          subtitle = un.isEmpty ? null : '用户：$un';
          iconData = Icons.person_outline;
          break;
        case NoteKind.token:
          final an = e['accountName']?.toString().trim() ?? '';
          title = an.isEmpty ? '（无账户名）' : an;
          subtitle = 'Token';
          iconData = Icons.key_outlined;
          break;
        default:
          final body = e['noteContent']?.toString() ?? '';
          if (body.trim().isEmpty) continue;
          var nt = e['title']?.toString().trim() ?? '';
          if (nt.isEmpty) {
            nt = '（无标题）';
          }
          title = nt;
          subtitle = tags.isEmpty ? null : tags.join(', ');
          iconData = Icons.note_outlined;
          break;
      }

      out.add(CardItem(
        title: title,
        subtitle: subtitle,
        icon: iconData,
        data: jsonEncode(e),
        isUserEntry: true,
        tags: tags,
      ));
    }
    return out;
  }

  Future<void> addNoteEntry(Map<String, dynamic> fields) async {
    final root = await _loadRoot();
    final e = Map<String, dynamic>.from(fields);
    e['id'] = _allocateNoteId();
    e['tags'] = _tagsFromJson(e['tags']);
    e['kind'] = e['kind']?.toString() ?? NoteKind.note;
    (root['notes'] as List<dynamic>).add(e);
    await _saveRoot(root);
  }

  Future<void> removeApp(String path) async {
    final root = await _loadRoot();
    (root['apps'] as List<dynamic>)
        .removeWhere((e) => e is Map && (e['path'] as String?) == path);
    await _saveRoot(root);
  }

  Future<void> updateApp({
    required String oldPath,
    required String path,
    List<String> tags = const [],
  }) async {
    final root = await _loadRoot();
    final list = root['apps'] as List<dynamic>;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e is Map && (e['path'] as String?) == oldPath) {
        list[i] = {'path': path, 'tags': tags};
        break;
      }
    }
    await _saveRoot(root);
  }

  Future<void> removeWeb(String url) async {
    final root = await _loadRoot();
    (root['web'] as List<dynamic>)
        .removeWhere((e) => e is Map && (e['url'] as String?) == url);
    await _saveRoot(root);
  }

  Future<void> updateWeb({
    required String oldUrl,
    required String url,
    List<String> tags = const [],
    String? fetchedTitle,
    Uint8List? faviconBytes,
    String? customTitle,
    bool removeCustomTitle = false,
  }) async {
    final root = await _loadRoot();
    final list = root['web'] as List<dynamic>;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e is Map && (e['url'] as String?) == oldUrl) {
        final prev = Map<String, dynamic>.from(e);
        final next = <String, dynamic>{
          'url': url,
          'tags': tags,
        };
        if (fetchedTitle != null && fetchedTitle.isNotEmpty) {
          next['fetchedTitle'] = fetchedTitle;
        } else {
          final pt = prev['fetchedTitle']?.toString();
          if (pt != null && pt.isNotEmpty) {
            next['fetchedTitle'] = pt;
          }
        }
        if (faviconBytes != null && faviconBytes.isNotEmpty) {
          next['faviconBase64'] = base64Encode(faviconBytes);
        } else {
          final pb = prev['faviconBase64']?.toString();
          if (pb != null && pb.isNotEmpty) {
            next['faviconBase64'] = pb;
          }
        }
        if (removeCustomTitle) {
          // 不写 customTitle
        } else if (customTitle != null && customTitle.trim().isNotEmpty) {
          next['customTitle'] = customTitle.trim();
        } else {
          final pc = prev['customTitle']?.toString();
          if (pc != null && pc.isNotEmpty) {
            next['customTitle'] = pc;
          }
        }
        list[i] = next;
        break;
      }
    }
    await _saveRoot(root);
  }

  Future<void> removeCommand(String command) async {
    final root = await _loadRoot();
    (root['commands'] as List<dynamic>).removeWhere(
        (e) => e is Map && (e['command'] as String?) == command);
    await _saveRoot(root);
  }

  Future<void> updateCommand({
    required String oldCommand,
    required String command,
    List<String> tags = const [],
    bool waitAfterRun = true,
    String? title,
  }) async {
    final root = await _loadRoot();
    final list = root['commands'] as List<dynamic>;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e is Map && (e['command'] as String?) == oldCommand) {
        final next = <String, dynamic>{
          'command': command,
          'tags': tags,
          'waitAfterRun': waitAfterRun,
        };
        final t = title?.trim();
        if (t != null && t.isNotEmpty) {
          next['title'] = t;
        }
        list[i] = next;
        break;
      }
    }
    await _saveRoot(root);
  }

  Future<void> removeNoteById(String id) async {
    final root = await _loadRoot();
    (root['notes'] as List<dynamic>)
        .removeWhere((e) => e is Map && e['id']?.toString() == id);
    await _saveRoot(root);
  }

  Future<void> updateNote({
    required String id,
    required Map<String, dynamic> fields,
  }) async {
    final root = await _loadRoot();
    final list = root['notes'] as List<dynamic>;
    for (var i = 0; i < list.length; i++) {
      final raw = list[i];
      if (raw is! Map) continue;
      final existing = Map<String, dynamic>.from(raw);
      if (existing['id']?.toString() != id) continue;
      final next = Map<String, dynamic>.from(fields);
      next['id'] = id;
      next['kind'] = fields['kind']?.toString() ?? existing['kind'] ?? NoteKind.note;
      if (fields.containsKey('tags')) {
        next['tags'] = _tagsFromJson(fields['tags']);
      } else {
        next['tags'] = _tagsFromJson(existing['tags']);
      }
      list[i] = next;
      await _saveRoot(root);
      return;
    }
  }

  /// 导出供云同步上传的数据（仅网页快开、快捷指令、快速笔记；不含快捷应用 `apps`）。
  Future<Map<String, dynamic>> exportCloudSyncPayload() async {
    final root = await _loadRoot();
    final out = <String, dynamic>{};
    for (final key in cloudSyncSectionKeys) {
      final raw = root[key];
      if (raw is List) {
        out[key] = jsonDecode(jsonEncode(raw)) as List<dynamic>;
      } else {
        out[key] = <dynamic>[];
      }
    }
    return out;
  }

  /// 将云同步下载结果合并写回本地；仅更新 [cloudSyncSectionKeys]，`apps` 保持不变。
  Future<void> importCloudSyncPayload(Map<String, dynamic> payload) async {
    _suppressAfterPersist = true;
    try {
      final root = await _loadRoot();
      for (final key in cloudSyncSectionKeys) {
        final v = payload[key];
        if (v is List) {
          root[key] = jsonDecode(jsonEncode(v)) as List<dynamic>;
        }
      }
      await _migrateNotesIfNeeded(root);
      await _saveRoot(root);
    } finally {
      _suppressAfterPersist = false;
    }
  }
}

/// 从快捷指令条目的 [CardItem.data] 读取命令正文（兼容旧版存为字符串）。
String? parseQuickCommandText(dynamic data) {
  if (data == null) return null;
  if (data is String) return data;
  if (data is Map) return data['command']?.toString();
  return null;
}

/// 是否需在终端中执行并保留窗口；缺省为 true（新开/保留终端）。
bool parseQuickCommandWaitAfterRun(dynamic data) {
  if (data is Map) return data['waitAfterRun'] != false;
  return true;
}
