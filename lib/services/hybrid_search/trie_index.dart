class TrieNode {
  final Map<String, TrieNode> children = {};
  final Set<int> docIds = {};
}

/// 将每条文档在各通道上的字符串的**所有前缀**挂载 docId，用于前缀候选剪枝。
class TrieIndex {
  final TrieNode root = TrieNode();

  void addStringWithPrefixes(int docId, String key) {
    if (key.isEmpty) return;
    var node = root;
    for (var i = 0; i < key.length; i++) {
      final c = key[i];
      node = node.children.putIfAbsent(c, TrieNode.new);
      node.docIds.add(docId);
    }
  }

  /// 无此前缀路径时返回 null；路径存在但无文档时返回空 Set（不应出现）。
  Set<int>? docsWithPrefix(String prefix) {
    if (prefix.isEmpty) return null;
    var node = root;
    for (var i = 0; i < prefix.length; i++) {
      final c = prefix[i];
      final next = node.children[c];
      if (next == null) return null;
      node = next;
    }
    return node.docIds;
  }
}
