import 'dart:async';

import 'package:flutter/material.dart';

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
      _library = controller.library;
      _favoriteStream = _library?.watchFavorite(_sequence!.mangaKey);
      final repository = controller.bookmarks;
      if (repository != null) {
        _bookmarks = ChapterBookmarksController(
          repository: repository,
          mangaKey: _sequence!.mangaKey,
          isCurrent: () =>
              mounted &&
              controller.isCurrentSource(source) &&
              controller.bookmarks?.identity.key == repository.identity.key,
        )..addListener(_bookmarksChanged);
        unawaited(_bookmarks!.refresh());
      }
      unawaited(_refreshResume());
    }
    controller.addListener(_catalogChanged);
  }

  void _bookmarksChanged() {
    if (mounted) setState(() {});
  }

  void _catalogChanged() => _bookmarks?.checkCurrent();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshResume());
      unawaited(_bookmarks?.refresh());
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
        controller.readingProgress?.identity.key != repository.identity.key) {
      return;
    }
    setState(() {
      _resume = resume;
      _resumeError = error;
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
    if (_opening) return;
    final route = ModalRoute.of(context);
    final sequence = _sequence;
    if (sequence == null) return;
    setState(() => _opening = true);
    final selected = sequence.entries[index];
    ReaderBaselineScope.read(context)?.event('navigation', {
      'action': 'open_chapter',
      'targetChapterKey': selected.key,
    });
    final opened = await controller.openChapter(
      manga,
      ChapterEntry(selected.snapshot),
      reference: source,
      logicalChapterKey: selected.key,
    );
    if (opened == null) {
      if (mounted) setState(() => _opening = false);
      return;
    }
    if (!context.mounted ||
        route?.isCurrent != true ||
        route?.isActive != true) {
      await controller.closeChapter(opened);
      if (mounted) setState(() => _opening = false);
      return;
    }
    try {
      final readerRoute = MaterialPageRoute<void>(
        builder: (_) => ChapterReaderRoute(
          catalog: controller,
          manga: manga,
          source: source,
          sequence: sequence,
          initialChapter: selected,
          initialOpened: opened,
          onAuthenticate: widget.onAuthenticateReader,
        ),
      );
      await Navigator.of(context).push<void>(readerRoute);
      await readerRoute.completed;
      await controller.flushReadingProgress();
    } finally {
      // Also covers a route popped before its first Reader leaf mounted.
      await controller.closeChapter(opened);
      if (mounted) {
        setState(() => _opening = false);
        await _refreshResume();
        await _bookmarks?.refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(manga.title)),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => !controller.isCurrentSource(source)
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
                          onPressed: _opening || controller.busy
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
                    Text(
                      '章节（${chapters.length}）',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (_bookmarks case final bookmarks?) ...[
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('仅书签'),
                            selected: _onlyBookmarks,
                            onSelected: bookmarks.loaded
                                ? (selected) =>
                                      setState(() => _onlyBookmarks = selected)
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
                        (key) => !_sequence!.entries.any(
                          (chapter) => chapter.key == key,
                        ),
                      ))
                        const _Notice(
                          text: '部分书签的章节未在当前列表中找到，原记录仍保留。',
                          icon: Icons.info_outline,
                        ),
                      if (_onlyBookmarks &&
                          !(_sequence?.entries.any(
                                (chapter) => bookmarks.contains(chapter.key),
                              ) ??
                              false))
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('当前章节列表中没有书签'),
                        ),
                    ],
                    if (controller.busy) const LinearProgressIndicator(),
                    if (controller.error != null)
                      _Notice(
                        text: controller.error!,
                        icon: Icons.error_outline,
                      ),
                    if (chapters.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('这个漫画源没有返回章节'),
                      ),
                    for (var index = 0; index < chapters.length; index++)
                      if (!_onlyBookmarks ||
                          (_sequence != null &&
                              (_bookmarks?.contains(
                                    _sequence!.entries[index].key,
                                  ) ??
                                  false)))
                        ListTile(
                          enabled: !controller.busy && !_opening,
                          leading: const Icon(Icons.article_outlined),
                          title: Text(chapters[index].name),
                          trailing: _bookmarks == null || _sequence == null
                              ? null
                              : ChapterBookmarkButton(
                                  controller: _bookmarks!,
                                  chapterKey: _sequence!.entries[index].key,
                                  chapterName: chapters[index].name,
                                  enabled: !controller.busy && !_opening,
                                ),
                          onTap: () => _openChapter(context, index),
                        ),
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
