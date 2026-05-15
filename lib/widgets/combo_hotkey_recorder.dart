import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

/// 强制要求「修饰键 + 普通键」组合的快捷键录制组件。
///
/// 特性：
/// - 点击进入录制状态（边框变粗变色）；
/// - 只有处于焦点状态的组件才捕获按键，多个录制框互不串扰；
/// - 单独按修饰键（Shift / Control / Option / Command）：保留等待；
/// - 单独按非修饰键：拒绝并显示提示；
/// - 修饰键 + 普通键：录制成功并回调。
///
/// 实现方式：用 [HardwareKeyboard.addHandler] 在最底层接收键盘事件，
/// 而不是 [Focus.onKeyEvent]。
/// 原因：macOS 上 `Ctrl + 非字母键`（数字 / 符号 / F 键等）的事件
/// 经常被 Cocoa 的 keyDown → doCommandBySelector 链路吞掉，
/// 等不到 Focus 系统；只有 `HardwareKeyboard` 层才能稳定收到。
/// 焦点节点仍然保留，用于「点击进入录制状态」的视觉反馈
/// 和多录制框互斥。
class ComboHotKeyRecorder extends StatefulWidget {
  const ComboHotKeyRecorder({
    super.key,
    required this.initialHotKey,
    required this.onHotKeyRecorded,
    this.scope = HotKeyScope.system,
    this.hintWhenInvalid = '请按下至少一个修饰键（如 ⌘ / ⌃ / ⌥ / ⇧）+ 一个普通键',
  });

  final HotKey? initialHotKey;
  final ValueChanged<HotKey> onHotKeyRecorded;
  final HotKeyScope scope;
  final String hintWhenInvalid;

  @override
  State<ComboHotKeyRecorder> createState() => _ComboHotKeyRecorderState();
}

class _ComboHotKeyRecorderState extends State<ComboHotKeyRecorder> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'ComboHotKeyRecorder');
  HotKey? _current;
  String? _errorHint;

  @override
  void initState() {
    super.initState();
    _current = widget.initialHotKey;
    _focusNode.addListener(_onFocusChanged);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted) return;
    setState(() {
      // 失去焦点时清除错误提示，避免遗留红字。
      if (!_focusNode.hasFocus) _errorHint = null;
    });
  }

  /// 检测某个 [HotKeyModifier] 当前是否处于按下状态。
  ///
  /// 在 macOS 上，按下 `Ctrl` 等修饰键时 `physicalKeysPressed`
  /// 不一定立刻包含 controlLeft / controlRight；Flutter 框架会
  /// 通过 `HardwareKeyboard.isXxxPressed` 暴露聚合后的状态，更稳健。
  /// 这里两种来源都查，任一命中即视为按下。
  static bool _isModifierActive(
    HotKeyModifier modifier,
    Set<PhysicalKeyboardKey> physicalKeysPressed,
  ) {
    if (modifier.physicalKeys.any(physicalKeysPressed.contains)) return true;
    final hk = HardwareKeyboard.instance;
    switch (modifier) {
      case HotKeyModifier.control:
        return hk.isControlPressed;
      case HotKeyModifier.shift:
        return hk.isShiftPressed;
      case HotKeyModifier.alt:
        return hk.isAltPressed;
      case HotKeyModifier.meta:
        return hk.isMetaPressed;
      case HotKeyModifier.capsLock:
      case HotKeyModifier.fn:
        return false;
    }
  }

  /// 仅当本录制框处于焦点时才处理事件，避免多个录制框相互串扰。
  bool _handleKeyEvent(KeyEvent keyEvent) {
    if (!mounted || !_focusNode.hasFocus) return false;

    if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
      return false;
    }

    final physicalKeysPressed = HardwareKeyboard.instance.physicalKeysPressed;
    final key = keyEvent.physicalKey;

    // 1. 当前按的键本身就是修饰键 → 仍在组合过程中，不录制不报错。
    final isCurrentKeyModifier = HotKeyModifier.values.any(
      (m) => m.physicalKeys.contains(key),
    );
    if (isCurrentKeyModifier) {
      if (_errorHint != null) {
        setState(() => _errorHint = null);
      }
      return true;
    }

    // 2. 计算除当前键之外被按下的修饰键集合（同时兼顾 macOS 行为）。
    final modifiers = HotKeyModifier.values
        .where((m) => _isModifierActive(m, physicalKeysPressed))
        .where((m) => !m.physicalKeys.contains(key))
        .toList();

    // 3. 没有任何修饰键 → 拒绝并提示。
    if (modifiers.isEmpty) {
      setState(() => _errorHint = widget.hintWhenInvalid);
      return true;
    }

    // 4. 合法组合键，录制成功。
    final hotKey = HotKey(
      identifier: widget.initialHotKey?.identifier,
      key: key,
      modifiers: modifiers,
      scope: widget.scope,
    );
    setState(() {
      _current = hotKey;
      _errorHint = null;
    });
    widget.onHotKeyRecorded(hotKey);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hotKey = _current;
    final hasFocus = _focusNode.hasFocus;

    final borderColor = hasFocus
        ? theme.colorScheme.primary
        : theme.dividerColor;
    final hintText = hasFocus ? '按下组合键…' : (hotKey == null ? '点击设置' : '点击修改');
    final hintColor = hasFocus
        ? theme.colorScheme.primary
        : theme.textTheme.bodySmall?.color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          focusNode: _focusNode,
          // 注意：这里不挂 onKeyEvent，事件统一交给 HardwareKeyboard handler。
          // Focus 仅用于焦点管理 / 视觉反馈。
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_focusNode.hasFocus) {
                _focusNode.unfocus();
              } else {
                _focusNode.requestFocus();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: hasFocus ? 2 : 1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hotKey != null) ...[
                    HotKeyVirtualView(hotKey: hotKey),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    hintText,
                    style: TextStyle(fontSize: 12, color: hintColor),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_errorHint != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorHint!,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }
}
