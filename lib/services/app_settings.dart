import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

class AppSettings extends ChangeNotifier {
  static const _themeKey = 'theme_mode';
  static const _hotkeyJsonKey = 'hotkey_json';
  static const _centerHotkeyJsonKey = 'center_hotkey_json';
  static const _cardHotkeysJsonKey = 'card_hotkeys_json';
  static const _dataRootKey = 'data_root';

  /// 旧版仅保存索引子目录的完整路径，用于迁移到 data_root
  static const _indexDirLegacyKey = 'index_directory';
  static const _cloudSyncEnabledKey = 'cloud_sync_enabled';
  static const _s3EndpointKey = 's3_endpoint';
  static const _s3RegionKey = 's3_region';
  static const _s3BucketKey = 's3_bucket';
  static const _s3AccessKeyKey = 's3_access_key';
  static const _s3SecretKey = 's3_secret_key';
  static const _s3PrefixKey = 's3_prefix';
  static const _s3PathStyleKey = 's3_path_style';
  static const _cloudSyncUiModeKey = 'cloud_sync_ui_mode';

  /// 设置页「云同步」展示方式：`oss_direct` 直接填写 OSS，`oss_passcode` 仅用口令加载。
  static const cloudSyncUiModeOssDirect = 'oss_direct';
  static const cloudSyncUiModeOssPasscode = 'oss_passphrase';
  static const int cardShortcutCount = 4;

  ThemeMode _themeMode = ThemeMode.system;
  HotKey? _hotKey;
  HotKey? _centerHotKey;
  List<HotKey> _cardHotKeys = [];
  String _dataRoot = '';
  bool _cloudSyncEnabled = false;
  String _s3Endpoint = '';
  String _s3Region = '';
  String _s3Bucket = '';
  String _s3AccessKeyId = '';
  String _s3SecretAccessKey = '';
  String _s3Prefix = '';
  bool _s3PathStyle = false;
  String _cloudSyncUiMode = cloudSyncUiModeOssDirect;

  ThemeMode get themeMode => _themeMode;
  HotKey? get hotKey => _hotKey;
  HotKey? get centerHotKey => _centerHotKey;
  List<HotKey> get cardHotKeys => List.unmodifiable(_cardHotKeys);

  /// 用户数据根目录（其下含 `index` 子目录与 `user_entries.json`）
  String get dataRoot => _dataRoot;

  /// 应用索引目录，等价于 `数据根/index`
  String get indexDirectory =>
      _dataRoot.isEmpty ? '' : _joinPath(_dataRoot, 'index');

  bool get cloudSyncEnabled => _cloudSyncEnabled;
  String get s3Endpoint => _s3Endpoint;
  String get s3Region => _s3Region;
  String get s3Bucket => _s3Bucket;
  String get s3AccessKeyId => _s3AccessKeyId;
  String get s3SecretAccessKey => _s3SecretAccessKey;
  String get s3Prefix => _s3Prefix;
  bool get s3PathStyle => _s3PathStyle;

  /// 与 [cloudSyncUiModeOssDirect] / [cloudSyncUiModeOssPasscode] 对应。
  String get cloudSyncUiMode => _cloudSyncUiMode;

  /// 是否已填写启用同步所需的最小 S3 配置（不含密钥也可只读场景，此处要求 bucket+endpoint）
  bool get hasCloudSyncConfig =>
      _s3Endpoint.trim().isNotEmpty && _s3Bucket.trim().isNotEmpty;

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
    _hotKey ??= _defaultToggleHotKey();

    final centerJson = prefs.getString(_centerHotkeyJsonKey);
    if (centerJson != null) {
      try {
        _centerHotKey = HotKey.fromJson(jsonDecode(centerJson));
      } catch (_) {}
    }
    _centerHotKey ??= _defaultCenterHotKey();

    final cardJson = prefs.getString(_cardHotkeysJsonKey);
    if (cardJson != null) {
      try {
        final list = jsonDecode(cardJson) as List<dynamic>;
        if (list.length == cardShortcutCount) {
          _cardHotKeys = list
              .map(
                (e) =>
                    _asInAppHotKey(HotKey.fromJson(e as Map<String, dynamic>)),
              )
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

    final savedRoot = prefs.getString(_dataRootKey);
    if (savedRoot != null && savedRoot.trim().isNotEmpty) {
      _dataRoot = _normalizePath(savedRoot.trim());
    } else {
      final legacyIndex = prefs.getString(_indexDirLegacyKey);
      if (legacyIndex != null && legacyIndex.trim().isNotEmpty) {
        _dataRoot = _normalizePath(_parentDirectory(legacyIndex.trim()));
      } else {
        _dataRoot = _defaultDataRoot();
      }
      await prefs.setString(_dataRootKey, _dataRoot);
    }
    await _ensureDataDirs();

    _cloudSyncEnabled = prefs.getBool(_cloudSyncEnabledKey) ?? false;
    _s3Endpoint = prefs.getString(_s3EndpointKey) ?? '';
    _s3Region = prefs.getString(_s3RegionKey) ?? '';
    _s3Bucket = prefs.getString(_s3BucketKey) ?? '';
    _s3AccessKeyId = prefs.getString(_s3AccessKeyKey) ?? '';
    _s3SecretAccessKey = prefs.getString(_s3SecretKey) ?? '';
    _s3Prefix = prefs.getString(_s3PrefixKey) ?? '';
    _s3PathStyle = prefs.getBool(_s3PathStyleKey) ?? false;
    final mode = prefs.getString(_cloudSyncUiModeKey);
    _cloudSyncUiMode =
        mode == cloudSyncUiModeOssPasscode ? cloudSyncUiModeOssPasscode : cloudSyncUiModeOssDirect;

    notifyListeners();
  }

  Future<void> setCloudSyncConfig({
    required bool enabled,
    required String endpoint,
    required String region,
    required String bucket,
    required String accessKeyId,
    required String secretAccessKey,
    required String prefix,
    required bool pathStyle,
  }) async {
    _cloudSyncEnabled = enabled;
    _s3Endpoint = endpoint.trim();
    _s3Region = region.trim();
    _s3Bucket = bucket.trim();
    _s3AccessKeyId = accessKeyId.trim();
    _s3SecretAccessKey = secretAccessKey;
    _s3Prefix = prefix.trim();
    _s3PathStyle = pathStyle;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cloudSyncEnabledKey, _cloudSyncEnabled);
    await prefs.setString(_s3EndpointKey, _s3Endpoint);
    await prefs.setString(_s3RegionKey, _s3Region);
    await prefs.setString(_s3BucketKey, _s3Bucket);
    await prefs.setString(_s3AccessKeyKey, _s3AccessKeyId);
    await prefs.setString(_s3SecretKey, _s3SecretAccessKey);
    await prefs.setString(_s3PrefixKey, _s3Prefix);
    await prefs.setBool(_s3PathStyleKey, _s3PathStyle);
    notifyListeners();
  }

  Future<void> setCloudSyncUiMode(String mode) async {
    final next = mode == cloudSyncUiModeOssPasscode
        ? cloudSyncUiModeOssPasscode
        : cloudSyncUiModeOssDirect;
    if (_cloudSyncUiMode == next) {
      return;
    }
    _cloudSyncUiMode = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cloudSyncUiModeKey, _cloudSyncUiMode);
    notifyListeners();
  }

  static String _normalizePath(String p) =>
      p.replaceAll('/', Platform.pathSeparator);

  String _defaultDataRoot() {
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      return _normalizePath('$appData\\quickbox');
    }
    return _normalizePath(
      '${Platform.environment['USERPROFILE'] ?? '.'}\\.quickbox',
    );
  }

  Future<void> _ensureDataDirs() async {
    if (_dataRoot.isEmpty) return;
    await Directory(_dataRoot).create(recursive: true);
    final idx = indexDirectory;
    if (idx.isNotEmpty) {
      await Directory(idx).create(recursive: true);
    }
  }

  String _joinPath(String dir, String name) {
    var base = _normalizePath(dir);
    if (base.endsWith(Platform.pathSeparator)) {
      base = base.substring(0, base.length - Platform.pathSeparator.length);
    }
    return '$base${Platform.pathSeparator}$name';
  }

  /// 设置数据根目录；索引与用户条目 JSON 将写入其下。
  Future<void> setDataRoot(String path) async {
    final p = _normalizePath(path.trim());
    if (p.isEmpty) return;
    _dataRoot = p;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dataRootKey, _dataRoot);
    await _ensureDataDirs();
    notifyListeners();
  }

  /// 兼容旧逻辑：传入的仍是「索引目录」完整路径时，取其上级作为数据根。
  Future<void> setIndexDirectory(String indexPath) async {
    final t = _normalizePath(indexPath.trim());
    if (t.isEmpty) return;
    await setDataRoot(_parentDirectory(t));
  }

  bool get indexExists {
    if (indexDirectory.isEmpty) return false;
    return File(_joinPath(indexDirectory, 'apps.json')).existsSync();
  }

  /// 用户自定义条目（卡片新建）的 JSON 文件路径
  String get userEntriesPath {
    if (_dataRoot.isNotEmpty) {
      return _joinPath(_dataRoot, 'user_entries.json');
    }
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      return _joinPath(
        _normalizePath('$appData\\quickbox'),
        'user_entries.json',
      );
    }
    return _joinPath(
      _normalizePath(
        '${Platform.environment['USERPROFILE'] ?? '.'}\\.quickbox',
      ),
      'user_entries.json',
    );
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

  Future<void> setCenterHotKey(HotKey hotKey) async {
    _centerHotKey = hotKey;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_centerHotkeyJsonKey, jsonEncode(hotKey.toJson()));
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

  HotKey _defaultToggleHotKey() {
    if (Platform.isMacOS) {
      return HotKey(
        key: PhysicalKeyboardKey.backquote,
        modifiers: [HotKeyModifier.meta],
        scope: HotKeyScope.system,
      );
    }
    return HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );
  }

  /// 默认「窗口居中」全局快捷键。
  /// - macOS：⌘ + Q（注：会拦截系统的 ⌘+Q 退出快捷键，用户在设置页可改）
  /// - 其他平台：Ctrl + Space
  HotKey _defaultCenterHotKey() {
    if (Platform.isMacOS) {
      return HotKey(
        key: PhysicalKeyboardKey.keyQ,
        modifiers: [HotKeyModifier.meta],
        scope: HotKeyScope.system,
      );
    }
    return HotKey(
      key: PhysicalKeyboardKey.space,
      modifiers: [HotKeyModifier.control],
      scope: HotKeyScope.system,
    );
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

  String centerHotKeyLabel() {
    final hk = _centerHotKey;
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
