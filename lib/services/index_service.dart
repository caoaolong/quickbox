import 'dart:convert';
import 'dart:io';

import '../cards/quick_apps.dart';
import 'app_settings.dart';

class IndexService {
  final AppSettings appSettings;

  IndexService({required this.appSettings});

  Future<int> buildIndex() async {
    final card = QuickAppsCard();
    final items = await card.scan();

    final data = items.map((item) => {
      'title': item.title,
      'path': item.iconPath,
    }).toList();

    final file = File('${appSettings.indexDirectory}\\apps.json');
    await file.writeAsString(jsonEncode(data));
    return data.length;
  }
}
