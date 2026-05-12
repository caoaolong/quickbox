import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'cards/icon_extractor.dart';
import 'services/shortcut_service.dart';

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
  String _searchQuery = '';
  List<CardItem> _searchResults = [];
  final _searchController = TextEditingController();

  late final List<BaseCard> _cards;
  late final ShortcutService _shortcutService;

  @override
  void initState() {
    super.initState();
    _cards = [
      QuickAppsCard(indexDirectory: widget.appSettings.indexDirectory),
      WebQuickOpenCard(),
      QuickCommandsCard(),
      QuickNotesCard(),
    ];
    _searchController.addListener(_onSearchChanged);
    trayManager.addListener(this);
    _initTray();

    _shortcutService = ShortcutService(appSettings: widget.appSettings);
    _shortcutService.onToggleWindow = _toggleWindow;
    _shortcutService.init();
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

  void _reRegisterHotKey() {
    _shortcutService.reRegister();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    if (query == _searchQuery) return;
    _searchQuery = query;
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    _performSearch(query);
  }

  Future<void> _performSearch(String query) async {
    final results = await _cards[0].search(query);
    if (!mounted || _searchController.text != query) return;
    setState(() => _searchResults = results);
  }

  void _handleEsc() {
    if (_isOnSettingsPage) {
      setState(() => _isOnSettingsPage = false);
      return;
    }
    if (_searchQuery.isNotEmpty) {
      _searchController.clear();
      return;
    }
    if (_selectedCardIndex >= 0) {
      setState(() => _selectedCardIndex = -1);
      return;
    }
    windowManager.hide();
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
                      separatorBuilder: (_, i) => const Divider(
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
                          leading: _AppIcon(iconPath: item.iconPath, fallback: item.icon),
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

  Widget _buildSearchResults() {
    final query = _searchQuery.trim();
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('未找到匹配的应用', style: TextStyle(color: Colors.white54)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _searchResults.length,
      separatorBuilder: (_, i) => const Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: Colors.white12,
      ),
      itemBuilder: (context, i) {
        final item = _searchResults[i];
        return ListTile(
          title: _HighlightedText(text: item.title, query: query),
          leading: _AppIcon(iconPath: item.iconPath, fallback: item.icon),
          onTap: () => _cards[0].onItemTap(item),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    trayManager.removeListener(this);
    _shortcutService.dispose();
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

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _handleEsc();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
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
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: '搜索应用...',
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
                    child: _searchQuery.trim().isNotEmpty
                        ? _buildSearchResults()
                        : _selectedCardIndex == -1
                            ? _buildCardGrid()
                            : _buildCardList(),
                  ),
                ],
              ),
            ),
          ],
        ),
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

class _AppIcon extends StatefulWidget {
  final String? iconPath;
  final IconData fallback;

  const _AppIcon({this.iconPath, required this.fallback});

  @override
  State<_AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<_AppIcon> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_AppIcon old) {
    super.didUpdateWidget(old);
    if (old.iconPath != widget.iconPath) _load();
  }

  Future<void> _load() async {
    final path = widget.iconPath;
    if (path == null) return;
    final bytes = await extractIconBytes(path);
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          _bytes!,
          width: 24,
          height: 24,
          fit: BoxFit.contain,
        ),
      );
    }
    return Icon(widget.fallback, color: Colors.white70);
  }
}

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightedText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: const TextStyle(color: Colors.white));
    }

    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lower.indexOf(q, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold),
      ));
      start = idx + q.length;
    }

    return RichText(text: TextSpan(style: const TextStyle(color: Colors.white), children: spans));
  }
}
