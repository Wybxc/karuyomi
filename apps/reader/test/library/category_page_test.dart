import 'package:karuyomi/widgets/choice_field.dart';
import 'package:karuyomi/widgets/edit_sheet.dart';

import '../../test_support/cupertino.dart';
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
const _conflict = '分类或漫画已在其他设备修改，请重新读取后重开编辑。';
const _expired = '身份或服务已变化，请关闭后重新打开。';

void main() {
  late TestBusinessServer server;
  late TestPlatform platform;
  late CatalogController controller;
  late BusinessStateClient remoteClient;
  late LibraryRepository remote;

  setUp(() async {
    server = TestBusinessServer();
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

  Future<void> show(WidgetTester tester, {CatalogController? service}) async {
    final current = service ?? controller;
    await tester.pumpApp(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: LibraryPage(
            controller: current,
            onBrowse: () {},
            onConnect: () => unawaited(current.connect()),
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
    if (finder.evaluate().isEmpty) {
      await tester.tap(iconLabel('书架选项'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(finder);
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  final categoryFilter = find.byKey(const ValueKey('library-category-filter'));
  Future<void> filter(WidgetTester tester, String name) async {
    await tap(tester, categoryFilter);
    await tap(tester, find.widgetWithText(CupertinoMenuItem, name));
  }

  bool hasCategory(WidgetTester tester, String name) => tester
      .widget<ChoiceField<String>>(categoryFilter)
      .options
      .containsValue(name);

  Future<void> create(
    WidgetTester tester, {
    String id = _first,
    String name = '想读',
  }) async {
    await tester.runAsync(
      () => controller.library!.createCategory(
        categoryId: id,
        name: name,
        expectedRevision: server.catalog().revision,
      ),
    );
  }

  Future<LibraryEntry> favorite(WidgetTester tester, String title) async {
    final entry = await tester.runAsync(() async {
      await controller.library!.setFavorite(
        packageName: 'eu.kanade.source.test',
        sourceId: sourceId,
        sourceName: '测试漫画源',
        sourceLang: 'zh',
        manga: wire.Manga(url: '/manga/$title', title: title),
        favorite: true,
      );
      return (await controller.library!.watchView().first).entries.singleWhere(
        (entry) => entry.title == title,
      );
    });
    if (entry == null) {
      throw StateError('Expected a confirmed test favorite');
    }
    return entry;
  }

  Future<void> nameAndSave(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(CupertinoTextField).last, name);
    await tap(tester, find.text('保存'));
  }

  Iterable<TestBusinessRequest> posts(String path) => server.requests.where(
    (request) => request.method == 'POST' && request.uri.path == path,
  );

  testWidgets(
    'an empty shelf can create, rename, reorder and delete server categories',
    (tester) async {
      await show(tester);
      expect(find.text('书架还是空的'), findsOneWidget);
      await tap(tester, find.text('管理分类'));
      await tap(tester, find.text('新建分类'));
      await nameAndSave(tester, '  想读  ');
      expect(server.catalog().categories.map((value) => value.name), ['想读']);

      await tap(tester, find.text('新建分类'));
      await nameAndSave(tester, '科幻');
      expect(server.catalog().categories.map((value) => value.name), [
        '想读',
        '科幻',
      ]);
      await tap(tester, iconLabel('上移分类 科幻'));
      expect(server.catalog().categories.map((value) => value.name), [
        '科幻',
        '想读',
      ]);
      await tap(tester, iconLabel('下移分类 科幻'));
      expect(server.catalog().categories.map((value) => value.name), [
        '想读',
        '科幻',
      ]);
      await tap(tester, iconLabel('重命名分类 想读'));
      await nameAndSave(tester, '待读');
      expect(server.catalog().categories.first.name, '待读');
      await tap(tester, iconLabel('删除分类 科幻'));
      await tap(tester, find.text('删除'));
      expect(server.catalog().categories.map((value) => value.name), ['待读']);
      await tap(tester, find.text('完成'));
      expect(hasCategory(tester, '待读'), true);
      expect(platform.invocations, isEmpty);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'multiple category selection and filters use the same confirmed shelf',
    (tester) async {
      await create(tester);
      await create(tester, id: _second, name: '科幻');
      final alpha = await favorite(tester, 'Alpha');
      await favorite(tester, 'Beta');
      await show(tester);
      await tap(tester, iconLabel('更多操作：Alpha'));
      await tap(tester, iconLabel('设置分类：Alpha'));
      await tap(tester, checkboxLabel('想读'));
      await tap(tester, checkboxLabel('科幻'));
      await tap(tester, find.text('保存'));
      expect(server.manga(alpha.mangaKey)!.categoryIds, [_first, _second]);
      await filter(tester, '想读');
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      await filter(tester, '未分类');
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsOneWidget);
      await filter(tester, '全部');
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      await tap(tester, iconLabel('更多操作：Alpha'));
      await tap(tester, iconLabel('设置分类：Alpha'));
      await tap(tester, checkboxLabel('想读'));
      await tap(tester, checkboxLabel('科幻'));
      await tap(tester, find.text('保存'));
      expect(server.manga(alpha.mangaKey)!.categoryIds, isEmpty);
      await filter(tester, '未分类');
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(platform.invocations, isEmpty);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a remote catalog edit cannot rebase an already open rename dialog',
    (tester) async {
      await create(tester);
      await show(tester);
      await tap(tester, find.text('管理分类'));
      await tap(tester, iconLabel('重命名分类 想读'));
      await tester.enterText(find.byType(CupertinoTextField).last, '本端草稿');
      await tester.runAsync(
        () => remote.renameCategory(
          categoryId: _first,
          name: '另一设备',
          expectedRevision: 1,
        ),
      );
      await tester.runAsync(() => controller.library!.refresh());
      await tester.pumpAndSettle();
      await tap(tester, find.text('保存'));
      expect(find.text(_conflict), findsWidgets);
      expect(server.catalog().categories.single.name, '另一设备');
      final attempted = wire.decodeProtoJson(
        wire.CategoryMutation(),
        jsonDecode(posts('/api/categories/mutations').last.body!),
      );
      expect(attempted.expectedRevision, 1);
      expect(attempted.renameCategory.name, '本端草稿');
      final postCount = posts('/api/categories/mutations').length;
      // A conflict cannot become an implicit retry against the new revision.
      expect(find.text('重试保存'), findsNothing);
      expect(posts('/api/categories/mutations').length, postCount);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a remote manga update cannot rebase an open multi-category selection',
    (tester) async {
      await create(tester);
      await create(tester, id: _second, name: '科幻');
      final alpha = await favorite(tester, 'Alpha');
      await show(tester);
      await tap(tester, iconLabel('更多操作：Alpha'));
      await tap(tester, iconLabel('设置分类：Alpha'));
      await tap(tester, checkboxLabel('科幻'));
      await tester.runAsync(
        () => remote.setCategories(
          mangaKey: alpha.mangaKey,
          categoryIds: [_first],
          expectedCatalogRevision: 2,
          expectedMangaRevision: alpha.revision,
        ),
      );
      await tester.runAsync(() => controller.library!.refresh());
      await tester.pumpAndSettle();
      final postCount = posts('/api/state/mutations').length;
      await tap(tester, find.text('保存'));
      expect(find.text(_conflict), findsWidgets);
      expect(server.manga(alpha.mangaKey)!.categoryIds, [_first]);
      // The data layer can reject the stale manga CAS before sending a request.
      expect(posts('/api/state/mutations').length, postCount);
      expect(find.text('重试保存'), findsNothing);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a lost category creation reply retains its exact request for explicit retry',
    (tester) async {
      await show(tester);
      await tap(tester, find.text('管理分类'));
      await tap(tester, find.text('新建分类'));
      platform.afterBusinessReply = (request, reply) {
        if (request.method != 'POST' ||
            request.uri.path != '/api/categories/mutations') {
          return reply;
        }
        platform.afterBusinessReply = null;
        // The mutation reached the supplier, but its ACK was unavailable to
        // this client. Keep the runtime healthy so the exact request can retry.
        return const ApiReply(
          status: 503,
          headers: {'content-type': 'text/plain'},
          body: 'Mutation acknowledgement unavailable',
          redirected: false,
        );
      };
      await nameAndSave(tester, '想读');
      expect(find.textContaining('尚未确认保存'), findsWidgets);
      expect(server.catalog().categories.map((value) => value.name), ['想读']);
      final initial = posts('/api/categories/mutations').single.body;
      expect(server.appliedMutations, 1);
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField).last)
            .enabled,
        false,
      );
      expect(hasCategory(tester, '想读'), false);
      await tap(tester, find.text('稍后处理').last);
      expect(
        tester
            .widget<CupertinoButton>(
              find.widgetWithText(CupertinoButton, '新建分类'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, find.text('稍后处理'));
      expect(find.text('处理未确认修改'), findsOneWidget);
      await tap(tester, find.text('处理未确认修改'));
      await tap(tester, find.text('继续未确认修改'));
      expect(posts('/api/categories/mutations'), hasLength(1));
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField).last)
            .enabled,
        false,
      );
      await tap(tester, find.text('重试保存'));
      expect(posts('/api/categories/mutations').map((value) => value.body), [
        initial,
        initial,
      ]);
      expect(server.appliedMutations, 1);
      await tap(tester, find.text('完成'));
      expect(hasCategory(tester, '想读'), true);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a failed association remains unsaved until an exact explicit retry succeeds',
    (tester) async {
      await create(tester);
      final alpha = await favorite(tester, 'Alpha');
      await show(tester);
      await tap(tester, iconLabel('更多操作：Alpha'));
      await tap(tester, iconLabel('设置分类：Alpha'));
      await tap(tester, checkboxLabel('想读'));
      server.failWrites = true;
      await tap(tester, find.text('保存'));
      expect(find.textContaining('尚未确认保存'), findsWidgets);
      expect(server.manga(alpha.mangaKey)!.categoryIds, isEmpty);
      expect(
        tester.widget<CupertinoCheckbox>(checkboxLabel('想读')).onChanged,
        isNull,
      );
      final first = posts('/api/state/mutations').last.body;
      final postCount = posts('/api/state/mutations').length;
      server.failWrites = false;
      await tap(tester, find.text('重试保存'));
      expect(posts('/api/state/mutations').length, postCount + 1);
      expect(posts('/api/state/mutations').last.body, first);
      expect(server.manga(alpha.mangaKey)!.categoryIds, [_first]);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a service identity switch disables a category draft instead of writing it to the new account',
    (tester) async {
      await show(tester);
      await tap(tester, find.text('管理分类'));
      await tap(tester, find.text('新建分类'));
      await tester.enterText(find.byType(CupertinoTextField).last, '旧身份草稿');
      final postCount = posts('/api/categories/mutations').length;
      platform.bootstrapSubject = 'other-subject';
      await tester.runAsync(controller.connect);
      await tester.pumpAndSettle();
      expect(find.text(_expired), findsWidgets);
      expect(
        tester
            .widget<CupertinoButton>(find.widgetWithText(CupertinoButton, '保存'))
            .onPressed,
        isNull,
      );
      expect(posts('/api/categories/mutations').length, postCount);
      expect(server.catalog().categories, isEmpty);
      expect(server.catalog(subject: 'other-subject').categories, isEmpty);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'category management remains usable on a narrow display with long names',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 760);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final name = '长' * 80;
      await create(tester, name: name);
      await create(tester, id: _second, name: '科幻');
      await favorite(tester, 'Alpha');
      await show(tester);
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('管理分类'));
      expect(iconLabel('重命名分类 $name'), findsOneWidget);
      expect(iconLabel('删除分类 $name'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, iconLabel('重命名分类 $name'));
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField).last, '长篇·待读');
      expect(find.text('保存').hitTestable(), findsOneWidget);
      expect(tester.getRect(find.text('保存')).bottom, lessThanOrEqualTo(440));
      await tap(tester, find.text('保存'));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(server.catalog().categories.first.name, '长篇·待读');
      await tap(tester, find.text('完成'));
      await tap(tester, iconLabel('更多操作：Alpha'));
      await tap(tester, iconLabel('设置分类：Alpha'));
      expect(checkboxLabel('长篇·待读'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'an open picker keeps its catalog revision until an explicit reread and reopening',
    (tester) async {
      await create(tester);
      await create(tester, id: _second, name: '科幻');
      final alpha = await favorite(tester, 'Alpha');
      await show(tester);
      await tap(tester, iconLabel('更多操作：Alpha'));
      await tap(tester, iconLabel('设置分类：Alpha'));
      await tap(tester, checkboxLabel('想读'));
      await tester.runAsync(
        () => remote.renameCategory(
          categoryId: _second,
          name: '新名字',
          expectedRevision: 2,
        ),
      );
      await tester.runAsync(() => controller.library!.refresh());
      await tester.pumpAndSettle();
      await tap(tester, find.text('保存'));
      expect(find.text(_conflict), findsWidgets);
      expect(server.manga(alpha.mangaKey)!.categoryIds, isEmpty);
      final rejected = wire.decodeProtoJson(
        wire.StateMutation(),
        jsonDecode(posts('/api/state/mutations').last.body!),
      );
      expect(rejected.expectedRevision, alpha.revision);
      expect(rejected.setCategories.expectedCatalogRevision, 2);
      final attempts = posts('/api/state/mutations').length;
      expect(find.text('重试保存'), findsNothing);
      await tap(tester, find.text('重新读取并关闭'));
      expect(posts('/api/state/mutations').length, attempts);
      await tap(tester, iconLabel('更多操作：Alpha'));
      await tap(tester, iconLabel('设置分类：Alpha'));
      expect(checkboxLabel('新名字'), findsOneWidget);
      await tap(tester, checkboxLabel('想读'));
      await tap(tester, find.text('保存'));
      final accepted = wire.decodeProtoJson(
        wire.StateMutation(),
        jsonDecode(posts('/api/state/mutations').last.body!),
      );
      expect(accepted.setCategories.expectedCatalogRevision, 3);
      expect(accepted.mutationId, isNot(rejected.mutationId));
      expect(server.manga(alpha.mangaKey)!.categoryIds, [_first]);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets('reconnecting the same identity never revives the old draft', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, find.text('管理分类'));
    await tap(tester, find.text('新建分类'));
    await tester.enterText(find.byType(CupertinoTextField).last, '旧会话草稿');
    await tester.runAsync(controller.connect);
    await tester.pumpAndSettle();
    expect(find.text(_expired), findsWidgets);
    expect(
      tester
          .widget<CupertinoTextField>(find.byType(CupertinoTextField).last)
          .enabled,
      false,
    );
    expect(
      tester
          .widget<CupertinoButton>(find.widgetWithText(CupertinoButton, '保存'))
          .onPressed,
      isNull,
    );
    expect(posts('/api/categories/mutations'), isEmpty);
    await tap(tester, find.text('取消'));
    await tap(tester, find.text('完成'));
    await tap(tester, find.text('管理分类'));
    await tap(tester, find.text('新建分类'));
    await nameAndSave(tester, '新会话修改');
    expect(server.catalog().categories.map((category) => category.name), [
      '新会话修改',
    ]);
    expect(tester.takeException(), isNull);
    await hide(tester);
  });

  testWidgets(
    'replacing the service immediately retires an open draft even with the same identity',
    (tester) async {
      await show(tester);
      await tap(tester, find.text('管理分类'));
      await tap(tester, find.text('新建分类'));
      await tester.enterText(find.byType(CupertinoTextField).last, '旧服务草稿');
      final nextPlatform = TestPlatform();
      final nextController = CatalogController(
        api: nextPlatform,
        runtime: nextPlatform.runtime,
        rebuildRuntime: nextPlatform.rebuild,
        deploymentOrigin: nextPlatform.origin,
      );
      addTearDown(() async {
        nextController.dispose();
        await nextController.closeReadingProgress();
        await nextPlatform.dispose();
      });
      await tester.runAsync(nextController.connect);
      await show(tester, service: nextController);
      expect(find.text(_expired), findsWidgets);
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField).last)
            .enabled,
        false,
      );
      expect(
        tester
            .widget<CupertinoButton>(find.widgetWithText(CupertinoButton, '保存'))
            .onPressed,
        isNull,
      );
      expect(posts('/api/categories/mutations'), isEmpty);
      expect(nextPlatform.businessServer.catalog().categories, isEmpty);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a category reply arriving after an identity change cannot close or save the new account editor',
    (tester) async {
      await show(tester);
      await tap(tester, find.text('管理分类'));
      await tap(tester, find.text('新建分类'));
      await tester.enterText(find.byType(CupertinoTextField).last, '旧请求');
      final received = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) {
          release.complete();
        }
      });
      platform.afterBusinessReply = (request, reply) async {
        if (request.method != 'POST' ||
            request.uri.path != '/api/categories/mutations') {
          return reply;
        }
        platform.afterBusinessReply = null;
        received.complete();
        await release.future;
        return reply;
      };
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.runAsync(() => received.future);
      expect(server.catalog().categories.single.name, '旧请求');
      platform.bootstrapSubject = 'other-subject';
      await tester.runAsync(controller.connect);
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.text(_expired), findsWidgets);
      release.complete();
      await tester.pumpAndSettle();
      expect(find.byType(EditSheet), findsNWidgets(2));
      expect(find.text(_expired), findsWidgets);
      expect(
        tester
            .widget<CupertinoButton>(find.byType(CupertinoButton).last)
            .onPressed,
        isNull,
      );
      expect(server.catalog(subject: 'other-subject').categories, isEmpty);
      expect(server.appliedMutations, 1);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'busy category drafts can resume after reconnect and accept their original late acknowledgement',
    (tester) async {
      var received = Completer<void>();
      var release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) {
          release.complete();
        }
      });
      void holdReply(String path) {
        platform.afterBusinessReply = (request, reply) async {
          if (request.method != 'POST' || request.uri.path != path) {
            return reply;
          }
          platform.afterBusinessReply = null;
          received.complete();
          await release.future;
          return reply;
        };
      }

      Future<void> startSaving() async {
        await tester.tap(find.text('保存'));
        await tester.pump();
        await tester.runAsync(
          () => received.future.timeout(const Duration(seconds: 5)),
        );
      }

      Future<void> acknowledge() async {
        await tester.runAsync(() async {
          release.complete();
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
      }

      Future<void> tapBusy(Finder finder) async {
        await tester.runAsync(() async {
          await tester.tap(finder);
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
      }

      await show(tester);
      await tap(tester, find.text('管理分类'));
      await tap(tester, find.text('新建分类'));
      await tester.enterText(find.byType(CupertinoTextField).last, '迟到确认');
      holdReply('/api/categories/mutations');
      await startSaving();
      final createdId = server.catalog().categories.single.id;
      await tester.runAsync(controller.connect);
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.text(_expired), findsWidgets);
      // An expired busy modal can close, while the original command stays held.
      await tapBusy(
        find.descendant(
          of: find.byKey(const ValueKey('category-command')),
          matching: find.text('稍后处理'),
        ),
      );
      // Sheets retain a departing route for their delegated transition. Count
      // active editors while a spinner prevents using pumpAndSettle.
      final activeSheets = find.byElementPredicate(
        (element) =>
            element.widget is EditSheet &&
            ModalRoute.of(element)?.isActive == true,
      );
      expect(activeSheets, findsOneWidget);
      await tap(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('category-manager')),
          matching: find.text('稍后处理'),
        ),
      );
      expect(activeSheets, findsNothing);
      await tapBusy(find.text('处理未确认修改'));
      expect(activeSheets, findsOneWidget);
      expect(iconLabel('书架选项'), findsOneWidget);
      expect(find.text(_expired), findsNothing);
      expect(
        tester
            .widget<CupertinoButton>(
              find.widgetWithText(CupertinoButton, '新建分类'),
            )
            .onPressed,
        isNull,
      );
      await acknowledge();
      expect(find.byType(EditSheet), findsOneWidget);
      expect(iconLabel('重命名分类 迟到确认'), findsOneWidget);
      expect(
        tester
            .widget<CupertinoButton>(
              find.widgetWithText(CupertinoButton, '新建分类'),
            )
            .onPressed,
        isNotNull,
      );
      expect(posts('/api/categories/mutations'), hasLength(1));
      await tap(tester, find.text('完成'));

      final alpha = await favorite(tester, 'Alpha');
      await tester.pumpAndSettle();
      await tap(tester, iconLabel('更多操作：Alpha'));
      await tap(tester, iconLabel('设置分类：Alpha'));
      await tap(tester, checkboxLabel('迟到确认'));
      received = Completer<void>();
      release = Completer<void>();
      holdReply('/api/state/mutations');
      await startSaving();
      final sent = posts('/api/state/mutations').length;
      await tester.runAsync(controller.connect);
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.text(_expired), findsWidgets);
      await tap(tester, find.text('稍后处理'));
      expect(find.byType(EditSheet), findsNothing);
      await tapBusy(find.text('处理未确认修改'));
      expect(find.text('设置分类'), findsOneWidget);
      expect(find.text(_expired), findsNothing);
      await acknowledge();
      expect(find.byType(EditSheet), findsOneWidget);
      expect(find.text('分类修改已由服务端确认。'), findsOneWidget);
      expect(
        tester.widget<CupertinoCheckbox>(checkboxLabel('迟到确认')).onChanged,
        isNull,
      );
      expect(posts('/api/state/mutations').length, sent);
      expect(server.manga(alpha.mangaKey)!.categoryIds, [createdId]);
      await tap(tester, find.text('完成'));
      expect(find.byType(EditSheet), findsNothing);
      expect(find.text('处理未确认修改'), findsNothing);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a category edit blocked by another uncertain write can close without replaying that write',
    (tester) async {
      await create(tester);
      final alpha = await favorite(tester, 'Alpha');
      await show(tester);
      Future<void> remove() => controller.library!.setFavorite(
        packageName: alpha.packageName,
        sourceId: alpha.sourceId,
        sourceName: alpha.sourceName,
        sourceLang: alpha.sourceLang,
        manga: alpha.snapshot,
        favorite: false,
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
          body: 'Acknowledgement unavailable',
          redirected: false,
        );
      };
      await tester.runAsync(
        () => expectLater(
          remove(),
          throwsA(isA<BusinessStateTransportException>()),
        ),
      );
      final original = posts('/api/state/mutations').last.body;
      final sent = posts('/api/state/mutations').length;
      await tap(tester, iconLabel('更多操作：Alpha'));
      await tap(tester, iconLabel('设置分类：Alpha'));
      await tap(tester, checkboxLabel('想读'));
      await tap(tester, find.text('保存'));
      expect(find.textContaining('先处理原操作'), findsOneWidget);
      expect(find.text('重新读取并关闭'), findsOneWidget);
      expect(posts('/api/state/mutations'), hasLength(sent));
      await tap(tester, find.text('重新读取并关闭'));
      expect(find.byType(EditSheet), findsNothing);
      expect(find.text('处理未确认修改'), findsNothing);
      expect(find.text('书架还是空的'), findsOneWidget);
      expect(posts('/api/state/mutations'), hasLength(sent));
      await tester.runAsync(remove);
      expect(posts('/api/state/mutations'), hasLength(sent + 1));
      expect(posts('/api/state/mutations').last.body, original);
      expect(server.manga(alpha.mangaKey)!.categoryIds, isEmpty);
      expect(server.manga(alpha.mangaKey)!.favorite, false);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'deleting the selected category restores the all filter and keeps favorites',
    (tester) async {
      await create(tester);
      await create(tester, id: _second, name: '科幻');
      final alpha = await favorite(tester, 'Alpha');
      await favorite(tester, 'Beta');
      await tester.runAsync(
        () => controller.library!.setCategories(
          mangaKey: alpha.mangaKey,
          categoryIds: [_first],
          expectedCatalogRevision: 2,
          expectedMangaRevision: alpha.revision,
        ),
      );
      await show(tester);
      await filter(tester, '想读');
      expect(find.text('Beta'), findsNothing);
      await tap(tester, find.text('管理分类'));
      await tap(tester, iconLabel('删除分类 想读'));
      await tap(tester, find.text('删除'));
      await tap(tester, find.text('完成'));
      expect(hasCategory(tester, '想读'), false);
      expect(
        tester.widget<ChoiceField<String>>(categoryFilter).value == null,
        true,
      );
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(server.manga(alpha.mangaKey)!.favorite, true);
      expect(server.manga(alpha.mangaKey)!.categoryIds, isEmpty);
      expect(platform.invocations, isEmpty);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );
}
