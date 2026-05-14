import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'base_card.dart';
import '../pages/card_item_form_page.dart';
import '../services/hybrid_search/hybrid_search_engine.dart';
import '../services/user_card_store.dart';

class _QuickNotesItemInteractor implements CardItemInteractor {
  _QuickNotesItemInteractor(this.card);
  final QuickNotesCard card;

  @override
  void onItemTap(CardItem item) {
    if (!item.isUserEntry) return;
    try {
      final raw = item.data;
      final m = raw is String
          ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
          : Map<String, dynamic>.from(raw as Map);
      final kind = m['kind']?.toString() ?? NoteKind.note;
      final String text;
      switch (kind) {
        case NoteKind.account:
          text =
              '账户名：${m['accountName'] ?? ''}\n用户名：${m['userName'] ?? ''}\n密码：${m['password'] ?? ''}';
          break;
        case NoteKind.token:
          text = '账户名：${m['accountName'] ?? ''}\nToken：${m['tokenValue'] ?? ''}';
          break;
        default:
          final t = m['title']?.toString().trim() ?? '';
          final body = m['noteContent']?.toString() ?? '';
          text = t.isNotEmpty ? '$t\n\n$body' : body;
      }
      Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      Clipboard.setData(ClipboardData(text: item.data?.toString() ?? ''));
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
    String? id;
    try {
      final raw = item.data;
      final m = raw is String
          ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
          : Map<String, dynamic>.from(raw as Map);
      id = m['id']?.toString();
    } catch (_) {}
    if (id == null || id.isEmpty) return;
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
      await card.userStore.removeNoteById(id);
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
    return userStore.loadNoteCardItems();
  }

  @override
  Future<List<CardItem>> search(String keywords) async {
    final all = await loadSearchItemPool();
    return HybridSearch.sortCardItems(keywords, all);
  }
}
