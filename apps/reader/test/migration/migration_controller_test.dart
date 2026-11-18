import '../test_app.dart';

import 'dart:async';
import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/bookmark_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/features/migration/migration_controller.dart';
import 'package:karuyomi/features/migration/migration_page.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/runtime/api_fetch.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import '../browse/fakes.dart';

const _package = 'eu.kanade.source.test';
const _targetId = '42';
wire.Manga get _target => wire.Manga(url: '/target', title: '目标作品');
List<wire.Chapter> _chapters(String prefix) => [
  wire.Chapter(url: '/$prefix/1', name: '第1章', chapterNumber: 1),
  wire.Chapter(url: '/$prefix/2', name: '第2章', chapterNumber: 2),
];

void main() {
  late TestPlatform platform;
  late CatalogController catalog;
  late MigrationController controller;
  late MigrationSeed seed;
  late ChapterSequence sequence;
  bool current = true;
  setUp(() async {
    current = true;
    platform = TestPlatform();
    final index = wire.decodeProtoJson(
      wire.ExtensionIndex(),
      platform.inventory,
    );
    index.builds.single.sourceIds.add(_targetId);
    index.builds.single.sources.add(
      wire.CatalogSource(id: _targetId, name: '目标源', lang: 'zh'),
    );
    platform.inventory = wire.encodeProtoJson(index);
    platform.sourceInventory = [
      wire.SourceInfo(id: sourceId, name: '原源', lang: 'en'),
      wire.SourceInfo(id: _targetId, name: '目标源', lang: 'zh'),
    ];
    platform.invokeHandler = (call) async => switch (call.whichRequest()) {
      wire.SourceCall_Request.search => wire.SourceResult(
        mangaPage: wire.MangaPage(
          mangas: [_target],
          hasNextPage: call.search.page == 1,
        ),
      ),
      wire.SourceCall_Request.details => wire.SourceResult(
        manga: call.details.manga.deepCopy()..initialized = true,
      ),
      wire.SourceCall_Request.chapters => wire.SourceResult(
        chapters: wire.ChapterList(
          chapters: _chapters(call.sourceId == sourceId ? 'old' : 'new'),
        ),
      ),
      _ => wire.SourceResult(mangaPage: wire.MangaPage()),
    };
    catalog = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    await catalog.library!.setFavorite(
      packageName: _package,
      sourceId: sourceId,
      sourceName: '原源',
      sourceLang: 'en',
      manga: testManga,
      favorite: true,
    );
    sequence = ChapterSequence(
      packageName: _package,
      sourceId: sourceId,
      mangaUrl: testManga.url,
      chapters: _chapters('old'),
    );
    final state = await catalog.library!.client.readManga(sequence.mangaKey);
    await ProgressRepository(catalog.library!.client).setChapterRead(
      mangaKey: sequence.mangaKey,
      chapterKey: sequence.entries.first.key,
      read: true,
      basedOnRevision: state.manga.revision,
    );
    final afterRead = await catalog.library!.client.readManga(
      sequence.mangaKey,
    );
    await BookmarkRepository(catalog.library!.client).set(
      mangaKey: sequence.mangaKey,
      chapterKey: sequence.entries.first.key,
      bookmarked: true,
      basedOnRevision: afterRead.manga.revision,
    );
    seed = MigrationSeed(
      metadata: wire.LibraryMetadata(
        packageName: _package,
        sourceId: sourceId,
        sourceName: '原源',
        sourceLang: 'en',
        manga: testManga,
      ),
      sequence: sequence,
    );
    controller = MigrationController(
      catalog: catalog,
      client: catalog.library!.client,
      seed: seed,
      isCurrent: () => current,
    );
  });
  tearDown(() async {
    controller.dispose();
    catalog.dispose();
    await catalog.closeReadingProgress();
    await platform.dispose();
  });
  List<String> posts() => platform.businessServer.requests
      .where((request) => request.method == 'POST')
      .map((request) => request.body!)
      .toList();
  void failOriginalRead() {
    platform.businessServer.beforeRequest = (request) =>
        request.method == 'GET' &&
            request.uri.path == '/api/state/manga/${sequence.mangaKey}'
        ? const ApiReply(
            status: 503,
            redirected: false,
            headers: {'content-type': 'text/plain'},
            body: 'Injected read failure',
          )
        : null;
  }

  Future<void> targetPreview() async {
    await controller.refreshSources();
    await controller.chooseSource(controller.sources.single);
    await controller.search('原作品');
    await controller.chooseManga(controller.results.first);
  }

  test('installed Source search pagination, details, mapping and confirmation retain the source without copying anchors', () async {
    final before = posts().length;
    await controller.refreshSources();
    expect(controller.sources.single.source.id, _targetId);
    await controller.chooseSource(controller.sources.single);
    final normal = platform.invokeHandler!;
    var entered = Completer<void>();
    var release = Completer<void>();
    platform.invokeHandler = (call) async {
      if (call.hasSearch()) {
        entered.complete();
        await release.future;
      }
      return normal(call);
    };
    final search = controller.search('原作品');
    try {
      await entered.future.timeout(const Duration(seconds: 5));
      expect(controller.busy, isTrue);
      expect(controller.canChange, isFalse);
      expect(controller.operationLabel, '搜索目标作品“原作品”');
      expect(posts(), hasLength(before));
    } finally {
      release.complete();
      await search;
    }
    final retained = controller.results;
    entered = Completer<void>();
    release = Completer<void>();
    final more = controller.loadMore();
    try {
      await entered.future.timeout(const Duration(seconds: 5));
      expect(controller.operationLabel, '加载更多“原作品”的搜索结果');
      expect(controller.results, orderedEquals(retained));
      expect(posts(), hasLength(before));
    } finally {
      release.complete();
      await more;
    }
    final searches = platform.invocations
        .where((call) => call.hasSearch())
        .toList();
    expect(searches.map((call) => call.search.page), [1, 2]);
    expect(searches.every((call) => call.sourceId == _targetId), true);
    expect(searches.every((call) => call.search.query == '原作品'), true);
    await controller.chooseManga(controller.results.first);
    expect(controller.preview, isNotNull);
    expect(controller.selectedChapters, {sequence.entries.first.key});
    expect(posts(), hasLength(before));
    await controller.confirm();
    expect(controller.completed, true, reason: controller.error);
    expect(posts(), hasLength(before + 1));
    final operation = wire.decodeProtoJson(
      wire.StateMutation(),
      jsonDecode(posts().last),
    );
    expect(operation.migrateFrom.chapters.single.copyRead, true);
    expect(operation.migrateFrom.chapters.single.copyBookmark, true);
    final targetKey = controller.preview!.targetKey;
    expect(platform.businessServer.manga(sequence.mangaKey)!.favorite, true);
    expect(platform.businessServer.manga(targetKey)!.favorite, true);
    final copied = platform.businessServer.progress(
      targetKey,
      operation.migrateFrom.chapters.single.targetChapterKey,
    )!;
    expect(copied.completed, true);
    expect(copied.epoch, 1);
    expect(copied.hasCurrent(), false);
    expect(copied.hasFurthest(), false);
    final notice = controller.notice;
    final requests = platform.businessServer.requests.length;
    await controller.refreshSources();
    expect(controller.notice, notice);
    expect(platform.businessServer.requests, hasLength(requests));
  });

  test('lost ACK survives closing the wizard and only explicit retry resends its original body', () async {
    await targetPreview();
    platform.businessServer.loseNextResponse = true;
    await controller.confirm();
    expect(controller.completed, false);
    expect(controller.pending?.retryable, true);
    final original = posts().last;
    final count = posts().length;
    controller.dispose();
    controller = MigrationController(
      catalog: catalog,
      client: catalog.library!.client,
      seed: seed,
      isCurrent: () => current,
    );
    await controller.refreshSources();
    await controller.refreshPreview();
    expect(posts(), hasLength(count));
    expect(controller.canChange, false);
    failOriginalRead();
    await controller.refreshSources();
    platform.businessServer.beforeRequest = null;
    expect(controller.operationLabel, '读取迁移输入');
    expect(controller.error, '本次读取未完成，请重新读取。原迁移操作保持不变。');
    expect(controller.pending?.retryable, true);
    expect(
      wire.encodeProtoJson(controller.pending!.request),
      jsonDecode(original),
    );
    expect(controller.canChange, false);
    expect(posts(), hasLength(count));
    await controller.retry();
    expect(controller.completed, true, reason: controller.error);
    expect(posts().last, original);
    expect(posts(), hasLength(count + 1));
  });

  test('a rejected migration requires a read before a new command and never suggests retrying the rejected operation', () async {
    await targetPreview();
    final before = posts().length;
    final applied = platform.businessServer.appliedMutations;
    final originalState = platform.businessServer.manga(sequence.mangaKey);
    final targetKey = controller.preview!.targetKey;
    platform.businessServer.beforeRequest = (request) {
      if (request.method != 'POST' ||
          request.uri.path != '/api/state/mutations') {
        return null;
      }
      final command = wire.decodeProtoJson(
        wire.StateMutation(),
        jsonDecode(request.body!),
      );
      return ApiReply(
        status: 400,
        redirected: false,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(
          wire.encodeProtoJson(
            wire.StateMutationResponse(
              schemaVersion: 1,
              mutationId: command.mutationId,
              error: wire.BusinessStateError(
                code: wire
                    .BusinessStateErrorCode
                    .BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
                message: 'Injected pre-dispatch rejection',
                retryable: false,
              ),
            ),
          ),
        ),
      );
    };
    await controller.confirm();
    platform.businessServer.beforeRequest = null;
    expect(controller.completed, false);
    expect(controller.pending?.retryable, false);
    expect(controller.error, contains('重新读取'));
    expect(controller.error, isNot(contains('重试')));
    expect(controller.canChange, false);
    final original = controller.pending!.request;
    await controller.retry();
    await controller.confirm();
    await controller.refreshSources();
    expect(controller.pending!.request, original);
    expect(posts(), hasLength(before + 1));
    expect(platform.businessServer.appliedMutations, applied);
    expect(platform.businessServer.manga(sequence.mangaKey), originalState);
    expect(platform.businessServer.manga(targetKey), isNull);
    failOriginalRead();
    await controller.refreshSources();
    platform.businessServer.beforeRequest = null;
    expect(controller.operationLabel, '读取迁移输入');
    expect(controller.error, '本次读取未完成，请重新读取。原迁移操作保持不变。');
    expect(controller.pending!.request, original);
    expect(controller.pending?.retryable, false);
    expect(controller.canChange, false);
    expect(posts(), hasLength(before + 1));
    expect(platform.businessServer.appliedMutations, applied);
    await controller.discardRejected();
    expect(controller.pending, isNull);
    expect(controller.preview, isNotNull);
    expect(controller.canChange, true);
    expect(posts(), hasLength(before + 1));
    expect(platform.businessServer.appliedMutations, applied);
  });

  test(
    'unavailable original chapters require an explicit categories-only choice',
    () async {
      controller.dispose();
      controller = MigrationController(
        catalog: catalog,
        client: catalog.library!.client,
        seed: MigrationSeed(metadata: seed.metadata),
        isCurrent: () => current,
      );
      await controller.refreshSources();
      await controller.chooseSource(controller.sources.single);
      expect(controller.selectedSource, isNull);
      controller.chooseCategoriesOnly();
      await controller.chooseSource(controller.sources.single);
      await controller.search('作品');
      await controller.chooseManga(controller.results.first);
      expect(controller.sourceSequence, isNull);
      expect(controller.matches, isEmpty);
      expect(controller.selectedChapters, isEmpty);
      await controller.confirm();
      expect(controller.completed, true, reason: controller.error);
      expect(
        wire
            .decodeProtoJson(wire.StateMutation(), jsonDecode(posts().last))
            .migrateFrom
            .chapters,
        isEmpty,
      );
    },
  );

  for (final failure in [
    RuntimeErrorCode.runtimeLost,
    RuntimeErrorCode.timeout,
  ]) {
    test(
      'original Source $failure still permits explicit categories-only migration through a recovered target',
      () async {
        controller.dispose();
        controller = MigrationController(
          catalog: catalog,
          client: catalog.library!.client,
          seed: MigrationSeed(metadata: seed.metadata),
          isCurrent: () => current,
        );
        await controller.refreshSources();
        final normal = platform.invokeHandler!;
        platform.invokeHandler = (call) async {
          if (call.sourceId == sourceId && call.hasDetails()) {
            throw RuntimeException(failure, 'Original Source unavailable');
          }
          return normal(call);
        };
        await controller.readOriginalChapters();
        expect(catalog.status, ServiceStatus.failed);
        expect(controller.available, true);
        expect(controller.error, isNotNull);
        controller.chooseCategoriesOnly();
        await controller.chooseSource(controller.sources.single);
        expect(platform.rebuildCount, 1);
        expect(
          catalog.status,
          ServiceStatus.ready,
          reason:
              'error=${controller.error} catalog=${catalog.error} available=${controller.available} session=${catalog.session}',
        );
        await controller.search('作品');
        await controller.chooseManga(controller.results.first);
        await controller.confirm();
        expect(controller.completed, true, reason: controller.error);
        expect(
          wire
              .decodeProtoJson(wire.StateMutation(), jsonDecode(posts().last))
              .migrateFrom
              .chapters,
          isEmpty,
        );
      },
    );
  }

  test('changing an already selected mapping to a fully populated target removes its disabled selection', () async {
    final secondSource = sequence.entries[1];
    final source = await catalog.library!.client.readManga(sequence.mangaKey);
    await catalog.readingProgress!.setChapterRead(
      mangaKey: sequence.mangaKey,
      chapterKey: secondSource.key,
      read: true,
      basedOnRevision: source.manga.revision,
    );
    final targetSequence = ChapterSequence(
      packageName: _package,
      sourceId: _targetId,
      mangaUrl: _target.url,
      chapters: _chapters('new'),
    );
    await catalog.library!.setFavorite(
      packageName: _package,
      sourceId: _targetId,
      sourceName: '目标源',
      sourceLang: 'zh',
      manga: _target,
      favorite: true,
    );
    final target = await catalog.library!.client.readManga(
      targetSequence.mangaKey,
    );
    await catalog.readingProgress!.setChapterRead(
      mangaKey: targetSequence.mangaKey,
      chapterKey: targetSequence.entries.first.key,
      read: false,
      basedOnRevision: target.manga.revision,
    );
    final targetUnread = await catalog.library!.client.readManga(
      targetSequence.mangaKey,
    );
    await catalog.bookmarks!.set(
      mangaKey: targetSequence.mangaKey,
      chapterKey: targetSequence.entries.first.key,
      bookmarked: true,
      basedOnRevision: targetUnread.manga.revision,
    );
    await targetPreview();
    expect(controller.selectedChapters, {secondSource.key});
    controller.mapChapter(sequence.entries.first.key, null);
    controller.mapChapter(secondSource.key, targetSequence.entries.first.key);
    expect(controller.hasCopyableMarks(secondSource.key), false);
    expect(controller.selectedChapters, isEmpty);
    await controller.confirm();
    expect(controller.completed, true, reason: controller.error);
    final operation = wire.decodeProtoJson(
      wire.StateMutation(),
      jsonDecode(posts().last),
    );
    expect(operation.migrateFrom.chapters, isEmpty);
    expect(
      platform.businessServer
          .progress(targetSequence.mangaKey, targetSequence.entries.first.key)!
          .completed,
      false,
    );
  });

  test('more than 256 selected chapters require an explicit smaller selection before any migration POST', () async {
    final oldChapters = [
      for (var number = 1; number <= 257; number++)
        wire.Chapter(
          url: '/old/$number',
          name: '第$number章',
          chapterNumber: number.toDouble(),
        ),
    ];
    sequence = ChapterSequence(
      packageName: _package,
      sourceId: sourceId,
      mangaUrl: testManga.url,
      chapters: oldChapters,
    );
    final progress = catalog.readingProgress!;
    for (final chapter in sequence.entries) {
      await progress.setChapterRead(
        mangaKey: sequence.mangaKey,
        chapterKey: chapter.key,
        read: true,
        basedOnRevision: platform.businessServer
            .manga(sequence.mangaKey)!
            .revision,
      );
    }
    controller.dispose();
    controller = MigrationController(
      catalog: catalog,
      client: catalog.library!.client,
      seed: MigrationSeed(metadata: seed.metadata, sequence: sequence),
      isCurrent: () => current,
    );
    final normal = platform.invokeHandler!;
    platform.invokeHandler = (call) async {
      if (call.sourceId == _targetId && call.hasChapters()) {
        return wire.SourceResult(
          chapters: wire.ChapterList(
            chapters: [
              for (var number = 1; number <= 257; number++)
                wire.Chapter(
                  url: '/new/$number',
                  name: '第$number章',
                  chapterNumber: number.toDouble(),
                ),
            ],
          ),
        );
      }
      return normal(call);
    };
    await targetPreview();
    expect(controller.selectedChapters, hasLength(257));
    expect(controller.tooMany, true);
    final before = posts().length;
    await controller.confirm();
    expect(controller.completed, false);
    expect(posts(), hasLength(before));
    controller.clearSelection();
    controller.selectChapter(sequence.entries.first.key, true);
    await controller.confirm();
    expect(controller.completed, true, reason: controller.error);
    expect(posts(), hasLength(before + 1));
    final operation = wire.decodeProtoJson(
      wire.StateMutation(),
      jsonDecode(posts().last),
    );
    expect(operation.migrateFrom.chapters, hasLength(1));
    expect(
      operation.migrateFrom.chapters.single.sourceChapterKey,
      sequence.entries.first.key,
    );
  });

  test('closing during a read-only preview stops subsequent reads and never submits migration', () async {
    await controller.refreshSources();
    await controller.chooseSource(controller.sources.single);
    await controller.search('作品');
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    platform.businessServer.beforeRequest = (request) async {
      if (request.uri.path ==
          '/api/state/manga/${sequence.mangaKey}/progress') {
        entered.complete();
        await release.future;
      }
      return null;
    };
    final count = posts().length;
    final loading = controller.chooseManga(controller.results.first);
    await entered.future.timeout(const Duration(seconds: 5));
    final requests = platform.businessServer.requests.length;
    current = false;
    release.complete();
    await loading;
    expect(platform.businessServer.requests, hasLength(requests));
    expect(controller.preview, isNull);
    expect(posts(), hasLength(count));
  });

  testWidgets(
    'Library menu opens migration without loading the original Source',
    (tester) async {
      await tester.pumpApp(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: LibraryPage(
              controller: catalog,
              onBrowse: () {},
              onConnect: () {},
              onAuthenticate: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = posts().length;
      await tester.tap(
        find.byKey(ValueKey(('library-more', sequence.mangaKey))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('迁移到其他漫画源'));
      await tester.pumpAndSettle();
      final page = tester.widget<MigrationPage>(find.byType(MigrationPage));
      expect(page.seed.sequence, isNull);
      expect(page.seed.metadata.manga.url, testManga.url);
      expect(find.text('读取原漫画源章节'), findsOneWidget);
      expect(platform.invocations, isEmpty);
      expect(posts(), hasLength(before));
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'opened Details menu passes its original chapter snapshot into migration',
    (tester) async {
      final source = await catalog.openMigrationSource(
        build: catalog.builds.single,
        sourceId: sourceId,
        shouldContinue: () => true,
      );
      expect(source, isNotNull);
      await tester.pumpApp(
        CupertinoApp(
          home: MangaDetailsPage(
            controller: catalog,
            manga: MangaEntry(testManga),
            chapters: _chapters('old').map(ChapterEntry.new).toList(),
            source: source!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = posts().length;
      await tester.tap(find.byKey(const ValueKey('details-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('迁移到其他漫画源'));
      await tester.pumpAndSettle();
      final page = tester.widget<MigrationPage>(find.byType(MigrationPage));
      expect(page.seed.sequence!.mangaKey, sequence.mangaKey);
      expect(
        page.seed.sequence!.entries.map((chapter) => chapter.key),
        sequence.entries.map((chapter) => chapter.key),
      );
      expect(posts(), hasLength(before));
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final fromDetails in [false, true]) {
    for (final replaceIdentity in [false, true]) {
      testWidgets(
        '${fromDetails ? 'Details' : 'Library'} route keeps its clicked client when ${replaceIdentity ? 'identity changes' : 'Access clears identity'} before lazy construction',
        (tester) async {
          final clickedClient = catalog.library!.client;
          if (fromDetails) {
            final source = await catalog.openMigrationSource(
              build: catalog.builds.single,
              sourceId: sourceId,
              shouldContinue: () => true,
            );
            await tester.pumpApp(
              CupertinoApp(
                home: MangaDetailsPage(
                  controller: catalog,
                  manga: MangaEntry(testManga),
                  chapters: _chapters('old').map(ChapterEntry.new).toList(),
                  source: source!,
                ),
              ),
            );
          } else {
            await tester.pumpApp(
              CupertinoApp(
                home: CupertinoPageScaffold(
                  child: LibraryPage(
                    controller: catalog,
                    onBrowse: () {},
                    onConnect: () {},
                    onAuthenticate: () {},
                  ),
                ),
              ),
            );
          }
          await tester.pumpAndSettle();
          final menu = tester.widget<CupertinoMenuAnchor>(
            find.byKey(
              fromDetails
                  ? const ValueKey('details-more')
                  : ValueKey(('library-more', sequence.mangaKey)),
            ),
          );
          final before = posts().length;
          final reads = platform.businessServer.requests.length;
          final calls = platform.invocations.length;
          final opened = platform.openedBuilds.length;
          // Run the real entry handler, then invalidate before the pushed
          // route's lazy builder receives its first frame.
          menu.menuChildren
              .whereType<CupertinoMenuItem>()
              .singleWhere(
                (item) =>
                    item.child is Text &&
                    (item.child as Text).data == '迁移到其他漫画源',
              )
              .onPressed!();
          expect(find.byType(MigrationPage), findsNothing);
          catalog.subject = replaceIdentity ? 'other-subject' : null;
          catalog.status = replaceIdentity
              ? ServiceStatus.ready
              : ServiceStatus.loginRequired;
          if (replaceIdentity) {
            expect(catalog.library!.client, isNot(same(clickedClient)));
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final page = tester.widget<MigrationPage>(find.byType(MigrationPage));
          expect(page.client, same(clickedClient));
          expect(find.text('身份或服务已改变，请关闭后重新开始迁移。'), findsOneWidget);
          expect(posts(), hasLength(before));
          expect(platform.businessServer.requests, hasLength(reads));
          expect(platform.invocations, hasLength(calls));
          expect(platform.openedBuilds, hasLength(opened));
          if (!replaceIdentity) {
            // Even restoring this exact client cannot reactivate an old seed.
            catalog.subject = 'owner-subject';
            catalog.status = ServiceStatus.ready;
            expect(catalog.library!.client, same(clickedClient));
            await catalog.refreshInstallations();
            await tester.pumpAndSettle();
            expect(find.text('迁移已停用'), findsOneWidget);
            expect(
              find.byKey(const ValueKey('migration-refresh-sources')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('migration-source')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('migration-confirm')),
              findsNothing,
            );
            expect(
              find.byKey(const ValueKey('migration-retry-original')),
              findsNothing,
            );
            expect(posts(), hasLength(before));
            expect(platform.invocations, hasLength(calls));
            expect(platform.openedBuilds, hasLength(opened));
          }
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'migration Cupertino states $brightness ${scale}x keep reads, drafts and original confirmation distinct',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final readPath = '/api/state/manga/${sequence.mangaKey}';
          final readGate = Completer<void>();
          var failRead = true;
          platform.beforeApiFetch = (path) async {
            if (Uri.parse(path).path == readPath) {
              await readGate.future;
            }
          };
          platform.afterBusinessReply = (request, reply) async {
            if (failRead &&
                request.method == 'GET' &&
                request.uri.path == readPath) {
              failRead = false;
              return ApiReply(
                status: 503,
                redirected: false,
                headers: reply.headers,
                body: reply.body,
              );
            }
            return reply;
          };
          addTearDown(() {
            if (!readGate.isCompleted) readGate.complete();
          });
          Widget page({bool fromShelf = false}) => CupertinoApp(
            home: MigrationPage(
              catalog: catalog,
              client: catalog.library!.client,
              seed: fromShelf ? MigrationSeed(metadata: seed.metadata) : seed,
            ),
          );
          Finder control(String key) => find.byKey(ValueKey(key));
          Future<void> reveal(
            Finder finder, {
            double delta = 300,
            bool settle = true,
          }) async {
            await tester.scrollUntilVisible(
              finder,
              delta,
              scrollable: find.byType(Scrollable).first,
            );
            if (settle) {
              await tester.pumpAndSettle();
            } else {
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 400));
            }
          }

          Future<void> tap(String key, {bool settle = true}) async {
            await reveal(control(key));
            await tester.tap(control(key));
            if (settle) {
              await tester.pumpAndSettle();
            } else {
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 400));
            }
          }

          Future<void> errorColor() async {
            final error = control('migration-error');
            await reveal(error, delta: -300);
            expect(error, findsOneWidget);
            expect(
              tester.renderObject<RenderParagraph>(error).text.style?.color,
              AppColors.error.resolveFrom(tester.element(error)),
            );
          }

          final writes = posts().length;
          final applied = platform.businessServer.appliedMutations;
          await tester.pumpApp(page());
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('没有其他已安装且启用的可用漫画源。请先在扩展管理中准备目标。'), findsNothing);
          expect(find.text('正在读取迁移输入'), findsOneWidget);
          expect(find.text('尚未读取迁移输入'), findsNothing);
          expect(posts(), hasLength(writes));
          readGate.complete();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          platform.beforeApiFetch = null;
          await errorColor();
          expect(find.byType(CupertinoActivityIndicator), findsNothing);
          expect(find.text('没有其他已安装且启用的可用漫画源。请先在扩展管理中准备目标。'), findsNothing);
          await tap('migration-refresh-sources');
          expect(control('migration-error'), findsNothing);
          expect(find.byType(CupertinoFormSection), findsWidgets);
          await tap('migration-source');
          await tester.tap(find.text('目标源 · zh · eu.kanade.source.test').last);
          await tester.pumpAndSettle();
          await reveal(control('migration-search'));
          await tester.tap(control('migration-search'));
          await tester.enterText(control('migration-search'), '目标作品');
          await tap('migration-search-submit');
          final rowWidth = tester.getSize(control('migration-search')).width;
          final firstResult = find.byKey(
            const ValueKey(('migration-result', 0)),
          );
          await reveal(firstResult);
          expect(
            tester.getSize(firstResult).width,
            greaterThanOrEqualTo(rowWidth),
            reason:
                'A short candidate title still needs a complete tappable row',
          );
          failRead = true;
          await tester.tapAt(
            tester.getRect(firstResult).centerRight - const Offset(8, 0),
          );
          await tester.pumpAndSettle();
          await errorColor();
          expect(control('migration-confirm'), findsNothing);
          expect(posts(), hasLength(writes));
          await tap('migration-refresh-preview');
          expect(control('migration-error'), findsNothing);
          final retained = find.text('目标将加入书架，原作品保留；目标已有分类、章节状态、书签、封面与阅读位置保留。');
          await reveal(retained);
          final semantics = tester.ensureSemantics();
          try {
            await tester.pump();
            expect(
              tester.getSemantics(retained).label,
              '目标将加入书架，原作品保留；目标已有分类、章节状态、书签、封面与阅读位置保留。',
              reason: 'Preview guidance must be readable separately from chapter mappings',
            );
            expect(
              tester
                  .getSemantics(
                    find.text('原作品：${seed.metadata.manga.title} · 原源 · en'),
                  )
                  .label,
              '原作品：${seed.metadata.manga.title} · 原源 · en',
            );
            expect(
              tester.getSemantics(control('migration-target-preview')).label,
              '目标：目标作品 · 目标源 · zh',
            );
          } finally {
            semantics.dispose();
          }
          expect(
            tester.renderObject<RenderParagraph>(retained).text.style?.color,
            AppColors.secondaryLabel.resolveFrom(tester.element(retained)),
          );
          expect(posts(), hasLength(writes));
          final chooseChapter = find.byKey(
            ValueKey(('migration-map-choose', sequence.entries.first.key)),
          );
          await reveal(chooseChapter);
          final mainScroll = tester.state<ScrollableState>(
            find.byType(Scrollable).first,
          );
          final beforeChoice = mainScroll.position.pixels;
          await tester.tap(chooseChapter);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(CupertinoTextField).last,
            '没有这个章节',
          );
          await tester.pumpAndSettle();
          expect(find.text('没有匹配的选项'), findsOneWidget);
          await tester.tap(find.byType(CupertinoNavigationBarBackButton).last);
          await tester.pumpAndSettle();
          expect(
            mainScroll.position.pixels,
            closeTo(beforeChoice, 1),
            reason:
                'Cancelling a chapter choice must keep the mapping position',
          );
          expect(
            Focus.of(
              tester.element(
                find.descendant(
                  of: chooseChapter,
                  matching: find.text('选择目标章节'),
                ),
              ),
            ).hasPrimaryFocus,
            isTrue,
            reason: 'Chapter choice must return keyboard focus to its trigger',
          );
          expect(tester.testTextInput.isVisible, isFalse);
          await tap('migration-confirm');
          final beforeConfirm = mainScroll.position.pixels;
          await tester.tap(find.text('返回检查'));
          await tester.pumpAndSettle();
          expect(
            mainScroll.position.pixels,
            closeTo(beforeConfirm, 1),
            reason: 'Cancelling confirmation must keep the review position',
          );
          expect(
            Focus.of(tester.element(find.text('检查并确认迁移'))).hasPrimaryFocus,
            isTrue,
            reason: 'Confirmation must return keyboard focus to its trigger',
          );
          expect(tester.testTextInput.isVisible, isFalse);
          expect(posts(), hasLength(writes));
          final saveGate = Completer<void>();
          addTearDown(() {
            if (!saveGate.isCompleted) saveGate.complete();
          });
          platform.beforeApiFetch = (path) async {
            if (Uri.parse(path).path == '/api/state/mutations') {
              await saveGate.future;
            }
          };
          platform.businessServer.loseNextResponse = true;
          await tap('migration-confirm');
          expect(find.byType(CupertinoAlertDialog), findsOneWidget);
          expect(
            find.textContaining(
              '原作品“${seed.metadata.manga.title}”（原源 · en）保留。',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining('将目标“目标作品”（目标源 · zh）加入书架。'),
            findsOneWidget,
          );
          expect(find.textContaining('选中 1 条章节映射'), findsOneWidget);
          expect(posts(), hasLength(writes));
          await tap('migration-confirm-send', settle: false);
          await reveal(find.text('正在等待服务端确认'), delta: -300, settle: false);
          expect(find.text('正在等待服务端确认'), findsOneWidget);
          expect(find.textContaining('迁移已由服务端确认'), findsNothing);
          expect(control('migration-search'), findsNothing);
          expect(
            tester
                .widget<CupertinoButton>(control('migration-retry-original'))
                .onPressed,
            isNull,
          );
          saveGate.complete();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          platform.beforeApiFetch = null;
          await errorColor();
          final original = posts().last;
          final command = wire.decodeProtoJson(
            wire.StateMutation(),
            jsonDecode(original),
          );
          expect(posts(), hasLength(writes + 1));
          expect(platform.businessServer.appliedMutations, applied + 1);
          expect(find.textContaining(command.mutationId), findsNothing);
          expect(find.textContaining(command.mangaKey), findsNothing);
          await tap('migration-original-details');
          expect(find.textContaining(command.mutationId), findsOneWidget);
          expect(posts(), hasLength(writes + 1));
          await tester.tap(find.text('关闭'));
          await tester.pumpAndSettle();
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
          final reopenGate = Completer<void>();
          addTearDown(() {
            if (!reopenGate.isCompleted) reopenGate.complete();
          });
          platform.beforeApiFetch = (path) async {
            if (Uri.parse(path).path == readPath) {
              await reopenGate.future;
            }
          };
          await tester.pumpApp(page(fromShelf: true));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('正在读取迁移输入'), findsOneWidget);
          await reveal(find.text('原迁移尚未确认'), settle: false);
          expect(find.text('原操作的复制范围已固定，原作品保留。'), findsOneWidget);
          expect(find.text('先读取原源章节，或明确选择仅迁移收藏和分类。'), findsNothing);
          expect(find.text('等待服务端确认'), findsNothing);
          expect(posts(), hasLength(writes + 1));
          reopenGate.complete();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          platform.beforeApiFetch = null;
          expect(find.text('目标作品 · 目标源 · zh'), findsOneWidget);
          expect(find.textContaining(command.mutationId), findsNothing);
          expect(posts(), hasLength(writes + 1));
          failRead = true;
          await tap('migration-refresh-sources');
          await errorColor();
          expect(find.text('本次读取未完成，请重新读取。原迁移操作保持不变。'), findsOneWidget);
          expect(find.text('原迁移尚未确认'), findsOneWidget);
          expect(control('migration-search'), findsNothing);
          expect(posts(), hasLength(writes + 1));
          expect(platform.businessServer.appliedMutations, applied + 1);
          await tap('migration-retry-original');
          expect(find.textContaining('原迁移操作已由服务端确认'), findsOneWidget);
          expect(find.text('原作品已保留；迁移结果见下方服务端确认。'), findsOneWidget);
          expect(find.text('先读取原源章节，或明确选择仅迁移收藏和分类。'), findsNothing);
          expect(find.text('目标作品 · 目标源 · zh'), findsOneWidget);
          expect(posts(), hasLength(writes + 2));
          expect(posts().last, original);
          expect(platform.businessServer.appliedMutations, applied + 1);
          expect(tester.takeException(), isNull);
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets(
    'retiring a scrolled migration starts with the full warning visible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpApp(
        CupertinoApp(
          home: MigrationPage(
            catalog: catalog,
            client: catalog.library!.client,
            seed: seed,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final writes = posts().length;
      final scrollable = find.byType(Scrollable).first;
      Future<void> tap(Finder finder) async {
        await tester.scrollUntilVisible(finder, 220, scrollable: scrollable);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap(find.byKey(const ValueKey('migration-source')));
      await tester.tap(find.text('目标源 · zh · eu.kanade.source.test').last);
      await tester.pumpAndSettle();
      await tap(find.byKey(const ValueKey('migration-search-submit')));
      await tap(find.byKey(const ValueKey(('migration-result', 0))));
      final reload = find.byKey(const ValueKey('migration-refresh-preview'));
      await tester.scrollUntilVisible(reload, 220, scrollable: scrollable);
      final previous = tester.state<ScrollableState>(scrollable);
      expect(previous.position.pixels, greaterThan(0));

      platform.loginHtml = true;
      await tester.runAsync(catalog.connect);
      expect(catalog.accessPaused, isTrue);
      await tester.pump();
      final warning = find.byKey(const ValueKey('migration-error'));
      expect(warning, findsOneWidget);
      expect(find.text('迁移已停用'), findsOneWidget);
      final navigationBottom = tester
          .getBottomLeft(find.byType(CupertinoNavigationBar))
          .dy;
      expect(tester.getTopLeft(warning).dy, greaterThan(navigationBottom));
      expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
      expect(posts(), hasLength(writes));
      expect(tester.takeException(), isNull);
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'wizard browses a target without search results and filters marks before confirmation',
    (tester) async {
      final normal = platform.invokeHandler!;
      var entered = Completer<void>();
      var release = Completer<void>();
      platform.invokeHandler = (call) async {
        if (call.hasSearch()) {
          return wire.SourceResult(mangaPage: wire.MangaPage());
        }
        if (call.hasPopular()) {
          entered.complete();
          await release.future;
          return wire.SourceResult(
            mangaPage: wire.MangaPage(
              mangas: [
                if (call.popular.page == 1)
                  _target
                else
                  wire.Manga(url: '/another', title: '第二页作品'),
              ],
              hasNextPage: call.popular.page == 1,
            ),
          );
        }
        return normal(call);
      };
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpApp(
        CupertinoApp(
          home: MigrationPage(
            catalog: catalog,
            client: catalog.library!.client,
            seed: seed,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = posts().length;
      await tester.tap(find.byKey(const ValueKey('migration-source')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('目标源 · zh · eu.kanade.source.test').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('migration-search-submit')));
      await tester.pumpAndSettle();
      expect(find.text('没有搜索结果，可尝试浏览目标源热门作品。'), findsOneWidget);
      expect(platform.invocations.where((call) => call.hasPopular()), isEmpty);
      await tester.tap(find.byKey(const ValueKey('migration-popular')));
      try {
        await tester.pump();
        await tester.runAsync(
          () => entered.future.timeout(const Duration(seconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.ensureVisible(find.byType(CupertinoActivityIndicator));
        await tester.pump();
        expect(find.text('正在浏览目标源热门作品'), findsOneWidget);
        expect(posts(), hasLength(before));
      } finally {
        release.complete();
        await tester.pumpAndSettle();
      }
      expect(find.text('目标作品'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('migration-search')),
        '尚未提交的新查询',
      );
      await tester.pumpAndSettle();
      entered = Completer<void>();
      release = Completer<void>();
      final more = find.byKey(const ValueKey('migration-search-more'));
      await tester.ensureVisible(more);
      await tester.tap(more);
      try {
        await tester.pump();
        await tester.runAsync(
          () => entered.future.timeout(const Duration(seconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await tester.ensureVisible(find.byType(CupertinoActivityIndicator));
        await tester.pump();
        expect(find.text('正在加载更多目标源热门作品'), findsOneWidget);
        expect(posts(), hasLength(before));
      } finally {
        release.complete();
        await tester.pumpAndSettle();
      }
      expect(find.text('第二页作品'), findsOneWidget);
      final popular = platform.invocations.where((call) => call.hasPopular());
      expect(popular.map((call) => call.popular.page), [1, 2]);
      expect(popular.every((call) => call.sourceId == _targetId), true);
      expect(find.text('没有搜索结果，可尝试浏览目标源热门作品。'), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey(('migration-result', 0))),
      );
      await tester.tap(find.byKey(const ValueKey(('migration-result', 0))));
      await tester.pumpAndSettle();
      final filter = find.byKey(const ValueKey('migration-only-marked'));
      final scroller = find.byType(Scrollable).first;
      final marked = find.byKey(
        ValueKey(('migration-map-selected', sequence.entries[0].key)),
      );
      final unmarked = find.byKey(
        ValueKey(('migration-map-selected', sequence.entries[1].key)),
      );
      await tester.scrollUntilVisible(unmarked, 300, scrollable: scroller);
      expect(unmarked, findsOneWidget);
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(unmarked, findsNothing);
      expect(tester.widget<CupertinoCheckbox>(marked).value, true);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(unmarked, findsOneWidget);
      expect(tester.widget<CupertinoCheckbox>(marked).value, true);
      final confirm = find.byKey(const ValueKey('migration-confirm'));
      await tester.scrollUntilVisible(
        confirm,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey('migration-target-preview')),
        findsOneWidget,
      );
      expect(posts(), hasLength(before));
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(posts(), hasLength(before));
      await tester.tap(find.byKey(const ValueKey('migration-confirm-send')));
      await tester.pumpAndSettle();
      expect(find.textContaining('迁移已由服务端确认'), findsOneWidget);
      expect(posts(), hasLength(before + 1));
      final operation = wire.decodeProtoJson(
        wire.StateMutation(),
        jsonDecode(posts().last),
      );
      expect(operation.migrateFrom.chapters.single.copyRead, true);
      expect(operation.migrateFrom.chapters.single.copyBookmark, true);
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
