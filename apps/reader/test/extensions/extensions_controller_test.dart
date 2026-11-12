import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../test_app.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test(
    'preparation installs only after confirmation, preserves global values, and does not execute a Source',
    () async {
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
    },
  );

  test(
    'lost ACK is shared across pages and retries the exact original global request',
    () async {
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
    },
  );

  test(
    'candidate retains original CAS through concurrent remote settings and late identity retirement',
    () async {
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
    },
  );

  test(
    'adopting a dirty progress client rebinds confirmed installation updates without resending progress',
    () async {
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
    },
  );

  test(
    'checking updates keeps the confirmed selection and failed preparation never replaces it',
    () async {
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
    },
  );

  test(
    'explicit cancellation discards a late preparation without changing account settings',
    () async {
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
    },
  );

  test(
    'explicit rebuild recovers confirmed unavailable runtime cleanup without claiming a close ACK',
    () async {
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
    },
  );

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

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpApp(
      MaterialApp(
        home: ExtensionsPage(catalog: catalog, repository: catalog.settings!),
      ),
    );
    await tester.pumpAndSettle();
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
      await tester.pageBack();
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
      expect(tester.widget<SwitchListTile>(enabled).onChanged, isNull);
      await tap(tester, find.byKey(const ValueKey('extensions-refresh')));
      await tester.pageBack();
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

  test(
    'canonical install boundaries reject duplicate packages and normalized URL aliases',
    () {
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
    },
  );
}
