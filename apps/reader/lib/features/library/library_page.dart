import '../../widgets/app_page_route.dart';
import '../../widgets/choice_field.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/library_repository.dart';
import '../../data/business_state_client.dart';
import '../../data/cover_repository.dart';
import '../../theme/app_theme.dart';
import '../browse/catalog_controller.dart';
import '../browse/manga_cover_tile.dart';
import '../browse/manga_details_page.dart';
import '../reader/reader_recovery.dart';
import '../reader/chapter_reader_route.dart';
import '../reader/chapter_sequence.dart';
import '../migration/migration_controller.dart';
import '../migration/migration_page.dart';
import 'category_dialogs.dart';
import 'library_batch.dart';
import 'library_batch_dialogs.dart';
import 'library_providers.dart';

enum _LibrarySort { added, title }

class const LibraryPage({
  super.key,
  required final CatalogController? controller,
  required final VoidCallback onBrowse,
  required final VoidCallback onConnect,
  required final VoidCallback onAuthenticate,
  final ReaderAuthentication? onAuthenticateReader,
}) extends StatefulHookConsumerWidget {
  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  late TextEditingController _search;
  LibraryRepository? _repository;
  CoverRepository? _covers;
  late ValueNotifier<int> _editLifecycle;
  String? _categoryFilter;
  bool _editing = false;
  bool _disposing = false;
  _LibrarySort _sort = _LibrarySort.added;
  bool _opening = false;
  bool _catalogChangeScheduled = false;
  String? _refreshError;
  String? _openError;
  String? _retryingMetadata;
  Object? _metadataAttempt;
  final _selection = <String>{};
  bool _selecting = false;

  @override
  void didUpdateWidget(LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindRepository();
  }

  void _catalogChanged() {
    if (!mounted || _disposing) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_catalogChangeScheduled) {
        _catalogChangeScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _catalogChangeScheduled = false;
          _catalogChanged();
        });
      }
      return;
    }
    setState(_bindRepository);
  }

  void _bindRepository() {
    final next = widget.controller?.library;
    _editLifecycle.value++;
    if (widget.controller?.status != ServiceStatus.ready) {
      _selection.clear();
      _selecting = false;
    }
    if (identical(_repository, next)) {
      return;
    }
    _repository = next;
    _covers = next == null ? null : CoverRepository(next.client);
    _selection.clear();
    _selecting = false;
    _refreshError = null;
    _openError = null;
    _retryingMetadata = null;
    _metadataAttempt = null;
    _categoryFilter = null;
  }

  Future<void> _refresh() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.refresh();
      if (mounted && identical(repository, _repository)) {
        setState(() => _refreshError = null);
      }
    } catch (_) {
      if (mounted && identical(repository, _repository)) {
        setState(() => _refreshError = '未能刷新服务端书架，当前显示上次确认的结果。');
      }
    }
  }

  void _retryStorage() {
    if (_repository case final repository?) {
      ref.invalidate(libraryViewProvider(repository));
    }
  }

  Future<void> _open(LibraryEntry entry, {bool continueReading = false}) async {
    final controller = widget.controller;
    final repository = _repository;
    if (_opening ||
        _retryingMetadata != null ||
        controller == null ||
        repository == null) {
      return;
    }
    final route = ModalRoute.of(context);
    final identityKey = repository.identity.key;
    bool isCurrent() =>
        mounted &&
        !_disposing &&
        identical(widget.controller, controller) &&
        identical(_repository, repository) &&
        identical(controller.library, repository) &&
        repository.identity.key == identityKey &&
        controller.status == ServiceStatus.ready &&
        route?.isCurrent == true &&
        route?.isActive == true;
    if (!isCurrent()) return;
    setState(() {
      _opening = true;
      _openError = null;
    });
    try {
      final details = await controller.openLibraryEntry(
        entry,
        identityKey: identityKey,
        shouldContinue: isCurrent,
      );
      if (details == null || !isCurrent()) return;
      Future<void> showDetails({String? notice}) async {
        if (!isCurrent() || !controller.isCurrentSource(details.source)) return;
        await Navigator.of(context).push<void>(
          AppPageRoute<void>(
            builder: (_) => MangaDetailsPage(
              controller: controller,
              manga: details.manga,
              chapters: details.chapters,
              source: details.source,
              notice: notice,
              onAuthenticateReader: widget.onAuthenticateReader,
            ),
          ),
        );
      }

      if (!continueReading) {
        await showDetails();
        return;
      }
      final progress = controller.readingProgress;
      if (progress == null || progress.identity.key != identityKey) return;
      // The shelf projects confirmed state. An explicit resume uses this
      // session's unsaved navigation first, otherwise rereads current D1 state.
      final draftResume = controller.readingDraftResume(entry.mangaKey);
      final resume = draftResume ?? await progress.loadResume(entry.mangaKey);
      bool sourceCurrent() =>
          isCurrent() &&
          identical(controller.readingProgress, progress) &&
          controller.isCurrentSource(details.source);
      if (!sourceCurrent()) return;
      final sequence = ChapterSequence(
        packageName: entry.packageName,
        sourceId: details.source.sourceId,
        mangaUrl: details.manga.url,
        chapters: details.chapters.map((chapter) => chapter.snapshot),
      );
      final chapterIndex = resume == null || sequence.mangaKey != entry.mangaKey
          ? -1
          : sequence.entries.indexWhere(
              (chapter) => chapter.key == resume.chapterKey,
            );
      if (chapterIndex < 0) {
        await showDetails(
          notice: resume == null
              ? '当前没有可继续的阅读位置，已打开详情，请选择章节。'
              : '上次阅读的章节已不在当前清单，已打开详情，请选择章节。',
        );
        return;
      }
      final chapter = sequence.entries[chapterIndex];
      final opened = await controller.openChapter(
        details.manga,
        ChapterEntry(chapter.snapshot),
        reference: details.source,
        logicalChapterKey: chapter.key,
      );
      if (opened == null) {
        if (sourceCurrent()) {
          setState(() => _openError = controller.error ?? '章节未能打开，请重试。');
        }
        return;
      }
      try {
        if (!mounted || !sourceCurrent()) return;
        final readerRoute = AppPageRoute<void>(
          builder: (_) => ChapterReaderRoute(
            catalog: controller,
            manga: details.manga,
            source: details.source,
            sequence: sequence,
            initialChapter: chapter,
            initialOpened: opened,
            initialOrder: draftResume == null
                ? null
                : draftResume.reversedOrder
                ? ChapterOrder.reversed
                : ChapterOrder.source,
            onAuthenticate: widget.onAuthenticateReader,
          ),
        );
        await Navigator.of(context).push<void>(readerRoute);
        await readerRoute.completed;
      } finally {
        // Also owns a page session acquired after this shelf ceased to be
        // current, or a route popped before its Reader leaf attached.
        await controller.closeChapter(opened);
      }
    } catch (_) {
      if (isCurrent()) {
        setState(() => _openError = '未能打开继续阅读，请重试；原阅读位置和未确认草稿仍保留。');
      }
    } finally {
      if (isCurrent()) await _refresh();
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _migrate(LibraryEntry entry) async {
    final catalog = widget.controller;
    final repository = _repository;
    if (_opening ||
        _editing ||
        _retryingMetadata != null ||
        catalog == null ||
        repository == null ||
        catalog.busy ||
        catalog.status != ServiceStatus.ready ||
        !identical(catalog.library, repository)) {
      return;
    }
    final client = repository.client;
    setState(() => _opening = true);
    try {
      await Navigator.of(context).push<void>(
        AppPageRoute(
          builder: (_) => MigrationPage(
            catalog: catalog,
            client: client,
            seed: MigrationSeed(
              metadata: wire.LibraryMetadata(
                packageName: entry.packageName,
                sourceId: entry.sourceId,
                sourceName: entry.sourceName,
                sourceLang: entry.sourceLang,
                manga: entry.snapshot,
              ),
            ),
          ),
        ),
      );
      if (mounted &&
          identical(_repository, repository) &&
          identical(catalog.library?.client, repository.client)) {
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _retryMetadata(LibraryEntry entry) async {
    final controller = widget.controller;
    final repository = _repository;
    if (_opening ||
        _editing ||
        _retryingMetadata != null ||
        controller == null ||
        repository == null ||
        controller.busy ||
        controller.status != ServiceStatus.ready ||
        !repository.client.hasPendingMetadata(entry.mangaKey)) {
      return;
    }
    final route = ModalRoute.of(context);
    final identityKey = repository.identity.key;
    final attempt = Object();
    final originalCatalogError = controller.error;
    bool isCurrent() =>
        mounted &&
        !_disposing &&
        identical(_metadataAttempt, attempt) &&
        identical(widget.controller, controller) &&
        identical(_repository, repository) &&
        identical(controller.library, repository) &&
        repository.identity.key == identityKey &&
        controller.status == ServiceStatus.ready &&
        route?.isCurrent == true &&
        route?.isActive == true;
    setState(() {
      _metadataAttempt = attempt;
      _retryingMetadata = entry.mangaKey;
      _openError = null;
    });
    try {
      await repository.client.retryMetadata(entry.mangaKey);
      if (!isCurrent()) return;
      setState(() {
        if (controller.error == originalCatalogError) controller.error = null;
        _openError = '书架资料已获服务器确认。';
      });
      // A failed read after the ACK cannot make the completed write pending.
      // Refresh has its own read-failure state and never resends the command.
      await _refresh();
    } on BusinessStateException catch (failure) {
      if (!isCurrent()) return;
      if (failure.conflict || !failure.error.retryable) {
        try {
          // A confirmed rejection permits a read to release the old pending
          // command. Never turn opening a manga into another implicit write.
          await repository.client.readManga(entry.mangaKey);
          await repository.refresh();
          if (!isCurrent()) return;
          setState(() {
            if (controller.error == originalCatalogError) {
              controller.error = null;
            }
            _openError = '原书架资料修改未能确认，已读取服务器当前状态。请重新打开漫画取得最新资料。';
          });
        } catch (_) {
          if (isCurrent()) {
            setState(() => _openError = '原书架资料修改已被拒绝，当前状态未能读取；请刷新书架后重试。');
          }
        }
      } else {
        setState(() => _openError = '书架资料仍未获确认，原操作已保留，请明确重试保存。');
      }
    } catch (_) {
      if (isCurrent()) setState(() => _openError = '书架资料仍未获确认，原操作已保留，请明确重试保存。');
    } finally {
      if (mounted && identical(_metadataAttempt, attempt)) {
        setState(() {
          _metadataAttempt = null;
          _retryingMetadata = null;
        });
      }
    }
  }

  Future<void> _editCategories(LibraryView view, {LibraryEntry? entry}) async {
    final controller = widget.controller;
    final repository = _repository;
    if (_editing ||
        _opening ||
        _retryingMetadata != null ||
        controller == null ||
        repository == null ||
        controller.status != ServiceStatus.ready ||
        controller.busy ||
        pendingLibraryBatch(repository) != null) {
      return;
    }
    final route = ModalRoute.of(context);
    final identityKey = repository.identity.key;
    bool isCurrent() =>
        mounted &&
        !_disposing &&
        identical(widget.controller, controller) &&
        identical(_repository, repository) &&
        identical(controller.library, repository) &&
        repository.identity.key == identityKey &&
        controller.status == ServiceStatus.ready &&
        route?.isActive == true;
    setState(() => _editing = true);
    try {
      if (entry == null) {
        await showLibraryCategoryManager(
          context: context,
          controller: controller,
          repository: repository,
          view: view,
          lifecycle: _editLifecycle,
          isCurrent: isCurrent,
        );
      } else {
        await showLibraryCategoryPicker(
          context: context,
          controller: controller,
          repository: repository,
          view: view,
          entry: entry,
          lifecycle: _editLifecycle,
          isCurrent: isCurrent,
        );
      }
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Set<String> _selectedKeys(LibraryView view) => view.entries
      .where((entry) => _selection.contains(entry.mangaKey))
      .map((entry) => entry.mangaKey)
      .toSet();

  void _toggleSelection(String key) => setState(() {
    if (!_selection.add(key)) _selection.remove(key);
  });

  Future<void> _batch(LibraryView view, {LibraryBatchAction? action}) async {
    final controller = widget.controller;
    final repository = _repository;
    if (_editing ||
        _opening ||
        _retryingMetadata != null ||
        controller == null ||
        repository == null ||
        controller.status != ServiceStatus.ready ||
        controller.busy ||
        hasPendingLibraryCategoryEdit(repository)) {
      return;
    }
    final pending = pendingLibraryBatch(repository);
    final keys = _selectedKeys(view);
    if (pending == null && (action == null || keys.isEmpty)) return;
    final route = ModalRoute.of(context);
    final identityKey = repository.identity.key;
    bool isCurrent() =>
        mounted &&
        !_disposing &&
        identical(widget.controller, controller) &&
        identical(_repository, repository) &&
        identical(controller.library, repository) &&
        repository.identity.key == identityKey &&
        controller.status == ServiceStatus.ready &&
        route?.isActive == true;
    setState(() => _editing = true);
    try {
      final remaining = await showLibraryBatchDialog(
        context: context,
        controller: controller,
        repository: repository,
        view: view,
        mangaKeys: keys,
        action: pending?.action ?? action!,
        lifecycle: _editLifecycle,
        isCurrent: isCurrent,
      );
      if (isCurrent() && remaining != null) {
        setState(() {
          _selection
            ..clear()
            ..addAll(remaining);
          _selecting = remaining.isNotEmpty;
        });
      }
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _editLifecycle = useValueNotifier(0);
    useEffect(() {
      _bindRepository();
      return null;
    }, const []);
    useOnListenableChange(widget.controller, _catalogChanged);
    _search = useTextEditingController(keys: [_repository]);
    useListenable(_search);
    useOnAppLifecycleStateChange((previous, state) {
      if (state == AppLifecycleState.resumed) unawaited(_refresh());
    });
    final AsyncValue<LibraryView?> snapshot = _repository == null
        ? const AsyncData(null)
        : ref.watch(libraryViewProvider(_repository!));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: CustomScrollView(
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: _refresh),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.list(
                children: [
                  if (_opening || widget.controller?.busy == true) ...[
                    const CupertinoActivityIndicator(),
                    const SizedBox(height: 12),
                  ],
                  if (widget.controller?.error case final error?)
                    Text(
                      error,
                      style: TextStyle(
                        color: AppColors.error.resolveFrom(context),
                      ),
                    ),
                  if (_refreshError case final error?)
                    Text(
                      error,
                      style: TextStyle(
                        color: AppColors.error.resolveFrom(context),
                      ),
                    ),
                  if (_openError case final error?)
                    Text(
                      error,
                      style: TextStyle(
                        color: AppColors.error.resolveFrom(context),
                      ),
                    ),
                  if (widget.controller case final controller?)
                    if (controller.status != ServiceStatus.ready)
                      _connection(controller),
                  if (_repository != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CupertinoButton(
                        onPressed: () => unawaited(_refresh()),
                        child: const Text('刷新服务端书架'),
                      ),
                    ),
                ],
              ),
            ),
            _libraryContents(snapshot),
          ],
        ),
      ),
    );
  }

  Widget _libraryContents(AsyncValue<LibraryView?> snapshot) {
    if (snapshot.hasError && !snapshot.hasValue) {
      return SliverToBoxAdapter(
        child: Column(
          children: [
            Text('未能读取服务端书架，请重试。'),
            CupertinoButton(
              onPressed: _retryStorage,
              child: const Text('重试读取书架'),
            ),
          ],
        ),
      );
    }
    if (_repository != null && !snapshot.hasValue) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: Text('正在读取书架')),
        ),
      );
    }
    final view = snapshot.value;
    if (view == null) {
      return SliverToBoxAdapter(
        child: _repository == null && widget.controller != null
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Text('连接并确认身份后显示服务端书架。'),
              )
            : _empty(),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(
            children: [
              if (snapshot.hasError) Text('未能读取服务端书架，当前显示上次确认的结果。'),
              _categoryControls(view),
            ],
          ),
        ),
        if (view.entries.isEmpty)
          SliverToBoxAdapter(child: _empty())
        else
          _library(view),
      ],
    );
  }

  Widget _connection(CatalogController controller) {
    final needsLogin = controller.accessPaused;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (controller.status) {
            ServiceStatus.connecting => '正在连接服务',
            ServiceStatus.loginRequired => '登录后继续阅读',
            ServiceStatus.denied => '当前账号无法访问',
            _ => '连接服务后打开书架漫画',
          }),
          CupertinoButton(
            onPressed: controller.busy
                ? null
                : needsLogin
                ? widget.onAuthenticate
                : widget.onConnect,
            child: Text(needsLogin ? '登录' : '连接服务'),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 64),
    child: Column(
      children: [
        Icon(
          CupertinoIcons.book,
          size: 64,
          color: CupertinoTheme.of(context).primaryColor,
        ),
        const SizedBox(height: 24),
        Text(
          '书架还是空的',
          style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle,
        ),
        const SizedBox(height: 12),
        const Text('从浏览打开漫画详情，收藏喜欢的漫画。'),
        const SizedBox(height: 24),
        CupertinoButton.filled(
          onPressed: widget.onBrowse,
          child: const Text('去浏览'),
        ),
      ],
    ),
  );

  String? _filterFor(LibraryView view) {
    final selected = _categoryFilter;
    if (selected != null &&
        selected.isNotEmpty &&
        !view.categories.any((category) => category.id == selected)) {
      return null;
    }
    return selected;
  }

  Widget _categoryControls(LibraryView view) {
    final repository = _repository;
    final pending =
        repository != null && hasPendingLibraryCategoryEdit(repository);
    final batch = repository == null ? null : pendingLibraryBatch(repository);
    final available =
        !_editing &&
        !_opening &&
        _retryingMetadata == null &&
        widget.controller?.status == ServiceStatus.ready &&
        widget.controller?.busy == false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending) ...[
          Text('有一项分类修改尚未处理。请继续原修改，当前列表仅显示服务端已确认的结果。'),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton.tinted(
              onPressed: available
                  ? () => unawaited(_editCategories(view))
                  : null,
              child: const Text('处理未确认修改'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (batch != null) ...[
          Text('有未完成的批量操作，当前列表仅显示服务端已确认的结果。'),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoButton.tinted(
              key: const ValueKey('library-resume-batch'),
              onPressed: available ? () => unawaited(_batch(view)) : null,
              child: const Text('继续处理批量操作'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            onPressed: available && !pending && batch == null && !_selecting
                ? () => unawaited(_editCategories(view))
                : null,
            child: const Text('管理分类'),
          ),
        ),
        ChoiceField<String>(
          key: const ValueKey('library-category-filter'),
          label: '分类',
          value: _filterFor(view),
          options: {
            null: '全部',
            '': '未分类',
            for (final category in view.categories) category.id: category.name,
          },
          onChanged: (value) => setState(() => _categoryFilter = value),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _library(LibraryView view) {
    final entries = view.entries;
    final query = _search.text.trim().toLowerCase();
    final filter = _filterFor(view);
    final visible = entries.where((entry) {
      if (filter == '' && entry.categoryIds.isNotEmpty) return false;
      if (filter != null &&
          filter.isNotEmpty &&
          !entry.categoryIds.contains(filter)) {
        return false;
      }
      final text = [
        entry.title,
        entry.snapshot.author,
        entry.sourceName,
      ].join('\n').toLowerCase();
      return text.contains(query);
    }).toList();
    visible.sort((a, b) {
      final result = switch (_sort) {
        _LibrarySort.added => b.addedAt.compareTo(a.addedAt),
        _LibrarySort.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
      };
      return result == 0 ? a.mangaKey.compareTo(b.mangaKey) : result;
    });
    final controller = widget.controller;
    final canOpen =
        !_selecting &&
        !_opening &&
        _retryingMetadata == null &&
        controller?.busy == false &&
        controller?.status == ServiceStatus.ready;
    final repository = _repository;
    final canCategorize =
        canOpen &&
        !_editing &&
        repository != null &&
        !hasPendingLibraryCategoryEdit(repository) &&
        pendingLibraryBatch(repository) == null;
    final canSelect =
        !_opening &&
        !_editing &&
        _retryingMetadata == null &&
        controller?.busy == false &&
        controller?.status == ServiceStatus.ready;
    final hasPending =
        repository != null &&
        (hasPendingLibraryCategoryEdit(repository) ||
            pendingLibraryBatch(repository) != null);
    final selected = _selectedKeys(view);
    final visibleKeys = visible.map((entry) => entry.mangaKey).toSet();
    final hiddenCount = selected.difference(visibleKeys).length;
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(
            children: [
              CupertinoSearchTextField(
                controller: _search,
                placeholder: '漫画、作者或漫画源',
              ),
              Row(
                children: [
                  Expanded(
                    child: ChoiceField<_LibrarySort>(
                      label: '排序',
                      value: _sort,
                      options: {
                        _LibrarySort.added: '最近收藏',
                        _LibrarySort.title: '标题',
                      },
                      onChanged: (value) {
                        if (value != null) setState(() => _sort = value);
                      },
                    ),
                  ),
                  CupertinoButton(
                    key: const ValueKey('library-selection-toggle'),
                    onPressed: canSelect && (_selecting || !hasPending)
                        ? () => setState(() {
                            _selecting = !_selecting;
                            if (!_selecting) _selection.clear();
                          })
                        : null,
                    child: Text(_selecting ? '退出选择' : '选择漫画'),
                  ),
                ],
              ),
              Text('收藏 ${entries.length} 部 · 当前显示 ${visible.length} 部'),
              if (_selecting) ...[
                Text('已选 ${selected.length} 部 · 当前隐藏 $hiddenCount 部'),
                if (hiddenCount > 0) const Text('批量操作包含隐藏选中的漫画，请在确认清单中核对。'),
                Wrap(
                  spacing: 8,
                  children: [
                    CupertinoButton(
                      key: const ValueKey('library-select-visible'),
                      onPressed: canSelect && visible.isNotEmpty
                          ? () => setState(() => _selection.addAll(visibleKeys))
                          : null,
                      child: const Text('全选当前显示'),
                    ),
                    CupertinoButton(
                      key: const ValueKey('library-deselect-visible'),
                      onPressed:
                          canSelect &&
                              selected.intersection(visibleKeys).isNotEmpty
                          ? () => setState(
                              () => _selection.removeAll(visibleKeys),
                            )
                          : null,
                      child: const Text('取消当前显示选择'),
                    ),
                    CupertinoButton(
                      key: const ValueKey('library-clear-selection'),
                      onPressed: canSelect && selected.isNotEmpty
                          ? () => setState(_selection.clear)
                          : null,
                      child: const Text('清空选择'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (action, id, label) in const [
                      (
                        LibraryBatchAction.addCategories,
                        'add-categories',
                        '批量添加分类',
                      ),
                      (
                        LibraryBatchAction.removeCategories,
                        'remove-categories',
                        '批量移出分类',
                      ),
                      (
                        LibraryBatchAction.removeFavorites,
                        'remove-favorites',
                        '批量移出书架',
                      ),
                    ])
                      CupertinoButton(
                        key: ValueKey('library-batch-$id'),
                        onPressed:
                            canSelect &&
                                !hasPending &&
                                selected.isNotEmpty &&
                                (action == LibraryBatchAction.removeFavorites ||
                                    view.categories.isNotEmpty)
                            ? () => unawaited(_batch(view, action: action))
                            : null,
                        child: Text(label),
                      ),
                  ],
                ),
              ],
              for (final entry in visible)
                if (repository?.client.hasPendingMetadata(entry.mangaKey) ==
                    true)
                  CupertinoButton(
                    key: ValueKey(('library-retry-metadata', entry.mangaKey)),
                    onPressed: canOpen && !_editing
                        ? () => unawaited(_retryMetadata(entry))
                        : null,
                    child: Text(
                      _retryingMetadata == entry.mangaKey
                          ? '正在重试保存书架资料'
                          : '重试保存书架资料',
                    ),
                  ),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('没有找到收藏', textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 2 / 3,
            ),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final entry = visible[index];
              final draft =
                  controller?.readingDraftResume(entry.mangaKey) != null;
              return MangaCoverTile(
                key: ValueKey(entry.mangaKey),
                title: entry.title,
                entry: entry,
                covers: _covers,
                selected: _selecting ? selected.contains(entry.mangaKey) : null,
                onLongPress: canSelect && !_selecting && !hasPending
                    ? () => setState(() {
                        _selecting = true;
                        _selection.add(entry.mangaKey);
                      })
                    : null,
                onPressed: _selecting
                    ? canSelect
                          ? () => _toggleSelection(entry.mangaKey)
                          : null
                    : canOpen
                    ? () => unawaited(_open(entry))
                    : null,
                badge: _selecting
                    ? CupertinoCheckbox(
                        key: ValueKey(('library-select', entry.mangaKey)),
                        value: selected.contains(entry.mangaKey),
                        onChanged: canSelect
                            ? (_) => _toggleSelection(entry.mangaKey)
                            : null,
                      )
                    : null,
                continueKey: ValueKey(('library-continue', entry.mangaKey)),
                continueLabel: !_selecting && (entry.resume != null || draft)
                    ? draft
                          ? '继续阅读（未保存）：${entry.title}'
                          : '继续阅读：${entry.title}'
                    : null,
                onContinue: canOpen
                    ? () => unawaited(_open(entry, continueReading: true))
                    : null,
                menu: _selecting
                    ? null
                    : CupertinoMenuAnchor(
                        key: ValueKey(('library-more', entry.mangaKey)),
                        menuChildren: [
                          CupertinoMenuItem(
                            onPressed: canCategorize
                                ? () => unawaited(
                                    _editCategories(view, entry: entry),
                                  )
                                : null,
                            leading: Icon(
                              CupertinoIcons.folder,
                              semanticLabel: '设置分类：${entry.title}',
                            ),
                            child: const Text('设置分类'),
                          ),
                          CupertinoMenuItem(
                            onPressed: canOpen && !_editing
                                ? () => unawaited(_migrate(entry))
                                : null,
                            child: const Text('迁移到其他漫画源'),
                          ),
                        ],
                        builder: (context, menu, child) => CupertinoButton(
                          onPressed: canOpen && !_editing
                              ? () => menu.isOpen ? menu.close() : menu.open()
                              : null,
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            CupertinoIcons.ellipsis,
                            color: const Color(0xFFFFFFFF),
                            shadows: const [Shadow(blurRadius: 4)],
                            semanticLabel: '更多操作：${entry.title}',
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _disposing = true;
    _editLifecycle.value++;
    super.dispose();
  }
}
