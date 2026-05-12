import 'package:flutter/material.dart';
import 'base_card.dart';

class QuickCommandsCard extends BaseCard {
  @override
  String get name => '快捷指令';

  @override
  IconData get icon => Icons.flash_on;

  @override
  List<Color> get gradient => const [Color(0xFF9B7FB5), Color(0xFF7A5F95)];

  @override
  Future<List<CardItem>> scan() async {
    return [
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

  @override
  void onItemTap(CardItem item) {
    // TODO: 执行系统指令
  }
}
