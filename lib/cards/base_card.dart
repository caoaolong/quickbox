import 'package:flutter/material.dart';

class CardItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final dynamic data;
  final String? iconPath;

  const CardItem({
    required this.title,
    this.subtitle,
    this.icon = Icons.description,
    this.data,
    this.iconPath,
  });
}

abstract class BaseCard {
  String get name;
  IconData get icon;
  List<Color> get gradient;

  Future<List<CardItem>> scan();
  Future<List<CardItem>> search(String keywords) async => [];
  void onItemTap(CardItem item);
}
