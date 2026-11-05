import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import '../data/business_state_server.dart';

void main() {
  late TestPlatform platform;
  late CatalogController catalog;
  late LibraryEntry entry;
  late BusinessStateClient remote;
  late Map<String, ChapterManifest> manifests;
  late List<wire.Chapter> chapters;
  Future<void> Function(wire.SourceCall call)? beforePages;
  var nextSession = 0;

  setUp(() async {
    nextSession = 0;
    beforePages = null;
    chapters = [
      wire.Chapter(url: '/one', name: '第一章'),
      wire.Chapter(url: '/two', name: '第二章'),
    ];
    platform = TestPlatform()
      ..invokeHandler = (call) async {
        switch (call.whichRequest()) {
          case wire.SourceCall_Request.details:
            return wire.SourceResult(manga: testManga);
          case wire.SourceCall_Request.chapters:
            return wire.SourceResult(
              chapters: wire.ChapterList(chapters: chapters),
            );
          case wire.SourceCall_Request.pages:
            await beforePages?.call(call);
            return wire.SourceResult(
              pageList: wire.PageList(
                pageSessionId: 'resume-pages-${++nextSession}',
                pages: [
                  for (var index = 0; index < 3; index++)
                    wire.Page(
                      pageKey: 'p-$index',
                      index: index,
                      sourceIndex: index,
                      url: '${call.pages.chapter.url}/page-$index',
                    ),
                ],
              ),
            );
          default:
            throw StateError('Shelf resume must not fetch a listing');
        }
      };
    catalog = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    final library = catalog.library!;
    await library.setFavorite(
      packageName: 'source.test',
      sourceId: sourceId,
      sourceName: '测试漫画源',
      sourceLang: 'zh',
      manga: testManga,
      favorite: true,
    );
    entry = (await library.watchEntries().first).single;
    final details = (await catalog.openLibraryEntry(
      entry,
      identityKey: library.identity.key,
    ))!;
    final sequence = ChapterSequence(
      packageName: entry.packageName,
      sourceId: sourceId,
      mangaUrl: testManga.url,
      chapters: chapters,
    );
    manifests = {};
    for (final chapter in sequence.entries) {
      final opened = (await catalog.openChapter(
        details.manga,
        ChapterEntry(chapter.snapshot),
        reference: details.source,
        logicalChapterKey: chapter.key,
      ))!;
      manifests[chapter.snapshot.url] = opened.manifest;
      await catalog.closeChapter(opened);
    }
    remote = BusinessStateClient(
      api: platform.businessServer,
      identity: library.identity,
    );
    await ProgressRepository(remote).save(
      mangaKey: entry.mangaKey,
      manifest: manifests['/one']!,
      progress: ChapterProgress(
        current: manifests['/one']!.positionAt(1, offset: .2),
      ),
      reversedOrder: false,
    );
    await library.refresh();
    platform.invocations.clear();
    platform.openedBuilds.clear();
    platform.imageControls.clear();
  });

  tearDown(() async {
    catalog.dispose();
    await catalog.closeReadingProgress();
    await remote.dispose();
    await platform.dispose();
  });

  Finder getContinue() =>
      find.byKey(ValueKey(('library-continue', entry.mangaKey)));

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    await tester.ensureVisible(getContinue());
    await tester.pumpAndSettle();
  }

  Future<void> hide(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  List<TestBusinessRequest> writes() => platform.businessServer.requests
      .where((request) => request.uri.path == '/api/state/mutations')
      .toList();

  testWidgets(
    'shelf keeps details navigation and directly resumes fresh server chapter and anchor once',
    (tester) async {
      await show(tester);
      expect(find.byTooltip('继续阅读：${entry.title}'), findsOneWidget);
      await tester.tap(find.text(entry.title));
      await tester.pumpAndSettle();
      expect(find.byType(MangaDetailsPage), findsOneWidget);
      expect(platform.invocations.where((call) => call.hasPages()), isEmpty);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.ensureVisible(getContinue());
      final target = manifests['/two']!;
      await remote.readManga(entry.mangaKey);
      await ProgressRepository(remote).save(
        mangaKey: entry.mangaKey,
        manifest: target,
        progress: ChapterProgress(
          current: target.positionAt(
            1,
            offset: .45,
            normalizedX: .6,
            viewportX: .3,
            viewportY: .2,
          ),
        ),
        reversedOrder: true,
      );
      // No shelf refresh: the displayed confirmed resume still names /one.
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      beforePages = (call) async {
        if (call.pages.chapter.url == '/two') {
          entered.complete();
          await release.future;
        }
      };
      await tester.tap(getContinue());
      await tester.tap(getContinue());
      await tester.pump();
      await tester.runAsync(
        () => entered.future.timeout(const Duration(seconds: 5)),
      );
      expect(tester.widget<IconButton>(getContinue()).onPressed, isNull);
      expect(
        platform.invocations.where(
          (call) => call.hasPages() && call.pages.chapter.url == '/two',
        ),
        hasLength(1),
      );
      // pages() is still pending while another client changes the same
      // chapter's anchor and reading order. The route's final state read wins.
      await remote.readManga(entry.mangaKey);
      await ProgressRepository(remote).save(
        mangaKey: entry.mangaKey,
        manifest: target,
        progress: ChapterProgress(
          current: target.positionAt(
            2,
            offset: .65,
            normalizedX: .7,
            viewportX: .4,
            viewportY: .25,
          ),
        ),
        reversedOrder: false,
      );
      release.complete();
      await tester.pumpAndSettle();
      expect(find.byType(MangaDetailsPage), findsNothing);
      expect(find.byType(ChapterReaderRoute), findsOneWidget);
      final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect(reader.manifest.chapterKey, target.chapterKey);
      expect(reader.initialPosition!.pageIndexHint, 2);
      expect(reader.initialPosition!.normalizedOffset, .65);
      expect(reader.initialPosition!.normalizedX, .7);
      expect(reader.initialPosition!.viewportX, .4);
      expect(reader.initialPosition!.viewportY, .25);
      expect(
        tester
            .widget<ChapterReaderRoute>(find.byType(ChapterReaderRoute))
            .initialOrder,
        isNull,
      );
      expect(
        tester
            .widget<DropdownButton<ChapterOrder>>(
              find.byType(DropdownButton<ChapterOrder>),
            )
            .value,
        ChapterOrder.source,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.byType(MangaDetailsPage), findsNothing);
      final sessions = platform.imageControls
          .where((event) => event.$1 == 'closePageSession')
          .map((event) => event.$2['pageSessionId'])
          .toList();
      expect(sessions, isNotEmpty);
      expect(sessions.toSet().length, sessions.length);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets('missing resume chapter opens details with a clear notice', (
    tester,
  ) async {
    chapters = [wire.Chapter(url: '/replacement', name: '替代章节')];
    await show(tester);
    await tester.tap(getContinue());
    await tester.pumpAndSettle();
    expect(find.byType(MangaDetailsPage), findsOneWidget);
    expect(find.byType(ChapterReaderRoute), findsNothing);
    expect(find.text('上次阅读的章节已不在当前清单，已打开详情，请选择章节。'), findsOneWidget);
    expect(platform.invocations.where((call) => call.hasPages()), isEmpty);
    await tester.scrollUntilVisible(
      find.text('替代章节'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(MangaDetailsPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('替代章节'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await hide(tester);
  });

  testWidgets('a late acquired page session closes after another route opens', (
    tester,
  ) async {
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    beforePages = (_) async {
      entered.complete();
      await release.future;
    };
    await show(tester);
    await tester.tap(getContinue());
    await tester.pump();
    await tester.runAsync(
      () => entered.future.timeout(const Duration(seconds: 5)),
    );
    unawaited(
      Navigator.of(tester.element(find.byType(LibraryPage))).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('另一个页面')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    release.complete();
    await tester.pumpAndSettle();
    expect(find.text('另一个页面'), findsOneWidget);
    expect(find.byType(ChapterReaderRoute), findsNothing);
    expect(
      platform.imageControls.where((event) => event.$1 == 'closePageSession'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
    await hide(tester);
  });

  testWidgets('identity change discards a late confirmed resume read', (
    tester,
  ) async {
    await show(tester);
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    platform.afterBusinessReply = (request, reply) async {
      if (request.method == 'GET' &&
          request.uri.path == '/api/state/manga/${entry.mangaKey}' &&
          request.uri.queryParameters.isEmpty) {
        entered.complete();
        await release.future;
      }
      return reply;
    };
    await tester.tap(getContinue());
    await tester.pump();
    await tester.runAsync(
      () => entered.future.timeout(const Duration(seconds: 5)),
    );
    platform.bootstrapSubject = 'another-owner';
    await tester.runAsync(catalog.connect);
    release.complete();
    // connect ran in the real async zone while the previous identity's GET
    // was gated. Await the new shelf read before asserting its rendered data.
    await tester.runAsync(
      () => catalog.library!.refresh().timeout(const Duration(seconds: 5)),
    );
    await tester.pumpAndSettle();
    expect(catalog.subject, 'another-owner');
    expect(catalog.library!.identity.subject, 'another-owner');
    expect(find.byType(ChapterReaderRoute), findsNothing);
    expect(find.byType(MangaDetailsPage), findsNothing);
    expect(platform.invocations.where((call) => call.hasPages()), isEmpty);
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(
      find.text('书架还是空的'),
      findsOneWidget,
      reason:
          'status=${catalog.status} error=${catalog.error}; '
          'texts=${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).toList()}',
    );
    expect(tester.takeException(), isNull);
    await hide(tester);
  });

  testWidgets(
    'lost metadata acknowledgement retries only its original command and separates a failed shelf read',
    (tester) async {
      var loseAck = true;
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final bodies = <String>[];
      final appliedBefore = platform.businessServer.appliedMutations;
      platform.afterBusinessReply = (request, reply) async {
        if (request.method == 'POST' &&
            request.uri.path == '/api/state/mutations' &&
            wire
                .decodeProtoJson(
                  wire.StateMutation(),
                  jsonDecode(request.body!),
                )
                .hasUpdateMetadata()) {
          bodies.add(request.body!);
          if (loseAck) {
            loseAck = false;
            return const ApiReply(
              status: 502,
              headers: {'content-type': 'text/plain'},
              body: 'Committed metadata ACK lost at the response boundary',
              redirected: false,
            );
          }
          entered.complete();
          await release.future;
        }
        return reply;
      };
      await show(tester);
      await tester.tap(find.text(entry.title));
      await tester.pumpAndSettle();
      expect(find.byType(MangaDetailsPage), findsOneWidget);
      expect(platform.businessServer.appliedMutations, appliedBefore + 1);
      expect(catalog.library!.client.hasPendingMetadata(entry.mangaKey), true);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      final retry = find.byKey(
        ValueKey(('library-retry-metadata', entry.mangaKey)),
      );
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      expect(find.text('重试保存书架资料'), findsOneWidget);
      expect(tester.widget<TextButton>(retry).onPressed, isNotNull);
      expect(bodies, hasLength(1));
      await tester.tap(retry);
      await tester.tap(retry);
      await tester.pump();
      await tester.runAsync(
        () => entered.future.timeout(const Duration(seconds: 5)),
      );
      expect(tester.widget<TextButton>(retry).onPressed, isNull);
      expect(bodies, hasLength(2));
      expect(bodies.last, bodies.first);
      expect(platform.businessServer.appliedMutations, appliedBefore + 1);
      platform.businessServer.beforeRequest = (request) =>
          request.uri.path == '/api/library'
          ? const ApiReply(
              status: 503,
              headers: {'content-type': 'text/plain'},
              body: 'Injected read failure after confirmed metadata retry',
              redirected: false,
            )
          : null;
      release.complete();
      await tester.pumpAndSettle();
      expect(catalog.library!.client.hasPendingMetadata(entry.mangaKey), false);
      expect(retry, findsNothing);
      expect(find.text('书架资料已获服务器确认。'), findsOneWidget);
      expect(find.text('未能刷新服务端书架，当前显示上次确认的结果。'), findsOneWidget);
      expect(find.text('书架资料仍未获确认，原操作已保留，请明确重试保存。'), findsNothing);
      expect(find.text('书架资料尚未确认，仍可继续阅读；请返回书架处理未确认操作。'), findsNothing);
      expect(bodies, hasLength(2));
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'unsaved session chapter takes priority without metadata replaying the pending write',
    (tester) async {
      final draftManifest = manifests['/two']!;
      final progress = catalog.createReadingProgress(entry.mangaKey)!;
      await progress.restore(draftManifest);
      progress.observe(
        manifest: draftManifest,
        current: draftManifest.positionAt(2, offset: .72),
        reversedOrder: true,
      );
      platform.businessServer.failWrites = true;
      expect(await progress.flush(), false);
      final originalBody = writes().last.body;
      final writesBefore = writes().length;
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      beforePages = (call) async {
        expect(call.pages.chapter.url, '/two');
        entered.complete();
        await release.future;
      };
      await show(tester);
      expect(find.byTooltip('继续阅读（未保存）：${entry.title}'), findsOneWidget);
      await tester.tap(getContinue());
      await tester.pump();
      await tester.runAsync(
        () => entered.future.timeout(const Duration(seconds: 5)),
      );
      expect(writes(), hasLength(writesBefore));
      expect(writes().last.body, originalBody);
      expect(progress.unsaved, true);
      expect(
        platform.businessServer.manga(entry.mangaKey)!.resume.chapterKey,
        manifests['/one']!.chapterKey,
      );
      release.complete();
      await tester.pumpAndSettle();
      final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect(reader.manifest.chapterKey, draftManifest.chapterKey);
      expect(reader.initialPosition!.normalizedOffset, .72);
      expect(progress.unsaved, true);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );
}
