import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

class AppSettings extends ChangeNotifier {
  static const _themeKey = 'theme_mode';
  static const _hotkeyJsonKey = 'hotkey_json';
  static const _indexDirKey = 'index_directory';

  ThemeMode _themeMode = ThemeMode.system;
  HotKey? _hotKey;
  String _indexDirectory = '';

  ThemeMode get themeMode => _themeMode;
  HotKey? get hotKey => _hotKey;
  String get indexDirectory => _indexDirectory;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeStr = prefs.getString(_themeKey) ?? 'system';
    _themeMode = _parseThemeMode(themeStr);

    final hotkeyJson = prefs.getString(_hotkeyJsonKey);
    if (hotkeyJson != null) {
      try {
        _hotKey = HotKey.fromJson(jsonDecode(hotkeyJson));
      } catch (_) {}
    }
    _hotKey ??= HotKey(
      key: const PhysicalKeyboardKey(0x0007002C),
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );

    _indexDirectory = prefs.getString(_indexDirKey) ?? _defaultIndexDir();
    _ensureIndexDir();

    notifyListeners();
  }

  String _defaultIndexDir() {
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      return '$appData\\quickbox\\index';
    }
    return '${Platform.environment['USERPROFILE'] ?? '.'}\\.quickbox\\index';
  }

  Future<void> _ensureIndexDir() async {
    if (_indexDirectory.isEmpty) return;
    final dir = Directory(_indexDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  Future<void> setIndexDirectory(String path) async {
    _indexDirectory = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexDirKey, path);
    await _ensureIndexDir();
    notifyListeners();
  }

  bool get indexExists {
    if (_indexDirectory.isEmpty) return false;
    return File('$_indexDirectory\\apps.json').existsSync();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, _serializeThemeMode(mode));
    notifyListeners();
  }

  Future<void> setHotKey(HotKey hotKey) async {
    _hotKey = hotKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hotkeyJsonKey, jsonEncode(hotKey.toJson()));
    notifyListeners();
  }

  String hotKeyLabel() {
    final hk = _hotKey;
    if (hk == null) return '';
    final parts = <String>[];
    for (final m in hk.modifiers ?? []) {
      parts.add(_modifierToLabel(m));
    }
    final keyLabel = _keyToLabel(hk.key);
    parts.add(keyLabel);
    return parts.join(' + ');
  }

  String _modifierToLabel(HotKeyModifier m) {
    switch (m) {
      case HotKeyModifier.control:
        return 'Ctrl';
      case HotKeyModifier.alt:
        return 'Alt';
      case HotKeyModifier.shift:
        return 'Shift';
      case HotKeyModifier.meta:
        return 'Win';
      case HotKeyModifier.capsLock:
        return 'Caps';
      case HotKeyModifier.fn:
        return 'Fn';
    }
  }

  String _keyToLabel(KeyboardKey key) {
    final pk = key is PhysicalKeyboardKey ? key : null;
    final id = pk?.usbHidUsage ?? 0;
    if (id == 0x0007002C) return 'Space';
    if (id == 0x00070028) return 'Enter';
    if (id == 0x00070029) return 'Esc';
    if (id >= 0x00070004 && id <= 0x0007001D) {
      return String.fromCharCode(0x41 + id - 0x00070004);
    }
    if (id >= 0x0007001E && id <= 0x00070027) {
      return String.fromCharCode(0x30 + id - 0x0007001E);
    }
    return pk?.debugName ?? 'Key($id)';
  }

  ThemeMode _parseThemeMode(String s) {
    switch (s) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _serializeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
