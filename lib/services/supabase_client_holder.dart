import 'package:supabase/supabase.dart';

import 'supabase_config.dart';

/// 持有 [SupabaseClient]；在未配置或未初始化时为 null。
abstract final class SupabaseClientHolder {
  static SupabaseClient? _client;

  /// 在未配置或未调用时返回 null。
  static SupabaseClient? get maybeClient => _client;

  /// 仅在 [SupabaseConfig.isConfigured] 为 true 时应调用一次。
  static void initialize() {
    if (!SupabaseConfig.isConfigured || _client != null) {
      return;
    }
    _client = SupabaseClient(SupabaseConfig.url.trim(), SupabaseConfig.anonKey.trim());
  }

  /// 仅供测试或未接入配置时卸载。
  static void resetForTesting() {
    _client = null;
  }
}
