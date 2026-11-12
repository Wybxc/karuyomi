import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import '../data/business_state_server.dart';

TestPlatform _platform({
  Uri? origin,
  String subject = 'owner-subject',
  TestBusinessServer? server,
}) {
  var session = 0;
  return TestPlatform(
      origin: origin,
      bootstrapSubject: subject,
      businessServer: server,
    )
    ..invokeHandler = (call) async => switch (call.whichRequest()) {
      wire.SourceCall_Request.details => wire.SourceResult(manga: testManga),
      wire.SourceCall_Request.chapters => wire.SourceResult(
        chapters: wire.ChapterList(
          chapters: [
            wire.Chapter(url: '/one', name: '第一章'),
            wire.Chapter(url: '/two', name: '第二章'),
          ],
        ),
      ),
      wire.SourceCall_Request.pages => wire.SourceResult(
        pageList: wire.PageList(
          pageSessionId: 'session-${++session}',
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
      ),
      _ => wire.SourceResult(mangaPage: wire.MangaPage(mangas: [testManga])),
    };
}

Future<CatalogController> _details(
  WidgetTester tester,
  TestPlatform platform, {
  TestPlatform Function(Uri? origin)? factory,
}) async {
  await tester.pumpWidget(
    KaruyomiApp(platform: platform, platformFactory: factory),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('去浏览'));
  await tester.pumpAndSettle();
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
    await tester.tap(target);
    await tester.pumpAndSettle();
  }
  return tester
      .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
      .controller;
}

Future<void> _revealDetails(WidgetTester tester, Finder finder) async {
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
}

void main() {
  testWidgets(
    'foreground refresh keeps the viewport until explicit reopen adopts remote progress and order',
    (tester) async {
      final server = TestBusinessServer();
      final platform = _platform(server: server);
      final catalog = await _details(tester, platform);
      await _revealDetails(tester, find.text('第一章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第一章'));
      await tester.pumpAndSettle();
      expect(await catalog.flushReadingProgress(), true);
      // Layout preferences now belong to the settings command path. Explicit
      // choices must survive a progress reopen independently of viewport data.
      tester
          .widget<ReaderScreen>(find.byType(ReaderScreen))
          .onDoublePageChanged!(true);
      await tester.pumpAndSettle();
      tester.widget<ReaderScreen>(find.byType(ReaderScreen)).onModeChanged!(
        ReadingMode.webtoon,
      );
      await tester.pumpAndSettle();
      final before = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      final manifest = before.manifest;
      final mangaKey = ChapterSequence(
        packageName: 'eu.kanade.source.test',
        sourceId: sourceId,
        mangaUrl: testManga.url,
        chapters: const [],
      ).mangaKey;
      final remote = BusinessStateClient(
        api: server,
        identity: catalog.readingProgress!.identity,
      );
      final repository = ProgressRepository(remote);
      await repository.save(
        mangaKey: mangaKey,
        manifest: manifest,
        progress: ChapterProgress(
          current: manifest.positionAt(
            2,
            offset: .7,
            normalizedX: .6,
            viewportX: .3,
            viewportY: .2,
          ),
          furthest: manifest.positionAt(2, offset: .7),
        ),
        reversedOrder: true,
      );
      final remoteRevision = server.accountRevision;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('重新打开本章'), findsOneWidget);
      final unchanged = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect(unchanged.key, before.key);
      expect(unchanged.initialPosition, before.initialPosition);
      expect(unchanged.positionRequest!.value, before.positionRequest!.value);
      unchanged.onViewportChanged!(
        ReaderViewportState(
          current: manifest.positionAt(1),
          observed: manifest.positionAt(1),
          atEnd: false,
          windowReady: true,
          // A late viewport report cannot overwrite the confirmed preference.
          mode: ReadingMode.leftToRight,
          doublePage: null,
        ),
      );
      await tester.pumpAndSettle();
      expect(await catalog.flushReadingProgress(), false);
      expect(server.accountRevision, remoteRevision);
      await tester.tap(find.text('重新打开本章'));
      await tester.pumpAndSettle();
      final reopened = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect(reopened.key, isNot(before.key));
      expect(reopened.initialPosition!.pageIndexHint, 2);
      expect(reopened.initialPosition!.normalizedOffset, .7);
      expect(reopened.initialPosition!.normalizedX, .6);
      expect(reopened.initialPosition!.viewportX, .3);
      expect(reopened.initialPosition!.viewportY, .2);
      expect(reopened.initialMode, ReadingMode.webtoon);
      expect(reopened.doublePage, true);
      expect(find.text('重新打开本章'), findsNothing);
      expect(
        tester
            .widget<DropdownButton<ChapterOrder>>(
              find.byType(DropdownButton<ChapterOrder>),
            )
            .value,
        ChapterOrder.reversed,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await catalog.closeReadingProgress();
      await remote.dispose();
    },
  );

  testWidgets(
    'failed foreground refresh keeps reading available and the explicit refresh retries',
    (tester) async {
      final server = TestBusinessServer();
      final platform = _platform(server: server);
      final catalog = await _details(tester, platform);
      await _revealDetails(tester, find.text('第一章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第一章'));
      await tester.pumpAndSettle();
      expect(await catalog.flushReadingProgress(), true);
      final before = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      var failChapterRead = true;
      server.beforeRequest = (request) {
        if (failChapterRead &&
            request.uri.queryParameters.containsKey('chapterKey')) {
          failChapterRead = false;
          return const ApiReply(
            status: 503,
            headers: {'content-type': 'text/plain'},
            body: 'Injected foreground chapter read failure',
            redirected: false,
          );
        }
        return null;
      };
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('未能刷新服务器进度，当前阅读位置保持不变，可重试。'), findsOneWidget);
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).key,
        before.key,
      );
      await tester.tap(find.text('刷新进度'));
      await tester.pumpAndSettle();
      expect(find.text('未能刷新服务器进度，当前阅读位置保持不变，可重试。'), findsNothing);
      expect(find.text('阅读进度已保存到服务端'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await catalog.closeReadingProgress();
    },
  );

  testWidgets(
    'failed save retains its original identity draft until that service reconnects',
    (tester) async {
      final server = TestBusinessServer();
      final original = _platform(server: server);
      final recovered = _platform(server: server);
      final replacement = _platform(
        origin: Uri.parse('https://other.example'),
        subject: 'other-subject',
      );
      final catalog = await _details(
        tester,
        original,
        factory: (origin) {
          return origin == original.origin ? recovered : replacement;
        },
      );
      await _revealDetails(tester, find.text('第一章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第一章'));
      await tester.pumpAndSettle();
      await catalog.flushReadingProgress();
      final leaf = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      final manifest = leaf.manifest;
      final mangaKey = ChapterSequence(
        packageName: 'eu.kanade.source.test',
        sourceId: sourceId,
        mangaUrl: testManga.url,
        chapters: const [],
      ).mangaKey;
      server.failWrites = true;
      (leaf.positionRequest! as ValueNotifier<ReadingPosition?>).value =
          manifest.positionAt(1, offset: .4);
      await tester.pumpAndSettle();
      expect(await catalog.flushReadingProgress(), false);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        replacement.origin.toString(),
      );
      await tester.tap(find.text('连接服务'));
      await tester.pumpAndSettle();
      expect(original.disposalCount, 1);
      expect(find.text('重试保存所有进度'), findsOneWidget);
      final oldControls = original.controlCommands.length;
      await tester.tap(find.text('浏览').last);
      await tester.pumpAndSettle();
      final nextCatalog = tester
          .widget<CatalogPage>(find.byType(CatalogPage))
          .controller!;
      expect(nextCatalog.readingProgress!.identity.subject, 'other-subject');
      expect(nextCatalog.readingProgress!.identity.origin, replacement.origin);
      expect(
        await nextCatalog.readingProgress!.loadChapter(
          mangaKey: mangaKey,
          chapterKey: manifest.chapterKey,
        ),
        isNull,
      );
      final nextWriter = nextCatalog.createReadingProgress(mangaKey)!;
      await nextWriter.restore(manifest);
      nextWriter.observe(
        manifest: manifest,
        current: manifest.positionAt(2),
        reversedOrder: false,
      );
      expect(await nextWriter.flush(), true);
      await nextCatalog.releaseReadingProgress(nextWriter);
      expect(
        server.progress(mangaKey, manifest.chapterKey)!.current.pageIndexHint,
        0,
      );
      server.failWrites = false;
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        original.origin.toString(),
      );
      await tester.tap(find.text('连接服务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试保存所有进度'));
      await tester.pumpAndSettle();
      expect(find.text('重试保存所有进度'), findsNothing);
      expect(
        server.progress(mangaKey, manifest.chapterKey)!.current.pageIndexHint,
        1,
      );
      expect(
        replacement.businessServer
            .progress(mangaKey, manifest.chapterKey, subject: 'other-subject')!
            .current
            .pageIndexHint,
        2,
      );
      expect(original.controlCommands.length, oldControls);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await nextCatalog.closeReadingProgress();
    },
  );

  testWidgets(
    'product routes save and resume exact chapter/offset on a separate client',
    (tester) async {
      final server = TestBusinessServer();
      var platform = _platform(server: server);
      var catalog = await _details(tester, platform);
      final mangaKey = ChapterSequence(
        packageName: 'eu.kanade.source.test',
        sourceId: sourceId,
        mangaUrl: testManga.url,
        chapters: const [],
      ).mangaKey;
      await _revealDetails(tester, find.text('第一章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第一章'));
      await tester.pumpAndSettle();
      var leaf = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      final firstManifest = leaf.manifest;
      (leaf.positionRequest! as ValueNotifier<ReadingPosition?>).value =
          firstManifest.positionAt(2);
      await tester.pumpAndSettle();
      // These callbacks exercise product navigation/persistence. Actual decode
      // visibility and zoom gates are separately tested in ReaderScreen tests.
      leaf.onViewportChanged!(
        ReaderViewportState(
          current: firstManifest.positionAt(2),
          observed: firstManifest.positionAt(2, offset: 1),
          atEnd: true,
          windowReady: false,
        ),
      );
      await tester.tap(find.text('下一章'));
      await tester.pumpAndSettle();
      expect(find.text('真实源 DTO 测试 · 第二章'), findsOneWidget);
      expect(
        (await catalog.readingProgress!.loadChapter(
          mangaKey: mangaKey,
          chapterKey: firstManifest.chapterKey,
        ))!.completed,
        true,
      );
      leaf = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      final secondManifest = leaf.manifest;
      tester
          .widget<DropdownButton<ChapterOrder>>(
            find.byType(DropdownButton<ChapterOrder>),
          )
          .onChanged!(ChapterOrder.reversed);
      await tester.pumpAndSettle();
      (leaf.positionRequest! as ValueNotifier<ReadingPosition?>).value =
          secondManifest.positionAt(
            1,
            offset: .35,
            normalizedX: .65,
            viewportX: .25,
            viewportY: .15,
          );
      await tester.pumpAndSettle();
      leaf.onViewportChanged!(
        ReaderViewportState(
          current: secondManifest.positionAt(
            1,
            offset: .35,
            normalizedX: .65,
            viewportX: .25,
            viewportY: .15,
          ),
          observed: secondManifest.positionAt(1, offset: .8),
          atEnd: false,
          windowReady: false,
        ),
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('继续阅读'), findsOneWidget);
      expect(find.byType(ReaderScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await catalog.closeReadingProgress();
      platform = _platform(server: server);
      catalog = await _details(tester, platform);
      expect(find.text('继续阅读'), findsOneWidget);
      await _revealDetails(tester, find.text('继续阅读'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续阅读'));
      await tester.pumpAndSettle();
      leaf = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect(leaf.manifest.chapterKey, secondManifest.chapterKey);
      expect(leaf.preserveInitialPlacement, true);
      expect(leaf.initialPosition!.pageKey, secondManifest.pages[1].key);
      expect(leaf.initialPosition!.normalizedOffset, .35);
      expect(leaf.initialPosition!.normalizedX, .65);
      expect(leaf.initialPosition!.viewportX, .25);
      expect(leaf.initialPosition!.viewportY, .15);
      expect(
        tester
            .widget<DropdownButton<ChapterOrder>>(
              find.byType(DropdownButton<ChapterOrder>),
            )
            .value,
        ChapterOrder.reversed,
      );
      var stored = (await catalog.readingProgress!.loadChapter(
        mangaKey: mangaKey,
        chapterKey: secondManifest.chapterKey,
      ))!;
      expect(stored.furthest!.pageKey, secondManifest.pages[1].key);
      expect(stored.furthest!.normalizedOffset, .8);
      expect(stored.completed, false);
      final pagesBeforeReset = platform.invocations
          .where((call) => call.whichRequest() == wire.SourceCall_Request.pages)
          .length;
      await tester.tap(find.text('重新阅读本章'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      expect(
        platform.invocations.where(
          (call) => call.whichRequest() == wire.SourceCall_Request.pages,
        ),
        hasLength(pagesBeforeReset),
      );
      stored = (await catalog.readingProgress!.loadChapter(
        mangaKey: mangaKey,
        chapterKey: secondManifest.chapterKey,
      ))!;
      expect(stored.epoch, 1);
      expect(stored.current.pageIndexHint, 0);
      expect(stored.furthest, isNull);
      expect(stored.completed, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await catalog.closeReadingProgress();
    },
  );

  testWidgets(
    'unconfirmed writes remain session drafts and never remove the Reader',
    (tester) async {
      final platform = _platform();
      final catalog = await _details(tester, platform);
      await _revealDetails(tester, find.text('第一章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第一章'));
      await tester.pumpAndSettle();
      expect(find.text('阅读进度待服务端确认'), findsOneWidget);
      expect(find.text('阅读进度已保存到服务端'), findsNothing);
      await catalog.flushReadingProgress();
      platform.businessServer.failWrites = true;
      final leaf = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      leaf.onViewportChanged!(
        ReaderViewportState(
          current: leaf.manifest.positionAt(1),
          observed: null,
          atEnd: false,
          windowReady: false,
        ),
      );
      expect(await catalog.flushReadingProgress(), false);
      await tester.pump();
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(find.text('进度尚未获服务器确认，可重试；草稿仅保留在当前会话。'), findsOneWidget);
      expect(find.text('重试保存'), findsOneWidget);
      expect(find.text('阅读进度已保存到服务端'), findsNothing);
      platform.businessServer.failWrites = false;
      await tester.tap(find.text('重试保存'));
      await tester.pumpAndSettle();
      expect(catalog.hasUnsavedReadingProgress, false);
      expect(find.text('阅读进度已保存到服务端'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await catalog.closeReadingProgress();
    },
  );
}
