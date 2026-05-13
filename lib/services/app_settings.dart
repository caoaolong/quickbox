import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

class AppSettings extends ChangeNotifier {
  static const _themeKey = 'theme_mode';
  static const _hotkeyJsonKey = 'hotkey_json';
  static const _cardHotkeysJsonKey = 'card_hotkeys_json';
  static const _indexDirKey = 'index_directory';
  static const int cardShortcutCount = 4;

  ThemeMode _themeMode = ThemeMode.system;
  HotKey? _hotKey;
  List<HotKey> _cardHotKeys = [];
  String _indexDirectory = '';

  ThemeMode get themeMode => _themeMode;
  HotKey? get hotKey => _hotKey;
  List<HotKey> get cardHotKeys => List.unmodifiable(_cardHotKeys);
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

    final cardJson = prefs.getString(_cardHotkeysJsonKey);
    if (cardJson != null) {
      try {
        final list = jsonDecode(cardJson) as List<dynamic>;
        if (list.length == cardShortcutCount) {
          _cardHotKeys = list
              .map((e) => _asInAppHotKey(HotKey.fromJson(e as Map<String, dynamic>)))
              .toList();
        } else {
          _initDefaultCardHotKeys();
        }
      } catch (_) {
        _initDefaultCardHotKeys();
      }
    } else {
      _initDefaultCardHotKeys();
    }

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

  /// 用户自定义条目（卡片新建）的 JSON 文件路径，与索引目录同属 quickbox 数据目录
  String get userEntriesPath {
    if (_indexDirectory.isNotEmpty) {
      final parent = _parentDirectory(_indexDirectory);
      return '$parent${Platform.pathSeparator}user_entries.json';
    }
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      return '$appData\\quickbox\\user_entries.json';
    }
    return '${Platform.environment['USERPROFILE'] ?? '.'}\\.quickbox\\user_entries.json';
  }

  String _parentDirectory(String path) {
    final normalized = path.replaceAll('/', Platform.pathSeparator);
    var p = normalized;
    if (p.endsWith(Platform.pathSeparator)) {
      p = p.substring(0, p.length - Platform.pathSeparator.length);
    }
    final i = p.lastIndexOf(Platform.pathSeparator);
    if (i <= 0) return p;
    return p.substring(0, i);
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

  HotKey cardHotKeyAt(int index) {
    return _cardHotKeys[index];
  }

  Future<void> setCardHotKey(int index, HotKey hotKey) async {
    if (index < 0 || index >= _cardHotKeys.length) return;
    _cardHotKeys[index] = _asInAppHotKey(hotKey);
    await _persistCardHotKeys();
    notifyListeners();
  }

  void _initDefaultCardHotKeys() {
    _cardHotKeys = List.generate(cardShortcutCount, (i) {
      final usage = 0x0007001E + i;
      return HotKey(
        key: PhysicalKeyboardKey(usage),
        modifiers: [HotKeyModifier.control],
        scope: HotKeyScope.inapp,
      );
    });
  }

  HotKey _asInAppHotKey(HotKey hk) {
    return HotKey(
      identifier: hk.identifier,
      key: hk.key,
      modifiers: hk.modifiers,
      scope: HotKeyScope.inapp,
    );
  }

  Future<void> _persistCardHotKeys() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cardHotkeysJsonKey,
      jsonEncode(_cardHotKeys.map((e) => e.toJson()).toList()),
    );
  }

  String hotKeyLabel() {
    final hk = _hotKey;
    if (hk == null) return '';
    return _formatHotKey(hk);
  }

  String cardHotKeyLabel(int index) {
    if (index < 0 || index >= _cardHotKeys.length) return '';
    return _formatHotKey(_cardHotKeys[index]);
  }

  String _formatHotKey(HotKey hk) {
    final parts = <String>[];
    for (final m in hk.modifiers ?? []) {
      parts.add(_modifierToLabel(m));
    }
    parts.add(_keyToLabel(hk.key));
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
    // USB HID：0x1E～0x26 为数字 1～9，0x27 为 0（并非连续对应 ASCII 0～9）
    if (id >= 0x0007001E && id <= 0x00070027) {
      if (id == 0x00070027) return '0';
      return String.fromCharCode(0x31 + id - 0x0007001E);
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
