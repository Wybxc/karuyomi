import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/bookmark_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/features/migration/migration_controller.dart';
import 'package:karuyomi/features/migration/migration_page.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
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
      wire.SourceInfo(id: sourceId, name: '原源', lang: 'zh'),
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
      sourceLang: 'zh',
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
        sourceLang: 'zh',
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
  Future<void> targetPreview() async {
    await controller.refreshSources();
    await controller.chooseSource(controller.sources.single);
    await controller.search('原作品');
    await controller.chooseManga(controller.results.first);
  }

  test(
    'installed Source search pagination, details, mapping and confirmation retain the source without copying anchors',
    () async {
      final before = posts().length;
      await controller.refreshSources();
      expect(controller.sources.single.source.id, _targetId);
      await controller.chooseSource(controller.sources.single);
      await controller.search('原作品');
      await controller.loadMore();
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
    },
  );

  test(
    'lost ACK survives closing the wizard and only explicit retry resends its original body',
    () async {
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
      await controller.retry();
      expect(controller.completed, true, reason: controller.error);
      expect(posts().last, original);
      expect(posts(), hasLength(count + 1));
    },
  );

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

  test(
    'changing an already selected mapping to a fully populated target removes its disabled selection',
    () async {
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
            .progress(
              targetSequence.mangaKey,
              targetSequence.entries.first.key,
            )!
            .completed,
        false,
      );
    },
  );

  test(
    'more than 256 selected chapters require an explicit smaller selection before any migration POST',
    () async {
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
    },
  );

  test(
    'closing during a read-only preview stops subsequent reads and never submits migration',
    () async {
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
    },
  );

  testWidgets(
    'Library menu opens migration without loading the original Source',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryPage(
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
      await tester.pumpWidget(const SizedBox.shrink());
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
      await tester.pumpWidget(
        MaterialApp(
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
      await tester.pumpWidget(const SizedBox.shrink());
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
            await tester.pumpWidget(
              MaterialApp(
                home: MangaDetailsPage(
                  controller: catalog,
                  manga: MangaEntry(testManga),
                  chapters: _chapters('old').map(ChapterEntry.new).toList(),
                  source: source!,
                ),
              ),
            );
          } else {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: LibraryPage(
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
          final menu = tester.widget<PopupMenuButton<String>>(
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
          menu.onSelected!('migrate');
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
            expect(
              tester
                  .widget<TextButton>(
                    find.byKey(const ValueKey('migration-refresh-sources')),
                  )
                  .onPressed,
              isNull,
            );
            expect(posts(), hasLength(before));
            expect(platform.invocations, hasLength(calls));
            expect(platform.openedBuilds, hasLength(opened));
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets(
    'wizard browses a target without search results and filters marks before confirmation',
    (tester) async {
      final normal = platform.invokeHandler!;
      platform.invokeHandler = (call) async {
        if (call.hasSearch()) {
          return wire.SourceResult(mangaPage: wire.MangaPage());
        }
        if (call.hasPopular()) {
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
      await tester.binding.setSurfaceSize(const Size(700, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
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
      await tester.pumpAndSettle();
      expect(find.text('目标作品'), findsOneWidget);
      final more = find.byKey(const ValueKey('migration-search-more'));
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
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
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(unmarked, findsNothing);
      expect(tester.widget<CheckboxListTile>(marked).value, true);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(unmarked, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(marked).value, true);
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
      expect(find.byType(AlertDialog), findsOneWidget);
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
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
