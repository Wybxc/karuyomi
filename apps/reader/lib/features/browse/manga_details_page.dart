import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../widgets/app_appearance.dart';

import '../../widgets/app_page_route.dart';
import '../../widgets/choice_field.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/reading_progress.dart';
import '../../data/library_repository.dart';
import '../library/library_providers.dart';
import '../../data/cover_repository.dart';
import '../covers/custom_cover.dart';
import '../covers/custom_cover_editor.dart';
import '../../data/business_state_client.dart';
import '../../diagnostics/reader_baseline.dart';
import 'catalog_controller.dart';
import '../bookmarks/chapter_bookmarks_controller.dart';
import '../bookmarks/bookmark_status.dart';
import '../reader/chapter_reader_route.dart';
import '../reader/chapter_sequence.dart';
import '../reader/reader_recovery.dart';
import '../progress/chapter_read_batch.dart';
import '../progress/chapter_read_controller.dart';
import '../progress/chapter_read_dialog.dart';
import '../migration/migration_controller.dart';
import '../migration/migration_page.dart';

class const MangaDetailsPage({
  super.key,
  required final CatalogController controller,
  required final MangaEntry manga,
  required final List<ChapterEntry> chapters,
  required final CatalogSourceRef source,
  final ReaderAuthentication? onAuthenticateReader,
  final String? notice,
}) extends StatefulHookConsumerWidget {
  @override
  ConsumerState<MangaDetailsPage> createState() => _MangaDetailsPageState();
}

enum _ChapterReadFilter { all, read, unread }

class _MangaDetailsPageState extends ConsumerState<MangaDetailsPage> {
  CatalogController get controller => widget.controller;
  MangaEntry get manga => widget.manga;
  List<ChapterEntry> get chapters => widget.chapters;
  CatalogSourceRef get source => widget.source;
  ChapterSequence? _sequence;
  MangaResume? _resume;
  String? _resumeError;
  bool _resumeReadFailed = false;
  bool _loadingResume = false;
  int _resumeRequest = 0;
  SequenceChapter? _failedChapter;
  String? _chapterOpenError;
  bool _opening = false;
  LibraryRepository? _library;
  CoverRepository? _covers;
  late ValueNotifier<int> _coverLifecycle;
  bool _editingCover = false;
  bool _savingFavorite = false;
  bool _migrating = false;
  String? _favoriteError;
  ChapterBookmarksController? _bookmarks;
  bool _onlyBookmarks = false;
  ChapterReadController? _chapterRead;
  _ChapterReadFilter _readFilter = _ChapterReadFilter.all;
  bool _detailsExpired = false;
  bool _selectingChapters = false;
  bool _markingChapters = false;
  final _chapterSelection = <String>{};
  int _unmatchedChapterSelectionCount = 0;
  String? _rangeStart;
  String? _rangeEnd;
  late TextEditingController _chapterSearch;
  ChapterOrder _chapterOrder = ChapterOrder.source;
  bool _chapterOrderChosen = false;
  final _chapterNameCounts = <String, int>{};
  final _chapterUrlCounts = <String, int>{};

  void _initialize() {
    final build = controller.activeBuild;
    if (build != null) {
      _sequence = ChapterSequence(
        packageName: build.packageName,
        sourceId: source.sourceId,
        mangaUrl: manga.url,
        chapters: chapters.map((chapter) => chapter.snapshot),
      );
      for (final chapter in _sequence!.entries) {
        _chapterNameCounts.update(
          chapter.name,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        _chapterUrlCounts.update(
          chapter.snapshot.url,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      _library = controller.library;
      if (_library != null) _covers = CoverRepository(_library!.client);
      final repository = controller.bookmarks;
      if (repository != null) {
        _bookmarks = ChapterBookmarksController(
          repository: repository,
          mangaKey: _sequence!.mangaKey,
          onConfirmed: () async {
            await _chapterRead?.refreshAfterCurrent();
          },
          isCurrent: () =>
              mounted &&
              !_detailsExpired &&
              controller.status == ServiceStatus.ready &&
              controller.isCurrentSource(source) &&
              identical(controller.bookmarks, repository),
        );
        unawaited(_bookmarks!.refresh());
      }
      final progress = controller.readingProgress;
      if (progress != null) {
        _chapterRead = ChapterReadController(
          repository: progress,
          mangaKey: _sequence!.mangaKey,
          isCurrent: () =>
              mounted &&
              !_detailsExpired &&
              controller.status == ServiceStatus.ready &&
              controller.isCurrentSource(source) &&
              identical(controller.readingProgress, progress),
        );
        unawaited(_chapterRead!.refresh());
      }
      unawaited(_refreshResume());
    }
  }

  @override
  void didUpdateWidget(MangaDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller) ||
        !identical(oldWidget.source, widget.source) ||
        !identical(oldWidget.manga, widget.manga) ||
        !identical(oldWidget.chapters, widget.chapters)) {
      _detailsExpired = true;
      _chapterSelection.clear();
      _selectingChapters = false;
      _bookmarks?.checkCurrent();
      _chapterRead?.checkCurrent();
      _detailsChanged();
    }
  }

  void _detailsChanged() {
    if (!mounted) return;
    _coverLifecycle.value++;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _catalogChanged() {
    final progress = _chapterRead;
    if (!_detailsExpired &&
        (controller.status != ServiceStatus.ready ||
            !controller.isCurrentSource(source) ||
            (_library != null &&
                !identical(controller.library?.client, _library?.client)) ||
            (progress != null &&
                !identical(controller.readingProgress, progress.repository)))) {
      _detailsExpired = true;
      _chapterSelection.clear();
      _selectingChapters = false;
      _detailsChanged();
    }
    _bookmarks?.checkCurrent();
    progress?.checkCurrent();
  }

  void _lifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshResume());
      unawaited(_bookmarks?.refresh());
      unawaited(_chapterRead?.refresh());
      final key = _sequence?.mangaKey;
      final library = _library;
      if (key != null && library != null) {
        unawaited(
          library.contains(key).then<void>((_) {}, onError: (Object _) {}),
        );
      }
    }
  }

  @override
  void dispose() {
    _coverLifecycle.value++;
    _bookmarks?.dispose();
    _chapterRead?.dispose();
    super.dispose();
  }

  Future<void> _refreshResume() async {
    final catalog = controller;
    final sequence = _sequence;
    final repository = catalog.readingProgress;
    if (sequence == null || repository == null) return;
    bool isCurrent() =>
        mounted &&
        !_detailsExpired &&
        identical(controller, catalog) &&
        identical(_sequence, sequence) &&
        identical(catalog.readingProgress, repository) &&
        catalog.status == ServiceStatus.ready &&
        catalog.isCurrentSource(source);
    if (!isCurrent()) return;
    final request = ++_resumeRequest;
    setState(() => _loadingResume = true);
    MangaResume? resume;
    String? error;
    var readFailed = false;
    try {
      final confirmed = await repository.loadResume(sequence.mangaKey);
      resume = catalog.readingDraftResume(sequence.mangaKey) ?? confirmed;
    } catch (_) {
      resume = catalog.readingDraftResume(sequence.mangaKey);
      error = '未能读取服务端阅读位置，仍可从章节列表打开。';
      readFailed = true;
    }
    if (!isCurrent() || request != _resumeRequest) return;
    if (resume != null &&
        !sequence.entries.any((entry) => entry.key == resume!.chapterKey)) {
      error = '章节清单已变化，无法确定上次章节；请从列表选择。';
      resume = null;
    }
    setState(() {
      _loadingResume = false;
      _resume = resume;
      _resumeError = error;
      _resumeReadFailed = readFailed;
      // A user's list choice lasts for this detail page. Until then, the same
      // resume order supplies both the list and the reader's initial order.
      if (!_chapterOrderChosen && (resume != null || error == null)) {
        _chapterOrder = resume?.reversedOrder == true
            ? ChapterOrder.reversed
            : ChapterOrder.source;
      }
    });
  }

  Future<void> _retryProgress() async {
    await controller.flushReadingProgress(explicitRetry: true);
    await _refreshResume();
  }

  Future<void> _setFavorite(bool favorite) async {
    final repository = _library;
    final chapterRead = _chapterRead;
    final build = controller.activeBuild;
    final selectedSource = controller.activeSource;
    if (_savingFavorite ||
        _editingCover ||
        repository == null ||
        build == null ||
        selectedSource == null ||
        !controller.isCurrentSource(source) ||
        controller.library?.identity.key != repository.identity.key) {
      return;
    }
    setState(() {
      _savingFavorite = true;
      _favoriteError = null;
    });
    try {
      await repository.setFavorite(
        packageName: build.packageName,
        sourceId: selectedSource.id,
        sourceName: selectedSource.name,
        sourceLang: selectedSource.lang,
        manga: manga.snapshot,
        favorite: favorite,
      );
      if (mounted && identical(_chapterRead, chapterRead)) {
        await chapterRead?.refreshAfterCurrent();
      }
    } catch (failure) {
      var message = '收藏未能保存，请重试；仍可继续阅读。';
      if (failure is BusinessStateException &&
          failure.conflictedChapterKey != null) {
        message = '此作品有阅读进度冲突，请重新打开相关章节后再修改收藏。';
      } else if (failure is BusinessStateException && failure.conflict) {
        try {
          await repository.contains(_sequence!.mangaKey);
          message = '此作品已在其他设备更新，已重新读取；请确认收藏状态后重试。';
        } catch (_) {
          message = '此作品已在其他设备更新，请刷新书架后重试。';
        }
      }
      if (mounted) setState(() => _favoriteError = message);
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  Future<void> _migrate() async {
    final build = controller.activeBuild;
    final selectedSource = controller.activeSource;
    final client = _library?.client;
    if (_migrating ||
        _opening ||
        _savingFavorite ||
        _editingCover ||
        _detailsExpired ||
        client == null ||
        !identical(controller.library?.client, client) ||
        _sequence == null ||
        build == null ||
        selectedSource == null ||
        controller.busy ||
        controller.status != ServiceStatus.ready ||
        !controller.isCurrentSource(source)) {
      return;
    }
    final seed = MigrationSeed(
      metadata: wire.LibraryMetadata(
        packageName: build.packageName,
        sourceId: selectedSource.id,
        sourceName: selectedSource.name,
        sourceLang: selectedSource.lang,
        manga: manga.snapshot,
      ),
      sequence: _sequence,
    );
    setState(() => _migrating = true);
    try {
      await Navigator.of(context).push<void>(
        AppPageRoute(
          builder: (_) =>
              MigrationPage(catalog: controller, client: client, seed: seed),
        ),
      );
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  Future<void> _editCover() async {
    final repository = _covers;
    final chapterRead = _chapterRead;
    final sequence = _sequence;
    final catalog = controller;
    final selectedSource = source;
    final route = ModalRoute.of(context);
    if (_editingCover ||
        _savingFavorite ||
        _opening ||
        repository == null ||
        sequence == null) {
      return;
    }
    final identity = repository.identity.key;
    bool current() =>
        mounted &&
        !_detailsExpired &&
        identical(widget.controller, catalog) &&
        identical(catalog.library?.client, repository.client) &&
        repository.identity.key == identity &&
        catalog.status == ServiceStatus.ready &&
        catalog.isCurrentSource(selectedSource) &&
        route?.isActive == true;
    if (!current()) return;
    setState(() => _editingCover = true);
    try {
      final saved = await showCustomCoverEditor(
        context: context,
        controller: catalog,
        repository: repository,
        mangaKey: sequence.mangaKey,
        lifecycle: _coverLifecycle,
        isCurrent: current,
      );
      if (saved == true && current() && identical(_chapterRead, chapterRead)) {
        await chapterRead?.refreshAfterCurrent();
      }
    } finally {
      if (mounted) setState(() => _editingCover = false);
    }
  }

  Widget _favoriteControl() {
    final snapshot =
        _library == null ||
            _sequence == null ||
            !identical(controller.library, _library)
        ? const AsyncData<wire.MangaState?>(null)
        : ref.watch(mangaStateProvider(_library!.client, _sequence!.mangaKey));
    final state = snapshot.value;
    final favorite = state?.favorite ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CustomCover(
              repository: _covers!,
              cover: state?.hasCustomCover() == true
                  ? state!.customCover
                  : null,
              width: 96,
              height: 128,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CupertinoButton(
                  onPressed:
                      state == null ||
                          _savingFavorite ||
                          _opening ||
                          _editingCover
                      ? null
                      : () => unawaited(_setFavorite(!favorite)),
                  child: Text(
                    _savingFavorite
                        ? '正在保存'
                        : favorite
                        ? '移出书架'
                        : '加入书架',
                  ),
                ),
                CupertinoButton(
                  key: const ValueKey('custom-cover-editor'),
                  onPressed:
                      state == null ||
                          _savingFavorite ||
                          _opening ||
                          _editingCover
                      ? null
                      : () => unawaited(_editCover()),
                  child: const Text('自定义封面'),
                ),
              ],
            ),
          ],
        ),
        if (_favoriteError != null || snapshot.hasError)
          Text(_favoriteError ?? '未能读取作品状态，请返回书架重试；仍可继续阅读。'),
      ],
    );
  }

  Future<void> _openChapter(BuildContext context, int index) async {
    if (!mounted ||
        _opening ||
        controller.busy ||
        _selectingChapters ||
        _detailsExpired) {
      return;
    }
    final catalog = controller;
    final selectedManga = manga;
    final selectedSource = source;
    final authenticate = widget.onAuthenticateReader;
    final progress = catalog.readingProgress;
    final route = ModalRoute.of(context);
    final sequence = _sequence;
    if (sequence == null || index < 0 || index >= sequence.entries.length) {
      return;
    }
    bool isCurrent() =>
        mounted &&
        !_detailsExpired &&
        identical(controller, catalog) &&
        identical(manga, selectedManga) &&
        identical(source, selectedSource) &&
        identical(_sequence, sequence) &&
        identical(catalog.readingProgress, progress) &&
        catalog.status == ServiceStatus.ready &&
        catalog.isCurrentSource(selectedSource) &&
        route?.isCurrent == true &&
        route?.isActive == true;
    if (!isCurrent()) return;
    setState(() {
      _opening = true;
      _failedChapter = null;
      _chapterOpenError = null;
    });
    final selected = sequence.entries[index];
    final initialOrder = _chapterOrderChosen || _resume != null
        ? _chapterOrder
        : null;
    ReaderBaselineScope.read(context)?.event('navigation', {
      'action': 'open_chapter',
      'targetChapterKey': selected.key,
    });
    final opened = await catalog.openChapter(
      selectedManga,
      ChapterEntry(selected.snapshot),
      reference: selectedSource,
      logicalChapterKey: selected.key,
    );
    if (opened == null) {
      if (mounted) {
        setState(() {
          _opening = false;
          if (isCurrent()) {
            _failedChapter = selected;
            _chapterOpenError = catalog.error ?? '未能打开章节，请重试。';
          }
        });
      }
      return;
    }
    if (!context.mounted || !isCurrent()) {
      await catalog.closeChapter(opened);
      if (mounted) setState(() => _opening = false);
      return;
    }
    try {
      final readerRoute = AppPageRoute<void>(
        builder: (_) => ChapterReaderRoute(
          catalog: catalog,
          manga: selectedManga,
          source: selectedSource,
          sequence: sequence,
          initialChapter: selected,
          initialOpened: opened,
          initialOrder: initialOrder,
          onAuthenticate: authenticate,
        ),
      );
      await Navigator.of(context).push<void>(readerRoute);
      await readerRoute.completed;
      await catalog.flushReadingProgress();
    } finally {
      // Also covers a route popped before its first Reader leaf mounted.
      await catalog.closeChapter(opened);
      if (mounted) {
        setState(() => _opening = false);
        if (!_detailsExpired && identical(controller, catalog)) {
          await _refreshResume();
          await _bookmarks?.refresh();
          await _chapterRead?.refresh();
        }
      }
    }
  }

  void _resetRange() {
    _rangeStart = null;
    _rangeEnd = null;
  }

  Future<void> _markChapters({bool? read}) async {
    final progress = _chapterRead;
    final sequence = _sequence;
    if (progress == null ||
        sequence == null ||
        _markingChapters ||
        _savingFavorite ||
        _bookmarks?.saving == true ||
        _opening ||
        !progress.available ||
        progress.busy) {
      return;
    }
    final repository = progress.repository;
    final pending = pendingChapterReadBatch(repository, sequence.mangaKey);
    final selectedChapters = sequence
        .ordered(_chapterOrder)
        .where((chapter) => _chapterSelection.contains(chapter.key))
        .toList();
    if (pending == null &&
        (read == null || !progress.loaded || selectedChapters.isEmpty)) {
      return;
    }
    final route = ModalRoute.of(context);
    bool isCurrent() =>
        mounted &&
        !_detailsExpired &&
        identical(_chapterRead, progress) &&
        identical(controller.readingProgress, repository) &&
        controller.status == ServiceStatus.ready &&
        controller.isCurrentSource(source) &&
        route?.isActive == true;
    final draft =
        pending ??
        ChapterReadBatchDraft(
          repository: repository,
          mangaKey: sequence.mangaKey,
          read: read!,
          revision: progress.revision,
          chapters: selectedChapters,
        );
    setState(() => _markingChapters = true);
    try {
      final remaining = await showChapterReadDialog(
        context: context,
        catalog: controller,
        progress: progress,
        draft: draft,
        isCurrent: isCurrent,
      );
      if (isCurrent() && remaining != null) {
        final currentKeys = sequence.entries
            .map((chapter) => chapter.key)
            .toSet();
        final matched = remaining.intersection(currentKeys);
        setState(() {
          _chapterSelection
            ..clear()
            ..addAll(matched);
          _unmatchedChapterSelectionCount = remaining.length - matched.length;
          _selectingChapters = matched.isNotEmpty;
          _resetRange();
        });
      }
    } finally {
      if (mounted) setState(() => _markingChapters = false);
    }
  }

  String? _chapterNumber(SequenceChapter chapter) {
    final snapshot = chapter.snapshot;
    final number = snapshot.chapterNumber;
    if (!snapshot.hasChapterNumber() || !number.isFinite || number < 0) {
      return null;
    }
    return number == number.truncateToDouble()
        ? number.toStringAsFixed(0)
        : number.toString();
  }

  String? _chapterSubtitle(SequenceChapter chapter) {
    final number = _chapterNumber(chapter);
    final scanlator = chapter.snapshot.scanlator.trim();
    final sameName = (_chapterNameCounts[chapter.name] ?? 0) > 1;
    final sameUrl = (_chapterUrlCounts[chapter.snapshot.url] ?? 0) > 1;
    final details = [
      if (number != null) '第 $number 章',
      if (scanlator.isNotEmpty) '扫描组：$scanlator',
      if (sameName) '同名章节',
      if (sameUrl) '重复链接',
      if (sameName || sameUrl) '来源第 ${chapter.sourceIndex + 1} 项',
    ];
    return details.isEmpty ? null : details.join(' · ');
  }

  void _toggleChapter(String key) => setState(() {
    if (!_chapterSelection.add(key)) _chapterSelection.remove(key);
  });

  List<Widget> _chapterReadControls(List<SequenceChapter> visible) {
    final progress = _chapterRead;
    if (progress == null) return [];
    final pending = pendingChapterReadBatch(
      progress.repository,
      progress.mangaKey,
    );
    final available =
        progress.available &&
        !_opening &&
        !_markingChapters &&
        !_savingFavorite &&
        _bookmarks?.saving != true &&
        !controller.busy;
    final canSelect = available && progress.loaded && !progress.busy;
    final visibleKeys = visible.map((chapter) => chapter.key).toSet();
    final hidden = _chapterSelection.difference(visibleKeys).length;
    final start = visibleKeys.contains(_rangeStart) ? _rangeStart : null;
    final end = visibleKeys.contains(_rangeEnd) ? _rangeEnd : null;
    Widget rangeEndpoint(
      String label,
      String key,
      String? value,
      ValueChanged<String?> change,
    ) => SizedBox(
      width: 280,
      child: ChoiceField<String>(
        key: ValueKey(key),
        label: label,
        value: value,
        options: {
          for (final chapter in visible)
            chapter.key: '${chapter.name} · 来源第 ${chapter.sourceIndex + 1} 项',
        },
        onChanged: canSelect ? change : null,
      ),
    );
    return [
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          CupertinoSlidingSegmentedControl<_ChapterReadFilter>(
            groupValue: _readFilter,
            disabledChildren: {
              if (!progress.loaded) ...{
                _ChapterReadFilter.read,
                _ChapterReadFilter.unread,
              },
            },
            children: {
              for (final (filter, label) in [
                (_ChapterReadFilter.all, '全部状态'),
                (_ChapterReadFilter.read, '已读'),
                (_ChapterReadFilter.unread, '未读'),
              ])
                filter: Text(
                  label,
                  key: ValueKey(('chapter-read-filter', filter.name)),
                ),
            },
            onValueChanged: (value) => setState(() {
              _readFilter = value!;
              _resetRange();
            }),
          ),
          CupertinoButton(
            key: const ValueKey('chapter-read-refresh'),
            onPressed: available && progress.canRefresh
                ? () => unawaited(progress.refresh())
                : null,
            child: const Text('刷新章节状态'),
          ),
        ],
      ),
      if (progress.busy) const CupertinoActivityIndicator(),
      if (progress.error case final error?) Text(error),
      if (_unmatchedChapterSelectionCount > 0)
        Text(
          '原清单中 $_unmatchedChapterSelectionCount 章已不在当前章节列表，未转入新选择，也未自动映射到其它章节。',
        ),
      if (pending != null) ...[
        const Text('有尚未结束的章节标记，列表仅显示服务端已确认的状态。'),
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton.filled(
            key: const ValueKey('chapter-read-resume'),
            onPressed: available && !progress.busy
                ? () => unawaited(_markChapters())
                : null,
            child: const Text('继续处理章节标记'),
          ),
        ),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: CupertinoButton(
          key: const ValueKey('chapter-selection-toggle'),
          onPressed: canSelect && (_selectingChapters || pending == null)
              ? () => setState(() {
                  _selectingChapters = !_selectingChapters;
                  _unmatchedChapterSelectionCount = 0;
                  if (!_selectingChapters) _chapterSelection.clear();
                  _resetRange();
                })
              : null,
          child: Text(_selectingChapters ? '退出章节选择' : '选择章节'),
        ),
      ),
      if (_selectingChapters) ...[
        Text('已选 ${_chapterSelection.length} 章 · 当前隐藏 $hidden 章'),
        if (hidden > 0) const Text('标记包含隐藏选中的章节，请核对完整确认清单。'),
        Wrap(
          spacing: 8,
          children: [
            CupertinoButton(
              key: const ValueKey('chapter-select-visible'),
              onPressed: canSelect && visible.isNotEmpty
                  ? () => setState(() => _chapterSelection.addAll(visibleKeys))
                  : null,
              child: const Text('全选当前显示章节'),
            ),
            CupertinoButton(
              key: const ValueKey('chapter-deselect-visible'),
              onPressed:
                  canSelect &&
                      _chapterSelection.intersection(visibleKeys).isNotEmpty
                  ? () =>
                        setState(() => _chapterSelection.removeAll(visibleKeys))
                  : null,
              child: const Text('取消当前显示章节选择'),
            ),
            CupertinoButton(
              key: const ValueKey('chapter-clear-selection'),
              onPressed: canSelect && _chapterSelection.isNotEmpty
                  ? () => setState(_chapterSelection.clear)
                  : null,
              child: const Text('清空章节选择'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            rangeEndpoint(
              '范围起点',
              'chapter-range-start',
              start,
              (value) => setState(() => _rangeStart = value),
            ),
            rangeEndpoint(
              '范围终点',
              'chapter-range-end',
              end,
              (value) => setState(() => _rangeEnd = value),
            ),
            CupertinoButton(
              key: const ValueKey('chapter-select-range'),
              onPressed: canSelect && start != null && end != null
                  ? () => setState(() {
                      final first = visible.indexWhere(
                        (chapter) => chapter.key == start,
                      );
                      final last = visible.indexWhere(
                        (chapter) => chapter.key == end,
                      );
                      final low = first < last ? first : last;
                      final high = first > last ? first : last;
                      _chapterSelection.addAll(
                        visible
                            .sublist(low, high + 1)
                            .map((chapter) => chapter.key),
                      );
                    })
                  : null,
              child: const Text('选中此范围'),
            ),
          ],
        ),
        const Text('范围按当前显示顺序的两个端点选择，包含两端；重复条目分别保留。'),
        Wrap(
          spacing: 8,
          children: [
            CupertinoButton.filled(
              key: const ValueKey('chapter-mark-read'),
              onPressed:
                  canSelect && pending == null && _chapterSelection.isNotEmpty
                  ? () => unawaited(_markChapters(read: true))
                  : null,
              child: const Text('标记所选已读'),
            ),
            CupertinoButton(
              key: const ValueKey('chapter-mark-unread'),
              onPressed:
                  canSelect && pending == null && _chapterSelection.isNotEmpty
                  ? () => unawaited(_markChapters(read: false))
                  : null,
              child: const Text('标记所选未读'),
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _chapterList() {
    final sequence = _sequence;
    final query = _chapterSearch.text.trim().toLowerCase();
    final visible = (sequence?.ordered(_chapterOrder) ?? <SequenceChapter>[])
        .where((chapter) {
          if (_onlyBookmarks && !(_bookmarks?.contains(chapter.key) ?? false)) {
            return false;
          }
          final completed = _chapterRead?.completed(chapter.key);
          if (_readFilter == _ChapterReadFilter.read && completed != true) {
            return false;
          }
          if (_readFilter == _ChapterReadFilter.unread && completed != false) {
            return false;
          }
          final text = [
            chapter.name,
            chapter.snapshot.scanlator,
            if (_chapterNumber(chapter) case final number?) '第 $number 章',
          ].join('\n').toLowerCase();
          return text.contains(query);
        })
        .toList();
    return [
      Text(
        '章节（${chapters.length}）',
        style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
      ),
      const SizedBox(height: 12),
      CupertinoTextField(
        key: const ValueKey('chapter-search'),
        controller: _chapterSearch,
        enabled: !_opening,
        onChanged: (_) => setState(_resetRange),
        placeholder: '章节名、扫描组或章节号',
        prefix: const Icon(CupertinoIcons.search),
        clearButtonMode: OverlayVisibilityMode.editing,
        clearButtonSemanticLabel: '清空章节搜索',
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Text('章节排序'),
          const SizedBox(width: 16),
          Expanded(
            child: ChoiceField<ChapterOrder>(
              key: const ValueKey('chapter-list-order'),
              label: '章节排序',
              value: _chapterOrder,
              options: {
                ChapterOrder.source: '来源顺序',
                ChapterOrder.reversed: '反向来源顺序',
              },
              onChanged: _opening
                  ? null
                  : (order) {
                      if (order != null) {
                        setState(() {
                          _chapterOrder = order;
                          _chapterOrderChosen = true;
                          _resetRange();
                        });
                      }
                    },
            ),
          ),
        ],
      ),
      if (_bookmarks case final bookmarks?) ...[
        MergeSemantics(
          child: CupertinoFormRow(
            prefix: const Expanded(flex: 3, child: Text('仅书签')),
            helper: Text(
              bookmarks.loaded
                  ? '已标记 ${bookmarks.chapterKeys.length} 章'
                  : '书签尚未确认',
            ),
            child: CupertinoSwitch(
              key: const ValueKey('chapters-bookmarked-only'),
              value: _onlyBookmarks,
              onChanged: bookmarks.loaded
                  ? (value) => setState(() {
                      _onlyBookmarks = value;
                      _resetRange();
                    })
                  : null,
            ),
          ),
        ),
        BookmarkStatus(controller: bookmarks),
        if (bookmarks.chapterKeys.any(
          (key) =>
              !(sequence?.entries.any((chapter) => chapter.key == key) ??
                  false),
        ))
          const Text('部分书签的章节未在当前列表中找到，原记录仍保留。'),
      ],
      ..._chapterReadControls(visible),
      Text('显示 ${visible.length} / ${chapters.length} 章'),
      if (controller.busy) const CupertinoActivityIndicator(),
      if (controller.error != null && _chapterOpenError == null)
        Text(controller.error!),
      if (chapters.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Text('这个漫画源没有返回章节'))
      else if (visible.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            query.isEmpty && _onlyBookmarks
                ? '当前章节列表中没有书签'
                : _onlyBookmarks
                ? '没有符合搜索和书签筛选的章节'
                : '没有匹配的章节',
          ),
        ),
      for (final chapter in visible)
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: !controller.busy && !_opening
              ? (_selectingChapters
                    ? _markingChapters
                          ? null
                          : () => _toggleChapter(chapter.key)
                    : () => _openChapter(context, chapter.sourceIndex))
              : null,
          child: CupertinoListTile(
            key: ValueKey(chapter.key),
            leading: _selectingChapters
                ? CupertinoCheckbox(
                    key: ValueKey(('chapter-select', chapter.key)),
                    value: _chapterSelection.contains(chapter.key),
                    onChanged: _markingChapters
                        ? null
                        : (_) => _toggleChapter(chapter.key),
                  )
                : const Icon(CupertinoIcons.doc_text),
            title: Text(chapter.name),
            subtitle: Text(
              [
                ?_chapterSubtitle(chapter),
                switch (_chapterRead?.completed(chapter.key)) {
                  true => '已读',
                  false => '未读',
                  null => '状态未知',
                },
              ].join(' · '),
            ),
            trailing: _selectingChapters || _bookmarks == null
                ? null
                : ChapterBookmarkButton(
                    controller: _bookmarks!,
                    chapterKey: chapter.key,
                    chapterName: chapter.name,
                    enabled: !controller.busy && !_opening,
                  ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _coverLifecycle = useValueNotifier(0);
    _chapterSearch = useTextEditingController();
    useEffect(() {
      _initialize();
      return null;
    }, const []);
    useListenable(controller);
    useOnListenableChange(controller, _catalogChanged);
    useOnListenableChange(_bookmarks, _detailsChanged);
    useOnListenableChange(_chapterRead, _detailsChanged);
    useOnAppLifecycleStateChange((_, state) => _lifecycleChanged(state));
    return GlassScaffold(
      enableBackgroundSampling: false,
      extendBody: false,
      backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
      appBar: GlassAppBar.pinned(
        backgroundColor: AppAppearance.chromeColor(context),
        title: Text(manga.title),
        actions: [
          GlassBarItem.menu(
            id: 'details-more',
            label: '更多操作',
            icon: const Icon(CupertinoIcons.ellipsis),
            menuWidth: 260,
            menuItems: [
              GlassMenuItem(
                title: '迁移到其他漫画源',
                enabled:
                    !_migrating &&
                    !_detailsExpired &&
                    !_opening &&
                    !_savingFavorite &&
                    !_editingCover &&
                    _library != null &&
                    _sequence != null &&
                    controller.status == ServiceStatus.ready &&
                    !controller.busy,
                onTap: () => unawaited(_migrate()),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _detailsExpired || !controller.isCurrentSource(source)
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(controller.error ?? '漫画源会话已变化，请返回浏览重新打开详情。'),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      if (widget.notice case final notice?) Text(notice),
                      if (_library != null) ...[
                        _favoriteControl(),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        manga.title,
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .navLargeTitleTextStyle,
                      ),
                      if (manga.author?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 12),
                        Text('作者：${manga.author}'),
                      ],
                      if (manga.artist?.isNotEmpty ?? false)
                        Text('画师：${manga.artist}'),
                      if (manga.genres.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final genre in manga.genres)
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: Text(genre),
                              ),
                          ],
                        ),
                      ],
                      if (manga.description?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 16),
                        SelectableRegion(
                          selectionControls: cupertinoTextSelectionControls,
                          contextMenuBuilder: (context, state) =>
                              CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                                buttonItems: state.contextMenuButtonItems,
                                anchors: state.contextMenuAnchors,
                              ),
                          child: Text(manga.description!),
                        ),
                      ],
                      const SizedBox(height: 32),
                      if (_failedChapter case final chapter?) ...[
                        Text(
                          '未能打开「${chapter.name}」：$_chapterOpenError',
                          key: const ValueKey('chapter-open-failure'),
                        ),
                        CupertinoButton(
                          key: const ValueKey('retry-open-chapter'),
                          onPressed:
                              _opening || controller.busy || _selectingChapters
                              ? null
                              : () =>
                                    _openChapter(context, chapter.sourceIndex),
                          child: Text('重试打开「${chapter.name}」'),
                        ),
                      ],
                      if (_resume case final resume?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: CupertinoButton.filled(
                            onPressed:
                                _opening ||
                                    controller.busy ||
                                    _selectingChapters
                                ? null
                                : () => _openChapter(
                                    context,
                                    _sequence!.entries.indexWhere(
                                      (entry) => entry.key == resume.chapterKey,
                                    ),
                                  ),
                            child: const Text('继续阅读'),
                          ),
                        ),
                      if (_resumeError != null) Text(_resumeError!),
                      if (_resumeReadFailed)
                        CupertinoButton(
                          key: const ValueKey('retry-read-resume'),
                          onPressed:
                              _loadingResume ||
                                  _opening ||
                                  controller.busy ||
                                  _selectingChapters
                              ? null
                              : () => unawaited(_refreshResume()),
                          child: Text(_loadingResume ? '正在读取阅读位置' : '重新读取阅读位置'),
                        ),
                      if (controller.hasUnsavedReadingProgress) ...[
                        const Text('部分阅读进度尚未保存，当前会话仍保留记录。'),
                        CupertinoButton(
                          onPressed: () => unawaited(_retryProgress()),
                          child: const Text('重试保存进度'),
                        ),
                      ],
                      ..._chapterList(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
