import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'services/app_settings.dart';
import 'pages/settings_page.dart';
import 'cards/base_card.dart';
import 'cards/quick_apps.dart';
import 'cards/web_quick_open.dart';
import 'cards/quick_commands.dart';
import 'cards/quick_notes.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();

  final appSettings = AppSettings();
  await appSettings.load();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 400),
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    center: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  });

  runApp(QuickBoxApp(appSettings: appSettings));
}

class QuickBoxApp extends StatelessWidget {
  final AppSettings appSettings;

  const QuickBoxApp({super.key, required this.appSettings});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Quick Box',
          debugShowCheckedModeBanner: false,
          themeMode: appSettings.themeMode,
          theme: ThemeData(
            colorSchemeSeed: Colors.blue,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.blue,
            brightness: Brightness.dark,
          ),
          home: QuickBox(appSettings: appSettings),
        );
      },
    );
  }
}

class QuickBox extends StatefulWidget {
  final AppSettings appSettings;

  const QuickBox({super.key, required this.appSettings});

  @override
  State<StatefulWidget> createState() => _QuickBox();
}

class _QuickBox extends State<QuickBox> with TrayListener {
  bool _isOnSettingsPage = false;
  int _selectedCardIndex = -1;
  List<CardItem> _cardItems = [];
  bool _isLoading = false;

  final _cards = <BaseCard>[
    QuickAppsCard(),
    WebQuickOpenCard(),
    QuickCommandsCard(),
    QuickNotesCard(),
  ];

  @override
  void initState() {
    super.initState();
    trayManager.addListener(this);
    _initTray();
    _registerHotKey();
  }

  void _registerHotKey() async {
    final hotKey = widget.appSettings.hotKey;
    if (hotKey != null) {
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (_) {
          _toggleWindow();
        },
      );
    }
  }

  void _reRegisterHotKey() async {
    await hotKeyManager.unregisterAll();
    _registerHotKey();
  }

  void _toggleWindow() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
    } else {
      setState(() => _isOnSettingsPage = false);
      await windowManager.show();
      await windowManager.focus();
    }
  }

  void _initTray() async {
    await trayManager.setIcon('assets/qb.ico');
    Menu menu = Menu(
      items: [
        MenuItem(key: 'show', label: '显示'),
        MenuItem(key: 'settings', label: '设置'),
        MenuItem(key: 'exit', label: '退出'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showMain();
        break;
      case 'settings':
        _openSettings();
        break;
      case 'exit':
        windowManager.destroy();
        break;
    }
  }

  void _showMain() async {
    setState(() => _isOnSettingsPage = false);
    await windowManager.show();
    await windowManager.focus();
  }

  void _openSettings() async {
    setState(() => _isOnSettingsPage = true);
    await windowManager.show();
    await windowManager.focus();
  }

  Widget _buildCardGrid() {
    return Row(
      children: List.generate(_cards.length, (i) {
        final card = _cards[i];
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _CardWidget(
              gradient: card.gradient,
              name: card.name,
              icon: card.icon,
              onTap: () => _openCard(i),
            ),
          ),
        );
      }),
    );
  }

  void _openCard(int index) async {
    setState(() {
      _selectedCardIndex = index;
      _isLoading = true;
      _cardItems = [];
    });
    final items = await _cards[index].scan();
    setState(() {
      _cardItems = items;
      _isLoading = false;
    });
  }

  Widget _buildCardList() {
    final card = _cards[_selectedCardIndex];
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: card.gradient),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => setState(() => _selectedCardIndex = -1),
                ),
                Text(
                  card.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: card.gradient,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _cardItems.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: Colors.white12,
                      ),
                      itemBuilder: (context, i) {
                        final item = _cardItems[i];
                        return ListTile(
                          title: Text(
                            item.title,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: item.subtitle != null
                              ? Text(item.subtitle!, style: const TextStyle(color: Colors.white54))
                              : null,
                          leading: Icon(item.icon, color: Colors.white70),
                          onTap: () => card.onItemTap(item),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    hotKeyManager.unregisterAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnSettingsPage) {
      return SettingsPage(
        appSettings: widget.appSettings,
        onHotKeyChanged: _reRegisterHotKey,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // 玻璃背景
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(color: Colors.transparent.withAlpha(200)),
              ),
            ),
            // 内容
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  TextField(
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: '搜索...',
                      hintStyle: const TextStyle(color: Colors.white60),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white60,
                      ),
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: _selectedCardIndex == -1
                        ? _buildCardGrid()
                        : _buildCardList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardWidget extends StatefulWidget {
  final List<Color> gradient;
  final String name;
  final IconData icon;
  final VoidCallback onTap;

  const _CardWidget({
    required this.gradient,
    required this.name,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_CardWidget> createState() => _CardWidgetState();
}

class _CardWidgetState extends State<_CardWidget> {
  double _scale = 1.0;

  void _onTapDown(_) => setState(() => _scale = 0.93);
  void _onTapUp(_) => setState(() => _scale = 1.0);
  void _onTapCancel() => setState(() => _scale = 1.0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: Colors.white, size: 36),
              const SizedBox(height: 8),
              Text(
                widget.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
