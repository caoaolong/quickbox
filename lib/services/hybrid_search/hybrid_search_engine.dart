import '../../cards/base_card.dart';
import 'edit_distance.dart';
import 'fzf_subsequence.dart';
import 'normalize.dart';
import 'search_channels.dart';
import 'trie_index.dart';

const double _wFzf = 1.0;
const double _wLev = 42.0;
const double _wPrefix = 28.0;
const int _levMax = 2;

class HybridSearchEngine {
  HybridSearchEngine._(
    this._channels,
    this._trieOrig,
    this._triePinyin,
    this._trieInitials,
  );

  final List<SearchChannels> _channels;
  final TrieIndex _trieOrig;
  final TrieIndex _triePinyin;
  final TrieIndex _trieInitials;

  int get count => _channels.length;

  factory HybridSearchEngine.build(List<SearchChannels> channels) {
    final t0 = TrieIndex();
    final t1 = TrieIndex();
    final t2 = TrieIndex();
    for (var i = 0; i < channels.length; i++) {
      final c = channels[i];
      if (c.original.isNotEmpty) {
        t0.addStringWithPrefixes(i, c.original);
      }
      if (c.fullPinyin.isNotEmpty) {
        t1.addStringWithPrefixes(i, c.fullPinyin);
      }
      if (c.initials.isNotEmpty) {
        t2.addStringWithPrefixes(i, c.initials);
      }
    }
    return HybridSearchEngine._(channels, t0, t1, t2);
  }

  static double _levTerm(String qCompact, String? target) {
    if (target == null || target.isEmpty) return 0;
    if (qCompact.length < 2) return 0;
    final d = boundedLevenshtein(qCompact, target, _levMax);
    if (d == null) return 0;
    return (3 - d).clamp(0, 3).toDouble();
  }

  static double _prefixHit(
    TrieIndex trie,
    String prefix,
    int docId,
    int channelLen,
  ) {
    if (prefix.isEmpty) return 0;
    final set = trie.docsWithPrefix(prefix);
    if (set == null || !set.contains(docId)) return 0;
    return prefix.length / (channelLen > 0 ? channelLen : 1);
  }

  /// 返回 (docIndex, score)，仅包含得分 > 0 的文档；按得分降序，同分按 index 升序稳定排序。
  List<(int, double)> rankedIndices(String rawQuery) {
    final qn = normalizeQuery(rawQuery);
    if (qn.isEmpty) return [];
    final qCompact = qn.replaceAll(' ', '');

    final candidates = _collectCandidates(qn, qCompact);
    final out = <(int, double)>[];

    for (final i in candidates) {
      final ch = _channels[i];
      final fOrig = fzfSubsequenceScore(qn, ch.original);
      final fPy = fzfSubsequenceScore(qCompact, ch.fullPinyin);
      final fIn = fzfSubsequenceScore(qCompact, ch.initials);
      var fzfMax = fOrig;
      if (fPy > fzfMax) fzfMax = fPy;
      if (fIn > fzfMax) fzfMax = fIn;

      final asc = compressAscii(ch.original);
      var lev = 0.0;
      lev = _levTerm(qCompact, ch.fullPinyin);
      final levIn = _levTerm(qCompact, ch.initials);
      if (levIn > lev) lev = levIn;
      final levAsc = _levTerm(qCompact, asc);
      if (levAsc > lev) lev = levAsc;

      var pref = 0.0;
      if (ch.original.isNotEmpty) {
        pref += _prefixHit(_trieOrig, qn, i, ch.original.length);
      }
      if (ch.fullPinyin.isNotEmpty) {
        pref += _prefixHit(_triePinyin, qCompact, i, ch.fullPinyin.length);
      }
      if (ch.initials.isNotEmpty) {
        pref += _prefixHit(_trieInitials, qCompact, i, ch.initials.length);
      }

      final total = _wFzf * fzfMax + _wLev * lev + _wPrefix * pref;
      if (total > 0) {
        out.add((i, total));
      }
    }

    out.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      if (c != 0) return c;
      final ta = _channels[a.$1].original;
      final tb = _channels[b.$1].original;
      final ct = ta.compareTo(tb);
      if (ct != 0) return ct;
      return a.$1.compareTo(b.$1);
    });
    return out;
  }

  Set<int> _collectCandidates(String qn, String qCompact) {
    final union = <int>{};
    var hitAny = false;

    void tryTrie(TrieIndex trie, String prefix) {
      if (prefix.isEmpty) return;
      final s = trie.docsWithPrefix(prefix);
      if (s != null && s.isNotEmpty) {
        union.addAll(s);
        hitAny = true;
      }
    }

    tryTrie(_trieOrig, qn);
    tryTrie(_triePinyin, qCompact);
    tryTrie(_trieInitials, qCompact);

    if (!hitAny || union.isEmpty) {
      return Set<int>.from(List<int>.generate(count, (i) => i));
    }
    return union;
  }
}

/// 对外统一入口：CardItem 排序、带 cardIndex 的条目排序。
class HybridSearch {
  HybridSearch._();

  static List<(int index, double score)> rankIndices(
    String query,
    List<SearchChannels> channels,
  ) {
    if (normalizeQuery(query).isEmpty) return [];
    if (channels.isEmpty) return [];
    final engine = HybridSearchEngine.build(channels);
    return engine.rankedIndices(query);
  }

  static List<CardItemWithScore<T>> rankPayloads<T>(
    String query,
    List<T> payloads,
    SearchChannels Function(T item) channelFn,
  ) {
    if (normalizeQuery(query).isEmpty) return [];
    if (payloads.isEmpty) return [];
    final channels = payloads.map(channelFn).toList();
    final ranked = rankIndices(query, channels);
    return ranked
        .map((e) => CardItemWithScore(payloads[e.$1], e.$2))
        .toList();
  }

  static List<CardItem> sortCardItems(String query, List<CardItem> items) {
    if (normalizeQuery(query).isEmpty) return [];
    if (items.isEmpty) return [];
    final ranked = rankPayloads(query, items, SearchChannels.fromCardItem);
    return ranked.map((r) => r.item).toList();
  }

  /// 跨卡片统一排序：输入扁平列表（含来源卡片下标），返回按相关度排序后的条目。
  static List<({CardItem item, int cardIndex})> rankCardEntries(
    String query,
    List<({CardItem item, int cardIndex})> entries,
  ) {
    if (normalizeQuery(query).isEmpty) return [];
    if (entries.isEmpty) return [];
    final channels = entries.map((e) => SearchChannels.fromCardItem(e.item)).toList();
    final ranked = rankIndices(query, channels);
    return ranked.map((r) => entries[r.$1]).toList();
  }
}

class CardItemWithScore<T> {
  const CardItemWithScore(this.item, this.score);
  final T item;
  final double score;
}
