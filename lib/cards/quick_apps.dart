import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'base_card.dart';

class QuickAppsCard extends BaseCard {
  final String? indexDirectory;

  QuickAppsCard({this.indexDirectory});
  @override
  String get name => '快捷应用';

  @override
  IconData get icon => Icons.apps;

  @override
  List<Color> get gradient => const [Color(0xFF5B7FA5), Color(0xFF3D5A80)];

  @override
  Future<List<CardItem>> scan() async {
    final items = <CardItem>[];
    final seen = <String>{};

    await _scanStartMenu(items, seen);
    await _scanPathExecutables(items, seen);

    items.sort((a, b) => a.title.compareTo(b.title));
    return items;
  }

  @override
  Future<List<CardItem>> search(String keywords) async {
    if (indexDirectory == null || keywords.trim().isEmpty) return [];
    final file = File('$indexDirectory\\apps.json');
    if (!await file.exists()) return [];

    try {
      final data = jsonDecode(await file.readAsString()) as List;
      final query = keywords.trim().toLowerCase();
      final results = <CardItem>[];
      final seen = <String>{};

      for (final item in data) {
        final title = item['title'] as String? ?? '';
        if (title.toLowerCase().contains(query) && seen.add(title)) {
          final path = item['path'] as String?;
          results.add(CardItem(
            title: title,
            icon: Icons.launch,
            data: path,
            iconPath: path,
          ));
        }
      }

      results.sort((a, b) => a.title.compareTo(b.title));
      return results;
    } catch (_) {
      return [];
    }
  }

  Future<void> _scanStartMenu(List<CardItem> items, Set<String> seen) async {
    final programData = Platform.environment['PROGRAMDATA'];
    final appData = Platform.environment['APPDATA'];

    final paths = [
      if (programData != null)
        '$programData\\Microsoft\\Windows\\Start Menu\\Programs',
      if (appData != null) '$appData\\Microsoft\\Windows\\Start Menu\\Programs',
    ];

    for (final path in paths) {
      final dir = Directory(path);
      if (!await dir.exists()) continue;
      await _walkDir(dir, items, seen);
    }
  }

  Future<void> _walkDir(
    Directory dir,
    List<CardItem> items,
    Set<String> seen,
  ) async {
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          await _walkDir(entity, items, seen);
        } else if (entity is File) {
          final p = entity.path;
          final name = p.split(Platform.pathSeparator).last;
          if (!name.endsWith('.lnk')) continue;
          final title = _cleanName(name.substring(0, name.length - 4));
          if (title.isNotEmpty && seen.add(title)) {
            items.add(
              CardItem(title: title, icon: Icons.launch, data: p, iconPath: p),
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _scanPathExecutables(
    List<CardItem> items,
    Set<String> seen,
  ) async {
    final pathStr = Platform.environment['PATH'] ?? '';
    for (final dirPath in pathStr.split(';')) {
      final trimmed = dirPath.trim();
      if (trimmed.isEmpty) continue;
      final dir = Directory(trimmed);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File) {
            final p = entity.path;
            final name = p.split(Platform.pathSeparator).last.toLowerCase();
            if (!name.endsWith('.exe') &&
                !name.endsWith('.cmd') &&
                !name.endsWith('.bat')) {
              continue;
            }
            final title = _cleanName(name.substring(0, name.lastIndexOf('.')));
            if (title.isNotEmpty && seen.add(title)) {
              items.add(
                CardItem(
                  title: title,
                  icon: Icons.dashboard,
                  data: p,
                  iconPath: p,
                ),
              );
            }
          }
        }
      } catch (_) {}
    }
  }

  String _cleanName(String name) {
    name = name.trim();
    if (name.isEmpty) return '';
    name = name.replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '');
    name = name.replaceAll(RegExp(r'[\s\-_]+$'), '');
    return name;
  }

  @override
  void onItemTap(CardItem item) {
    final path = item.data as String;
    if (path.toLowerCase().endsWith('.lnk')) {
      Process.run('cmd', ['/c', 'start', '', path], runInShell: true);
    } else {
      Process.run(path, [], runInShell: true);
    }
  }
}
