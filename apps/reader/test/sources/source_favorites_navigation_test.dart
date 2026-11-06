import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/business_state_validation.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
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
  theme: wire.AppTheme.APP_THEME_DARK,
  reader: wire.ReaderSettings(
    mode: wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
    pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
    background: wire.ReaderBackground.READER_BACKGROUND_WHITE,
    dimPercent: 17,
    tapZones: wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED,
    keyboard: wire.ReaderInputPreset.READER_INPUT_PRESET_DISABLED,
    fit: wire.ReaderFit.READER_FIT_HEIGHT,
    cropBorders: true,
  ),
  favoriteSources: favorites,
);

void main() {
  late TestPlatform platform;
  late CatalogController catalog;
  late BusinessStateClient remote;
  late SettingsRepository remoteSettings;

  setUp(() async {
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

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogPage(
            controller: catalog,
            onConnect: () {},
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

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final scrollable = find
        .descendant(
          of: find.byType(CatalogPage),
          matching: find.byType(Scrollable),
        )
        .first;
    if (finder.evaluate().isEmpty) {
      await tester.drag(scrollable, const Offset(0, 2500));
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
      find.byKey(ValueKey(('favorite-source-open', package, sourceId)));
  Finder remove(String package) =>
      find.byKey(ValueKey(('favorite-source-remove', package, sourceId)));
  List<TestBusinessRequest> posts() => platform.businessServer.requests
      .where(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/api/settings/mutations',
      )
      .toList();
  Future<void> loadCurrent(WidgetTester tester) async {
    await tap(tester, find.text('eu.kanade.source.test · 1.0'));
    if (toggle().evaluate().isEmpty) await tap(tester, find.text('收藏的漫画源'));
    await reveal(tester, toggle());
  }

  testWidgets(
    'favorite capacity blocks a new request but cancellation and opening allow replacement',
    (tester) async {
      await seed(
        _values(
          favorites: [
            _favorite(),
            for (var index = 1; index < businessFavoriteSourceLimit; index++)
              _favorite(
                package: 'saved.extension.$index',
                name: '已收藏来源 $index',
              ),
          ],
        ),
      );
      platform.sourceInventory = [
        wire.SourceInfo(id: sourceId, name: '已收藏来源', lang: 'zh'),
        wire.SourceInfo(id: '42', name: '待新增来源', lang: 'en'),
      ];
      await catalog.openBuild(catalog.builds.single);
      await show(tester);
      // Opening a confirmed favorite remains usable at capacity.
      await tap(tester, open('eu.kanade.source.test'));
      expect(catalog.activeSource!.id, sourceId);
      final newToggle = find.byKey(
        const ValueKey((
          'source-favorite-toggle',
          'eu.kanade.source.test',
          '42',
        )),
      );
      await reveal(tester, newToggle);
      expect(
        find.byKey(const ValueKey('source-favorite-limit')),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(newToggle).onPressed, isNull);
      expect(tester.widget<IconButton>(toggle()).onPressed, isNotNull);
      final before = posts().length;
      await tester.tap(newToggle);
      await tester.pumpAndSettle();
      expect(posts(), hasLength(before));
      expect(catalog.settings!.pendingGlobal(), isNull);
      await tap(tester, toggle());
      expect(
        (await remoteSettings.loadGlobal()).global.favoriteSources,
        hasLength(businessFavoriteSourceLimit - 1),
      );
      await reveal(tester, newToggle);
      expect(find.byKey(const ValueKey('source-favorite-limit')), findsNothing);
      expect(tester.widget<IconButton>(newToggle).onPressed, isNotNull);
      await tap(tester, newToggle);
      final confirmed = await remoteSettings.loadGlobal();
      expect(
        confirmed.global.favoriteSources,
        hasLength(businessFavoriteSourceLimit),
      );
      expect(
        confirmed.global.favoriteSources.any(
          (source) =>
              source.packageName == 'eu.kanade.source.test' &&
              source.sourceId == sourceId,
        ),
        false,
      );
      expect(
        confirmed.global.favoriteSources.any(
          (source) =>
              source.packageName == 'eu.kanade.source.test' &&
              source.sourceId == '42',
        ),
        true,
      );
      expect(posts(), hasLength(before + 2));
      expect(catalog.settings!.pendingGlobal(), isNull);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'source stars wait for server confirmation and preserve every other global preference',
    (tester) async {
      final original = _values();
      await seed(original);
      await show(tester);
      await loadCurrent(tester);
      final entered = Completer<void>();
      final release = gate();
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
      expect(tester.widget<IconButton>(toggle()).onPressed, isNull);
      expect(open('eu.kanade.source.test'), findsNothing);
      final command = wire.decodeProtoJson(
        wire.SettingsMutation(),
        jsonDecode(posts().last.body!),
      );
      expect(command.setGlobal.reader, original.reader);
      expect(command.setGlobal.theme, original.theme);
      expect(command.setGlobal.favoriteSources.single.sourceId, sourceId);
      release.complete();
      await tester.pumpAndSettle();
      expect(open('eu.kanade.source.test'), findsOneWidget);
      expect(
        tester.widget<IconButton>(toggle()).icon,
        isA<Icon>().having((icon) => icon.icon, 'saved star', Icons.star),
      );
      await tap(tester, remove('eu.kanade.source.test'));
      expect(open('eu.kanade.source.test'), findsNothing);
      final confirmed = await remoteSettings.loadGlobal();
      expect(confirmed.global.favoriteSources, isEmpty);
      expect(confirmed.global.reader, original.reader);
      expect(confirmed.global.theme, original.theme);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'confirmed favorites open the current build without a prior package selection and remain removable when unavailable',
    (tester) async {
      await seed(_values(favorites: [_favorite()]));
      platform.inventory = wire.encodeProtoJson(
        wire.ExtensionIndex(
          schemaVersion: 1,
          builds: [
            wire.ExtensionBuildDescriptor(
              buildId: 'build-2',
              packageName: 'eu.kanade.source.test',
              version: '2.0',
              manifestPath: '/extensions/builds/build-2/manifest.json',
            ),
          ],
        ),
      );
      platform.manifestBuildId = 'build-2';
      platform.runtimeGeneration = 'generation-2';
      platform.sourceInventory = [
        wire.SourceInfo(id: sourceId, name: '当前来源名称', lang: 'zh'),
      ];
      await catalog.connect();
      await show(tester);
      expect(catalog.session, isNull);
      expect(find.text('旧来源名称'), findsOneWidget);
      await tap(tester, open('eu.kanade.source.test'));
      expect(platform.openedBuilds, ['build-2']);
      expect(catalog.activeSource!.id, sourceId);
      expect(catalog.activeSource!.name, '当前来源名称');
      expect(catalog.listing, 'popular');
      expect(catalog.mangas.single.title, testManga.title);
      expect(platform.invocations.single.hasPopular(), true);
      platform.inventory = wire.encodeProtoJson(
        wire.ExtensionIndex(schemaVersion: 1),
      );
      await catalog.connect();
      await tester.pumpAndSettle();
      await tap(tester, open('eu.kanade.source.test'));
      expect(catalog.error, contains('扩展当前不可用'));
      expect(open('eu.kanade.source.test'), findsOneWidget);
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
    'an original global settings draft survives a new panel and retries the same UUID and complete body',
    (tester) async {
      final values = _values(
        favorites: [_favorite(package: 'another.extension')],
      );
      final repository = SettingsRepository(catalog.settings!.client);
      final editor = SettingsController(
        repository: repository,
        isCurrent: () => true,
      );
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
      final appliedBefore = platform.businessServer.appliedMutations;
      expect(
        await editor.saveGlobal(values, editor.snapshot!.globalRevision),
        false,
      );
      final originalBody = posts().single.body;
      editor.dispose();
      await show(tester);
      await loadCurrent(tester);
      expect(find.text('设置尚未确认，本会话保留原操作。'), findsOneWidget);
      expect(find.textContaining('应用主题：深色'), findsOneWidget);
      expect(find.textContaining('应用内调暗：17%'), findsOneWidget);
      expect(tester.widget<IconButton>(toggle()).onPressed, isNull);
      expect(posts(), hasLength(1));
      await tap(tester, find.text('重新读取设置'));
      expect(posts(), hasLength(1));
      expect(repository.pendingGlobal(), isNotNull);
      await hide(tester);
      await show(tester);
      expect(find.text('未确认的原全局设置内容'), findsOneWidget);
      await tap(tester, find.text('重试原设置操作'));
      expect(posts(), hasLength(2));
      expect(posts().last.body, originalBody);
      expect(platform.businessServer.appliedMutations, appliedBefore + 1);
      expect(repository.pendingGlobal(), isNull);
      expect((await remoteSettings.loadGlobal()).global, values);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'a remote conflict requires a read before another favorite edit and identity replacement drops late reads',
    (tester) async {
      await show(tester);
      await loadCurrent(tester);
      await seed(_values(favorites: [_favorite(package: 'remote.extension')]));
      await tap(tester, toggle());
      expect(posts(), hasLength(2));
      expect(catalog.settings!.pendingGlobal()!.retryable, false);
      expect(tester.widget<IconButton>(toggle()).onPressed, isNull);
      expect(find.text('设置已在其他设备修改，请重新读取后确认。'), findsOneWidget);
      await tap(tester, find.text('重新读取设置'));
      expect(posts(), hasLength(2));
      expect(catalog.settings!.pendingGlobal(), isNull);
      expect(open('remote.extension'), findsOneWidget);
      final entered = Completer<void>();
      final release = gate();
      var hold = true;
      platform.beforeApiFetch = (path) async {
        if (hold && path == '/api/settings') {
          hold = false;
          entered.complete();
          await release.future;
        }
      };
      await reveal(tester, find.text('重新读取设置'));
      await tester.tap(find.text('重新读取设置'));
      await tester.pump();
      await tester.runAsync(
        () => entered.future.timeout(const Duration(seconds: 5)),
      );
      platform.bootstrapSubject = 'another-owner';
      await tester.runAsync(catalog.connect);
      release.complete();
      await tester.runAsync(
        () =>
            catalog.settings!.loadGlobal().timeout(const Duration(seconds: 5)),
      );
      await tester.pumpAndSettle();
      expect(catalog.subject, 'another-owner');
      expect(open('remote.extension'), findsNothing);
      expect(posts(), hasLength(2));
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'leaving the browse route during favorite opening discards the late listing',
    (tester) async {
      await seed(_values(favorites: [_favorite()]));
      final entered = Completer<void>();
      final release = gate();
      platform.invokeHandler = (call) async {
        expect(call.hasPopular(), true);
        entered.complete();
        await release.future;
        return wire.SourceResult(
          mangaPage: wire.MangaPage(mangas: [testManga]),
        );
      };
      await show(tester);
      await reveal(tester, open('eu.kanade.source.test'));
      await tester.tap(open('eu.kanade.source.test'));
      await tester.pump();
      await tester.runAsync(
        () => entered.future.timeout(const Duration(seconds: 5)),
      );
      expect(catalog.busy, true);
      expect(
        tester.widget<IconButton>(open('eu.kanade.source.test')).onPressed,
        isNull,
      );
      unawaited(
        Navigator.of(tester.element(find.byType(CatalogPage))).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('另一个页面')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      release.complete();
      await tester.pumpAndSettle();
      expect(find.text('另一个页面'), findsOneWidget);
      expect(catalog.mangas, isEmpty);
      expect(catalog.busy, false);
      expect(posts(), hasLength(1));
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );
}
