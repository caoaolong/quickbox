import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../services/app_settings.dart';
import '../services/cloud_sync_preset_repository.dart';
import '../services/cloud_sync_service.dart';
import '../services/index_service.dart';
import '../services/github_release_update_service.dart';
import '../services/supabase_config.dart';
import '../services/user_card_store.dart';
import '../widgets/copyable_snackbar.dart';
import '../widgets/combo_hotkey_recorder.dart';

class SettingsPage extends StatefulWidget {
  final AppSettings appSettings;
  final VoidCallback onHotKeyChanged;
  final UserCardStore userCardStore;
  final VoidCallback onCloudSyncApplied;

  const SettingsPage({
    super.key,
    required this.appSettings,
    required this.onHotKeyChanged,
    required this.userCardStore,
    required this.onCloudSyncApplied,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _selectedIndex = 0;
  bool _isBuildingIndex = false;
  String _indexStatus = '';
  final GlobalKey<_CloudSyncTabState> _cloudSyncTabKey =
      GlobalKey<_CloudSyncTabState>();

  String _appVersionLabel = '…';
  bool _updateCheckBusy = false;

  @override
  void initState() {
    super.initState();
    widget.appSettings.addListener(_onSettingsChanged);
    unawaited(_loadAppVersion());
  }

  @override
  void dispose() {
    widget.appSettings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => windowManager.hide(),
        ),
        actions: [
          TextButton(
            onPressed: () => windowManager.hide(),
            child: const Text('完成'),
          ),
          if (_selectedIndex == 3)
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: '保存',
              onPressed: () =>
                  _cloudSyncTabKey.currentState?.saveCloudSyncSettings(),
            ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('常规'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.keyboard),
                label: Text('热键'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.storage),
                label: Text('数据'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.cloud_sync),
                label: Text('云同步'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.info_outline),
                label: Text('关于'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildGeneralTab();
      case 1:
        return _buildHotKeyTab();
      case 2:
        return _buildDataTab();
      case 3:
        return _CloudSyncTab(
          key: _cloudSyncTabKey,
          appSettings: widget.appSettings,
          userCardStore: widget.userCardStore,
          onCloudSyncApplied: widget.onCloudSyncApplied,
        );
      case 4:
        return _buildAboutTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildGeneralTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '主题',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('明亮'),
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('黑暗'),
              icon: Icon(Icons.dark_mode),
            ),
            ButtonSegment(
              value: ThemeMode.system,
              label: Text('跟随系统'),
              icon: Icon(Icons.settings_brightness),
            ),
          ],
          selected: {widget.appSettings.themeMode},
          onSelectionChanged: (selected) {
            widget.appSettings.setThemeMode(selected.first);
          },
        ),
      ],
    );
  }

  Widget _buildHotKeyTab() {
    final label = widget.appSettings.hotKeyLabel();
    final centerLabel = widget.appSettings.centerHotKeyLabel();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '全局快捷键',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '用于显示或隐藏主窗口',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ComboHotKeyRecorder(
            initialHotKey: widget.appSettings.hotKey,
            scope: HotKeyScope.system,
            onHotKeyRecorded: (hotKey) {
              widget.appSettings.setHotKey(hotKey);
              widget.onHotKeyChanged();
            },
          ),
          const SizedBox(height: 8),
          Text('当前快捷键: $label', style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 32),
          const Text(
            '居中窗口',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '将主窗口移回屏幕中心位置',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ComboHotKeyRecorder(
            initialHotKey: widget.appSettings.centerHotKey,
            scope: HotKeyScope.system,
            onHotKeyRecorded: (hotKey) {
              widget.appSettings.setCenterHotKey(hotKey);
              widget.onHotKeyChanged();
            },
          ),
          const SizedBox(height: 8),
          Text('当前快捷键: $centerLabel', style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 32),
          const Text(
            '卡片快捷键',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '主窗口在前台且未打开「设置」时生效，打开对应卡片列表（默认 Ctrl + 数字 1～4）',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ...List.generate(
            AppSettings.cardShortcutCount,
            _buildCardShortcutRow,
          ),
        ],
      ),
    );
  }

  static const _cardNames = ['快捷应用', '网页快开', '快捷指令', '快速笔记'];

  Widget _buildCardShortcutRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              _cardNames[index],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              widget.appSettings.cardHotKeyLabel(index),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          TextButton(
            onPressed: () => _showCardShortcutDialog(index),
            child: const Text('更改'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCardShortcutDialog(int index) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${_cardNames[index]}」快捷键'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请按下新的组合键',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ComboHotKeyRecorder(
              initialHotKey: widget.appSettings.cardHotKeyAt(index),
              scope: HotKeyScope.inapp,
              onHotKeyRecorded: (hotKey) async {
                await widget.appSettings.setCardHotKey(index, hotKey);
                widget.onHotKeyChanged();
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTab() {
    final dataRoot = widget.appSettings.dataRoot;
    final indexDir = widget.appSettings.indexDirectory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '数据管理',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          '数据存放位置',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Text(
          '应用索引与用户条目将保存在该文件夹内（含 index 子目录与 user_entries.json）。',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dataRoot.isEmpty ? '未设置' : dataRoot,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              TextButton(onPressed: _pickDataRoot, child: const Text('选择文件夹')),
            ],
          ),
        ),
        if (indexDir.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '索引目录：$indexDir',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          Text(
            '用户数据：${widget.appSettings.userEntriesPath}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isBuildingIndex ? null : _buildIndex,
            icon: _isBuildingIndex
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(widget.appSettings.indexExists ? '重建应用索引' : '创建应用索引'),
          ),
        ),
        if (_indexStatus.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _indexStatus,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  Widget _buildAboutTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '关于 Quick Box',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            '当前版本：$_appVersionLabel',
            style: const TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 10),
          Text(
            '检查更新基于 GitHub Releases。请在构建时添加 '
            '--dart-define=UPDATE_GITHUB_REPO=所有者/仓库名，'
            '或在 lib/services/update_github_repo.dart 中填写 kUpdateGithubRepoFallback。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _updateCheckBusy ? null : _onCheckForUpdates,
            icon: _updateCheckBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt),
            label: Text(_updateCheckBusy ? '检查中…' : '检查更新'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAppVersion() async {
    try {
      final p = await GitHubReleaseUpdateService.packageInfo();
      if (mounted) {
        setState(() {
          _appVersionLabel = '${p.version}（${p.buildNumber}）';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _appVersionLabel = '未知');
      }
    }
  }

  Future<void> _onCheckForUpdates() async {
    setState(() => _updateCheckBusy = true);
    try {
      final outcome = await GitHubReleaseUpdateService.checkForUpdate();
      if (!mounted) {
        return;
      }
      switch (outcome) {
        case UpdateCheckNotConfigured():
          showCopyableSnackBar(
            context,
            '未配置更新仓库：请设置 UPDATE_GITHUB_REPO 或在 update_github_repo.dart 填写仓库名',
          );
          break;
        case UpdateCheckError(:final message):
          showCopyableSnackBar(context, message);
          break;
        case UpdateCheckUpToDate():
          showCopyableSnackBar(context, '当前已是最新版本');
          break;
        case UpdateAvailable(
            :final currentVersion,
            :final remoteVersion,
            :final downloadUrl,
            :final releaseNotes,
          ):
          await _promptInstallUpdate(
            currentVersion: currentVersion,
            remoteVersion: remoteVersion,
            downloadUrl: downloadUrl,
            releaseNotes: releaseNotes,
          );
      }
    } finally {
      if (mounted) {
        setState(() => _updateCheckBusy = false);
      }
    }
  }

  Future<void> _promptInstallUpdate({
    required String currentVersion,
    required String remoteVersion,
    required String downloadUrl,
    required String releaseNotes,
  }) async {
    if (!mounted) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('发现新版本 v$remoteVersion'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('当前版本：v$currentVersion'),
                const SizedBox(height: 12),
                if (releaseNotes.isNotEmpty) ...[
                  const Text(
                    '更新说明：',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    releaseNotes,
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDownloadDialog(
        downloadUrl: downloadUrl,
        onNonWindowsFinished: Platform.isWindows
            ? null
            : () {
                if (!context.mounted) {
                  return;
                }
                showCopyableSnackBar(
                  context,
                  Platform.isMacOS
                      ? '已打开安装映像，请将应用拖入「应用程序」完成更新'
                      : '已尝试打开安装包，请按屏幕提示完成更新',
                );
              },
      ),
    );
  }

  Future<void> _pickDataRoot() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await widget.appSettings.setDataRoot(result);
    }
  }

  Future<void> _buildIndex() async {
    setState(() {
      _isBuildingIndex = true;
      _indexStatus = '正在扫描应用...';
    });

    try {
      final service = IndexService(appSettings: widget.appSettings);
      final count = await service.buildIndex();
      setState(() {
        _indexStatus = '索引完成，共扫描 $count 个应用';
      });
    } catch (e) {
      setState(() {
        _indexStatus = '索引创建失败: $e';
      });
    } finally {
      setState(() => _isBuildingIndex = false);
    }
  }
}

class _UpdateDownloadDialog extends StatefulWidget {
  const _UpdateDownloadDialog({
    required this.downloadUrl,
    this.onNonWindowsFinished,
  });

  final String downloadUrl;
  final VoidCallback? onNonWindowsFinished;

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  int _received = 0;
  int? _total;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _runDownload();
  }

  Future<void> _runDownload() async {
    try {
      await GitHubReleaseUpdateService.downloadAndApplyUpdate(
        downloadUrl: widget.downloadUrl,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _received = received;
              _total = total;
            });
          }
        },
      );
      if (!mounted) {
        return;
      }
      if (Platform.isWindows) {
        return;
      }
      Navigator.of(context).pop();
      widget.onNonWindowsFinished?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final err = _error;
    if (err != null) {
      return AlertDialog(
        title: const Text('更新失败'),
        content: SingleChildScrollView(child: Text('$err')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    }
    final t = _total;
    final progress = t != null && t > 0 ? _received / t : null;
    return AlertDialog(
      title: const Text('正在下载更新'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          Text(
            t != null && t > 0
                ? '${(_received / 1024).toStringAsFixed(1)} / ${(t / 1024).toStringAsFixed(1)} KB'
                : '正在连接…',
            style: const TextStyle(fontSize: 12),
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 12),
            Text(
              '下载完成后将自动运行安装程序并退出应用。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}

/// S3 兼容 OSS 配置与同步操作。
class _CloudSyncTab extends StatefulWidget {
  const _CloudSyncTab({
    super.key,
    required this.appSettings,
    required this.userCardStore,
    required this.onCloudSyncApplied,
  });

  final AppSettings appSettings;
  final UserCardStore userCardStore;
  final VoidCallback onCloudSyncApplied;

  @override
  State<_CloudSyncTab> createState() => _CloudSyncTabState();
}

class _CloudSyncTabState extends State<_CloudSyncTab> {
  late bool _enabled;
  late bool _pathStyle;
  late final TextEditingController _endpoint;
  late final TextEditingController _region;
  late final TextEditingController _bucket;
  late final TextEditingController _accessKey;
  late final TextEditingController _secret;
  late final TextEditingController _prefix;
  late final TextEditingController _passcode;
  bool _obscureSecret = true;
  bool _downloading = false;
  bool _publishBusy = false;
  bool _lookupBusy = false;

  @override
  void initState() {
    super.initState();
    _syncFieldsFromAppSettings();
    _endpoint = TextEditingController(text: widget.appSettings.s3Endpoint);
    _region = TextEditingController(text: widget.appSettings.s3Region);
    _bucket = TextEditingController(text: widget.appSettings.s3Bucket);
    _accessKey = TextEditingController(text: widget.appSettings.s3AccessKeyId);
    _secret = TextEditingController(text: widget.appSettings.s3SecretAccessKey);
    _prefix = TextEditingController(text: widget.appSettings.s3Prefix);
    _passcode = TextEditingController();
  }

  void _syncFieldsFromAppSettings() {
    _enabled = widget.appSettings.cloudSyncEnabled;
    _pathStyle = widget.appSettings.s3PathStyle;
  }

  void _reloadControllersFromAppSettings() {
    setState(() {
      _syncFieldsFromAppSettings();
      _endpoint.text = widget.appSettings.s3Endpoint;
      _region.text = widget.appSettings.s3Region;
      _bucket.text = widget.appSettings.s3Bucket;
      _accessKey.text = widget.appSettings.s3AccessKeyId;
      _secret.text = widget.appSettings.s3SecretAccessKey;
      _prefix.text = widget.appSettings.s3Prefix;
    });
  }

  Map<String, dynamic> _gatherOssPresetJson() {
    return <String, dynamic>{
      'endpoint': _endpoint.text.trim(),
      'region': _region.text.trim(),
      'bucket': _bucket.text.trim(),
      'accessKeyId': _accessKey.text.trim(),
      'secretAccessKey': _secret.text,
      'prefix': _prefix.text.trim(),
      'pathStyle': _pathStyle,
    };
  }

  Future<void> _testOssAndPublishToSupabase() async {
    if (!SupabaseConfig.isConfigured) {
      if (!mounted) return;
      showCopyableSnackBar(
        context,
        '未配置 Supabase：发布包需带构建期注入的 SUPABASE_URL、SUPABASE_ANON_KEY；本地开发可 `flutter run --dart-define=...` 或放置 .env',
      );
      return;
    }
    final endpoint = _endpoint.text.trim();
    final bucket = _bucket.text.trim();
    if (endpoint.isEmpty || bucket.isEmpty) {
      showCopyableSnackBar(context, '请先填写 Endpoint 与 Bucket');
      return;
    }
    if (_accessKey.text.trim().isEmpty || _secret.text.isEmpty) {
      showCopyableSnackBar(context, '请先填写 Access Key 与 Secret');
      return;
    }
    setState(() => _publishBusy = true);
    try {
      await CloudSyncService.verifyOssConnectivity(
        endpointRaw: _endpoint.text,
        regionRaw: _region.text,
        bucketRaw: _bucket.text,
        accessKeyIdRaw: _accessKey.text,
        secretAccessKeyRaw: _secret.text,
        pathStyle: _pathStyle,
      );
      final json = _gatherOssPresetJson();
      final pass = await CloudSyncPresetRepository.publishPreset(json);
      await widget.appSettings.setCloudSyncConfig(
        enabled: _enabled,
        endpoint: _endpoint.text,
        region: _region.text,
        bucket: _bucket.text,
        accessKeyId: _accessKey.text,
        secretAccessKey: _secret.text,
        prefix: _prefix.text,
        pathStyle: _pathStyle,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            title: const Text('已登记到 Supabase'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '您的口令码',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(180),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 16,
                      ),
                      child: SelectableText(
                        pass,
                        style:
                            theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                            ) ??
                            const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '请妥善保存。他人可在「云同步 → 口令码」中输入上述口令加载相同 OSS 配置。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制口令码'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: pass));
                },
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      showCopyableSnackBar(context, '操作失败：$e');
    } finally {
      if (mounted) setState(() => _publishBusy = false);
    }
  }

  Future<void> _loadByPasscode() async {
    if (!SupabaseConfig.isConfigured) {
      if (!mounted) return;
      showCopyableSnackBar(
        context,
        '未配置 Supabase：发布包需带构建期注入的 SUPABASE_URL、SUPABASE_ANON_KEY；本地开发可 `flutter run --dart-define=...` 或放置 .env',
      );
      return;
    }
    final raw = _passcode.text.trim();
    if (raw.isEmpty) {
      showCopyableSnackBar(context, '请输入口令码');
      return;
    }
    setState(() => _lookupBusy = true);
    try {
      Map<String, dynamic>? cfg;
      try {
        cfg = await CloudSyncPresetRepository.lookupByPasscode(raw);
      } catch (e) {
        if (!mounted) return;
        showCopyableSnackBar(context, '查询失败：$e');
        return;
      }
      if (cfg == null || cfg.isEmpty) {
        if (!mounted) return;
        showCopyableSnackBar(context, '请输入正确的口令码');
        return;
      }
      await widget.appSettings.setCloudSyncConfig(
        enabled: true,
        endpoint: cfg['endpoint']?.toString() ?? '',
        region: cfg['region']?.toString() ?? '',
        bucket: cfg['bucket']?.toString() ?? '',
        accessKeyId: cfg['accessKeyId']?.toString() ?? '',
        secretAccessKey: cfg['secretAccessKey']?.toString() ?? '',
        prefix: cfg['prefix']?.toString() ?? '',
        pathStyle: cfg['pathStyle'] == true || cfg['pathStyle'] == 'true',
      );
      _reloadControllersFromAppSettings();
      if (!mounted) return;
      showCopyableSnackBar(context, '已从口令码加载 OSS 配置并开启云同步');
    } finally {
      if (mounted) setState(() => _lookupBusy = false);
    }
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _region.dispose();
    _bucket.dispose();
    _accessKey.dispose();
    _secret.dispose();
    _prefix.dispose();
    _passcode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final endpoint = _endpoint.text.trim();
    final bucket = _bucket.text.trim();
    if (_enabled && (endpoint.isEmpty || bucket.isEmpty)) {
      showCopyableSnackBar(context, '开启云同步时请填写 Endpoint 与 Bucket');
      return;
    }
    await widget.appSettings.setCloudSyncConfig(
      enabled: _enabled,
      endpoint: _endpoint.text,
      region: _region.text,
      bucket: _bucket.text,
      accessKeyId: _accessKey.text,
      secretAccessKey: _secret.text,
      prefix: _prefix.text,
      pathStyle: _pathStyle,
    );
    if (!mounted) return;
    showCopyableSnackBar(context, '云同步设置已保存');
  }

  /// 供设置页 AppBar 保存按钮调用
  Future<void> saveCloudSyncSettings() => _save();

  Future<void> _downloadFromCloud() async {
    if (_downloading) return;
    final sync = CloudSyncService(appSettings: widget.appSettings);
    if (!sync.canRunSync) {
      if (!mounted) return;
      showCopyableSnackBar(context, '请先保存：开启云同步并填写 Endpoint、Bucket 与访问密钥');
      return;
    }
    setState(() => _downloading = true);
    try {
      await sync.downloadAndApply(widget.userCardStore);
      widget.onCloudSyncApplied();
      if (!mounted) return;
      showCopyableSnackBar(context, '已从云端合并到本地');
    } catch (e) {
      if (!mounted) return;
      showCopyableSnackBar(context, '下载失败：$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modeSeg = widget.appSettings.cloudSyncUiMode;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '云同步',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 12),
          if (!SupabaseConfig.isConfigured)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '提示：口令码与「测试并联用」需应用已配置 Supabase（发布包由构建注入；本地可用 .env 或 --dart-define）。',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ),
          const Text('配置方式', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            emptySelectionAllowed: false,
            segments: const [
              ButtonSegment<String>(
                value: AppSettings.cloudSyncUiModeOssDirect,
                label: Text('配置 OSS'),
                icon: Icon(Icons.cloud_outlined, size: 18),
              ),
              ButtonSegment<String>(
                value: AppSettings.cloudSyncUiModeOssPasscode,
                label: Text('口令码'),
                icon: Icon(Icons.key_outlined, size: 18),
              ),
            ],
            selected: <String>{modeSeg},
            onSelectionChanged: (Set<String> sel) async {
              final v = sel.first;
              await widget.appSettings.setCloudSyncUiMode(v);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 20),
          if (modeSeg == AppSettings.cloudSyncUiModeOssDirect) ...[
            Text(
              '填写 OSS 信息后，可先「保存」到本机；通过「测试 OSS 并联用」将校验 OSS 连通性并把配置写入 Supabase，便于他人用口令码加载。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用云同步'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _endpoint,
              decoration: const InputDecoration(
                labelText: 'Endpoint',
                hintText: '例如 https://oss-cn-hangzhou.aliyuncs.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _region,
              decoration: const InputDecoration(
                labelText: 'Region',
                hintText: '例如 oss-cn-hangzhou',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bucket,
              decoration: const InputDecoration(
                labelText: 'Bucket',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _accessKey,
              decoration: const InputDecoration(
                labelText: 'Access Key ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secret,
              obscureText: _obscureSecret,
              decoration: InputDecoration(
                labelText: 'Secret Access Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureSecret ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _obscureSecret = !_obscureSecret),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _prefix,
              decoration: const InputDecoration(
                labelText: '对象键前缀（可选）',
                hintText: '例如 quickbox/',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('路径风格（Path-Style）'),
              subtitle: Text(
                '部分自建或 MinIO 部署需要开启；公有云 OSS 一般关闭。',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              value: _pathStyle,
              onChanged: (v) => setState(() => _pathStyle = v),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _publishBusy ? null : _testOssAndPublishToSupabase,
              icon: _publishBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(_publishBusy ? '正在测试并联用…' : '测试 OSS 并联用（生成口令码）'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _downloading ? null : _downloadFromCloud,
                icon: _downloading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined),
                label: Text(_downloading ? '正在下载…' : '从云端下载（使用已保存的配置）'),
              ),
            ),
          ] else ...[
            Text(
              '向分享者索要口令码。加载成功后会写入本机的 OSS 与密钥配置，并可使用上方 AppBar「保存」或自动开启同步。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passcode,
              decoration: const InputDecoration(
                labelText: '口令码',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _loadByPasscode(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _lookupBusy ? null : _loadByPasscode,
              icon: _lookupBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.downloading_outlined),
              label: Text(_lookupBusy ? '正在查询…' : '加载口令码中的 OSS 配置'),
            ),
            const SizedBox(height: 20),
            Text(
              '当前本机 OSS 快照（口令加载后会更新；仅作确认）',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            SelectableText(
              'Bucket: ${_bucket.text.isEmpty ? "（空）" : _bucket.text}\n'
              'Endpoint: ${_endpoint.text.isEmpty ? "（空）" : _endpoint.text}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
