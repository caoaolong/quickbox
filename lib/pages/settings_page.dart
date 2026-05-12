import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import '../services/app_settings.dart';

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
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildThemeSection(),
            const SizedBox(height: 40),
            _buildHotKeySection(),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeSection() {
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

  Widget _buildHotKeySection() {
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
}
