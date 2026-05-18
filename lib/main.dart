import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'services/app_settings.dart';
import 'services/cloud_sync_service.dart';
import 'services/macos_helper.dart';
import 'services/user_card_store.dart';
import 'pages/settings_page.dart';
import 'pages/card_item_form_page.dart';
import 'cards/base_card.dart';
import 'cards/quick_apps.dart';
import 'cards/web_quick_open.dart';
import 'cards/quick_commands.dart';
import 'cards/quick_notes.dart';
import 'cards/icon_extractor.dart';
import 'services/hybrid_search/hybrid_search_engine.dart';
import 'services/shortcut_service.dart';
import 'services/supabase_client_holder.dart';
import 'services/supabase_env_loader.dart';

/// 不绘制滚动条，保留滚轮、触控板与拖拽滚动。
class NoScrollbarScrollBehavior extends MaterialScrollBehavior {
  const NoScrollbarScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}

/// macOS 上 Flutter 框架偶现的 `_pressedKeys.containsKey` 断言：
/// 同一个 `KeyDownEvent` 在 LSUIElement 应用 + alwaysOnTop 窗口
/// + 焦点切换 / key auto-repeat 等场景下，会被原生侧重复 dispatch，
/// 触发 [HardwareKeyboard._assertEventIsRegular] 断言失败。
///
/// 这是 Flutter 框架已知 issue（仅 debug 模式触发，release 不受影响），
/// 控制台会被刷屏，但快捷键功能本身仍可正常使用。
/// 这里仅过滤该特定断言，其他错误一律按原方式上报。
///
/// 参考：https://github.com/flutter/flutter/issues/116359
void _installMacosKeyboardAssertGuard() {
  if (!kDebugMode || !Platform.isMacOS) return;

  final original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    final isKnownKeyAssert =
        details.exception is AssertionError &&
        message.contains('KeyDownEvent is dispatched') &&
        message.contains('already pressed');
    if (isKnownKeyAssert) {
      return;
    }
    if (original != null) {
      original(details);
    } else {
      FlutterError.presentError(details);
    }
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installMacosKeyboardAssertGuard();
  await windowManager.ensureInitialized();
  await hotKeyManager.unregisterAll();

  await SupabaseEnvLoader.load();

  final appSettings = AppSettings();
  await appSettings.load();
  SupabaseClientHolder.initialize();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 400),
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    center: true,
    alwaysOnTop: true,
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
          scrollBehavior: const NoScrollbarScrollBehavior(),
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

class _SearchResult {
  final CardItem item;
  final int cardIndex;
  const _SearchResult(this.item, this.cardIndex);
}

class QuickBox extends StatefulWidget {
  final AppSettings appSettings;

  const QuickBox({super.key, required this.appSettings});

  @override
  State<StatefulWidget> createState() => _QuickBox();
}

class _QuickBox extends State<QuickBox> with TrayListener, WindowListener {
  bool _isOnSettingsPage = false;
  int _selectedCardIndex = -1;
  List<CardItem> _cardItems = [];
  bool _isLoading = false;
  int _displayedItemCount = 0;
  final _cardListScrollController = ScrollController();
  String _searchQuery = '';
  List<_SearchResult> _searchResults = [];
  int _selectedSearchIndex = -1;
  final List<GlobalKey> _searchResultKeys = [];
  List<CardItem> _localSearchResults = [];
  int _localSearchSelectedIndex = -1;
  final List<GlobalKey> _localSearchResultKeys = [];
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'search');
  Timer? _cloudUploadTimer;

  late final List<BaseCard> _cards;
  late final UserCardStore _userCardStore;
  late final ShortcutService _shortcutService;

  @override
  void initState() {
    super.initState();
    _userCardStore = UserCardStore(appSettings: widget.appSettings);
    _cards = [
      QuickAppsCard(
        indexDirectory: widget.appSettings.indexDirectory,
        userStore: _userCardStore,
        onUserDataChanged: _onUserCardDataChanged,
      ),
      WebQuickOpenCard(
        userStore: _userCardStore,
        onUserDataChanged: _onUserCardDataChanged,
      ),
      QuickCommandsCard(
        userStore: _userCardStore,
        onUserDataChanged: _onUserCardDataChanged,
      ),
      QuickNotesCard(
        userStore: _userCardStore,
        onUserDataChanged: _onUserCardDataChanged,
      ),
    ];
    _searchController.addListener(_onSearchChanged);
    _cardListScrollController.addListener(_onCardListScroll);
    trayManager.addListener(this);
    windowManager.addListener(this);
    _initTray();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);

    _shortcutService = ShortcutService(appSettings: widget.appSettings);
    _shortcutService.onToggleWindow = _toggleWindow;
    _shortcutService.onCenterWindow = _centerWindow;
    _shortcutService.shouldHandleCardShortcuts = () =>
        !_isOnSettingsPage && mounted;
    _shortcutService.onCardShortcut = (index) {
      _searchController.clear();
      _openCard(index);
    };
    _shortcutService.init();

    _userCardStore.onAfterPersist = _scheduleDebouncedCloudUpload;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupCloudDownload();
    });
  }

  void _scheduleDebouncedCloudUpload() {
    if (!widget.appSettings.cloudSyncEnabled) return;
    _cloudUploadTimer?.cancel();
    _cloudUploadTimer = Timer(const Duration(seconds: 2), () {
      _cloudUploadTimer = null;
      _uploadCloudSnapshot();
    });
  }

  Future<void> _uploadCloudSnapshot() async {
    if (!mounted) return;
    final sync = CloudSyncService(appSettings: widget.appSettings);
    if (!sync.canRunSync) return;
    try {
      await sync.upload(_userCardStore);
    } catch (e, st) {
      debugPrint('云同步上传失败: $e\n$st');
    }
  }

  Future<void> _runStartupCloudDownload() async {
    if (!mounted) return;
    final sync = CloudSyncService(appSettings: widget.appSettings);
    if (!sync.canRunSync) return;
    try {
      await sync.downloadAndApply(_userCardStore);
      if (mounted) _onUserCardDataChanged();
    } catch (e, st) {
      debugPrint('启动时云同步下载失败: $e\n$st');
    }
  }

  void _toggleWindow() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
    } else {
      setState(() => _isOnSettingsPage = false);
      await windowManager.setSize(const Size(800, 400));
      await windowManager.show();
      await windowManager.focus();
      await MacosHelper.activateApp();
      _focusSearchField();
    }
  }

  void _centerWindow() async {
    // 先确保窗口可见、被激活，再居中；否则在主窗口隐藏时按下「居中」无可见效果。
    if (!await windowManager.isVisible()) {
      await windowManager.show();
    }
    await windowManager.center();
    await windowManager.focus();
    await MacosHelper.activateApp();
  }

  void _focusSearchField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  void _onUserCardDataChanged() {
    if (!mounted) return;
    (_cards[0] as QuickAppsCard).invalidateSearchPoolCache();
    if (_selectedCardIndex >= 0) {
      _openCard(_selectedCardIndex);
    } else if (_searchQuery.trim().isNotEmpty) {
      _performSearch(_searchController.text);
    }
  }

  Widget? _userEntryDeleteOnly(
    BuildContext context,
    BaseCard card,
    CardItem item,
  ) {
    if (!item.isUserEntry) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(
            Icons.edit_outlined,
            color: Colors.white70,
            size: 22,
          ),
          tooltip: '编辑',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 40),
          onPressed: () => card.itemInteractor.onItemEdit(context, item),
        ),
        IconButton(
          icon: const Icon(
            Icons.delete_outline,
            color: Colors.white70,
            size: 22,
          ),
          tooltip: '删除',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 40),
          onPressed: () => card.itemInteractor.onItemDelete(context, item),
        ),
      ],
    );
  }

  Widget? _userEntryTrailing(
    BuildContext context,
    BaseCard card,
    CardItem item,
  ) {
    if (!item.isUserEntry) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(
            Icons.edit_outlined,
            color: Colors.white70,
            size: 22,
          ),
          tooltip: '编辑',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 40),
          onPressed: () => card.itemInteractor.onItemEdit(context, item),
        ),
        IconButton(
          icon: const Icon(
            Icons.delete_outline,
            color: Colors.white70,
            size: 22,
          ),
          tooltip: '删除',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 40),
          onPressed: () => card.itemInteractor.onItemDelete(context, item),
        ),
      ],
    );
  }

  void _reRegisterHotKey() {
    _shortcutService.reRegister();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    if (query == _searchQuery) return;
    _searchQuery = query;
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _selectedSearchIndex = -1;
        _localSearchResults = [];
        _localSearchSelectedIndex = -1;
      });
      return;
    }
    if (_selectedCardIndex < 0) {
      _performSearch(query);
    } else {
      _performLocalSearch(query);
    }
  }

  Future<void> _performLocalSearch(String query) async {
    if (_selectedCardIndex < 0) return;
    final items = await _cards[_selectedCardIndex].search(query);
    if (!mounted || _searchController.text != query) return;
    setState(() {
      _localSearchResults = items;
      _localSearchSelectedIndex = items.isEmpty ? -1 : 0;
    });
  }

  Future<void> _performSearch(String query) async {
    final results = <_SearchResult>[];

    final flat = <({CardItem item, int cardIndex})>[];
    final appPool = await _cards[0].loadSearchItemPool();
    for (final item in appPool) {
      flat.add((item: item, cardIndex: 0));
    }
    for (var i = 1; i < _cards.length; i++) {
      final items = await _cards[i].loadSearchItemPool();
      for (final item in items) {
        flat.add((item: item, cardIndex: i));
      }
    }

    final ranked = HybridSearch.rankCardEntries(query, flat);
    for (final e in ranked) {
      results.add(_SearchResult(e.item, e.cardIndex));
    }

    if (!mounted || _searchController.text != query) return;
    setState(() {
      _searchResults = results;
      _selectedSearchIndex = results.isEmpty ? -1 : 0;
    });
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (_isOnSettingsPage) return false;
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (!mounted) return false;
      // 有顶层路由（新建/编辑表单等）时交给后续处理器（如表单内 Esc 仅 pop），避免误触发主界面 _handleEsc 隐藏窗口
      if (Navigator.canPop(context)) {
        return false;
      }
      _handleEsc();
      return true;
    }
    if (_searchQuery.trim().isEmpty) return false;

    if (_selectedCardIndex < 0) {
      if (_searchResults.isEmpty) return false;
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          final n = _searchResults.length;
          _selectedSearchIndex = (_selectedSearchIndex + 1) % n;
        });
        _scrollSelectedSearchItemIntoView();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          final n = _searchResults.length;
          _selectedSearchIndex = (_selectedSearchIndex - 1 + n) % n;
        });
        _scrollSelectedSearchItemIntoView();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter &&
          _selectedSearchIndex >= 0 &&
          _selectedSearchIndex < _searchResults.length) {
        final r = _searchResults[_selectedSearchIndex];
        _cards[r.cardIndex].itemInteractor.onItemTap(r.item);
        return true;
      }
      return false;
    }

    if (_localSearchResults.isEmpty) return false;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        final n = _localSearchResults.length;
        _localSearchSelectedIndex = (_localSearchSelectedIndex + 1) % n;
      });
      _scrollSelectedLocalSearchItemIntoView();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        final n = _localSearchResults.length;
        _localSearchSelectedIndex = (_localSearchSelectedIndex - 1 + n) % n;
      });
      _scrollSelectedLocalSearchItemIntoView();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _localSearchSelectedIndex >= 0 &&
        _localSearchSelectedIndex < _localSearchResults.length) {
      final r = _localSearchResults[_localSearchSelectedIndex];
      _cards[_selectedCardIndex].itemInteractor.onItemTap(r);
      return true;
    }
    return false;
  }

  void _ensureSearchResultKeys() {
    final n = _searchResults.length;
    while (_searchResultKeys.length < n) {
      _searchResultKeys.add(GlobalKey());
    }
    if (_searchResultKeys.length > n) {
      _searchResultKeys.removeRange(n, _searchResultKeys.length);
    }
  }

  void _scrollSelectedSearchItemIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final i = _selectedSearchIndex;
      if (i < 0 || i >= _searchResultKeys.length) return;
      final ctx = _searchResultKeys[i].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _ensureLocalSearchResultKeys() {
    final n = _localSearchResults.length;
    while (_localSearchResultKeys.length < n) {
      _localSearchResultKeys.add(GlobalKey());
    }
    if (_localSearchResultKeys.length > n) {
      _localSearchResultKeys.removeRange(n, _localSearchResultKeys.length);
    }
  }

  void _scrollSelectedLocalSearchItemIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final i = _localSearchSelectedIndex;
      if (i < 0 || i >= _localSearchResultKeys.length) return;
      final ctx = _localSearchResultKeys[i].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.35,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
      }
    });
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
    await trayManager.setIcon('assets/qb.png');
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
  void onWindowFocus() {
    HardwareKeyboard.instance.syncKeyboardState();
  }

  @override
  void onWindowRestore() {
    HardwareKeyboard.instance.syncKeyboardState();
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
    await windowManager.setSize(const Size(800, 400));
    await windowManager.show();
    await windowManager.focus();
    // macOS LSUIElement 应用窗口默认拿不到键盘焦点，需要强制激活以接收键盘事件。
    await MacosHelper.activateApp();
    _focusSearchField();
  }

  void _openSettings() async {
    setState(() => _isOnSettingsPage = true);
    await windowManager.show();
    await windowManager.focus();
    // macOS 上设置页里的 HotKeyRecorder 依赖 HardwareKeyboard，
    // 必须确保进程被激活、主窗口成为 key window，否则按键事件无法到达。
    await MacosHelper.activateApp();
  }

  Widget _buildCardGrid(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
              onAddTap: () => _openNewItemForm(context, i),
            ),
          ),
        );
      }),
    );
  }

  void _onCardListScroll() {
    if (_displayedItemCount >= _cardItems.length) return;
    if (_cardListScrollController.position.pixels <
        _cardListScrollController.position.maxScrollExtent - 300) {
      return;
    }
    setState(() {
      _displayedItemCount = (_displayedItemCount + 30).clamp(
        0,
        _cardItems.length,
      );
    });
  }

  void _openCard(int index) async {
    setState(() {
      _selectedCardIndex = index;
      _isLoading = true;
      _cardItems = [];
      _displayedItemCount = 0;
    });
    _focusSearchField();
    final items = await _cards[index].scan();
    if (!mounted) return;
    setState(() {
      _cardItems = items;
      _isLoading = false;
      _displayedItemCount = 30 > items.length ? items.length : 30;
    });
    if (_searchQuery.trim().isNotEmpty) {
      await _performLocalSearch(_searchController.text);
    }
    _focusSearchField();
  }

  Future<void> _openNewItemForm(BuildContext context, int cardIndex) async {
    final card = _cards[cardIndex];
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => CardItemFormPage(
          cardIndex: cardIndex,
          gradient: card.gradient,
          cardTitle: card.name,
          userCardStore: _userCardStore,
        ),
      ),
    );
    if (saved == true && mounted) {
      _onUserCardDataChanged();
    }
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
              gradient: LinearGradient(
                colors: gradientColorsWithAlpha(card.gradient),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    final hadQuery = _searchQuery.trim().isNotEmpty;
                    setState(() => _selectedCardIndex = -1);
                    if (hadQuery) {
                      _performSearch(_searchController.text);
                    }
                  },
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
                  colors: gradientColorsWithAlpha(card.gradient),
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white54),
                    )
                  : ListView.separated(
                      controller: _cardListScrollController,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: _displayedItemCount < _cardItems.length
                          ? _displayedItemCount + 1
                          : _displayedItemCount,
                      separatorBuilder: (_, i) => const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: Colors.white12,
                      ),
                      itemBuilder: (context, i) {
                        if (i >= _cardItems.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                          );
                        }
                        final item = _cardItems[i];
                        return ListTile(
                          title: Text(
                            item.title,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: item.subtitle != null
                              ? Text(
                                  item.subtitle!,
                                  style: const TextStyle(color: Colors.white54),
                                )
                              : null,
                          leading: _AppIcon(
                            iconPath: item.iconPath,
                            iconBytes: item.iconBytes,
                            fallback: item.icon,
                          ),
                          trailing: _selectedCardIndex == 0
                              ? _userEntryTrailing(context, card, item)
                              : _userEntryDeleteOnly(context, card, item),
                          onTap: () => card.itemInteractor.onItemTap(item),
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
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text('未找到匹配项', style: TextStyle(color: Colors.white54)),
      );
    }
    _ensureSearchResultKeys();
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
        final result = _searchResults[i];
        final item = result.item;
        final card = _cards[result.cardIndex];
        final isSelected = i == _selectedSearchIndex;
        return ListTile(
          key: _searchResultKeys[i],
          selected: isSelected,
          selectedTileColor: Colors.lightBlue.withAlpha(46),
          title: Text(item.title, style: const TextStyle(color: Colors.white)),
          subtitle: item.subtitle != null
              ? Text(
                  item.subtitle!,
                  style: const TextStyle(color: Colors.white54),
                )
              : null,
          leading: _AppIcon(
            iconPath: item.iconPath,
            iconBytes: item.iconBytes,
            fallback: item.icon,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: gradientColorsWithAlpha(
                    card.gradient,
                  ).first.withAlpha(130),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  card.name,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
              if (item.isUserEntry) const SizedBox(width: 4),
              if (item.isUserEntry) _userEntryTrailing(context, card, item)!,
            ],
          ),
          onTap: () => card.itemInteractor.onItemTap(item),
        );
      },
    );
  }

  Widget _buildLocalSearchResults() {
    if (_localSearchResults.isEmpty) {
      return const Center(
        child: Text('未找到匹配项', style: TextStyle(color: Colors.white54)),
      );
    }
    _ensureLocalSearchResultKeys();
    final card = _cards[_selectedCardIndex];
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _localSearchResults.length,
      separatorBuilder: (_, i) => const Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: Colors.white12,
      ),
      itemBuilder: (context, i) {
        final item = _localSearchResults[i];
        final isSelected = i == _localSearchSelectedIndex;
        return ListTile(
          key: _localSearchResultKeys[i],
          selected: isSelected,
          selectedTileColor: Colors.lightBlue.withAlpha(46),
          title: Text(item.title, style: const TextStyle(color: Colors.white)),
          subtitle: item.subtitle != null
              ? Text(
                  item.subtitle!,
                  style: const TextStyle(color: Colors.white54),
                )
              : null,
          leading: _AppIcon(
            iconPath: item.iconPath,
            iconBytes: item.iconBytes,
            fallback: item.icon,
          ),
          trailing: _selectedCardIndex == 0
              ? _userEntryTrailing(context, card, item)
              : _userEntryDeleteOnly(context, card, item),
          onTap: () => card.itemInteractor.onItemTap(item),
        );
      },
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _cardListScrollController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    _cloudUploadTimer?.cancel();
    _shortcutService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isOnSettingsPage) {
      return SettingsPage(
        appSettings: widget.appSettings,
        onHotKeyChanged: _reRegisterHotKey,
        userCardStore: _userCardStore,
        onCloudSyncApplied: _onUserCardDataChanged,
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
            // 全窗拖拽层（translucent 不阻断子组件事件）
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                child: const SizedBox.expand(),
              ),
            ),
            // 内容
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) => windowManager.startDragging(),
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: SizedBox(height: 30),
                    ),
                  ),
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: '搜索应用、网页、指令、笔记…',
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
                        ? (_selectedCardIndex < 0
                              ? _buildSearchResults()
                              : _buildLocalSearchResults())
                        : _selectedCardIndex == -1
                        ? _buildCardGrid(context)
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
  final VoidCallback onAddTap;

  const _CardWidget({
    required this.gradient,
    required this.name,
    required this.icon,
    required this.onTap,
    required this.onAddTap,
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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColorsWithAlpha(widget.gradient),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _onTapDown,
                onTapUp: _onTapUp,
                onTapCancel: _onTapCancel,
                onTap: widget.onTap,
                child: AnimatedScale(
                  scale: _scale,
                  duration: const Duration(milliseconds: 100),
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
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              tooltip: '新建',
              onPressed: widget.onAddTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppIcon extends StatefulWidget {
  final String? iconPath;
  final Uint8List? iconBytes;
  final IconData fallback;

  const _AppIcon({this.iconPath, this.iconBytes, required this.fallback});

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
    if (old.iconPath != widget.iconPath || old.iconBytes != widget.iconBytes) {
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.iconBytes != null) {
      if (!mounted) return;
      setState(() => _bytes = widget.iconBytes);
      return;
    }
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
