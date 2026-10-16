import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import 'app_ui.dart';
import 'app_typography.dart';
import 'app_interactions.dart';
import 'archive_carousel.dart';
import 'backup_page.dart';
import 'book_collection_layout.dart';
import 'catalog.dart';
import 'glass_dock.dart';
import 'home_navigation.dart';
import 'library_state.dart';
import 'library_workspace.dart';
import 'library_reflow.dart';
import 'library_search_repository.dart';
import 'listening/controller.dart';
import 'listening/models.dart' show hasSpeechText;
import 'listening/widgets.dart';
import 'listening/custom_tts_page.dart';
import 'local_platform.dart';
import 'local_books.dart';
import 'local_library_page.dart';
import 'local_book_editor.dart';
import 'native_effects.dart' show NativeGlassGroup;
import 'network_status.dart';
import 'novel_feed_controller.dart';
import 'offline_repository.dart';
import 'offline_widgets.dart';
import 'low_performance_page.dart';
import 'reader_catalogue.dart';
import 'reader_chrome.dart';
import 'reader_appearance.dart';
import 'reader_content.dart';
import 'reader_follow_scroll.dart';
import 'reader_illustrations.dart';
import 'reader_find.dart';
import 'reader_pagination.dart';
import 'reader_paged_view.dart';
import 'reader_vertical_text.dart';
import 'reader_reflow.dart';
import 'reader_turn_motion.dart';
import 'reader_selection.dart';
import 'reader_landing_highlight.dart';
import 'reader_tools.dart';
import 'reader_preferences.dart';
import 'reading_history.dart';
import 'recent_searches.dart';
import 'ui_notifiers.dart';
import 'feature_pages.dart';
import 'wenku_features.dart';
import 'legacy_import_page.dart';
import 'legacy_transport.dart';
import 'review_pages.dart';
import 'updates/update_page.dart';
import 'updates/app_updates.dart';

export 'app_ui.dart' show sectionHeader;

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.state,
    required this.repository,
    this.network,
  });
  final LibraryState state;
  final NovelRepository repository;
  final NetworkStatus? network;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  late final _navigation = HomeNavigation(widget.state, widget.network);
  late List<int> _visibleTabs;
  final _visitedTabs = <int>{};
  bool _catalogStarted = false;
  bool _cachedShelf = false;
  static const _dockItems = [
    GlassDockItem(CupertinoIcons.house, '发现'),
    GlassDockItem(CupertinoIcons.book, '书架'),
    GlassDockItem(CupertinoIcons.folder, '本地'),
    GlassDockItem(CupertinoIcons.settings, '设置'),
  ];
  late final _catalog = NovelFeedController(
    widget.repository,
    initialItems: 60,
  );
  late final _searchFeed = NovelFeedController(widget.repository, search: true);
  LocalBookStore? get _localBooks => widget.repository is OfflineNovelRepository
      ? (widget.repository as OfflineNovelRepository).local
      : null;
  late final _shelfSearch = NovelFeedController(
    LibrarySearchRepository(
      source: widget.repository,
      state: widget.state,
      local: _localBooks,
      cachedOnly: () => _navigation.cachedShelf,
    ),
    search: true,
  );
  late final _localSearch = NovelFeedController(
    LibrarySearchRepository(
      source: widget.repository,
      state: widget.state,
      local: _localBooks,
      localOnly: true,
    ),
    search: true,
  );
  int _searchScope = 0;
  NovelFeedController get _activeSearch => switch (_searchScope) {
    1 => _shelfSearch,
    2 => _localSearch,
    _ => _searchFeed,
  };
  final _localLibrary = LocalLibraryController();
  List<Widget> _pageWidgets = const [];
  List<WidgetBuilder> _headers = const [];
  int _tab = 0;
  double _tabDirection = 1;
  int? _outgoingTab;
  bool _searchOpen = false;
  bool _searchMounted = false;
  bool _searchCovered = false;
  bool _searchFocusPending = false;
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode(
    debugLabel: 'inline-search',
    canRequestFocus: false,
  );
  bool _searchStarted = false;
  bool? _routeCurrent;
  String _lastRecordedSearch = '';
  late final AnimationController _searchExpansion =
      AnimationController(
        vsync: this,
        duration: NovelMotion.enter,
        reverseDuration: NovelMotion.exit,
      )..addStatusListener((status) {
        if (!mounted) return;
        if (status == AnimationStatus.dismissed && !_searchOpen) {
          setState(() => _searchMounted = false);
        } else if (status == AnimationStatus.completed && _searchOpen) {
          setState(() => _searchCovered = true);
          _focusOpenedSearch();
        }
      });
  late final AnimationController _pageTransition =
      AnimationController(vsync: this, duration: NovelMotion.enter, value: 1)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _outgoingTab = null);
          }
        });

  @override
  void initState() {
    super.initState();
    _visibleTabs = _navigation.tabs;
    _cachedShelf = _navigation.cachedShelf;
    _tab = _navigation.destination(_tab);
    _visitedTabs.add(_tab);
    _navigation.addListener(_navigationChanged);
    _searchText.addListener(_searchEdited);
    _searchFeed.addListener(_searchSucceeded);
    if (widget.repository case final OfflineNovelRepository offline) {
      unawaited(offline.loadCache().catchError((Object _) {}));
    }
    final discover = DiscoverPage(
      books: const [],
      feed: _catalog,
      state: widget.state,
      repository: widget.repository,
      showHeader: false,
      onSearch: _openSearch,
    );
    final shelf = ShelfPage(
      books: const [],
      state: widget.state,
      repository: widget.repository,
      showHeader: false,
      onSearch: _openSearch,
      navigation: _navigation,
    );
    final settings = SettingsPage(
      state: widget.state,
      repository: widget.repository,
      showHeader: false,
    );
    final local = widget.repository is OfflineNovelRepository
        ? (widget.repository as OfflineNovelRepository).local
        : null;
    final localPage = local == null
        ? null
        : LocalLibraryPage(
            books: local,
            state: widget.state,
            controller: _localLibrary,
            showHeader: false,
            onSearch: _openSearch,
            onOpen: (page, book) =>
                openDetail(page, book, widget.state, widget.repository),
            onOpenWithCover: (page, book, tag) => openDetail(
              page,
              book,
              widget.state,
              widget.repository,
              coverHeroTag: tag,
            ),
          );
    _headers = [
      discover.buildHeader,
      shelf.buildHeader,
      localPage?.buildHeader ??
          (_) => const ArchiveMasthead(title: '本地', code: '03 / LOCAL ARCHIVE'),
      settings.buildHeader,
    ];
    _pageWidgets =
        [
              discover,
              shelf,
              localPage ?? const Center(child: Text('当前演示数据源未启用本地书库')),
              settings,
            ]
            .map((page) => RepaintBoundary(child: Atmosphere(child: page)))
            .toList(growable: false);
    _ensureCatalog();
  }

  void _ensureCatalog() {
    if (_tab != 0 || !_visibleTabs.contains(0)) return;
    if (!_catalogStarted) {
      _catalogStarted = true;
      _catalog.loadInitial();
    } else if (_catalog.items.isEmpty && _catalog.error != null) {
      _catalog.retry();
    }
  }

  void _navigationChanged() {
    if (!mounted) return;
    final tabs = _navigation.tabs;
    final next = _navigation.destination(_tab);
    if (_searchOpen && !tabs.contains(_searchScope)) _closeSearch();
    final cacheChanged = _cachedShelf != _navigation.cachedShelf;
    setState(() {
      _visibleTabs = tabs;
      _cachedShelf = _navigation.cachedShelf;
    });
    if (next != _tab) _selectTab(next, feedback: false);
    if (cacheChanged && _searchOpen && _searchScope == 1) {
      _shelfSearch.refresh();
    }
    _ensureCatalog();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // An obscured route can pause its expansion ticker until it returns.
    // Returning must not resume an old request to open the keyboard.
    final current = ModalRoute.isCurrentOf(context);
    if (current == false) {
      _searchFocusPending = false;
    } else if (current == true &&
        _routeCurrent == false &&
        _searchOpen &&
        _searchScope != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _searchOpen &&
            _searchScope != 0 &&
            ModalRoute.isCurrentOf(context) == true) {
          _activeSearch.refresh();
        }
      });
    }
    _routeCurrent = current;
  }

  @override
  void dispose() {
    _navigation.removeListener(_navigationChanged);
    _navigation.dispose();
    _pageTransition.dispose();
    _searchExpansion.dispose();
    _searchText.dispose();
    _searchFocus.dispose();
    _catalog.dispose();
    _searchFeed.dispose();
    _shelfSearch.dispose();
    _localSearch.dispose();
    _localLibrary.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context);

  void _openSearch() {
    _searchFocus.canRequestFocus = true;
    _searchScope = _tab;
    final feed = _activeSearch;
    _searchText.value = TextEditingValue(
      text: feed.query,
      selection: TextSelection.collapsed(offset: feed.query.length),
    );
    _searchFocusPending = true;
    if (_searchScope != 0) {
      feed.refresh();
    } else if (!_searchStarted ||
        (_searchFeed.page == 0 && !_searchFeed.loading)) {
      _searchStarted = true;
      _searchFeed.loadInitial();
    }
    setState(() {
      _searchOpen = true;
      _searchMounted = true;
    });
    if (_reduceMotion) {
      _searchExpansion.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusOpenedSearch();
      });
    } else {
      _searchExpansion.forward();
    }
  }

  void _focusOpenedSearch() {
    if (!_searchFocusPending ||
        !_searchOpen ||
        _searchFocus.context == null ||
        ModalRoute.isCurrentOf(context) == false) {
      return;
    }
    _searchFocusPending = false;
    _searchFocus.requestFocus();
  }

  void _dismissSearchKeyboard() {
    _searchFocusPending = false;
    _searchFocus.unfocus();
  }

  void _closeSearch() {
    _dismissSearchKeyboard();
    _searchFocus.canRequestFocus = false;
    _activeSearch.cancelScheduledSearch();
    setState(() {
      _searchOpen = false;
      _searchCovered = false;
    });
    if (_reduceMotion) {
      _searchExpansion.value = 0;
    } else {
      _searchExpansion.reverse();
    }
  }

  void _searchEdited() {
    if (!_searchOpen) return;
    if (!_searchText.value.composing.isCollapsed) {
      _activeSearch.cancelScheduledSearch();
      return;
    }
    _activeSearch.scheduleSearch(_searchText.text);
  }

  void _searchSucceeded() {
    if (_searchScope != 0 ||
        _searchFeed.loading ||
        _searchFeed.error != null ||
        _searchFeed.page < 1) {
      return;
    }
    final query = _searchFeed.query.trim();
    if (query == _lastRecordedSearch) return;
    _lastRecordedSearch = query;
    unawaited(
      widget.state.recordSearch(query).catchError((Object _) {
        if (_lastRecordedSearch == query) _lastRecordedSearch = '';
        if (mounted) showNovelFeedback(context, '最近搜索保存失败');
      }),
    );
  }

  void _recallSearch(String query) {
    _searchText.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _searchFeed.searchFor(query);
    _dismissSearchKeyboard();
  }

  void _selectTab(int index, {bool feedback = true}) {
    if (index == _tab || !_visibleTabs.contains(index)) return;
    if (index == 2) _localLibrary.refresh?.call();
    FocusManager.instance.primaryFocus?.unfocus();
    final reduceMotion =
        widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context);
    if (feedback) HapticFeedback.selectionClick();
    setState(() {
      if (index != _tab) {
        _tabDirection = index > _tab ? 1 : -1;
        _outgoingTab = reduceMotion ? null : _tab;
        if (reduceMotion) {
          _pageTransition.value = 1;
        } else {
          _pageTransition.forward(from: 0);
        }
      }
      _tab = index;
      _visitedTabs.add(index);
    });
    _ensureCatalog();
  }

  Widget _tabPlane(int index) {
    if (!_visitedTabs.contains(index)) {
      return SizedBox.shrink(key: ValueKey('home-tab-unvisited-$index'));
    }
    final active = index == _tab;
    final outgoing = index == _outgoingTab;
    final animation = (active || outgoing) && !_reduceMotion
        ? _pageTransition
        : const AlwaysStoppedAnimation<double>(1);
    return RetainedPane(
      key: ValueKey('home-tab-$index'),
      active: !_searchCovered && (active || outgoing),
      child: ExcludeFocus(
        excluding: !active || _searchMounted,
        child: TickerMode(
          enabled: active && !_searchCovered,
          child: HeroMode(
            enabled: active && !_searchMounted,
            child: IgnorePointer(
              ignoring: !active || _searchMounted,
              child: ExcludeSemantics(
                excluding: !active || _searchMounted,
                child: ArchivePlaneTransition(
                  key: ValueKey('home-archive-plane-$index'),
                  animation: animation,
                  kind: outgoing
                      ? ArchivePlaneKind.outgoing
                      : ArchivePlaneKind.incoming,
                  direction: _tabDirection,
                  child: ArchiveMotionScope(
                    animation: animation,
                    enabled: active && !_reduceMotion,
                    child: _pageWidgets[index],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LibraryWorkspace(
    reduceMotion: widget.state.reduceMotion,
    child: PopScope<void>(
      canPop: !_searchMounted,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _searchMounted) _closeSearch();
      },
      child: Scaffold(
        body: Atmosphere(
          // Each tab/search paints its own archive diagram; the shell only
          // supplies the fallback canvas during a transition.
          archiveBackdrop: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          for (var i = 0; i < _pageWidgets.length; i++)
                            if (i != _tab && i != _outgoingTab) _tabPlane(i),
                          if (_outgoingTab case final outgoing?)
                            _tabPlane(outgoing),
                          _tabPlane(_tab),
                        ],
                      ),
                    ),
                    if (_searchMounted)
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !_searchOpen,
                          child: ArchivePlaneTransition(
                            key: const ValueKey('search-archive-plane'),
                            animation: _searchExpansion,
                            child: Atmosphere(
                              child: InlineSearchResults(
                                feed: _activeSearch,
                                state: widget.state,
                                repository: widget.repository,
                                onOpenBook: _dismissSearchKeyboard,
                                onRecall: _searchScope == 0
                                    ? _recallSearch
                                    : null,
                                emptyQueryTitle: switch (_searchScope) {
                                  1 => '书架中的书籍',
                                  2 => '本地书籍',
                                  _ => '你可能会喜欢',
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      key: const ValueKey('home-pinned-header'),
                      top: 0,
                      left: 0,
                      right: 0,
                      child: FrostedHeader(
                        child: _searchMounted
                            ? _expandedSearchHeader(context)
                            : ArchiveMotionScope(
                                animation: _pageTransition,
                                enabled: !_reduceMotion,
                                child: Row(
                                  children: [
                                    Expanded(child: _headers[_tab](context)),
                                    if (ListeningScope.maybeOf(context)
                                        case final listening?)
                                      SelectedValueBuilder<
                                        ListeningSnapshot,
                                        Novel?
                                      >(
                                        listenable: listening.snapshot,
                                        select: (session) => session.active
                                            ? session.novel
                                            : null,
                                        builder: (context, novel, _) =>
                                            novel == null
                                            ? const SizedBox.shrink()
                                            : Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 4,
                                                ),
                                                child: GlassIconButton(
                                                  key: const ValueKey(
                                                    'home-listening-entry',
                                                  ),
                                                  icon:
                                                      CupertinoIcons.headphones,
                                                  label:
                                                      '正在听书 · ${novel.title}',
                                                  onPressed: () {
                                                    // This button does not rebuild at clip boundaries;
                                                    // opening the panel still uses the live cursor.
                                                    final session = listening
                                                        .snapshot
                                                        .value;
                                                    if (session.novel == null ||
                                                        !session.active) {
                                                      return;
                                                    }
                                                    showListeningPanel(
                                                      context,
                                                      controller: listening,
                                                      novel: session.novel!,
                                                      chapter: session.chapter,
                                                      paragraph:
                                                          session
                                                              .current
                                                              ?.paragraph ??
                                                          0,
                                                      reduceMotion: widget
                                                          .state
                                                          .reduceMotion,
                                                    );
                                                  },
                                                ),
                                              ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DockUnderlay(),
              ),
              AnimatedBuilder(
                animation: _searchExpansion,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      22 + MediaQuery.paddingOf(context).left,
                      0,
                      22 + MediaQuery.paddingOf(context).right,
                      12 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: LibraryReflowPart(
                      child: GlassDock(
                        key: const ValueKey('liquid-dock'),
                        selectedIndex: _visibleTabs.indexOf(_tab),
                        reduceMotion: widget.state.reduceMotion,
                        onSelected: (slot) => _selectTab(_visibleTabs[slot]),
                        items: [
                          for (final page in _visibleTabs) _dockItems[page],
                        ],
                      ),
                    ),
                  ),
                ),
                builder: (context, child) => IgnorePointer(
                  ignoring: _searchMounted,
                  child: ExcludeSemantics(
                    excluding: _searchMounted,
                    child: Opacity(
                      opacity: 1 - _searchExpansion.value,
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _expandedSearchHeader(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => AnimatedBuilder(
      animation: _searchExpansion,
      child: _searchField(context),
      builder: (context, child) {
        final t = _searchExpansion.value;
        final expansion = NovelMotion.ease.transform(t);
        final wobble = _reduceMotion ? 0.0 : NovelMotion.jelly(t);
        final width = 46 + (constraints.maxWidth - 46) * expansion;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            ExcludeSemantics(
              child: Opacity(
                opacity: 1 - expansion,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ArchiveMasthead(
                    title: switch (_searchScope) {
                      1 => '书架',
                      2 => '本地',
                      _ => '轻小说文库',
                    },
                    code: switch (_searchScope) {
                      1 => '02 / PERSONAL ARCHIVE',
                      2 => '03 / LOCAL ARCHIVE',
                      _ => 'WENKU8 / READING ARCHIVE',
                    },
                    brand: _searchScope == 0,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Transform(
                key: const ValueKey('search-jelly-transform'),
                alignment: Alignment.centerRight,
                transform: Matrix4.diagonal3Values(
                  1 + .026 * wobble,
                  1 - .042 * wobble,
                  1,
                ),
                child: IgnorePointer(
                  ignoring: !_searchOpen || t < .4,
                  child: LiquidGlass(
                    key: const ValueKey('expanded-search-bar'),
                    radius: 24 - expansion,
                    elevated: false,
                    activation: wobble.abs() * .35,
                    touchPosition: .94,
                    child: SizedBox(
                      width: width,
                      height: 46,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24 - expansion),
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: constraints.maxWidth,
                          maxWidth: constraints.maxWidth,
                          minHeight: 46,
                          maxHeight: 46,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _searchField(BuildContext context) => Row(
    children: [
      const SizedBox(width: 46, child: Icon(CupertinoIcons.search, size: 21)),
      Expanded(
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchText,
          builder: (context, value, _) => TextField(
            key: const ValueKey('expanded-search-input'),
            controller: _searchText,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14),
            onSubmitted: (query) {
              _activeSearch.searchFor(query);
              _dismissSearchKeyboard();
            },
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: switch (_searchScope) {
                1 => '书架：书名、作者、标签',
                2 => '本地：书名、作者、标签',
                _ => '书名、作者',
              },
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      icon: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        size: 17,
                      ),
                      onPressed: _searchText.clear,
                    ),
            ),
          ),
        ),
      ),
      SizedBox(
        width: 46,
        height: 46,
        child: IconButton(
          key: const ValueKey('inline-search-close'),
          tooltip: '收起搜索',
          onPressed: _closeSearch,
          icon: const Icon(CupertinoIcons.xmark, size: 17),
        ),
      ),
    ],
  );
}

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({
    super.key,
    required this.books,
    required this.state,
    required this.repository,
    required this.onSearch,
    this.showHeader = true,
    this.feed,
    this.categoryTitle,
    this.onChooseCategory,
  });
  final List<Novel> books;
  final LibraryState state;
  final NovelRepository repository;
  final VoidCallback onSearch;
  final bool showHeader;
  final NovelFeedController? feed;
  final String? categoryTitle;
  final void Function(BuildContext context)? onChooseCategory;

  Widget buildHeader(BuildContext context) => Row(
    children: [
      Expanded(
        child: const ArchiveMasthead(
          title: '轻小说文库',
          code: 'WENKU8 / READING ARCHIVE',
          brand: true,
        ),
      ),
      if (WenkuFeaturesScope.maybeOf(context) case final features?)
        GlassIconButton(
          icon: CupertinoIcons.square_grid_2x2,
          label: '出版文库',
          onPressed: () => pushNovelPage<void>(
            context,
            PublicationLibraryPage(
              catalog: features.publications,
              account: features.account,
              repository: repository,
              state: state,
            ),
            reduceMotion: state.reduceMotion,
          ),
        ),
      GlassIconButton(
        icon: CupertinoIcons.search,
        label: '搜索',
        onPressed: onSearch,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => feed == null
      ? _buildContent(context, books)
      : ActiveListenableBuilder(
          listenable: feed!,
          builder: (context) => LoadedContentSequence(
            generation: feed!.resultRevision,
            firstIndex: feed!.resultStartIndex == 0
                ? 0
                : feed!.resultStartIndex + 2,
            child: _buildContent(context, feed!.items),
          ),
        );

  Widget _buildContent(BuildContext context, List<Novel> books) {
    final featuredCount = books.length.clamp(0, 10);
    Widget body;
    if (books.isEmpty && feed?.loading == true) {
      body = LibrarySkeleton(header: _categoryHeader(context));
    } else if (books.isEmpty && feed?.error != null) {
      body = ContentNotice(
        icon: CupertinoIcons.wifi_exclamationmark,
        title: '书籍加载失败',
        message: '检查网络后再试，已保存的书架与阅读记录仍保留。',
        onRetry: feed!.retry,
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.vertical &&
              feed?.loading == false &&
              feed?.hasMore == true &&
              feed?.error == null &&
              notification.metrics.extentAfter <
                  math.max(800, notification.metrics.viewportDimension * 1.5)) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => feed?.loadMore(),
            );
          }
          return false;
        },
        child: KeyedSubtree(
          key: ValueKey(feed?.sort),
          child: CustomScrollView(
            key: const PageStorageKey('discover'),
            clipBehavior: LibraryReflowScope.clipOf(context),
            physics: const AlwaysScrollableScrollPhysics(),
            cacheExtent: BookCollectionLayout.cacheExtentFor(
              MediaQuery.sizeOf(context).width - 48,
            ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.paddingOf(context).top +
                      FrostedHeader.toolbarHeight +
                      20,
                  24,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _categoryHeader(context),
                      const SizedBox(height: 14),
                      if (books.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 90),
                          child: Center(child: Text('暂无书籍')),
                        )
                      else ...[
                        ArchiveFileCarousel(
                          key: ValueKey(
                            'archive-files-${feed?.sort.name ?? 'recent'}-${books.first.id}',
                          ),
                          books: books
                              .take(featuredCount)
                              .toList(growable: false),
                          reduceMotion: state.reduceMotion,
                          animateEntrance: true,
                          onOpen: (book, tag) => openDetail(
                            context,
                            book,
                            state,
                            repository,
                            coverHeroTag: tag,
                          ),
                        ),
                        if (books.length > featuredCount ||
                            feed?.loading == true) ...[
                          const SizedBox(height: 32),
                          LoadedContentItem(
                            index: 2,
                            placeholder: const LoadingSkeleton(
                              layout: SkeletonLayout.actions,
                            ),
                            child: sectionHeader(context, '更多书籍', ''),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: BookCollectionSliver(
                  itemCount: books.length - featuredCount,
                  itemBuilder: (context, index) {
                    final book = books[index + featuredCount];
                    return LoadedContentItem(
                      key: ValueKey(book.id),
                      index: index + featuredCount + 2,
                      placeholder: const BookRowSkeleton(),
                      child: NovelRow(
                        novel: book,
                        coverHeroTag: CoverHeroTag(context, book.id),
                        onTap: () => openDetail(
                          context,
                          book,
                          state,
                          repository,
                          coverHeroTag: CoverHeroTag(context, book.id),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 120,
                ),
                sliver: SliverToBoxAdapter(
                  child: feed == null
                      ? const SizedBox.shrink()
                      : FeedFooter(feed: feed!),
                ),
              ),
            ],
          ),
        ),
      );
      if (feed != null) {
        body = FeedRefresh(feed: feed!, child: body);
      }
    }
    return GlassHeaderLayout(
      showHeader: showHeader,
      header: buildHeader(context),
      body: body,
    );
  }

  Widget _categoryHeader(BuildContext context) => Row(
    children: [
      Expanded(
        child: sectionHeader(
          context,
          categoryTitle ?? feed?.sort.label ?? '最近更新',
          '',
        ),
      ),
      if (feed != null)
        GlassMenuAnchor(
          child: Builder(
            builder: (buttonContext) => GlassIconButton(
              icon: CupertinoIcons.line_horizontal_3_decrease,
              label: '分类与排序',
              onPressed: () => onChooseCategory != null
                  ? onChooseCategory!(buttonContext)
                  : _chooseSort(buttonContext),
            ),
          ),
        ),
    ],
  );

  Future<void> _chooseSort(BuildContext context) async {
    final selected = await showGlassMenu<NovelSort>(
      context: context,
      reduceMotion: state.reduceMotion,
      builder: (menuContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(menuContext).height * .62,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final sort in NovelSort.values)
                GlassMenuItem(
                  order: sort.index,
                  label: sort.label,
                  selected: feed!.sort == sort,
                  onPressed: () => Navigator.of(menuContext).pop(sort),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) await feed!.selectSort(selected);
  }
}

/// Pull-to-refresh keeps content/scroll position and announces a bounded static
/// skeleton strip. There is no native spinner hidden behind the glass header.
class FeedRefresh extends StatelessWidget {
  const FeedRefresh({super.key, required this.feed, required this.child});
  final NovelFeedController feed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: RefreshIndicator.noSpinner(
          onRefresh: feed.refresh,
          child: child,
        ),
      ),
      if (feed.refreshing)
        Positioned(
          top: MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight,
          left: 24,
          right: 24,
          height: 64,
          child: IgnorePointer(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: const LoadingSkeleton(
                key: ValueKey('feed-refresh-skeleton'),
                layout: SkeletonLayout.actions,
                label: '正在刷新书籍',
              ),
            ),
          ),
        ),
    ],
  );
}

class FeedFooter extends StatelessWidget {
  const FeedFooter({
    super.key,
    required this.feed,
    this.horizontalPadding = 24,
  });
  final NovelFeedController feed;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(vertical: 20, horizontal: horizontalPadding),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (feed.loading)
          const BookCollectionSkeleton(rows: 2, label: '正在加载更多书籍')
        else if (feed.error != null) ...[
          Text(
            feed.refreshFailed ? '刷新失败，已保留原列表' : '加载下一页失败',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          GlassTextButton(onPressed: feed.retry, child: const Text('重试')),
        ] else if (feed.hasMore)
          GlassTextButton(onPressed: feed.loadMore, child: const Text('加载更多'))
        else if (feed.items.isNotEmpty)
          Text(
            '已经到底了',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
      ],
    ),
  );
}

void openDetail(
  BuildContext context,
  Novel novel,
  LibraryState state,
  NovelRepository repository, {
  Object? coverHeroTag,
  bool fromCache = false,
}) {
  if (LibraryWorkspace.open(
    context,
    novel.id,
    (_) => fromCache
        ? DetailPage(
            novel: novel,
            state: state,
            repository: repository,
            fromCache: true,
          )
        : DetailLoaderPage(novel: novel, state: state, repository: repository),
  )) {
    return;
  }
  unawaited(
    pushNovelPage<void>(
      context,
      fromCache
          ? DetailPage(
              novel: novel,
              state: state,
              repository: repository,
              fromCache: true,
              coverHeroTag: coverHeroTag,
            )
          : DetailLoaderPage(
              novel: novel,
              state: state,
              repository: repository,
              coverHeroTag: coverHeroTag,
            ),
      reduceMotion: state.reduceMotion,
      paperFlight: coverHeroTag != null,
      slot: 'detail',
    ),
  );
}

void openReadingHistory(
  BuildContext context,
  LibraryState state,
  NovelRepository repository,
) => unawaited(
  pushNovelPage<void>(
    context,
    ReadingHistoryPage(
      state: state,
      repository: repository,
      onOpen: (pageContext, id, book) => openDetail(
        pageContext,
        book ??
            Novel(
              id: id,
              title: '书籍 $id',
              author: '',
              genre: '',
              summary: '',
              colors: const [Color(0xFF202020), Color(0xFF333333)],
            ),
        state,
        repository,
      ),
    ),
    reduceMotion: state.reduceMotion,
  ),
);

class NovelRow extends StatelessWidget {
  const NovelRow({
    super.key,
    required this.novel,
    required this.onTap,
    this.trailing,
    this.coverHeroTag,
  });
  final Novel novel;
  final VoidCallback onTap;
  final Widget? trailing;
  final Object? coverHeroTag;

  @override
  Widget build(BuildContext context) => JellyTapSurface(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          NovelCover(novel, width: 56, height: 76, heroTag: coverHeroTag),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ArchiveCode(ArchiveDesign.fileCode(novel.id)),
                const SizedBox(height: 4),
                Text(
                  novel.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  novel.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          trailing ?? const Icon(CupertinoIcons.chevron_right, size: 15),
        ],
      ),
    ),
  );
}

class ShelfPage extends StatefulWidget {
  const ShelfPage({
    super.key,
    required this.books,
    required this.state,
    required this.repository,
    this.showHeader = true,
    this.onSearch,
    this.navigation,
  });
  final List<Novel> books;
  final LibraryState state;
  final NovelRepository repository;
  final bool showHeader;
  final VoidCallback? onSearch;
  final HomeNavigation? navigation;

  Widget buildHeader(BuildContext context) => Row(
    children: [
      Expanded(
        child: const ArchiveMasthead(
          title: '书架',
          code: '02 / PERSONAL ARCHIVE',
        ),
      ),
      GlassIconButton(
        icon: CupertinoIcons.clock,
        label: '阅读历史',
        onPressed: () => openReadingHistory(context, state, repository),
      ),
      GlassIconButton(
        key: const ValueKey('shelf-search-entry'),
        icon: CupertinoIcons.search,
        label: '搜索书架',
        onPressed: onSearch,
      ),
    ],
  );

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

enum _ShelfSort { recentRead, recentAdded, title }

class _ShelfPageState extends State<ShelfPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _modeTransition;
  late bool _lastCacheOnly;
  final _cacheAvailability = ValueNotifier(0);
  Set<int> _availableIds = const {};
  bool _cacheLoaded = false, _cacheFailed = false;
  OfflineNovelRepository? get _offline =>
      widget.repository is OfflineNovelRepository
      ? widget.repository as OfflineNovelRepository
      : null;
  bool get _cacheOnly => widget.navigation?.cachedShelf ?? false;
  final Map<int, Future<Novel?>> _requests = {};
  String? _previewKey;
  Future<List<Novel>>? _previewRequest;
  final _query = TextEditingController();
  bool _standaloneSearch = false;
  _ShelfSort get _sort =>
      _ShelfSort.values.firstWhere((sort) => sort.name == state.shelfSort);
  LibraryState get state => widget.state;
  late final _changes = Listenable.merge([
    state,
    state.historyChanges,
    state.shelfViewChanges,
    if (widget.navigation != null) widget.navigation!,
    _cacheAvailability,
    if (_offline?.local != null) _offline!.local!,
  ]);

  @override
  void initState() {
    super.initState();
    _modeTransition = AnimationController(
      vsync: this,
      duration: NovelMotion.enter,
      value: 1,
    );
    _lastCacheOnly = _cacheOnly;
    _offline?.addListener(_offlineCacheChanged);
    widget.navigation?.addListener(_modeChanged);
  }

  void _modeChanged() {
    if (_lastCacheOnly == _cacheOnly) return;
    _lastCacheOnly = _cacheOnly;
    if (state.effectiveReduceMotion ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _modeTransition.value = 1;
    } else {
      _modeTransition.forward(from: 0);
    }
  }

  Widget _modeMotion(int index, Widget child) => AnimatedBuilder(
    animation: _modeTransition,
    child: child,
    builder: (context, child) {
      final delay = (index * .07).clamp(0.0, .24);
      final progress = Curves.easeOutCubic.transform(
        ((_modeTransition.value - delay) / (1 - delay)).clamp(0.0, 1.0),
      );
      return Transform.translate(
        offset: Offset(-8, 10) * (1 - progress),
        child: child,
      );
    },
  );

  void _offlineCacheChanged() {
    if (!_cacheOnly) return;
    final source = _offline!;
    final ids = {
      for (final book in source.cache.books)
        if (book.cachedCount > 0) book.novel.id,
    };
    final loaded = source.cache.loaded;
    final failed = source.cacheError != null;
    if (setEquals(ids, _availableIds) &&
        loaded == _cacheLoaded &&
        failed == _cacheFailed) {
      return;
    }
    _availableIds = ids;
    _cacheLoaded = loaded;
    _cacheFailed = failed;
    _cacheAvailability.value++;
  }

  @override
  void dispose() {
    widget.navigation?.removeListener(_modeChanged);
    _modeTransition.dispose();
    _offline?.removeListener(_offlineCacheChanged);
    _cacheAvailability.dispose();
    _query.dispose();
    super.dispose();
  }

  bool _matches(int id) {
    if (_cacheOnly && _offline?.availableOffline(id) != true) return false;
    final book = _known(id);
    final term = _query.text.trim().toLowerCase();
    if (term.isNotEmpty &&
        !'$id ${book?.title ?? ''} ${book?.author ?? ''}'
            .toLowerCase()
            .contains(term)) {
      return false;
    }
    final read = state.hasRead(id);
    final finished = book != null && state.finishedReading(book);
    return switch (state.shelfFilter) {
      'unread' => !read,
      'reading' => read && !finished,
      'finished' => finished,
      _ => true,
    };
  }

  Novel? _known(int id) {
    final local = _offline?.local?.book(id);
    if (local != null) return local;
    if (_cacheOnly) {
      final cached = _offline?.cache.book(id)?.novel;
      if (cached != null) return cached;
    }
    final cached = state.cachedNovel(id);
    if (cached != null) return cached;
    for (final book in widget.books) {
      if (book.id == id) return book;
    }
    return null;
  }

  Future<Novel?> _resolve(int id) async {
    final book = await widget.repository.find(id);
    if (book != null) await state.rememberNovel(book);
    return book;
  }

  Future<List<Novel>> _resolvePreview(List<int> ids) async {
    final resolved = <int, Novel>{};
    var cursor = 0;
    Future<void> next() async {
      while (cursor < ids.length) {
        final id = ids[cursor++];
        try {
          final book =
              _known(id) ?? await _requests.putIfAbsent(id, () => _resolve(id));
          if (book != null) resolved[id] = book;
        } catch (_) {
          // Failed books keep the existing retry/remove actions in the list.
        }
      }
    }

    await Future.wait(List.generate(ids.length.clamp(0, 4), (_) => next()));
    return [
      for (final id in ids)
        if (resolved[id] != null) resolved[id]!,
    ];
  }

  Widget _preview(List<int> ids) {
    Widget carousel(List<Novel> books) => ArchiveFileCarousel(
      key: ValueKey(('bookshelf-preview', state.shelfSort, state.shelfFilter)),
      books: books,
      reduceMotion: state.reduceMotion,
      animateEntrance: true,
      onOpen: (book, tag) => openDetail(
        context,
        book,
        state,
        widget.repository,
        coverHeroTag: tag,
      ),
    );
    final known = [for (final id in ids) ?_known(id)];
    final ready = known.length == ids.length;
    final key = ids.join(',');
    if (!ready && _previewKey != key) {
      _previewKey = key;
      _previewRequest = _resolvePreview(ids);
    }
    return FutureBuilder<List<Novel>>(
      // Keep the same parent for resolved and asynchronously resolved books.
      // Reparenting the carousel on a later rebuild loses its Hero identity.
      key: const ValueKey('shelf-preview-state'),
      future: ready ? null : _previewRequest,
      initialData: ready ? known : null,
      builder: (context, snapshot) {
        if (!ready && snapshot.connectionState != ConnectionState.done) {
          return const ArchiveShelfSkeleton();
        }
        final books = ready ? known : snapshot.data ?? const <Novel>[];
        if (books.isNotEmpty) return carousel(books);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Column(
            children: [
              const Text('立体书架暂未载入，下方列表仍可整理书籍。'),
              const SizedBox(height: 12),
              GlassTextButton(
                onPressed: () => setState(() {
                  for (final id in ids) {
                    if (_known(id) == null) _requests.remove(id);
                  }
                  _previewKey = null;
                }),
                child: const Text('重新载入'),
              ),
            ],
          ),
        );
      },
    );
  }

  int _compare(int a, int b) {
    final result = switch (_sort) {
      _ShelfSort.recentRead =>
        state.lastReadAt(b).compareTo(state.lastReadAt(a)),
      _ShelfSort.recentAdded => state.addedAt(b).compareTo(state.addedAt(a)),
      _ShelfSort.title => (_known(a)?.title ?? '$a').compareTo(
        _known(b)?.title ?? '$b',
      ),
    };
    if (result != 0) return result;
    final added = state.addedAt(b).compareTo(state.addedAt(a));
    return added != 0 ? added : a.compareTo(b);
  }

  @override
  Widget build(BuildContext context) => ActiveListenableBuilder(
    listenable: _changes,
    builder: (context) {
      final saved = state.shelf.where(_matches).toList()..sort(_compare);
      final cacheLoading =
          _cacheOnly &&
          _offline?.cache.loaded == false &&
          _offline?.cacheError == null;
      final showPreview = state.shelfLayout == 'shelf' && saved.isNotEmpty;
      final previewRows = showPreview ? 2 : 0;
      return GlassHeaderLayout(
        showHeader: widget.showHeader,
        header: widget.onSearch != null
            ? widget.buildHeader(context)
            : Row(
                children: [
                  const Expanded(
                    child: ArchiveMasthead(
                      title: '书架',
                      code: '02 / PERSONAL ARCHIVE',
                    ),
                  ),
                  GlassIconButton(
                    icon: CupertinoIcons.search,
                    label: '搜索书架',
                    onPressed: () =>
                        setState(() => _standaloneSearch = !_standaloneSearch),
                  ),
                ],
              ),
        body: cacheLoading
            ? LibrarySkeleton(featured: state.shelfLayout == 'shelf')
            : _cacheOnly &&
                  _offline?.cache.loaded == false &&
                  _offline?.cacheError != null
            ? ContentNotice(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: '离线书库暂未载入',
                message: '缓存目录读取失败，请重试',
                onRetry: () => _offline!.loadCache().catchError((Object _) {}),
              )
            : BookCollectionView.builder(
                key: const PageStorageKey('shelf'),
                leadingCount: saved.isEmpty ? 2 : 1 + previewRows,
                padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.paddingOf(context).top +
                      FrostedHeader.toolbarHeight +
                      20,
                  24,
                  MediaQuery.paddingOf(context).bottom + 120,
                ),
                itemCount: saved.isEmpty ? 2 : saved.length + 1 + previewRows,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_standaloneSearch)
                            CupertinoSearchTextField(
                              key: const ValueKey('shelf-search'),
                              controller: _query,
                              borderRadius: BorderRadius.circular(
                                ArchiveDesign.panelRadius,
                              ),
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              placeholder: '在书架中查找书名、作者或 ID',
                              onChanged: (_) => setState(() {}),
                            ),
                          if (_standaloneSearch) const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _cacheOnly
                                      ? '离线可读 · ${saved.length} 本'
                                      : saved.length == state.shelf.length
                                      ? '${saved.length} 本书'
                                      : '${saved.length} / ${state.shelf.length} 本书',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              GlassMenuAnchor(
                                child: Builder(
                                  builder: (buttonContext) => GlassTextButton(
                                    key: const ValueKey('shelf-filter'),
                                    onPressed: () =>
                                        _chooseFilter(buttonContext),
                                    child: Text(switch (state.shelfFilter) {
                                      'unread' => '未读',
                                      'reading' => '阅读中',
                                      'finished' => '已读完',
                                      _ => '全部',
                                    }),
                                  ),
                                ),
                              ),
                              GlassMenuAnchor(
                                child: Builder(
                                  builder: (buttonContext) => GlassIconButton(
                                    icon: CupertinoIcons
                                        .line_horizontal_3_decrease,
                                    label: '书架排序',
                                    onPressed: () => _chooseSort(buttonContext),
                                  ),
                                ),
                              ),
                              GlassMenuAnchor(
                                child: Builder(
                                  builder: (buttonContext) => GlassIconButton(
                                    key: const ValueKey('shelf-view'),
                                    icon: state.shelfLayout == 'shelf'
                                        ? CupertinoIcons.square_grid_2x2
                                        : CupertinoIcons.list_bullet,
                                    label: '书架视图',
                                    onPressed: () => _chooseView(buttonContext),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }
                  if (saved.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 90),
                      child: Column(
                        children: [
                          Icon(
                            CupertinoIcons.book,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            size: 34,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _cacheOnly
                                ? '没有可离线阅读的书'
                                : state.shelf.isEmpty
                                ? '书架还空着'
                                : '没有符合条件的书',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _cacheOnly
                                ? '已缓存正文的收藏会显示在这里，本地导入请到「本地」阅读'
                                : state.shelf.isEmpty
                                ? '在发现页收藏喜欢的书'
                                : '试试其他关键词或切回全部',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (showPreview && index == 1) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _preview(saved.take(10).toList()),
                    );
                  }
                  if (showPreview && index == 2) {
                    return const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: ArchiveSection(
                        title: '全部书籍',
                        code: 'PERSONAL / INDEX',
                      ),
                    );
                  }
                  final rowIndex = index - 1 - previewRows;
                  final id = saved[rowIndex];
                  final book = _known(id);
                  return FutureBuilder<Novel?>(
                    key: ValueKey('shelf-resolve-$id'),
                    initialData: book,
                    future: book == null
                        ? _requests.putIfAbsent(id, () => _resolve(id))
                        : _requests[id],
                    builder: (context, snapshot) {
                      final resolved = book ?? snapshot.data;
                      final pending =
                          snapshot.connectionState != ConnectionState.done;
                      return _modeMotion(
                        rowIndex,
                        LoadedContentSequence(
                          generation: resolved?.id,
                          child: resolved != null
                              ? LoadedContentItem(
                                  index: rowIndex,
                                  placeholder: const BookRowSkeleton(),
                                  child: _row(context, resolved),
                                )
                              : pending
                              ? BookRowSkeleton(label: '正在载入书籍 $id')
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(CupertinoIcons.book, size: 26),
                                      const SizedBox(width: 15),
                                      Expanded(child: Text('书籍 $id 暂未载入')),
                                      GlassTextButton(
                                        onPressed: () => setState(() {
                                          _requests[id] = _resolve(id);
                                        }),
                                        child: const Text('重试'),
                                      ),
                                      GlassMenuAnchor(
                                        child: Builder(
                                          builder: (buttonContext) =>
                                              GlassIconButton(
                                                icon: CupertinoIcons.ellipsis,
                                                label: '书籍 $id 书架操作',
                                                onPressed: () => _bookMenu(
                                                  buttonContext,
                                                  id,
                                                ),
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      );
                    },
                  );
                },
              ),
      );
    },
  );

  Widget _row(BuildContext context, Novel book) => NovelRow(
    key: ValueKey('shelf-book-${book.id}'),
    novel: book,
    coverHeroTag: CoverHeroTag(this, book.id),
    onTap: () => openDetail(
      context,
      book,
      state,
      widget.repository,
      coverHeroTag: CoverHeroTag(this, book.id),
      fromCache: _cacheOnly,
    ),
    trailing: SizedBox(
      width: 74,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassMenuAnchor(
            child: Builder(
              builder: (buttonContext) => GlassIconButton(
                icon: CupertinoIcons.ellipsis,
                label: '${book.title}书架操作',
                onPressed: () => _bookMenu(buttonContext, book.id, book: book),
              ),
            ),
          ),
          Text(
            !state.hasRead(book.id)
                ? '未读'
                : state.finishedReading(book)
                ? '已读完'
                : (book.chapters.isNotEmpty || book.chapterCount > 0)
                ? '${state.chapterForNovel(book) + 1}/${book.chapters.isNotEmpty ? book.chapters.length : book.chapterCount}'
                : '第 ${state.chapterFor(book.id) + 1} 章',
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _chooseView(BuildContext context) async {
    final layout = await showGlassMenu<String>(
      context: context,
      reduceMotion: state.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, (value, label)) in [
            ('shelf', '立体书架 + 列表'),
            ('list', '仅列表'),
          ].indexed)
            GlassMenuItem(
              order: index,
              label: label,
              selected: state.shelfLayout == value,
              onPressed: () => Navigator.pop(menu, value),
            ),
        ],
      ),
    );
    if (!mounted || layout == null) return;
    try {
      await state.setShelfView(layout: layout);
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '书架视图保存失败，请重试');
    }
  }

  Future<void> _chooseSort(BuildContext context) async {
    final sort = await showGlassMenu<_ShelfSort>(
      context: context,
      reduceMotion: state.reduceMotion,
      builder: (menuContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, label) in [
            (_ShelfSort.recentRead, '最近阅读'),
            (_ShelfSort.recentAdded, '最近加入'),
            (_ShelfSort.title, '书名'),
          ])
            GlassMenuItem(
              order: value.index,
              label: label,
              selected: value == _sort,
              onPressed: () => Navigator.of(menuContext).pop(value),
            ),
        ],
      ),
    );
    if (!mounted || sort == null) return;
    try {
      await state.setShelfView(sort: sort.name);
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '书架排序保存失败，请重试');
    }
  }

  Future<void> _chooseFilter(BuildContext context) async {
    final filter = await showGlassMenu<String>(
      context: context,
      reduceMotion: state.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, (value, label)) in [
            ('all', '全部'),
            ('unread', '未读'),
            ('reading', '阅读中'),
            ('finished', '已读完'),
          ].indexed)
            GlassMenuItem(
              order: index,
              label: label,
              selected: state.shelfFilter == value,
              onPressed: () => Navigator.pop(menu, value),
            ),
        ],
      ),
    );
    if (!mounted || filter == null) return;
    try {
      await state.setShelfView(filter: filter);
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '书架筛选保存失败，请重试');
    }
  }

  Future<void> _bookMenu(BuildContext context, int id, {Novel? book}) async {
    final remove = await showGlassMenu<bool>(
      context: context,
      reduceMotion: state.reduceMotion,
      builder: (menuContext) => GlassMenuItem(
        label: '移出书架',
        onPressed: () => Navigator.of(menuContext).pop(true),
      ),
    );
    if (!mounted || remove != true || !state.contains(id)) return;
    final addedAt = state.addedAt(id);
    try {
      await state.setShelfMembership(id, false);
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '书架操作保存失败，请重试');
      return;
    }
    final revision = state.shelfRevision(id);
    if (!mounted) return;
    showNovelFeedback(
      this.context,
      '已移出书架',
      actionLabel: '撤销',
      action: () async {
        if (!state.contains(id) && state.shelfRevision(id) == revision) {
          await state.setShelfMembership(
            id,
            true,
            novel: book,
            restoredAddedAt: addedAt,
          );
        }
      },
    );
  }
}

Future<void> openLocalLibrary(
  BuildContext context,
  LocalBookStore books,
  LibraryState state,
  NovelRepository repository,
) => pushNovelPage<void>(
  context,
  LocalLibraryPage(
    books: books,
    state: state,
    onOpen: (page, novel) => openDetail(page, novel, state, repository),
    onOpenWithCover: (page, novel, tag) =>
        openDetail(page, novel, state, repository, coverHeroTag: tag),
  ),
  reduceMotion: state.reduceMotion,
);

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.state,
    this.repository,
    this.showHeader = true,
  });
  final LibraryState state;
  final NovelRepository? repository;
  final bool showHeader;

  Widget buildHeader(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: const ArchiveMasthead(title: '设置', code: '04 / SYSTEM PROFILE'),
  );

  @override
  Widget build(BuildContext context) => ActiveListenableBuilder(
    listenable: state.settingsChanges,
    builder: (context) => GlassHeaderLayout(
      showHeader: showHeader,
      header: buildHeader(context),
      body: ListView(
        key: const PageStorageKey('settings'),
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
          24,
          MediaQuery.paddingOf(context).bottom + 120,
        ),
        children: [
          if (WenkuFeaturesScope.maybeOf(context) case final features?) ...[
            sectionHeader(context, '文库账号', ''),
            const SizedBox(height: 14),
            FeatureEntry(
              key: const ValueKey('settings-account'),
              title: '账号与云书架',
              subtitle: '登录、签到与云端收藏',
              icon: CupertinoIcons.person_crop_circle,
              onTap: repository == null
                  ? null
                  : () => pushNovelPage<void>(
                      context,
                      WenkuAccountPage(
                        account: features.account,
                        state: state,
                        repository: repository!,
                      ),
                      reduceMotion: state.reduceMotion,
                    ),
            ),
            const SizedBox(height: 24),
          ],
          sectionHeader(context, '使用方式', ''),
          const SizedBox(height: 14),
          ContentPanel(
            child: Column(
              children: [
                _toggleSetting(
                  context,
                  keyName: 'settings-adapt-offline',
                  icon: CupertinoIcons.wifi_slash,
                  title: '离线适配',
                  description: '断网后隐藏发现，书架只显示已缓存的收藏',
                  value: state.adaptWhenOffline,
                  onChanged: (value) =>
                      state.setNavigationMode(adaptWhenOffline: value),
                ),
                const Divider(height: 22),
                _toggleSetting(
                  context,
                  keyName: 'settings-local-reader-mode',
                  icon: CupertinoIcons.book,
                  title: '阅读器模式',
                  description: '只显示本地和设置',
                  value: state.localReaderMode,
                  onChanged: (value) =>
                      state.setNavigationMode(localReaderMode: value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          sectionHeader(context, '阅读偏好', ''),
          const SizedBox(height: 14),
          ContentPanel(
            child: Column(
              children: [
                _appearanceSetting(context),
                const Divider(height: 22),
                _toggleSetting(
                  context,
                  keyName: 'settings-serif-font',
                  icon: CupertinoIcons.textformat,
                  title: '内置思源宋体',
                  description: '关闭后使用系统字体',
                  value: state.appTypeface == AppTypeface.sourceHanSerif,
                  onChanged: (value) => state.setAppTypeface(
                    value ? AppTypeface.sourceHanSerif : AppTypeface.system,
                  ),
                ),
                const Divider(height: 22),
                ReaderValueSlider(
                  sliderKey: const ValueKey('settings-font-slider'),
                  label: '阅读字号',
                  value: state.fontSize,
                  min: 15,
                  max: 27,
                  divisions: 12,
                  format: (value) => '${value.round()} pt',
                  onCommitted: (value) =>
                      _savePreference(context, () => state.setFontSize(value)),
                ),
                if (LocalPlatform.android)
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.sun_max,
                        size: 21,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '阅读时保持亮屏',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      AppControls.toggle(
                        context,
                        value: state.keepScreenOn,
                        onChanged: (value) => _savePreference(
                          context,
                          () => state.setKeepScreenOn(value),
                        ),
                      ),
                    ],
                  ),
                const Divider(height: 13),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.circle_grid_3x3,
                        color: Theme.of(context).colorScheme.primary,
                        size: 21,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '减少动态效果',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      AppControls.toggle(
                        context,
                        value: state.reduceMotion,
                        onChanged: (value) => _savePreference(
                          context,
                          () => state.setReduceMotion(value),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (repository case final NovelRepository source) ...[
            sectionHeader(context, '阅读记录', ''),
            const SizedBox(height: 14),
            ContentPanel(
              onTap: () => openReadingHistory(context, state, source),
              child: const Row(
                children: [
                  Icon(CupertinoIcons.clock, size: 21),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '阅读历史',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 14),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (repository case final OfflineNovelRepository offline) ...[
            sectionHeader(context, '离线阅读', ''),
            const SizedBox(height: 14),
            ContentPanel(
              onTap: () => pushNovelPage<void>(
                context,
                OfflineCachePage(
                  repository: offline,
                  reduceMotion: state.reduceMotion,
                  onOpen: (pageContext, novel) => openDetail(
                    pageContext,
                    novel,
                    state,
                    offline,
                    fromCache: true,
                  ),
                ),
                reduceMotion: state.reduceMotion,
              ),
              child: const Row(
                children: [
                  Icon(CupertinoIcons.cloud_download, size: 21),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '缓存管理',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 14),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          sectionHeader(context, '玻璃外观', '实时预览'),
          const SizedBox(height: 14),
          ContentPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _glassSettingLabel(
                  context,
                  '模糊度',
                  '${state.glassBlur.round()}',
                ),
                AppControls.slider(
                  context,
                  key: const ValueKey('glass-blur-slider'),
                  value: state.glassBlur,
                  min: 0,
                  max: 24,
                  divisions: 24,
                  onChanged: (value) =>
                      state.setGlassBlur(value, persist: false),
                  onChangeEnd: state.setGlassBlur,
                ),
                const Divider(height: 22),
                _glassSettingLabel(
                  context,
                  '不透明度',
                  '${(state.glassOpacity * 100).round()}%',
                ),
                AppControls.slider(
                  context,
                  key: const ValueKey('glass-opacity-slider'),
                  value: state.glassOpacity,
                  min: 0,
                  max: 1,
                  divisions: 100,
                  onChanged: (value) =>
                      state.setGlassOpacity(value, persist: false),
                  onChangeEnd: state.setGlassOpacity,
                ),
                GlassTextButton(
                  onPressed: () async {
                    await state.setGlassBlur(8);
                    await state.setGlassOpacity(.87);
                  },
                  child: const Text('恢复默认'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          sectionHeader(context, '本地数据', ''),
          const SizedBox(height: 14),
          ContentPanel(
            key: const ValueKey('settings-backup'),
            onTap: () => pushNovelPage<void>(
              context,
              LibraryBackupPage(state: state),
              reduceMotion: state.reduceMotion,
            ),
            child: const Row(
              children: [
                Icon(CupertinoIcons.folder, size: 21),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '备份与恢复',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(CupertinoIcons.chevron_right, size: 14),
              ],
            ),
          ),
          if (LocalPlatform.android) ...[
            if (ListeningScope.maybeOf(context) case final listening?)
              if (listening.customSpeech case final settings?) ...[
                const SizedBox(height: 14),
                FeatureEntry(
                  title: '自定义语音接口',
                  subtitle: 'Microsoft SSML 兼容服务',
                  icon: CupertinoIcons.waveform,
                  onTap: () => pushNovelPage<void>(
                    context,
                    CustomSpeechPage(settings: settings, controller: listening),
                    reduceMotion: state.reduceMotion,
                  ),
                ),
              ],
            const SizedBox(height: 14),
            FeatureEntry(
              key: const ValueKey('settings-legacy-import'),
              title: '导入旧版文库记录',
              icon: CupertinoIcons.folder_badge_plus,
              subtitle: '预览后合并，保留较新的阅读进度',
              onTap: () => pushNovelPage<void>(
                context,
                LegacyImportPage(state: state),
                reduceMotion: state.reduceMotion,
              ),
            ),
            const SizedBox(height: 14),
            FeatureEntry(
              title: '清理插图缓存',
              icon: CupertinoIcons.photo,
              subtitle: '不影响书架、正文缓存和阅读记录',
              onTap: () async {
                if (!await confirmNovelAction(
                  context,
                  title: '清理已下载的插图？',
                  message: '插图下次查看时重新下载，正文和阅读记录仍保留。',
                  confirmLabel: '清理插图',
                  reduceMotion: state.reduceMotion,
                )) {
                  return;
                }
                try {
                  await LegacyTransport.clearIllustrations();
                  ReaderIllustrationCache.shared.clearMemory();
                  if (context.mounted) showNovelFeedback(context, '插图缓存已清理');
                } catch (_) {
                  if (context.mounted) showNovelFeedback(context, '缓存清理失败，请重试');
                }
              },
            ),
          ],
          const SizedBox(height: 24),
          sectionHeader(context, '性能与流畅度', ''),
          const SizedBox(height: 14),
          ContentPanel(
            key: const ValueKey('settings-performance'),
            onTap: () => pushNovelPage<void>(
              context,
              LowPerformancePage(state: state),
              reduceMotion: state.reduceMotion,
            ),
            child: const Row(
              children: [
                Icon(CupertinoIcons.speedometer, size: 21),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '低性能设备模式',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(CupertinoIcons.chevron_right, size: 14),
              ],
            ),
          ),
          const SizedBox(height: 24),
          sectionHeader(context, '关于', ''),
          const SizedBox(height: 14),
          FeatureEntry(
            key: const ValueKey('settings-app-update'),
            title: '关于轻小说文库',
            icon: CupertinoIcons.arrow_down_circle,
            subtitle:
                '版本 ${AppUpdatesScope.maybeOf(context)?.installed?.version ?? currentAppVersion}'
                ' · 构建 ${AppUpdatesScope.maybeOf(context)?.installed?.build ?? currentAppBuild}'
                '${AppUpdatesScope.maybeOf(context)?.available == true ? ' · 有新版本' : ''}',
            onTap: () => pushNovelPage<void>(
              context,
              AppUpdatePage(updates: AppUpdatesScope.maybeOf(context)),
              reduceMotion: state.reduceMotion,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _appearanceSetting(BuildContext context) {
    final label = Row(
      children: [
        Icon(
          CupertinoIcons.moon_stars,
          size: 21,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('外观模式', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
    final selector = GlassMenuAnchor(
      child: Builder(
        builder: (anchorContext) => LiquidGlass(
          radius: 20,
          elevated: false,
          semanticLabel: '选择外观模式',
          onTap: () => _chooseTheme(anchorContext),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(switch (state.theme) {
                ThemeMode.system => '跟随系统',
                ThemeMode.light => '浅色',
                ThemeMode.dark => '深色',
              }),
              const SizedBox(width: 7),
              const Icon(CupertinoIcons.chevron_down, size: 14),
            ],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 160 * scale + 70) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: selector),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: label),
            const SizedBox(width: 12),
            selector,
          ],
        );
      },
    );
  }

  Widget _glassSettingLabel(
    BuildContext context,
    String title,
    String value,
  ) => Row(
    children: [
      Expanded(
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      Text(
        value,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _toggleSetting(
    BuildContext context, {
    required String keyName,
    required IconData icon,
    required String title,
    required String description,
    required bool value,
    required Future<void> Function(bool) onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          AppControls.toggle(
            context,
            key: ValueKey(keyName),
            value: value,
            onChanged: (value) =>
                _savePreference(context, () => onChanged(value)),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(left: 33, top: 4),
        child: Text(
          description,
          style: TextStyle(
            fontSize: 12,
            height: 1.6,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );

  Future<void> _chooseTheme(BuildContext context) async {
    final selected = await showGlassMenu<ThemeMode>(
      context: context,
      reduceMotion:
          state.reduceMotion || MediaQuery.disableAnimationsOf(context),
      builder: (menuContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (mode, label) in [
            (ThemeMode.system, '跟随系统'),
            (ThemeMode.light, '浅色'),
            (ThemeMode.dark, '深色'),
          ])
            GlassMenuItem(
              order: mode.index,
              selected: state.theme == mode,
              onPressed: () => Navigator.of(menuContext).pop(mode),
              label: label,
            ),
        ],
      ),
    );
    if (selected != null && context.mounted) {
      await _savePreference(context, () => state.setTheme(selected));
    }
  }

  Future<void> _savePreference(
    BuildContext context,
    Future<void> Function() save,
  ) async {
    try {
      await save();
    } catch (_) {
      if (context.mounted) showNovelFeedback(context, '设置保存失败，请重试');
    }
  }
}

class InlineSearchResults extends StatelessWidget {
  const InlineSearchResults({
    super.key,
    required this.state,
    required this.repository,
    required this.feed,
    required this.onOpenBook,
    this.onRecall,
    this.emptyQueryTitle = '你可能会喜欢',
  });
  final LibraryState state;
  final NovelRepository repository;
  final NovelFeedController feed;
  final VoidCallback onOpenBook;
  final ValueChanged<String>? onRecall;
  final String emptyQueryTitle;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: feed,
    builder: (context, _) => LoadedContentSequence(
      generation: feed.resultRevision,
      firstIndex: feed.resultStartIndex == 0 ? 0 : feed.resultStartIndex + 1,
      child: _buildResults(context),
    ),
  );

  Widget _buildResults(BuildContext context) {
    final books = feed.items;
    if (books.isEmpty &&
        feed.query.isEmpty &&
        onRecall != null &&
        state.recentSearches.isNotEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(
          24,
          MediaQuery.paddingOf(context).top + FrostedHeader.toolbarHeight + 20,
          24,
          24,
        ),
        children: [
          RecentSearches(state: state, onRecall: onRecall!),
          if (feed.loading)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: BookCollectionSkeleton(rows: 2),
            )
          else if (feed.error != null)
            Column(
              children: [
                const Text('推荐载入失败，仍可搜索书名或作者'),
                GlassTextButton(onPressed: feed.retry, child: const Text('重试')),
              ],
            )
          else
            const Text('搜索书名或作者，开始寻找故事。'),
        ],
      );
    }
    if (books.isEmpty && feed.loading) {
      return const SearchSkeleton();
    }
    if (books.isEmpty && feed.error != null) {
      return ContentNotice(
        icon: CupertinoIcons.wifi_exclamationmark,
        title: '搜索失败，请稍后重试',
        onRetry: feed.retry,
      );
    }
    if (books.isEmpty) {
      return const ContentNotice(
        icon: CupertinoIcons.search,
        title: '没有找到相关故事',
        message: '试试更短的书名或作者名',
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            !feed.loading &&
            feed.hasMore &&
            feed.error == null &&
            notification.metrics.extentAfter < 400) {
          WidgetsBinding.instance.addPostFrameCallback((_) => feed.loadMore());
        }
        return false;
      },
      child: FeedRefresh(
        feed: feed,
        child: BookCollectionView.builder(
          key: PageStorageKey('inline-search-results-${feed.query}'),
          leadingCount: 1,
          trailingCount: 1,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            22,
            MediaQuery.paddingOf(context).top +
                FrostedHeader.toolbarHeight +
                20,
            22,
            MediaQuery.paddingOf(context).bottom + 24,
          ),
          itemCount: books.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) {
              return LoadedContentItem(
                index: 0,
                placeholder: const LoadingSkeleton(
                  layout: SkeletonLayout.actions,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (feed.query.isEmpty && onRecall != null)
                        RecentSearches(state: state, onRecall: onRecall!),
                      Text(
                        feed.query.isEmpty
                            ? emptyQueryTitle
                            : '找到 ${feed.totalItems ?? books.length} 个结果',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (index == books.length + 1) {
              return FeedFooter(feed: feed, horizontalPadding: 0);
            }
            final book = books[index - 1];
            return LoadedContentItem(
              key: ValueKey(book.id),
              index: index,
              placeholder: const BookRowSkeleton(),
              child: NovelRow(
                novel: book,
                coverHeroTag: CoverHeroTag(context, book.id),
                onTap: () {
                  onOpenBook();
                  openDetail(
                    context,
                    book,
                    state,
                    repository,
                    coverHeroTag: CoverHeroTag(context, book.id),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class DetailLoaderPage extends StatefulWidget {
  const DetailLoaderPage({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
    this.coverHeroTag,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  final Object? coverHeroTag;

  @override
  State<DetailLoaderPage> createState() => _DetailLoaderPageState();
}

class _DetailLoaderPageState extends State<DetailLoaderPage> {
  late Future<Novel> _loaded = _load();
  Novel? _cached;

  @override
  void initState() {
    super.initState();
    if (widget.repository case final OfflineNovelRepository offline) {
      final saved = offline.cache.book(widget.novel.id)?.novel;
      if (saved != null && saved.chapters.isNotEmpty) _cached = saved;
    }
    unawaited(_seedFromCache());
  }

  Future<void> _seedFromCache() async {
    if (widget.repository case final OfflineNovelRepository offline) {
      try {
        final cached = await offline.cachedBook(widget.novel.id);
        if (mounted && cached != null && cached.chapters.isNotEmpty) {
          setState(() => _cached = cached);
        }
      } catch (_) {
        // Online loading remains available when a local snapshot is damaged.
      }
    }
  }

  Future<Novel> _load() async {
    final detail = await widget.repository.detail(widget.novel);
    final chapters = await widget.repository.chapters(widget.novel.id);
    final loaded = detail.withChapters(chapters);
    await widget.state.rememberNovel(loaded);
    return loaded;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Novel>(
    future: _loaded,
    // Keep the destination cover's element and layout alive from the first
    // route frame through loading, errors and completion of its Hero flight.
    builder: (context, snapshot) => DetailPage(
      novel: snapshot.data ?? _cached ?? widget.novel,
      transitionNovel: widget.novel,
      coverHeroTag: widget.coverHeroTag,
      state: widget.state,
      repository: widget.repository,
      isLoading:
          !snapshot.hasData &&
          _cached == null &&
          snapshot.connectionState != ConnectionState.done,
      loadError: _cached == null ? snapshot.error : null,
      fromCache:
          (_cached != null && !snapshot.hasData) ||
          (widget.repository is OfflineNovelRepository &&
              (widget.repository as OfflineNovelRepository).isDirectoryOffline(
                widget.novel.id,
              )),
      onRetry: () => setState(() {
        _loaded = _load();
      }),
    ),
  );
}

class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
    this.coverHeroTag,
    this.transitionNovel,
    this.isLoading = false,
    this.loadError,
    this.onRetry,
    this.fromCache = false,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  final Object? coverHeroTag;
  final Novel? transitionNovel;
  final bool isLoading;
  final Object? loadError;
  final VoidCallback? onRetry;
  final bool fromCache;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: NovelMotion.reveal,
  );
  late final AnimationController _contentIntro = AnimationController(
    vsync: this,
    duration: NovelMotion.reveal,
  );
  Animation<double>? _routeAnimation;
  bool _introStarted = false;
  bool _contentStarted = false;
  bool _cacheSkeletonShown = false;
  bool _readerOpening = false;
  bool _shelfChanging = false;
  int? _resumeChapter;
  final Set<String> _expandedVolumes = {};
  final Set<String> _directoryVolumeKeys = {};
  int? _directoryBook;

  List<({NovelVolume? volume, int? chapter})> _directory() {
    // Provisional cached chapters can predate volume metadata. Wait for the
    // displayed directory before choosing its initially expanded volume.
    if (isLoading || loadError != null) return const [];
    final volumes = NovelVolume.of(novel.chapters);
    if (_directoryBook != novel.id) {
      _expandedVolumes.clear();
      _directoryVolumeKeys.clear();
    }
    final current = _resumeChapter ?? 0;
    for (final volume in volumes) {
      if (current >= volume.start &&
          current < volume.end &&
          !_directoryVolumeKeys.contains(volume.key)) {
        _expandedVolumes.add(volume.key);
      }
    }
    _directoryVolumeKeys
      ..clear()
      ..addAll(volumes.map((volume) => volume.key));
    _expandedVolumes.retainAll(_directoryVolumeKeys);
    if (volumes.isNotEmpty) _directoryBook = novel.id;
    return [
      for (final volume in volumes) ...[
        if (volume.title.isNotEmpty) (volume: volume, chapter: null),
        if (volume.title.isEmpty || _expandedVolumes.contains(volume.key))
          for (var i = volume.start; i < volume.end; i++)
            (volume: null, chapter: i),
      ],
    ];
  }

  Novel get novel =>
      isLocalBook(widget.novel.id) && repository is OfflineNovelRepository
      ? (repository as OfflineNovelRepository).local?.book(widget.novel.id) ??
            widget.novel
      : widget.novel;
  LibraryState get state => widget.state;
  NovelRepository get repository => widget.repository;
  Object? get coverHeroTag => widget.coverHeroTag;
  Novel? get transitionNovel => widget.transitionNovel;
  bool get _titleUpdated =>
      transitionNovel != null && transitionNovel!.title != novel.title;
  bool get _authorUpdated =>
      transitionNovel != null && transitionNovel!.author != novel.author;
  bool get isLoading => widget.isLoading;
  Object? get loadError => widget.loadError;
  VoidCallback? get onRetry => widget.onRetry;
  bool get _reduceMotion =>
      state.reduceMotion || MediaQuery.disableAnimationsOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (_routeAnimation != animation) {
      _routeAnimation?.removeStatusListener(_routeChanged);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeChanged);
    }
    if (_reduceMotion) {
      _intro.stop();
      _contentIntro.stop();
      _intro.value = 1;
      _contentIntro.value = 1;
      _introStarted = true;
      _contentStarted = !isLoading;
    } else if (animation == null ||
        animation.status == AnimationStatus.completed) {
      // A newly installed route's proxy can briefly report completed before
      // Navigator attaches the push animation at the end of its first frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startIntro();
      });
    }
  }

  void _routeChanged(AnimationStatus status) {
    if (mounted && status == AnimationStatus.completed) _startIntro();
  }

  void _startIntro() {
    if (_routeAnimation != null &&
        _routeAnimation!.status != AnimationStatus.completed) {
      return;
    }
    if (!_introStarted) {
      _introStarted = true;
      if (isLoading) setState(() => _cacheSkeletonShown = true);
      _intro.forward();
    }
    if (!isLoading && !_contentStarted) {
      _contentStarted = true;
      _contentIntro.forward();
    }
  }

  @override
  void didUpdateWidget(DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (isLoading && !oldWidget.isLoading) {
      _contentStarted = false;
      _contentIntro.value = 0;
    } else if (!isLoading && oldWidget.isLoading) {
      if (_reduceMotion) {
        _contentIntro.value = 1;
        _contentStarted = true;
      } else if (_introStarted) {
        _startIntro();
      }
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeChanged);
    _intro.dispose();
    _contentIntro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Resolve a stable chapter ID once for the lazily built directory, not once
    // per visible row or once per animation/scroll frame.
    _resumeChapter = state.hasRead(novel.id) && novel.chapters.isNotEmpty
        ? state.chapterForNovel(novel)
        : null;
    final directory = _directory();
    return Scaffold(
      body: Atmosphere(
        child: GlassHeaderLayout(
          header: _header(context),
          body: Stack(
            children: [
              Positioned.fill(
                child: CustomScrollView(
                  key: PageStorageKey('detail-scroll-${novel.id}'),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        MediaQuery.paddingOf(context).top +
                            FrostedHeader.toolbarHeight +
                            12,
                        24,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: RepaintBoundary(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  NovelCover(
                                    transitionNovel ?? novel,
                                    width: 118,
                                    height: 166,
                                    heroTag: coverHeroTag,
                                    isDetailCover: true,
                                  ),
                                  const SizedBox(width: 22),
                                  Expanded(
                                    child: Padding(
                                      // Keep the title at its existing landing
                                      // position; the inverse ID plaque belongs
                                      // below the fixed header's blur feather.
                                      padding: const EdgeInsets.only(top: 32),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          RevealFromTop(
                                            key: const ValueKey(
                                              'detail-title-reveal',
                                            ),
                                            axis: ArchiveRevealAxis.horizontal,
                                            animation: _titleUpdated
                                                ? _contentIntro
                                                : _intro,
                                            end: .46,
                                            placeholder: _titleUpdated
                                                ? const LoadingSkeleton(
                                                    layout:
                                                        SkeletonLayout.inline,
                                                  )
                                                : null,
                                            child: Text(
                                              novel.title,
                                              maxLines: 4,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 23,
                                                height: 1.3,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          RevealFromTop(
                                            key: const ValueKey(
                                              'detail-author-reveal',
                                            ),
                                            axis: ArchiveRevealAxis.horizontal,
                                            animation: _authorUpdated
                                                ? _contentIntro
                                                : _intro,
                                            start: .09,
                                            end: .56,
                                            placeholder:
                                                _authorUpdated && !isLoading
                                                ? const LoadingSkeleton(
                                                    layout:
                                                        SkeletonLayout.inline,
                                                  )
                                                : null,
                                            child:
                                                isLoading &&
                                                    novel.author.trim().isEmpty
                                                ? const InlineSkeleton(
                                                    key: ValueKey(
                                                      'detail-author-skeleton',
                                                    ),
                                                    height: 20,
                                                    label: '正在加载作者信息',
                                                  )
                                                : Text(
                                                    novel.author,
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                          ),
                                          const SizedBox(height: 20),
                                          RevealFromTop(
                                            key: const ValueKey(
                                              'detail-meta-reveal',
                                            ),
                                            axis: ArchiveRevealAxis.horizontal,
                                            animation: isLoading
                                                ? _intro
                                                : _contentIntro,
                                            start: .18,
                                            end: .64,
                                            placeholder: !isLoading
                                                ? const LoadingSkeleton(
                                                    layout:
                                                        SkeletonLayout.actions,
                                                  )
                                                : null,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (isLoading)
                                                  const InlineSkeleton(
                                                    key: ValueKey(
                                                      'detail-meta-skeleton',
                                                    ),
                                                    label: '正在加载章节信息',
                                                  )
                                                else
                                                  Text(
                                                    loadError != null
                                                        ? '目录暂未载入'
                                                        : '${novel.isComplete ? '已完结' : '连载中'}  ·  ${novel.chapters.length} 章',
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                const SizedBox(height: 8),
                                                ArchiveCode(
                                                  ArchiveDesign.fileCode(
                                                    novel.id,
                                                  ),
                                                  inverse: true,
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (repository
                                              case final OfflineNovelRepository
                                                  offline) ...[
                                            const SizedBox(height: 8),
                                            if (isLoading &&
                                                _cacheSkeletonShown)
                                              const InlineSkeleton(
                                                key: ValueKey(
                                                  'detail-cache-skeleton',
                                                ),
                                                label: '正在加载缓存信息',
                                              )
                                            else if (isLoading)
                                              const SizedBox(height: 18)
                                            else if (loadError == null &&
                                                !isLocalBook(novel.id))
                                              RevealFromTop(
                                                key: const ValueKey(
                                                  'detail-cache-reveal',
                                                ),
                                                axis: ArchiveRevealAxis
                                                    .horizontal,
                                                animation: _cacheSkeletonShown
                                                    ? _contentIntro
                                                    : _intro,
                                                start: .24,
                                                end: .72,
                                                placeholder: _cacheSkeletonShown
                                                    ? const LoadingSkeleton(
                                                        layout: SkeletonLayout
                                                            .inline,
                                                      )
                                                    : null,
                                                child: OfflineBookStatus(
                                                  repository: offline,
                                                  novel: novel,
                                                  localDirectory:
                                                      widget.fromCache,
                                                ),
                                              )
                                            else
                                              const SizedBox(height: 18),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 35),
                              if (isLoading) ...[
                                const DetailSkeleton(),
                              ] else if (loadError != null) ...[
                                const Center(child: Text('书籍详情加载失败')),
                                Center(
                                  child: GlassTextButton(
                                    onPressed: onRetry,
                                    child: const Text('重试'),
                                  ),
                                ),
                              ] else ...[
                                RevealFromTop(
                                  key: const ValueKey('detail-summary-reveal'),
                                  animation: _contentIntro,
                                  start: .27,
                                  end: .76,
                                  placeholder: const LoadingSkeleton(
                                    layout: SkeletonLayout.detail,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      sectionHeader(context, '简介', ''),
                                      const SizedBox(height: 13),
                                      Text(
                                        novel.summary,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.75,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 32),
                                if (!isLocalBook(novel.id) &&
                                    WenkuFeaturesScope.maybeOf(context) !=
                                        null) ...[
                                  RevealFromTop(
                                    animation: _contentIntro,
                                    start: .34,
                                    placeholder: const LoadingSkeleton(
                                      layout: SkeletonLayout.actions,
                                    ),
                                    child: BookCommunityActions(
                                      novel: novel,
                                      state: state,
                                      repository: repository,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                                RevealFromTop(
                                  key: const ValueKey(
                                    'detail-directory-reveal',
                                  ),
                                  animation: _contentIntro,
                                  start: .43,
                                  placeholder: const LoadingSkeleton(
                                    layout: SkeletonLayout.actions,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      sectionHeader(context, '目录', ''),
                                      const SizedBox(height: 7),
                                      if (novel.chapters.isEmpty)
                                        const Text('暂无章节'),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (!isLoading && loadError == null)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        // Keep the directory out of a single tall Column: only
                        // visible/cache-nearby rows build, lay out and paint.
                        sliver: SliverList.builder(
                          itemCount: directory.length,
                          itemBuilder: (context, index) => RevealFromTop(
                            key: ValueKey('detail-chapter-$index'),
                            animation: _contentIntro,
                            start: .48 + index.clamp(0, 8) * .025,
                            placeholder: const LoadingSkeleton(
                              layout: SkeletonLayout.inline,
                            ),
                            end: .78 + index.clamp(0, 8) * .025,
                            child: directory[index].volume != null
                                ? _volumeRow(context, directory[index].volume!)
                                : _chapterRow(
                                    context,
                                    directory[index].chapter!,
                                  ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.paddingOf(context).bottom + 96,
                      ),
                    ),
                  ],
                ),
              ),
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: DockUnderlay(),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    0,
                    22,
                    MediaQuery.paddingOf(context).bottom + 12,
                  ),
                  child: RevealFromTop(
                    key: const ValueKey('detail-footer-reveal'),
                    animation: _intro,
                    start: .52,
                    child: ArchiveMotionScope(
                      animation: _contentIntro,
                      enabled: !_reduceMotion && loadError == null,
                      child: AnimatedBuilder(
                        animation: state,
                        builder: (context, _) => GlassPillButton(
                          key: const ValueKey('detail-read-button'),
                          icon: CupertinoIcons.book,
                          loading: isLoading,
                          label: _readLabel,
                          onPressed: isLoading
                              ? null
                              : loadError != null
                              ? onRetry
                              : novel.chapters.isEmpty
                              ? null
                              : () => _openReader(
                                  context,
                                  state.chapterForNovel(novel),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _readLabel {
    if (isLoading) return '正在加载目录';
    if (loadError != null) return '重试加载目录';
    if (novel.chapters.isEmpty) return '暂无可读章节';
    final action = state.hasRead(novel.id) ? '继续阅读' : '开始阅读';
    return '$action · 第${state.chapterForNovel(novel) + 1}章';
  }

  Widget _volumeRow(BuildContext context, NovelVolume volume) {
    final expanded = _expandedVolumes.contains(volume.key);
    return Semantics(
      expanded: expanded,
      child: JellyTapSurface(
        key: ValueKey('detail-volume-${volume.key}'),
        onTap: () => setState(() {
          if (!_expandedVolumes.add(volume.key)) {
            _expandedVolumes.remove(volume.key);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  volume.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${volume.length} 章',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                expanded
                    ? CupertinoIcons.chevron_down
                    : CupertinoIcons.chevron_right,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chapterRow(BuildContext context, int index) => JellyTapSurface(
    onTap: () => _openReader(context, index),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 17),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              (index + 1).toString().padLeft(2, '0'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              novel.chapters[index].title,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
          if (index == _resumeChapter) ...[
            const SizedBox(width: 8),
            Text(
              '上次阅读',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Icon(CupertinoIcons.chevron_right, size: 14),
        ],
      ),
    ),
  );

  Widget _header(BuildContext context) => ArchiveHeaderBar(
    leading: GlassIconButton(
      icon: CupertinoIcons.back,
      label: '返回',
      onPressed: () {
        if (!LibraryWorkspace.close(context)) Navigator.pop(context);
      },
    ),
    title: ArchiveRouteTitle(
      title: '图书详情',
      code: ArchiveDesign.fileCode(novel.id),
    ),
    actions: [
      if (repository case final OfflineNovelRepository offline)
        if (isLocalBook(novel.id))
          const SizedBox.shrink()
        else if (isLoading || loadError != null || novel.chapters.isEmpty)
          const GlassIconButton(
            icon: CupertinoIcons.cloud_download,
            label: '下载与缓存',
            onPressed: null,
          )
        else
          OfflineBookMenu(
            repository: offline,
            novel: novel,
            startChapter: state.chapterForNovel(novel),
            reduceMotion: state.reduceMotion,
          ),
      if (isLocalBook(novel.id))
        GlassIconButton(
          key: const ValueKey('local-book-config'),
          icon: CupertinoIcons.gear_alt,
          label: '配置本地书籍',
          onPressed: () async {
            final local = repository is OfflineNovelRepository
                ? (repository as OfflineNovelRepository).local
                : null;
            if (local == null) return;
            final result = await pushNovelPage<LocalBookEditResult>(
              context,
              LocalBookEditor(book: novel, books: local, library: state),
              reduceMotion: _reduceMotion,
            );
            if (!mounted) return;
            if (result == LocalBookEditResult.deleted ||
                result == LocalBookEditResult.regrouped) {
              if (!LibraryWorkspace.close(this.context)) {
                Navigator.pop(this.context);
              }
            } else if (result == LocalBookEditResult.saved) {
              setState(() {});
            }
          },
        )
      else
        AnimatedBuilder(
          animation: state,
          builder: (context, child) => GlassIconButton(
            icon: state.contains(novel.id)
                ? CupertinoIcons.bookmark_fill
                : CupertinoIcons.bookmark,
            label: state.contains(novel.id) ? '移出书架' : '加入书架',
            onPressed: () async {
              if (_shelfChanging) return;
              _shelfChanging = true;
              try {
                await state.toggleShelf(novel.id, novel: novel);
              } catch (_) {
                if (context.mounted) showNovelFeedback(context, '书架操作保存失败，请重试');
              } finally {
                _shelfChanging = false;
              }
            },
          ),
        ),
    ],
  );

  Future<void> _openReader(BuildContext context, int chapter) async {
    if (_readerOpening || !mounted || !context.mounted) return;
    _readerOpening = true;
    try {
      await pushNovelPage<void>(
        context,
        ReaderPage(
          novel: novel,
          state: state,
          repository: repository,
          initialChapter: chapter,
        ),
        reduceMotion: state.reduceMotion,
      );
    } finally {
      _readerOpening = false;
      // Reader exit persists its final anchor without broadcasting scroll
      // changes. Refresh the label and directory marker once, without replay.
      if (mounted) setState(() {});
    }
  }
}

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.novel,
    required this.state,
    required this.repository,
    required this.initialChapter,
  });
  final Novel novel;
  final LibraryState state;
  final NovelRepository repository;
  final int initialChapter;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late int _chapter = widget.novel.chapters.isEmpty
      ? 0
      : widget.initialChapter.clamp(0, widget.novel.chapters.length - 1);
  late Future<({ReaderContent? content, Object? error})> _content;
  ReaderContent? _currentContent;
  bool _illustrationsRefreshing = false;
  final _findMatch = ValueNotifier<ReaderMatch?>(null);
  final _bookmarkLanding = ValueNotifier<int?>(null);
  Timer? _bookmarkLandingTimer;
  bool _bookmarkLandingPending = false;
  Timer? _highlightTimer;
  // Stable chapter IDs/paragraph anchors own restoration; do not also walk
  // PageStorage and persist the viewport on every interrupted fling.
  final _scroll = ScrollController(keepScrollOffset: false);
  late final _followScroll = ReaderFollowScroll(_scroll);
  final _paragraphRegistry = ReaderParagraphRegistry();
  final _paged = ReaderPagedController();
  final _verticalGlyphs = ReaderGlyphCache();
  final _selection = ReaderSelectionController();
  final _jumpHistory = <ReadingPosition>[];
  late ReaderMode _readerMode;
  bool get _paginated => _readerMode.paginated;
  ReadingPosition? _restorePending;
  bool _restoreQueued = false;
  bool _restoring = false;
  bool _ready = false;
  int _paragraphCount = 0;
  bool _saveQueued = false;
  Timer? _idleSave;
  bool _catalogueOpen = false;
  bool _toolsOpen = false;
  bool _findOpen = false;
  bool _listeningOpen = false;
  bool _confirmingExit = false, _allowExit = false;
  ListeningController? _listening;
  (int, int, int, int)? _listeningTarget;
  String? _listeningError;
  int _followTicket = 0;
  bool _followLocallyPaused = false;
  bool _followAutomatic = false;
  final _followPrompt = ValueNotifier(false);
  bool _enablingFollow = false;
  int _restoreTicket = 0;
  double _layoutWidth = 0;
  AppTypeface _layoutTypeface = AppTypeface.system;
  bool _typographyPreviewing = false;
  double _layoutTextScale = 1;
  double _readingInset = 0;
  int _contentGeneration = 0;
  late final AnimationController _chapterReveal;
  bool _chapterRevealPending = false;
  int _chapterRevealFirst = 0;
  late final AnimationController _chrome;
  bool _chromeTarget = true;
  bool _chromeReserved = true;
  late final Ticker _autoScroll;
  Duration? _autoLast;
  bool _autoRunning = false;
  bool _autoPaused = false;
  double _autoPageSeconds = 0;
  String _layoutKey = '';
  late ReaderPaper _paper;
  Widget _readerSurface(Widget child) => ReaderAppearance(
    state: widget.state,
    appTheme: Theme.of(context),
    child: child,
  );

  void _paperChanged() {
    final paper = widget.state.readerPreferences.paper;
    // Typography previews rebuild the article, not the glass controls. Only a
    // different paper palette needs to update the chrome's contrast.
    final mode = widget.state.readerPreferences.mode;
    if (mode != _readerMode) {
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
      _selection.clear();
      _stopAutoScroll();
    }
    if (paper != _paper || mode != _readerMode) {
      setState(() {
        _paper = paper;
        _readerMode = mode;
      });
    }
  }

  void _autoTick(Duration elapsed) {
    final previous = _autoLast;
    _autoLast = elapsed;
    if (previous == null ||
        !_ready ||
        _restoring ||
        !_listeningScrollSceneActive) {
      return;
    }
    if (_paginated) {
      if (!_paged.ready) return;
      _autoPageSeconds += ((elapsed - previous).inMicroseconds / 1000000).clamp(
        0.0,
        .05,
      );
      if (_autoPageSeconds >=
          600 / widget.state.readerPreferences.autoScrollSpeed) {
        _autoPageSeconds = 0;
        if (!_paged.pageBy(1)) {
          if (_chapter + 1 < widget.novel.chapters.length) {
            _go(_chapter + 1);
          } else {
            _stopAutoScroll(showControls: true);
          }
        }
      }
      return;
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - .5) {
      if (_chapter + 1 < widget.novel.chapters.length) {
        _go(_chapter + 1);
      } else {
        _stopAutoScroll(showControls: true);
      }
      return;
    }
    final dt = ((elapsed - previous).inMicroseconds / 1000000).clamp(0.0, .05);
    _scroll.jumpTo(
      (position.pixels + dt * widget.state.readerPreferences.autoScrollSpeed)
          .clamp(0.0, position.maxScrollExtent),
    );
  }

  void _startAutoScroll() {
    if (!_ready) return;
    _suspendListeningFollow();
    unawaited(_listening?.pause().catchError((Object _) {}));
    _autoRunning = true;
    if (_autoPaused) setState(() => _autoPaused = false);
    _autoPageSeconds = 0;
    _autoLast = null;
    _showChrome(false);
    if (!_autoScroll.isActive) _autoScroll.start();
  }

  void _stopAutoScroll({bool showControls = false}) {
    if (!_autoRunning) return;
    _autoRunning = false;
    _autoLast = null;
    _autoScroll.stop();
    if (mounted && _autoPaused != showControls) {
      setState(() => _autoPaused = showControls);
    }
    _saveWhenIdle();
    if (showControls && mounted) _showChrome(true);
  }

  void _contentTap(TapUpDetails details) {
    if (_selection.value) {
      _selection.clear();
      return;
    }
    if (_autoRunning) {
      _stopAutoScroll(showControls: true);
      return;
    }
    if (widget.state.readerPreferences.tapPaging) {
      final prefs = widget.state.readerPreferences;
      final x = details.localPosition.dx / MediaQuery.sizeOf(context).width;
      final y = details.localPosition.dy / MediaQuery.sizeOf(context).height;
      final direction = switch (prefs.tapLayout) {
        ReaderTapLayout.standard =>
          x < .28
              ? -1
              : x > .72
              ? 1
              : 0,
        ReaderTapLayout.rightHand => x > .4 ? (y < .3 ? -1 : 1) : 0,
        ReaderTapLayout.leftHand => x < .6 ? (y < .3 ? -1 : 1) : 0,
      };
      if (direction != 0) {
        _pageBy(
          prefs.mode == ReaderMode.vertical &&
                  prefs.tapLayout == ReaderTapLayout.standard
              ? -direction
              : direction,
        );
        return;
      }
    }
    _toggleChrome();
  }

  @override
  void initState() {
    super.initState();
    _paper = widget.state.readerPreferences.paper;
    _readerMode = widget.state.readerPreferences.mode;
    widget.state.readerSettingsChanges.addListener(_paperChanged);
    _autoScroll = createTicker(_autoTick);
    _chapterReveal = AnimationController(
      vsync: this,
      duration: NovelMotion.enter,
      value: 1,
    );
    _chrome = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: NovelMotion.exit,
      value: 1,
    );
    WidgetsBinding.instance.addObserver(this);
    final saved = widget.state.positionFor(widget.novel.id);
    if (saved != null &&
        widget.novel.chapters.isNotEmpty &&
        (saved.chapterId > 0
            ? saved.chapterId == widget.novel.chapters[_chapter].id
            : saved.chapter == _chapter)) {
      _restorePending = saved;
    }
    _content = _loadContent();
  }

  @override
  void didUpdateWidget(covariant ReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.readerSettingsChanges.removeListener(_paperChanged);
      widget.state.readerSettingsChanges.addListener(_paperChanged);
      _paper = widget.state.readerPreferences.paper;
    }
  }

  @override
  void deactivate() {
    // The Scrollable child detaches its controller before this State's dispose.
    // Capture while it is still attached, also when idle-save is pending.
    _idleSave?.cancel();
    _followTicket++;
    _followScroll.cancel();
    _savePosition(notify: false, finalSave: true);
    super.deactivate();
  }

  @override
  void dispose() {
    widget.state.readerSettingsChanges.removeListener(_paperChanged);
    _idleSave?.cancel();
    _savePosition(notify: false, finalSave: true);
    _highlightTimer?.cancel();
    _findMatch.dispose();
    _bookmarkLandingTimer?.cancel();
    _bookmarkLanding.dispose();
    _selection.dispose();
    _verticalGlyphs.dispose();
    _listening?.snapshot.removeListener(_listeningChanged);
    _followPrompt.dispose();
    _followTicket++;
    _followScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _chapterReveal.dispose();
    _chrome.dispose();
    _autoScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final listening = ListeningScope.maybeOf(context);
    if (listening != _listening) {
      _listening?.snapshot.removeListener(_listeningChanged);
      _listening = listening;
      listening?.snapshot.addListener(_listeningChanged);
      _listeningTarget = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listeningChanged();
      });
    } else if (listening != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listeningChanged();
      });
    }
    if (!_ready || _restoring || _layoutWidth <= 0) return;
    final media = MediaQuery.of(context);
    final scale =
        media.textScaler.scale(widget.state.fontSize) / widget.state.fontSize;
    if ((media.size.width - _layoutWidth).abs() >= 1 ||
        (scale - _layoutTextScale).abs() >= .01 ||
        _layoutTypeface != widget.state.appTypeface) {
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
    }
  }

  Future<void> _listen() async {
    _selection.clear();
    final listening = _listening;
    if (listening == null ||
        _listeningOpen ||
        _toolsOpen ||
        _catalogueOpen ||
        _findOpen) {
      return;
    }
    _stopAutoScroll();
    _listeningOpen = true;
    _followTicket++;
    _followScroll.cancel();
    try {
      await showListeningPanel(
        context,
        controller: listening,
        novel: widget.novel,
        chapter: _chapter,
        paragraph: _currentPosition()?.paragraphIndex ?? 0,
        reduceMotion: widget.state.reduceMotion,
        surfaceWrapper: _readerSurface,
      );
    } finally {
      _listeningOpen = false;
      _listeningTarget = null;
      if (mounted) _listeningChanged();
    }
  }

  void _suspendListeningFollow({bool userDrag = false}) {
    final listening = _listening;
    _followTicket++;
    _followScroll.cancel(userDrag: userDrag);
    if (listening != null &&
        listening.snapshot.value.active &&
        listening.snapshot.value.novel?.id == widget.novel.id &&
        listening.snapshot.value.follow) {
      _followLocallyPaused = true;
      _followPrompt.value = listening.snapshot.value.current != null;
      unawaited(listening.setFollow(false).catchError((Object _) {}));
    }
  }

  void _listeningChanged() {
    final state = _listening?.snapshot.value;
    final current = state?.current;
    if (state?.error == null) _listeningError = null;
    if (mounted &&
        state?.novel?.id == widget.novel.id &&
        state?.error != null &&
        state!.error != _listeningError) {
      final error = _listeningError = state.error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_listeningOpen &&
            ModalRoute.of(context)?.isCurrent != false &&
            _listening?.snapshot.value.error == error) {
          showNovelFeedback(
            context,
            error!,
            actionLabel: '听书',
            action: _listen,
          );
        }
      });
    }
    if (state == null || !state.active || !state.follow) {
      _followLocallyPaused = false;
    }
    _followPrompt.value =
        state != null &&
        state.active &&
        state.novel?.id == widget.novel.id &&
        current != null &&
        (!state.follow || _followLocallyPaused);
    if (state == null ||
        !state.active ||
        state.novel?.id != widget.novel.id ||
        !_listeningScrollSceneActive) {
      _listeningTarget = null;
      _followTicket++;
      _followScroll.cancel();
      return;
    }
    if (!state.follow || _followLocallyPaused || current == null) {
      _listeningTarget = null;
      if (_followAutomatic) {
        _followTicket++;
        _followScroll.cancel();
        _followAutomatic = false;
      }
      return;
    }
    final target = (
      widget.novel.id,
      state.chapter,
      current.paragraph,
      current.start,
    );
    if (_listeningTarget == target) return;
    _listeningTarget = target;
    if (state.chapter != _chapter) _go(state.chapter, listeningFollow: true);
    _revealListeningFragment(
      state.chapter,
      current.paragraph,
      current.start,
      current.end,
      automatic: true,
    );
  }

  bool get _listeningScrollSceneActive =>
      mounted &&
      !_listeningOpen &&
      !_toolsOpen &&
      !_catalogueOpen &&
      !_findOpen &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      ModalRoute.of(context)?.isCurrent != false;

  Future<void> _enableListeningFollow() async {
    final listening = _listening;
    final state = listening?.snapshot.value;
    if (_enablingFollow ||
        listening == null ||
        state?.active != true ||
        state?.novel?.id != widget.novel.id ||
        state?.current == null) {
      return;
    }
    _enablingFollow = true;
    _stopAutoScroll();
    _selection.clear();
    try {
      await listening.setFollow(true);
      if (!mounted) return;
      _followLocallyPaused = false;
      _listeningTarget = null;
      _listeningChanged();
    } catch (_) {
      if (mounted) showNovelFeedback(context, '跟随设置保存失败，请重试');
    } finally {
      _enablingFollow = false;
    }
  }

  void _revealListeningFragment(
    int chapter,
    int paragraph,
    int start,
    int end, {
    required bool automatic,
  }) {
    final ticket = ++_followTicket;
    _followAutomatic = automatic;
    _followScroll.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      bool allowed() =>
          _listeningScrollSceneActive &&
          ticket == _followTicket &&
          _chapter == chapter &&
          _listening?.snapshot.value.active == true &&
          _listening?.snapshot.value.novel?.id == widget.novel.id &&
          (!automatic ||
              (_listening?.snapshot.value.follow == true &&
                  !_followLocallyPaused));
      if (!allowed()) return;
      try {
        if (_paginated) {
          if (allowed() && _paged.ready) {
            _paged.reveal(ReaderTextAnchor(paragraph, start));
          }
          return;
        }
        await _followScroll.reveal(
          allowed: allowed,
          reduceMotion:
              widget.state.reduceMotion ||
              MediaQuery.disableAnimationsOf(context),
          target: () =>
              !_ready ||
                  _restoring ||
                  _restorePending != null ||
                  !_scroll.hasClients
              ? null
              : _paragraphRegistry.speechTarget(
                  paragraph,
                  start,
                  end,
                  _readingInset,
                  viewportBottom:
                      _scroll.position.viewportDimension -
                      MediaQuery.paddingOf(context).bottom -
                      116,
                  trailingSpace: 12,
                ),
        );
      } finally {
        if (ticket == _followTicket) _followAutomatic = false;
      }
    });
    // Adding a post-frame callback alone does not request a frame. In a static
    // chapter or after resuming, explicitly wake the one requested landing.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _doubleTapListeningParagraph(int paragraph) async {
    final listening = _listening;
    if (listening == null) return;
    final state = listening.snapshot.value;
    final other =
        state.active &&
        state.novel?.id == widget.novel.id &&
        (state.chapter != _chapter || state.current?.paragraph != paragraph);
    final action = listening.paragraphDoubleTap(
      novelId: widget.novel.id,
      chapter: _chapter,
      paragraph: paragraph,
    );
    // An explicit double-tap is a one-off soft landing even after a manual
    // scroll suspended following. It never flips the user's follow preference.
    if (other &&
        (!state.follow || _followLocallyPaused) &&
        _currentContent != null) {
      final text = _currentContent!.paragraphs[paragraph];
      _revealListeningFragment(
        _chapter,
        paragraph,
        0,
        text.length.clamp(0, 240),
        automatic: false,
      );
    }
    await action;
  }

  void _go(
    int index, {
    ReadingPosition? position,
    bool highlightBookmark = false,
    bool listeningFollow = false,
    bool remember = false,
  }) {
    if (index < 0 || index >= widget.novel.chapters.length) {
      return;
    }
    if (remember) _recordJump();
    _selection.clear();
    if (!listeningFollow) _suspendListeningFollow();
    _clearBookmarkLanding();
    _bookmarkLandingPending = highlightBookmark;
    if (highlightBookmark) {
      _highlightTimer?.cancel();
      _findMatch.value = null;
    }
    if (index == _chapter) {
      if (position == null) return;
      _prepareRestore(position);
      setState(() {});
      return;
    }
    _idleSave?.cancel();
    _savePosition(notify: false);
    _highlightTimer?.cancel();
    _findMatch.value = null;
    _currentContent = null;
    _illustrationsRefreshing = false;
    _ready = false;
    _restorePending = position;
    _restoreQueued = false;
    _restoring = false;
    _restoreTicket++;
    setState(() {
      _chapter = index;
      _content = _loadContent();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _catalogue() async {
    _selection.clear();
    if (_catalogueOpen ||
        _listeningOpen ||
        _toolsOpen ||
        _findOpen ||
        widget.novel.chapters.isEmpty) {
      return;
    }
    _stopAutoScroll();
    _catalogueOpen = true;
    _followTicket++;
    _followScroll.cancel();
    try {
      final index = await showJellySheet<int>(
        context: context,
        reduceMotion: widget.state.reduceMotion,
        surfaceWrapper: _readerSurface,
        builder: (context) => ReaderCatalogue(
          novel: widget.novel,
          currentChapter: _chapter,
          cache: widget.repository is OfflineNovelRepository
              ? (widget.repository as OfflineNovelRepository).cache
              : null,
        ),
      );
      if (mounted && index != null && index != _chapter) {
        _go(index, remember: true);
      }
    } finally {
      _catalogueOpen = false;
      _listeningTarget = null;
      if (mounted) _listeningChanged();
    }
  }

  Future<({ReaderContent? content, Object? error})> _loadContent({
    bool refresh = false,
  }) async {
    final index = _chapter;
    final generation = ++_contentGeneration;
    _chapterRevealPending = false;
    _chapterReveal.value = 1;
    // Picker results can arrive between frames. Carry expected request failure
    // as data, rather than an exceptional future awaiting the next UI listener.
    try {
      final content = await ReaderContent.parse(
        await _requestContent(index, refresh: refresh),
      );
      if (mounted && index == _chapter && generation == _contentGeneration) {
        _currentContent = content;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _contentGeneration) {
            _listeningTarget = null;
            _listeningChanged();
            if (content.paragraphs.any((p) => p.trim() == '[插图]') &&
                widget.repository is OfflineNovelRepository) {
              unawaited(_refreshIllustrations(automatic: true));
            }
          }
        });
        final reduce =
            widget.state.reduceMotion ||
            MediaQuery.disableAnimationsOf(context);
        if (reduce) {
          _chapterReveal.value = 1;
        } else {
          _chapterRevealPending = true;
          _chapterReveal.value = 0;
        }
      }
      return (content: content, error: null);
    } catch (error) {
      if (mounted && generation == _contentGeneration) _showChrome(true);
      return (content: null, error: error);
    }
  }

  void _showChrome(bool visible) {
    _chromeTarget = visible;
    // Start the incremental text move with the glass transition, not after
    // waiting for the hide animation to finish and then shaping the chapter.
    if (_chromeReserved != visible) {
      _chromeReserved = visible;
      // Scrolling has a constant status-bar inset. Only paged text changes
      // its reserved area; leave the scrolling article and paragraphs intact.
      if (_paginated) setState(() {});
    }
    if (widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      _chrome.value = visible ? 1 : 0;
    } else if (visible) {
      _chrome.forward();
    } else {
      _chrome.reverse();
    }
  }

  void _revealChapter() {
    if (!_chapterRevealPending || !_ready || !_scroll.hasClients) return;
    _chapterRevealPending = false;
    // Reveal the restored viewport, not offscreen paragraphs at chapter start.
    // The anchor render objects remain outside the visual transform so saving,
    // typography changes and lazy restoration keep the same coordinates.
    final first =
        _paragraphRegistry.capture(_scroll.offset + _readingInset)?.index ?? 0;
    if (_chapterRevealFirst != first) {
      setState(() => _chapterRevealFirst = first);
    }
    if (widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      _chapterReveal.value = 1;
    } else {
      _chapterReveal.forward(from: 0);
    }
  }

  void _toggleChrome() {
    if (_ready &&
        !_toolsOpen &&
        !_catalogueOpen &&
        !_findOpen &&
        !_listeningOpen) {
      _showChrome(!_chromeTarget);
    }
  }

  void _pageBy(int direction) {
    if (!_ready ||
        _toolsOpen ||
        _catalogueOpen ||
        _listeningOpen ||
        _findOpen) {
      return;
    }
    if (_selection.value) {
      _selection.clear();
      return;
    }
    _stopAutoScroll();
    _suspendListeningFollow();
    if (_paginated) {
      if (!_paged.ready || _paged.pageBy(direction)) return;
      if (direction > 0 && _chapter + 1 < widget.novel.chapters.length) {
        _go(_chapter + 1);
      }
      if (direction < 0 && _chapter > 0) {
        _go(
          _chapter - 1,
          position: ReadingPosition(
            chapter: _chapter - 1,
            chapterId: widget.novel.chapters[_chapter - 1].id,
            offset: 0,
            fraction: 1,
            fontSize: widget.state.fontSize,
            width: 0,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
      return;
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (direction > 0 &&
        position.extentAfter <= .5 &&
        _chapter + 1 < widget.novel.chapters.length) {
      _go(_chapter + 1);
      return;
    }
    if (direction < 0 && position.pixels <= .5 && _chapter > 0) {
      _go(
        _chapter - 1,
        position: ReadingPosition(
          chapter: _chapter - 1,
          chapterId: widget.novel.chapters[_chapter - 1].id,
          offset: 0,
          fraction: 1,
          fontSize: widget.state.fontSize,
          width: 0,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      return;
    }
    final target =
        (position.pixels +
                direction *
                    (position.viewportDimension - _readingInset - 100).clamp(
                      80.0,
                      double.infinity,
                    ))
            .clamp(0.0, position.maxScrollExtent);
    if (widget.state.reduceMotion || MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: NovelMotion.contact,
        curve: NovelMotion.ease,
      );
    }
  }

  Future<String> _requestContent(int index, {bool refresh = false}) async {
    if (widget.novel.chapters.isEmpty) throw const FormatException('目录为空');
    if (widget.repository case final OfflineNovelRepository offline) {
      await offline.rememberDirectory(widget.novel);
      if (refresh) {
        return offline.refreshChapterContent(
          widget.novel.id,
          widget.novel.chapters[index],
        );
      }
    }
    return widget.repository.chapterContent(
      widget.novel.id,
      widget.novel.chapters[index],
    );
  }

  Future<void> _refreshIllustrations({bool automatic = false}) async {
    if (_illustrationsRefreshing) return;
    final chapter = _chapter;
    final generation = _contentGeneration;
    setState(() => _illustrationsRefreshing = true);
    try {
      final body = automatic
          ? await (widget.repository as OfflineNovelRepository)
                .repairChapterIllustrations(
                  widget.novel.id,
                  widget.novel.chapters[chapter],
                )
          : await _requestContent(chapter, refresh: true);
      if (body == null) return;
      final content = await ReaderContent.parse(body);
      if (!mounted || chapter != _chapter || generation != _contentGeneration) {
        return;
      }
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
      setState(() {
        _currentContent = content;
        _content = Future.value((content: content, error: null));
      });
    } catch (_) {
      if (!automatic && mounted && chapter == _chapter) {
        showNovelFeedback(context, '插图暂未更新成功，正文已保留，可稍后重试');
      }
    } finally {
      if (mounted && generation == _contentGeneration) {
        setState(() => _illustrationsRefreshing = false);
      }
    }
  }

  Widget _paragraphContent(
    List<String> paragraphs,
    int index,
    TextStyle style, {
    bool fullPage = false,
  }) {
    final url = readerIllustrationUrl(paragraphs[index]);
    if (url != null) {
      return ReaderIllustration(
        url: url,
        fitPage: fullPage,
        onOpen: () => pushNovelPage<void>(
          context,
          ReaderIllustrationGallery(
            urls: _currentContent!.illustrations,
            initialUrl: url,
          ),
          reduceMotion: widget.state.reduceMotion,
        ),
      );
    }
    if (paragraphs[index].trim() == '[插图]') {
      return ReaderIllustrationFrame(
        fitPage: fullPage,
        child: _illustrationsRefreshing
            ? const LoadingSkeleton(
                layout: SkeletonLayout.cover,
                label: '正在补全插图',
              )
            : ContentPanel(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.photo),
                      const SizedBox(height: 10),
                      const Text('暂未取得本章插图地址'),
                      GlassTextButton(
                        onPressed: _refreshIllustrations,
                        child: const Text('重试本章插图'),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }
    return ReaderHighlightText(
      text: paragraphs[index],
      index: index,
      match: _findMatch,
      style: style,
      indent: widget.state.readerPreferences.indent,
      textAlign: widget.state.readerPreferences.justify
          ? TextAlign.justify
          : TextAlign.start,
    );
  }

  @override
  void didChangeMetrics() {
    if (!mounted || !_ready || _restoring) return;
    final view = View.of(context);
    final width = view.physicalSize.width / view.devicePixelRatio;
    if ((width - _layoutWidth).abs() < 1) return;
    final position = _currentPosition();
    if (position != null) _prepareRestore(position);
  }

  @override
  void didChangeTextScaleFactor() {
    if (!mounted) return;
    final position = _currentPosition();
    if (position != null) _prepareRestore(position);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _stopAutoScroll();
      _idleSave?.cancel();
      _savePosition(notify: false);
    }
    _followTicket++;
    _followScroll.cancel();
    _listeningTarget = null;
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _listeningChanged();
      });
    }
  }

  void _saveWhenIdle() {
    _idleSave?.cancel();
    if (_restoring) return;
    final generation = _contentGeneration;
    _idleSave = Timer(const Duration(milliseconds: 160), () {
      _idleSave = null;
      if (mounted &&
          generation == _contentGeneration &&
          (_paginated
              ? _paged.ready
              : _scroll.hasClients &&
                    !_scroll.position.isScrollingNotifier.value)) {
        _savePosition(notify: false);
      }
    });
  }

  void _savePosition({bool notify = true, bool finalSave = false}) {
    // Explicit save/restore/exit supersedes any delayed copy of that position.
    _idleSave?.cancel();
    _idleSave = null;
    if (!_ready ||
        _restoring ||
        (_paginated ? !_paged.ready : !_scroll.hasClients) ||
        (_typographyPreviewing && !finalSave)) {
      return;
    }
    // Lazy slivers can emit a scroll-end while correcting their estimated
    // extent during layout. Persist after that frame, not from inside layout.
    final duringLayout =
        WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks;
    if (duringLayout && !finalSave) {
      if (!_saveQueued) {
        _saveQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _saveQueued = false;
          if (mounted) _savePosition(notify: notify);
        });
      }
      return;
    }
    final position = _currentPosition(includeParagraph: !duringLayout);
    unawaited(
      widget.state
          .savePosition(
            novel: widget.novel,
            chapter: _chapter,
            offset:
                position?.offset ??
                (_paginated ? _paged.fraction : _scroll.offset),
            maximum: _paginated ? 1 : _scroll.position.maxScrollExtent,
            width: _layoutWidth,
            notify: notify,
            paragraphIndex: position?.paragraphIndex,
            paragraphFraction: position?.paragraphFraction ?? 0,
            textOffset: position?.textOffset,
            textScale: _textScale,
            typeface: position?.typeface ?? _layoutTypeface.name,
          )
          .catchError((Object _) {}),
    );
  }

  double get _textScale => _layoutTextScale;

  ReadingPosition? _currentPosition({
    bool includeParagraph = true,
    bool bookmark = false,
  }) {
    if (!_ready ||
        _restoring ||
        (_paginated ? !_paged.ready : !_scroll.hasClients) ||
        widget.novel.chapters.isEmpty) {
      return null;
    }
    if (_paginated) {
      final anchor = _paged.anchor;
      return ReadingPosition(
        chapter: _chapter,
        chapterId: widget.novel.chapters[_chapter].id,
        offset: _paged.fraction,
        fraction: _paged.fraction,
        fontSize: widget.state.fontSize,
        lineHeight: widget.state.lineHeight,
        width: _layoutWidth,
        textScale: _textScale,
        typeface: _layoutTypeface.name,
        layout: _layoutKey,
        paragraphIndex: anchor?.paragraph,
        textOffset: anchor?.offset,
        paragraphFraction: anchor == null
            ? 0
            : anchor.offset /
                  _currentContent!.paragraphs[anchor.paragraph].length.clamp(
                    1,
                    100000000,
                  ),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
    }
    final maximum = _scroll.position.maxScrollExtent;
    final offset = _scroll.offset.clamp(
      0.0,
      maximum.clamp(0.0, double.infinity),
    );
    var paragraph =
        includeParagraph && (bookmark || offset > .5 && offset < maximum - .5)
        ? _paragraphRegistry.capture(
            offset + _readingInset,
            clampToLast: bookmark,
          )
        : null;
    if (!includeParagraph) {
      // A route can be disposed inside layout, where reading RenderBox sizes
      // is invalid. Retain an already measured anchor only for the exact same
      // chapter, offset and geometry; otherwise keep the raw-offset fallback.
      final previous = widget.state.positionFor(widget.novel.id);
      if (previous != null &&
          previous.paragraphIndex != null &&
          previous.chapter == _chapter &&
          previous.chapterId == widget.novel.chapters[_chapter].id &&
          (previous.offset - offset).abs() < .5 &&
          previous.fontSize == widget.state.fontSize &&
          previous.lineHeight == widget.state.lineHeight &&
          previous.typeface == _layoutTypeface.name &&
          previous.layout == _layoutKey &&
          (previous.width - _layoutWidth).abs() < .5 &&
          (previous.textScale - _textScale).abs() < .01) {
        paragraph = (
          index: previous.paragraphIndex!,
          fraction: previous.paragraphFraction,
        );
      }
    }
    return ReadingPosition(
      chapter: _chapter,
      chapterId: widget.novel.chapters[_chapter].id,
      offset: offset,
      fraction: maximum > 0 ? (offset / maximum).clamp(0, 1) : 0,
      fontSize: widget.state.fontSize,
      lineHeight: widget.state.lineHeight,
      width: _layoutWidth,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      paragraphIndex: paragraph?.index,
      paragraphFraction: paragraph?.fraction ?? 0,
      textOffset: paragraph == null
          ? null
          : includeParagraph
          ? _paragraphRegistry.captureTextOffset(
              paragraph.index,
              offset + _readingInset,
            )
          : widget.state.positionFor(widget.novel.id)?.textOffset,
      textScale: _textScale,
      typeface: _layoutTypeface.name,
      layout: _layoutKey,
    );
  }

  void _prepareRestore(ReadingPosition position) {
    _restorePending = position;
    _restoreQueued = false;
    _restoring = true;
    _restoreTicket++;
  }

  void _clearBookmarkLanding() {
    _bookmarkLandingTimer?.cancel();
    _bookmarkLandingPending = false;
    _bookmarkLanding.value = null;
  }

  void _recordJump() {
    final position = _currentPosition();
    if (position == null) return;
    if (_jumpHistory.isNotEmpty) {
      final last = _jumpHistory.last;
      if (last.chapterId == position.chapterId &&
          last.paragraphIndex == position.paragraphIndex &&
          last.textOffset == position.textOffset &&
          (last.offset - position.offset).abs() < .5) {
        return;
      }
    }
    setState(() {
      _jumpHistory.add(position);
      if (_jumpHistory.length > 8) _jumpHistory.removeAt(0);
    });
  }

  void _returnToReading() {
    if (_jumpHistory.isEmpty) return;
    final position = _jumpHistory.last;
    final chapter = widget.state.chapterForPosition(widget.novel, position);
    setState(() => _jumpHistory.removeLast());
    if (chapter != null) _go(chapter, position: position);
  }

  void _pagedReady() {
    if (!mounted || !_paginated || !_paged.ready) return;
    final saved = _restorePending;
    _restorePending = null;
    _restoring = false;
    _restoreQueued = false;
    _landBookmark(saved);
    _listeningTarget = null;
    _listeningChanged();
    _saveWhenIdle();
  }

  Widget _pagedLeaf(ReaderLeaf page, TextStyle style) {
    if (page.fragments.length == 1 && page.fragments.first.image) {
      return ReaderTurnPart(
        child: _paragraphContent(
          _currentContent!.paragraphs,
          page.fragments.first.paragraph,
          style,
          fullPage: true,
        ),
      );
    }
    if (_readerMode == ReaderMode.vertical) {
      final key = GlobalKey(debugLabel: 'reader-vertical-page');
      Offset? doubleTap;
      Widget verticalPage(
        BuildContext context,
        ({bool active, int? paragraph}) listening,
        Widget? child,
      ) => AnimatedBuilder(
        animation: Listenable.merge([_findMatch, _bookmarkLanding]),
        builder: (context, _) {
          final match = _findMatch.value;
          final body = ReaderVerticalText(
            key: key,
            page: page,
            glyphCache: _verticalGlyphs,
            style: style.copyWith(
              fontSize: MediaQuery.textScalerOf(
                context,
              ).scale(style.fontSize ?? 19),
            ),
            highlightParagraph: _bookmarkLanding.value,
            listeningParagraph: listening.paragraph,
            match: match == null
                ? null
                : (
                    paragraph: match.paragraph,
                    start: match.start,
                    end: match.end,
                  ),
          );
          return !listening.active
              ? body
              : GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTapDown: (details) =>
                      doubleTap = details.localPosition,
                  onDoubleTap: () {
                    if (_selection.value || doubleTap == null) return;
                    final render = key.currentContext?.findRenderObject();
                    final glyph = render is RenderReaderVerticalText
                        ? render.glyphAt(doubleTap!)
                        : null;
                    if (glyph != null) {
                      unawaited(
                        _doubleTapListeningParagraph(
                          glyph.paragraph,
                        ).catchError((Object _) {}),
                      );
                    }
                  },
                  child: body,
                );
        },
      );
      final controller = _listening;
      return controller == null
          ? verticalPage(context, (active: false, paragraph: null), null)
          : SelectedValueBuilder<
              ListeningSnapshot,
              ({bool active, int? paragraph})
            >(
              listenable: controller.snapshot,
              select: (state) {
                final active =
                    state.active && state.novel?.id == widget.novel.id;
                return (
                  active: active,
                  paragraph: active && state.chapter == _chapter
                      ? state.current?.paragraph
                      : null,
                );
              },
              builder: verticalPage,
            );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final (index, fragment) in page.fragments.indexed)
          Positioned.fromRect(
            rect: fragment.rect,
            child: ReaderFragmentMotion(
              fragment: fragment,
              index: index,
              count: page.fragments.length,
              child: ValueListenableBuilder<int?>(
                valueListenable: _bookmarkLanding,
                child: Builder(
                  builder: (context) {
                    final text = ReaderHighlightText(
                      text: fragment.text,
                      index: fragment.paragraph,
                      sourceStart: fragment.start,
                      match: _findMatch,
                      style: style,
                      indent: fragment.indent,
                      textAlign: widget.state.readerPreferences.justify
                          ? TextAlign.justify
                          : TextAlign.start,
                    );
                    return _listening == null
                        ? text
                        : ListeningParagraphHighlight(
                            controller: _listening!,
                            novelId: widget.novel.id,
                            chapter: _chapter,
                            paragraph: fragment.paragraph,
                            onDoubleTap: () => _doubleTapListeningParagraph(
                              fragment.paragraph,
                            ),
                            child: text,
                          );
                  },
                ),
                builder: (context, selected, child) =>
                    selected == fragment.paragraph
                    ? ReaderLandingHighlight(
                        reduceMotion: widget.state.reduceMotion,
                        child: child!,
                      )
                    : child!,
              ),
            ),
          ),
      ],
    );
  }

  void _landBookmark(ReadingPosition? saved, {int? paragraphIndex}) {
    if (!_bookmarkLandingPending ||
        (_paginated ? !_paged.ready : !_scroll.hasClients)) {
      return;
    }
    _bookmarkLandingPending = false;
    final savedIndex = paragraphIndex ?? saved?.paragraphIndex;
    final index =
        savedIndex != null && savedIndex >= 0 && savedIndex < _paragraphCount
        ? savedIndex
        : (_paginated
                  ? _paged.anchor?.paragraph
                  : _paragraphRegistry
                        .capture(_scroll.offset + _readingInset)
                        ?.index) ??
              0;
    if (index >= _paragraphCount) return;
    _bookmarkLanding.value = index;
    _bookmarkLandingTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) _bookmarkLanding.value = null;
    });
  }

  void _applyTypography({
    double? fontSize,
    double? lineHeight,
    bool persist = true,
  }) {
    final font = fontSize ?? widget.state.fontSize;
    final spacing = lineHeight ?? widget.state.lineHeight;
    if (font == widget.state.fontSize && spacing == widget.state.lineHeight) {
      if (persist) {
        unawaited(
          widget.state
              .setTypography(fontSize: fontSize, lineHeight: lineHeight)
              .catchError((Object _) {
                if (mounted) showNovelFeedback(context, '排版设置保存失败，请重试');
              }),
        );
      }
      return;
    }
    final position = _currentPosition();
    if (position != null) _prepareRestore(position);
    unawaited(
      widget.state
          .setTypography(
            fontSize: fontSize,
            lineHeight: lineHeight,
            persist: persist,
          )
          .catchError((Object _) {
            if (mounted) showNovelFeedback(context, '排版设置保存失败，请重试');
          }),
    );
  }

  void _applyReaderPreferences(ReaderPreferences value, bool persist) {
    final changesLayout =
        value.layoutKey != widget.state.readerPreferences.layoutKey;
    if (changesLayout) {
      final position = _currentPosition();
      if (position != null) _prepareRestore(position);
    }
    unawaited(
      widget.state.setReaderPreferences(value, persist: persist).catchError((
        Object _,
      ) {
        if (mounted) {
          _restoring = false;
          showNovelFeedback(context, '阅读偏好保存失败，请重试');
        }
      }),
    );
  }

  Future<ReaderBookmark?> _addBookmark() async {
    final position = _currentPosition(bookmark: true);
    if (position == null) return null;
    _savePosition(notify: false);
    return widget.state.addBookmark(novel: widget.novel, position: position);
  }

  Future<void> _seekProgress(double fraction) async {
    if (!_ready || (_paginated ? !_paged.ready : !_scroll.hasClients)) return;
    _recordJump();
    _clearBookmarkLanding();
    if (_paginated) {
      _paged.seek(fraction);
      return;
    }
    final value = fraction.clamp(0.0, 1.0);
    final generation = _contentGeneration;
    final ticket = ++_restoreTicket;
    _restoring = true;
    // A lazy sliver refines its estimate after a large jump. Follow that new
    // extent for a bounded number of frames, including an exact chapter end.
    for (var step = 0; step < 4; step++) {
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket ||
          !_scroll.hasClients) {
        return;
      }
      final maximum = _scroll.position.maxScrollExtent;
      _scroll.jumpTo(value * maximum);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket ||
          !_scroll.hasClients) {
        return;
      }
      if ((_scroll.position.maxScrollExtent - maximum).abs() < .5) break;
    }
    _restoring = false;
    _savePosition(notify: false);
  }

  void _restoreAfterLayout() {
    if (_paginated) return;
    if (_restoreQueued) return;
    _restoreQueued = true;
    final generation = _contentGeneration;
    final ticket = ++_restoreTicket;
    _restoring = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket ||
          !_scroll.hasClients ||
          !_ready) {
        return;
      }
      final saved = _restorePending;
      _restorePending = null;
      int? landingParagraph;
      if (saved != null) {
        final centreBookmark = _bookmarkLandingPending;
        final viewportBottom = centreBookmark
            ? (_scroll.position.viewportDimension -
                      MediaQuery.paddingOf(context).bottom -
                      96)
                  .clamp(_readingInset + 1, double.infinity)
            : null;
        final sameLayout =
            (saved.fontSize - widget.state.fontSize).abs() < .01 &&
            (saved.lineHeight - widget.state.lineHeight).abs() < .01 &&
            (saved.width - _layoutWidth).abs() < 1 &&
            (saved.textScale - _textScale).abs() < .01 &&
            saved.typeface == widget.state.appTypeface.name;
        final identicalLayout =
            sameLayout &&
            saved.layout == widget.state.readerPreferences.layoutKey;
        var anchor =
            saved.paragraphIndex != null &&
                saved.paragraphIndex! >= 0 &&
                saved.paragraphIndex! < _paragraphCount
            ? (index: saved.paragraphIndex!, fraction: saved.paragraphFraction)
            : null;
        for (var step = 0; step < 10; step++) {
          if (!mounted ||
              generation != _contentGeneration ||
              ticket != _restoreTicket ||
              !_scroll.hasClients) {
            return;
          }
          final maximum = _scroll.position.maxScrollExtent;
          final paragraph = anchor == null
              ? null
              : _paragraphRegistry.target(
                  anchor,
                  _readingInset,
                  viewportBottom: viewportBottom,
                  trailingSpace: centreBookmark ? 12 : 0,
                );
          final textOffset = saved.textOffset;
          final fromPaged =
              saved.layout.endsWith(':paged') ||
              saved.layout.endsWith(':vertical');
          final precise =
              fromPaged &&
                  !centreBookmark &&
                  anchor != null &&
                  textOffset != null
              ? _paragraphRegistry.matchOffset(
                  anchor.index,
                  textOffset,
                  textOffset + 1,
                  _readingInset,
                )
              : null;
          final target = identicalLayout && step == 0 && !centreBookmark
              ? saved.offset
              : precise ??
                    paragraph?.offset ??
                    (identicalLayout && saved.fraction < .999
                        ? saved.offset
                        : saved.fraction * maximum);
          _scroll.jumpTo(
            target.clamp(
              0.0,
              centreBookmark && paragraph?.exact == true
                  ? maximum.clamp(0.0, double.infinity)
                  : double.infinity,
            ),
          );
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted ||
              generation != _contentGeneration ||
              ticket != _restoreTicket ||
              !_scroll.hasClients) {
            return;
          }
          // Older bookmarks stored only pixels. Resolve that position once,
          // then use the same paragraph-centred refinement as newer bookmarks.
          if (centreBookmark && anchor == null) {
            anchor = _paragraphRegistry.capture(
              _scroll.offset + _readingInset,
              clampToLast: true,
            );
          }
          final refined = anchor == null
              ? null
              : _paragraphRegistry.target(
                  anchor,
                  _readingInset,
                  viewportBottom: viewportBottom,
                  trailingSpace: centreBookmark ? 12 : 0,
                );
          final preciseRefined =
              fromPaged &&
                  !centreBookmark &&
                  anchor != null &&
                  textOffset != null
              ? _paragraphRegistry.matchOffset(
                  anchor.index,
                  textOffset,
                  textOffset + 1,
                  _readingInset,
                )
              : null;
          if (refined?.exact == true &&
              (_scroll.offset -
                          (preciseRefined ?? refined!.offset).clamp(
                            0.0,
                            centreBookmark
                                ? _scroll.position.maxScrollExtent.clamp(
                                    0.0,
                                    double.infinity,
                                  )
                                : double.infinity,
                          ))
                      .abs() <
                  .5) {
            break;
          }
          if (anchor == null &&
              (_scroll.position.maxScrollExtent - maximum).abs() < .5) {
            break;
          }
        }
        landingParagraph = anchor?.index;
      }
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket) {
        return;
      }
      _restoring = false;
      _revealChapter();
      _landBookmark(saved, paragraphIndex: landingParagraph);
      _savePosition();
    });
  }

  Future<void> _requestExit() async {
    if (_confirmingExit || _allowExit) return;
    _confirmingExit = true;
    try {
      final confirmed = await confirmNovelAction(
        context,
        title: '退出阅读？',
        message: '阅读位置会保留，下次可从这里继续。',
        confirmLabel: '退出阅读',
        reduceMotion: widget.state.reduceMotion,
      );
      if (!mounted || !confirmed) return;
      setState(() => _allowExit = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } finally {
      _confirmingExit = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.novel.chapters.isEmpty
        ? const NovelChapter('目录为空', '')
        : widget.novel.chapters[_chapter];
    _layoutWidth = MediaQuery.sizeOf(context).width;
    _layoutTypeface = widget.state.appTypeface;
    final appTheme = Theme.of(context);
    final appDark = appTheme.brightness == Brightness.dark;
    return PopScope<void>(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestExit();
      },
      child: ReaderAppearance(
        state: widget.state,
        appTheme: appTheme,
        child: Builder(
          builder: (context) => _readerScaffold(context, chapter, appDark),
        ),
      ),
    );
  }

  Widget _readerScaffold(
    BuildContext context,
    NovelChapter chapter,
    bool appDark,
  ) => Scaffold(
    // The catalogue owns the keyboard inset; keep the obscured article and
    // its saved scroll geometry fixed while searching in the drawer.
    resizeToAvoidBottomInset: false,
    body: Atmosphere(
      shareGlass: true,
      archiveBackdrop: false,
      child: Stack(
        children: [
          ReaderScreenBinding(state: widget.state, onPage: _pageBy),
          Positioned.fill(
            child: NativeGlassGroup(
              enabled: false,
              inherit: false,
              child: RepaintBoundary(
                key: const ValueKey('reader-article-boundary'),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                          _pageBy(1),
                      const SingleActivator(LogicalKeyboardKey.space): () =>
                          _pageBy(1),
                      const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                          _pageBy(-1),
                      const SingleActivator(LogicalKeyboardKey.home): () =>
                          _seekProgress(0),
                      const SingleActivator(LogicalKeyboardKey.end): () =>
                          _seekProgress(1),
                      const SingleActivator(
                        LogicalKeyboardKey.keyF,
                        control: true,
                      ): _findInChapter,
                      const SingleActivator(
                        LogicalKeyboardKey.keyF,
                        meta: true,
                      ): _findInChapter,
                    },
                    child: Focus(
                      autofocus: true,
                      child: Semantics(
                        customSemanticsActions: {
                          const CustomSemanticsAction(label: '切换阅读控件'):
                              _toggleChrome,
                        },
                        child: ReaderSelection(
                          controller: _selection,
                          vertical: _readerMode == ReaderMode.vertical,
                          onSelect: () {
                            _stopAutoScroll();
                            _suspendListeningFollow();
                          },
                          child: GestureDetector(
                            key: const ValueKey('reader-content-tap'),
                            behavior: HitTestBehavior.translucent,
                            onTapUp: _contentTap,
                            child: _article(context, chapter, appDark),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: ReaderChromeLayer(
              key: const ValueKey('reader-chrome-edge-blur'),
              animation: _chrome,
              child: ReaderEdgeBlur(animation: _chrome),
            ),
          ),
          if (LocalPlatform.android)
            Positioned(
              left: 0,
              width: 20,
              top: MediaQuery.paddingOf(context).top + 80,
              bottom: MediaQuery.paddingOf(context).bottom + 116,
              child: ReaderBrightnessGesture(
                state: widget.state,
                onChanged: _applyReaderPreferences,
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FrostedHeader(
              blurBackground: false,
              child: ReaderChromeLayer(
                key: const ValueKey('reader-chrome-header'),
                animation: _chrome,
                slide: const Offset(0, -1),
                child: ArchiveHeaderBar(
                  // Balance the two control groups without shrinking the title
                  // into the space left by three trailing buttons.
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlassIconButton(
                        icon: CupertinoIcons.back,
                        label: '返回详情',
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 4),
                      GlassIconButton(
                        key: const ValueKey('reader-bookmarks-entry'),
                        icon: CupertinoIcons.bookmark,
                        label: '阅读书签',
                        onPressed: () => _settings(bookmarks: true),
                      ),
                    ],
                  ),
                  title: ArchiveRouteTitle(
                    title: widget.novel.title,
                    code: 'READ / ${ArchiveDesign.fileCode(widget.novel.id)}',
                  ),
                  actions: [
                    if (_listening != null) ...[
                      GlassIconButton(
                        key: const ValueKey('reader-listening-entry'),
                        icon: CupertinoIcons.headphones,
                        label: '听书',
                        onPressed: _listen,
                      ),
                    ],
                    const SizedBox(width: 4),
                    GlassIconButton(
                      icon: CupertinoIcons.textformat_size,
                      label: '阅读设置',
                      onPressed: _settings,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                22 + MediaQuery.paddingOf(context).left,
                0,
                22 + MediaQuery.paddingOf(context).right,
                MediaQuery.paddingOf(context).bottom + 12,
              ),
              child: ReaderChromeLayer(
                key: const ValueKey('reader-chrome-dock'),
                animation: _chrome,
                slide: const Offset(0, 1),
                paintPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_jumpHistory.isNotEmpty || _autoPaused)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (_jumpHistory.isNotEmpty)
                              GlassTextButton(
                                key: const ValueKey('reader-return-position'),
                                onPressed: _returnToReading,
                                child: const Text('返回原位'),
                              ),
                            if (_autoPaused)
                              GlassTextButton(
                                key: const ValueKey('reader-auto-resume'),
                                onPressed: _startAutoScroll,
                                child: Text(_paginated ? '继续自动翻页' : '继续自动滚动'),
                              ),
                          ],
                        ),
                      ),
                    GlassDock(
                      key: const ValueKey('reader-liquid-dock'),
                      selectedIndex: 1,
                      reduceMotion: widget.state.reduceMotion,
                      items: [
                        GlassDockItem(
                          CupertinoIcons.arrow_left,
                          '上一章',
                          enabled: _chapter > 0,
                        ),
                        GlassDockItem(
                          CupertinoIcons.book,
                          '${widget.novel.chapters.isEmpty ? 0 : _chapter + 1} / ${widget.novel.chapters.length}',
                          id: 'reader-catalogue',
                          enabled: widget.novel.chapters.isNotEmpty,
                          selectableOnDrag: false,
                          semanticLabel:
                              '目录，当前第 ${widget.novel.chapters.isEmpty ? 0 : _chapter + 1} 章，共 ${widget.novel.chapters.length} 章',
                        ),
                        GlassDockItem(
                          CupertinoIcons.arrow_right,
                          '下一章',
                          enabled: _chapter + 1 < widget.novel.chapters.length,
                        ),
                      ],
                      onSelected: (index) {
                        if (index == 1) {
                          _catalogue();
                        } else {
                          _go(_chapter + (index == 0 ? -1 : 1));
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_listening != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: ValueListenableBuilder<bool>(
                valueListenable: _followPrompt,
                builder: (context, visible, _) => ReaderFollowDock(
                  visible: visible,
                  chrome: _chrome,
                  extraControlsHeight: _jumpHistory.isNotEmpty || _autoPaused
                      ? 64
                      : 0,
                  reduceMotion: widget.state.reduceMotion,
                  onEnable: _enableListeningFollow,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _article(
    BuildContext context,
    NovelChapter chapter,
    bool dark,
  ) => AnimatedBuilder(
    animation: widget.state.readerSettingsChanges,
    builder: (context, child) => FutureBuilder<({ReaderContent? content, Object? error})>(
      future: _content,
      builder: (context, snapshot) {
        final prefs = widget.state.readerPreferences;
        _layoutKey = prefs.layoutKey;
        _layoutTextScale =
            MediaQuery.textScalerOf(context).scale(widget.state.fontSize) /
            widget.state.fontSize;
        // Scroll offsets are relative to the inset, clipped viewport, not the
        // status bar. Keep that band clear even after all glass is hidden.
        _readingInset = FrostedHeader.toolbarHeight + 12;
        final content = snapshot.data?.content;
        final ready =
            snapshot.connectionState == ConnectionState.done && content != null;
        final failed =
            snapshot.connectionState == ConnectionState.done &&
            (snapshot.hasError || snapshot.data?.error != null);
        _ready = ready;
        if (ready) _restoreAfterLayout();
        final paragraphs = ready ? content.paragraphs : const <String>[];
        _paragraphCount = paragraphs.length;
        // Pagination must measure the exact resolved style that Text paints,
        // including the theme's leading distribution and fallback metrics.
        // Android emoji/CJK fallback otherwise makes the final line taller
        // than the fragment measured with a standalone partial TextStyle.
        final paragraphStyle = DefaultTextStyle.of(context).style
            .merge(
              TextStyle(
                fontFamily:
                    widget.state.appTypeface.family ??
                    Theme.of(context).textTheme.bodyMedium?.fontFamily,
                fontSize: widget.state.fontSize,
                height: widget.state.lineHeight,
                letterSpacing: .1,
                color: prefs.foreground(dark),
              ),
            )
            .copyWith(inherit: false);
        final safe = MediaQuery.viewPaddingOf(context);
        final pagedPadding = EdgeInsets.fromLTRB(
          prefs.margin + safe.left,
          safe.top + (_chromeReserved ? FrostedHeader.toolbarHeight + 12 : 8),
          prefs.margin + safe.right,
          safe.bottom +
              (_chromeReserved
                  ? 78 + (_jumpHistory.isNotEmpty || _autoPaused ? 64 : 0)
                  : 8),
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: novelSystemUiStyle(
            ThemeData.estimateBrightnessForColor(prefs.background(dark)),
          ),
          child: ColoredBox(
            color: prefs.background(dark),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: prefs.foreground(dark)),
              child: _paginated && !ready && !failed
                  ? ReaderPageSkeleton(
                      title: chapter.title,
                      padding: pagedPadding,
                      style: paragraphStyle,
                      vertical: prefs.mode == ReaderMode.vertical,
                      margin: prefs.margin,
                    )
                  : _paginated && ready
                  ? ReaderPagedView(
                      key: ValueKey('reader-pages-$_contentGeneration'),
                      content: content,
                      controller: _paged,
                      preferences: prefs,
                      style: paragraphStyle,
                      title: chapter.title,
                      position: _restorePending,
                      padding: pagedPadding,
                      reduceMotion: widget.state.reduceMotion,
                      onReady: _pagedReady,
                      onChanged: _saveWhenIdle,
                      onUserScroll: () {
                        _stopAutoScroll();
                        _suspendListeningFollow(userDrag: true);
                        _clearBookmarkLanding();
                      },
                      onBoundary: _pageBy,
                      pageBuilder: (page) => _pagedLeaf(page, paragraphStyle),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.depth == 0) {
                          if (notification is ScrollStartNotification) {
                            _idleSave?.cancel();
                            if (notification.dragDetails != null) {
                              _stopAutoScroll();
                              _suspendListeningFollow(userDrag: true);
                              _clearBookmarkLanding();
                              _restoreTicket++;
                              _restorePending = null;
                              _restoring = false;
                              _revealChapter();
                            }
                          } else if (notification is ScrollEndNotification) {
                            // A new drag stops the old fling and emits scroll-end
                            // inside its input callback. Do no anchor/storage work in
                            // that callback; save only after genuine, stable idle.
                            _saveWhenIdle();
                          }
                        }
                        return false;
                      },
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: safe.top,
                          left: safe.left,
                          right: safe.right,
                        ),
                        child: ClipRect(
                          key: const ValueKey('reader-scroll-safe-viewport'),
                          child: CustomScrollView(
                            key: const ValueKey('reader-scroll'),
                            controller: _scroll,
                            cacheExtent:
                                (MediaQuery.sizeOf(context).height * .75).clamp(
                                  250.0,
                                  900.0,
                                ),
                            slivers: [
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                  prefs.margin,
                                  FrostedHeader.toolbarHeight + 24,
                                  prefs.margin,
                                  28,
                                ),
                                sliver: SliverToBoxAdapter(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '第 ${_chapter + 1} 章',
                                            style: TextStyle(
                                              color: prefs
                                                  .foreground(dark)
                                                  .withValues(alpha: .65),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: ArchiveCode(
                                                'CH.${(_chapter + 1).toString().padLeft(3, '0')} / TEXT',
                                                color: prefs
                                                    .foreground(dark)
                                                    .withValues(alpha: .65),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        chapter.title,
                                        style: TextStyle(
                                          color: prefs.foreground(dark),
                                          fontSize: 23,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (failed)
                                SliverToBoxAdapter(
                                  child: Column(
                                    children: [
                                      const Text('章节加载失败'),
                                      GlassTextButton(
                                        onPressed: () => setState(() {
                                          _content = _loadContent();
                                        }),
                                        child: const Text('重试'),
                                      ),
                                    ],
                                  ),
                                )
                              else if (!ready)
                                const SliverPadding(
                                  padding: EdgeInsets.symmetric(horizontal: 26),
                                  sliver: SliverToBoxAdapter(
                                    child: ReaderSkeleton(),
                                  ),
                                )
                              else ...[
                                SliverPadding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: prefs.margin,
                                  ),
                                  sliver: SliverList.builder(
                                    addAutomaticKeepAlives: false,
                                    itemCount: paragraphs.length,
                                    itemBuilder: (context, index) => ReaderParagraph(
                                      key: ValueKey(
                                        'paragraph-anchor-$_contentGeneration-$index',
                                      ),
                                      registry: _paragraphRegistry,
                                      index: index,
                                      textOffset: prefs.indent ? 2 : 0,
                                      child: LoadedContentItem(
                                        key: ValueKey(
                                          'reader-paragraph-reveal-$index',
                                        ),
                                        index: index - _chapterRevealFirst,
                                        animation: _chapterReveal,
                                        placeholder: const LoadingSkeleton(
                                          layout: SkeletonLayout.reader,
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            bottom: prefs.paragraphGap,
                                          ),
                                          child: ValueListenableBuilder<int?>(
                                            valueListenable: _bookmarkLanding,
                                            child: _listening == null
                                                ? _paragraphContent(
                                                    paragraphs,
                                                    index,
                                                    paragraphStyle,
                                                  )
                                                : ListeningParagraphHighlight(
                                                    controller: _listening!,
                                                    novelId: widget.novel.id,
                                                    chapter: _chapter,
                                                    paragraph: index,
                                                    onDoubleTap: () =>
                                                        _doubleTapListeningParagraph(
                                                          index,
                                                        ),
                                                    interactive:
                                                        readerIllustrationUrl(
                                                              paragraphs[index],
                                                            ) ==
                                                            null &&
                                                        paragraphs[index]
                                                                .trim() !=
                                                            '[插图]' &&
                                                        hasSpeechText(
                                                          paragraphs[index],
                                                        ),
                                                    child: _paragraphContent(
                                                      paragraphs,
                                                      index,
                                                      paragraphStyle,
                                                    ),
                                                  ),
                                            builder:
                                                (
                                                  context,
                                                  selected,
                                                  child,
                                                ) => selected == index
                                                ? ReaderLandingHighlight(
                                                    key: ValueKey(
                                                      'bookmark-landing-$index',
                                                    ),
                                                    reduceMotion: widget
                                                        .state
                                                        .reduceMotion,
                                                    child: child!,
                                                  )
                                                : child!,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SliverPadding(
                                  padding: EdgeInsets.only(
                                    top: 48,
                                    bottom:
                                        MediaQuery.paddingOf(context).bottom +
                                        116,
                                  ),
                                  sliver: SliverToBoxAdapter(
                                    child: Column(
                                      children: [
                                        SizedBox(
                                          width: 30,
                                          child: Divider(
                                            color: prefs
                                                .foreground(dark)
                                                .withValues(alpha: .25),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          '本章完',
                                          style: TextStyle(
                                            color: prefs
                                                .foreground(dark)
                                                .withValues(alpha: .65),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        if (_chapter + 1 <
                                            widget.novel.chapters.length)
                                          GlassTextButton(
                                            key: const ValueKey(
                                              'reader-end-next',
                                            ),
                                            onPressed: () => _go(_chapter + 1),
                                            child: const Text('继续下一章'),
                                          )
                                        else
                                          Text(
                                            '已读至当前目录末章',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: prefs
                                                  .foreground(dark)
                                                  .withValues(alpha: .65),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    ),
  );

  Future<void> _settings({bool bookmarks = false}) async {
    if (_toolsOpen || _catalogueOpen || _findOpen || _listeningOpen) return;
    _selection.clear();
    _stopAutoScroll();
    _toolsOpen = true;
    _followTicket++;
    _followScroll.cancel();
    final position = _currentPosition();
    final preview = ValueNotifier(false);
    try {
      final action = await showJellySheet<ReaderToolAction>(
        context: context,
        reduceMotion: widget.state.reduceMotion,
        previewing: preview,
        heightFactor: .86,
        surfaceWrapper: _readerSurface,
        builder: (context) => ReaderTools(
          novel: widget.novel,
          state: widget.state,
          position: position,
          onAddBookmark: _addBookmark,
          onFontSize: (value) => _applyTypography(fontSize: value),
          onLineHeight: (value) => _applyTypography(lineHeight: value),
          onFontPreview: (value) =>
              _applyTypography(fontSize: value, persist: false),
          onLineHeightPreview: (value) =>
              _applyTypography(lineHeight: value, persist: false),
          onPreviewChanged: (value) {
            _typographyPreviewing = value;
            preview.value = value;
          },
          onReset: () => _applyTypography(fontSize: 19, lineHeight: 1.72),
          initialBookmarks: bookmarks,
          onPreferencesChanged: _applyReaderPreferences,
        ),
      );
      if (!mounted) return;
      switch (action) {
        case ReaderEnterFocus():
          _showChrome(false);
        case ReaderSeekProgress(:final fraction):
          await _seekProgress(fraction);
        case ReaderOpenBookmark(:final bookmark):
          final chapter = widget.state.chapterForPosition(
            widget.novel,
            bookmark.position,
          );
          if (chapter != null) {
            _go(
              chapter,
              position: bookmark.position,
              highlightBookmark: true,
              remember: true,
            );
          }
        case ReaderOpenFind():
          // The settings surface has fully collapsed before opening the next.
          _toolsOpen = false;
          await _findInChapter();
        case ReaderStartAutoScroll():
          _toolsOpen = false;
          _startAutoScroll();
        case null:
          break;
      }
    } finally {
      _toolsOpen = false;
      _typographyPreviewing = false;
      preview.dispose();
      _savePosition(notify: false);
    }
  }

  Future<void> _findInChapter() async {
    final content = _currentContent;
    if (!_ready ||
        content == null ||
        _findOpen ||
        _toolsOpen ||
        _listeningOpen ||
        _catalogueOpen) {
      return;
    }
    _stopAutoScroll();
    _clearBookmarkLanding();
    _suspendListeningFollow();
    _findOpen = true;
    final generation = _contentGeneration;
    try {
      final match = await showJellySheet<ReaderMatch>(
        context: context,
        reduceMotion: widget.state.reduceMotion,
        surfaceWrapper: _readerSurface,
        builder: (_) => ReaderFindPanel(content: content),
      );
      if (!mounted || match == null || generation != _contentGeneration) return;
      _recordJump();
      _highlightTimer?.cancel();
      _findMatch.value = match;
      // A manual drag can interrupt lazy positioning before it completes.
      // Expiration belongs to selection, not to successful restoration.
      _highlightTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) _findMatch.value = null;
      });
      if (_paginated) {
        _paged.reveal(ReaderTextAnchor(match.paragraph, match.start));
        _saveWhenIdle();
        _showChrome(true);
        return;
      }
      final ticket = ++_restoreTicket;
      _restoring = true;
      for (var step = 0; step < 20; step++) {
        if (!mounted ||
            generation != _contentGeneration ||
            ticket != _restoreTicket ||
            !_scroll.hasClients) {
          return;
        }
        final precise = _paragraphRegistry.matchOffset(
          match.paragraph,
          match.start,
          match.end,
          _readingInset + 8,
        );
        final estimate = _paragraphRegistry.target((
          index: match.paragraph,
          fraction: 0,
        ), _readingInset + 8);
        final target = precise ?? estimate?.offset;
        if (target == null) break;
        _scroll.jumpTo(target.clamp(0.0, double.infinity));
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            generation != _contentGeneration ||
            ticket != _restoreTicket ||
            !_scroll.hasClients) {
          return;
        }
        final refined = _paragraphRegistry.matchOffset(
          match.paragraph,
          match.start,
          match.end,
          _readingInset + 8,
        );
        if (refined != null &&
            (_scroll.offset -
                        refined.clamp(0.0, _scroll.position.maxScrollExtent))
                    .abs() <
                1) {
          break;
        }
      }
      if (!mounted ||
          generation != _contentGeneration ||
          ticket != _restoreTicket) {
        return;
      }
      _restoring = false;
      _savePosition(notify: false);
      _showChrome(true);
    } finally {
      _findOpen = false;
    }
  }
}
