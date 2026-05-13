import 'package:flutter/material.dart';

class CardItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final dynamic data;
  final String? iconPath;
  /// 用户通过表单新建的条目（与内置条目区分处理逻辑）
  final bool isUserEntry;
  /// 标签（用户条目用于编辑表单；内置条目可为空）
  final List<String> tags;

  const CardItem({
    required this.title,
    this.subtitle,
    this.icon = Icons.description,
    this.data,
    this.iconPath,
    this.isUserEntry = false,
    this.tags = const [],
  });
}

/// 列表项交互：点击、编辑、删除（由各卡片实现具体子类）
abstract class CardItemInteractor {
  void onItemTap(CardItem item);
  void onItemEdit(BuildContext context, CardItem item);
  void onItemDelete(BuildContext context, CardItem item);
}

abstract class BaseCard {
  String get name;
  IconData get icon;
  List<Color> get gradient;

  /// 用户增删改条目后刷新列表（由主界面注入）
  final VoidCallback? onUserDataChanged;

  BaseCard({this.onUserDataChanged});

  CardItemInteractor get itemInteractor;

  Future<List<CardItem>> scan();
  Future<List<CardItem>> search(String keywords) async => [];
}
