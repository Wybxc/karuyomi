import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/business_state_client.dart';
import '../../data/source_migration_repository.dart';
import '../../data/source_migration_matching.dart';
import '../browse/catalog_controller.dart';
import '../reader/chapter_sequence.dart';

final class MigrationSeed {
  MigrationSeed({required wire.LibraryMetadata metadata, this.sequence})
    : metadata = metadata.deepCopy()..freeze();
  final wire.LibraryMetadata metadata;
  final ChapterSequence? sequence;
}

final class MigrationSourceChoice {
  const MigrationSourceChoice({required this.build, required this.source});
  final CatalogBuild build;
  final wire.CatalogSource source;
  String get key => '${build.packageName}:${source.id}';
}

/// The wizard belongs to one account client, independently of the Source slot
/// it switches while searching. Every continuation also checks the route.
final class MigrationController extends ChangeNotifier {
  MigrationController({
    required this.catalog,
    required this.client,
    required this.seed,
    required this.isCurrent,
  }) : sourceSequence = seed.sequence {
    repository = MigrationRepository(client);
    if (!identical(catalog.library?.client, client) || catalog.accessPaused) {
      _retired = true;
      if (!_cancelled.isCompleted) _cancelled.complete();
      error = '身份或服务已改变，请关闭后重新开始迁移。';
    }
    catalog.addListener(_catalogChanged);
  }
  final CatalogController catalog;
  final MigrationSeed seed;
  final BusinessStateClient client;
  late final MigrationRepository repository;
  String get sourceKey =>
      seed.sequence?.mangaKey ??
      ChapterSequence(
        packageName: seed.metadata.packageName,
        sourceId: seed.metadata.sourceId,
        mangaUrl: seed.metadata.manga.url,
        chapters: const [],
      ).mangaKey;
  MigrationDraft? get pending => repository.pending(sourceKey);
  MigrationPreview? preview;
  List<MigrationChapterMatch> matches = const [];
  final mappedTargets = <String, String>{};
  final selectedChapters = <String>{};
  bool categoriesOnly = false;
  bool copyCategories = true;
  bool copyRead = true;
  bool copyBookmarks = true;
  bool completed = false;
  bool _sourceConfirmed = false;
  bool get sourceDecided => sourceSequence != null || categoriesOnly;
  bool get canChange =>
      available && !busy && pending == null && !completed && _sourceConfirmed;
  bool get tooMany => selectedChapters.length > migrationChapterLimit;
  int get unmappedStoredMarks {
    final value = preview;
    if (value == null) return 0;
    final mapped = selectedChapters;
    return {
      for (final entry in value.sourceProgress.entries)
        if (entry.value.completed) entry.key,
      ...value.sourceBookmarks,
    }.difference(mapped).length;
  }

  final bool Function() isCurrent;
  ChapterSequence? sourceSequence;
  List<MigrationSourceChoice> sources = const [];
  MigrationSourceChoice? selectedSource;
  CatalogSourceRef? _targetReference;
  List<MangaEntry> results = const [];
  String? _listingQuery;
  int _listingPage = 0;
  bool hasNextPage = false;
  String? get emptyResultsMessage => _listingPage == 0 || results.isNotEmpty
      ? null
      : _listingQuery == null
      ? '目标源的热门列表没有作品。'
      : '没有搜索结果，可尝试浏览目标源热门作品。';
  wire.LibraryMetadata? targetMetadata;
  ChapterSequence? targetSequence;
  String? error;
  String? notice;
  bool _busy = false;
  final _cancelled = Completer<void>();
  bool _disposed = false;
  bool _retired = false;
  int _epoch = 0;

  bool get available =>
      !_disposed &&
      !_retired &&
      isCurrent() &&
      identical(catalog.library?.client, client) &&
      {ServiceStatus.ready, ServiceStatus.failed}.contains(catalog.status);
  bool get busy => _busy || catalog.busy;
  bool _current(int epoch) => available && epoch == _epoch;

  void _catalogChanged() {
    if (_disposed) return;
    if (!identical(catalog.library?.client, client) || catalog.accessPaused) {
      _retired = true;
      if (!_cancelled.isCompleted) _cancelled.complete();
      ++_epoch;
      error = '身份或服务已改变，请关闭后重新开始迁移。';
    }
    notifyListeners();
  }

  Future<void> refreshSources() async {
    if (!available || busy) return;
    await _run((epoch) async {
      await catalog.refreshInstallations();
      if (!_current(epoch)) return;
      await catalog.refreshCatalog(
        shouldContinue: () => _current(epoch),
        cancelled: _cancelled.future,
      );
      if (!_current(epoch)) return;
      final original = await client.readManga(
        sourceKey,
        updateSession: false,
        shouldContinue: () => _current(epoch),
      );
      if (!_current(epoch)) return;
      _sourceConfirmed = original.manga.hasMetadata();
      if (!_sourceConfirmed) throw const FormatException('请先将原作品加入书架，再开始迁移。');
      sources = List.unmodifiable([
        for (final build in catalog.builds)
          if (catalog.installedExtensions.any(
            (installed) =>
                installed.enabled &&
                installed.catalogUrl == build.catalogUrl &&
                catalog.isRepositoryRegistered(build.catalog) &&
                installed.repoId == build.repoId &&
                installed.packageName == build.packageName &&
                installed.buildId == build.id,
          ))
            for (final source in build.sources)
              if (build.packageName != seed.metadata.packageName ||
                  source.id != seed.metadata.sourceId)
                MigrationSourceChoice(build: build, source: source),
      ]);
    });
  }

  Future<void> readOriginalChapters() async {
    if (!canChange || selectedSource != null) return;
    await _run((epoch) async {
      final ref = await catalog.openSelectedSource(
        packageName: seed.metadata.packageName,
        sourceId: seed.metadata.sourceId,
        shouldContinue: () => _current(epoch),
      );
      if (!_current(epoch)) return;
      if (ref == null) {
        throw FormatException(catalog.error ?? '原漫画源未能打开，可继续仅迁移收藏和分类。');
      }
      final details = await catalog.details(
        MangaEntry(seed.metadata.manga),
        shouldContinue: () => _current(epoch) && catalog.isCurrentSource(ref),
      );
      if (!_current(epoch)) return;
      if (details == null) {
        throw FormatException(catalog.error ?? '原章节未能读取，可继续仅迁移收藏和分类。');
      }
      categoriesOnly = false;
      sourceSequence = ChapterSequence(
        packageName: seed.metadata.packageName,
        sourceId: seed.metadata.sourceId,
        mangaUrl: seed.metadata.manga.url,
        chapters: details.chapters.map((chapter) => chapter.snapshot),
      );
      notice = '已读取原漫画源章节，请在预览中逐项确认映射。';
    });
  }

  Future<void> chooseSource(MigrationSourceChoice choice) async {
    if (!canChange || !sourceDecided) return;
    await _run((epoch) async {
      final ref = await catalog.openMigrationSource(
        build: choice.build,
        sourceId: choice.source.id,
        shouldContinue: () => _current(epoch),
      );
      if (!_current(epoch)) return;
      if (ref == null) throw FormatException(catalog.error ?? '目标漫画源未能打开。');
      selectedSource = choice;
      _targetReference = ref;
      results = const [];
      _listingQuery = null;
      _listingPage = 0;
      hasNextPage = false;
      targetMetadata = null;
      targetSequence = null;
      preview = null;
      matches = const [];
      mappedTargets.clear();
      selectedChapters.clear();
    });
  }

  Future<void> search(String value) => _listTargets(value.trim());

  Future<void> browsePopular() => _listTargets(null);

  Future<void> loadMore() async {
    if (_listingPage == 0 || !hasNextPage) return;
    await _listTargets(_listingQuery, more: true);
  }

  Future<void> _listTargets(String? search, {bool more = false}) async {
    final ref = _targetReference;
    if (!canChange || ref == null) return;
    await _run((epoch) async {
      final next = more ? _listingPage + 1 : 1;
      final found = await catalog.listMigrationTargets(
        source: ref,
        search: search,
        page: next,
        shouldContinue: () => _current(epoch),
      );
      if (!_current(epoch)) return;
      if (found == null) throw FormatException(catalog.error ?? '目标列表未能读取。');
      _listingQuery = search;
      _listingPage = next;
      hasNextPage = found.hasNextPage;
      results = List.unmodifiable(
        more ? [...results, ...found.mangas] : found.mangas,
      );
    });
  }

  Future<void> chooseManga(MangaEntry manga) async {
    final ref = _targetReference;
    final selected = selectedSource;
    if (!canChange || ref == null || selected == null) return;
    await _run((epoch) async {
      preview = null;
      targetMetadata = null;
      targetSequence = null;
      matches = const [];
      mappedTargets.clear();
      selectedChapters.clear();
      final details = await catalog.details(
        manga,
        shouldContinue: () => _current(epoch) && catalog.isCurrentSource(ref),
      );
      if (!_current(epoch)) return;
      if (details == null) {
        throw FormatException(catalog.error ?? '目标详情和章节未能读取。');
      }
      targetMetadata = wire.LibraryMetadata(
        packageName: selected.build.packageName,
        sourceId: selected.source.id,
        sourceName: catalog.activeSource!.name,
        sourceLang: catalog.activeSource!.lang,
        manga: details.manga.snapshot,
      )..freeze();
      targetSequence = ChapterSequence(
        packageName: selected.build.packageName,
        sourceId: selected.source.id,
        mangaUrl: details.manga.url,
        chapters: details.chapters.map((chapter) => chapter.snapshot),
      );
      await _loadPreview(epoch);
    });
  }

  void chooseCategoriesOnly() {
    if (!canChange || selectedSource != null) return;
    categoriesOnly = true;
    sourceSequence = null;
    error = null;
    notice = '仅迁移收藏和所选分类；章节未映射，已读、书签及页面位置不复制。';
    notifyListeners();
  }

  Future<void> _loadPreview(int epoch) async {
    final metadata = targetMetadata;
    final sequence = targetSequence;
    if (metadata == null || sequence == null) return;
    preview = null;
    matches = const [];
    mappedTargets.clear();
    selectedChapters.clear();
    final loaded = await repository.preview(
      sourceKey: sourceKey,
      targetMetadata: metadata,
      shouldContinue: () => _current(epoch),
    );
    if (!_current(epoch)) return;
    preview = loaded;
    matches = sourceSequence == null
        ? const []
        : suggestMigrationChapterMatches(sourceSequence!, sequence);
    mappedTargets.clear();
    selectedChapters.clear();
    final used = <String>{};
    for (final match in matches) {
      final target = match.suggested;
      if (target != null && used.add(target.key)) {
        mappedTargets[match.source.key] = target.key;
        if (hasCopyableMarks(match.source.key)) {
          selectedChapters.add(match.source.key);
        }
      }
    }
  }

  bool hasCopyableMarks(String sourceChapterKey) {
    final value = preview;
    final target = mappedTargets[sourceChapterKey];
    return value != null &&
        target != null &&
        ((copyRead &&
                value.sourceProgress[sourceChapterKey]?.completed == true &&
                !value.targetProgress.containsKey(target)) ||
            (copyBookmarks &&
                value.sourceBookmarks.contains(sourceChapterKey) &&
                !value.targetBookmarks.contains(target)));
  }

  bool targetUsed(String targetKey, String sourceChapterKey) =>
      mappedTargets.entries.any(
        (entry) => entry.key != sourceChapterKey && entry.value == targetKey,
      );

  void mapChapter(String sourceChapterKey, String? targetKey) {
    if (!canChange) return;
    if (targetKey != null && targetUsed(targetKey, sourceChapterKey)) {
      error = '同一目标章节不能对应多个原章节，请先取消另一条映射。';
    } else {
      error = null;
      if (targetKey == null) {
        mappedTargets.remove(sourceChapterKey);
        selectedChapters.remove(sourceChapterKey);
      } else {
        mappedTargets[sourceChapterKey] = targetKey;
        if (!hasCopyableMarks(sourceChapterKey)) {
          selectedChapters.remove(sourceChapterKey);
        }
      }
    }
    notifyListeners();
  }

  void selectChapter(String sourceChapterKey, bool selected) {
    if (!canChange ||
        !mappedTargets.containsKey(sourceChapterKey) ||
        !hasCopyableMarks(sourceChapterKey)) {
      return;
    }
    if (selected) {
      selectedChapters.add(sourceChapterKey);
    } else {
      selectedChapters.remove(sourceChapterKey);
    }
    notifyListeners();
  }

  void clearSelection() {
    if (!canChange) return;
    selectedChapters.clear();
    notifyListeners();
  }

  void setCopyOptions({bool? categories, bool? read, bool? bookmarks}) {
    if (!canChange) return;
    copyCategories = categories ?? copyCategories;
    copyRead = read ?? copyRead;
    copyBookmarks = bookmarks ?? copyBookmarks;
    selectedChapters.removeWhere((key) => !hasCopyableMarks(key));
    notifyListeners();
  }

  Future<void> refreshPreview() async {
    if (!available || busy || completed) return;
    await _run((epoch) async {
      await _loadPreview(epoch);
    });
  }

  Future<void> confirm() async {
    final value = preview;
    if (!canChange || value == null || tooMany) return;
    final chapters = <wire.ChapterMigration>[
      for (final sourceChapter in selectedChapters)
        if ((copyRead &&
                value.sourceProgress[sourceChapter]?.completed == true &&
                !value.targetProgress.containsKey(
                  mappedTargets[sourceChapter],
                )) ||
            (copyBookmarks &&
                value.sourceBookmarks.contains(sourceChapter) &&
                !value.targetBookmarks.contains(mappedTargets[sourceChapter])))
          wire.ChapterMigration(
            sourceChapterKey: sourceChapter,
            targetChapterKey: mappedTargets[sourceChapter],
            copyRead:
                copyRead &&
                value.sourceProgress[sourceChapter]?.completed == true &&
                !value.targetProgress.containsKey(mappedTargets[sourceChapter]),
            copyBookmark:
                copyBookmarks &&
                value.sourceBookmarks.contains(sourceChapter) &&
                !value.targetBookmarks.contains(mappedTargets[sourceChapter]),
          ),
    ];
    await _run((epoch) async {
      final result = await repository.commit(
        value,
        chapters: chapters,
        copyCategories: copyCategories,
        shouldContinue: () => _current(epoch),
      );
      if (!_current(epoch)) return;
      completed = true;
      notice =
          '迁移已由服务端确认：新增已读 ${result.migration.copiedReadChapters} 章、书签 ${result.migration.copiedBookmarks} 个。原作品及目标原有数据保留。';
    });
  }

  Future<void> retry() async {
    if (!available || busy || pending?.retryable != true) return;
    await _run((epoch) async {
      final result = await repository.retry(
        sourceKey,
        shouldContinue: () => _current(epoch),
      );
      if (!_current(epoch)) return;
      completed = true;
      notice =
          '原迁移操作已由服务端确认：新增已读 ${result.migration.copiedReadChapters} 章、书签 ${result.migration.copiedBookmarks} 个。';
    });
  }

  Future<void> discardRejected() async {
    if (!available || busy || pending?.retryable != false) return;
    await _run((epoch) async {
      repository.discardRejected(sourceKey);
      await _loadPreview(epoch);
    });
  }

  Future<void> _run(Future<void> Function(int epoch) action) async {
    _busy = true;
    final epoch = ++_epoch;
    error = null;
    notice = null;
    notifyListeners();
    try {
      await action(epoch);
    } catch (failure) {
      if (_current(epoch)) {
        error = failure is FormatException
            ? failure.message
            : failure is BusinessPendingMutationException
            ? failure.message
            : failure is BusinessStateException && failure.conflict
            ? '迁移预览已在其他设备改变，请重新读取后确认。'
            : pending != null
            ? '迁移尚未确认。请明确重试原操作；已确认冲突须先重新读取。'
            : '操作未完成，请重试；尚未提交迁移。';
      }
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (!_cancelled.isCompleted) _cancelled.complete();
    _disposed = true;
    ++_epoch;
    catalog.removeListener(_catalogChanged);
    super.dispose();
  }
}
