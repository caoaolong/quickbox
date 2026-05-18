import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

import 'supabase_env_loader.dart';
import 'update_github_repo.dart';

/// 将 GitHub 相关的网络异常转成可读中文说明。
String _humanizeGithubNetworkError(Object e) {
  if (e is StateError) {
    final m = e.message;
    if (m.startsWith('下载失败') || m == '非法下载地址') {
      return m;
    }
  }
  final t = e.toString();
  if (e is TimeoutException ||
      t.contains('TimeoutException') ||
      t.toLowerCase().contains('timed out')) {
    return '连接 GitHub 超时，请检查网络或稍后重试。';
  }
  if (t.contains('Failed host lookup') ||
      t.contains('nodename nor servname provided') ||
      t.contains('errno = 8') ||
      (t.contains('SocketException') &&
          (t.contains('lookup') || t.contains('nodename')))) {
    return '无法访问 GitHub（域名解析失败 api.github.com）。'
        '请确认：设备已联网、DNS 正常；防火墙或公司网络是否拦截 GitHub。'
        '在中国大陆网络下 GitHub 常不稳定，可尝试更换 DNS、开启系统代理/VPN，'
        '或用浏览器访问 https://api.github.com 验证后再检查更新。';
  }
  if (t.contains('SocketException')) {
    return '网络异常，无法连接服务器：${t.contains('\n') ? t.split('\n').first : t}';
  }
  return '检查更新失败：$e';
}

/// GitHub `releases/latest` 检查结果。
sealed class UpdateCheckOutcome {
  const UpdateCheckOutcome();
}

/// 未配置 `UPDATE_GITHUB_REPO` 或未设置回退常量。
final class UpdateCheckNotConfigured extends UpdateCheckOutcome {
  const UpdateCheckNotConfigured();
}

/// 网络或 API 错误。
final class UpdateCheckError extends UpdateCheckOutcome {
  const UpdateCheckError(this.message);
  final String message;
}

/// 已是最新版本。
final class UpdateCheckUpToDate extends UpdateCheckOutcome {
  const UpdateCheckUpToDate(this.latestTagVersion);
  final String latestTagVersion;
}

/// 有新版本可安装。
final class UpdateAvailable extends UpdateCheckOutcome {
  const UpdateAvailable({
    required this.currentVersion,
    required this.remoteVersion,
    required this.downloadUrl,
    required this.releaseNotes,
  });

  final String currentVersion;
  final String remoteVersion;
  final String downloadUrl;
  final String releaseNotes;
}

abstract final class GitHubReleaseUpdateService {
  static String get _repoSlug {
    final d = kUpdateGithubRepoFromDefine.trim();
    if (d.isNotEmpty) {
      return d;
    }
    final fromDot = SupabaseEnvLoader.updateGithubRepo.trim();
    if (fromDot.isNotEmpty) {
      return fromDot;
    }
    return kUpdateGithubRepoFallback.trim();
  }

  static Future<PackageInfo> packageInfo() => PackageInfo.fromPlatform();

  static Future<UpdateCheckOutcome> checkForUpdate() async {
    final repo = _repoSlug;
    if (repo.isEmpty || !repo.contains('/')) {
      return const UpdateCheckNotConfigured();
    }

    final current = await PackageInfo.fromPlatform();
    final currentVer = _normalizeVersion(current.version);

    final uri = Uri.parse(
      'https://api.github.com/repos/$repo/releases/latest',
    );
    try {
      final res = await http
          .get(
            uri,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'QuickBox-UpdateCheck',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode == 404) {
        return const UpdateCheckError('未找到 Releases（仓库尚无发布版本）');
      }
      if (res.statusCode != 200) {
        return UpdateCheckError('GitHub API 错误：HTTP ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) {
        return const UpdateCheckError('响应格式错误');
      }
      final json = Map<String, dynamic>.from(decoded);
      final tag = json['tag_name']?.toString() ?? '';
      final remoteVer = _normalizeVersion(tag);
      if (remoteVer.isEmpty) {
        return const UpdateCheckError('无法解析发布版本标签');
      }

      final notes = json['body']?.toString() ?? '';
      final assets =
          (json['assets'] as List<dynamic>?) ?? const <dynamic>[];

      final downloadUrl = _pickDownloadAssetUrl(assets);
      if (downloadUrl == null || downloadUrl.isEmpty) {
        return const UpdateCheckError('该发布未找到与本机系统匹配的安装包（.exe / .dmg）');
      }

      if (_compareSemver(remoteVer, currentVer) <= 0) {
        return UpdateCheckUpToDate(remoteVer);
      }

      return UpdateAvailable(
        currentVersion: currentVer,
        remoteVersion: remoteVer,
        downloadUrl: downloadUrl,
        releaseNotes: notes.trim(),
      );
    } catch (e, st) {
      debugPrint('checkForUpdate: $e\n$st');
      return UpdateCheckError(_humanizeGithubNetworkError(e));
    }
  }

  /// 下载后启动安装：Windows 静默运行 Inno Setup；macOS 打开 DMG。
  static Future<void> downloadAndApplyUpdate({
    required String downloadUrl,
    required void Function(int received, int? total) onProgress,
  }) async {
    final uri = Uri.parse(downloadUrl);
    final h = uri.host.toLowerCase();
    if (!h.endsWith('github.com') && !h.endsWith('githubusercontent.com')) {
      throw StateError('非法下载地址');
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      final stream = await client.send(request);
      if (stream.statusCode != 200) {
        throw StateError('下载失败：HTTP ${stream.statusCode}');
      }

      final total = stream.contentLength;
      final ext = _installerExtension();
      final tmp = Directory.systemTemp;
      final file = File(
        '${tmp.path}/quickbox_update_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in stream.stream) {
        received += chunk.length;
        onProgress(received, total);
        sink.add(chunk);
      }
      await sink.close();

      if (Platform.isWindows) {
        await Process.start(file.path, const [
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
        ], mode: ProcessStartMode.detached);
        await windowManager.destroy();
      } else if (Platform.isMacOS) {
        await Process.run('open', [file.path]);
      } else {
        await Process.run('xdg-open', [file.path]);
      }
    } catch (e, st) {
      debugPrint('downloadAndApplyUpdate: $e\n$st');
      throw StateError(_humanizeGithubNetworkError(e));
    } finally {
      client.close();
    }
  }

  static String _installerExtension() {
    if (Platform.isWindows) {
      return '.exe';
    }
    if (Platform.isMacOS) {
      return '.dmg';
    }
    return '.bin';
  }

  static String? _pickDownloadAssetUrl(List<dynamic> assets) {
    if (Platform.isWindows) {
      String? anyExe;
      for (final a in assets) {
        if (a is! Map) {
          continue;
        }
        final m = Map<String, dynamic>.from(a);
        final name = m['name']?.toString() ?? '';
        final u = m['browser_download_url']?.toString();
        if (u == null || u.isEmpty) {
          continue;
        }
        if (!name.toLowerCase().endsWith('.exe')) {
          continue;
        }
        if (name.toLowerCase().contains('quickbox')) {
          return u;
        }
        anyExe ??= u;
      }
      return anyExe;
    }
    if (Platform.isMacOS) {
      for (final a in assets) {
        if (a is! Map) {
          continue;
        }
        final m = Map<String, dynamic>.from(a);
        final name = m['name']?.toString() ?? '';
        final u = m['browser_download_url']?.toString();
        if (u != null &&
            u.isNotEmpty &&
            name.toLowerCase().endsWith('.dmg')) {
          return u;
        }
      }
      return null;
    }
    for (final a in assets) {
      if (a is! Map) {
        continue;
      }
      final m = Map<String, dynamic>.from(a);
      final name = m['name']?.toString() ?? '';
      final u = m['browser_download_url']?.toString();
      if (u == null || u.isEmpty) {
        continue;
      }
      final n = name.toLowerCase();
      if (n.endsWith('.appimage') || n.endsWith('.deb')) {
        return u;
      }
    }
    return null;
  }

  static String _normalizeVersion(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }
    final plus = s.indexOf('+');
    if (plus >= 0) {
      s = s.substring(0, plus);
    }
    return s.trim();
  }

  /// >0 表示 a 比 b 新。
  static int _compareSemver(String a, String b) {
    final pa = a.split('.').map((e) {
      final i = int.tryParse(e.replaceAll(RegExp(r'[^\d]'), ''));
      return i ?? 0;
    }).toList();
    final pb = b.split('.').map((e) {
      final i = int.tryParse(e.replaceAll(RegExp(r'[^\d]'), ''));
      return i ?? 0;
    }).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) {
        return va.compareTo(vb);
      }
    }
    return 0;
  }
}
