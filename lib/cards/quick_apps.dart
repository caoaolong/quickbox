import 'dart:io';

import 'package:flutter/material.dart';
import 'base_card.dart';
import '../pages/card_item_form_page.dart';
import '../services/hybrid_search/hybrid_search_engine.dart';
import '../services/user_card_store.dart';

class _QuickAppsItemInteractor implements CardItemInteractor {
  _QuickAppsItemInteractor(this.card);
  final QuickAppsCard card;

  @override
  void onItemTap(CardItem item) {
    final path = item.data as String;
    if (path.toLowerCase().endsWith('.lnk')) {
      Process.run('cmd', ['/c', 'start', '', path], runInShell: true);
    } else {
      Process.run(path, [], runInShell: true);
    }
  }

  @override
  void onItemEdit(BuildContext context, CardItem item) {
    if (!item.isUserEntry || card.userStore == null) return;
    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CardItemFormPage(
          cardIndex: 0,
          gradient: card.gradient,
          cardTitle: card.name,
          userCardStore: card.userStore!,
          editingItem: item,
        ),
      ),
    )
        .then((saved) {
      if (saved == true) card.onUserDataChanged?.call();
    });
  }

  @override
  void onItemDelete(BuildContext context, CardItem item) async {
    if (!item.isUserEntry || card.userStore == null) return;
    final path = item.data as String?;
    if (path == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定删除「${item.title}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await card.userStore!.removeApp(path);
      card.onUserDataChanged?.call();
    }
  }
}

class QuickAppsCard extends BaseCard {
  final String? indexDirectory;
  /// 为 null 时（例如仅构建索引）不合并用户自定义应用
  final UserCardStore? userStore;

  QuickAppsCard({
    this.indexDirectory,
    this.userStore,
    super.onUserDataChanged,
  });

  String? _searchPoolFp;
  List<CardItem>? _searchPoolItems;

  void invalidateSearchPoolCache() {
    _searchPoolFp = null;
    _searchPoolItems = null;
  }

  @override
  CardItemInteractor get itemInteractor => _itemInteractor;
  late final _QuickAppsItemInteractor _itemInteractor =
      _QuickAppsItemInteractor(this);

  @override
  String get name => '快捷应用';

  @override
  IconData get icon => Icons.apps;

  @override
  List<Color> get gradient => const [Color(0xFF5B7FA5), Color(0xFF3D5A80)];

  @override
  Future<List<CardItem>> scan() async {
    final userItems =
        userStore != null ? await userStore!.loadAppCardItems() : <CardItem>[];
    final items = <CardItem>[...userItems];
    final seen = <String>{for (final u in userItems) u.data as String};

    await _scanStartMenu(items, seen);
    await _scanPathExecutables(items, seen);

    items.sort((a, b) => a.title.compareTo(b.title));
    return items;
  }

  Future<String> _computeSearchPoolFingerprint() async {
    final parts = <String>[];
    parts.add(Platform.environment['PATH'] ?? '');
    if (userStore != null) {
      final uf = File(userStore!.appSettings.userEntriesPath);
      if (await uf.exists()) {
        final st = await uf.stat();
        parts.add(
          'user:${st.modified.millisecondsSinceEpoch}:${st.size}',
        );
      } else {
        parts.add('user:missing');
      }
    } else {
      parts.add('user:none');
    }
    final programData = Platform.environment['PROGRAMDATA'];
    final appData = Platform.environment['APPDATA'];
    for (final root in [
      if (programData != null)
        '$programData\\Microsoft\\Windows\\Start Menu\\Programs',
      if (appData != null)
        '$appData\\Microsoft\\Windows\\Start Menu\\Programs',
    ]) {
      final d = Directory(root);
      if (await d.exists()) {
        try {
          final st = await d.stat();
          parts.add('sm:$root:${st.modified.millisecondsSinceEpoch}');
        } catch (_) {
          parts.add('sm:$root:err');
        }
      }
    }
    return parts.join('|');
  }

  /// 与 [scan] 同源：保证列表里能看到的快捷应用均可被搜索（不仅限于 apps.json）。
  @override
  Future<List<CardItem>> loadSearchItemPool() async {
    final fp = await _computeSearchPoolFingerprint();
    if (_searchPoolFp == fp && _searchPoolItems != null) {
      return _searchPoolItems!;
    }
    final results = await scan();
    _searchPoolFp = fp;
    _searchPoolItems = results;
    return results;
  }

  @override
  Future<List<CardItem>> search(String keywords) async {
    final pool = await loadSearchItemPool();
    return HybridSearch.sortCardItems(keywords, pool);
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
}
