import 'dart:async';

import 'package:flutter/material.dart';
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
import 'manga_list_tile.dart';

enum _ListingWork { initial, query, refresh, more }

class SourceBrowsePage extends StatefulHookConsumerWidget {
  const SourceBrowsePage({
    super.key,
    required this.catalog,
    required this.build,
    required this.source,
    this.onAuthenticateReader,
    this.onAuthenticate,
  });
  final CatalogController catalog;
  final CatalogBuild build;
  final wire.CatalogSource source;
  final ReaderAuthentication? onAuthenticateReader;
  final VoidCallback? onAuthenticate;
  @override
  ConsumerState<SourceBrowsePage> createState() => _SourceBrowsePageState();
}

class _SourceBrowsePageState extends ConsumerState<SourceBrowsePage> {
  late TextEditingController _search;
  late ScrollController _scroll;
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
      if (_error == null && _sourceCurrent) _adoptResults();
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
      MaterialPageRoute(
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
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: SourceFiltersSheet(catalog: catalog, query: _search.text),
      ),
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: SourcePreferencesSheet(
          catalog: catalog,
          target: target,
          repository: repository,
        ),
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

  Widget _failure(String title) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(_error ?? catalog.error ?? '请返回后重新选择漫画源。'),
          for (final recovery in catalog.sourcePreferenceRecoveries.where(
            (target) =>
                target.build.packageName == widget.build.packageName &&
                target.build.catalog == widget.build.catalog,
          ))
            TextButton(
              onPressed: _loading != null || _leaving
                  ? null
                  : () => unawaited(_preferences(recovery)),
              child: const Text('处理漫画源设置'),
            ),
          TextButton(
            onPressed: _loading != null || _leaving
                ? null
                : catalog.accessPaused
                ? widget.onAuthenticate
                : _retry,
            child: Text(catalog.accessPaused ? '登录' : '重试'),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    _search = useTextEditingController();
    _scroll = useScrollController();
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
    final canBrowse =
        _sourceCurrent &&
        catalog.extensionUnavailableReason == null &&
        !catalog.sourcePreferencesBlocked &&
        !catalog.accessPaused;
    final mode = switch (_displayListing) {
      'search' => '搜索',
      'latest' => '最新',
      _ => '热门',
    };
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => unawaited(_leave())),
          title: Text(widget.source.name),
          actions: [
            IconButton(
              key: const ValueKey('source-preferences-open'),
              tooltip: '漫画源设置',
              onPressed: busy || !canBrowse
                  ? null
                  : () => unawaited(_preferences()),
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    key: const ValueKey('source-manga-search'),
                    controller: _search,
                    enabled: !busy && canBrowse,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: '搜索此源的作品',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: '搜索',
                        onPressed: busy || !canBrowse
                            ? null
                            : () => _start(
                                _ListingWork.query,
                                query: _search.text,
                              ),
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ),
                    onSubmitted: (query) =>
                        _start(_ListingWork.query, query: query),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final item in [
                        ('popular', '热门'),
                        if (catalog.activeSource?.hasSupportsLatest() == true &&
                            catalog.activeSource!.supportsLatest)
                          ('latest', '最新'),
                      ])
                        ChoiceChip(
                          label: Text(item.$2),
                          selected: catalog.listing == item.$1,
                          onSelected: busy || !canBrowse
                              ? null
                              : (_) {
                                  _search.clear();
                                  _start(
                                    _ListingWork.query,
                                    query: '',
                                    listing: item.$1,
                                  );
                                },
                        ),
                      OutlinedButton.icon(
                        key: const ValueKey('source-filters-open'),
                        onPressed: busy || !canBrowse
                            ? null
                            : () => unawaited(_filters()),
                        icon: const Icon(Icons.filter_list),
                        label: Text(
                          catalog.appliedSourceFilters == null
                              ? '筛选'
                              : '筛选（已应用）',
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('source-refresh'),
                        tooltip: '刷新当前列表',
                        onPressed: busy || !canBrowse
                            ? null
                            : () => _start(_ListingWork.refresh),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                if (_leaving || _loading != null || _openingDetails) ...[
                  const LinearProgressIndicator(),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _leaving
                          ? '正在停止并收尾'
                          : _openingDetails
                          ? '正在打开作品详情'
                          : _preparation != null
                          ? '正在下载账户所选构建'
                          : switch (_loading) {
                              _ListingWork.initial => '正在打开漫画源',
                              _ListingWork.query => '正在加载新查询',
                              _ListingWork.refresh => '正在刷新，原作品仍可查看',
                              _ => '正在加载下一页',
                            },
                    ),
                  ),
                ],
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      _work = _load(_ListingWork.refresh);
                      await _work;
                    },
                    child: ListView(
                      controller: _scroll,
                      key: const PageStorageKey('source-manga-scroll'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_libraryError != null)
                          ListTile(
                            title: Text(_libraryError!),
                            trailing: TextButton(
                              onPressed: () => unawaited(_refreshLibrary()),
                              child: const Text('重试读取书架'),
                            ),
                          ),
                        if (_loading != _ListingWork.initial && !canBrowse)
                          _failure(catalog.accessPaused ? '登录后继续' : '漫画源需要处理')
                        else if (_error != null && _failed != _ListingWork.more)
                          _failure(
                            _failed == _ListingWork.refresh
                                ? '刷新失败，原作品仍可查看'
                                : _failed == _ListingWork.query
                                ? '新查询失败，仍显示原列表'
                                : '加载失败',
                          ),
                        if (showOld &&
                            (_results.isNotEmpty || catalog.page > 0))
                          Text(
                            '$mode${_displayQuery.isEmpty ? '' : ' · $_displayQuery'}${_displayFiltered ? ' · 筛选已应用' : ''}',
                            key: const ValueKey('source-query-context'),
                          ),
                        if (showOld)
                          for (final manga in _results)
                            MangaListTile(
                              key: ValueKey(('source-manga', manga.url)),
                              manga: manga,
                              libraryEntry: saved[manga.url],
                              covers: _covers,
                              onTap: busy || !canBrowse
                                  ? null
                                  : () => unawaited(_details(manga)),
                            ),
                        if (_loading == null &&
                            _error == null &&
                            canBrowse &&
                            _results.isEmpty &&
                            catalog.page > 0)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                const Text('没有结果'),
                                Text(
                                  catalog.query.isNotEmpty ||
                                          catalog.appliedSourceFilters != null
                                      ? '请修改关键词或筛选条件。'
                                      : '当前列表暂时没有作品。',
                                ),
                                TextButton(
                                  onPressed: () => _start(_ListingWork.refresh),
                                  child: const Text('刷新'),
                                ),
                                if (catalog.query.isNotEmpty ||
                                    catalog.appliedSourceFilters != null)
                                  TextButton(
                                    onPressed: () {
                                      _search.clear();
                                      _start(
                                        _ListingWork.query,
                                        query: '',
                                        listing: 'popular',
                                      );
                                    },
                                    child: const Text('清除查询'),
                                  ),
                              ],
                            ),
                          ),
                        if (_failed == _ListingWork.more) _failure('下一页加载失败'),
                        if (showOld &&
                            canBrowse &&
                            _results.isNotEmpty &&
                            _hasNextPage)
                          Center(
                            child: TextButton(
                              key: const ValueKey('source-load-more'),
                              onPressed: busy
                                  ? null
                                  : () => _start(_ListingWork.more),
                              child: const Text('加载下一页'),
                            ),
                          )
                        else if (showOld &&
                            canBrowse &&
                            _results.isNotEmpty &&
                            !_hasNextPage &&
                            _loading == null)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('全部加载完成', textAlign: TextAlign.center),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
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
