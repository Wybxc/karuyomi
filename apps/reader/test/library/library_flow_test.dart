import '../test_app.dart';

import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/main.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import '../data/business_state_server.dart';

Future<CatalogController> _browseDetails(WidgetTester tester) async {
  await tester.tap(find.text('去浏览'));
  await tester.pumpAndSettle();
  for (final target in [
    find.byKey(
      const ValueKey((
        'source-directory-row',
        'eu.kanade.source.test',
        sourceId,
      )),
    ),
    find.text('真实源 DTO 测试'),
  ]) {
    await tester.ensureVisible(target);
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
    'favorite conflict refreshes the remote state and requires a new explicit action',
    (tester) async {
      final server = TestBusinessServer();
      final platform = TestPlatform(businessServer: server);
      await tester.pumpApp(KaruyomiApp(platform: platform));
      await tester.pumpAndSettle();
      final catalog = await _browseDetails(tester);
      expect(find.text('加入书架'), findsOneWidget);
      final remoteClient = BusinessStateClient(
        api: server,
        identity: catalog.library!.identity,
      );
      final remoteLibrary = LibraryRepository(remoteClient);
      try {
        await remoteLibrary.setFavorite(
          packageName: 'eu.kanade.source.test',
          sourceId: sourceId,
          sourceName: '测试漫画源',
          sourceLang: 'zh',
          manga: testManga,
          favorite: true,
        );
        await tester.pumpAndSettle();
        expect(find.text('加入书架'), findsOneWidget);
        final requestsBefore = server.requests
            .where((request) => request.uri.path == '/api/state/mutations')
            .length;
        final appliedBefore = server.appliedMutations;
        await tester.tap(find.text('加入书架'));
        await tester.pumpAndSettle();
        expect(find.text('移出书架'), findsOneWidget);
        expect(find.text('此作品已在其他设备更新，已重新读取；请确认收藏状态后重试。'), findsOneWidget);
        final requestsAfter = server.requests
            .where((request) => request.uri.path == '/api/state/mutations')
            .toList();
        expect(requestsAfter.length, requestsBefore + 1);
        expect(server.appliedMutations, appliedBefore);
        final rejected = wire.decodeProtoJson(
          wire.StateMutation(),
          jsonDecode(requestsAfter.last.body!),
        );
        final confirmed = server.manga(rejected.mangaKey)!;
        expect(confirmed.favorite, true);
        expect(rejected.expectedRevision, lessThan(confirmed.revision));

        await tester.tap(find.text('移出书架'));
        await tester.pumpAndSettle();
        expect(find.text('加入书架'), findsOneWidget);
        expect(find.text('此作品已在其他设备更新，已重新读取；请确认收藏状态后重试。'), findsNothing);
        final explicitRemoval = wire.decodeProtoJson(
          wire.StateMutation(),
          jsonDecode(
            server.requests
                .lastWhere(
                  (request) => request.uri.path == '/api/state/mutations',
                )
                .body!,
          ),
        );
        expect(explicitRemoval.mutationId, isNot(rejected.mutationId));
        expect(explicitRemoval.expectedRevision, confirmed.revision);
        expect(explicitRemoval.setFavorite.favorite, false);
        expect(server.appliedMutations, appliedBefore + 1);
        expect(await remoteLibrary.contains(rejected.mangaKey), false);
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await catalog.closeReadingProgress();
      } finally {
        await remoteClient.dispose();
      }
    },
  );

  testWidgets('favorites and exact reading anchor reach a separate client', (
    tester,
  ) async {
    final server = TestBusinessServer();
    var platform = TestPlatform(businessServer: server);
    await tester.pumpApp(KaruyomiApp(platform: platform));
    await tester.pumpAndSettle();
    var catalog = await _browseDetails(tester);
    await _revealDetails(tester, find.text('加入书架'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入书架'));
    await tester.pumpAndSettle();
    expect(find.text('移出书架'), findsOneWidget);
    await _revealDetails(tester, find.text('第 1 章'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 1 章'));
    await tester.pumpAndSettle();
    final initialReader = tester.widget<ReaderScreen>(
      find.byType(ReaderScreen),
    );
    final manifest = initialReader.manifest;
    // Component evidence with a shared test server; image visibility is separate.
    initialReader.onViewportChanged!(
      ReaderViewportState(
        current: manifest.positionAt(0, offset: .35),
        observed: null,
        atEnd: false,
        windowReady: false,
      ),
    );
    await catalog.flushReadingProgress();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('继续阅读'), findsOneWidget);
    await tester.pumpApp(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await catalog.closeReadingProgress();

    platform = TestPlatform(businessServer: server)
      ..runtimeGeneration = 'second-client-generation';
    await tester.pumpApp(KaruyomiApp(platform: platform));
    await tester.pumpAndSettle();
    expect(find.text('真实源 DTO 测试'), findsOneWidget);
    expect(platform.invocations, isEmpty);
    await tester.tap(find.text('真实源 DTO 测试'));
    await tester.pumpAndSettle();
    catalog = tester
        .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
        .controller;
    expect(find.text('移出书架'), findsOneWidget);
    expect(find.text('继续阅读'), findsOneWidget);
    expect(platform.invocations.map((call) => call.whichRequest()), [
      wire.SourceCall_Request.details,
      wire.SourceCall_Request.chapters,
    ]);
    await _revealDetails(tester, find.text('继续阅读'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续阅读'));
    await tester.pumpAndSettle();
    final resumed = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    expect(resumed.initialPosition!.chapterKey, manifest.chapterKey);
    expect(resumed.initialPosition!.pageKey, manifest.pages.single.key);
    expect(resumed.initialPosition!.normalizedOffset, .35);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await _revealDetails(tester, find.text('移出书架'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出书架'));
    await tester.pumpAndSettle();
    expect(find.text('加入书架'), findsOneWidget);
    expect(find.text('继续阅读'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('书架还是空的'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpApp(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await catalog.closeReadingProgress();
  });

  testWidgets(
    'failed favorite write stays retryable and does not block chapter reading',
    (tester) async {
      final platform = TestPlatform();
      await tester.pumpApp(KaruyomiApp(platform: platform));
      await tester.pumpAndSettle();
      final catalog = await _browseDetails(tester);
      platform.businessServer.failWrites = true;
      await _revealDetails(tester, find.text('加入书架'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入书架'));
      await tester.pumpAndSettle();
      expect(find.text('收藏未能保存，请重试；仍可继续阅读。'), findsOneWidget);
      expect(find.text('加入书架'), findsOneWidget);
      expect(
        await tester.runAsync(() => catalog.library!.watchEntries().first),
        isEmpty,
      );
      await _revealDetails(tester, find.text('第 1 章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 1 章'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      platform.businessServer.failWrites = false;
      await _revealDetails(tester, find.text('加入书架'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('加入书架'));
      await tester.pumpAndSettle();
      expect(find.text('移出书架'), findsOneWidget);
      expect(find.text('收藏未能保存，请重试；仍可继续阅读。'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await catalog.closeReadingProgress();
    },
  );
}
