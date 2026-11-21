import '../../theme/app_theme.dart';
import '../../widgets/app_routes.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:uuid/uuid.dart';

import '../../data/cover_repository.dart';
import '../../data/library_repository.dart';
import '../library/library_providers.dart';
import '../reader/reader_recovery.dart';
import '../sources/source_filters.dart';
import '../sources/source_preferences.dart';
import 'catalog_controller.dart';
import 'manga_details_page.dart';
import 'manga_cover_tile.dart';

enum _ListingWork { initial, query, refresh, more }

class const SourceBrowsePage({
  super.key,
  required final CatalogController catalog,
  required final CatalogBuild build,
  required final wire.CatalogSource source,
  final ReaderAuthentication? onAuthenticateReader,
  final VoidCallback? onAuthenticate,
}) extends StatefulHookConsumerWidget {
  @override
  ConsumerState<SourceBrowsePage> createState() => _SourceBrowsePageState();
}

class _SourceBrowsePageState extends ConsumerState<SourceBrowsePage> {
  static const _coverInset = 12.0;
  static const _coverSpacing = 12.0;
  static const _minimumCoverWidth = 120.0;

  late TextEditingController _search;
  late ScrollController _scroll;
  bool _searchVisible = false;
  late final Object? _identity;
  late final LibraryRepository? _library;
  CoverRepository? _covers;
  CatalogSourceRef? _reference;
  Future<void>? _work;
  String? _preparation;
  String? _error;
  _ListingWork? _loading;
  _ListingWork? _failed;
  List<MangaEntry> _results = const [];
  String _displayQuery = '';
  String _displayListing = 'popular';
  bool _displayFiltered = false;
  bool _hasNextPage = false;
  void _adoptResults() {
    _results = List.unmodifiable(catalog.mangas);
    _displayQuery = catalog.query;
    _displayListing = catalog.listing;
    _displayFiltered = catalog.appliedSourceFilters != null;
    _hasNextPage = catalog.hasNextPage;
  }

  String? _requestedQuery;
  String? _requestedListing;
  bool _leaving = false;
  bool _allowPop = false;
  bool _openingDetails = false;
  bool _loadingLibrary = false;
  String? _libraryError;
  Future<void> _refreshLibrary() async {
    if (!_current || _library == null || _loadingLibrary) return;
    _loadingLibrary = true;
    try {
      await _library.refresh();
      if (_current) setState(() => _libraryError = null);
    } catch (_) {
      if (_current) setState(() => _libraryError = '未能读取书架状态，可重试。');
    } finally {
      _loadingLibrary = false;
    }
  }

  CatalogController get catalog => widget.catalog;
  bool get _current =>
      mounted &&
      !_leaving &&
      identical(catalog.library?.client, _identity) &&
      !catalog.accessPaused &&
      ModalRoute.of(context)?.isActive == true;
  bool get _sourceCurrent =>
      _reference != null && catalog.isCurrentSource(_reference!);

  @override
  void initState() {
    super.initState();
    _identity = catalog.library?.client;
    _library = catalog.library;
    if (_library != null) {
      _covers = CoverRepository(_library.client);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _work = _open();
        unawaited(_refreshLibrary());
      }
    });
  }

  Future<void> _open() async {
    if (!_current || catalog.busy) return;
    setState(() {
      _loading = _ListingWork.initial;
      _error = null;
      _failed = null;
    });
    try {
      if (catalog.activeBuild?.id == widget.build.id &&
          catalog.activeBuild?.catalog == widget.build.catalog &&
          catalog.activeSource?.id == widget.source.id &&
          catalog.extensionUnavailableReason == null &&
          !catalog.sourcePreferencesBlocked) {
        _reference = catalog.sourceReference;
        _search.text = catalog.query;
        if (catalog.page > 0) {
          _adoptResults();
          return;
        }
      } else {
        final id = const Uuid().v4();
        _preparation = id;
        _reference = await catalog.openSelectedSource(
          packageName: widget.build.packageName,
          requested: widget.build,
          sourceId: widget.source.id,
          shouldContinue: () => _current,
          preparationId: id,
          onPrepared: () {
            if (_current) setState(() => _preparation = null);
          },
        );
        if (!_current || _reference == null) {
          if (_current) _error = catalog.error ?? '漫画源未能打开，请重试。';
          return;
        }
      }
      await catalog.loadMangas(
        shouldContinue: () => _current && _sourceCurrent,
      );
      if (_current) {
        _error = catalog.error;
        if (_error == null) _adoptResults();
      }
    } catch (error) {
      if (_current) {
        _error = error is FormatException ? error.message : '漫画源未能打开，请重试。';
      }
    } finally {
      _preparation = null;
      if (mounted) {
        setState(() {
          _loading = null;
          if (_error != null) _failed = _ListingWork.initial;
        });
      }
    }
  }

  Future<void> _load(
    _ListingWork kind, {
    String? query,
    String? listing,
  }) async {
    if (!_current || !_sourceCurrent || catalog.busy || _loading != null) {
      return;
    }
    setState(() {
      _loading = kind;
      _failed = null;
      _error = null;
      _requestedQuery = query;
      _requestedListing = listing;
    });
    await catalog.loadMangas(
      search: query,
      operation: listing,
      more: kind == _ListingWork.more,
      shouldContinue: () => _current && _sourceCurrent,
    );
    if (!mounted) return;
    setState(() {
      _loading = null;
      _error = catalog.error;
      if (_error == null && _sourceCurrent) {
        _adoptResults();
        if (kind == _ListingWork.query) _search.text = _displayQuery;
      }
      _failed = _error == null ? null : kind;
      if (_error == null &&
          kind != _ListingWork.more &&
          kind != _ListingWork.refresh &&
          _scroll.hasClients) {
        _scroll.jumpTo(0);
      }
    });
  }

  void _start(_ListingWork kind, {String? query, String? listing}) =>
      _work = _load(kind, query: query, listing: listing);
  void _retry() {
    if (_failed == _ListingWork.initial || !_sourceCurrent) {
      _work = _open();
      return;
    }
    _start(
      _failed ?? _ListingWork.refresh,
      query: _requestedQuery,
      listing: _requestedListing,
    );
  }

  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    final id = _preparation;
    _preparation = null;
    try {
      if (id != null) await catalog.runtime.cancelPreparation(id);
      await _work;
    } catch (_) {
      if (mounted) {
        setState(() {
          _leaving = false;
          _error = '停止未完成，请重试返回。';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  Future<void> _details(MangaEntry entry) async {
    if (!_current || !_sourceCurrent || catalog.busy || _openingDetails) return;
    setState(() => _openingDetails = true);
    final request = catalog.details(
      entry,
      shouldContinue: () => _current && _sourceCurrent,
    );
    _work = request.then<void>((_) {});
    final details = await request;
    if (!mounted) return;
    setState(() => _openingDetails = false);
    if (details == null || !_current || !_sourceCurrent) {
      setState(() => _error = catalog.error);
      return;
    }
    await Navigator.of(context).push<void>(
      AppPageRoute(
        builder: (_) => MangaDetailsPage(
          controller: catalog,
          manga: details.manga,
          chapters: details.chapters,
          source: details.source,
          onAuthenticateReader: widget.onAuthenticateReader,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _filters() async {
    final applied = await showAppSheet<bool>(
      context: context,
      enableDrag: false,
      scrollableBuilder: (context, _) =>
          SourceFiltersSheet(catalog: catalog, query: _search.text),
    );
    if (mounted && applied == true) {
      setState(() {
        _error = null;
        _failed = null;
        _adoptResults();
      });
    }
  }

  Future<void> _preferences([SourcePreferencesTarget? recovery]) async {
    final target = recovery ?? catalog.currentPreferencesTarget,
        repository = catalog.sourcePreferences;
    if (target == null || repository == null) return;
    await showAppSheet<void>(
      context: context,
      enableDrag: false,
      scrollableBuilder: (context, _) => SourcePreferencesSheet(
        catalog: catalog,
        target: target,
        repository: repository,
      ),
    );
    if (mounted &&
        catalog.activeSource?.id == widget.source.id &&
        catalog.activeBuild?.id == widget.build.id) {
      setState(() {
        _reference = catalog.sourceReference;
        _error = catalog.error;
        if (_sourceCurrent && catalog.page > 0) _adoptResults();
      });
    }
  }

  Widget _failure(String title) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: CupertinoListSection.insetGrouped(
      // Cupertino paints keyboard focus outside the button's bounds.
      clipBehavior: Clip.none,
      backgroundColor: AppColors.background.resolveFrom(context),
      separatorColor: AppColors.separator.resolveFrom(context),
      decoration: BoxDecoration(
        color: AppColors.groupedSurface.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      children: [
        Text(
          title,
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        const SizedBox(height: 8),
        Text(_error ?? catalog.error ?? '请返回后重新选择漫画源。'),
        for (final recovery in catalog.sourcePreferenceRecoveries.where(
          (target) =>
              target.build.packageName == widget.build.packageName &&
              target.build.catalog == widget.build.catalog,
        ))
          CupertinoButton(
            onPressed: _loading != null || _leaving
                ? null
                : () => unawaited(_preferences(recovery)),
            child: const Text('处理漫画源设置'),
          ),
        CupertinoButton(
          onPressed: _loading != null || _leaving
              ? null
              : catalog.accessPaused
              ? widget.onAuthenticate
              : _retry,
          child: Text(catalog.accessPaused ? '登录' : '重试'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    _search = useTextEditingController();
    _scroll = useScrollController();
    final searchFocus = useFocusNode();
    final searchToggleFocus = useFocusNode();
    final draftQuery = useListenableSelector(_search, () => _search.text);
    useListenable(catalog);
    final view =
        _library != null &&
            identical(catalog.library?.client, _identity) &&
            !catalog.accessPaused
        ? ref.watch(libraryViewProvider(_library)).value
        : null;
    final saved = {
      for (final entry in view?.entries ?? <LibraryEntry>[])
        if (entry.packageName == widget.build.packageName &&
            entry.sourceId == widget.source.id)
          entry.url: entry,
    };
    final busy =
        catalog.busy || _loading != null || _leaving || _openingDetails;
    final showOld = _loading != _ListingWork.query;
    final appending = _loading == _ListingWork.more;
    final activity = _leaving
        ? '正在停止并收尾'
        : _openingDetails
        ? '正在打开作品详情'
        : _preparation != null
        ? '正在下载账户所选构建'
        : switch (_loading) {
            _ListingWork.initial => '正在打开漫画源',
            _ListingWork.query => '正在加载新查询',
            _ListingWork.refresh => '正在刷新，原作品仍可查看',
            _ => null,
          };
    final canBrowse =
        _sourceCurrent &&
        catalog.extensionUnavailableReason == null &&
        !catalog.sourcePreferencesBlocked &&
        !catalog.accessPaused;
    final canInteract = !busy && canBrowse;
    final keyboardOpen =
        _searchVisible &&
        searchFocus.hasFocus &&
        MediaQuery.viewInsetsOf(context).bottom > 0;
    final noResults =
        _loading == null &&
        _error == null &&
        canBrowse &&
        _results.isEmpty &&
        catalog.page > 0;
    final mode = switch (_displayListing) {
      'search' => '搜索',
      'latest' => '最新',
      _ => '热门',
    };
    final feedback = <Widget>[
      if (_libraryError case final error?)
        CupertinoListTile(
          title: Text(error),
          trailing: CupertinoButton(
            onPressed: () => unawaited(_refreshLibrary()),
            child: const Text('重试读取书架'),
          ),
        ),
      if (showOld &&
          ((_displayQuery.isNotEmpty &&
                  (!_searchVisible || draftQuery != _displayQuery)) ||
              (_failed == _ListingWork.query && _results.isNotEmpty)))
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
          child: Text(
            _displayQuery.isEmpty ? '当前列表：$mode' : '当前查询：$_displayQuery',
            key: const ValueKey('source-query-context'),
            style: TextStyle(
              color: AppColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
      if (_loading != _ListingWork.initial && !canBrowse)
        _failure(catalog.accessPaused ? '登录后继续' : '漫画源需要处理')
      else if (_error != null && _failed != _ListingWork.more)
        _failure(switch (_failed) {
          _ListingWork.refresh => '刷新失败，原作品仍可查看',
          _ListingWork.query => '新查询失败，仍显示原列表',
          _ => '加载失败',
        }),
    ];

    void submitSearch(String query) {
      searchFocus.unfocus();
      _start(_ListingWork.query, query: query);
    }

    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          leading: CupertinoNavigationBarBackButton(
            onPressed: () => unawaited(_leave()),
          ),
          middle: Text(
            widget.source.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoButton(
                key: const ValueKey('source-search-toggle'),
                focusNode: searchToggleFocus,
                padding: EdgeInsets.zero,
                onPressed: canInteract
                    ? () {
                        if (_searchVisible) {
                          _search.text = _displayQuery;
                          searchToggleFocus.requestFocus();
                        }
                        setState(() => _searchVisible = !_searchVisible);
                      }
                    : null,
                child: Icon(
                  _searchVisible ? CupertinoIcons.xmark : CupertinoIcons.search,
                  semanticLabel: _searchVisible ? '关闭搜索' : '搜索此源的作品',
                ),
              ),
              CupertinoButton(
                key: const ValueKey('source-preferences-open'),
                onPressed: canInteract ? () => unawaited(_preferences()) : null,
                padding: EdgeInsets.zero,
                child: const Icon(
                  CupertinoIcons.slider_horizontal_3,
                  semanticLabel: '漫画源设置',
                ),
              ),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                children: [
                  if (_searchVisible)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoTextField(
                              key: const ValueKey('source-manga-search'),
                              controller: _search,
                              focusNode: searchFocus,
                              autofocus: true,
                              autofillHints: null,
                              enabled: canInteract,
                              clearButtonMode: OverlayVisibilityMode.editing,
                              textInputAction: TextInputAction.search,
                              onSubmitted: submitSearch,
                              placeholder: '搜索此源的作品',
                              placeholderStyle: TextStyle(
                                color: AppColors.secondaryLabel.resolveFrom(
                                  context,
                                ),
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.selection.resolveFrom(context),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              prefix: Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  start: 8,
                                ),
                                child: Icon(
                                  CupertinoIcons.search,
                                  color: AppColors.secondaryLabel.resolveFrom(
                                    context,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          CupertinoButton(
                            key: const ValueKey('source-search-submit'),
                            onPressed: canInteract
                                ? () => submitSearch(_search.text)
                                : null,
                            padding: EdgeInsets.zero,
                            child: const Icon(
                              CupertinoIcons.arrow_right,
                              semanticLabel: '提交搜索',
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!keyboardOpen)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (catalog.activeSource?.supportsLatest == true)
                              CupertinoSlidingSegmentedControl<String>(
                                groupValue: _displayListing == 'search'
                                    ? null
                                    : _displayListing,
                                children: const {
                                  'popular': Text('热门'),
                                  'latest': Text('最新'),
                                },
                                disabledChildren: !canInteract
                                    ? const {'popular', 'latest'}
                                    : const {},
                                onValueChanged: (value) {
                                  _start(
                                    _ListingWork.query,
                                    query: '',
                                    listing: value!,
                                  );
                                },
                              )
                            else
                              Semantics(
                                selected: _displayListing == 'popular',
                                child: CupertinoButton(
                                  sizeStyle: CupertinoButtonSize.small,
                                  minimumSize: const Size(44, 44),
                                  color: _displayListing == 'popular'
                                      ? AppColors.selection
                                      : null,
                                  foregroundColor: _displayListing == 'popular'
                                      ? AppColors.onSelection
                                      : null,
                                  onPressed: !canInteract
                                      ? null
                                      : () {
                                          _start(
                                            _ListingWork.query,
                                            query: '',
                                            listing: 'popular',
                                          );
                                        },
                                  child: const Text('热门'),
                                ),
                              ),
                            CupertinoButton(
                              key: const ValueKey('source-filters-open'),
                              sizeStyle: CupertinoButtonSize.small,
                              minimumSize: const Size(44, 44),
                              onPressed: !canInteract
                                  ? null
                                  : () => unawaited(_filters()),
                              child: Text(_displayFiltered ? '筛选（已应用）' : '筛选'),
                            ),
                            CupertinoButton(
                              key: const ValueKey('source-refresh'),
                              onPressed: !canInteract
                                  ? null
                                  : () => _start(_ListingWork.refresh),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                CupertinoIcons.refresh,
                                semanticLabel: '刷新当前列表',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (activity != null) ...[
                    const CupertinoActivityIndicator(),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(activity),
                    ),
                  ],
                  Expanded(
                    child: CustomScrollView(
                      key: const PageStorageKey('source-manga-scroll'),
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        CupertinoSliverRefreshControl(
                          onRefresh: () async {
                            _work = _load(_ListingWork.refresh);
                            await _work;
                          },
                        ),
                        if (feedback.isNotEmpty)
                          SliverList.list(children: feedback),
                        if (showOld && _results.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.all(_coverInset),
                            sliver: SliverLayoutBuilder(
                              builder: (context, constraints) =>
                                  SliverGrid.builder(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount:
                                              ((constraints.crossAxisExtent +
                                                          _coverSpacing) /
                                                      (_minimumCoverWidth +
                                                          _coverSpacing))
                                                  .floor()
                                                  .clamp(1, 100),
                                          mainAxisSpacing: _coverSpacing,
                                          crossAxisSpacing: _coverSpacing,
                                          childAspectRatio: 2 / 3,
                                        ),
                                    itemCount: _results.length,
                                    itemBuilder: (context, index) {
                                      final manga = _results[index];
                                      return MangaCoverTile(
                                        key: ValueKey((
                                          'source-manga',
                                          manga.url,
                                        )),
                                        title: manga.title,
                                        entry: saved[manga.url],
                                        covers: _covers,
                                        badge: saved[manga.url] == null
                                            ? null
                                            : Icon(
                                                CupertinoIcons.book_fill,
                                                color: CupertinoTheme.of(
                                                  context,
                                                ).primaryColor,
                                                semanticLabel: '已在书架',
                                              ),
                                        onPressed: busy || !canBrowse
                                            ? null
                                            : () => unawaited(_details(manga)),
                                      );
                                    },
                                  ),
                            ),
                          ),
                        if (noResults)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '没有结果',
                                      style: CupertinoTheme.of(context)
                                          .textTheme
                                          .navTitleTextStyle,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _displayQuery.isNotEmpty ||
                                              _displayFiltered
                                          ? '请修改关键词或筛选条件。'
                                          : '当前列表暂时没有作品。',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.secondaryLabel
                                            .resolveFrom(context),
                                      ),
                                    ),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      children: [
                                        CupertinoButton(
                                          onPressed: canInteract
                                              ? () =>
                                                    _start(_ListingWork.refresh)
                                              : null,
                                          child: const Text('刷新'),
                                        ),
                                        if (_displayQuery.isNotEmpty ||
                                            _displayFiltered)
                                          CupertinoButton(
                                            onPressed: canInteract
                                                ? () => _start(
                                                    _ListingWork.query,
                                                    query: '',
                                                    listing: 'popular',
                                                  )
                                                : null,
                                            child: const Text('清除查询'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (showOld && _results.isNotEmpty)
                          SliverPadding(
                            padding: const EdgeInsets.all(16),
                            sliver: SliverList.list(
                              children: [
                                if (_failed == _ListingWork.more)
                                  _failure('下一页加载失败')
                                else if (appending && !_leaving && canBrowse)
                                  Semantics(
                                    liveRegion: true,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      child: Wrap(
                                        alignment: WrapAlignment.center,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          CupertinoActivityIndicator(),
                                          Text('正在加载下一页'),
                                        ],
                                      ),
                                    ),
                                  )
                                else if (canBrowse && _hasNextPage)
                                  Center(
                                    child: CupertinoButton(
                                      key: const ValueKey('source-load-more'),
                                      onPressed: busy
                                          ? null
                                          : () => _start(_ListingWork.more),
                                      child: const Text('加载下一页'),
                                    ),
                                  )
                                else if (canBrowse &&
                                    !_hasNextPage &&
                                    _loading == null)
                                  const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      '全部加载完成',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    final id = _preparation;
    _preparation = null;
    if (id != null) {
      unawaited(
        catalog.runtime.cancelPreparation(id).catchError((Object _) {}),
      );
    }
    super.dispose();
  }
}
