import 'package:hotkey_manager/hotkey_manager.dart';
import 'app_settings.dart';

class ShortcutService {
  final AppSettings appSettings;

  ShortcutService({required this.appSettings});

  void Function()? onToggleWindow;

  Future<void> init() async {
    await hotKeyManager.unregisterAll();
    _registerToggleHotKey();
  }

  void _registerToggleHotKey() async {
    final hotKey = appSettings.hotKey;
    if (hotKey == null) return;
    await hotKeyManager.register(
      hotKey,
      keyDownHandler: (_) => onToggleWindow?.call(),
    );
  }

  Future<void> reRegister() async {
    await hotKeyManager.unregisterAll();
    _registerToggleHotKey();
  }

  void dispose() {
    hotKeyManager.unregisterAll();
  }
}
