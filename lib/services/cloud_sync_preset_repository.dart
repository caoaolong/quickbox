import 'package:supabase/supabase.dart';

import 'supabase_client_holder.dart';

/// 口令码方案的 Supabase RPC：发布 OSS 预览配置 / 凭口令检索。
abstract final class CloudSyncPresetRepository {
  static Future<String> publishPreset(Map<String, dynamic> config) async {
    final client = SupabaseClientHolder.maybeClient;
    if (client == null) {
      throw StateError('Supabase 未初始化：请配置 .env 中的 SUPABASE_URL 与 SUPABASE_ANON_KEY 后重启应用');
    }
    try {
      final raw = await client.rpc(
        'publish_cloud_sync_preset',
        params: <String, dynamic>{'p_config': config},
      );
      final s = _asTrimmedPasscode(raw);
      if (s != null && s.isNotEmpty) {
        return s;
      }
    } on PostgrestException catch (e) {
      final msg = e.message;
      final hint =
          msg.contains('Could not find the function') || msg.contains('schema cache')
              ? '请打开 Supabase → SQL Editor，执行仓库内 supabase/migrations/202605160001_cloud_sync_preset.sql 全文；若仍报错再执行一行：NOTIFY pgrst, \'reload schema\';'
              : '';
      throw StateError(
        hint.isEmpty ? '发布失败：$msg' : '发布失败：$msg\n$hint',
      );
    }
    throw StateError('服务端未返回有效口令码');
  }

  static Future<Map<String, dynamic>?> lookupByPasscode(String passcodeRaw) async {
    final client = SupabaseClientHolder.maybeClient;
    if (client == null) {
      throw StateError('Supabase 未初始化：请配置 .env 中的 SUPABASE_URL 与 SUPABASE_ANON_KEY 后重启应用');
    }
    final pass = passcodeRaw.trim();
    if (pass.isEmpty) {
      return null;
    }
    try {
      final raw = await client.rpc(
        'lookup_cloud_sync_preset',
        params: <String, dynamic>{'p_passcode': pass},
      );
      if (raw == null) {
        return null;
      }
      if (raw is Map<String, dynamic>) {
        return raw;
      }
      if (raw is Map) {
        return Map<String, dynamic>.from(raw);
      }
    } on PostgrestException catch (e) {
      final msg = e.message;
      final hint =
          msg.contains('Could not find the function') || msg.contains('schema cache')
              ? '请确认已在 Supabase 执行 migrations SQL，必要时运行 NOTIFY pgrst, \'reload schema\';'
              : '';
      throw StateError(
        hint.isEmpty ? '查询失败：$msg' : '查询失败：$msg\n$hint',
      );
    }
    return null;
  }

  static String? _asTrimmedPasscode(dynamic raw) {
    if (raw == null) {
      return null;
    }
    if (raw is String) {
      return raw.trim();
    }
    return raw.toString().trim();
  }
}
