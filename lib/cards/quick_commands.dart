import 'dart:io';

import 'package:flutter/material.dart';
import 'base_card.dart';
import '../pages/card_item_form_page.dart';
import '../services/user_card_store.dart';

class _QuickCommandsItemInteractor implements CardItemInteractor {
  _QuickCommandsItemInteractor(this.card);
  final QuickCommandsCard card;

  @override
  void onItemTap(CardItem item) {
    if (!item.isUserEntry) return;
    final cmd = item.data as String?;
    if (cmd != null && cmd.isNotEmpty) {
      Process.run('cmd', ['/c', cmd], runInShell: true);
    }
  }

  @override
  void onItemEdit(BuildContext context, CardItem item) {
    if (!item.isUserEntry) return;
    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CardItemFormPage(
          cardIndex: 2,
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
    final cmd = item.data as String?;
    if (cmd == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: const Text('确定删除该快捷命令？'),
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
      await card.userStore.removeCommand(cmd);
      card.onUserDataChanged?.call();
    }
  }
}

class QuickCommandsCard extends BaseCard {
  final UserCardStore userStore;

  QuickCommandsCard({
    required this.userStore,
    super.onUserDataChanged,
  });

  @override
  CardItemInteractor get itemInteractor => _itemInteractor;
  late final _QuickCommandsItemInteractor _itemInteractor =
      _QuickCommandsItemInteractor(this);

  @override
  String get name => '快捷指令';

  @override
  IconData get icon => Icons.flash_on;

  @override
  List<Color> get gradient => const [Color(0xFF9B7FB5), Color(0xFF7A5F95)];

  @override
  Future<List<CardItem>> scan() async {
    return userStore.loadCommandCardItems();
  }
}
