import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/library_repository.dart';
import '../../data/business_state_client.dart';
import '../../data/cover_repository.dart';
import '../covers/custom_cover.dart';
import '../browse/catalog_controller.dart';
import '../browse/manga_details_page.dart';
import '../reader/reader_recovery.dart';
import '../reader/chapter_reader_route.dart';
import '../reader/chapter_sequence.dart';
import '../migration/migration_controller.dart';
import '../migration/migration_page.dart';
import 'category_dialogs.dart';
import 'library_batch.dart';
import 'library_batch_dialogs.dart';

enum _LibrarySort { added, title }

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.controller,
    required this.onBrowse,
    required this.onConnect,
    required this.onAuthenticate,
    this.onAuthenticateReader,
  });

  final CatalogController? controller;
  final VoidCallback onBrowse;
  final VoidCallback onConnect;
  final VoidCallback onAuthenticate;
  final ReaderAuthentication? onAuthenticateReader;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> with WidgetsBindingObserver {
  final _search = TextEditingController();
  LibraryRepository? _repository;
  CoverRepository? _covers;
  Stream<LibraryView>? _views;
  final _editLifecycle = ValueNotifier(0);
  String? _categoryFilter;
  bool _editing = false;
  bool _disposing = false;
  _LibrarySort _sort = _LibrarySort.added;
  int _retry = 0;
  ServiceStatus? _lastStatus;
  bool _opening = false;
  bool _catalogChangeScheduled = false;
  String? _refreshError;
  String? _openError;
  String? _retryingMetadata;
  Object? _metadataAttempt;
  final _selection = <String>{};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.addListener(_catalogChanged);
    _bindRepository();
  }

  @override
  void didUpdateWidget(LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_catalogChanged);
      widget.controller?.addListener(_catalogChanged);
    }
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
    final status = widget.controller?.status;
    final reconnected = status == ServiceStatus.ready && _lastStatus != status;
    _lastStatus = status;
    setState(_bindRepository);
    if (reconnected) unawaited(_refresh());
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
    _views = next?.watchView();
    _categoryFilter = null;
    _search.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
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

  void _retryStorage() => setState(() {
    _retry++;
    _views = _repository?.watchView();
  });

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
        if (notice != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(notice)));
        }
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => MangaDetailsPage(
              controller: controller,
              manga: details.manga,
              chapters: details.chapters,
              source: details.source,
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
        final readerRoute = MaterialPageRoute<void>(
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
        MaterialPageRoute(
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
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_opening || widget.controller?.busy == true) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          if (widget.controller?.error case final error?) _notice(error),
          if (_refreshError case final error?) _notice(error),
          if (_openError case final error?) _notice(error),
          if (widget.controller case final controller?)
            if (controller.status != ServiceStatus.ready)
              _connection(controller),
          if (_repository != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => unawaited(_refresh()),
                icon: const Icon(Icons.sync),
                label: const Text('刷新服务端书架'),
              ),
            ),
          StreamBuilder<LibraryView>(
            key: ValueKey((_repository, _repository?.identity.key, _retry)),
            stream: _views,
            builder: (context, snapshot) {
              if (snapshot.hasError && !snapshot.hasData) {
                return Column(
                  children: [
                    _notice('未能读取服务端书架，请重试。'),
                    TextButton(
                      onPressed: _retryStorage,
                      child: const Text('重试读取书架'),
                    ),
                  ],
                );
              }
              if (_views != null && !snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('正在读取书架')),
                );
              }
              final view = snapshot.data;
              if (view == null) {
                return _repository == null && widget.controller != null
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('连接并确认身份后显示服务端书架。'),
                      )
                    : _empty();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (snapshot.hasError) _notice('未能读取服务端书架，当前显示上次确认的结果。'),
                  _categoryControls(view),
                  if (view.entries.isEmpty) _empty() else _library(view),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

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
          TextButton.icon(
            onPressed: controller.busy
                ? null
                : needsLogin
                ? widget.onAuthenticate
                : widget.onConnect,
            icon: Icon(needsLogin ? Icons.login : Icons.refresh),
            label: Text(needsLogin ? '登录' : '连接服务'),
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
          Icons.auto_stories_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text('书架还是空的', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text('从浏览打开漫画详情，收藏喜欢的漫画。'),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: widget.onBrowse,
          icon: const Icon(Icons.explore_outlined),
          label: const Text('去浏览'),
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
    final selected = _filterFor(view);
    Widget chip(String? value, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: label,
        child: ChoiceChip(
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          selected: selected == value,
          onSelected: (_) => setState(() => _categoryFilter = value),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending) ...[
          _notice('有一项分类修改尚未处理。请继续原修改，当前列表仅显示服务端已确认的结果。'),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: available
                  ? () => unawaited(_editCategories(view))
                  : null,
              icon: const Icon(Icons.pending_actions),
              label: const Text('处理未确认修改'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (batch != null) ...[
          _notice('有未完成的批量操作，当前列表仅显示服务端已确认的结果。'),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const ValueKey('library-resume-batch'),
              onPressed: available ? () => unawaited(_batch(view)) : null,
              icon: const Icon(Icons.pending_actions),
              label: const Text('继续处理批量操作'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: available && !pending && batch == null && !_selecting
                ? () => unawaited(_editCategories(view))
                : null,
            icon: const Icon(Icons.folder_outlined),
            label: const Text('管理分类'),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip(null, '全部'),
              chip('', '未分类'),
              for (final category in view.categories)
                chip(category.id, category.name),
            ],
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: '搜索书架',
            hintText: '漫画、作者或漫画源',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<_LibrarySort>(
          initialValue: _sort,
          decoration: const InputDecoration(
            labelText: '排序',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: _LibrarySort.added, child: Text('最近收藏')),
            DropdownMenuItem(value: _LibrarySort.title, child: Text('标题')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _sort = value);
          },
        ),
        const SizedBox(height: 16),
        Text('收藏 ${entries.length} 部 · 当前显示 ${visible.length} 部'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('library-selection-toggle'),
            onPressed: canSelect && (_selecting || !hasPending)
                ? () => setState(() {
                    _selecting = !_selecting;
                    if (!_selecting) _selection.clear();
                  })
                : null,
            icon: Icon(_selecting ? Icons.close : Icons.checklist),
            label: Text(_selecting ? '退出选择' : '选择漫画'),
          ),
        ),
        if (_selecting) ...[
          Text('已选 ${selected.length} 部 · 当前隐藏 $hiddenCount 部'),
          if (hiddenCount > 0) const Text('批量操作包含隐藏选中的漫画，请在确认清单中核对。'),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                key: const ValueKey('library-select-visible'),
                onPressed: canSelect && visible.isNotEmpty
                    ? () => setState(() => _selection.addAll(visibleKeys))
                    : null,
                child: const Text('全选当前显示'),
              ),
              TextButton(
                key: const ValueKey('library-deselect-visible'),
                onPressed:
                    canSelect && selected.intersection(visibleKeys).isNotEmpty
                    ? () => setState(() => _selection.removeAll(visibleKeys))
                    : null,
                child: const Text('取消当前显示选择'),
              ),
              TextButton(
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
              OutlinedButton.icon(
                key: const ValueKey('library-batch-add-categories'),
                onPressed:
                    canSelect &&
                        !hasPending &&
                        selected.isNotEmpty &&
                        view.categories.isNotEmpty
                    ? () => unawaited(
                        _batch(view, action: LibraryBatchAction.addCategories),
                      )
                    : null,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('批量添加分类'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('library-batch-remove-categories'),
                onPressed:
                    canSelect &&
                        !hasPending &&
                        selected.isNotEmpty &&
                        view.categories.isNotEmpty
                    ? () => unawaited(
                        _batch(
                          view,
                          action: LibraryBatchAction.removeCategories,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.folder_off_outlined),
                label: const Text('批量移出分类'),
              ),
              FilledButton.tonalIcon(
                key: const ValueKey('library-batch-remove-favorites'),
                onPressed: canSelect && !hasPending && selected.isNotEmpty
                    ? () => unawaited(
                        _batch(
                          view,
                          action: LibraryBatchAction.removeFavorites,
                        ),
                      )
                    : null,
                icon: const Icon(Icons.bookmark_remove_outlined),
                label: const Text('批量移出书架'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('没有找到收藏', textAlign: TextAlign.center),
          ),
        for (final entry in visible)
          Card(
            key: ValueKey(entry.mangaKey),
            child: ListTile(
              leading: _selecting
                  ? Checkbox(
                      key: ValueKey(('library-select', entry.mangaKey)),
                      value: selected.contains(entry.mangaKey),
                      onChanged: canSelect
                          ? (_) => _toggleSelection(entry.mangaKey)
                          : null,
                    )
                  : CustomCover(repository: _covers!, cover: entry.customCover),
              title: Text(entry.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      if (entry.snapshot.author.isNotEmpty)
                        entry.snapshot.author,
                      '${entry.sourceName} · ${entry.sourceLang}',
                      '分类：${entry.categoryIds.isEmpty ? '未分类' : view.categories.where((category) => entry.categoryIds.contains(category.id)).map((category) => category.name).join('、')}',
                    ].join('\n'),
                  ),
                  if (repository?.client.hasPendingMetadata(entry.mangaKey) ==
                      true)
                    TextButton(
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
                ],
              ),
              trailing: _selecting
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (entry.resume != null ||
                            controller?.readingDraftResume(entry.mangaKey) !=
                                null)
                          IconButton(
                            key: ValueKey(('library-continue', entry.mangaKey)),
                            tooltip:
                                controller?.readingDraftResume(
                                      entry.mangaKey,
                                    ) !=
                                    null
                                ? '继续阅读（未保存）：${entry.title}'
                                : '继续阅读：${entry.title}',
                            onPressed: canOpen
                                ? () => unawaited(
                                    _open(entry, continueReading: true),
                                  )
                                : null,
                            icon: const Icon(Icons.play_arrow),
                          ),
                        IconButton(
                          tooltip: '设置分类：${entry.title}',
                          onPressed: canCategorize
                              ? () => unawaited(
                                  _editCategories(view, entry: entry),
                                )
                              : null,
                          icon: const Icon(Icons.folder_outlined),
                        ),
                        PopupMenuButton<String>(
                          key: ValueKey(('library-more', entry.mangaKey)),
                          tooltip: '更多操作：${entry.title}',
                          enabled: canOpen && !_editing,
                          onSelected: (value) {
                            if (value == 'migrate') unawaited(_migrate(entry));
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'migrate',
                              child: Text('迁移到其他漫画源'),
                            ),
                          ],
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
              onTap: _selecting
                  ? canSelect
                        ? () => _toggleSelection(entry.mangaKey)
                        : null
                  : canOpen
                  ? () => unawaited(_open(entry))
                  : null,
              onLongPress: canSelect && !_selecting && !hasPending
                  ? () => setState(() {
                      _selecting = true;
                      _selection.add(entry.mangaKey);
                    })
                  : null,
            ),
          ),
      ],
    );
  }

  Widget _notice(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _disposing = true;
    _editLifecycle.value++;
    _editLifecycle.dispose();
    widget.controller?.removeListener(_catalogChanged);
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }
}
