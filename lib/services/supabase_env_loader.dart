import 'dart:io';

/// 发布构建在 `flutter build` 时注入（与 GitHub Actions Secrets 对应），见根目录 `.env.example` 说明。
const _kSupabaseUrlFromDefine =
    String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const _kSupabaseAnonKeyFromDefine =
    String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

/// 加载 Supabase：`--dart-define` 优先；若某键仍为空，再从 `.env` 补全（忽略注释与空行）。
/// `.env` 查找顺序：当前工作目录 → 可执行文件所在目录。
abstract final class SupabaseEnvLoader {
  static String _url = '';
  static String _anonKey = '';

  static String get url => _url;

  static String get anonKey => _anonKey;

  static Future<void> load() async {
    _url = _kSupabaseUrlFromDefine.trim();
    _anonKey = _kSupabaseAnonKeyFromDefine.trim();
    try {
      final file = await _resolveDotEnvFile();
      if (file == null) {
        return;
      }
      final map = await _parseDotEnv(file);
      if (_url.isEmpty) {
        _url = map['SUPABASE_URL']?.trim() ?? '';
      }
      if (_anonKey.isEmpty) {
        _anonKey = map['SUPABASE_ANON_KEY']?.trim() ?? '';
      }
    } catch (_) {}
  }

  static Future<File?> _resolveDotEnvFile() async {
    final cwdFile =
        File('${Directory.current.path}${Platform.pathSeparator}.env');
    if (await cwdFile.exists()) {
      return cwdFile;
    }
    try {
      final exe = Platform.resolvedExecutable;
      if (exe.isEmpty) {
        return null;
      }
      final nearExe =
          File('${File(exe).parent.path}${Platform.pathSeparator}.env');
      if (await nearExe.exists()) {
        return nearExe;
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, String>> _parseDotEnv(File file) async {
    final map = <String, String>{};
    final lines = await file.readAsLines();
    for (final raw in lines) {
      var line = raw.trimRight();
      final hash = line.indexOf('#');
      if (hash >= 0) {
        line = line.substring(0, hash).trimRight();
      }
      line = line.trim();
      if (line.isEmpty) {
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      map[key] = value;
    }
    return map;
  }
}
