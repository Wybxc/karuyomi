import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/reading_progress.dart';
import '../../data/library_repository.dart';
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

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.controller,
    required this.onConnect,
    required this.onAuthenticate,
    this.configurationError,
    this.onAuthenticateReader,
  });
  final CatalogController? controller;
  final VoidCallback onConnect;
  final VoidCallback onAuthenticate;
  final String? configurationError;
  final ReaderAuthentication? onAuthenticateReader;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _search = TextEditingController();

  Future<void> _details(MangaEntry entry) async {
    final controller = widget.controller!;
    final details = await controller.details(entry);
    if (!mounted || details == null) return;
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

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) return _content(context, null);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _content(context, controller),
    );
  }

  Widget _content(BuildContext context, CatalogController? controller) {
    final status = controller?.status ?? ServiceStatus.disconnected;
    final busy = controller?.busy ?? false;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(controller!.activity ?? '正在加载'),
              const SizedBox(height: 16),
            ],
            if (controller?.error != null) ...[
              _Notice(text: controller!.error!, icon: Icons.error_outline),
              const SizedBox(height: 16),
            ],
            if (status != ServiceStatus.ready) ...[
              const Icon(Icons.travel_explore_outlined, size: 56),
              const SizedBox(height: 20),
              Text(
                switch (status) {
                  ServiceStatus.loginRequired => '登录后继续浏览',
                  ServiceStatus.denied => '当前账号无法访问',
                  ServiceStatus.connecting => '正在连接服务',
                  ServiceStatus.failed => '服务连接未完成',
                  _ => '连接漫画服务',
                },
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                widget.configurationError ?? '连接你的服务，加载已安装的漫画源。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Center(
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : status == ServiceStatus.loginRequired ||
                            status == ServiceStatus.denied
                      ? widget.onAuthenticate
                      : widget.onConnect,
                  icon: Icon(
                    status == ServiceStatus.loginRequired ||
                            status == ServiceStatus.denied
                        ? Icons.login
                        : Icons.refresh,
                  ),
                  label: Text(
                    status == ServiceStatus.loginRequired ||
                            status == ServiceStatus.denied
                        ? '登录'
                        : '连接服务',
                  ),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      controller!.email ?? '已连接',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : widget.onConnect,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新连接'),
                  ),
                ],
              ),
              if (controller.hasUnsavedReadingProgress) ...[
                const _Notice(
                  text: '部分阅读进度尚未保存，当前会话仍保留记录。',
                  icon: Icons.warning_amber,
                ),
                TextButton(
                  onPressed: () => unawaited(controller.flushReadingProgress()),
                  child: const Text('重试保存进度'),
                ),
              ],
              if (controller.builds.isEmpty)
                const _Notice(
                  text: '尚未安装漫画源。安装后重新连接即可浏览。',
                  icon: Icons.extension_outlined,
                ),
              if (controller.builds.isNotEmpty) ...[
                Text('漫画源', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final build in controller.builds)
                      ChoiceChip(
                        label: Text('${build.packageName} · ${build.version}'),
                        selected: controller.activeBuild?.id == build.id,
                        onSelected: busy
                            ? null
                            : (_) => controller.openBuild(build),
                      ),
                  ],
                ),
              ],
              if (controller.session != null) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final source in controller.session!.sources)
                      FilterChip(
                        label: Text('${source.name} · ${source.lang}'),
                        selected: controller.activeSource?.id == source.id,
                        onSelected: busy
                            ? null
                            : (_) => controller.selectSource(source),
                      ),
                  ],
                ),
              ],
              if (controller.activeSource != null) ...[
                const SizedBox(height: 24),
                TextField(
                  controller: _search,
                  enabled: !busy,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (query) => controller.loadMangas(search: query),
                  decoration: InputDecoration(
                    labelText: '搜索漫画',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: '搜索',
                      onPressed: busy
                          ? null
                          : () => controller.loadMangas(search: _search.text),
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in [('popular', '热门'), ('latest', '最新')])
                      if (item.$1 != 'latest' ||
                          controller.activeSource?.hasSupportsLatest() !=
                              true ||
                          controller.activeSource?.supportsLatest != false)
                        ChoiceChip(
                          label: Text(item.$2),
                          selected: controller.listing == item.$1,
                          onSelected: busy
                              ? null
                              : (_) {
                                  _search.clear();
                                  controller.loadMangas(
                                    search: '',
                                    operation: item.$1,
                                  );
                                },
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!busy && controller.mangas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('没有找到漫画', textAlign: TextAlign.center),
                  ),
                for (final manga in controller.mangas)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(manga.title),
                      subtitle: manga.author == null
                          ? null
                          : Text(manga.author!),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy ? null : () => _details(manga),
                    ),
                  ),
                if (controller.hasNextPage)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => controller.loadMangas(more: true),
                      child: const Text('加载更多'),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class MangaDetailsPage extends StatefulWidget {
  const MangaDetailsPage({
    super.key,
    required this.controller,
    required this.manga,
    required this.chapters,
    required this.source,
    this.onAuthenticateReader,
  });
  final CatalogController controller;
  final MangaEntry manga;
  final List<ChapterEntry> chapters;
  final CatalogSourceRef source;
  final ReaderAuthentication? onAuthenticateReader;

  @override
  State<MangaDetailsPage> createState() => _MangaDetailsPageState();
}

enum _ChapterReadFilter { all, read, unread }

class _MangaDetailsPageState extends State<MangaDetailsPage>
    with WidgetsBindingObserver {
  CatalogController get controller => widget.controller;
  MangaEntry get manga => widget.manga;
  List<ChapterEntry> get chapters => widget.chapters;
  CatalogSourceRef get source => widget.source;
  ChapterSequence? _sequence;
  MangaResume? _resume;
  String? _resumeError;
  bool _opening = false;
  LibraryRepository? _library;
  Stream<bool>? _favoriteStream;
  bool _savingFavorite = false;
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
  final _chapterSearch = TextEditingController();
  ChapterOrder _chapterOrder = ChapterOrder.source;
  bool _chapterOrderChosen = false;
  final _chapterNameCounts = <String, int>{};
  final _chapterUrlCounts = <String, int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      _favoriteStream = _library?.watchFavorite(_sequence!.mangaKey);
      final repository = controller.bookmarks;
      if (repository != null) {
        _bookmarks = ChapterBookmarksController(
          repository: repository,
          mangaKey: _sequence!.mangaKey,
          isCurrent: () =>
              mounted &&
              !_detailsExpired &&
              controller.status == ServiceStatus.ready &&
              controller.isCurrentSource(source) &&
              identical(controller.bookmarks, repository),
        )..addListener(_bookmarksChanged);
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
        )..addListener(_detailsChanged);
        unawaited(_chapterRead!.refresh());
      }
      unawaited(_refreshResume());
    }
    controller.addListener(_catalogChanged);
  }

  @override
  void didUpdateWidget(MangaDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_catalogChanged);
      controller.addListener(_catalogChanged);
    }
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

  void _bookmarksChanged() => _detailsChanged();

  void _detailsChanged() {
    if (!mounted) return;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_catalogChanged);
    _bookmarks?.removeListener(_bookmarksChanged);
    _bookmarks?.dispose();
    _chapterRead?.removeListener(_detailsChanged);
    _chapterRead?.dispose();
    _chapterSearch.dispose();
    super.dispose();
  }

  Future<void> _refreshResume() async {
    final sequence = _sequence;
    final repository = controller.readingProgress;
    if (sequence == null || repository == null) return;
    MangaResume? resume;
    String? error;
    try {
      resume =
          controller.readingDraftResume(sequence.mangaKey) ??
          await repository.loadResume(sequence.mangaKey);
      if (resume != null &&
          !sequence.entries.any((entry) => entry.key == resume!.chapterKey)) {
        error = '章节清单已变化，无法确定上次章节；请从列表选择。';
        resume = null;
      }
    } catch (_) {
      error = '未能读取服务端阅读位置，仍可从章节列表打开。';
    }
    if (!mounted ||
        _detailsExpired ||
        !identical(controller.readingProgress, repository)) {
      return;
    }
    setState(() {
      _resume = resume;
      _resumeError = error;
      // A user's list choice lasts for this detail page. Until then, the same
      // resume order supplies both the list and the reader's initial order.
      if (!_chapterOrderChosen && error == null) {
        _chapterOrder = resume?.reversedOrder == true
            ? ChapterOrder.reversed
            : ChapterOrder.source;
      }
    });
  }

  Future<void> _retryProgress() async {
    await controller.flushReadingProgress();
    await _refreshResume();
  }

  Future<void> _setFavorite(bool favorite) async {
    final repository = _library;
    final build = controller.activeBuild;
    final selectedSource = controller.activeSource;
    if (_savingFavorite ||
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

  Widget _favoriteControl() => StreamBuilder<bool>(
    stream: _favoriteStream,
    builder: (context, snapshot) {
      final favorite = snapshot.data ?? false;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: !snapshot.hasData || _savingFavorite || _opening
                ? null
                : () => unawaited(_setFavorite(!favorite)),
            icon: Icon(favorite ? Icons.bookmark : Icons.bookmark_add_outlined),
            label: Text(
              _savingFavorite
                  ? '正在保存'
                  : favorite
                  ? '移出书架'
                  : '加入书架',
            ),
          ),
          if (_favoriteError != null || snapshot.hasError)
            _Notice(
              text: _favoriteError ?? '未能读取收藏状态，请返回书架重试；仍可继续阅读。',
              icon: Icons.warning_amber,
            ),
        ],
      );
    },
  );

  Future<void> _openChapter(BuildContext context, int index) async {
    if (_opening || _selectingChapters || _detailsExpired) return;
    final catalog = controller;
    final selectedManga = manga;
    final selectedSource = source;
    final authenticate = widget.onAuthenticateReader;
    final progress = catalog.readingProgress;
    final route = ModalRoute.of(context);
    final sequence = _sequence;
    if (sequence == null) return;
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
    setState(() => _opening = true);
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
      if (mounted) setState(() => _opening = false);
      return;
    }
    if (!context.mounted || !isCurrent()) {
      await catalog.closeChapter(opened);
      if (mounted) setState(() => _opening = false);
      return;
    }
    try {
      final readerRoute = MaterialPageRoute<void>(
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
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: ValueKey(key),
            value: value,
            isExpanded: true,
            items: [
              for (final chapter in visible)
                DropdownMenuItem(
                  value: chapter.key,
                  child: Text(
                    '${chapter.name} · 来源第 ${chapter.sourceIndex + 1} 项',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: canSelect ? change : null,
          ),
        ),
      ),
    );
    return [
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (filter, label) in [
            (_ChapterReadFilter.all, '全部状态'),
            (_ChapterReadFilter.read, '已读'),
            (_ChapterReadFilter.unread, '未读'),
          ])
            ChoiceChip(
              key: ValueKey(('chapter-read-filter', filter.name)),
              label: Text(label),
              selected: _readFilter == filter,
              onSelected: filter == _ChapterReadFilter.all || progress.loaded
                  ? (_) => setState(() {
                      _readFilter = filter;
                      _resetRange();
                    })
                  : null,
            ),
          TextButton.icon(
            key: const ValueKey('chapter-read-refresh'),
            onPressed: available && progress.canRefresh
                ? () => unawaited(progress.refresh())
                : null,
            icon: const Icon(Icons.sync),
            label: const Text('刷新章节状态'),
          ),
        ],
      ),
      if (progress.busy) const LinearProgressIndicator(),
      if (progress.error case final error?)
        _Notice(text: error, icon: Icons.warning_amber),
      if (_unmatchedChapterSelectionCount > 0)
        _Notice(
          text:
              '原清单中 $_unmatchedChapterSelectionCount 章已不在当前章节列表，未转入新选择，也未自动映射到其它章节。',
          icon: Icons.info_outline,
        ),
      if (pending != null) ...[
        const _Notice(
          text: '有尚未结束的章节标记，列表仅显示服务端已确认的状态。',
          icon: Icons.pending_actions,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
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
        child: TextButton.icon(
          key: const ValueKey('chapter-selection-toggle'),
          onPressed: canSelect && (_selectingChapters || pending == null)
              ? () => setState(() {
                  _selectingChapters = !_selectingChapters;
                  _unmatchedChapterSelectionCount = 0;
                  if (!_selectingChapters) _chapterSelection.clear();
                  _resetRange();
                })
              : null,
          icon: Icon(_selectingChapters ? Icons.close : Icons.checklist),
          label: Text(_selectingChapters ? '退出章节选择' : '选择章节'),
        ),
      ),
      if (_selectingChapters) ...[
        Text('已选 ${_chapterSelection.length} 章 · 当前隐藏 $hidden 章'),
        if (hidden > 0) const Text('标记包含隐藏选中的章节，请核对完整确认清单。'),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              key: const ValueKey('chapter-select-visible'),
              onPressed: canSelect && visible.isNotEmpty
                  ? () => setState(() => _chapterSelection.addAll(visibleKeys))
                  : null,
              child: const Text('全选当前显示章节'),
            ),
            TextButton(
              key: const ValueKey('chapter-deselect-visible'),
              onPressed:
                  canSelect &&
                      _chapterSelection.intersection(visibleKeys).isNotEmpty
                  ? () =>
                        setState(() => _chapterSelection.removeAll(visibleKeys))
                  : null,
              child: const Text('取消当前显示章节选择'),
            ),
            TextButton(
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
            OutlinedButton(
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
            FilledButton.tonal(
              key: const ValueKey('chapter-mark-read'),
              onPressed:
                  canSelect && pending == null && _chapterSelection.isNotEmpty
                  ? () => unawaited(_markChapters(read: true))
                  : null,
              child: const Text('标记所选已读'),
            ),
            OutlinedButton(
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
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('chapter-search'),
        controller: _chapterSearch,
        enabled: !_opening,
        onChanged: (_) => setState(_resetRange),
        decoration: InputDecoration(
          labelText: '搜索章节',
          hintText: '章节名、扫描组或章节号',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _chapterSearch.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空章节搜索',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _chapterSearch.clear();
                    _resetRange();
                  }),
                ),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Text('章节排序'),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButton<ChapterOrder>(
              key: const ValueKey('chapter-list-order'),
              value: _chapterOrder,
              isExpanded: true,
              items: const [
                DropdownMenuItem(
                  value: ChapterOrder.source,
                  child: Text('来源顺序'),
                ),
                DropdownMenuItem(
                  value: ChapterOrder.reversed,
                  child: Text('反向来源顺序'),
                ),
              ],
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
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: const Text('仅书签'),
              selected: _onlyBookmarks,
              onSelected: bookmarks.loaded
                  ? (selected) => setState(() {
                      _onlyBookmarks = selected;
                      _resetRange();
                    })
                  : null,
            ),
            Text(
              bookmarks.loaded
                  ? '已标记 ${bookmarks.chapterKeys.length} 章'
                  : '书签尚未确认',
            ),
          ],
        ),
        BookmarkStatus(controller: bookmarks),
        if (bookmarks.chapterKeys.any(
          (key) =>
              !(sequence?.entries.any((chapter) => chapter.key == key) ??
                  false),
        ))
          const _Notice(
            text: '部分书签的章节未在当前列表中找到，原记录仍保留。',
            icon: Icons.info_outline,
          ),
      ],
      ..._chapterReadControls(visible),
      Text('显示 ${visible.length} / ${chapters.length} 章'),
      if (controller.busy) const LinearProgressIndicator(),
      if (controller.error != null)
        _Notice(text: controller.error!, icon: Icons.error_outline),
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
        ListTile(
          key: ValueKey(chapter.key),
          enabled: !controller.busy && !_opening,
          leading: _selectingChapters
              ? Checkbox(
                  key: ValueKey(('chapter-select', chapter.key)),
                  value: _chapterSelection.contains(chapter.key),
                  onChanged: _markingChapters
                      ? null
                      : (_) => _toggleChapter(chapter.key),
                )
              : const Icon(Icons.article_outlined),
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
          onTap: _selectingChapters
              ? _markingChapters
                    ? null
                    : () => _toggleChapter(chapter.key)
              : () => _openChapter(context, chapter.sourceIndex),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(manga.title)),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) =>
          _detailsExpired || !controller.isCurrentSource(source)
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
                    Text(
                      manga.title,
                      style: Theme.of(context).textTheme.headlineMedium,
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
                            Chip(label: Text(genre)),
                        ],
                      ),
                    ],
                    if (manga.description?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 16),
                      SelectableText(manga.description!),
                    ],
                    if (_library != null) ...[
                      const SizedBox(height: 16),
                      _favoriteControl(),
                    ],
                    const SizedBox(height: 32),
                    if (_resume case final resume?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('继续阅读'),
                          onPressed:
                              _opening || controller.busy || _selectingChapters
                              ? null
                              : () => _openChapter(
                                  context,
                                  _sequence!.entries.indexWhere(
                                    (entry) => entry.key == resume.chapterKey,
                                  ),
                                ),
                        ),
                      ),
                    if (_resumeError != null)
                      _Notice(text: _resumeError!, icon: Icons.info_outline),
                    if (controller.hasUnsavedReadingProgress) ...[
                      const _Notice(
                        text: '部分阅读进度尚未保存，当前会话仍保留记录。',
                        icon: Icons.warning_amber,
                      ),
                      TextButton(
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

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}
