import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../services/app_settings.dart';
import '../services/cloud_sync_service.dart';
import '../services/index_service.dart';
import '../services/user_card_store.dart';

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

  @override
  void initState() {
    super.initState();
    widget.appSettings.addListener(_onSettingsChanged);
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
          appSettings: widget.appSettings,
          userCardStore: widget.userCardStore,
          onCloudSyncApplied: widget.onCloudSyncApplied,
        );
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
          HotKeyRecorder(
            initalHotKey: widget.appSettings.hotKey,
            onHotKeyRecorded: (hotKey) {
              widget.appSettings.setHotKey(hotKey);
              widget.onHotKeyChanged();
            },
          ),
          const SizedBox(height: 8),
          Text(
            '当前快捷键: $label',
            style: const TextStyle(fontSize: 14),
          ),
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
          HotKeyRecorder(
            initalHotKey: widget.appSettings.centerHotKey,
            onHotKeyRecorded: (hotKey) {
              widget.appSettings.setCenterHotKey(hotKey);
              widget.onHotKeyChanged();
            },
          ),
          const SizedBox(height: 8),
          Text(
            '当前快捷键: $centerLabel',
            style: const TextStyle(fontSize: 14),
          ),
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
          ...List.generate(AppSettings.cardShortcutCount, _buildCardShortcutRow),
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
            _CardHotKeyDialogCapture(
              initialHotKey: widget.appSettings.cardHotKeyAt(index),
              onRecorded: (hotKey) async {
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
              TextButton(
                onPressed: _pickDataRoot,
                child: const Text('选择文件夹'),
              ),
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
            label: Text(
              widget.appSettings.indexExists ? '重建应用索引' : '创建应用索引',
            ),
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

/// S3 兼容 OSS 配置与同步操作。
class _CloudSyncTab extends StatefulWidget {
  const _CloudSyncTab({
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
  bool _obscureSecret = true;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.appSettings.cloudSyncEnabled;
    _pathStyle = widget.appSettings.s3PathStyle;
    _endpoint = TextEditingController(text: widget.appSettings.s3Endpoint);
    _region = TextEditingController(text: widget.appSettings.s3Region);
    _bucket = TextEditingController(text: widget.appSettings.s3Bucket);
    _accessKey = TextEditingController(text: widget.appSettings.s3AccessKeyId);
    _secret = TextEditingController(text: widget.appSettings.s3SecretAccessKey);
    _prefix = TextEditingController(text: widget.appSettings.s3Prefix);
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _region.dispose();
    _bucket.dispose();
    _accessKey.dispose();
    _secret.dispose();
    _prefix.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final endpoint = _endpoint.text.trim();
    final bucket = _bucket.text.trim();
    if (_enabled && (endpoint.isEmpty || bucket.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('开启云同步时请填写 Endpoint 与 Bucket')),
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('云同步设置已保存')),
    );
  }

  Future<void> _downloadFromCloud() async {
    if (_downloading) return;
    final sync = CloudSyncService(appSettings: widget.appSettings);
    if (!sync.canRunSync) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先保存：开启云同步并填写 Endpoint、Bucket 与访问密钥'),
        ),
      );
      return;
    }
    setState(() => _downloading = true);
    try {
      await sync.downloadAndApply(widget.userCardStore);
      widget.onCloudSyncApplied();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已从云端合并到本地')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '云同步',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '兼容 Amazon S3 API 的对象存储（如阿里云 OSS、腾讯云 COS、MinIO 等）。'
            '开启并保存后：应用启动时会自动从云端合并一次；本地「网页快开、快捷指令、快速笔记」变更会在约 2 秒后自动上传；'
            '也可在下方手动从云端下载。'
            '不含「快捷应用」条目。'
            '密钥保存在本机 SharedPreferences，请注意设备安全。',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
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
                onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 仅用于「卡片快捷键」弹窗：单独注册键盘回调，避免与设置页上的 [HotKeyRecorder] 冲突。
class _CardHotKeyDialogCapture extends StatefulWidget {
  const _CardHotKeyDialogCapture({
    required this.initialHotKey,
    required this.onRecorded,
  });

  final HotKey initialHotKey;
  final Future<void> Function(HotKey hotKey) onRecorded;

  @override
  State<_CardHotKeyDialogCapture> createState() => _CardHotKeyDialogCaptureState();
}

class _CardHotKeyDialogCaptureState extends State<_CardHotKeyDialogCapture> {
  late HotKey _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialHotKey;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent keyEvent) {
    if (keyEvent is KeyUpEvent) return false;
    final physicalKeysPressed = HardwareKeyboard.instance.physicalKeysPressed;
    final key = keyEvent.physicalKey;
    List<HotKeyModifier>? modifiers = HotKeyModifier.values
        .where((e) => e.physicalKeys.any(physicalKeysPressed.contains))
        .toList();
    if (modifiers.isNotEmpty) {
      modifiers = modifiers
          .where((e) => !e.physicalKeys.contains(key))
          .toList();
    }
    final hotKey = HotKey(
      identifier: widget.initialHotKey.identifier,
      key: key,
      modifiers: modifiers,
      scope: HotKeyScope.inapp,
    );
    setState(() => _current = hotKey);
    widget.onRecorded(hotKey);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return HotKeyVirtualView(hotKey: _current);
  }
}
