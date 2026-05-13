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
    if (item.isUserEntry) {
      final cmd = item.data as String?;
      if (cmd != null && cmd.isNotEmpty) {
        Process.run('cmd', ['/c', cmd], runInShell: true);
      }
      return;
    }
    final id = item.data as String?;
    if (id == null) return;
    switch (id) {
      case 'empty_trash':
        Process.run('cmd', ['/c', 'rd', '/s', '/q', r'%systemdrive%\$Recycle.Bin'],
            runInShell: true);
        break;
      case 'screenshot':
        Process.run('cmd', ['/c', 'snippingtool'], runInShell: true);
        break;
      case 'task_manager':
        Process.run('taskmgr', [], runInShell: true);
        break;
      case 'lock_screen':
        Process.run('cmd', ['/c', 'rundll32.exe', 'user32.dll,LockWorkStation'],
            runInShell: true);
        break;
      case 'sleep':
        Process.run(
            'cmd', ['/c', 'rundll32.exe', 'powrprof.dll,SetSuspendState', '0,1,0'],
            runInShell: true);
        break;
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
    final user = await userStore.loadCommandCardItems();
    return [
      ...user,
      const CardItem(
        title: '清空回收站',
        icon: Icons.delete_sweep,
        data: 'empty_trash',
      ),
      const CardItem(title: '截屏', icon: Icons.screenshot, data: 'screenshot'),
      const CardItem(
        title: '打开任务管理器',
        icon: Icons.settings,
        data: 'task_manager',
      ),
      const CardItem(title: '锁定屏幕', icon: Icons.lock, data: 'lock_screen'),
      const CardItem(
        title: '休眠',
        icon: Icons.power_settings_new,
        data: 'sleep',
      ),
    ];
  }
}
