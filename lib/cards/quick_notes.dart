import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'base_card.dart';
import '../pages/card_item_form_page.dart';
import '../services/user_card_store.dart';

class _QuickNotesItemInteractor implements CardItemInteractor {
  _QuickNotesItemInteractor(this.card);
  final QuickNotesCard card;

  @override
  void onItemTap(CardItem item) {
    if (item.isUserEntry) {
      final text = item.data as String?;
      if (text != null && text.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: text));
      }
      return;
    }
  }

  @override
  void onItemEdit(BuildContext context, CardItem item) {
    if (!item.isUserEntry) return;
    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CardItemFormPage(
          cardIndex: 3,
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
    final content = item.data as String?;
    if (content == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: const Text('确定删除该笔记？'),
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
      await card.userStore.removeNote(content);
      card.onUserDataChanged?.call();
    }
  }
}

class QuickNotesCard extends BaseCard {
  final UserCardStore userStore;

  QuickNotesCard({
    required this.userStore,
    super.onUserDataChanged,
  });

  @override
  CardItemInteractor get itemInteractor => _itemInteractor;
  late final _QuickNotesItemInteractor _itemInteractor =
      _QuickNotesItemInteractor(this);

  @override
  String get name => '快速笔记';

  @override
  IconData get icon => Icons.note;

  @override
  List<Color> get gradient => const [Color(0xFFC49B6B), Color(0xFFA57B4B)];

  @override
  Future<List<CardItem>> scan() async {
    final user = await userStore.loadNoteCardItems();
    return [
      ...user,
      const CardItem(
        title: '会议记录',
        subtitle: '2024-01-15',
        icon: Icons.meeting_room,
      ),
      const CardItem(title: '待办事项', subtitle: '5 项未完成', icon: Icons.checklist),
      const CardItem(title: '学习笔记', subtitle: 'Flutter 相关', icon: Icons.school),
      const CardItem(title: '代码片段', subtitle: '常用代码段', icon: Icons.terminal),
    ];
  }
}
