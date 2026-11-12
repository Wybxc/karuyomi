import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/bookmark_repository.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/progress/chapter_read_batch.dart';
import 'package:karuyomi/features/progress/chapter_read_controller.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/business_state_server.dart';
import 'fakes.dart';

List<wire.Chapter> get _chapters => [
  wire.Chapter(
    url: '/duplicate',
    name: '同名章',
    scanlator: '甲组',
    sourceOrder: 16,
    memoJson: '{"edition":"a"}',
  ),
  wire.Chapter(
    url: '/middle',
    name: '中章',
    chapterNumber: 0.5,
    scanlator: '特别组',
    sourceOrder: 2,
  ),
  wire.Chapter(
    url: '/duplicate',
    name: '同名章',
    scanlator: '乙组',
    sourceOrder: 8,
    memoJson: '{"edition":"b"}',
  ),
  wire.Chapter(url: '/tail', name: '尾章', sourceOrder: 1),
];

ChapterSequence get _sequence => ChapterSequence(
  packageName: 'eu.kanade.source.test',
  sourceId: sourceId,
  mangaUrl: testManga.url,
  chapters: _chapters,
);

TestPlatform _platform() =>
    TestPlatform()
      ..invokeHandler = (call) async => switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(manga: testManga),
        wire.SourceCall_Request.chapters => wire.SourceResult(
          chapters: wire.ChapterList(chapters: _chapters),
        ),
        wire.SourceCall_Request.pages => throw StateError(
          'Chapter marking must not fetch Source pages',
        ),
        _ => wire.SourceResult(mangaPage: wire.MangaPage(mangas: [testManga])),
      };

BusinessStateClient _remote(TestPlatform platform) {
  final client = BusinessStateClient(
    api: platform.businessServer,
    identity: ProgressIdentity(
      origin: platform.origin,
      subject: platform.bootstrapSubject,
    ),
  );
  addTearDown(client.dispose);
  return client;
}

Finder _control(String key) => find.byKey(ValueKey(key));
Finder _row(int index) => find.byKey(ValueKey(_sequence.entries[index].key));
Finder _readFilter(String name) =>
    find.byKey(ValueKey(('chapter-read-filter', name)));
Finder _preview(int index) =>
    find.byKey(ValueKey(('chapter-read-item', _sequence.entries[index].key)));

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
          of: find.byType(MangaDetailsPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(scrollable, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 250, scrollable: scrollable);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Future<CatalogController> _details(
  WidgetTester tester,
  TestPlatform platform,
) async {
  await tester.pumpWidget(KaruyomiApp(platform: platform));
  await tester.pumpAndSettle();
  await _tap(tester, find.text('去浏览'));
  final catalog = find.byType(CatalogPage);
  final scrollable = find
      .descendant(of: catalog, matching: find.byType(Scrollable))
      .first;
  for (final finder in [
    find.text('eu.kanade.source.test · 1.0'),
    find.byKey(ValueKey(('catalog-source', sourceId))),
    find.text('真实源 DTO 测试'),
  ]) {
    final target = find.descendant(of: catalog, matching: finder);
    await tester.scrollUntilVisible(target, 250, scrollable: scrollable);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }
  return tester
      .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
      .controller;
}

Future<void> _finish(
  WidgetTester tester,
  TestPlatform platform,
  CatalogController catalog,
) async {
  expect(
    platform.invocations.where(
      (call) => call.whichRequest() == wire.SourceCall_Request.pages,
    ),
    isEmpty,
  );
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(catalog.closeReadingProgress);
}

Future<void> _search(WidgetTester tester, String query) async {
  await _reveal(tester, _control('chapter-search'));
  await tester.enterText(_control('chapter-search'), query);
  await tester.pumpAndSettle();
}

Future<void> _shown(WidgetTester tester, List<int> indices) async {
  final count = find.text('显示 ${indices.length} / 4 章');
  await _reveal(tester, count);
  expect(count, findsOneWidget);
  for (final index in indices) {
    await _reveal(tester, _row(index));
    expect(_row(index), findsOneWidget);
  }
}

Future<void> _selectAll(WidgetTester tester) async {
  await _tap(tester, _control('chapter-selection-toggle'));
  await _tap(tester, _control('chapter-select-visible'));
}

Future<void> _confirmFirstThree(WidgetTester tester) async {
  await _tap(tester, _control('chapter-selection-toggle'));
  await _tap(tester, _control('chapter-range-start'));
  await _tap(tester, find.text('同名章 · 来源第 1 项').last);
  await _tap(tester, _control('chapter-range-end'));
  await _tap(tester, find.text('同名章 · 来源第 3 项').last);
  await _tap(tester, _control('chapter-select-range'));
  await _tap(tester, _control('chapter-mark-read'));
  expect(find.text('确认清单：3 章'), findsOneWidget);
  await _tap(tester, find.text('确认并开始'));
  expect(find.text('全部标记已由服务端确认。'), findsOneWidget);
}

Future<void> _back(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.binding.handlePopRoute();
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

List<TestBusinessRequest> _posts(TestPlatform platform) => platform
    .businessServer
    .requests
    .where((request) => request.method == 'POST')
    .toList();
wire.StateMutation _command(TestBusinessRequest request) =>
    wire.decodeProtoJson(wire.StateMutation(), jsonDecode(request.body!));

void main() {
  for (final retire in [false, true]) {
    test(
      'a queued chapter refresh respects an in-flight read and retirement: $retire',
      () async {
        final platform = _platform();
        final repo = ProgressRepository(_remote(platform));
        var isCurrent = true;
        final controller = ChapterReadController(
          repository: repo,
          mangaKey: _sequence.mangaKey,
          isCurrent: () => isCurrent,
        );
        addTearDown(controller.dispose);
        final entered = Completer<void>();
        final release = Completer<void>();
        var reads = 0;
        platform.businessServer.beforeRequest = (request) async {
          if (request.uri.path.endsWith('/progress') && ++reads == 1) {
            entered.complete();
            await release.future;
          }
          return null;
        };

        final initial = controller.refresh();
        await entered.future;
        final queued = controller.refreshAfterCurrent();
        expect(reads, 1);
        if (retire) {
          isCurrent = false;
          controller.checkCurrent();
        }
        release.complete();
        await Future.wait([initial, queued]);
        expect(reads, retire ? 1 : 2);
        expect(controller.loaded, !retire);
        expect(controller.busy, isFalse);
      },
    );
  }

  testWidgets(
    'complete read state treats missing rows as unread and intersects bookmarks and search',
    (tester) async {
      final platform = _platform();
      final seed = _remote(platform);
      await tester.runAsync(() async {
        await ProgressRepository(seed).setChapterRead(
          mangaKey: _sequence.mangaKey,
          chapterKey: _sequence.entries[0].key,
          read: true,
          basedOnRevision: 0,
        );
        final bookmarks = BookmarkRepository(seed);
        await bookmarks.set(
          mangaKey: _sequence.mangaKey,
          chapterKey: _sequence.entries[0].key,
          bookmarked: true,
          basedOnRevision: 1,
        );
        await bookmarks.set(
          mangaKey: _sequence.mangaKey,
          chapterKey: _sequence.entries[2].key,
          bookmarked: true,
          basedOnRevision: 2,
        );
      });
      final catalog = await _details(tester, platform);
      final calls = platform.invocations.length;
      platform.businessServer.requests.clear();
      await _shown(tester, [0, 1, 2, 3]);
      await _reveal(tester, _row(0));
      expect(
        find.descendant(of: _row(0), matching: find.textContaining('已读')),
        findsOneWidget,
      );
      await _reveal(tester, _row(1));
      expect(
        find.descendant(of: _row(1), matching: find.textContaining('未读')),
        findsOneWidget,
      );
      expect(
        platform.businessServer.progress(
          _sequence.mangaKey,
          _sequence.entries[1].key,
        ),
        isNull,
      );
      await _tap(tester, _readFilter('unread'));
      await _shown(tester, [1, 2, 3]);
      await _tap(tester, find.widgetWithText(FilterChip, '仅书签'));
      await _search(tester, '同名');
      await _shown(tester, [2]);
      await _tap(tester, _readFilter('read'));
      await _shown(tester, [0]);
      await _search(tester, '特别组');
      await _shown(tester, []);
      expect(_posts(platform), isEmpty);
      expect(platform.invocations, hasLength(calls));
      await _finish(tester, platform, catalog);
    },
  );

  testWidgets(
    'visible selection and reversed ranges preserve hidden independent chapter occurrences',
    (tester) async {
      final platform = _platform();
      final catalog = await _details(tester, platform);
      platform.businessServer.requests.clear();
      await _tap(tester, _control('chapter-selection-toggle'));
      await _search(tester, '中章');
      await _tap(tester, _control('chapter-select-visible'));
      await _search(tester, '同名');
      await _tap(tester, _control('chapter-select-visible'));
      expect(find.text('已选 3 章 · 当前隐藏 1 章'), findsOneWidget);
      await _tap(tester, _control('chapter-deselect-visible'));
      expect(find.text('已选 1 章 · 当前隐藏 1 章'), findsOneWidget);
      await _tap(tester, _control('chapter-select-visible'));
      await _search(tester, '');
      await _tap(tester, _control('chapter-clear-selection'));
      await _tap(tester, _control('chapter-list-order'));
      await _tap(tester, find.text('反向来源顺序').last);
      await _tap(tester, _control('chapter-range-start'));
      await _tap(tester, find.text('同名章 · 来源第 3 项').last);
      await _tap(tester, _control('chapter-range-end'));
      await _tap(tester, find.text('同名章 · 来源第 1 项').last);
      await _tap(tester, _control('chapter-select-range'));
      for (final index in [0, 1, 2, 3]) {
        final checkbox = find.byKey(
          ValueKey(('chapter-select', _sequence.entries[index].key)),
        );
        await _reveal(tester, checkbox);
        expect(tester.widget<Checkbox>(checkbox).value, index != 3);
      }
      await _search(tester, '同名');
      await _tap(tester, _control('chapter-mark-read'));
      expect(find.text('确认清单：3 章'), findsOneWidget);
      expect(
        tester
            .widgetList<ListTile>(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(ListTile),
              ),
            )
            .map((tile) => tile.key),
        [
          for (final index in [2, 1, 0])
            ValueKey(('chapter-read-item', _sequence.entries[index].key)),
        ],
      );
      for (final index in [2, 1, 0]) {
        final item = tester.widget<ListTile>(_preview(index));
        expect((item.title! as Text).data, _chapters[index].name);
        expect((item.subtitle! as Text).data, '来源第 ${index + 1} 项');
      }
      expect(_posts(platform), isEmpty);
      await _tap(tester, find.text('取消'));
      await _finish(tester, platform, catalog);
    },
  );

  testWidgets(
    'same-detail favorite then range marking confirms the new exact revision',
    (tester) async {
      final platform = _platform();
      final catalog = await _details(tester, platform);
      platform.businessServer.requests.clear();

      await _tap(tester, find.text('加入书架'));
      expect(platform.businessServer.manga(_sequence.mangaKey)?.favorite, true);

      await _confirmFirstThree(tester);
      final commands = _posts(platform).map(_command).toList();
      expect(commands.map((command) => command.expectedRevision), [0, 1, 2, 3]);
      expect(commands.first.setFavorite.favorite, isTrue);
      expect(
        commands.skip(1).map((command) => command.setChapterRead.chapterKey),
        [for (final chapter in _sequence.entries.take(3)) chapter.key],
      );
      expect(
        commands.skip(1).every((command) => command.setChapterRead.read),
        isTrue,
      );
      await _back(tester);
      await _finish(tester, platform, catalog);
    },
  );

  for (final loseAck in [false, true]) {
    testWidgets(
      'same-detail bookmark then range uses the confirmed revision (lost ACK: $loseAck)',
      (tester) async {
        final platform = _platform();
        final catalog = await _details(tester, platform);
        final server = platform.businessServer;
        final mangaKey = _sequence.mangaKey;
        final bookmarkKey = _sequence.entries.last.key;
        server.requests.clear();
        if (loseAck) {
          platform.afterBusinessReply = (request, reply) {
            if (request.method != 'POST') return reply;
            platform.afterBusinessReply = null;
            return const ApiReply(
              status: 503,
              headers: {'content-type': 'text/plain'},
              body: 'Bookmark acknowledgement unavailable',
              redirected: false,
            );
          };
        }

        await _tap(tester, _control('chapter-bookmark-$bookmarkKey'));
        expect(server.bookmarked(mangaKey, bookmarkKey), isTrue);
        if (loseAck) {
          final original = _posts(platform).single.body;
          expect(
            server.requests.where(
              (request) => request.uri.path.endsWith('/progress'),
            ),
            isEmpty,
          );
          await _tap(tester, find.text('重试原书签操作'));
          expect(_posts(platform).map((request) => request.body), [
            original,
            original,
          ]);
        }

        final bookmarkRequests = loseAck ? 2 : 1;
        await _confirmFirstThree(tester);
        final commands = _posts(platform).map(_command).toList();
        expect(commands.map((command) => command.expectedRevision), [
          0,
          if (loseAck) 0,
          1,
          2,
          3,
        ]);
        expect(commands.first.setBookmark.chapterKey, bookmarkKey);
        expect(
          commands
              .skip(bookmarkRequests)
              .map((command) => command.setChapterRead.chapterKey),
          [for (final chapter in _sequence.entries.take(3)) chapter.key],
        );
        expect(server.progress(mangaKey, bookmarkKey), isNull);
        expect(server.bookmarked(mangaKey, bookmarkKey), isTrue);
        await _back(tester);
        await _finish(tester, platform, catalog);
      },
    );
  }

  testWidgets(
    'read and unread marking keeps resume and system back clears the confirmed selection',
    (tester) async {
      final platform = _platform();
      final seed = _remote(platform);
      final manifest = ChapterManifest(
        chapterKey: _sequence.entries[3].key,
        version: 'saved-manifest',
        pages: [ReaderPage(key: 'saved-page')],
      );
      await tester.runAsync(
        () => ProgressRepository(seed).save(
          mangaKey: _sequence.mangaKey,
          manifest: manifest,
          progress: ChapterProgress(
            current: manifest.positionAt(0, offset: .4),
          ),
          reversedOrder: true,
        ),
      );
      final before = platform.businessServer.manga(_sequence.mangaKey)!;
      final catalog = await _details(tester, platform);
      platform.businessServer.requests.clear();
      await _search(tester, '同名');
      await _selectAll(tester);
      await _tap(tester, _control('chapter-mark-read'));
      await _tap(tester, find.text('确认并开始'));
      expect(find.text('全部标记已由服务端确认。'), findsOneWidget);
      expect(
        _posts(platform).map(_command).map((value) => value.expectedRevision),
        [1, 2],
      );
      await _back(tester);
      await _reveal(tester, _control('chapter-selection-toggle'));
      expect(find.text('选择章节'), findsOneWidget);
      expect(find.textContaining('已选 '), findsNothing);
      await _tap(tester, _readFilter('read'));
      await _shown(tester, [2, 0]);
      await _selectAll(tester);
      await _tap(tester, _control('chapter-mark-unread'));
      await _tap(tester, find.text('确认并开始'));
      await _back(tester);
      await _search(tester, '');
      await _tap(tester, _readFilter('unread'));
      await _shown(tester, [3, 2, 1, 0]);
      final after = platform.businessServer.manga(_sequence.mangaKey)!;
      expect(after.resume, before.resume);
      for (final index in [0, 2]) {
        final state = platform.businessServer.progress(
          _sequence.mangaKey,
          _sequence.entries[index].key,
        )!;
        expect(state.completed, false);
        expect(state.epoch, 2);
        expect(state.hasCurrent(), false);
      }
      expect(
        _posts(
          platform,
        ).map(_command).every((value) => value.hasSetChapterRead()),
        true,
      );
      await _finish(tester, platform, catalog);
    },
  );

  testWidgets(
    'partial marking retries only its exact uncertain command before explicit remaining writes',
    (tester) async {
      final platform = _platform();
      final catalog = await _details(tester, platform);
      platform.businessServer.requests.clear();
      var replies = 0;
      platform.afterBusinessReply = (request, reply) {
        if (request.method != 'POST' ||
            request.uri.path != '/api/state/mutations') {
          return reply;
        }
        if (++replies != 2) return reply;
        platform.afterBusinessReply = null;
        return const ApiReply(
          status: 503,
          headers: {'content-type': 'text/plain'},
          body: 'Acknowledgement unavailable',
          redirected: false,
        );
      };
      await _selectAll(tester);
      await _tap(tester, _control('chapter-mark-read'));
      await _tap(tester, find.text('确认并开始'));
      expect(find.text('已确认 1 / 4 章 · 未开始 2 章'), findsOneWidget);
      expect(find.text('全部标记已由服务端确认。'), findsNothing);
      expect(_posts(platform), hasLength(2));
      final uncertain = _posts(platform).last.body;
      await _tap(tester, find.text('稍后处理'));
      await _tap(tester, _control('chapter-read-resume'));
      expect(_posts(platform), hasLength(2));
      await _tap(tester, find.text('重试原未确认操作'));
      expect(_posts(platform), hasLength(3));
      expect(_posts(platform).last.body, uncertain);
      expect(find.text('已确认 2 / 4 章 · 未开始 2 章'), findsOneWidget);
      expect(
        platform.businessServer.progress(
          _sequence.mangaKey,
          _sequence.entries[2].key,
        ),
        isNull,
      );
      await _tap(tester, find.text('继续剩余原清单'));
      expect(find.text('全部标记已由服务端确认。'), findsOneWidget);
      expect(
        _posts(platform).map(_command).map((value) => value.expectedRevision),
        [0, 1, 1, 2, 3],
      );
      expect(
        _posts(platform).map(_command).map((value) => value.mutationId).toSet(),
        hasLength(4),
      );
      await _back(tester);
      await _tap(tester, _readFilter('read'));
      await _shown(tester, [0, 1, 2, 3]);

      final detail = tester.widget<MangaDetailsPage>(
        find.byType(MangaDetailsPage),
      );
      final repository = catalog.readingProgress!;
      final snapshot = (await tester.runAsync(
        () => repository.loadAll(_sequence.mangaKey),
      ))!;
      final pending = ChapterReadBatchDraft(
        repository: repository,
        mangaKey: _sequence.mangaKey,
        read: false,
        revision: snapshot.revision,
        chapters: [_sequence.entries[0], _sequence.entries[2]],
      );
      platform.afterBusinessReply = (request, reply) {
        if (request.method != 'POST' ||
            request.uri.path != '/api/state/mutations') {
          return reply;
        }
        platform.afterBusinessReply = null;
        return const ApiReply(
          status: 503,
          headers: {'content-type': 'text/plain'},
          body: 'Original snapshot acknowledgement unavailable',
          redirected: false,
        );
      };
      final beforePending = _posts(platform).length;
      await tester.runAsync(() => pending.start(isCurrent: () => true));
      final frozenBody = _posts(platform).last.body;
      expect(pending.canRetry, true);
      final changedChapters = [
        ..._chapters,
        wire.Chapter(url: '/new-chapter', name: '新增章'),
      ];
      final changedSequence = ChapterSequence(
        packageName: 'eu.kanade.source.test',
        sourceId: sourceId,
        mangaUrl: testManga.url,
        chapters: changedChapters,
      );
      expect(
        changedSequence.entries.first.key,
        isNot(_sequence.entries.first.key),
      );
      await tester.runAsync(() async {
        unawaited(
          Navigator.of(
            tester.element(find.byType(MangaDetailsPage)),
          ).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => MangaDetailsPage(
                controller: catalog,
                manga: detail.manga,
                chapters: changedChapters.map(ChapterEntry.new).toList(),
                source: detail.source,
              ),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(
        pendingChapterReadBatch(repository, _sequence.mangaKey),
        same(pending),
      );
      expect(pending.remainingKeys, {
        _sequence.entries[0].key,
        _sequence.entries[2].key,
      });
      await _tap(tester, _control('chapter-read-resume'));
      expect(_preview(0), findsOneWidget);
      expect(_preview(2), findsOneWidget);
      expect(_posts(platform), hasLength(beforePending + 1));
      await _tap(tester, find.text('重试原未确认操作'));
      expect(_posts(platform).last.body, frozenBody);
      expect(pending.remainingKeys, {_sequence.entries[2].key});
      await _tap(tester, find.text('结束剩余操作'));
      await _back(tester);
      final unmatched = find.text('原清单中 1 章已不在当前章节列表，未转入新选择，也未自动映射到其它章节。');
      await _reveal(tester, unmatched);
      expect(unmatched, findsOneWidget);
      await _reveal(tester, _control('chapter-selection-toggle'));
      expect(find.text('选择章节'), findsOneWidget);
      expect(find.textContaining('已选 '), findsNothing);
      await _tap(tester, _control('chapter-selection-toggle'));
      await _tap(
        tester,
        find.byKey(
          ValueKey(('chapter-select', changedSequence.entries.first.key)),
        ),
      );
      await _tap(tester, _control('chapter-mark-read'));
      expect(find.text('确认清单：1 章'), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(('chapter-read-item', changedSequence.entries.first.key)),
        ),
        findsOneWidget,
      );
      expect(_posts(platform), hasLength(beforePending + 2));
      await _tap(tester, find.text('取消'));
      await _finish(tester, platform, catalog);
    },
  );

  testWidgets(
    'an open marking batch keeps its old revision and ends a conflict through readonly refresh',
    (tester) async {
      final platform = _platform();
      final remote = ProgressRepository(_remote(platform));
      final catalog = await _details(tester, platform);
      await _selectAll(tester);
      await _tap(tester, _control('chapter-mark-read'));
      await tester.runAsync(
        () => remote.setChapterRead(
          mangaKey: _sequence.mangaKey,
          chapterKey: _sequence.entries[2].key,
          read: true,
          basedOnRevision: 0,
        ),
      );
      platform.businessServer.requests.clear();
      await _tap(tester, find.text('确认并开始'));
      expect(find.textContaining('重新读取章节状态'), findsWidgets);
      expect(find.text('重试原未确认操作'), findsNothing);
      expect(find.text('继续剩余原清单'), findsNothing);
      expect(_posts(platform).length, lessThanOrEqualTo(1));
      expect(
        _posts(
          platform,
        ).map(_command).every((value) => value.expectedRevision == 0),
        true,
      );
      final posts = _posts(platform).length;
      await _tap(tester, find.text('重新读取并结束原批次'));
      expect(_posts(platform), hasLength(posts));
      expect(find.text('全部标记已由服务端确认。'), findsNothing);
      expect(
        platform.businessServer.progress(
          _sequence.mangaKey,
          _sequence.entries[0].key,
        ),
        isNull,
      );
      await _back(tester);
      await _tap(tester, _readFilter('read'));
      await _shown(tester, [2]);
      expect(_posts(platform), hasLength(posts));
      await _finish(tester, platform, catalog);
    },
  );

  testWidgets(
    'repository replacement permanently retires a busy modal and late ACK cannot continue under another identity',
    (tester) async {
      final platform = _platform();
      final catalog = await _details(tester, platform);
      platform.businessServer.requests.clear();
      final received = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      platform.afterBusinessReply = (request, reply) async {
        if (request.method != 'POST' ||
            request.uri.path != '/api/state/mutations') {
          return reply;
        }
        platform.afterBusinessReply = null;
        received.complete();
        await release.future;
        return reply;
      };
      await _selectAll(tester);
      await _tap(tester, _control('chapter-mark-read'));
      await tester.runAsync(() async {
        await tester.tap(find.text('确认并开始'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 32));
      await tester.runAsync(
        () => received.future.timeout(const Duration(seconds: 5)),
      );
      expect(find.text('全部标记已由服务端确认。'), findsNothing);
      await tester.runAsync(catalog.connect);
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.textContaining('原窗口已停用'), findsOneWidget);
      platform.bootstrapSubject = 'another-subject';
      await tester.runAsync(catalog.connect);
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.textContaining('原窗口已停用'), findsOneWidget);
      await tester.runAsync(() async {
        release.complete();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('全部标记已由服务端确认。'), findsNothing);
      expect(_posts(platform), hasLength(1));
      for (final chapter in _sequence.entries) {
        expect(
          platform.businessServer.progress(
            _sequence.mangaKey,
            chapter.key,
            subject: 'another-subject',
          ),
          isNull,
        );
      }
      await _back(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(MangaDetailsPage), findsOneWidget);
      expect(find.textContaining('漫画源会话已变化'), findsOneWidget);
      await _finish(tester, platform, catalog);
    },
  );

  testWidgets(
    'late Source pages are closed when the same detail state receives a different manga',
    (tester) async {
      final platform = _platform();
      final received = Completer<void>();
      final pages = Completer<wire.SourceResult>();
      final closed = Completer<void>();
      final closedSessions = <String>[];
      wire.SourceResult latePages() => wire.SourceResult(
        pageList: wire.PageList(
          pageSessionId: 'late-old-manga-session',
          pages: [wire.Page(pageKey: 'old-page', url: '/old-page')],
        ),
      );
      addTearDown(() {
        if (!pages.isCompleted) pages.complete(latePages());
      });
      platform.invokeHandler = (call) {
        expect(call.whichRequest(), wire.SourceCall_Request.pages);
        received.complete();
        return pages.future;
      };
      platform.closePageSessionHandler = (id) async {
        closedSessions.add(id);
        if (id == 'late-old-manga-session' && !closed.isCompleted) {
          closed.complete();
        }
      };
      final catalog = CatalogController(
        api: platform,
        runtime: platform.runtime,
        rebuildRuntime: platform.rebuild,
        deploymentOrigin: platform.origin,
      );
      addTearDown(() async {
        catalog.dispose();
        await catalog.closeReadingProgress();
        await platform.dispose();
      });
      await tester.runAsync(() async {
        await catalog.connect();
        await catalog.openBuild(catalog.builds.single);
        await catalog.selectSource(
          catalog.session!.sources.single,
          loadListing: false,
        );
      });
      final key = GlobalKey();
      final chapters = _chapters.map(ChapterEntry.new).toList();
      final source = catalog.sourceReference;
      Widget detail(MangaEntry manga) => MaterialApp(
        home: MangaDetailsPage(
          key: key,
          controller: catalog,
          manga: manga,
          chapters: chapters,
          source: source,
        ),
      );
      await tester.pumpWidget(detail(MangaEntry(testManga)));
      await tester.pumpAndSettle();
      final previousState = tester.state(find.byKey(key));
      await _reveal(tester, _row(0));
      await tester.runAsync(() async {
        await tester.tap(_row(0));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 32));
      await tester.runAsync(
        () => received.future.timeout(const Duration(seconds: 5)),
      );
      final replacement = MangaEntry(
        wire.Manga(url: '/new-manga', title: '新作品'),
      );
      await tester.pumpWidget(detail(replacement));
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.state(find.byKey(key)), same(previousState));
      expect(
        tester.widget<MangaDetailsPage>(find.byKey(key)).manga,
        same(replacement),
      );
      await tester.runAsync(() async {
        pages.complete(latePages());
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => closed.future.timeout(const Duration(seconds: 5)),
      );
      await tester.pumpAndSettle();
      expect(closedSessions, ['late-old-manga-session']);
      expect(find.byType(ChapterReaderRoute), findsNothing);
      expect(find.byType(ReaderScreen), findsNothing);
      expect(find.text('新作品'), findsOneWidget);
      expect(find.textContaining('漫画源会话已变化'), findsOneWidget);
      expect(_posts(platform), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
