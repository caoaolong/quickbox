import 'package:flutter/material.dart';
import 'base_card.dart';

class WebQuickOpenCard extends BaseCard {
  @override
  String get name => '网页快开';

  @override
  IconData get icon => Icons.public;

  @override
  List<Color> get gradient => const [Color(0xFF5BA57B), Color(0xFF3D7A5B)];

  @override
  Future<List<CardItem>> scan() async {
    return [
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

  @override
  void onItemTap(CardItem item) {
    // TODO: 用浏览器打开链接
  }
}
