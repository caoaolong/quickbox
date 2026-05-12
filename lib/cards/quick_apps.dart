import 'package:flutter/material.dart';
import 'base_card.dart';

class QuickAppsCard extends BaseCard {
  @override
  String get name => '快捷应用';

  @override
  IconData get icon => Icons.apps;

  @override
  List<Color> get gradient => const [Color(0xFF5B7FA5), Color(0xFF3D5A80)];

  @override
  Future<List<CardItem>> scan() async {
    return [
      const CardItem(title: 'Visual Studio Code', icon: Icons.code, data: 'code'),
      const CardItem(title: 'Terminal', icon: Icons.terminal, data: 'terminal'),
      const CardItem(title: '浏览器', icon: Icons.language, data: 'browser'),
      const CardItem(title: '计算器', icon: Icons.calculate, data: 'calculator'),
      const CardItem(title: '记事本', icon: Icons.edit_note, data: 'notepad'),
    ];
  }

  @override
  void onItemTap(CardItem item) {
    // TODO: 启动应用
  }
}
