import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../services/app_settings.dart';
import '../services/index_service.dart';

class SettingsPage extends StatefulWidget {
  final AppSettings appSettings;
  final VoidCallback onHotKeyChanged;

  const SettingsPage({
    super.key,
    required this.appSettings,
    required this.onHotKeyChanged,
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

    return Column(
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
      ],
    );
  }

  Widget _buildDataTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '数据管理',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        const Text(
          '索引目录',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
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
                  widget.appSettings.indexDirectory.isEmpty
                      ? '未选择目录'
                      : widget.appSettings.indexDirectory,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: _pickDirectory,
                child: const Text('选择'),
              ),
            ],
          ),
        ),
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

  Future<void> _pickDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      await widget.appSettings.setIndexDirectory(result);
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
