import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../test_app.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/business_state_validation.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/features/reader/reading_progress_controller.dart';
import 'package:reader_core/reader_core.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/extensions/extensions_controller.dart';
import 'package:karuyomi/features/extensions/extensions_page.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:karuyomi/main.dart';
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

  Future<void> seedBatchCandidates() async {
    final index = wire.decodeProtoJson(
      wire.ExtensionIndex(),
      platform.inventory,
    );
    final second = index.builds.single.deepCopy()
      ..packageName = 'eu.kanade.source.batch'
      ..buildId = 'batch-2'
      ..manifestPath = '/extensions/builds/batch-2/manifest.json';
    second.sources.single.name = 'Batch Source';
    index.builds.add(second);
    platform.inventory = wire.encodeProtoJson(index);
    platform.businessServer.seedInstalledExtensions([
      testInstalledExtension(buildId: 'previous-1', enabled: false)
        ..bundleSha256 = 'b' * 64,
      testInstalledExtension(
        packageName: second.packageName,
        buildId: 'previous-2',
      )..bundleSha256 = 'c' * 64,
    ], advanceRevision: true);
    await manager.refresh(catalogToo: true);
  }

  test('batch publishes only verified same-repository updates in one account write', () async {
    await seedBatchCandidates();
    platform.beforePrepare = (request) async {
      if (request.build.buildId == 'batch-2') {
        platform.preparationFailure = wire.RuntimeError(
          code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_INTEGRITY_ERROR,
          message: 'Fixture failed integrity',
        );
      }
    };
    final before = manager.settings.snapshot!.global.reader;
    await manager.updateAll();

    expect(platform.preparations, hasLength(2));
    expect(platform.openedBuilds, isEmpty);
    expect(platform.businessServer.appliedMutations, 1);
    expect(
      manager.installed.map((value) => (value.buildId, value.enabled)),
      unorderedEquals([('build-1', false), ('previous-2', true)]),
    );
    expect(manager.settings.snapshot!.global.reader, before);
    expect(manager.batchFailures.single.name, 'Batch Source');
    expect(manager.batchFailures.single.reason, contains('校验失败'));
    expect(manager.updates.single.latest!.id, 'batch-2');
  });

  test(
    'cancelling the second preparation leaves the entire batch unsubmitted',
    () async {
      await seedBatchCandidates();
      final secondStarted = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      platform.beforePrepare = (request) async {
        if (request.build.buildId == 'batch-2') {
          secondStarted.complete();
          await release.future;
        }
      };
      final batch = manager.updateAll();
      await secondStarted.future.timeout(const Duration(seconds: 5));
      expect(manager.batchProgress, (current: 2, total: 2));
      await manager.cancelPreparation();
      release.complete();
      await batch;

      expect(platform.businessServer.appliedMutations, 0);
      expect(manager.updates, hasLength(2));
      expect(manager.message, contains('已取消'));
    },
  );

  test(
    'batch keeps its original account revision through another device edit',
    () async {
      await seedBatchCandidates();
      final client = BusinessStateClient(
        api: platform.businessServer,
        identity: manager.repository.identity,
      );
      addTearDown(client.dispose);
      final remote = SettingsRepository(client);
      final baseline = await remote.loadGlobal();
      platform.beforePrepare = (request) async {
        if (request.build.buildId == 'batch-2') {
          await remote.setGlobal(
            values: baseline.global.deepCopy()
              ..reader.fit = wire.ReaderFit.READER_FIT_WIDTH,
            basedOnRevision: baseline.globalRevision,
          );
        }
      };

      await manager.updateAll();

      expect(platform.businessServer.appliedMutations, 1);
      expect(
        manager.settings.pending!.basedOnRevision,
        baseline.globalRevision,
      );
      expect(manager.settings.pending!.retryable, false);
      final current = await remote.loadGlobal();
      expect(current.global.reader.fit, wire.ReaderFit.READER_FIT_WIDTH);
      expect(
        current.global.installedExtensions.map((value) => value.buildId),
        unorderedEquals(['previous-1', 'previous-2']),
      );
    },
  );

  test('preparation installs only after confirmation, preserves global values, and does not execute a Source', () async {
    final before = manager.settings.snapshot!;
    await manager.install(catalog.builds.single);
    expect(platform.preparations, hasLength(1));
    expect(platform.openedBuilds, isEmpty);
    expect(platform.invocations, isEmpty);
    expect(manager.installed.single, testInstalledExtension());
    expect(manager.settings.snapshot!.global.reader, before.global.reader);
    expect(
      manager.settings.snapshot!.global.reader.fit,
      before.global.reader.fit,
    );
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

  test('uninstall rejects a selection from a previous repository', () async {
    await manager.install(catalog.builds.single);
    final selected = manager.installed.single;
    final stale = selected.deepCopy()..repoId = 'previous-repository';
    final writes = platform.businessServer.appliedMutations;

    await manager.uninstall(stale);

    expect(manager.error, contains('扩展版本或仓库已改变'));
    expect(manager.installed.single, selected);
    expect(platform.businessServer.appliedMutations, writes);
    expect(manager.cache!.artifacts.single.sha256, selected.bundleSha256);
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
      ..reader.fit = wire.ReaderFit.READER_FIT_WIDTH;
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
      manager.settings.snapshot!.global.reader.fit,
      wire.ReaderFit.READER_FIT_WIDTH,
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

  test(
    'unavailable extension materials keep the same build ready to retry',
    () async {
      final candidate = catalog.builds.single;
      platform.preparationFailure = wire.RuntimeError(
        code: wire
            .RuntimeErrorCode
            .RUNTIME_ERROR_CODE_EXTENSION_ASSET_UNAVAILABLE,
        message: 'Static extension asset returned HTTP 503',
        retryable: true,
      );

      await manager.install(candidate);

      final failure = manager.preparationFailure!;
      expect(failure.reason, '无法从仓库读取扩展材料。');
      expect(failure.build, same(candidate));
      expect(catalog.status, ServiceStatus.ready);
      expect(manager.repository.pendingGlobal(), isNull);
      expect(platform.businessServer.appliedMutations, 0);

      platform.preparationFailure = null;
      await manager.install(failure.build);

      expect(manager.preparationFailure, isNull);
      expect(platform.preparations.map((request) => request.build), [
        candidate.toProto(),
        candidate.toProto(),
      ]);
      expect(platform.preparations.map((request) => request.catalog), [
        candidate.catalog,
        candidate.catalog,
      ]);
      expect(manager.installed.single.buildId, candidate.id);
      expect(platform.businessServer.appliedMutations, 1);
    },
  );

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

  test(
    'confirmed uninstall retains the removed copy after runtime close fails',
    () async {
      await manager.install(catalog.builds.single);
      await catalog.openBuild(catalog.builds.single);
      final installed = manager.installed.single;
      platform.closeAcknowledged = false;

      await manager.uninstall(installed);

      expect(manager.installed, isEmpty);
      expect(manager.cleanupTarget, (
        sha256: installed.bundleSha256,
        name: testCatalogSource.name,
      ));
      expect(manager.cleanupError, contains('扩展资源尚未关闭'));
      expect(platform.cachedArtifacts.keys, [installed.bundleSha256]);
      final writes = platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length;

      platform.closeAcknowledged = true;
      await manager.retryCleanup();

      expect(manager.cleanupTarget, isNull);
      expect(manager.cleanupError, isNull);
      expect(catalog.session, isNull);
      expect(platform.cachedArtifacts, isEmpty);
      expect(
        platform.businessServer.requests
            .where((request) => request.method == 'POST')
            .length,
        writes,
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
      'extension directory distinguishes loading, empty and failed reads in $appearance',
      (tester) async {
        final populatedIndex = platform.inventory;
        platform.inventory = wire.encodeProtoJson(
          wire.ExtensionIndex(schemaVersion: 1, repoId: 'keiyoushi'),
        );
        await tester.runAsync(catalog.refreshCatalog);
        final releaseCatalog = Completer<void>();
        final catalogPath = Uri.parse(catalog.catalogUrl).path;
        platform.beforeApiFetch = (path) async {
          if (path == catalogPath) await releaseCatalog.future;
        };
        addTearDown(() {
          if (!releaseCatalog.isCompleted) releaseCatalog.complete();
        });
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpApp(
          CupertinoApp(
            theme: readerAppTheme(appearance),
            home: ExtensionsPage(
              catalog: catalog,
              repository: catalog.settings!,
            ),
          ),
        );
        await tester.pump();

        final refresh = find.byKey(const ValueKey('extensions-check-updates'));
        final empty = find.text('当前目录没有扩展');
        final unavailable = find.text('未能读取扩展目录');
        final manage = find.widgetWithText(CupertinoButton, '管理仓库');
        expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
        expect(tester.widget<CupertinoButton>(refresh).enabled, isFalse);
        expect(empty, findsNothing);
        expect(unavailable, findsNothing);

        releaseCatalog.complete();
        await tester.pumpAndSettle();
        expect(empty, findsOneWidget);
        expect(find.text('账户尚未安装扩展。'), findsNothing);
        await tap(tester, manage);
        expect(find.byType(ExtensionRepositoriesPage), findsOneWidget);
        await tester.tap(find.byType(CupertinoNavigationBarBackButton));
        await tester.pumpAndSettle();

        platform.beforeApiFetch = (path) async {
          if (path == catalogPath) throw StateError('Repository unavailable');
        };
        await tap(tester, refresh);
        expect(unavailable, findsOneWidget);
        expect(manage, findsOneWidget);
        expect(empty, findsNothing);
        expect(find.byKey(const ValueKey('extensions-message')), findsNothing);

        platform.beforeApiFetch = null;
        platform.inventory = populatedIndex;
        await tap(tester, refresh);
        final install = find.byKey(
          ValueKey((
            'extension-install',
            catalog.catalogUrl,
            'eu.kanade.source.test',
          )),
        );
        expect(install, findsOneWidget);
        expect(unavailable, findsNothing);
        expect(find.text('已检查当前目录，账户构建选择未改变。'), findsOneWidget);

        platform.beforeApiFetch = (path) async {
          if (path == catalogPath) throw StateError('Repository unavailable');
        };
        await tap(tester, refresh);
        expect(install, findsOneWidget);
        expect(unavailable, findsOneWidget);
        expect(find.byKey(const ValueKey('extensions-message')), findsNothing);
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
      'preparation failure keeps its reason and exact-build retry reachable in $appearance',
      (tester) async {
        final name = '${'跨端阅读测试扩展资料目录' * 6}末尾';
        final index = wire.decodeProtoJson(
          wire.ExtensionIndex(),
          platform.inventory,
        );
        index.builds.single.sources.single.name = name;
        final appPlatform = TestPlatform(seedDefaultInstallation: false)
          ..inventory = wire.encodeProtoJson(index)
          ..preparationFailure = wire.RuntimeError(
            code:
                wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_UNSUPPORTED_CAPABILITY,
            message: 'Fixture rejected this build',
          );
        await tester.binding.setSurfaceSize(const Size(360, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        tester.view.viewPadding = tester.view.padding;
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        tester.platformDispatcher.platformBrightnessTestValue = appearance;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpApp(KaruyomiApp(platform: appPlatform));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey(('app-destination', 'extensions'))),
        );
        await tester.pumpAndSettle();
        final appCatalog = tester
            .widget<CatalogPage>(find.byType(CatalogPage))
            .controller!;
        final install = find.widgetWithText(CupertinoButton, '安装');
        final error = find.byKey(const ValueKey('extensions-error'));
        final retry = find.byKey(const ValueKey('extensions-retry-prepare'));
        final candidate = appCatalog.builds.single;
        final repository = appCatalog.repositories.single;
        await tester.ensureVisible(install);
        await tester.pumpAndSettle();
        await tester.tap(install.hitTestable());
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(error).data, contains('当前应用不支持此扩展材料'));
        final statusScroll = find.ancestor(
          of: error,
          matching: find.byType(Scrollable),
        );
        final viewport = tester.getRect(statusScroll);
        final reasonBounds = tester.getRect(error);
        expect(reasonBounds.top, greaterThanOrEqualTo(viewport.top));
        expect(reasonBounds.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(error.hitTestable(), findsOneWidget);
        expect(retry.hitTestable(), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const PageStorageKey('extensions-scroll')),
            matching: error,
          ),
          findsNothing,
        );
        final semantics = tester.ensureSemantics();
        try {
          await tester.pump();
          expect(
            tester
                .getSemantics(error)
                .getSemanticsData()
                .flagsCollection
                .isLiveRegion,
            isTrue,
          );
        } finally {
          semantics.dispose();
        }
        expect(
          find.byKey(const ValueKey('extension-preparation-status')),
          findsNothing,
        );
        expect(appCatalog.installedExtensions, isEmpty);
        expect(
          appPlatform.businessServer.requests.where(
            (request) => request.method == 'POST',
          ),
          isEmpty,
        );

        final fullName = find.descendant(
          of: statusScroll,
          matching: find.text(name),
        );
        expect(
          tester.renderObject<RenderParagraph>(fullName).didExceedMaxLines,
          isFalse,
        );
        final version = find.text('${candidate.version} · ${repository.name}');
        final retryBounds = tester.getRect(retry);
        await tester.ensureVisible(version);
        await tester.pumpAndSettle();
        expect(version.hitTestable(), findsOneWidget);
        expect(tester.getRect(retry), retryBounds);

        appPlatform.preparationFailure = null;
        await tester.tap(retry.hitTestable());
        await tester.pumpAndSettle();
        expect(error, findsNothing);
        expect(appPlatform.preparations.map((request) => request.build), [
          candidate.toProto(),
          candidate.toProto(),
        ]);
        expect(appPlatform.preparations.map((request) => request.catalog), [
          candidate.catalog,
          candidate.catalog,
        ]);
        expect(appCatalog.installedExtensions.single.buildId, candidate.id);
        expect(
          appPlatform.businessServer.requests.where(
            (request) => request.method == 'POST',
          ),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'preparation names its build and remains visible until cancellation is acknowledged in $appearance',
      (tester) async {
        final name = '${'跨端阅读测试扩展资料目录' * 6}末尾';
        final index = wire.decodeProtoJson(
          wire.ExtensionIndex(),
          platform.inventory,
        );
        index.builds.single.sources.single.name = name;
        platform.inventory = wire.encodeProtoJson(index);
        await tester.runAsync(catalog.refreshCatalog);
        final releasePreparation = Completer<void>();
        final releaseCancellation = Completer<void>();
        String? cancelledId;
        platform.beforePrepare = (_) => releasePreparation.future;
        platform.beforeCancelPreparation = (id) {
          cancelledId = id;
          return releaseCancellation.future;
        };
        try {
          await show(
            tester,
            appearance: appearance,
            size: const Size(360, 480),
            textScale: 2,
          );
          final install = find.widgetWithText(CupertinoButton, '安装');
          await tester.ensureVisible(install);
          await tester.tap(install);
          await tester.pump();

          final preparation = find.byKey(
            const ValueKey('extension-preparation-status'),
          );
          expect(preparation, findsOneWidget);
          expect(
            find.ancestor(of: preparation, matching: find.byType(Scrollable)),
            findsNothing,
          );
          final label = find.descendant(
            of: preparation,
            matching: find.text(name),
          );
          expect(
            tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
            isFalse,
          );
          final version = find.descendant(
            of: preparation,
            matching: find.text('1.0'),
          );
          final cancel = find.byKey(
            const ValueKey('extensions-cancel-prepare'),
          );
          expect(cancel.hitTestable(), findsOneWidget);
          await tester.ensureVisible(version);
          await tester.pump();
          expect(version.hitTestable(), findsOneWidget);
          expect(cancel.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(cancel);
          await tester.pump();
          releasePreparation.complete();
          await tester.pump();

          expect(cancelledId, platform.preparations.single.preparationId);
          expect(find.text('正在取消准备').hitTestable(), findsOneWidget);
          expect(tester.widget<CupertinoButton>(install).enabled, isFalse);
          expect(manager.installed, isEmpty);

          releaseCancellation.complete();
          await tester.pumpAndSettle();
          expect(preparation, findsNothing);
          expect(find.textContaining('已取消准备'), findsOneWidget);
          expect(tester.widget<CupertinoButton>(install).enabled, isTrue);
          expect(
            platform.businessServer.requests.where(
              (request) => request.method == 'POST',
            ),
            isEmpty,
          );
        } finally {
          if (!releasePreparation.isCompleted) releasePreparation.complete();
          if (!releaseCancellation.isCompleted) releaseCancellation.complete();
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets(
      'extension details keep preparation actions visible while scrolling sources in $appearance',
      (tester) async {
        final index = wire.decodeProtoJson(
          wire.ExtensionIndex(),
          platform.inventory,
        );
        final build = index.builds.single;
        for (var i = 1; i <= 30; i++) {
          build.sourceIds.add('$i');
          build.sources.add(
            wire.CatalogSource(id: '$i', name: '测试漫画源 $i', lang: 'zh'),
          );
        }
        platform.inventory = wire.encodeProtoJson(index);
        await tester.runAsync(catalog.refreshCatalog);
        final release = Completer<void>();
        platform.beforePrepare = (_) => release.future;
        platform.preparationFailure = wire.RuntimeError(
          code: wire
              .RuntimeErrorCode
              .RUNTIME_ERROR_CODE_EXTENSION_ASSET_UNAVAILABLE,
          message: 'Manifest unavailable',
        );
        try {
          await show(
            tester,
            appearance: appearance,
            size: const Size(844, 390),
          );
          await tap(
            tester,
            find.byKey(
              ValueKey((
                'extension-details',
                catalog.catalogUrl,
                build.packageName,
              )),
            ),
          );
          final install = find.widgetWithText(CupertinoButton, '安装');
          await tester.ensureVisible(install);
          await tester.tap(install);
          await tester.pump();
          final cancel = find.byKey(
            const ValueKey('extensions-cancel-prepare'),
          );
          expect(cancel.hitTestable(), findsOneWidget);

          final sources = find.descendant(
            of: find.byType(ExtensionDetailsPage),
            matching: find.byType(ListView),
          );
          final scroll = tester.state<ScrollableState>(
            find
                .descendant(of: sources, matching: find.byType(Scrollable))
                .first,
          );
          await tester.drag(sources, const Offset(0, -580));
          await tester.pump(const Duration(milliseconds: 600));
          expect(scroll.position.pixels, greaterThan(300));
          expect(install.hitTestable(), findsNothing);
          expect(cancel.hitTestable(), findsOneWidget);

          release.complete();
          await tester.pumpAndSettle();
          final retry = find.byKey(const ValueKey('extensions-retry-prepare'));
          expect(retry.hitTestable(), findsOneWidget);
          expect(scroll.position.pixels, greaterThan(300));
          expect(find.text('无法从仓库读取扩展材料。').hitTestable(), findsOneWidget);
          expect(platform.businessServer.appliedMutations, 0);

          platform.preparationFailure = null;
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(retry, findsNothing);
          expect(
            platform.preparations.map((request) => request.build.buildId),
            [build.buildId, build.buildId],
          );
          expect(platform.businessServer.appliedMutations, 1);
        } finally {
          if (!release.isCompleted) release.complete();
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets(
      'storage retains the exact failed copy and retries it without an account write in $appearance',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final original = 'a' * 64;
        final other = 'b' * 64;
        await manager.install(catalog.builds.single);
        final confirmed = manager.installed.single.deepCopy();
        final writes = platform.businessServer.requests
            .where((request) => request.method == 'POST')
            .length;
        platform.cachedArtifacts[other] = wire.CachedExtensionArtifact(
          sha256: other,
          byteLength: 128,
          contentType: 'application/javascript',
        );
        await manager.refresh();
        final release = Completer<wire.RuntimeError?>();
        final attempts = <String>[];
        platform.beforeForgetArtifact = (sha256) async {
          attempts.add(sha256);
          if (attempts.length == 1) return release.future;
          return null;
        };

        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpApp(
            CupertinoApp(
              theme: readerAppTheme(appearance),
              home: ExtensionStoragePage(controller: manager),
            ),
          );
          await tester.pumpAndSettle();
          final status = find.byKey(const ValueKey('extension-cleanup-status'));
          final originalAction = find.byKey(
            ValueKey(('extension-forget', original)),
          );
          final otherAction = find.byKey(ValueKey(('extension-forget', other)));
          final refresh = find.text('重新读取本机副本');
          await tester.ensureVisible(originalAction);
          await tester.tap(originalAction);
          await tester.pump();

          expect(attempts, [original]);
          expect(find.text('正在清理本机副本'), findsOneWidget);
          expect(
            find.descendant(
              of: status,
              matching: find.text(testCatalogSource.name),
            ),
            findsOneWidget,
          );
          expect(tester.widget<CupertinoButton>(otherAction).enabled, isFalse);
          for (final control in [originalAction, otherAction, refresh]) {
            await tester.ensureVisible(control);
            await tester.pump();
            expect(
              tester
                  .getSemantics(control)
                  .getSemanticsData()
                  .flagsCollection
                  .isEnabled,
              Tristate.isFalse,
            );
          }
          expect(manager.installed.single, confirmed);

          release.complete(
            wire.RuntimeError(
              code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_STORAGE_BUSY,
              message: 'An active runtime has the artifact in use',
            ),
          );
          await tester.pumpAndSettle();
          final reason = find.textContaining('关闭正在使用此扩展的标签页或窗口');
          expect(find.text('清理未完成'), findsOneWidget);
          expect(find.descendant(of: status, matching: reason), findsOneWidget);
          expect(
            find.descendant(of: status, matching: find.text(original)),
            findsOneWidget,
          );
          final usage = find.ancestor(
            of: find.text('扩展副本占用'),
            matching: find.byType(CupertinoFormSection),
          );
          expect(
            tester.getBottomLeft(status).dy,
            lessThan(tester.getTopLeft(usage).dy),
          );
          await tester.ensureVisible(refresh);
          await tester.tap(refresh);
          await tester.pumpAndSettle();
          final retry = find.text('重试资源清理');
          await tester.ensureVisible(retry);
          expect(reason, findsOneWidget);
          await tester.tap(retry);
          await tester.pumpAndSettle();

          expect(attempts, [original, original]);
          expect(status, findsNothing);
          expect(platform.cachedArtifacts.keys, [other]);
          expect(manager.installed.single, confirmed);
          expect(
            platform.businessServer.requests
                .where((request) => request.method == 'POST')
                .length,
            writes,
          );
        } finally {
          semantics.dispose();
          if (!release.isCompleted) release.complete(null);
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );

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

    testWidgets(
      'storage shows one truthful progress indicator and disables rereading in $appearance',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final fresh = ExtensionsController(
          container: container,
          catalog: catalog,
          repository: manager.repository,
          isCurrent: () => current,
        );
        final release = Completer<void>();
        platform.beforeApiFetch = (path) async {
          if (path == '/api/settings') await release.future;
        };
        try {
          await tester.pumpApp(
            CupertinoApp(
              theme: readerAppTheme(appearance),
              home: ExtensionStoragePage(controller: fresh),
            ),
          );
          await tester.pump();
          final showedIdle = find.text('尚未读取本机副本').evaluate().isNotEmpty;
          final refreshLabel = find.text('重新读取本机副本');
          final refresh = find.widgetWithText(CupertinoButton, '重新读取本机副本');
          await tester.tap(refresh);
          await tester.pump();

          expect(find.text('正在检查本机副本'), findsOneWidget);
          expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
          expect(find.text('正在读取账户、目录与本机副本'), findsNothing);
          expect(showedIdle, isTrue);
          expect(tester.widget<CupertinoButton>(refresh).enabled, isFalse);
          final labelContext = tester.element(refreshLabel);
          expect(
            DefaultTextStyle.of(labelContext).style.color,
            CupertinoColors.tertiaryLabel.resolveFrom(labelContext),
          );

          release.complete();
          await tester.pumpAndSettle();
          expect(find.byType(CupertinoActivityIndicator), findsNothing);
          expect(find.text('本机没有扩展副本'), findsOneWidget);
          expect(tester.widget<CupertinoButton>(refresh).enabled, isTrue);
          expect(
            platform.businessServer.requests.where(
              (request) => request.method == 'POST',
            ),
            isEmpty,
          );
        } finally {
          if (!release.isCompleted) release.complete();
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
          fresh.dispose();
        }
      },
    );

    testWidgets(
      'storage reads the complete copy identity and recovery at twice text size in $appearance',
      (tester) async {
        final name = '${'跨端阅读测试扩展资料目录' * 4}末尾';
        final index = wire.decodeProtoJson(
          wire.ExtensionIndex(),
          platform.inventory,
        );
        index.builds.single.sources.single.name = name;
        platform.inventory = wire.encodeProtoJson(index);
        await tester.runAsync(() async {
          await catalog.refreshCatalog();
          await manager.install(catalog.builds.single);
        });
        expect(manager.installed, hasLength(1));
        final writes = platform.businessServer.requests
            .where((request) => request.method == 'POST')
            .length;
        await show(
          tester,
          appearance: appearance,
          size: const Size(360, 480),
          textScale: 2,
        );
        await tap(tester, find.byKey(const ValueKey('extensions-more')));
        await tap(tester, find.widgetWithText(CupertinoMenuItem, '本机存储'));

        final label = find.text(name);
        await tester.ensureVisible(label);
        final usage = find.byKey(const ValueKey('extensions-cache-usage'));
        expect(
          (
            tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
            tester.widget<Text>(usage).data,
          ),
          (false, '1 个副本 · 256 B'),
        );
        final row = find.ancestor(
          of: label,
          matching: find.byType(CupertinoListTile),
        );
        expect(
          find.descendant(of: row, matching: find.text('256 B')),
          findsOneWidget,
        );
        final checksum = 'a' * 64;
        final clear = find.byKey(ValueKey(('extension-forget', checksum)));
        await tester.ensureVisible(clear);
        await tester.pumpAndSettle();
        expect(clear.hitTestable(), findsOneWidget);
        final attempts = <String>[];
        platform.beforeForgetArtifact = (sha256) async {
          attempts.add(sha256);
          return attempts.length == 1
              ? wire.RuntimeError(
                  code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_STORAGE_BUSY,
                  message: 'An active runtime has the artifact in use',
                )
              : null;
        };
        await tap(tester, clear);
        final status = find.byKey(const ValueKey('extension-cleanup-status'));
        final retry = find.text('重试资源清理');
        final reason = find.textContaining('关闭正在使用此扩展的标签页或窗口');
        final failedName = find.descendant(of: status, matching: label);
        final failedChecksum = find.descendant(
          of: status,
          matching: find.text(checksum),
        );
        expect(status, findsOneWidget);
        expect(retry.hitTestable(), findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(failedName).didExceedMaxLines,
          isFalse,
        );
        expect(
          tester
              .renderObject<RenderParagraph>(failedChecksum)
              .didExceedMaxLines,
          isFalse,
        );
        expect(
          tester.getBottomLeft(reason).dy,
          lessThan(tester.getTopLeft(retry).dy),
        );
        await tap(tester, retry);
        expect(attempts, [checksum, checksum]);
        expect(find.text('本机没有扩展副本'), findsOneWidget);
        expect(
          platform.businessServer.requests.where(
            (request) => request.method == 'POST',
          ),
          hasLength(writes),
        );
        expect(tester.takeException(), isNull);
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
            expect(find.textContaining('256 B / '), findsOneWidget);
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
      'extension details keep long identity and Source names readable in $appearance',
      (tester) async {
        final name = '${'跨端阅读测试扩展资料目录' * 5}末尾';
        final index = wire.decodeProtoJson(
          wire.ExtensionIndex(),
          platform.inventory,
        );
        final build = index.builds.single;
        build.sources.single.name = name;
        platform.inventory = wire.encodeProtoJson(index);
        await tester.runAsync(catalog.refreshCatalog);
        await tester.runAsync(() => manager.install(catalog.builds.single));
        expect(manager.installed.single.packageName, build.packageName);
        final writes = platform.businessServer.requests
            .where((request) => request.method == 'POST')
            .length;

        await show(
          tester,
          appearance: appearance,
          size: const Size(360, 480),
          textScale: 2,
        );
        expect(find.byKey(const ValueKey('extensions-message')), findsNothing);
        await tap(
          tester,
          find.byKey(
            ValueKey((
              'extension-details',
              catalog.catalogUrl,
              build.packageName,
            )),
          ),
        );
        final details = find.byType(ExtensionDetailsPage);
        final summary = find
            .descendant(
              of: details,
              matching: find.byType(CupertinoFormSection),
            )
            .first;
        for (final value in [
          name,
          build.packageName,
          '${build.version} · zh · 已安装 · 本机就绪',
          catalog.repositories.single.name,
        ]) {
          final field = find.descendant(
            of: summary,
            matching: find.text(value),
          );
          expect(field, findsOneWidget, reason: value);
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          expect(field.hitTestable(), findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(field).didExceedMaxLines,
            isFalse,
          );
        }

        final source = find.byKey(ValueKey(('extension-source', sourceId)));
        await tester.scrollUntilVisible(source, 200);
        final sourceName = find.descendant(
          of: source,
          matching: find.text(name),
        );
        expect(
          tester.renderObject<RenderParagraph>(sourceName).didExceedMaxLines,
          isFalse,
        );
        expect(tester.widget<CupertinoButton>(source).enabled, isTrue);
        await tester.tap(find.byType(CupertinoNavigationBarBackButton));
        await tester.pumpAndSettle();
        expect(details, findsNothing);
        expect(
          platform.businessServer.requests.where(
            (request) => request.method == 'POST',
          ),
          hasLength(writes),
        );
        expect(tester.takeException(), isNull);
      },
    );

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
        final status = find.descendant(
          of: find.byType(ExtensionDetailsPage),
          matching: find.text(expected),
        );
        expect(status, findsOneWidget);
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
    'retrying a failed local copy download preserves the account selection',
    (tester) async {
      await manager.install(catalog.builds.single);
      final installed = catalog.installedExtensions.single;
      final before = platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length;
      platform.cachedArtifacts.clear();
      platform.preparationFailure = wire.RuntimeError(
        code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_STORAGE_BUSY,
        message: 'Fixture rejected the local download',
      );
      await show(tester);
      await tap(
        tester,
        find.byKey(ValueKey(('extension-installed', installed.packageName))),
      );
      await tap(
        tester,
        find.byKey(ValueKey(('extension-prepare', installed.packageName))),
      );
      expect(find.textContaining('扩展仍在使用'), findsOneWidget);
      final retry = find.byKey(const ValueKey('extensions-retry-prepare'));
      expect(retry.hitTestable(), findsOneWidget);
      platform.preparationFailure = null;
      await tap(tester, retry);
      expect(find.text('本机产物已准备，账户选择未改变。'), findsOneWidget);
      expect(catalog.installedExtensions.single, installed);
      expect(platform.cachedArtifacts, contains(installed.bundleSha256));
      expect(platform.preparations.map((request) => request.build.buildId), [
        installed.buildId,
        installed.buildId,
        installed.buildId,
      ]);
      expect(
        platform.businessServer.requests.where(
          (request) => request.method == 'POST',
        ),
        hasLength(before),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a long extension name keeps the uninstall effect and actions visible on a short screen',
    (tester) async {
      final name = '${'跨端阅读测试扩展资料目录' * 6}末尾';
      final index = wire.decodeProtoJson(
        wire.ExtensionIndex(),
        platform.inventory,
      );
      index.builds.single.sources.single.name = name;
      platform.inventory = wire.encodeProtoJson(index);
      await tester.runAsync(() async {
        await catalog.refreshCatalog();
        await manager.install(catalog.builds.single);
      });
      final installed = catalog.installedExtensions.single;
      await show(
        tester,
        appearance: Brightness.dark,
        size: const Size(360, 480),
        textScale: 2,
      );
      await tap(
        tester,
        find.byKey(ValueKey(('extension-installed', installed.packageName))),
      );
      final uninstall = find.byKey(
        ValueKey(('extension-uninstall', installed.packageName)),
      );
      await tester.ensureVisible(uninstall);
      await tester.pumpAndSettle();
      await tester.tap(uninstall.hitTestable());
      await tester.pumpAndSettle();

      final dialog = find.byType(CupertinoAlertDialog);
      final cancel = find.descendant(
        of: dialog,
        matching: find.widgetWithText(CupertinoButton, '取消'),
      );
      final confirm = find.byKey(const ValueKey('extension-uninstall-confirm'));
      expect(find.text('此扩展将从账户移除。').hitTestable(), findsOneWidget);
      expect(cancel.hitTestable(), findsOneWidget);
      expect(confirm.hitTestable(), findsOneWidget);
      final preserved = find.descendant(
        of: dialog,
        matching: find.text('书架、分类、阅读进度、收藏源及漫画源数据会保留。'),
      );
      await tester.ensureVisible(preserved);
      await tester.pumpAndSettle();
      expect(preserved.hitTestable(), findsOneWidget);
      expect(cancel.hitTestable(), findsOneWidget);
      expect(confirm.hitTestable(), findsOneWidget);

      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(find.byType(ExtensionDetailsPage), findsOneWidget);
      expect(catalog.installedExtensions.single, installed);
      expect(
        platform.businessServer.requests.where(
          (request) => request.method == 'POST',
        ),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'management page installs, shows confirmed disable and independently retries cleanup before uninstall',
    (tester) async {
      await show(
        tester,
        appearance: Brightness.dark,
        size: const Size(360, 800),
      );
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
      final uninstall = find.byKey(
        const ValueKey(('extension-uninstall', 'eu.kanade.source.test')),
      );
      final dialog = find.byType(CupertinoAlertDialog);
      final confirm = find.byKey(const ValueKey('extension-uninstall-confirm'));
      int submissions() => platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length;
      final before = submissions();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(uninstall);
      await tester.tap(uninstall);
      await tester.pump();
      final initialRect = tester.getRect(dialog);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getRect(dialog), initialRect);
      expect(
        find.ancestor(
          of: dialog,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is FadeTransition &&
                widget.opacity.value > 0 &&
                widget.opacity.value < 1,
          ),
        ),
        findsWidgets,
      );
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      expect(find.text('卸载扩展？'), findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(testCatalogSource.name),
        ),
        findsOneWidget,
      );
      expect(find.text('此扩展将从账户移除。').hitTestable(), findsOneWidget);
      expect(find.textContaining('书架、分类、阅读进度'), findsOneWidget);
      expect(
        tester.widget<CupertinoButton>(confirm).foregroundColor,
        AppColors.error.resolveFrom(tester.element(confirm)),
      );
      expect(submissions(), before);
      final cancel = find.descendant(
        of: dialog,
        matching: find.widgetWithText(CupertinoButton, '取消'),
      );
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<CupertinoButton>(),
        tester.widget<CupertinoButton>(cancel),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        find.byType(CupertinoAlertDialog, skipOffstage: false),
        findsNothing,
      );
      expect(catalog.installedExtensions.single.enabled, false);
      expect(submissions(), before);
      await tester.tap(uninstall);
      await tester.pump();
      expect(ModalRoute.of(tester.element(dialog))!.animation!.value, 1);
      await tester.tap(cancel);
      await tester.pump();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pumpAndSettle();
      await tap(tester, uninstall);
      await tap(tester, confirm);
      expect(submissions(), before + 1);
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
