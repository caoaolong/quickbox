import 'dart:io';

import 'package:flutter/material.dart';
import 'base_card.dart';
import '../pages/card_item_form_page.dart';
import '../services/user_card_store.dart';

class _WebQuickOpenItemInteractor implements CardItemInteractor {
  _WebQuickOpenItemInteractor(this.card);
  final WebQuickOpenCard card;

  @override
  void onItemTap(CardItem item) {
    final url = item.data as String?;
    if (url == null || url.isEmpty) return;
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
    } else {
      Process.run('xdg-open', [url], runInShell: true);
    }
  }

  @override
  void onItemEdit(BuildContext context, CardItem item) {
    if (!item.isUserEntry) return;
    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CardItemFormPage(
          cardIndex: 1,
          gradient: card.gradient,
          cardTitle: card.name,
          userCardStore: card.userStore,
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
    if (!item.isUserEntry) return;
    final url = item.data as String?;
    if (url == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定删除「$url」？'),
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
      await card.userStore.removeWeb(url);
      card.onUserDataChanged?.call();
    }
  }
}

class WebQuickOpenCard extends BaseCard {
  final UserCardStore userStore;

  WebQuickOpenCard({
    required this.userStore,
    super.onUserDataChanged,
  });

  @override
  CardItemInteractor get itemInteractor => _itemInteractor;
  late final _WebQuickOpenItemInteractor _itemInteractor =
      _WebQuickOpenItemInteractor(this);

  @override
  String get name => '网页快开';

  @override
  IconData get icon => Icons.public;

  @override
  List<Color> get gradient => const [Color(0xFF5BA57B), Color(0xFF3D7A5B)];

  @override
  Future<List<CardItem>> scan() async {
    final user = await userStore.loadWebCardItems();
    return [
      ...user,
      const CardItem(
        title: 'GitHub',
        icon: Icons.code,
        data: 'https://github.com',
      ),
      const CardItem(
        title: 'Stack Overflow',
        icon: Icons.help,
        data: 'https://stackoverflow.com',
      ),
      const CardItem(
        title: 'Google',
        icon: Icons.search,
        data: 'https://google.com',
      ),
      const CardItem(
        title: '哔哩哔哩',
        icon: Icons.videocam,
        data: 'https://bilibili.com',
      ),
      const CardItem(title: '知乎', icon: Icons.forum, data: 'https://zhihu.com'),
    ];
  }
}
