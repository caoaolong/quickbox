import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../cards/base_card.dart';
import 'app_settings.dart';

/// 持久化各卡片中用户通过「新建」添加的条目
class UserCardStore {
  UserCardStore({required this.appSettings});

  final AppSettings appSettings;

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
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final items = await loadAppCardItems();
    return items.where((it) {
      if (it.title.toLowerCase().contains(q)) return true;
      if ((it.subtitle ?? '').toLowerCase().contains(q)) return true;
      for (final t in it.tags) {
        if (t.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  Future<void> addApp({required String path, required List<String> tags}) async {
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
      final title = uri?.host.isNotEmpty == true ? uri!.host : url;
      out.add(CardItem(
        title: title,
        subtitle: tags.isEmpty ? url : '${tags.join(', ')}\n$url',
        icon: Icons.public,
        data: url,
        isUserEntry: true,
        tags: tags,
      ));
    }
    return out;
  }

  Future<void> addWeb({required String url, required List<String> tags}) async {
    final root = await _loadRoot();
    (root['web'] as List<dynamic>).add({
      'url': url,
      'tags': tags,
    });
    await _saveRoot(root);
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
      var title = cmd.split(RegExp(r'[\r\n]')).first.trim();
      if (title.length > 48) title = '${title.substring(0, 45)}…';
      out.add(CardItem(
        title: title,
        subtitle: tags.isEmpty ? null : tags.join(', '),
        icon: Icons.terminal,
        data: cmd,
        isUserEntry: true,
        tags: tags,
      ));
    }
    return out;
  }

  Future<void> addCommand({required String command, required List<String> tags}) async {
    final root = await _loadRoot();
    (root['commands'] as List<dynamic>).add({
      'command': command,
      'tags': tags,
    });
    await _saveRoot(root);
  }

  Future<List<CardItem>> loadNoteCardItems() async {
    final root = await _loadRoot();
    final list = root['notes'] as List<dynamic>;
    final out = <CardItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final content = e['content'] as String? ?? '';
      if (content.isEmpty) continue;
      final tags = _tagsFromJson(e['tags']);
      var firstLine = content.split(RegExp(r'[\r\n]')).first.trim();
      if (firstLine.length > 40) firstLine = '${firstLine.substring(0, 37)}…';
      final title = firstLine.isEmpty ? '（无标题）' : firstLine;
      out.add(CardItem(
        title: title,
        subtitle: tags.isEmpty ? null : tags.join(', '),
        icon: Icons.note,
        data: content,
        isUserEntry: true,
        tags: tags,
      ));
    }
    return out;
  }

  Future<void> addNote({required String content, required List<String> tags}) async {
    final root = await _loadRoot();
    (root['notes'] as List<dynamic>).add({
      'content': content,
      'tags': tags,
    });
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
    required List<String> tags,
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
    required List<String> tags,
  }) async {
    final root = await _loadRoot();
    final list = root['web'] as List<dynamic>;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e is Map && (e['url'] as String?) == oldUrl) {
        list[i] = {'url': url, 'tags': tags};
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
    required List<String> tags,
  }) async {
    final root = await _loadRoot();
    final list = root['commands'] as List<dynamic>;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e is Map && (e['command'] as String?) == oldCommand) {
        list[i] = {'command': command, 'tags': tags};
        break;
      }
    }
    await _saveRoot(root);
  }

  Future<void> removeNote(String content) async {
    final root = await _loadRoot();
    (root['notes'] as List<dynamic>).removeWhere(
        (e) => e is Map && (e['content'] as String?) == content);
    await _saveRoot(root);
  }

  Future<void> updateNote({
    required String oldContent,
    required String content,
    required List<String> tags,
  }) async {
    final root = await _loadRoot();
    final list = root['notes'] as List<dynamic>;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e is Map && (e['content'] as String?) == oldContent) {
        list[i] = {'content': content, 'tags': tags};
        break;
      }
    }
    await _saveRoot(root);
  }
}
