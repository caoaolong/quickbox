import 'package:flutter/material.dart';
import 'base_card.dart';

class QuickNotesCard extends BaseCard {
  @override
  String get name => '快速笔记';

  @override
  IconData get icon => Icons.note;

  @override
  List<Color> get gradient => const [Color(0xFFC49B6B), Color(0xFFA57B4B)];

  @override
  Future<List<CardItem>> scan() async {
    return [
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

  @override
  void onItemTap(CardItem item) {
    // TODO: 打开笔记
  }
}
