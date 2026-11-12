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
  installedExtensions: [testInstalledExtension()],
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
          of: find.byType(ListView).first,
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
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final command = wire.decodeProtoJson(
        wire.SettingsMutation(),
        jsonDecode(posts().last.body!),
      );
      expect(command.setGlobal.reader, original.reader);
      expect(command.setGlobal.theme, original.theme);
      release.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(toggle()).icon,
        isA<Icon>().having((icon) => icon.icon, 'saved star', Icons.star),
      );
      expect(platform.openedBuilds, isEmpty);
      await tap(tester, toggle());
      final confirmed = await remoteSettings.loadGlobal();
      expect(confirmed.global.favoriteSources, isEmpty);
      expect(confirmed.global.reader, original.reader);
      expect(confirmed.global.theme, original.theme);
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
      expect(tester.widget<IconButton>(toggle()).onPressed, isNull);
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
      expect(tester.widget<IconButton>(toggle()).onPressed, isNotNull);
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
      await tester.pageBack();
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
      final applied = platform.businessServer.appliedMutations;
      expect(
        await editor.saveGlobal(values, editor.snapshot!.globalRevision),
        false,
      );
      final originalBody = posts().single.body;
      editor.dispose();
      await show(tester);
      expect(find.text('设置尚未确认，本会话保留原操作。'), findsOneWidget);
      expect(find.textContaining('应用主题：深色'), findsOneWidget);
      expect(tester.widget<IconButton>(toggle()).onPressed, isNull);
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

  testWidgets(
    'conflicts require a fresh read and changed identity discards old favorites',
    (tester) async {
      await show(tester);
      await seed(_values(favorites: [_favorite(package: 'remote.extension')]));
      await tap(tester, toggle());
      expect(catalog.settings!.pendingGlobal()!.retryable, false);
      expect(tester.widget<IconButton>(toggle()).onPressed, isNull);
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
}
