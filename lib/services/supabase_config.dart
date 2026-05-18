import 'supabase_env_loader.dart';

/// Supabase 连接信息来自工程根目录（或可执行文件同级）的 `.env`。
///
/// 需在 `.env` 中配置：
/// `SUPABASE_URL=...`
/// `SUPABASE_ANON_KEY=...`
///
/// 可将 `.env.example` 复制为 `.env` 后填写。
abstract final class SupabaseConfig {
  static String get url => SupabaseEnvLoader.url;

  static String get anonKey => SupabaseEnvLoader.anonKey;

  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty;
}
