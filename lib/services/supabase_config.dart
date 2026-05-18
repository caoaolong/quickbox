import 'supabase_env_loader.dart';

/// Supabase 连接信息优先来自构建期 `--dart-define=SUPABASE_URL` / `SUPABASE_ANON_KEY`；
/// 本地开发若未传 dart-define，可由工程根目录（或可执行文件同级）的 `.env` 补全缺项。
abstract final class SupabaseConfig {
  static String get url => SupabaseEnvLoader.url;

  static String get anonKey => SupabaseEnvLoader.anonKey;

  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty;
}
