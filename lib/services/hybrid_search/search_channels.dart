import 'package:lpinyin/lpinyin.dart';

import '../../cards/base_card.dart';
import 'normalize.dart';

/// 单条文档的三通道检索文本。
class SearchChannels {
  const SearchChannels({
    required this.original,
    required this.fullPinyin,
    required this.initials,
  });

  final String original;
  final String fullPinyin;
  final String initials;

  static SearchChannels fromCardItem(CardItem item) {
    final buf = StringBuffer();
    buf.write(item.title);
    if (item.subtitle != null && item.subtitle!.trim().isNotEmpty) {
      buf.write(' ');
      buf.write(item.subtitle);
    }
    for (final t in item.tags) {
      final tt = t.trim();
      if (tt.isNotEmpty) {
        buf.write(' ');
        buf.write(tt);
      }
    }
    final dataStr = switch (item.data) {
      final String s => s.trim(),
      final Map m =>
          (m['command']?.toString() ?? '').trim(),
      _ => '',
    };
    if (dataStr.isNotEmpty) {
      buf.write(' ');
      buf.write(dataStr);
    }
    final ip = item.iconPath?.trim();
    if (ip != null && ip.isNotEmpty && ip != dataStr) {
      buf.write(' ');
      buf.write(ip);
    }
    final combined = buf.toString().trim();
    if (combined.isEmpty) {
      return const SearchChannels(original: '', fullPinyin: '', initials: '');
    }

    final original = combined.toLowerCase();

    var fullPy = '';
    try {
      fullPy = PinyinHelper.getPinyinE(
        combined,
        separator: '',
        defPinyin: '',
        format: PinyinFormat.WITHOUT_TONE,
      ).toLowerCase();
    } catch (_) {}
    fullPy = compressAscii(fullPy);

    var initialsStr = '';
    try {
      initialsStr = PinyinHelper.getShortPinyin(combined).toLowerCase();
    } catch (_) {}
    initialsStr = compressAscii(initialsStr);
    if (initialsStr.isEmpty && fullPy.isNotEmpty) {
      initialsStr = fullPy;
    }

    return SearchChannels(
      original: original,
      fullPinyin: fullPy,
      initials: initialsStr,
    );
  }
}
