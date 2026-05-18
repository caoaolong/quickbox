import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 底部 SnackBar，右侧带复制全文按钮。
void showCopyableSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }

  final theme = Theme.of(context);
  final fg = theme.snackBarTheme.contentTextStyle?.color ??
      theme.colorScheme.onInverseSurface;

  final screenW = MediaQuery.sizeOf(context).width;
  final snackWidth = screenW > 80 ? (screenW - 32).clamp(200.0, 1200.0) : null;
  // SnackBar：width 与 margin 不可同时非 null。
  final EdgeInsetsGeometry? snackMargin =
      snackWidth == null ? const EdgeInsets.fromLTRB(16, 0, 16, 16) : null;

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: duration,
      behavior: SnackBarBehavior.floating,
      margin: snackMargin,
      width: snackWidth,
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: fg),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '复制',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            style: IconButton.styleFrom(foregroundColor: fg),
            icon: Icon(Icons.copy_outlined, size: 22, color: fg),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
            },
          ),
        ],
      ),
    ),
  );
}
