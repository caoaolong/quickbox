/// 有界 Levenshtein：超过 [maxDist] 返回 null。
int? boundedLevenshtein(String a, String b, int maxDist) {
  if (a == b) return 0;
  if ((a.length - b.length).abs() > maxDist) return null;
  final m = a.length;
  final n = b.length;
  var previous = List<int>.generate(n + 1, (j) => j);
  for (var i = 1; i <= m; i++) {
    final current = List<int>.filled(n + 1, 0);
    current[0] = i;
    var rowMin = current[0];
    for (var j = 1; j <= n; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final ins = current[j - 1] + 1;
      final del = previous[j] + 1;
      final sub = previous[j - 1] + cost;
      final v = ins < del ? ins : del;
      current[j] = v < sub ? v : sub;
      if (current[j] < rowMin) rowMin = current[j];
    }
    if (rowMin > maxDist) return null;
    previous = current;
  }
  final d = previous[n];
  return d > maxDist ? null : d;
}
