import '../test_app.dart';

import 'dart:async';
import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import '../data/business_state_server.dart';

const _first = '10000000-0000-4000-8000-000000000001';
const _second = '10000000-0000-4000-8000-000000000002';
const _third = '10000000-0000-4000-8000-000000000003';

void main() {
  late TestBusinessServer server;
  late TestPlatform platform;
  late CatalogController controller;
  late BusinessStateClient remoteClient;
  late LibraryRepository remote;

  setUp(() async {
    server = TestBusinessServer(now: () => DateTime.utc(2026, 1, 1));
    platform = TestPlatform(businessServer: server);
    controller = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await controller.connect();
    remoteClient = BusinessStateClient(
      api: server,
      identity: controller.library!.identity,
    );
    remote = LibraryRepository(remoteClient);
  });

  tearDown(() async {
    await remoteClient.dispose();
    controller.dispose();
    await controller.closeReadingProgress();
    await platform.dispose();
  });

  Future<LibraryEntry> favorite(WidgetTester tester, String title) async {
    final entry = await tester.runAsync(() async {
      await controller.library!.setFavorite(
        packageName: 'eu.kanade.source.test',
        sourceId: sourceId,
        sourceName: '测试漫画源',
        sourceLang: 'zh',
        manga: wire.Manga(url: '/manga/$title', title: title, author: '作者'),
        favorite: true,
      );
      return (await controller.library!.watchView().first).entries.singleWhere(
        (entry) => entry.title == title,
      );
    });
    return entry!;
  }

  Future<void> createCategory(
    WidgetTester tester,
    String id,
    String name,
  ) async {
    await tester.runAsync(
      () => controller.library!.createCategory(
        categoryId: id,
        name: name,
        expectedRevision: server.catalog().revision,
      ),
    );
  }

  Future<void> show(WidgetTester tester) async {
    await tester.pumpApp(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: LibraryPage(
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
    await tester.pumpApp(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  Future<void> selectAll(WidgetTester tester) async {
    await tap(tester, find.byKey(const ValueKey('library-selection-toggle')));
    await tap(tester, find.byKey(const ValueKey('library-select-visible')));
  }

  Future<void> search(WidgetTester tester, String query) async {
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is CupertinoTextField && widget.placeholder == '漫画、作者或漫画源',
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, query);
    await tester.pumpAndSettle();
  }

  List<TestBusinessRequest> mutations() => server.requests
      .where(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/api/state/mutations',
      )
      .toList();

  wire.StateMutation command(TestBusinessRequest request) =>
      wire.decodeProtoJson(wire.StateMutation(), jsonDecode(request.body!));

  Finder batchEntry(String key) => find.byKey(ValueKey(('batch-item', key)));
  Finder category(String id) => find.byKey(ValueKey(('batch-category', id)));

  testWidgets(
    'visible selection preserves hidden choices and confirms the complete removal list',
    (tester) async {
      final alpha = await favorite(tester, 'Alpha');
      final beta = await favorite(tester, 'Beta');
      final gamma = await favorite(tester, 'Gamma');
      await show(tester);
      server.requests.clear();
      await tap(tester, find.byKey(const ValueKey('library-selection-toggle')));
      await search(tester, 'Alpha');
      await tap(tester, find.byKey(const ValueKey('library-select-visible')));
      await search(tester, 'Beta');
      await tap(tester, find.byKey(const ValueKey('library-select-visible')));
      await tap(tester, find.byKey(const ValueKey('library-deselect-visible')));
      expect(find.text('已选 1 部 · 当前隐藏 1 部'), findsOneWidget);
      await tap(tester, find.byKey(const ValueKey('library-select-visible')));
      await search(tester, 'Gamma');
      expect(find.text('已选 2 部 · 当前隐藏 2 部'), findsOneWidget);
      await tap(
        tester,
        find.byKey(const ValueKey('library-batch-remove-favorites')),
      );
      expect(find.text('确认清单：2 部漫画'), findsOneWidget);
      expect(batchEntry(alpha.mangaKey), findsOneWidget);
      expect(batchEntry(beta.mangaKey), findsOneWidget);
      expect(batchEntry(gamma.mangaKey), findsNothing);
      expect(mutations(), isEmpty);
      await tap(tester, find.text('确认并开始'));
      expect(find.text('全部修改已由服务端确认。'), findsOneWidget);
      expect(mutations(), hasLength(2));
      expect(server.manga(alpha.mangaKey)!.favorite, false);
      expect(server.manga(beta.mangaKey)!.favorite, false);
      expect(server.manga(gamma.mangaKey)!.favorite, true);
      expect(server.manga(alpha.mangaKey)!.metadata.manga, alpha.snapshot);
      expect(server.manga(beta.mangaKey)!.metadata.manga, beta.snapshot);
      expect(
        mutations()
            .map(command)
            .every(
              (mutation) =>
                  mutation.hasSetFavorite() &&
                  !mutation.setFavorite.favorite &&
                  !mutation.setFavorite.hasMetadata(),
            ),
        true,
      );
      await tap(tester, find.text('完成'));
      expect(find.byKey(ValueKey(gamma.mangaKey)), findsOneWidget);
      expect(platform.invocations, isEmpty);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'batch category add and removal preserve every unselected association',
    (tester) async {
      await createCategory(tester, _first, '想读');
      await createCategory(tester, _second, '科幻');
      await createCategory(tester, _third, '本月');
      final alpha = await favorite(tester, 'Alpha');
      final beta = await favorite(tester, 'Beta');
      await tester.runAsync(() async {
        await controller.library!.setCategories(
          mangaKey: alpha.mangaKey,
          categoryIds: [_first],
          expectedCatalogRevision: 3,
          expectedMangaRevision: alpha.revision,
        );
        await controller.library!.setCategories(
          mangaKey: beta.mangaKey,
          categoryIds: [_second],
          expectedCatalogRevision: 3,
          expectedMangaRevision: beta.revision,
        );
      });
      await show(tester);
      server.requests.clear();
      await selectAll(tester);
      await tap(
        tester,
        find.byKey(const ValueKey('library-batch-add-categories')),
      );
      expect(find.text('确认清单：2 部漫画'), findsOneWidget);
      await tap(tester, category(_first));
      await tap(tester, category(_third));
      expect(mutations(), isEmpty);
      await tap(tester, find.text('确认并开始'));
      expect(server.manga(alpha.mangaKey)!.categoryIds, [_first, _third]);
      expect(server.manga(beta.mangaKey)!.categoryIds, [
        _first,
        _second,
        _third,
      ]);
      await tap(tester, find.text('完成'));
      await selectAll(tester);
      await tap(
        tester,
        find.byKey(const ValueKey('library-batch-remove-categories')),
      );
      await tap(tester, category(_first));
      await tap(tester, find.text('确认并开始'));
      expect(server.manga(alpha.mangaKey)!.categoryIds, [_third]);
      expect(server.manga(beta.mangaKey)!.categoryIds, [_second, _third]);
      expect(mutations(), hasLength(4));
      expect(
        mutations()
            .map(command)
            .every(
              (mutation) =>
                  mutation.hasSetCategories() &&
                  mutation.setCategories.expectedCatalogRevision == 3,
            ),
        true,
      );
      expect(server.manga(alpha.mangaKey)!.favorite, true);
      expect(server.manga(beta.mangaKey)!.favorite, true);
      await tap(tester, find.text('完成'));
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a partial batch resumes its exact uncertain command before explicitly continuing the remainder',
    (tester) async {
      await favorite(tester, 'Alpha');
      await favorite(tester, 'Beta');
      await favorite(tester, 'Gamma');
      await show(tester);
      server.requests.clear();
      final appliedBefore = server.appliedMutations;
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
          body: 'Mutation acknowledgement unavailable',
          redirected: false,
        );
      };
      await selectAll(tester);
      await tap(
        tester,
        find.byKey(const ValueKey('library-batch-remove-favorites')),
      );
      await tap(tester, find.text('确认并开始'));
      expect(find.text('已确认 1 / 3 部 · 未开始 1 部'), findsOneWidget);
      expect(find.text('全部修改已由服务端确认。'), findsNothing);
      expect(server.appliedMutations, appliedBefore + 2);
      expect(mutations(), hasLength(2));
      final uncertain = mutations().last;
      final firstConfirmed = command(mutations().first).mangaKey;
      final third = (await tester.runAsync(() => remote.watchView().first))!
          .entries
          .single;
      await tap(tester, find.text('稍后处理'));
      expect(
        find.byKey(const ValueKey('library-resume-batch')),
        findsOneWidget,
      );
      await tap(tester, find.byKey(const ValueKey('library-resume-batch')));
      expect(find.text('已确认 1 / 3 部 · 未开始 1 部'), findsOneWidget);
      expect(mutations(), hasLength(2));
      await tap(tester, find.text('重试原未确认操作'));
      expect(mutations(), hasLength(3));
      expect(mutations().last.body, uncertain.body);
      expect(server.appliedMutations, appliedBefore + 2);
      expect(find.text('已确认 2 / 3 部 · 未开始 1 部'), findsOneWidget);
      expect(server.manga(third.mangaKey)!.favorite, true);
      expect(
        mutations().where(
          (request) => command(request).mangaKey == firstConfirmed,
        ),
        hasLength(1),
      );
      await tap(tester, find.text('继续剩余原清单'));
      expect(mutations(), hasLength(4));
      expect(server.appliedMutations, appliedBefore + 3);
      expect(server.manga(third.mangaKey)!.favorite, false);
      expect(find.text('全部修改已由服务端确认。'), findsOneWidget);
      await tap(tester, find.text('完成'));
      expect(find.byKey(const ValueKey('library-resume-batch')), findsNothing);
      expect(find.text('书架还是空的'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a remote edit cannot rebase an open batch and requires an explicit reread',
    (tester) async {
      await createCategory(tester, _first, '想读');
      await favorite(tester, 'Alpha');
      await favorite(tester, 'Beta');
      final view = (await tester.runAsync(
        () => controller.library!.watchView().first,
      ))!;
      final changed = view.entries.first;
      await show(tester);
      await selectAll(tester);
      await tap(
        tester,
        find.byKey(const ValueKey('library-batch-add-categories')),
      );
      await tap(tester, category(_first));
      await tester.runAsync(() async {
        await remote.setCategories(
          mangaKey: changed.mangaKey,
          categoryIds: [_first],
          expectedCatalogRevision: view.categoryRevision,
          expectedMangaRevision: changed.revision,
        );
        await controller.library!.refresh();
      });
      server.requests.clear();
      await tap(tester, find.text('确认并开始'));
      expect(find.textContaining('需重新读取'), findsWidgets);
      expect(find.text('重试原未确认操作'), findsNothing);
      expect(find.text('继续剩余原清单'), findsNothing);
      expect(mutations(), isEmpty);
      expect(server.manga(changed.mangaKey)!.categoryIds, [_first]);
      expect(server.manga(view.entries.last.mangaKey)!.categoryIds, isEmpty);
      await tap(tester, find.text('重新读取并结束原批次'));
      expect(mutations(), isEmpty);
      expect(find.text('全部修改已由服务端确认。'), findsNothing);
      await tap(tester, find.text('完成'));
      expect(find.byKey(const ValueKey('library-resume-batch')), findsNothing);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'system back waits for a busy batch and clears selection after confirmed categories',
    (tester) async {
      await createCategory(tester, _first, '想读');
      final alpha = await favorite(tester, 'Alpha');
      final beta = await favorite(tester, 'Beta');
      await show(tester);
      server.requests.clear();
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
      await selectAll(tester);
      await tap(
        tester,
        find.byKey(const ValueKey('library-batch-add-categories')),
      );
      await tap(tester, category(_first));
      await tester.runAsync(() async {
        await tester.tap(find.text('确认并开始'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 32));
      await tester.runAsync(
        () => received.future.timeout(const Duration(seconds: 5)),
      );
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 32));
      expect(
        find.byKey(const ValueKey('library-batch-review')),
        findsOneWidget,
      );
      expect(find.text('全部修改已由服务端确认。'), findsNothing);
      expect(mutations(), hasLength(1));
      await tester.runAsync(() async {
        release.complete();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('全部修改已由服务端确认。'), findsOneWidget);
      expect(server.manga(alpha.mangaKey)!.categoryIds, [_first]);
      expect(server.manga(beta.mangaKey)!.categoryIds, [_first]);
      expect(mutations(), hasLength(2));
      await tester.runAsync(() async {
        await tester.binding.handlePopRoute();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-batch-review')), findsNothing);
      final toggle = find.byKey(const ValueKey('library-selection-toggle'));
      await tester.scrollUntilVisible(
        toggle,
        -200,
        scrollable: find
            .descendant(
              of: find.byType(LibraryPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('选择漫画'), findsOneWidget);
      expect(find.text('退出选择'), findsNothing);
      expect(find.textContaining('已选 '), findsNothing);
      expect(find.byKey(ValueKey(alpha.mangaKey)), findsOneWidget);
      expect(find.byKey(ValueKey(beta.mangaKey)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'an identity change retires the batch and a late acknowledgement cannot send its remainder',
    (tester) async {
      await favorite(tester, 'Alpha');
      await favorite(tester, 'Beta');
      await show(tester);
      server.requests.clear();
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
      await selectAll(tester);
      await tap(
        tester,
        find.byKey(const ValueKey('library-batch-remove-favorites')),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('确认并开始'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump(const Duration(milliseconds: 32));
      await tester.runAsync(
        () => received.future.timeout(const Duration(seconds: 5)),
      );
      expect(find.text('全部修改已由服务端确认。'), findsNothing);
      expect(mutations(), hasLength(1));
      platform.bootstrapSubject = 'other-subject';
      await tester.runAsync(controller.connect);
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.textContaining('原窗口已停用'), findsOneWidget);
      await tester.runAsync(() async {
        release.complete();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('原窗口已停用'), findsOneWidget);
      expect(find.text('全部修改已由服务端确认。'), findsNothing);
      expect(mutations(), hasLength(1));
      expect(
        mutations().single.headers.entries
            .singleWhere(
              (header) => header.key.toLowerCase() == 'x-app-subject',
            )
            .value,
        'owner-subject',
      );
      await tap(tester, find.text('稍后处理'));
      expect(find.text('书架还是空的'), findsOneWidget);
      expect(find.byKey(const ValueKey('library-resume-batch')), findsNothing);
      expect(find.textContaining('已选 '), findsNothing);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );
}
