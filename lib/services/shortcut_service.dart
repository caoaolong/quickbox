import 'package:hotkey_manager/hotkey_manager.dart';
import 'app_settings.dart';

class ShortcutService {
  final AppSettings appSettings;

  ShortcutService({required this.appSettings});

  void Function()? onToggleWindow;
  void Function()? onCenterWindow;
  bool Function()? shouldHandleCardShortcuts;
  void Function(int cardIndex)? onCardShortcut;

  Future<void> init() async {
    await hotKeyManager.unregisterAll();
    await _registerToggleHotKey();
    await _registerCenterHotKey();
    await _registerCardHotKeys();
  }

  Future<void> _registerToggleHotKey() async {
    final hotKey = appSettings.hotKey;
    if (hotKey == null) return;
    await hotKeyManager.register(
      hotKey,
      keyDownHandler: (_) => onToggleWindow?.call(),
    );
  }

  Future<void> _registerCenterHotKey() async {
    final hotKey = appSettings.centerHotKey;
    if (hotKey == null) return;
    await hotKeyManager.register(
      hotKey,
      keyDownHandler: (_) => onCenterWindow?.call(),
    );
  }

  Future<void> _registerCardHotKeys() async {
    for (var i = 0; i < AppSettings.cardShortcutCount; i++) {
      final hotKey = appSettings.cardHotKeyAt(i);
      final index = i;
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) {
          if (shouldHandleCardShortcuts?.call() != true) return;
          onCardShortcut?.call(index);
        },
      );
    }
  }

  Future<void> reRegister() async {
    await hotKeyManager.unregisterAll();
    await _registerToggleHotKey();
    await _registerCenterHotKey();
    await _registerCardHotKeys();
  }

  void dispose() {
    hotKeyManager.unregisterAll();
  }
}
