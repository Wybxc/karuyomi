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
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/features/reader/reading_progress_controller.dart';
import 'package:reader_core/reader_core.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/extensions/extensions_controller.dart';
import 'package:karuyomi/features/extensions/extensions_page.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';

void main() {
  late TestPlatform platform;
  late CatalogController catalog;
  late ExtensionsController manager;
  late ProviderContainer container;
  bool current = true;
  setUp(() async {
    container = ProviderContainer();
    current = true;
    platform = TestPlatform(seedDefaultInstallation: false);
    catalog = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    manager = ExtensionsController(
      container: container,
      catalog: catalog,
      repository: catalog.settings!,
      isCurrent: () => current,
    );
    await manager.refresh();
  });
  tearDown(() async {
    manager.dispose();
    container.dispose();
    catalog.dispose();
    await catalog.closeReadingProgress();
    await platform.dispose();
  });

  test('preparation installs only after confirmation, preserves global values, and does not execute a Source', () async {
    final before = manager.settings.snapshot!;
    await manager.install(catalog.builds.single);
    expect(platform.preparations, hasLength(1));
    expect(platform.openedBuilds, isEmpty);
    expect(platform.invocations, isEmpty);
    expect(manager.installed.single, testInstalledExtension());
    expect(manager.settings.snapshot!.global.reader, before.global.reader);
    expect(manager.settings.snapshot!.global.theme, before.global.theme);
    expect(manager.cache!.artifacts.single.sha256, 'a' * 64);
    final remote = SettingsRepository(
      BusinessStateClient(
        api: platform.businessServer,
        identity: catalog.settings!.identity,
      ),
    );
    expect(
      (await remote.loadGlobal()).global.installedExtensions.single,
      testInstalledExtension(),
    );
    await remote.client.dispose();
    await catalog.openBuild(catalog.builds.single);
    expect(platform.openedBuilds, ['build-1']);
    await manager.setEnabled(manager.installed.single, false);
    expect(manager.installed.single.enabled, false);
    expect(platform.buildClosures, hasLength(1));
    expect(catalog.session, isNull);
    await catalog.openBuild(catalog.builds.single);
    expect(catalog.error, contains('已停用'));
    expect(platform.openedBuilds, hasLength(1));
    await manager.uninstall(manager.installed.single);
    expect(manager.installed, isEmpty);
    expect(manager.cache!.artifacts, isEmpty);
  });

  test('lost ACK is shared across pages and retries the exact original global request', () async {
    platform.businessServer.loseNextResponse = true;
    await manager.install(catalog.builds.single);
    final pending = manager.repository.pendingGlobal()!;
    expect(manager.installed, isEmpty);
    expect(pending.global!.installedExtensions.single.buildId, 'build-1');
    final first = platform.businessServer.requests.singleWhere(
      (request) => request.method == 'POST',
    );
    final second = ExtensionsController(
      container: container,
      catalog: catalog,
      repository: catalog.settings!,
      isCurrent: () => true,
    );
    addTearDown(second.dispose);
    await second.refresh();
    expect(second.settings.pending!.basedOnRevision, pending.basedOnRevision);
    expect(second.canEdit, false);
    await second.install(catalog.builds.single);
    expect(platform.preparations, hasLength(1));
    expect(second.settings.canRetry, true);
    await second.retry();
    final posts = platform.businessServer.requests
        .where((request) => request.method == 'POST')
        .toList();
    expect(posts, hasLength(2));
    expect(posts.last.body, first.body);
    expect(platform.businessServer.appliedMutations, 1);
    expect(second.installed.single.buildId, 'build-1');
    expect(second.settings.pending, isNull);
  });

  test('candidate retains original CAS through concurrent remote settings and late identity retirement', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    platform.beforePrepare = (_) async {
      entered.complete();
      await release.future;
    };
    final install = manager.install(catalog.builds.single);
    await entered.future.timeout(const Duration(seconds: 5));
    final remoteClient = BusinessStateClient(
      api: platform.businessServer,
      identity: catalog.settings!.identity,
    );
    addTearDown(remoteClient.dispose);
    final remote = SettingsRepository(remoteClient);
    final snapshot = await remote.loadGlobal();
    final values = snapshot.global.deepCopy()
      ..theme = wire.AppTheme.APP_THEME_DARK;
    await remote.setGlobal(
      values: values,
      basedOnRevision: snapshot.globalRevision,
    );
    release.complete();
    await install;
    expect(manager.settings.pending!.retryable, false);
    expect(manager.settings.pending!.basedOnRevision, 0);
    expect(manager.settings.snapshot!.global.installedExtensions, isEmpty);
    await manager.refresh();
    expect(manager.settings.pending, isNull);
    expect(
      manager.settings.snapshot!.global.theme,
      wire.AppTheme.APP_THEME_DARK,
    );
    final posts = platform.businessServer.requests
        .where((request) => request.method == 'POST')
        .toList();
    expect(jsonDecode(posts.last.body!)['expectedRevision'] ?? 0, 0);
    expect(manager.cache!.artifacts, hasLength(1));
    current = false;
    await manager.install(catalog.builds.single);
    expect(platform.preparations, hasLength(1));
  });

  test('adopting a dirty progress client rebinds confirmed installation updates without resending progress', () async {
    final retained = BusinessStateClient(
      api: platform.businessServer,
      identity: catalog.settings!.identity,
    );
    final progress = ReadingProgressController(
      repository: ProgressRepository(retained),
      mangaKey: 'b' * 64,
    );
    final manifest = ChapterManifest(
      chapterKey: 'chapter',
      version: 'v1',
      pages: [ReaderPage(key: 'page')],
    );
    await progress.restore(manifest);
    platform.businessServer.failWrites = true;
    progress.observe(
      manifest: manifest,
      current: manifest.positionAt(0),
      reversedOrder: false,
    );
    expect(await progress.flush(), false);
    expect(progress.unsaved, true);
    platform.businessServer.failWrites = false;
    expect(catalog.adoptReadingProgress(progress), true);
    manager.dispose();
    manager = ExtensionsController(
      container: container,
      catalog: catalog,
      repository: catalog.settings!,
      isCurrent: () => current,
    );
    await manager.refresh();
    await manager.install(catalog.builds.single);
    await catalog.openBuild(catalog.builds.single);
    expect(catalog.session, isNotNull);
    final before = platform.businessServer.requests
        .where(
          (request) =>
              request.uri.path == '/api/progress/mutations' &&
              request.method == 'POST',
        )
        .length;
    await manager.setEnabled(manager.installed.single, false);
    expect(catalog.installedExtensions.single.enabled, false);
    expect(catalog.session, isNull);
    expect(platform.buildClosures, hasLength(1));
    expect(progress.unsaved, true);
    expect(
      platform.businessServer.requests
          .where(
            (request) =>
                request.uri.path == '/api/progress/mutations' &&
                request.method == 'POST',
          )
          .length,
      before,
    );
  });

  test('checking updates keeps the confirmed selection and failed preparation never replaces it', () async {
    await manager.install(catalog.builds.single);
    await manager.setEnabled(manager.installed.single, false);
    final index = wire.decodeProtoJson(
      wire.ExtensionIndex(),
      platform.inventory,
    );
    index.builds.single
      ..buildId = 'build-2'
      ..manifestPath = '/extensions/builds/build-2/manifest.json'
      ..version = '2';
    platform.inventory = wire.encodeProtoJson(index);
    final posts = platform.businessServer.requests
        .where((request) => request.method == 'POST')
        .length;
    await manager.refresh(catalogToo: true);
    expect(manager.installed.single.buildId, 'build-1');
    expect(
      platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length,
      posts,
    );
    platform.preparationFailure = wire.RuntimeError(
      code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_INTEGRITY_ERROR,
      message: 'Bad candidate',
    );
    await manager.install(catalog.builds.single);
    expect(manager.installed.single.buildId, 'build-1');
    expect(
      platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length,
      posts,
    );
    platform.preparationFailure = null;
    await manager.install(catalog.builds.single);
    expect(manager.installed.single.buildId, 'build-2');
    expect(manager.installed.single.enabled, false);
    expect(platform.openedBuilds, isEmpty);
  });

  test('explicit cancellation discards a late preparation without changing account settings', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    platform.beforePrepare = (_) async {
      entered.complete();
      await release.future;
    };
    final installation = manager.install(catalog.builds.single);
    await entered.future.timeout(const Duration(seconds: 5));
    await manager.cancelPreparation();
    release.complete();
    await installation;
    expect(manager.installed, isEmpty);
    expect(manager.error, isNull);
    expect(manager.message, contains('已取消'));
    expect(
      platform.businessServer.requests.where(
        (request) => request.method == 'POST',
      ),
      isEmpty,
    );
  });

  test('explicit rebuild recovers confirmed unavailable runtime cleanup without claiming a close ACK', () async {
    await manager.install(catalog.builds.single);
    await catalog.openBuild(catalog.builds.single);
    platform.closeAcknowledged = false;
    await manager.setEnabled(manager.installed.single, false);
    expect(catalog.extensionCleanupError, isNotNull);
    expect(catalog.session, isNotNull);
    final posts = platform.businessServer.requests
        .where((request) => request.method == 'POST')
        .length;
    await manager.rebuildForCleanup();
    expect(platform.rebuildCount, 1);
    expect(catalog.session, isNull);
    expect(catalog.extensionCleanupError, isNull);
    expect(manager.message, contains('已重建'));
    await manager.forget('a' * 64);
    expect(platform.cachedArtifacts, isEmpty);
    expect(
      platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length,
      posts,
    );
  });

  for (final enabled in [null, false]) {
    for (final path in ['direct', 'favorite', 'library', 'recovery']) {
      test(
        '$path opening rejects ${enabled == null ? 'uninstalled' : 'disabled'} account intent before Source execution',
        () async {
          if (enabled != null) {
            final values = manager.settings.snapshot!.global.deepCopy();
            values.installedExtensions.add(
              testInstalledExtension(enabled: enabled),
            );
            await container
                .read(
                  settingsControllerProvider(
                    catalog,
                    catalog.settings,
                  ).notifier,
                )
                .saveGlobal(values, manager.settings.snapshot!.globalRevision);
          }
          final build = catalog.builds.single;
          switch (path) {
            case 'direct':
              await catalog.openBuild(build);
            case 'favorite':
              expect(
                await catalog.openFavoriteSource(
                  wire.FavoriteSource(
                    packageName: build.packageName,
                    sourceId: sourceId,
                    sourceName: 'Test Source',
                    sourceLang: 'zh',
                  ),
                  identityKey: catalog.settings!.identity.key,
                ),
                false,
              );
            case 'library':
              final library = catalog.library!;
              await library.setFavorite(
                packageName: build.packageName,
                sourceId: sourceId,
                sourceName: 'Test Source',
                sourceLang: 'zh',
                manga: testManga,
                favorite: true,
              );
              final entry = (await library.watchEntries().first).single;
              expect(
                await catalog.openLibraryEntry(
                  entry,
                  identityKey: library.identity.key,
                ),
                isNull,
              );
            case 'recovery':
              expect(
                await catalog.reopenSourcePreferences(
                  SourcePreferencesTarget(
                    build: build,
                    source: wire.SourceInfo(
                      id: sourceId,
                      name: 'Test Source',
                      lang: 'zh',
                    ),
                  ),
                ),
                false,
              );
          }
          expect(catalog.error, contains(enabled == null ? '尚未安装' : '已停用'));
          expect(platform.openedBuilds, isEmpty);
          expect(platform.invocations, isEmpty);
        },
      );
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    final scrollable = find.byType(Scrollable).first;
    if (finder.evaluate().isEmpty) {
      await tester.drag(scrollable, const Offset(0, 4000));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(finder, 250, scrollable: scrollable);
    }
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> show(
    WidgetTester tester, {
    Brightness? appearance,
    Size size = const Size(600, 1100),
    PageStorageBucket? pageStorage,
    double textScale = 1,
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
        home: PageStorage(
          bucket: pageStorage ?? PageStorageBucket(),
          child: ExtensionsPage(
            catalog: catalog,
            repository: catalog.settings!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final appearance in Brightness.values) {
    testWidgets(
      'confirmed extension read recovery survives reentry and only reads in $appearance',
      (tester) async {
        var failReads = true;
        platform.afterBusinessReply = (request, reply) {
          if (failReads &&
              request.method == 'GET' &&
              request.uri.path == '/api/settings') {
            throw StateError('Latest account settings unavailable');
          }
          return reply;
        };
        await manager.install(catalog.builds.single);
        final writes = platform.businessServer.requests
            .where((request) => request.method == 'POST')
            .length;
        final applied = platform.businessServer.appliedMutations;
        await show(tester, appearance: appearance, size: const Size(360, 800));
        expect(find.textContaining('安装扩展：'), findsOneWidget);
        expect(find.text('重试读取最新设置'), findsOneWidget);
        expect(find.text('重试原设置操作'), findsNothing);
        expect(find.textContaining('结果待确认'), findsNothing);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await show(tester, appearance: appearance, size: const Size(360, 800));
        expect(find.text('重试读取最新设置'), findsOneWidget);
        expect(find.textContaining('安装扩展：'), findsOneWidget);
        await tap(tester, find.text('查看已确认的原操作'));
        expect(find.textContaining('未确认'), findsNothing);
        await tap(tester, find.text('查看已确认的原操作'));
        failReads = false;
        await tap(tester, find.text('重试读取最新设置'));
        expect(
          platform.businessServer.requests.where(
            (request) => request.method == 'POST',
          ),
          hasLength(writes),
        );
        expect(platform.businessServer.appliedMutations, applied);
        expect(find.text('重试读取最新设置'), findsNothing);
        expect(find.textContaining('安装扩展：'), findsNothing);
        expect(
          find.byKey(
            const ValueKey(('extension-installed', 'eu.kanade.source.test')),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'original account retry shows saving until its real reply arrives in $appearance',
      (tester) async {
        platform.businessServer.loseNextResponse = true;
        await manager.install(catalog.builds.single);
        final original = platform.businessServer.requests
            .where((request) => request.method == 'POST')
            .single
            .body;
        final applied = platform.businessServer.appliedMutations;
        await show(tester, appearance: appearance, size: const Size(360, 800));
        final entered = Completer<void>();
        final release = Completer<void>();
        platform.afterBusinessReply = (request, reply) async {
          if (request.method == 'POST' &&
              request.uri.path == '/api/settings/mutations') {
            entered.complete();
            await release.future;
          }
          return reply;
        };
        try {
          final retry = find.text('重试原设置操作');
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await tester.pump();
          expect(entered.isCompleted, true);
          expect(find.text('正在保存账户选择，等待确认'), findsOneWidget);
          expect(find.textContaining('安装扩展：'), findsOneWidget);
          expect(find.textContaining('结果待确认'), findsNothing);
          expect(
            tester
                .widget<CupertinoButton>(
                  find.byKey(const ValueKey('extensions-retry-settings')),
                )
                .onPressed,
            isNull,
          );
        } finally {
          release.complete();
          await tester.pumpAndSettle();
          platform.afterBusinessReply = null;
        }
        final writes = platform.businessServer.requests
            .where((request) => request.method == 'POST')
            .toList();
        expect(writes, hasLength(2));
        expect(writes.last.body, original);
        expect(platform.businessServer.appliedMutations, applied);
        expect(find.text('正在保存账户选择，等待确认'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'frozen account operation identifies the removed extension after refresh and reentry in $appearance at $textScale',
        (tester) async {
          await manager.install(catalog.builds.single);
          platform.businessServer.loseNextResponse = true;
          await manager.uninstall(manager.installed.single);
          final writes = platform.businessServer.requests
              .where((request) => request.method == 'POST')
              .toList();
          final original = writes.last.body;
          final applied = platform.businessServer.appliedMutations;
          await show(
            tester,
            appearance: appearance,
            size: const Size(360, 800),
            textScale: textScale,
          );
          expect(find.textContaining('卸载扩展：'), findsOneWidget);
          expect(find.textContaining('eu.kanade.source.test'), findsWidgets);
          await manager.refresh(catalogToo: true);
          await tester.pumpAndSettle();
          expect(manager.installed, isEmpty);
          expect(find.textContaining('卸载扩展：'), findsOneWidget);
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await show(
            tester,
            appearance: appearance,
            size: const Size(360, 800),
            textScale: textScale,
          );
          expect(find.textContaining('卸载扩展：'), findsOneWidget);
          expect(
            platform.businessServer.requests.where(
              (request) => request.method == 'POST',
            ),
            hasLength(writes.length),
          );
          await tap(tester, find.text('查看未确认的原操作'));
          expect(find.textContaining('扩展安装选择：空列表'), findsOneWidget);
          await tap(tester, find.text('重试原设置操作'));
          final retried = platform.businessServer.requests
              .where((request) => request.method == 'POST')
              .toList();
          expect(retried, hasLength(writes.length + 1));
          expect(retried.last.body, original);
          expect(platform.businessServer.appliedMutations, applied);
          expect(find.textContaining('卸载扩展：'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }

    for (final expanded in [false, true]) {
      testWidgets(
        'extension recovery keeps scroll storage separate in $appearance when expanded=$expanded',
        (tester) async {
          final bucket = PageStorageBucket();
          platform.businessServer.loseNextResponse = true;
          await manager.install(catalog.builds.single);
          final original = platform.businessServer.requests
              .where((request) => request.method == 'POST')
              .single
              .body;
          final applied = platform.businessServer.appliedMutations;
          await show(tester, appearance: appearance, pageStorage: bucket);
          await tap(tester, find.text('查看未确认的原操作'));
          if (!expanded) {
            await tap(tester, find.text('查看未确认的原操作'));
          }
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await show(tester, appearance: appearance, pageStorage: bucket);
          expect(tester.takeException(), isNull);
          expect(find.text('查看未确认的原操作'), findsOneWidget);
          expect(
            find.text('原全局设置内容'),
            expanded ? findsOneWidget : findsNothing,
          );
          expect(
            platform.businessServer.requests.where(
              (request) => request.method == 'POST',
            ),
            hasLength(1),
          );
          await tap(tester, find.text('重试原设置操作'));
          final writes = platform.businessServer.requests
              .where((request) => request.method == 'POST')
              .toList();
          expect(writes, hasLength(2));
          expect(writes.last.body, original);
          expect(platform.businessServer.appliedMutations, applied);
          expect(platform.preparations, hasLength(1));
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await show(
            tester,
            appearance: appearance == Brightness.light
                ? Brightness.dark
                : Brightness.light,
            pageStorage: bucket,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('查看未确认的原操作'), findsNothing);
          expect(
            platform.businessServer.requests.where(
              (request) => request.method == 'POST',
            ),
            hasLength(2),
          );
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }

    testWidgets(
      'extension menu immediately activates its first keyboard item in $appearance',
      (tester) async {
        await show(tester, appearance: appearance, size: const Size(360, 800));
        final anchor = find.byKey(const ValueKey('extensions-more'));
        final button = find
            .descendant(of: anchor, matching: find.byType(CupertinoButton))
            .first;
        for (var attempt = 0; attempt < 12; attempt++) {
          final focused = FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<CupertinoButton>();
          if (focused == tester.widget<CupertinoButton>(button)) break;
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<CupertinoMenuItem>()
              ?.child,
          isA<Text>().having((text) => text.data, 'focused menu item', '仓库管理'),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(ExtensionRepositoriesPage), findsOneWidget);
        final footer = tester.element(find.text('仓库提供可安装的扩展目录；添加仓库不会自动安装扩展。'));
        final footerStyle = DefaultTextStyle.of(footer).style;
        expect(footerStyle.fontSize, 13);
        expect(footerStyle.color, AppColors.secondaryLabel.resolveFrom(footer));
        expect(
          platform.businessServer.requests.where(
            (request) => request.method == 'POST',
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'storage exposes keyboard diagnostics and clears only the local copy at $appearance / $scale',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await tester.binding.setSurfaceSize(const Size(360, 800));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await manager.install(catalog.builds.single);
            final confirmed = await manager.repository.loadGlobal();
            final writes = platform.businessServer.requests
                .where((request) => request.method == 'POST')
                .length;
            await tester.pumpApp(
              CupertinoApp(
                theme: readerAppTheme(appearance),
                home: ExtensionStoragePage(controller: manager),
              ),
            );
            await tester.pumpAndSettle();
            final note = tester.element(
              find.text('清理副本后仍是账户已安装状态，重新打开时会再次下载。书架与阅读记录保留。'),
            );
            final noteStyle = DefaultTextStyle.of(note).style;
            expect(noteStyle.fontSize, 13);
            expect(noteStyle.color, AppColors.secondaryLabel.resolveFrom(note));
            final clear = find.byKey(ValueKey(('extension-forget', 'a' * 64)));
            expect(
              tester.getSemantics(clear).label,
              '清理副本：${testCatalogSource.name}',
            );
            final diagnostics = find.widgetWithText(CupertinoButton, '诊断信息');
            CupertinoButton? focusedButton() => FocusManager
                .instance
                .primaryFocus
                ?.context
                ?.findAncestorWidgetOfExactType<CupertinoButton>();
            for (
              var attempt = 0;
              attempt < 12 &&
                  focusedButton() !=
                      tester.widget<CupertinoButton>(diagnostics);
              attempt++
            ) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pump();
            }
            expect(
              focusedButton(),
              tester.widget<CupertinoButton>(diagnostics),
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(find.textContaining('a' * 64), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
            await tester.pump();
            expect(focusedButton(), tester.widget<CupertinoButton>(clear));
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pumpAndSettle();
            expect(find.text('本机没有扩展副本'), findsOneWidget);
            expect(platform.cachedArtifacts, isEmpty);
            expect(manager.installed.single, testInstalledExtension());
            final after = await manager.repository.loadGlobal();
            expect(after.global, confirmed.global);
            expect(after.globalRevision, confirmed.globalRevision);
            expect(
              platform.businessServer.requests.where(
                (request) => request.method == 'POST',
              ),
              hasLength(writes),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpApp(const SizedBox.shrink());
            await tester.pumpAndSettle();
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      'installed source and diagnostic actions have independent keyboard access in $appearance',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await manager.install(catalog.builds.single);
          final writes = platform.businessServer.requests
              .where((request) => request.method == 'POST')
              .length;
          final opened = <wire.CatalogSource>[];
          await tester.binding.setSurfaceSize(const Size(360, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpApp(
            CupertinoApp(
              theme: readerAppTheme(appearance),
              home: ExtensionDetailsPage(
                controller: manager,
                packageName: 'eu.kanade.source.test',
                onOpenSource: (extension, source) async {
                  expect(
                    extension.installed!.packageName,
                    'eu.kanade.source.test',
                  );
                  opened.add(source);
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.getSemantics(find.text('卸载扩展')).label, '卸载扩展');
          final sourceKey = ValueKey((
            'extension-source',
            testCatalogSource.id,
          ));
          Key? focusedButton() => FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<CupertinoButton>()
              ?.key;
          for (
            var attempt = 0;
            attempt < 12 && focusedButton() != sourceKey;
            attempt++
          ) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          expect(focusedButton(), sourceKey);
          expect(
            tester.getSemantics(find.byKey(sourceKey)).label,
            isNot(contains('包含的漫画源')),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(opened.single.id, testCatalogSource.id);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(
            FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<CupertinoButton>(),
            tester.widget<CupertinoButton>(
              find.widgetWithText(CupertinoButton, '诊断信息'),
            ),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(
            find.textContaining('包名：eu.kanade.source.test'),
            findsOneWidget,
          );
          expect(platform.invocations, isEmpty);
          expect(
            platform.businessServer.requests.where(
              (request) => request.method == 'POST',
            ),
            hasLength(writes),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'extension search stays readable and clearable in $appearance',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            appearance == Brightness.light ? Brightness.dark : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await show(tester, appearance: appearance);
        final search = find.byKey(const ValueKey('extensions-search'));
        final context = tester.element(search);
        final placeholder = tester.widget<Text>(find.text('查找扩展或漫画源名称'));
        final field = tester.widget<CupertinoTextField>(search);
        final foreground = placeholder.style!.color!;
        final background = field.decoration!.color!;
        expect(foreground, AppColors.secondaryLabel.resolveFrom(context));
        final a = foreground.computeLuminance();
        final b = background.computeLuminance();
        expect(
          a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05),
          greaterThanOrEqualTo(4.5),
        );
        await tester.enterText(search, '__missing__');
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的扩展，请清除筛选。'), findsOneWidget);
        await tester.tap(find.byIcon(CupertinoIcons.clear_thick_circled));
        await tester.pumpAndSettle();
        expect(find.text('查找扩展或漫画源名称'), findsOneWidget);
        expect(find.text('没有匹配的扩展，请清除筛选。'), findsNothing);
        expect(
          platform.businessServer.requests.where((r) => r.method == 'POST'),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final appearance in Brightness.values) {
    testWidgets(
      'many languages keep the extension version and status visible in $appearance',
      (tester) async {
        final index = wire.decodeProtoJson(
          wire.ExtensionIndex(),
          platform.inventory,
        );
        final build = index.builds.single;
        build.sources
          ..clear()
          ..addAll(
            List.generate(
              61,
              (index) => wire.CatalogSource(
                id: '${1000 + index}',
                name: 'Test Source',
                lang: 'lang$index',
              ),
            ),
          );
        build.sourceIds
          ..clear()
          ..addAll(build.sources.map((source) => source.id));
        platform.inventory = wire.encodeProtoJson(index);
        await show(tester, appearance: appearance, size: const Size(360, 800));
        final row = find.byKey(
          ValueKey((
            'extension-available',
            catalog.catalogUrl,
            build.packageName,
          )),
        );
        final expected = '${build.version} · 61 种语言 · 可安装';
        expect(
          (tester.widget<CupertinoListTile>(row).subtitle! as Text).data,
          expected,
        );
        await tester.tap(
          find.byKey(
            ValueKey((
              'extension-details',
              catalog.catalogUrl,
              build.packageName,
            )),
          ),
        );
        await tester.pumpAndSettle();
        final status = find.ancestor(
          of: find.text('扩展状态'),
          matching: find.byType(CupertinoListTile),
        );
        expect(
          (tester.widget<CupertinoListTile>(status).subtitle! as Text).data,
          expected,
        );
        expect(find.text('lang60'), findsOneWidget);
        expect(
          platform.businessServer.requests.where(
            (request) => request.method == 'POST',
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'extension details are reachable by Tab and Enter in $appearance',
      (tester) async {
        await show(tester, appearance: appearance, size: const Size(360, 800));
        final key = ValueKey((
          'extension-details',
          catalog.catalogUrl,
          'eu.kanade.source.test',
        ));
        Key? focusedButton() => FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<CupertinoButton>()
            ?.key;
        for (
          var attempt = 0;
          attempt < 16 && focusedButton() != key;
          attempt++
        ) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(focusedButton(), key);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(ExtensionDetailsPage), findsOneWidget);
        expect(
          platform.businessServer.requests.where(
            (request) => request.method == 'POST',
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'compact extension accessories install without opening details at $appearance / $scale',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await show(
            tester,
            appearance: appearance,
            size: const Size(360, 800),
          );
          await tap(
            tester,
            find.byKey(
              ValueKey((
                'extension-install',
                catalog.catalogUrl,
                'eu.kanade.source.test',
              )),
            ),
          );
          expect(
            catalog.installedExtensions.single.packageName,
            'eu.kanade.source.test',
          );
          expect(find.byType(ExtensionDetailsPage), findsNothing);
          final writes = platform.businessServer.requests
              .where((request) => request.method == 'POST')
              .length;
          expect(writes, 1);
          await tap(
            tester,
            find.byKey(
              const ValueKey(('extension-installed', 'eu.kanade.source.test')),
            ),
          );
          expect(find.byType(ExtensionDetailsPage), findsOneWidget);
          expect(
            platform.businessServer.requests.where(
              (request) => request.method == 'POST',
            ),
            hasLength(writes),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets(
    'management page installs, shows confirmed disable and independently retries cleanup before uninstall',
    (tester) async {
      await show(tester);
      expect(find.text('账户尚未安装扩展。'), findsOneWidget);
      await tap(
        tester,
        find.byKey(
          ValueKey((
            'extension-install',
            catalog.catalogUrl,
            'eu.kanade.source.test',
          )),
        ),
      );
      expect(
        find.byKey(
          const ValueKey(('extension-installed', 'eu.kanade.source.test')),
        ),
        findsOneWidget,
      );
      await tap(
        tester,
        find.byKey(
          const ValueKey(('extension-installed', 'eu.kanade.source.test')),
        ),
      );
      expect(find.textContaining('本机就绪'), findsOneWidget);
      await tester.runAsync(() => catalog.openBuild(catalog.builds.single));
      await tester.pumpAndSettle();
      platform.closeAcknowledged = false;
      await tap(
        tester,
        find.byKey(
          const ValueKey(('extension-enabled', 'eu.kanade.source.test')),
        ),
      );
      expect(catalog.installedExtensions.single.enabled, false);
      expect(find.text('重试资源清理'), findsOneWidget);
      expect(catalog.session, isNotNull);
      platform.closeAcknowledged = true;
      await tap(tester, find.text('重试资源清理'));
      expect(catalog.session, isNull);
      expect(find.text('重试资源清理'), findsNothing);
      await tap(
        tester,
        find.byKey(
          const ValueKey(('extension-uninstall', 'eu.kanade.source.test')),
        ),
      );
      expect(find.text('账户已卸载此扩展，请返回扩展列表。'), findsOneWidget);
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pumpAndSettle();
      expect(find.text('账户尚未安装扩展。'), findsOneWidget);
      expect(platform.cachedArtifacts, isEmpty);
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'installed source name search keeps management actions without account writes',
    (tester) async {
      await manager.install(catalog.builds.single);
      final posts = platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length;
      await show(tester);
      final search = find.byKey(const ValueKey('extensions-search'));
      await tester.enterText(search, testCatalogSource.name);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey(('extension-installed', 'eu.kanade.source.test')),
        ),
        findsOneWidget,
      );
      await tap(
        tester,
        find.byKey(
          const ValueKey(('extension-installed', 'eu.kanade.source.test')),
        ),
      );
      expect(
        find.byKey(
          const ValueKey(('extension-enabled', 'eu.kanade.source.test')),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey(('extension-uninstall', 'eu.kanade.source.test')),
        ),
        findsOneWidget,
      );
      expect(
        platform.businessServer.requests
            .where((request) => request.method == 'POST')
            .length,
        posts,
      );
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'missing catalog metadata still allows installed package name search',
    (tester) async {
      await manager.install(catalog.builds.single);
      platform.inventory = wire.encodeProtoJson(
        wire.ExtensionIndex(schemaVersion: 1, repoId: 'keiyoushi'),
      );
      final posts = platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length;
      await show(tester);
      expect(catalog.builds, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('extensions-search')),
        'eu.kanade.source.test',
      );
      await tester.pumpAndSettle();
      await tap(
        tester,
        find.byKey(
          const ValueKey(('extension-installed', 'eu.kanade.source.test')),
        ),
      );
      expect(
        find.byKey(
          const ValueKey(('extension-uninstall', 'eu.kanade.source.test')),
        ),
        findsOneWidget,
      );
      expect(
        platform.businessServer.requests
            .where((request) => request.method == 'POST')
            .length,
        posts,
      );
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'unknown global pending disables new edits and refreshing the page never posts the draft',
    (tester) async {
      platform.businessServer.loseNextResponse = true;
      await manager.install(catalog.builds.single);
      final posts = platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length;
      await show(tester);
      expect(find.textContaining('结果待确认'), findsOneWidget);
      expect(find.textContaining('安装扩展：'), findsOneWidget);
      await tap(tester, find.text('查看未确认的原操作'));
      expect(find.text('原全局设置内容'), findsOneWidget);
      expect(
        find.textContaining('扩展安装选择：eu.kanade.source.test'),
        findsOneWidget,
      );
      expect(find.textContaining('build-1'), findsOneWidget);
      expect(find.textContaining('a' * 64), findsOneWidget);
      expect(find.text('重试原设置操作'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(
        tester,
        find.byKey(
          const ValueKey(('extension-installed', 'eu.kanade.source.test')),
        ),
      );
      final enabled = find.byKey(
        const ValueKey(('extension-enabled', 'eu.kanade.source.test')),
      );
      await tester.ensureVisible(enabled);
      expect(tester.widget<CupertinoSwitch>(enabled).onChanged, isNull);
      await tap(tester, find.byKey(const ValueKey('extensions-refresh')));
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('extensions-check-updates')));
      expect(
        platform.businessServer.requests
            .where((request) => request.method == 'POST')
            .length,
        posts,
      );
      expect(platform.preparations, hasLength(1));
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  test('canonical install boundaries reject duplicate packages and normalized URL aliases', () {
    for (final url in [
      'https://reader.example.com/extensions/index.json',
      'http://127.0.0.1:8787/extensions/index.json',
      'http://localhost:8787/extensions/index.json',
      'http://[::1]:8787/extensions/index.json',
    ]) {
      expect(
        () => validateBusinessInstalledExtension(
          testInstalledExtension(catalogUrl: url),
        ),
        returnsNormally,
      );
    }
    for (final url in [
      'https://reader.example.com:443/extensions/index.json',
      'https://Reader.example.com/extensions/index.json',
      'http://127.1/extensions/index.json',
      'https://reader.example.com/extensions/index.json?',
      'https://reader.example.com/extensions/%69ndex.json',
      'http://example.com/extensions/index.json',
    ]) {
      expect(
        () => validateBusinessInstalledExtension(
          testInstalledExtension(catalogUrl: url),
        ),
        throwsFormatException,
        reason: url,
      );
    }
    expect(
      () => validateBusinessInstalledExtensions([
        testInstalledExtension(),
        testInstalledExtension(buildId: 'other'),
      ]),
      throwsFormatException,
    );
    expect(
      () => validateBusinessInstalledExtension(
        testInstalledExtension(sha256: 'A' * 64),
      ),
      throwsFormatException,
    );
    expect(
      () => validateBusinessInstalledExtensions([
        for (var index = 0; index < 129; index++)
          testInstalledExtension(packageName: 'package.$index'),
      ]),
      throwsFormatException,
    );
  });
}
