/// FZF 风格子序列匹配得分：靠前、连续匹配加分；非子序列返回 0。
double fzfSubsequenceScore(String query, String haystack) {
  if (query.isEmpty) return 0;
  if (haystack.isEmpty) return 0;
  final q = query.toLowerCase();
  final h = haystack.toLowerCase();
  var qi = 0;
  final positions = <int>[];
  for (var hi = 0; hi < h.length && qi < q.length; hi++) {
    if (h[hi] == q[qi]) {
      positions.add(hi);
      qi++;
    }
  }
  if (qi < q.length) return 0;

  const startBonus = 120.0;
  const consecutiveBonus = 35.0;
  const earlyWeight = 3.0;
  final first = positions.first;
  double score = startBonus - first * earlyWeight;
  for (var k = 1; k < positions.length; k++) {
    if (positions[k] == positions[k - 1] + 1) {
      score += consecutiveBonus;
    }
  }
  final span = positions.last - first + 1;
  if (span > 0) {
    score += (q.length / span) * 80.0;
  }
  return score;
}
