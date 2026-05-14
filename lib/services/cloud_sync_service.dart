import 'dart:convert';
import 'dart:typed_data';

import 'package:minio/minio.dart';

import 'app_settings.dart';
import 'user_card_store.dart';

/// 使用 S3 兼容 API 同步「网页快开 / 快捷指令 / 快速笔记」JSON（不含快捷应用）。
class CloudSyncService {
  CloudSyncService({required this.appSettings});

  final AppSettings appSettings;

  static const objectFileName = 'quickbox_user_cards.json';

  /// 与 UI 一致：开启云同步且 Endpoint、Bucket、AccessKey、Secret 齐全时可执行拉取/推送。
  bool get canRunSync =>
      appSettings.cloudSyncEnabled &&
      appSettings.hasCloudSyncConfig &&
      appSettings.s3AccessKeyId.trim().isNotEmpty &&
      appSettings.s3SecretAccessKey.isNotEmpty;

  Minio _buildClient() {
    final parsed = _parseEndpoint(appSettings.s3Endpoint);
    final region = appSettings.s3Region.trim();
    return Minio(
      endPoint: parsed.host,
      port: parsed.port,
      useSSL: parsed.useSSL,
      accessKey: appSettings.s3AccessKeyId.trim(),
      secretKey: appSettings.s3SecretAccessKey,
      region: region.isEmpty ? null : region,
      pathStyle: appSettings.s3PathStyle,
    );
  }

  String _objectKey() {
    var p = appSettings.s3Prefix.trim().replaceAll(r'\', '/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    if (p.isNotEmpty && !p.endsWith('/')) {
      p = '$p/';
    }
    return '$p$objectFileName';
  }

  /// 从对象存储拉取并合并到本地（对象不存在时静默跳过）。
  Future<void> downloadAndApply(UserCardStore store) async {
    if (!canRunSync) {
      throw StateError('请先开启云同步，并填写 Endpoint、Bucket 与访问密钥');
    }
    final minio = _buildClient();
    final bucket = appSettings.s3Bucket.trim();
    final key = _objectKey();

    late final String body;
    try {
      final stream = await minio.getObject(bucket, key);
      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }
      body = utf8.decode(chunks);
    } on MinioS3Error catch (e) {
      final code = e.error?.code;
      if (code == 'NoSuchKey' ||
          code == 'NoSuchKeyError' ||
          code == 'NotFound') {
        return;
      }
      rethrow;
    }

    if (body.trim().isEmpty) return;

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('云端 JSON 根类型无效');
    }
    await store.importCloudSyncPayload(decoded);
  }

  /// 导出本地可同步片段并上传（配置未就绪时不操作）。
  Future<void> upload(UserCardStore store) async {
    if (!canRunSync) return;
    final minio = _buildClient();
    final bucket = appSettings.s3Bucket.trim();
    final key = _objectKey();
    final payload = await store.exportCloudSyncPayload();
    final bytes = utf8.encode(jsonEncode(payload));
    final u8 = Uint8List.fromList(bytes);
    await minio.putObject(
      bucket,
      key,
      Stream.value(u8),
      size: u8.length,
    );
  }
}

class _ParsedEndpoint {
  const _ParsedEndpoint({
    required this.host,
    required this.port,
    required this.useSSL,
  });
  final String host;
  final int port;
  final bool useSSL;
}

_ParsedEndpoint _parseEndpoint(String raw) {
  var s = raw.trim();
  if (s.isEmpty) {
    throw ArgumentError('Endpoint 为空');
  }
  var useSSL = true;
  final lower = s.toLowerCase();
  if (lower.startsWith('https://')) {
    s = s.substring(8);
    useSSL = true;
  } else if (lower.startsWith('http://')) {
    s = s.substring(7);
    useSSL = false;
  }
  final slash = s.indexOf('/');
  if (slash >= 0) {
    s = s.substring(0, slash);
  }

  final defaultPort = useSSL ? 443 : 80;
  var host = s;
  var port = defaultPort;

  if (host.startsWith('[')) {
    final end = host.indexOf(']');
    if (end > 0 && host.length > end + 1 && host[end + 1] == ':') {
      final portPart = host.substring(end + 2);
      final p = int.tryParse(portPart);
      if (p != null) {
        port = p;
        host = host.substring(1, end);
      }
    } else if (end > 0) {
      host = host.substring(1, end);
    }
  } else {
    final colon = host.lastIndexOf(':');
    if (colon > 0) {
      final maybePort = host.substring(colon + 1);
      final p = int.tryParse(maybePort);
      if (p != null) {
        port = p;
        host = host.substring(0, colon);
      }
    }
  }

  if (host.isEmpty) {
    throw ArgumentError('无效的 Endpoint');
  }
  return _ParsedEndpoint(host: host, port: port, useSSL: useSSL);
}
