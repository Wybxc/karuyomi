import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import '../data/business_state_server.dart';

void main() {
  late TestPlatform platform;
  var serverNow = DateTime.utc(2026, 1, 1);
  late CatalogController controller;

  setUp(() async {
    platform = TestPlatform(
      businessServer: TestBusinessServer(now: () => serverNow),
    );
    controller = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await controller.connect();
  });

  tearDown(() async {
    controller.dispose();
    await controller.closeReadingProgress();
    await platform.dispose();
  });

  Future<void> favorite({
    wire.Manga? manga,
    String sourceName = '测试漫画源',
    DateTime? addedAt,
  }) async {
    if (addedAt != null) serverNow = addedAt;
    final repository = controller.library!;
    await repository.setFavorite(
      packageName: 'eu.kanade.source.test',
      sourceId: sourceId,
      sourceName: sourceName,
      sourceLang: 'zh',
      manga: manga ?? testManga,
      favorite: true,
    );
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryPage(
            controller: controller,
            onBrowse: () {},
            onConnect: () => unawaited(controller.connect()),
            onAuthenticate: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> hide(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('shelf search and sorting only use stored metadata', (
    tester,
  ) async {
    await favorite(
      manga: wire.Manga(url: '/alpha', title: 'Alpha', author: '旧作者'),
      addedAt: DateTime.utc(2026, 1, 1),
    );
    await favorite(
      manga: wire.Manga(url: '/zulu', title: 'Zulu', author: '新作者'),
      sourceName: '另一漫画源',
      addedAt: DateTime.utc(2026, 2, 1),
    );
    await show(tester);

    expect(
      tester.getTopLeft(find.text('Zulu')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );
    await tester.tap(find.text('最近收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标题').last);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Zulu')).dy),
    );

    await tester.enterText(find.byType(TextField), '新作者');
    await tester.pumpAndSettle();
    expect(find.text('Zulu'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    await tester.enterText(find.byType(TextField), '测试漫画源');
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Zulu'), findsNothing);
    await tester.enterText(find.byType(TextField), '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有找到收藏'), findsOneWidget);
    expect(platform.invocations, isEmpty);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
    await hide(tester);
  });

  testWidgets('identity reconnect immediately drops old shelf results', (
    tester,
  ) async {
    await favorite();
    await show(tester);
    expect(find.text(testManga.title), findsOneWidget);
    final entered = Completer<void>();
    final release = Completer<void>();
    platform.bootstrapSubject = 'other-subject';
    platform.beforeApiFetch = (path) async {
      if (path != '/api/bootstrap') return;
      entered.complete();
      await release.future;
    };
    final reconnecting = controller.connect();
    await tester.runAsync(() => entered.future);
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.text(testManga.title), findsNothing);
    release.complete();
    await tester.runAsync(() => reconnecting);
    await tester.pumpAndSettle();
    expect(find.text('书架还是空的'), findsOneWidget);
    expect(find.text(testManga.title), findsNothing);
    expect(tester.takeException(), isNull);
    await hide(tester);
  });

  testWidgets('shelf reopens Source details with its stored manga reference', (
    tester,
  ) async {
    await favorite();
    await show(tester);
    await tester.tap(find.text(testManga.title));
    await tester.pumpAndSettle();
    expect(find.byType(MangaDetailsPage), findsOneWidget);
    expect(find.text('漫画源返回的完整简介'), findsOneWidget);
    expect(platform.invocations.map((call) => call.whichRequest()), [
      wire.SourceCall_Request.details,
      wire.SourceCall_Request.chapters,
    ]);
    expect(platform.invocations.first.details.manga, testManga);
    expect(platform.openedIdentities, ['owner-subject']);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
    await hide(tester);
  });

  testWidgets(
    'missing Source retains the favorite and displays a retryable error',
    (tester) async {
      await favorite();
      platform.inventory = wire.encodeProtoJson(
        wire.ExtensionIndex(schemaVersion: 1, repoId: 'keiyoushi'),
      );
      await controller.connect();
      await show(tester);
      await tester.tap(find.text(testManga.title));
      await tester.pumpAndSettle();
      expect(find.byType(MangaDetailsPage), findsNothing);
      expect(find.text(testManga.title), findsOneWidget);
      expect(controller.error, isNotNull);
      expect(find.text(controller.error!), findsOneWidget);
      expect(platform.invocations, isEmpty);
      expect(
        await tester.runAsync(() => controller.library!.watchEntries().first),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a late Source detail does not navigate away from another route',
    (tester) async {
      await favorite();
      final entered = Completer<void>();
      final delayed = Completer<wire.SourceResult>();
      platform.invokeHandler = (call) {
        expect(call.whichRequest(), wire.SourceCall_Request.details);
        entered.complete();
        return delayed.future;
      };
      await show(tester);
      await tester.tap(find.text(testManga.title));
      await tester.pump();
      await tester.runAsync(() => entered.future);
      unawaited(
        Navigator.of(tester.element(find.byType(LibraryPage))).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('另一页面')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      delayed.complete(wire.SourceResult(manga: testManga));
      await tester.pumpAndSettle();
      expect(find.text('另一页面'), findsOneWidget);
      expect(find.byType(MangaDetailsPage), findsNothing);
      expect(platform.invocations, hasLength(1));
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'foreground refresh reads favorites created by an independent client',
    (tester) async {
      final remotePlatform = TestPlatform(
        businessServer: platform.businessServer,
      );
      final remote = CatalogController(
        api: remotePlatform,
        runtime: remotePlatform.runtime,
        rebuildRuntime: remotePlatform.rebuild,
        deploymentOrigin: remotePlatform.origin,
      );
      try {
        await remote.connect();
        await show(tester);
        expect(find.text('书架还是空的'), findsOneWidget);
        await remote.library!.setFavorite(
          packageName: 'eu.kanade.source.test',
          sourceId: sourceId,
          sourceName: '测试漫画源',
          sourceLang: 'zh',
          manga: testManga,
          favorite: true,
        );
        await tester.pumpAndSettle();
        expect(find.text(testManga.title), findsNothing);
        expect(find.text('书架还是空的'), findsOneWidget);
        final readsBefore = platform.businessServer.requests
            .where((request) => request.uri.path == '/api/library')
            .length;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text(testManga.title), findsOneWidget);
        expect(find.text('书架还是空的'), findsNothing);
        expect(
          platform.businessServer.requests
              .where((request) => request.uri.path == '/api/library')
              .length,
          greaterThan(readsBefore),
        );
        expect(platform.invocations, isEmpty);
        expect(tester.takeException(), isNull);
        await hide(tester);
      } finally {
        remote.dispose();
        await remote.closeReadingProgress();
        await remotePlatform.dispose();
      }
    },
  );

  testWidgets(
    'manual refresh failure retains confirmed entries and reports a retryable notice',
    (tester) async {
      await favorite();
      await show(tester);
      expect(find.text(testManga.title), findsOneWidget);
      platform.businessServer.beforeRequest = (request) {
        if (request.uri.path != '/api/library') return null;
        return ApiReply(
          status: 503,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(
            wire.encodeProtoJson(
              wire.LibraryPageResponse(
                schemaVersion: 1,
                accountRevision: platform.businessServer.accountRevision,
                categoryCatalog: wire.CategoryCatalog(),
                error: wire.BusinessStateError(
                  code: wire
                      .BusinessStateErrorCode
                      .BUSINESS_STATE_ERROR_CODE_UNAVAILABLE,
                  message: 'Injected library refresh failure',
                  retryable: true,
                ),
              ),
            ),
          ),
          redirected: false,
        );
      };
      await tester.tap(find.text('刷新服务端书架'));
      await tester.pumpAndSettle();
      expect(find.text(testManga.title), findsOneWidget);
      expect(find.text('未能刷新服务端书架，当前显示上次确认的结果。'), findsOneWidget);
      expect(find.text('书架还是空的'), findsNothing);
      expect(controller.status, ServiceStatus.ready);
      platform.businessServer.beforeRequest = null;
      await tester.tap(find.text('刷新服务端书架'));
      await tester.pumpAndSettle();
      expect(find.text(testManga.title), findsOneWidget);
      expect(find.text('未能刷新服务端书架，当前显示上次确认的结果。'), findsNothing);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'the shelf offers an explicit server refresh without local persistence',
    (tester) async {
      await show(tester);
      expect(find.text('刷新服务端书架'), findsOneWidget);
      expect(find.text('书架仅保存在此设备。'), findsNothing);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );
}
