import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_interactions.dart';
import 'app_ui.dart';
import 'archive_carousel.dart';
import 'book_collection_layout.dart';
import 'book_documents.dart';
import 'book_sync.dart';
import 'catalog.dart';
import 'cloud_book_sync_panel.dart';
import 'cloud_library_page.dart';
import 'cloud_sources.dart';
import 'feature_pages.dart' show confirmNovelAction;
import 'library_state.dart';
import 'library_reflow.dart';
import 'local_books.dart';
import 'local_import_batch.dart';
import 'local_import_review.dart';
import 'local_library_preferences.dart';
import 'local_series_actions.dart';
import 'local_series_editor.dart';
import 'pages.dart' show NovelRow;

export 'cloud_book_sync_panel.dart' show CloudBookSyncPanel;

class _CategoryNameSheet extends StatefulWidget {
  const _CategoryNameSheet({required this.organization, this.id});
  final LocalLibraryPreferences organization;
  final String? id;
  @override
  State<_CategoryNameSheet> createState() => _CategoryNameSheetState();
}

class _CategoryNameSheetState extends State<_CategoryNameSheet> {
  late final text = TextEditingController(
    text: widget.id == null ? '' : widget.organization.groups[widget.id],
  );
  bool busy = false;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      if (widget.id == null) {
        await widget.organization.addGroup(text.text);
      } else {
        await widget.organization.renameGroup(widget.id!, text.text);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        showNovelFeedback(context, e is FormatException ? e.message : '分类保存失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ArchiveSection(
          title: widget.id == null ? '新建分类' : '重命名分类',
          code: 'LOCAL / CATEGORY',
        ),
        const SizedBox(height: 20),
        CupertinoTextField(
          controller: text,
          enabled: !busy,
          placeholder: '分类名称',
          maxLength: 30,
          padding: const EdgeInsets.all(16),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 18),
        GlassPillButton(
          icon: CupertinoIcons.checkmark,
          label: '保存分类',
          onPressed: busy ? null : save,
        ),
      ],
    ),
  );
}

class LocalLibraryController extends ChangeNotifier {
  void Function(BuildContext)? importMenu;
  VoidCallback? search, refresh;
  bool importing = false;
  void changed() => notifyListeners();
}

Widget _localLibraryHeader(
  BuildContext context,
  LocalLibraryController? controller, {
  bool back = false,
}) {
  Widget header() => Row(
    children: [
      if (back)
        GlassIconButton(
          icon: CupertinoIcons.back,
          label: '返回',
          onPressed: () => Navigator.pop(context),
        ),
      const Expanded(
        child: ArchiveMasthead(title: '本地', code: '03 / LOCAL ARCHIVE'),
      ),
      GlassMenuAnchor(
        child: Builder(
          builder: (anchor) => GlassIconButton(
            key: const ValueKey('local-import-book'),
            icon: CupertinoIcons.plus,
            label: '导入书籍',
            onPressed: controller?.importMenu == null
                ? null
                : () => controller!.importMenu!(anchor),
          ),
        ),
      ),
      GlassIconButton(
        key: const ValueKey('local-search'),
        icon: CupertinoIcons.search,
        label: '搜索本地书籍',
        onPressed: controller?.search,
      ),
    ],
  );
  return controller == null
      ? header()
      : AnimatedBuilder(animation: controller, builder: (_, _) => header());
}

class LocalLibraryPage extends StatefulWidget {
  const LocalLibraryPage({
    super.key,
    required this.books,
    required this.state,
    required this.onOpen,
    this.onOpenWithCover,
    this.showHeader = true,
    this.controller,
    this.documents,
    this.cloudSettings,
    this.onSearch,
  });
  final LocalBookStore books;
  final LibraryState state;
  final void Function(BuildContext, Novel) onOpen;
  final void Function(BuildContext, Novel, Object)? onOpenWithCover;
  final bool showHeader;
  final LocalLibraryController? controller;
  final BookDocuments? documents;
  final CloudSourceSettings? cloudSettings;
  final VoidCallback? onSearch;
  Widget buildHeader(BuildContext context) =>
      _localLibraryHeader(context, controller, back: showHeader);

  @override
  State<LocalLibraryPage> createState() => _LocalLibraryPageState();
}

class _LocalLibraryPageState extends State<LocalLibraryPage> {
  late final _documents = widget.documents ?? BookDocuments();
  late final _controller = widget.controller ?? LocalLibraryController();
  late final _cloudSources = widget.cloudSettings ?? CloudSourceSettings();
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'local-library-search');
  bool _searchOpen = false;
  BookSync? _sync;
  LocalLibraryPreferences? _organization;
  String? _error;
  String _encoding = 'auto';
  bool _importing = false;
  (int, int)? _importProgress;
  bool? _routeCurrent;
  final _newImports = <int>{};
  @override
  void initState() {
    super.initState();
    _controller.refresh = _reload;
    _controller.search = widget.onSearch ?? _toggleSearch;
    _controller.importMenu = _importMenu;
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context);
    if (current == true && _routeCurrent == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.isCurrentOf(context) == true) _reload();
      });
    }
    _routeCurrent = current;
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchFocus.unfocus();
        _search.clear();
      }
    });
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _searchOpen &&
            _searchFocus.canRequestFocus &&
            ModalRoute.isCurrentOf(context) != false) {
          _searchFocus.requestFocus();
        }
      });
    }
  }

  Future<void> _importMenu(BuildContext anchor) async {
    if (_importing) return;
    final action = await showGlassMenu<String>(
      context: anchor,
      reduceMotion: widget.state.reduceMotion,
      builder: (menu) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassMenuItem(
            label: '导入书籍',
            onPressed: () => Navigator.pop(menu, 'local'),
          ),
          GlassMenuItem(
            label: '从网盘导入',
            onPressed: () => Navigator.pop(menu, 'cloud'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    _searchFocus.unfocus();
    if (action == 'local') {
      await _import();
    } else {
      await _cloud();
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final organization = LocalLibraryPreferences(prefs)..load();
      final sync = BookSync(
        books: widget.books,
        state: widget.state,
        preferences: prefs,
        documents: _documents,
        organization: organization,
      );
      setState(() {
        _organization = organization;
        _sync = sync;
        _encoding = prefs.getString('localTxtEncoding') ?? 'auto';
      });
      _controller.changed();
      await Future.wait([sync.load(), _cloudSources.load()]);
    } catch (_) {
      if (mounted) setState(() => _error = '本地书库设置读取失败，请重试');
    }
  }

  void _reload() {
    try {
      _organization?.refresh();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = '本地分类读取失败，请重试');
    }
  }

  Future<void> _save(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        showNovelFeedback(
          context,
          e is FormatException ? e.message : '设置保存失败，请重试',
        );
      }
    }
  }

  Future<Novel> _importFile(String name, String path) async {
    final imported = await widget.books.importFile(
      name,
      path,
      text: name.toLowerCase().endsWith('.txt')
          ? await _documents.decodeText(path, encoding: _encoding)
          : null,
    );
    final parent = widget.books.seriesFor(imported.id);
    final book = parent == null ? imported : widget.books.book(parent.id)!;
    if (parent != null) await reconcileLocalSeries(widget.books, widget.state);
    await widget.state.setShelfMembership(book.id, false, novel: book);
    final group = _organization?.selected;
    if (group != null && group != LocalLibraryPreferences.all) {
      await _organization!.assign(book.id, group);
    }
    if (parent == null) _newImports.add(book.id);
    return book;
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    _controller
      ..importing = true
      ..importMenu = null
      ..changed();
    List<BookDocumentSelection> selected = const [];
    LocalImportReport? report;
    try {
      selected = await _documents.pickBooks();
      if (selected.isEmpty || !mounted) return;
      setState(() => _importProgress = (0, selected.length));
      report = await importLocalBatch(
        selections: selected,
        books: widget.books,
        importFile: _importFile,
        onProgress: (completed, total) {
          if (mounted) setState(() => _importProgress = (completed, total));
        },
      );
      _newImports.removeAll(report.bookIds);
    } catch (e) {
      if (mounted) setState(() => _error = cloudFailureMessage(e));
    } finally {
      try {
        await _documents.releaseBooks(selected);
      } catch (_) {
        // The original has already been saved; disposable cache cleanup must
        // not turn a completed import into a book-import failure.
      }
      if (mounted) {
        setState(() {
          _importing = false;
          _importProgress = null;
        });
        _controller
          ..importing = false
          ..importMenu = _importMenu
          ..changed();
      }
    }
    if (mounted && report != null) await _reviewImports(report);
  }

  Future<void> _reviewImports(LocalImportReport report) async {
    if (localImportGroups(widget.books, report.bookIds).isNotEmpty ||
        report.failures.isNotEmpty) {
      await pushNovelPage<void>(
        context,
        LocalImportReview(
          books: widget.books,
          library: widget.state,
          report: report,
        ),
        reduceMotion: widget.state.reduceMotion,
      );
      if (mounted) _reload();
    } else {
      showNovelFeedback(context, report.summary);
    }
  }

  Future<void> _cloud() async {
    if (_importing) return;
    await pushNovelPage<void>(
      context,
      CloudLibraryPage(
        settings: _cloudSources,
        onImport: _importFile,
        reduceMotion: widget.state.reduceMotion,
      ),
      reduceMotion: widget.state.reduceMotion,
    );
    if (!mounted) return;
    final suggestions = _newImports.toList();
    _newImports.clear();
    if (suggestions.isNotEmpty) {
      await _reviewImports(
        LocalImportReport(
          bookIds: suggestions,
          added: suggestions.length,
          existing: 0,
        ),
      );
    }
  }

  Future<void> _volumes(Novel book, {bool suggested = false}) async {
    final result = await pushNovelPage<LocalSeriesEditResult>(
      context,
      LocalSeriesEditor(
        book: book,
        books: widget.books,
        library: widget.state,
        suggested: suggested,
      ),
      reduceMotion: widget.state.reduceMotion,
    );
    if (!mounted || result == null) return;
    _organization?.refresh();
    showNovelFeedback(
      context,
      result.dissolved
          ? '已恢复为独立书籍'
          : '已保存《${widget.books.book(result.bookId!)!.title}》的分卷',
    );
  }

  Future<void> _syncSettings() async {
    final sync = _sync;
    if (sync != null) {
      await showJellySheet<void>(
        context: context,
        reduceMotion: widget.state.reduceMotion,
        heightFactor: .86,
        builder: (_) => CloudBookSyncPanel(sync: sync),
      );
    }
  }

  Future<void> _remove(Novel book) async {
    final series = widget.books.seriesFor(book.id);
    if (!await confirmNovelAction(
      context,
      title: series == null ? '删除本机原书？' : '删除整部书的本机原书？',
      message:
          '${series == null ? '《${book.title}》的' : '《${book.title}》的 ${series.volumes.length} 卷原书将从本机移除，'}阅读记录仍保留，网盘文件不会删除。',
      confirmLabel: '删除本机原书',
      reduceMotion: widget.state.reduceMotion,
    )) {
      return;
    }
    await _save(() async {
      await removeLocalBook(
        books: widget.books,
        library: widget.state,
        id: book.id,
      );
    });
  }

  Future<void> _bookMenu(Novel book) async {
    final organization = _organization!;
    final value = await showJellySheet<String>(
      context: context,
      reduceMotion: widget.state.reduceMotion,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ArchiveSection(title: book.title, code: 'LOCAL / ORGANIZE'),
            const SizedBox(height: 14),
            for (final entry in {
              LocalLibraryPreferences.unfiled: '未分类',
              ...organization.groups,
            }.entries)
              GlassTextButton(
                onPressed: () => Navigator.pop(sheet, entry.key),
                child: Text('移至 ${entry.value}'),
              ),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, '_series'),
              child: Text(
                widget.books.seriesFor(book.id) == null ? '合并分卷' : '管理分卷',
              ),
            ),
            GlassTextButton(
              onPressed: () => Navigator.pop(sheet, '_delete'),
              child: const Text('删除本机原书'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || value == null) return;
    if (value == '_series') {
      await _volumes(book);
    } else if (value == '_delete') {
      await _remove(book);
    } else {
      await _save(() => organization.assign(book.id, value));
    }
  }

  Future<void> _nameGroup({String? id}) async {
    final organization = _organization!;
    await showJellySheet<void>(
      context: context,
      reduceMotion: widget.state.reduceMotion,
      heightFactor: .58,
      builder: (_) => _CategoryNameSheet(organization: organization, id: id),
    );
  }

  Future<void> _categories() async {
    final organization = _organization!;
    final result = await showJellySheet<String>(
      context: context,
      reduceMotion: widget.state.reduceMotion,
      heightFactor: .72,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const ArchiveSection(title: '本地分类', code: 'LOCAL / CATEGORIES'),
            const SizedBox(height: 16),
            for (final entry in {
              LocalLibraryPreferences.all: '全部书籍',
              LocalLibraryPreferences.unfiled: '未分类',
              ...organization.groups,
            }.entries)
              Row(
                children: [
                  Expanded(
                    child: GlassTextButton(
                      onPressed: () => Navigator.pop(sheet, entry.key),
                      child: Text(entry.value),
                    ),
                  ),
                  if (!entry.key.startsWith('_')) ...[
                    GlassIconButton(
                      icon: CupertinoIcons.pencil,
                      label: '重命名 ${entry.value}',
                      onPressed: () =>
                          Navigator.pop(sheet, 'rename:${entry.key}'),
                    ),
                    const SizedBox(width: 8),
                    GlassIconButton(
                      icon: CupertinoIcons.trash,
                      label: '删除分类 ${entry.value}',
                      onPressed: () =>
                          Navigator.pop(sheet, 'delete:${entry.key}'),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 12),
            GlassPillButton(
              icon: CupertinoIcons.plus,
              label: '新建分类',
              onPressed: () => Navigator.pop(sheet, '_new'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result == '_new') {
      await _nameGroup();
    } else if (result.startsWith('rename:')) {
      await _nameGroup(id: result.substring(7));
    } else if (result.startsWith('delete:')) {
      final id = result.substring(7);
      if (await confirmNovelAction(
        context,
        title: '删除这个分类？',
        message: '书籍会回到未分类，原书与阅读记录保留。',
        confirmLabel: '删除分类',
        reduceMotion: widget.state.reduceMotion,
      )) {
        await _save(() => organization.removeGroup(id));
      }
    } else {
      await _save(() => organization.select(result));
    }
  }

  Future<void> _display() async {
    final organization = _organization!;
    await showJellySheet<void>(
      context: context,
      reduceMotion: widget.state.reduceMotion,
      heightFactor: .72,
      builder: (sheet) => AnimatedBuilder(
        animation: organization,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ArchiveSection(title: '书库设置', code: 'LOCAL / SETTINGS'),
              const SizedBox(height: 18),
              for (final value in LocalLibraryView.values)
                GlassTextButton(
                  onPressed: () => _save(() => organization.setView(value)),
                  child: Text(
                    '${organization.view == value ? '✓  ' : ''}${value == LocalLibraryView.shelf ? '立体书架 + 列表' : '仅列表'}',
                  ),
                ),
              const Text('当前分类达到 10 本时显示立体书架。', style: TextStyle(height: 1.65)),
              const Divider(height: 32),
              for (final value in LocalLibrarySort.values)
                GlassTextButton(
                  onPressed: () => _save(() => organization.setSort(value)),
                  child: Text(
                    '${organization.sort == value ? '✓  ' : ''}${switch (value) {
                      LocalLibrarySort.recentAdded => '最近导入',
                      LocalLibrarySort.recentRead => '最近阅读',
                      LocalLibrarySort.title => '书名排序',
                    }}',
                  ),
                ),
              const Divider(height: 32),
              const Text(
                'TXT 编码',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final entry in {
                'auto': '自动识别',
                'UTF-8': 'UTF-8',
                'GB18030': 'GB18030 / GBK',
                'UTF-16LE': 'UTF-16 LE',
              }.entries)
                GlassTextButton(
                  onPressed: () => _save(() async {
                    await organization.setEncoding(entry.key);
                    if (mounted) setState(() => _encoding = entry.key);
                  }),
                  child: Text(
                    '${_encoding == entry.key ? '✓  ' : ''}${entry.value}',
                  ),
                ),
              const Divider(height: 32),
              GlassTextButton(
                onPressed: () {
                  Navigator.pop(sheet);
                  _syncSettings();
                },
                child: const Text('跨设备同步设置'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(Novel book, Object tag) {
    if (widget.onOpenWithCover case final open?) {
      open(context, book, tag);
    } else {
      widget.onOpen(context, book);
    }
  }

  @override
  void dispose() {
    _controller
      ..importMenu = null
      ..search = null
      ..refresh = null;
    if (widget.controller == null) _controller.dispose();
    _sync?.dispose();
    _organization?.dispose();
    if (widget.cloudSettings == null) _cloudSources.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Widget _header(BuildContext context) =>
      _localLibraryHeader(context, _controller, back: true);
  @override
  Widget build(BuildContext context) {
    final organization = _organization;
    final body = GlassHeaderLayout(
      showHeader: widget.showHeader,
      header: _header(context),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          widget.books,
          widget.state.historyChanges,
          ?organization,
        ]),
        builder: (context, _) {
          final books =
              organization?.filter(
                widget.books.books,
                query: _search.text,
                addedAt: widget.books.importedAt,
                readAt: (id) => widget.state.positionFor(id)?.updatedAt ?? 0,
              ) ??
              const <Novel>[];
          final shelf = organization?.showsShelf(books.length) == true;
          final rows = shelf ? books.skip(10).toList() : books;
          return LoadedContentSequence(
            generation: (organization?.selected, _search.text, shelf),
            child: CustomScrollView(
              key: const PageStorageKey('local-library'),
              clipBehavior: LibraryReflowScope.clipOf(context),
              cacheExtent: BookCollectionLayout.cacheExtentFor(
                MediaQuery.sizeOf(context).width - 48,
                base: 250,
              ),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    MediaQuery.paddingOf(context).top +
                        FrostedHeader.toolbarHeight +
                        20,
                    24,
                    14,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: GlassTextButton(
                                key: const ValueKey('local-category'),
                                onPressed: organization == null
                                    ? null
                                    : _categories,
                                child: Text(
                                  organization?.nameOf(organization.selected) ??
                                      '全部书籍',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GlassIconButton(
                              key: const ValueKey('local-display'),
                              icon: CupertinoIcons.slider_horizontal_3,
                              label: '本地书库设置',
                              onPressed: organization == null ? null : _display,
                            ),
                          ],
                        ),
                        AnimatedOptionSection(
                          expanded: _searchOpen,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: CupertinoSearchTextField(
                              controller: _search,
                              focusNode: _searchFocus,
                              placeholder: '搜索本地书名、作者',
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ArchiveSection(
                          title: '${books.length} 本书，随时阅读',
                          code: 'TXT / EPUB',
                        ),
                        const SizedBox(height: 14),
                        if (widget.books.books.isEmpty &&
                            organization != null) ...[
                          const Text(
                            '还没有本地书籍，点击右上角 ＋ 添加。',
                            style: TextStyle(height: 1.7),
                          ),
                        ],
                        if (_importing || organization == null)
                          BookCollectionSkeleton(
                            rows: 2,
                            label: _importProgress == null
                                ? '正在整理本地书库'
                                : '正在导入 ${_importProgress!.$1} / ${_importProgress!.$2} 本',
                          ),
                        if ((_error ?? widget.books.seriesError) != null) ...[
                          Text(
                            (_error ?? widget.books.seriesError)!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          if (organization == null)
                            GlassTextButton(
                              onPressed: _load,
                              child: const Text('重试'),
                            ),
                        ],
                        if (organization != null &&
                            books.isEmpty &&
                            widget.books.books.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text('没有符合条件的书籍，换个分类或关键词试试。'),
                          ),
                      ],
                    ),
                  ),
                ),
                if (shelf)
                  SliverToBoxAdapter(
                    child: ArchiveFileCarousel(
                      key: ValueKey(('local-shelf', organization!.selected)),
                      books: books.take(10).toList(),
                      reduceMotion: widget.state.reduceMotion,
                      animateEntrance: true,
                      onOpen: _open,
                    ),
                  ),
                if (shelf && rows.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
                    sliver: SliverToBoxAdapter(
                      child: ArchiveSection(
                        title: '更多书籍',
                        code: '${rows.length} FILES',
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: BookCollectionSliver(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final book = rows[index],
                          tag = ValueKey('local-cover-${rows[index].id}');
                      return LoadedContentItem(
                        key: ValueKey(book.id),
                        index: index,
                        placeholder: const BookRowSkeleton(),
                        child: NovelRow(
                          novel: book,
                          coverHeroTag: tag,
                          onTap: () => _open(book, tag),
                          trailing: GlassIconButton(
                            icon: CupertinoIcons.ellipsis,
                            label: '整理 ${book.title}',
                            onPressed: () => _bookMenu(book),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height:
                        MediaQuery.paddingOf(context).bottom +
                        (widget.showHeader ? 32 : 120),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    return widget.showHeader ? Scaffold(body: Atmosphere(child: body)) : body;
  }
}
