import 'dart:io';

import 'package:flutter/material.dart';
import 'base_card.dart';
import '../pages/card_item_form_page.dart';
import '../services/hybrid_search/hybrid_search_engine.dart';
import '../services/user_card_store.dart';

void _scheduleTempCleanup(Directory dir) {
  Future<void>.delayed(const Duration(seconds: 4), () async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  });
}

Future<void> _runUnixTerminalKeepOpen(String cmd) async {
  final dir = Directory.systemTemp.createTempSync('qb_cmd');
  final script = File('${dir.path}${Platform.pathSeparator}run.sh');
  await script.writeAsString('#!/usr/bin/env bash\nset +e\n$cmd\nexec bash\n');
  final chmod = await Process.run('chmod', ['+x', script.path]);
  if (chmod.exitCode != 0) {
    await Process.run('/bin/sh', ['-c', cmd]);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
    return;
  }

  final path = script.path;

  if (Platform.isMacOS) {
    final escaped =
        path.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    final appleScript =
        'tell application "Terminal" to do script "/bin/bash " & quoted form of "$escaped"';
    await Process.run('osascript', [
      '-e',
      'tell application "Terminal" to activate',
      '-e',
      appleScript,
    ]);
    _scheduleTempCleanup(dir);
    return;
  }

  final attempts = <List<String>>[
    ['gnome-terminal', '--', path],
    ['xfce4-terminal', '-x', path],
    ['konsole', '-e', path],
    ['xterm', '-e', path],
  ];
  for (final argv in attempts) {
    try {
      await Process.start(
        argv.first,
        argv.skip(1).toList(),
        mode: ProcessStartMode.detached,
      );
      _scheduleTempCleanup(dir);
      return;
    } catch (_) {}
  }
  await Process.run('/bin/sh', ['-c', cmd]);
  try {
    await dir.delete(recursive: true);
  } catch (_) {}
}

/// 多行快捷指令合并为一行：按顺序用 `&&` 连接（便于 Windows `cmd` 与其它平台的 `sh -c`）。
String _chainQuickCommandLines(String cmd) {
  final parts = cmd
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.single;
  return parts.join(' && ');
}

/// 运行快捷指令正文（Windows：后台 `cmd /c`；保留窗口用 `start`+`cmd /k` 弹出可见控制台；Unix：`sh -c` 或图形终端）。
void runQuickCommand(String cmd, {required bool waitAfterRun}) {
  if (cmd.trim().isEmpty) return;
  final chained = _chainQuickCommandLines(cmd);
  if (chained.isEmpty) return;
  if (Platform.isWindows) {
    // 勿用 runInShell，否则再套一层 cmd，且多行参数易被错误解析。
    if (waitAfterRun) {
      // GUI 宿主直接起 cmd.exe /k 时子进程常无独立控制台会话；经 start 可新建可见窗口。
      Process.run(
        'cmd.exe',
        ['/c', 'start', '', 'cmd.exe', '/k', chained],
        runInShell: false,
      );
      return;
    }
    Process.run(
      'cmd.exe',
      ['/c', chained],
      runInShell: false,
    );
    return;
  }
  if (waitAfterRun) {
    _runUnixTerminalKeepOpen(chained);
    return;
  }
  Process.run('/bin/sh', ['-c', chained], runInShell: false);
}

class _QuickCommandsItemInteractor implements CardItemInteractor {
  _QuickCommandsItemInteractor(this.card);
  final QuickCommandsCard card;

  @override
  void onItemTap(CardItem item) {
    if (!item.isUserEntry) return;
    final cmd = parseQuickCommandText(item.data);
    if (cmd != null && cmd.isNotEmpty) {
      runQuickCommand(
        cmd,
        waitAfterRun: parseQuickCommandWaitAfterRun(item.data),
      );
    }
  }

  @override
  void onItemEdit(BuildContext context, CardItem item) {
    if (!item.isUserEntry) return;
    Navigator.of(context)
        .push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CardItemFormPage(
          cardIndex: 2,
          gradient: card.gradient,
          cardTitle: card.name,
          userCardStore: card.userStore,
          editingItem: item,
        ),
      ),
    )
        .then((saved) {
      if (saved == true) card.onUserDataChanged?.call();
    });
  }

  @override
  void onItemDelete(BuildContext context, CardItem item) async {
    if (!item.isUserEntry) return;
    final cmd = parseQuickCommandText(item.data);
    if (cmd == null || cmd.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: const Text('确定删除该快捷命令？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await card.userStore.removeCommand(cmd);
      card.onUserDataChanged?.call();
    }
  }
}

class QuickCommandsCard extends BaseCard {
  final UserCardStore userStore;

  QuickCommandsCard({
    required this.userStore,
    super.onUserDataChanged,
  });

  @override
  CardItemInteractor get itemInteractor => _itemInteractor;
  late final _QuickCommandsItemInteractor _itemInteractor =
      _QuickCommandsItemInteractor(this);

  @override
  String get name => '快捷指令';

  @override
  IconData get icon => Icons.flash_on;

  @override
  List<Color> get gradient => const [Color(0xFF9B7FB5), Color(0xFF7A5F95)];

  @override
  Future<List<CardItem>> scan() async {
    return userStore.loadCommandCardItems();
  }

  @override
  Future<List<CardItem>> search(String keywords) async {
    final all = await loadSearchItemPool();
    return HybridSearch.sortCardItems(keywords, all);
  }
}
