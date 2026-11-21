import '../../widgets/app_routes.dart';
import '../../widgets/choice_field.dart';
import '../../widgets/edit_sheet.dart';
import '../../theme/app_theme.dart';

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
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
  final VoidCallback? onClose,
}) extends StatefulHookConsumerWidget {
  @override
  ConsumerState<MangaDetailsPage> createState() => _MangaDetailsPageState();
}

enum _ChapterReadFilter { all, read, unread }

enum _DetailsRefresh { pull, action }

class _MangaDetailsPageState extends ConsumerState<MangaDetailsPage> {
  CatalogController get controller => widget.controller;
  MangaEntry get manga => _refreshedDetails?.manga ?? widget.manga;
  List<ChapterEntry> get chapters =>
      _refreshedDetails?.chapters ?? widget.chapters;
  CatalogSourceRef get source => widget.source;
  ChapterSequence? _sequence;
  ({MangaEntry manga, List<ChapterEntry> chapters})? _refreshedDetails;
  _DetailsRefresh? _sourceRefresh;
  String? _sourceRefreshError;
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
  late FocusNode _chapterSearchFocus;
  ChapterOrder _chapterOrder = ChapterOrder.source;
  bool _chapterOrderChosen = false;
  bool _chapterOptions = false;
  bool _descriptionExpanded = false;
  final _chapterNameCounts = <String, int>{};
  final _chapterUrlCounts = <String, int>{};

  void _rebuildSequence(String packageName) {
    final sequence = ChapterSequence(
      packageName: packageName,
      sourceId: source.sourceId,
      mangaUrl: manga.url,
      chapters: chapters.map((chapter) => chapter.snapshot),
    );
    _sequence = sequence;
    _chapterNameCounts.clear();
    _chapterUrlCounts.clear();
    for (final chapter in sequence.entries) {
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
  }

  void _initialize() {
    final build = controller.activeBuild;
    if (build != null) {
      _rebuildSequence(build.packageName);
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
      _refreshedDetails = null;
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

  bool get _canRefreshSource =>
      _sourceRefresh == null &&
      !_detailsExpired &&
      !_opening &&
      !_editingCover &&
      !_migrating &&
      !_savingFavorite &&
      !_selectingChapters &&
      !_markingChapters &&
      !controller.busy &&
      controller.status == ServiceStatus.ready &&
      controller.isCurrentSource(source);

  Future<void> _refreshSource(_DetailsRefresh refresh) async {
    if (!_canRefreshSource) return;
    final catalog = controller;
    final build = catalog.activeBuild;
    if (build == null) return;
    final route = ModalRoute.of(context);
    final reference = source;
    bool current() =>
        mounted &&
        !_detailsExpired &&
        identical(controller, catalog) &&
        identical(source, reference) &&
        route?.isCurrent == true &&
        catalog.status == ServiceStatus.ready &&
        catalog.isCurrentSource(reference);
    if (!current()) return;
    setState(() {
      _sourceRefresh = refresh;
      _sourceRefreshError = null;
    });
    final result = await catalog.details(manga, shouldContinue: current);
    if (!mounted) return;
    if (!current()) {
      setState(() => _sourceRefresh = null);
      return;
    }
    if (result == null ||
        !catalog.isCurrentSource(result.source) ||
        result.manga.url != manga.url) {
      setState(() {
        _sourceRefresh = null;
        _sourceRefreshError = result == null
            ? catalog.error ?? '请稍后重试。'
            : '漫画源返回了不同的作品。';
      });
      return;
    }
    setState(() {
      _sourceRefresh = null;
      _refreshedDetails = (manga: result.manga, chapters: result.chapters);
      _rebuildSequence(build.packageName);
      _resetRange();
      _failedChapter = null;
      _chapterOpenError = null;
      if (_resume case final resume?
          when !_sequence!.entries.any(
            (entry) => entry.key == resume.chapterKey,
          )) {
        _resume = null;
      }
    });
    unawaited(_refreshResume());
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
      await Navigator.of(context, rootNavigator: true).push<void>(
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
        target: MangaEditContext(
          title: manga.title,
          sourceName: selectedSource.sourceName,
          sourceLang: selectedSource.sourceLang,
        ),
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
        _mangaInformation(state),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CupertinoButton(
              onPressed:
                  state == null || _savingFavorite || _opening || _editingCover
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
                  state == null || _savingFavorite || _opening || _editingCover
                  ? null
                  : () => unawaited(_editCover()),
              child: const Text('自定义封面'),
            ),
          ],
        ),
        if (_favoriteError != null || snapshot.hasError)
          Text(_favoriteError ?? '未能读取作品状态，请返回书架重试；仍可继续阅读。'),
      ],
    );
  }

  Widget _mangaInformation(wire.MangaState? state) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_covers case final covers?)
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CustomCover(
            repository: covers,
            cover: state?.hasCustomCover() == true ? state!.customCover : null,
            constraints: const BoxConstraints.tightFor(width: 100, height: 150),
          ),
        ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              manga.title,
              style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle
                  .copyWith(fontSize: 28),
            ),
            const SizedBox(height: 8),
            if (manga.author?.isNotEmpty == true)
              Text(
                '作者：${manga.author}',
                style: TextStyle(
                  color: AppColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            if (manga.artist?.isNotEmpty == true &&
                manga.artist != manga.author)
              Text(
                '画师：${manga.artist}',
                style: TextStyle(
                  color: AppColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            Text(
              controller.activeSource?.name ?? '漫画源',
              style: TextStyle(
                color: AppColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    ],
  );

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
      await Navigator.of(context, rootNavigator: true).push<void>(readerRoute);
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
        target: MangaEditContext(
          title: manga.title,
          sourceName: source.sourceName,
          sourceLang: source.sourceLang,
        ),
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

  String? _chapterDate(
    String dateUpload,
    DateTime today,
    DateFormat dateFormat,
  ) {
    final milliseconds = int.tryParse(dateUpload, radix: 10);
    // Leave room for the local calendar day at the limits of DateTime.
    const maxEpoch = 8640000000000000 - Duration.millisecondsPerDay;
    if (milliseconds == null ||
        milliseconds == 0 ||
        milliseconds < -maxEpoch ||
        milliseconds > maxEpoch) {
      return null;
    }
    final local = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final day = DateTime.utc(local.year, local.month, local.day);
    final daysAgo = today.difference(day).inDays;
    return switch (daysAgo) {
      0 => '今天',
      > 0 && < 7 => '$daysAgo 天前',
      >= -7 && < 0 => '${-daysAgo} 天后',
      _ => dateFormat.format(local),
    };
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

  bool get _chapterStateActionsAvailable =>
      _chapterRead?.available == true &&
      !_opening &&
      !_markingChapters &&
      !_savingFavorite &&
      _bookmarks?.saving != true &&
      !controller.busy;

  bool get _canSelectChapters {
    final progress = _chapterRead;
    return progress != null &&
        _chapterStateActionsAvailable &&
        progress.loaded &&
        !progress.busy;
  }

  ChapterReadBatchDraft? get _pendingChapterRead {
    final progress = _chapterRead;
    return progress == null
        ? null
        : pendingChapterReadBatch(progress.repository, progress.mangaKey);
  }

  void _exitChapterSelection() {
    if (_markingChapters) return;
    setState(() {
      _selectingChapters = false;
      _unmatchedChapterSelectionCount = 0;
      _chapterSelection.clear();
      _resetRange();
    });
  }

  Widget _chapterSelectionBar(Set<String> visibleKeys) {
    final hidden = _chapterSelection.difference(visibleKeys).length;
    final canSelect = _canSelectChapters;
    return Row(
      children: [
        CupertinoButton(
          key: const ValueKey('chapter-selection-toggle'),
          padding: EdgeInsets.zero,
          onPressed: _markingChapters ? null : _exitChapterSelection,
          child: const Icon(
            CupertinoIcons.xmark,
            size: 20,
            semanticLabel: '退出章节选择',
          ),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text('已选 ${_chapterSelection.length} 章 · 当前隐藏 $hidden 章'),
          ),
        ),
        CupertinoButton(
          key: const ValueKey('chapter-select-visible'),
          padding: EdgeInsets.zero,
          onPressed: canSelect && visibleKeys.isNotEmpty
              ? () => setState(() => _chapterSelection.addAll(visibleKeys))
              : null,
          child: const Icon(
            CupertinoIcons.check_mark_circled,
            size: 20,
            semanticLabel: '全选当前显示章节',
          ),
        ),
        CupertinoButton(
          key: const ValueKey('chapter-deselect-visible'),
          padding: EdgeInsets.zero,
          onPressed:
              canSelect &&
                  _chapterSelection.intersection(visibleKeys).isNotEmpty
              ? () => setState(() => _chapterSelection.removeAll(visibleKeys))
              : null,
          child: const Icon(
            CupertinoIcons.minus_circled,
            size: 20,
            semanticLabel: '取消当前显示章节选择',
          ),
        ),
      ],
    );
  }

  Widget _chapterSelectionActions() {
    final canMark =
        _canSelectChapters &&
        _pendingChapterRead == null &&
        _chapterSelection.isNotEmpty;
    return Row(
      children: [
        for (final (read, key, label) in const [
          (true, 'chapter-mark-read', '标为已读'),
          (false, 'chapter-mark-unread', '标为未读'),
        ])
          Expanded(
            child: CupertinoButton(
              key: ValueKey(key),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              onPressed: canMark
                  ? () => unawaited(_markChapters(read: read))
                  : null,
              child: Text(label, textAlign: TextAlign.center),
            ),
          ),
      ],
    );
  }

  List<Widget> _chapterReadControls(
    List<SequenceChapter> visible,
    Set<String> visibleKeys,
  ) {
    final progress = _chapterRead;
    if (progress == null) return [];
    final pending = _pendingChapterRead;
    final available = _chapterStateActionsAvailable;
    final canSelect = _canSelectChapters;
    final hidden = _chapterSelection.difference(visibleKeys).length;
    final start = visibleKeys.contains(_rangeStart) ? _rangeStart : null;
    final end = visibleKeys.contains(_rangeEnd) ? _rangeEnd : null;
    Widget rangeEndpoint(
      String label,
      String key,
      String? value,
      ValueChanged<String?> change,
    ) => ChoiceField<String>(
      key: ValueKey(key),
      inline: false,
      label: label,
      value: value,
      options: {
        for (final chapter in visible)
          chapter.key: '${chapter.name} · 来源第 ${chapter.sourceIndex + 1} 项',
      },
      onChanged: canSelect ? change : null,
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
      if (!_selectingChapters)
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            key: const ValueKey('chapter-selection-toggle'),
            onPressed: canSelect && pending == null
                ? () => setState(() {
                    _selectingChapters = true;
                    _unmatchedChapterSelectionCount = 0;
                    _resetRange();
                  })
                : null,
            child: const Text('选择章节'),
          ),
        ),
      if (_selectingChapters) ...[
        if (hidden > 0) const Text('标记包含隐藏选中的章节，请核对完整确认清单。'),
        Align(
          alignment: Alignment.centerLeft,
          child: CupertinoButton(
            key: const ValueKey('chapter-clear-selection'),
            onPressed: canSelect && _chapterSelection.isNotEmpty
                ? () => setState(_chapterSelection.clear)
                : null,
            child: const Text('清空章节选择'),
          ),
        ),
        CupertinoFormSection.insetGrouped(
          margin: EdgeInsets.zero,
          footer: const Text('范围按当前显示顺序的两个端点选择，包含两端；重复条目分别保留。'),
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
      ],
    ];
  }

  Widget _sourceRefreshButton({bool retry = false}) {
    final enabled = _canRefreshSource && (retry || _sourceRefreshError == null);
    return Semantics(
      enabled: enabled,
      child: CupertinoButton(
        key: ValueKey(
          retry ? 'details-source-retry' : 'details-source-refresh',
        ),
        padding: const EdgeInsets.all(8),
        onPressed: enabled
            ? () => unawaited(_refreshSource(_DetailsRefresh.action))
            : null,
        child: retry
            ? const Text('重试刷新')
            : const Icon(CupertinoIcons.refresh, semanticLabel: '刷新作品资料和章节'),
      ),
    );
  }

  Widget _sourceRefreshFeedback() {
    final error = _sourceRefreshError;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.toolbar.resolveFrom(context),
        border: Border(
          top: BorderSide(color: AppColors.separator.resolveFrom(context)),
        ),
      ),
      child: SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                liveRegion: true,
                child: error == null
                    ? Row(
                        children: [
                          if (_sourceRefresh == _DetailsRefresh.action) ...[
                            const CupertinoActivityIndicator(),
                            const SizedBox(width: 8),
                          ],
                          const Flexible(child: Text('正在刷新作品资料和章节')),
                        ],
                      )
                    : Text(
                        '未能刷新作品资料和章节。$error',
                        style: TextStyle(
                          color: AppColors.error.resolveFrom(context),
                        ),
                      ),
              ),
              if (error != null) _sourceRefreshButton(retry: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailsScrollView({
    required Set<String> visibleKeys,
    required List<Widget> slivers,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      Widget selectionToolbar(Widget contents, {required bool top}) {
        final separator = BorderSide(
          color: AppColors.separator.resolveFrom(context),
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight / 3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.toolbar.resolveFrom(context),
              border: top ? Border(bottom: separator) : Border(top: separator),
            ),
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: contents,
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selectingChapters)
            selectionToolbar(_chapterSelectionBar(visibleKeys), top: true),
          Expanded(
            key: const ValueKey('details-scroll'),
            child: NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                // End editing when the user moves past the chapter search.
                if (notification.depth == 0 &&
                    notification.direction != ScrollDirection.idle) {
                  _chapterSearchFocus.unfocus();
                }
                return false;
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                semanticChildCount: visibleKeys.length,
                slivers: slivers,
              ),
            ),
          ),
          if (_selectingChapters)
            selectionToolbar(_chapterSelectionActions(), top: false)
          else if (_sourceRefresh != null || _sourceRefreshError != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: _sourceRefreshFeedback(),
            ),
        ],
      );
    },
  );

  Widget _chapterRow(SequenceChapter chapter, String? date) {
    final completed = _chapterRead?.completed(chapter.key);
    final titleStyle = CupertinoTheme.of(context).textTheme.textStyle;
    final name = Text(chapter.name);
    final canOpen = !controller.busy && !_opening;
    final selected =
        _selectingChapters && _chapterSelection.contains(chapter.key);
    final bookmarks = _selectingChapters ? null : _bookmarks;
    final action = CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: _selectingChapters
          ? (_canSelectChapters ? () => _toggleChapter(chapter.key) : null)
          : (canOpen ? () => _openChapter(context, chapter.sourceIndex) : null),
      child: CupertinoListTile(
        key: ValueKey(chapter.key),
        backgroundColor: selected
            ? AppColors.selection.resolveFrom(context)
            : null,
        padding: EdgeInsets.fromLTRB(16, 13, bookmarks == null ? 16 : 0, 13),
        title: DefaultTextStyle(
          style: completed == true && !selected
              ? titleStyle.copyWith(
                  color: AppColors.secondaryLabel.resolveFrom(context),
                )
              : titleStyle,
          child: completed == false
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.circle_fill,
                      size: 8,
                      color: AppColors.accent.resolveFrom(context),
                    ),
                    const SizedBox(width: 6),
                    Flexible(child: name),
                  ],
                )
              : name,
        ),
        subtitle: DefaultTextStyle(
          style: titleStyle.copyWith(
            fontSize: 12,
            color: AppColors.secondaryLabel.resolveFrom(context),
          ),
          child: Text(
            [
              ?date,
              ?_chapterSubtitle(chapter),
              switch (completed) {
                true => '已读',
                false => '未读',
                null => '状态未知',
              },
            ].join(' · '),
          ),
        ),
        trailing: _selectingChapters
            ? SizedBox(
                width: kMinInteractiveDimensionCupertino,
                child: Icon(
                  selected
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.circle,
                  size: 20,
                  color:
                      (selected ? AppColors.accent : AppColors.secondaryLabel)
                          .resolveFrom(context),
                ),
              )
            : null,
      ),
    );
    return Row(
      key: ValueKey(('chapter-row', chapter.key)),
      children: [
        Expanded(
          child: _selectingChapters
              ? Semantics(
                  key: ValueKey(('chapter-select', chapter.key)),
                  selected: selected,
                  child: action,
                )
              : action,
        ),
        if (bookmarks != null)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ChapterBookmarkButton(
              controller: bookmarks,
              chapterKey: chapter.key,
              chapterName: chapter.name,
              enabled: canOpen,
            ),
          ),
      ],
    );
  }

  List<SequenceChapter> _visibleChapters(String query) =>
      (_sequence?.ordered(_chapterOrder) ?? <SequenceChapter>[]).where((
        chapter,
      ) {
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
      }).toList();

  Widget _chapterRows(List<SequenceChapter> visible) {
    final now = clock.now().toLocal();
    final today = DateTime.utc(now.year, now.month, now.day);
    final dateFormat = DateFormat.yMd(
      Localizations.localeOf(context).toString(),
    );
    return SliverList.list(
      children: [
        for (final chapter in visible)
          _chapterRow(
            chapter,
            _chapterDate(chapter.snapshot.dateUpload, today, dateFormat),
          ),
      ],
    );
  }

  List<Widget> _chapterListControls(
    String query,
    List<SequenceChapter> visible,
    Set<String> visibleKeys,
  ) {
    final sequence = _sequence;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              '章节（${chapters.length}）',
              style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
            ),
          ),
          CupertinoButton(
            key: const ValueKey('chapter-options'),
            padding: const EdgeInsets.all(8),
            onPressed: () => setState(() => _chapterOptions = !_chapterOptions),
            child: Icon(
              CupertinoIcons.line_horizontal_3_decrease,
              semanticLabel: _chapterOptions ? '收起章节选项' : '章节选项',
            ),
          ),
          _sourceRefreshButton(),
        ],
      ),
      const SizedBox(height: 12),
      Semantics(
        label: '筛选章节',
        child: CupertinoTextField(
          autofillHints: null,
          key: const ValueKey('chapter-search'),
          controller: _chapterSearch,
          focusNode: _chapterSearchFocus,
          enabled: !_opening,
          onChanged: (_) => setState(_resetRange),
          placeholder: '章节名、扫描组或章节号',
          placeholderStyle: TextStyle(
            color: AppColors.secondaryLabel.resolveFrom(context),
          ),
          prefix: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              CupertinoIcons.search,
              size: 20,
              color: AppColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          decoration: BoxDecoration(
            color: AppColors.groupedSurface.resolveFrom(context),
            borderRadius: BorderRadius.circular(10),
          ),
          clearButtonMode: OverlayVisibilityMode.editing,
          clearButtonSemanticLabel: '清空章节搜索',
        ),
      ),
      const SizedBox(height: 12),
      if (_chapterOptions ||
          _selectingChapters ||
          _unmatchedChapterSelectionCount > 0 ||
          _chapterRead?.error != null ||
          _bookmarks?.error != null ||
          _bookmarks?.pending != null ||
          (_chapterRead != null &&
              pendingChapterReadBatch(
                    _chapterRead!.repository,
                    _chapterRead!.mangaKey,
                  ) !=
                  null)) ...[
        ChoiceField<ChapterOrder>(
          key: const ValueKey('chapter-list-order'),
          inline: false,
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
        ..._chapterReadControls(visible, visibleKeys),
      ],
      Text('显示 ${visible.length} / ${chapters.length} 章'),
      if (controller.busy && _sourceRefresh == null)
        const CupertinoActivityIndicator(),
      if (controller.error != null &&
          _chapterOpenError == null &&
          _sourceRefreshError == null)
        Text(controller.error!),
      if (chapters.isEmpty)
        const Padding(padding: EdgeInsets.all(24), child: Text('这个漫画源没有返回章节'))
      else if (visible.isEmpty)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                query.isEmpty && _onlyBookmarks
                    ? '当前章节列表中没有书签'
                    : _onlyBookmarks
                    ? '没有符合搜索和书签筛选的章节'
                    : '没有匹配的章节',
              ),
              CupertinoButton(
                key: const ValueKey('clear-chapter-filters'),
                padding: EdgeInsets.zero,
                onPressed: _markingChapters
                    ? null
                    : () => setState(() {
                        _chapterSearch.clear();
                        _onlyBookmarks = false;
                        _readFilter = _ChapterReadFilter.all;
                        _resetRange();
                      }),
                child: const Text('清除章节筛选'),
              ),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _coverLifecycle = useValueNotifier(0);
    _chapterSearch = useTextEditingController();
    _chapterSearchFocus = useFocusNode();
    useEffect(() {
      _initialize();
      return null;
    }, const []);
    useListenable(controller);
    useOnListenableChange(controller, _catalogChanged);
    useOnListenableChange(_bookmarks, _detailsChanged);
    useOnListenableChange(_chapterRead, _detailsChanged);
    useOnAppLifecycleStateChange((_, state) => _lifecycleChanged(state));
    final query = _chapterSearch.text.trim().toLowerCase();
    final visible = _visibleChapters(query);
    final visibleKeys = visible.map((chapter) => chapter.key).toSet();
    final page = CupertinoPageScaffold(
      navigationBar: _selectingChapters
          ? null
          : CupertinoNavigationBar(
              leading: widget.onClose == null
                  ? null
                  : CupertinoNavigationBarBackButton(onPressed: widget.onClose),
              middle: Text(
                manga.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoMenuAnchor(
                    key: const ValueKey('details-more'),
                    menuChildren: [
                      CupertinoMenuItem(
                        autofocus: true,
                        onPressed:
                            !_migrating &&
                                !_detailsExpired &&
                                !_opening &&
                                !_savingFavorite &&
                                !_editingCover &&
                                _library != null &&
                                _sequence != null &&
                                controller.status == ServiceStatus.ready &&
                                !controller.busy
                            ? () => unawaited(_migrate())
                            : null,
                        child: Text('迁移到其他漫画源'),
                      ),
                    ],
                    builder: (context, menu, child) => CupertinoButton(
                      onPressed:
                          !_migrating &&
                              !_detailsExpired &&
                              !_opening &&
                              !_savingFavorite &&
                              !_editingCover &&
                              _library != null &&
                              _sequence != null &&
                              controller.status == ServiceStatus.ready &&
                              !controller.busy
                          ? () => menu.isOpen ? menu.close() : menu.open()
                          : null,
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        CupertinoIcons.ellipsis,
                        semanticLabel: '更多操作',
                      ),
                    ),
                  ),
                ],
              ),
            ),
      child: SafeArea(
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
                  child: _detailsScrollView(
                    visibleKeys: visibleKeys,
                    slivers: [
                      CupertinoSliverRefreshControl(
                        onRefresh: () => _refreshSource(_DetailsRefresh.pull),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        sliver: SliverList.list(
                          addSemanticIndexes: false,
                          children: [
                            if (widget.notice case final notice?) Text(notice),
                            if (_library != null) ...[
                              _favoriteControl(),
                              const SizedBox(height: 16),
                            ] else
                              _mangaInformation(null),
                            if (manga.genres.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final genre in manga.genres)
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: AppColors.selection.resolveFrom(
                                          context,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        child: Text(
                                          genre,
                                          style: TextStyle(
                                            color: AppColors.onSelection
                                                .resolveFrom(context),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            if (manga.description?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 16),
                              SelectableRegion(
                                selectionControls:
                                    cupertinoTextSelectionControls,
                                contextMenuBuilder: (context, state) =>
                                    CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                                      buttonItems: state.contextMenuButtonItems,
                                      anchors: state.contextMenuAnchors,
                                    ),
                                child: Text(
                                  manga.description!,
                                  maxLines: _descriptionExpanded ? null : 3,
                                  overflow: _descriptionExpanded
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.secondaryLabel.resolveFrom(
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                              CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                onPressed: () => setState(
                                  () => _descriptionExpanded =
                                      !_descriptionExpanded,
                                ),
                                child: Text(
                                  _descriptionExpanded ? '收起简介' : '展开简介',
                                ),
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
                                    _opening ||
                                        controller.busy ||
                                        _selectingChapters
                                    ? null
                                    : () => _openChapter(
                                        context,
                                        chapter.sourceIndex,
                                      ),
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
                                            (entry) =>
                                                entry.key == resume.chapterKey,
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
                                child: Text(
                                  _loadingResume ? '正在读取阅读位置' : '重新读取阅读位置',
                                ),
                              ),
                            if (controller.hasUnsavedReadingProgress) ...[
                              const Text('部分阅读进度尚未保存，当前会话仍保留记录。'),
                              CupertinoButton(
                                onPressed: () => unawaited(_retryProgress()),
                                child: const Text('重试保存进度'),
                              ),
                            ],
                            ..._chapterListControls(
                              query,
                              visible,
                              visibleKeys,
                            ),
                          ],
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: 16),
                        sliver: _chapterRows(visible),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
    return PopScope<void>(
      canPop: !_selectingChapters,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectingChapters) _exitChapterSelection();
      },
      child: page,
    );
  }
}
