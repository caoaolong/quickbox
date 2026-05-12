import 'package:flutter/material.dart';

class CardItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final dynamic data;

  const CardItem({
    required this.title,
    this.subtitle,
    this.icon = Icons.description,
    this.data,
  });
}

abstract class BaseCard {
  String get name;
  IconData get icon;
  List<Color> get gradient;

  Future<List<CardItem>> scan();
  void onItemTap(CardItem item);
}
