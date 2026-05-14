String normalizeQuery(String query) {
  return query
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// 仅保留小写字母与数字，用于拼音通道与编辑距离。
String compressAscii(String s) {
  return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
