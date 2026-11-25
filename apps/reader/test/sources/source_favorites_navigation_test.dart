import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../test_app.dart';

import 'dart:async';
import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/business_state_validation.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import '../data/business_state_server.dart';

wire.FavoriteSource _favorite({
  String package = 'eu.kanade.source.test',
  String name = '旧来源名称',
}) => wire.FavoriteSource(
  packageName: package,
  sourceId: sourceId,
  sourceName: name,
  sourceLang: 'zh',
);
wire.GlobalSettingsValues _values({
  List<wire.FavoriteSource> favorites = const [],
}) => wire.GlobalSettingsValues(
  reader: wire.ReaderSettings(
    mode: wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
    pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
    fit: wire.ReaderFit.READER_FIT_HEIGHT,
    cropBorders: true,
  ),
  favoriteSources: favorites,
  installedExtensions: [testInstalledExtension()],
);

void main() {
  late TestPlatform platform;
  late CatalogController catalog;
  late ProviderContainer container;
  late BusinessStateClient remote;
  late SettingsRepository remoteSettings;

  setUp(() async {
    container = ProviderContainer();
    platform = TestPlatform();
    catalog = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    remote = BusinessStateClient(
      api: platform.businessServer,
      identity: catalog.settings!.identity,
    );
    remoteSettings = SettingsRepository(remote);
  });
  tearDown(() async {
    container.dispose();
    catalog.dispose();
    await catalog.closeReadingProgress();
    await remote.dispose();
    await platform.dispose();
  });

  Future<void> seed(wire.GlobalSettingsValues values) async {
    final before = await remoteSettings.loadGlobal();
    await remoteSettings.setGlobal(
      values: values,
      basedOnRevision: before.globalRevision,
    );
  }

  Completer<void> gate() {
    final value = Completer<void>();
    addTearDown(() {
      if (!value.isCompleted) value.complete();
    });
    return value;
  }

  Future<void> show(
    WidgetTester tester, {
    Brightness? appearance,
    Size size = const Size(480, 800),
    double textScale = 1,
    PageStorageBucket? pageStorage,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpApp(
      CupertinoApp(
        theme: appearance == null ? null : readerAppTheme(appearance),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: CupertinoPageScaffold(
          child: PageStorage(
            bucket: pageStorage ?? PageStorageBucket(),
            child: CatalogPage(
              controller: catalog,
              onConnect: () {},
              onAuthenticate: () {},
              onManageExtensions: () {},
            ),
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

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final scrollable = find
        .descendant(
          of: find.byKey(const PageStorageKey('source-directory-scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    if (finder.evaluate().isEmpty) {
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 220, scrollable: scrollable);
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder toggle() => find.byKey(
    const ValueKey((
      'source-favorite-toggle',
      'eu.kanade.source.test',
      sourceId,
    )),
  );
  Finder open(String package) =>
      find.byKey(ValueKey(('source-directory-row', package, sourceId)));
  Finder remove(String package) =>
      find.byKey(ValueKey(('source-favorite-toggle', package, sourceId)));
  List<TestBusinessRequest> posts() => platform.businessServer.requests
      .where(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/api/settings/mutations',
      )
      .toList();

  for (final appearance in Brightness.values) {
    testWidgets(
      'directory opening and favorite actions are separate keyboard targets in $appearance',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await show(
            tester,
            appearance: appearance,
            size: const Size(360, 800),
          );
          final source = open('eu.kanade.source.test');
          final sourceNode = tester.getSemantics(source);
          for (
            var parent = tester.getSemantics(toggle()).parent;
            parent != null;
            parent = parent.parent
          ) {
            expect(
              parent.id,
              isNot(sourceNode.id),
              reason:
                  'the favorite action must not be nested in the open action',
            );
          }
          CupertinoButton? focusedButton() => FocusManager
              .instance
              .primaryFocus
              ?.context
              ?.findAncestorWidgetOfExactType<CupertinoButton>();
          for (
            var attempt = 0;
            attempt < 16 &&
                focusedButton()?.key != toggle().evaluate().single.widget.key;
            attempt++
          ) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          expect(focusedButton(), tester.widget<CupertinoButton>(toggle()));
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(platform.openedBuilds, isEmpty);
          expect(posts(), hasLength(1));
          expect(
            (await remoteSettings.loadGlobal())
                .global
                .favoriteSources
                .single
                .sourceId,
            sourceId,
          );
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
          expect(
            focusedButton()?.key,
            const ValueKey((
              'configure-source',
              'eu.kanade.source.test',
              sourceId,
            )),
          );
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
          expect(
            find.descendant(
              of: find.byWidget(focusedButton()!),
              matching: source,
            ),
            findsOneWidget,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(platform.openedBuilds, ['build-1']);
          expect(catalog.activeSource!.id, sourceId);
          expect(posts(), hasLength(1));
          expect(tester.takeException(), isNull);
          await hide(tester);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'stars wait for account ACK and preserve all other global settings',
    (tester) async {
      final original = _values();
      await seed(original);
      await show(tester);
      final entered = Completer<void>(), release = gate();
      var hold = true;
      platform.afterBusinessReply = (request, reply) async {
        if (hold &&
            request.method == 'POST' &&
            request.uri.path == '/api/settings/mutations') {
          hold = false;
          entered.complete();
          await release.future;
        }
        return reply;
      };
      await tester.tap(toggle());
      await tester.pump();
      await tester.runAsync(
        () => entered.future.timeout(const Duration(seconds: 5)),
      );
      expect(catalog.installationSettings!.global.favoriteSources, isEmpty);
      expect(
        find.descendant(
          of: find.byType(SettingsStatus),
          matching: find.byType(CupertinoActivityIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey(('settings-activity', 'saving'))),
        findsOneWidget,
      );
      expect(toggle(), findsNothing);
      final command = wire.decodeProtoJson(
        wire.SettingsMutation(),
        jsonDecode(posts().last.body!),
      );
      expect(command.setGlobal.reader, original.reader);
      release.complete();
      await tester.pumpAndSettle();
      expect(find.text('正在等待服务端确认设置修改'), findsNothing);
      expect(
        tester.widget<CupertinoButton>(toggle()).child,
        isA<Icon>().having(
          (icon) => icon.icon,
          'saved star',
          CupertinoIcons.star_fill,
        ),
      );
      expect(platform.openedBuilds, isEmpty);
      await tap(tester, toggle());
      final confirmed = await remoteSettings.loadGlobal();
      expect(confirmed.global.favoriteSources, isEmpty);
      expect(confirmed.global.reader, original.reader);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'favorite capacity blocks additions while unavailable favorites remain removable',
    (tester) async {
      await seed(
        _values(
          favorites: [
            for (var index = 0; index < businessFavoriteSourceLimit; index++)
              _favorite(package: 'saved.extension.$index', name: '收藏 $index'),
          ],
        ),
      );
      await show(tester);
      await reveal(tester, toggle());
      expect(tester.widget<CupertinoButton>(toggle()).onPressed, isNull);
      final before = posts().length;
      await tester.tap(toggle());
      await tester.pumpAndSettle();
      expect(posts(), hasLength(before));
      expect(platform.openedBuilds, isEmpty);
      expect(find.byType(CatalogPage), findsOneWidget);
      final unavailable = remove('saved.extension.0');
      await tap(tester, unavailable);
      expect(
        (await remoteSettings.loadGlobal()).global.favoriteSources,
        hasLength(businessFavoriteSourceLimit - 1),
      );
      await reveal(tester, toggle());
      expect(tester.widget<CupertinoButton>(toggle()).onPressed, isNotNull);
      await tap(tester, toggle());
      expect(
        (await remoteSettings.loadGlobal()).global.favoriteSources,
        hasLength(businessFavoriteSourceLimit),
      );
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a source opens the selected build directly and its favorite survives catalog removal',
    (tester) async {
      await seed(_values(favorites: [_favorite()]));
      await show(tester);
      expect(catalog.session, isNull);
      final before = posts().length;
      await tap(tester, open('eu.kanade.source.test'));
      expect(catalog.activeSource!.id, sourceId);
      expect(catalog.mangas.single.title, testManga.title);
      expect(platform.openedBuilds, ['build-1']);
      expect(posts(), hasLength(before));
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pumpAndSettle();
      platform.inventory = wire.encodeProtoJson(
        wire.ExtensionIndex(schemaVersion: 1, repoId: 'keiyoushi'),
      );
      await catalog.connect();
      await tester.pumpAndSettle();
      expect(find.text('旧来源名称'), findsOneWidget);
      expect(find.textContaining('所选构建已下架'), findsWidgets);
      await tap(tester, remove('eu.kanade.source.test'));
      expect(
        (await remoteSettings.loadGlobal()).global.favoriteSources,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a shared unknown settings operation reopens and retries the same UUID and body',
    (tester) async {
      final values = _values(
        favorites: [_favorite(package: 'another.extension')],
      );
      final repository = SettingsRepository(catalog.settings!.client);
      final provider = settingsControllerProvider(catalog, catalog.settings);
      final subscription = container.listen(provider, (_, _) {});
      final editor = container.read(provider.notifier);
      await editor.refresh();
      var loseAck = true;
      platform.afterBusinessReply = (request, reply) {
        if (loseAck &&
            request.method == 'POST' &&
            request.uri.path == '/api/settings/mutations') {
          loseAck = false;
          return const ApiReply(
            status: 502,
            headers: {'content-type': 'text/plain'},
            body: 'Committed ACK was lost',
            redirected: false,
          );
        }
        return reply;
      };
      final applied = platform.businessServer.appliedMutations;
      expect(
        await editor.saveGlobal(
          values,
          container.read(provider).snapshot!.globalRevision,
        ),
        false,
      );
      final originalBody = posts().single.body;
      subscription.close();
      await show(tester);
      expect(find.text('设置尚未确认，本会话保留原操作。'), findsOneWidget);
      expect(find.textContaining('图像适配：适高'), findsNothing);
      await tap(tester, find.text('查看未确认的原全局设置'));
      expect(find.textContaining('图像适配：适高'), findsOneWidget);
      await reveal(tester, toggle());
      expect(tester.widget<CupertinoButton>(toggle()).onPressed, isNull);
      await tap(tester, find.text('重新读取设置'));
      expect(posts(), hasLength(1));
      expect(repository.pendingGlobal(), isNotNull);
      await hide(tester);
      await show(tester);
      await tap(tester, find.text('重试原设置操作'));
      expect(posts(), hasLength(2));
      expect(posts().last.body, originalBody);
      expect(platform.businessServer.appliedMutations, applied + 1);
      expect(repository.pendingGlobal(), isNull);
      expect((await remoteSettings.loadGlobal()).global, values);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  for (final appearance in Brightness.values) {
    for (final expanded in [false, true]) {
      testWidgets(
        'source recovery keeps scroll storage separate in $appearance when expanded=$expanded',
        (tester) async {
          final bucket = PageStorageBucket();
          await seed(_values(favorites: [_favorite()]));
          await show(tester, appearance: appearance, pageStorage: bucket);
          platform.businessServer.loseNextResponse = true;
          await tap(tester, toggle());
          final original = posts().last.body;
          final postCount = posts().length;
          final applied = platform.businessServer.appliedMutations;
          await tap(tester, find.text('查看未确认的原全局设置'));
          if (!expanded) {
            await tap(tester, find.text('查看未确认的原全局设置'));
          }
          await hide(tester);
          await show(tester, appearance: appearance, pageStorage: bucket);
          expect(tester.takeException(), isNull);
          expect(find.text('取消收藏源：旧来源名称'), findsOneWidget);
          expect(
            find.textContaining('图像适配：'),
            expanded ? findsOneWidget : findsNothing,
          );
          expect(posts(), hasLength(postCount));
          await tap(tester, find.text('重试原设置操作'));
          expect(posts(), hasLength(postCount + 1));
          expect(posts().last.body, original);
          expect(platform.businessServer.appliedMutations, applied);
          expect(catalog.settings!.pendingGlobal(), isNull);
          await hide(tester);
          await show(
            tester,
            appearance: appearance == Brightness.light
                ? Brightness.dark
                : Brightness.light,
            pageStorage: bucket,
          );
          expect(tester.takeException(), isNull);
          expect(toggle(), findsOneWidget);
          expect(posts(), hasLength(postCount + 1));
          await hide(tester);
        },
      );
    }

    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'pending source cancellation keeps its original object and natural insets in $appearance at $textScale',
        (tester) async {
          await seed(_values(favorites: [_favorite()]));
          await show(
            tester,
            appearance: appearance,
            size: const Size(360, 800),
            textScale: textScale,
          );
          platform.businessServer.loseNextResponse = true;
          await tap(tester, toggle());
          final original = posts().last.body;
          final postCount = posts().length;
          final applied = platform.businessServer.appliedMutations;
          final error = find.text('设置修改尚未确认，请明确重试原操作。');
          expect(tester.getTopLeft(error).dx, greaterThanOrEqualTo(16));
          expect(tester.getBottomRight(error).dx, lessThanOrEqualTo(344));
          expect(find.text('取消收藏源：旧来源名称'), findsOneWidget);
          expect(find.textContaining('图像适配：'), findsNothing);
          await tap(tester, find.text('重新读取设置'));
          expect(posts(), hasLength(postCount));
          expect(find.text('取消收藏源：旧来源名称'), findsOneWidget);
          await hide(tester);
          await show(
            tester,
            appearance: appearance,
            size: const Size(360, 800),
            textScale: textScale,
          );
          expect(find.text('取消收藏源：旧来源名称'), findsOneWidget);
          await tap(tester, find.text('查看未确认的原全局设置'));
          expect(find.textContaining('图像适配：适高'), findsOneWidget);
          await tap(tester, find.text('重试原设置操作'));
          expect(posts(), hasLength(postCount + 1));
          expect(posts().last.body, original);
          expect(platform.businessServer.appliedMutations, applied);
          expect(catalog.settings!.pendingGlobal(), isNull);
          expect(
            (await remoteSettings.loadGlobal()).global.favoriteSources,
            isEmpty,
          );
          expect(tester.takeException(), isNull);
          await hide(tester);
        },
      );
    }
  }

  testWidgets(
    'conflicts require a fresh read and changed identity discards old favorites',
    (tester) async {
      await show(tester);
      await seed(_values(favorites: [_favorite(package: 'remote.extension')]));
      await tap(tester, toggle());
      expect(catalog.settings!.pendingGlobal()!.retryable, false);
      expect(tester.widget<CupertinoButton>(toggle()).onPressed, isNull);
      expect(find.text('设置已在其他设备修改，请重新读取后确认。'), findsOneWidget);
      await tap(tester, find.text('重新读取设置'));
      expect(catalog.settings!.pendingGlobal(), isNull);
      expect(open('remote.extension'), findsOneWidget);
      final before = posts().length;
      platform.bootstrapSubject = 'another-owner';
      await catalog.connect();
      await tester.pumpAndSettle();
      expect(catalog.subject, 'another-owner');
      expect(open('remote.extension'), findsNothing);
      expect(posts(), hasLength(before));
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'frozen account operation remains identifiable from the source directory',
    (tester) async {
      final repository = catalog.settings!;
      final provider = settingsControllerProvider(catalog, repository);
      final subscription = container.listen(provider, (_, _) {});
      final editor = container.read(provider.notifier);
      expect(await editor.refresh(), true);
      final before = container.read(provider).snapshot!;
      final values = before.global.deepCopy()..installedExtensions.clear();
      platform.businessServer.loseNextResponse = true;
      expect(await editor.saveGlobal(values, before.globalRevision), false);
      final original = posts().single.body;
      final applied = platform.businessServer.appliedMutations;
      subscription.close();
      await show(tester);
      expect(find.textContaining('卸载扩展：'), findsOneWidget);
      expect(find.textContaining('eu.kanade.source.test'), findsWidgets);
      await tap(tester, find.text('重新读取设置'));
      await hide(tester);
      await show(tester);
      expect(find.textContaining('卸载扩展：'), findsOneWidget);
      await tap(tester, find.text('查看未确认的原全局设置'));
      expect(find.textContaining('扩展安装选择：空列表'), findsOneWidget);
      expect(posts(), hasLength(1));
      await tap(tester, find.text('重试原设置操作'));
      expect(posts(), hasLength(2));
      expect(posts().last.body, original);
      expect(platform.businessServer.appliedMutations, applied);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );
}
