import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import 'fakes.dart';

wire.FavoriteSource get _favorite => wire.FavoriteSource(
  packageName: 'eu.kanade.source.test',
  sourceId: sourceId,
  sourceName: '已保存的名称',
  sourceLang: 'zh',
);

wire.ExtensionBuildDescriptor _build(String id, String packageName) =>
    wire.ExtensionBuildDescriptor(
      buildId: id,
      packageName: packageName,
      repoId: 'keiyoushi',
      sourceIds: [sourceId],
      sources: [testCatalogSource],
      version: '2.0',
      manifestPath: '/extensions/builds/$id/manifest.json',
    );

void main() {
  late TestPlatform platform;
  late CatalogController catalog;

  setUp(() async {
    platform = TestPlatform();
    catalog = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
  });

  tearDown(() async {
    catalog.dispose();
    await catalog.closeReadingProgress();
    await platform.dispose();
  });

  String identity() => catalog.settings!.identity.key;

  test(
    'a saved Source opens the current build and ID without a prior package selection',
    () async {
      platform.inventory = wire.encodeProtoJson(
        wire.ExtensionIndex(
          schemaVersion: 1,
          repoId: 'keiyoushi',
          builds: [_build('build-2', 'eu.kanade.source.test')],
        ),
      );
      platform.seedInstalledBuilds([
        _build('build-2', 'eu.kanade.source.test'),
      ]);
      platform.manifestBuildId = 'build-2';
      platform.runtimeGeneration = 'generation-2';
      platform.sourceInventory = [
        wire.SourceInfo(id: '42', name: '已保存的名称', lang: 'zh'),
        wire.SourceInfo(id: sourceId, name: '源的新名称', lang: 'en'),
      ];
      await catalog.connect();
      expect(catalog.activeBuild, isNull);
      expect(
        await catalog.openFavoriteSource(_favorite, identityKey: identity()),
        true,
        reason: catalog.error,
      );
      expect(platform.openedBuilds, ['build-2']);
      expect(catalog.activeBuild!.id, 'build-2');
      expect(catalog.session!.generation, 'generation-2');
      expect(catalog.activeSource!.id, sourceId);
      expect(catalog.activeSource!.name, '源的新名称');
      expect(catalog.mangas.single.url, testManga.url);
      expect(catalog.page, 1);
      expect(catalog.listing, 'popular');
      expect(platform.invocations, hasLength(1));
      expect(platform.invocations.single.sourceId, sourceId);
      expect(platform.invocations.single.popular.page, 1);
      expect(
        platform.businessServer.requests.where(
          (request) => request.method == 'POST',
        ),
        isEmpty,
      );
    },
  );

  test(
    'the same Source ID in another package cannot redirect the favorite',
    () async {
      platform.inventory = wire.encodeProtoJson(
        wire.ExtensionIndex(
          schemaVersion: 1,
          repoId: 'keiyoushi',
          builds: [
            _build('build-other', 'source.other'),
            _build('build-current', 'eu.kanade.source.test'),
          ],
        ),
      );
      platform.seedInstalledBuilds([
        _build('build-current', 'eu.kanade.source.test'),
      ]);
      platform.manifestBuildId = 'build-current';
      await catalog.connect();
      expect(
        await catalog.openFavoriteSource(_favorite, identityKey: identity()),
        true,
        reason: catalog.error,
      );
      expect(platform.openedBuilds, ['build-current']);
      expect(catalog.activeBuild!.packageName, 'eu.kanade.source.test');
    },
  );

  test(
    'an unavailable package reports a failure without opening another extension',
    () async {
      final favorite = _favorite..packageName = 'source.unavailable';
      expect(
        await catalog.openFavoriteSource(favorite, identityKey: identity()),
        false,
      );
      expect(catalog.error, contains('尚未安装'));
      expect(platform.openedBuilds, isEmpty);
      expect(platform.invocations, isEmpty);
      expect(catalog.status, ServiceStatus.ready);
      expect(favorite.packageName, 'source.unavailable');
    },
  );

  test(
    'a missing Source never falls back to a matching display name',
    () async {
      platform.sourceInventory = [
        wire.SourceInfo(id: '42', name: _favorite.sourceName, lang: 'zh'),
      ];
      expect(
        await catalog.openFavoriteSource(_favorite, identityKey: identity()),
        false,
      );
      expect(catalog.error, '当前扩展中找不到这个收藏源，收藏仍保留。');
      expect(catalog.activeSource, isNull);
      expect(platform.invocations, isEmpty);
      expect(catalog.mangas, isEmpty);
    },
  );

  test(
    'invalid favorite input and the wrong identity never load a Source',
    () async {
      final key = identity();
      expect(
        await catalog.openFavoriteSource(_favorite, identityKey: '$key-other'),
        false,
      );
      expect(
        await catalog.openFavoriteSource(
          _favorite..sourceId = '9223372036854775808',
          identityKey: key,
        ),
        false,
      );
      expect(catalog.error, '收藏源资料无效，请重新读取服务端设置。');
      expect(platform.openedBuilds, isEmpty);
      expect(platform.invocations, isEmpty);
    },
  );

  test(
    'one busy operation blocks duplicate opening and manual browsing through all stages',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      platform.beforeApiFetch = (path) async {
        if (path != '/extensions/builds/build-1/manifest.json') return;
        entered.complete();
        await release.future;
      };
      final observations = <(bool, int)>[];
      catalog.addListener(() => observations.add((catalog.busy, catalog.page)));
      final favorite = _favorite;
      final opening = catalog.openFavoriteSource(
        favorite,
        identityKey: identity(),
      );
      await entered.future.timeout(const Duration(seconds: 5));
      favorite.sourceId = '42';
      expect(catalog.busy, true);
      expect(
        await catalog.openFavoriteSource(_favorite, identityKey: identity()),
        false,
      );
      await catalog.openBuild(catalog.builds.single);
      await catalog.loadMangas(search: 'must not interleave');
      expect(platform.invocations, isEmpty);
      release.complete();
      expect(await opening, true);
      expect(platform.openedBuilds, ['build-1']);
      expect(platform.invocations, hasLength(1));
      expect(platform.invocations.single.sourceId, sourceId);
      expect(platform.invocations.single.hasPopular(), true);
      expect(
        observations.where((value) => !value.$1 && value.$2 == 0),
        isEmpty,
      );
      expect(catalog.busy, false);
    },
  );

  test(
    'a page that leaves during manifest fetching cannot open the runtime',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      platform.beforeApiFetch = (path) async {
        if (path != '/extensions/builds/build-1/manifest.json') return;
        entered.complete();
        await release.future;
      };
      var current = true;
      final opening = catalog.openFavoriteSource(
        _favorite,
        identityKey: identity(),
        shouldContinue: () => current,
      );
      await entered.future.timeout(const Duration(seconds: 5));
      current = false;
      release.complete();
      expect(await opening, false);
      expect(platform.openedBuilds, isEmpty);
      expect(platform.invocations, isEmpty);
      expect(catalog.mangas, isEmpty);
      expect(catalog.busy, false);
    },
  );

  test(
    'a new identity rejects the old manifest result after a container loss',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      platform.beforeApiFetch = (path) async {
        if (path != '/extensions/builds/build-1/manifest.json') return;
        entered.complete();
        await release.future;
      };
      final oldIdentity = identity();
      final opening = catalog.openFavoriteSource(
        _favorite,
        identityKey: oldIdentity,
      );
      await entered.future.timeout(const Duration(seconds: 5));
      platform.runtime.containerLost('Lost while opening a favorite');
      await Future<void>.delayed(Duration.zero);
      platform.bootstrapSubject = 'other-subject';
      await catalog.connect();
      expect(identity(), isNot(oldIdentity));
      release.complete();
      expect(await opening, false);
      expect(catalog.subject, 'other-subject');
      expect(catalog.status, ServiceStatus.ready);
      expect(catalog.activeSource, isNull);
      expect(platform.openedBuilds, isEmpty);
      expect(platform.invocations, isEmpty);
    },
  );

  test(
    'late listing data is discarded when the opening page is no longer current',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      platform.invokeHandler = (_) async {
        entered.complete();
        await release.future;
        return wire.SourceResult(
          mangaPage: wire.MangaPage(mangas: [testManga]),
        );
      };
      var current = true;
      final opening = catalog.openFavoriteSource(
        _favorite,
        identityKey: identity(),
        shouldContinue: () => current,
      );
      await entered.future.timeout(const Duration(seconds: 5));
      current = false;
      release.complete();
      expect(await opening, false);
      expect(catalog.mangas, isEmpty);
      expect(catalog.page, 0);
      expect(catalog.busy, false);
    },
  );

  test(
    'a Source failure remains visible and is never retried automatically',
    () async {
      platform.invokeHandler = (_) async => throw const RuntimeException(
        RuntimeErrorCode.sourceError,
        'Source failure',
      );
      expect(
        await catalog.openFavoriteSource(_favorite, identityKey: identity()),
        false,
      );
      expect(catalog.error, '漫画源请求失败，请重试');
      expect(catalog.status, ServiceStatus.ready);
      expect(catalog.activeSource!.id, sourceId);
      expect(catalog.page, 0);
      await Future<void>.delayed(Duration.zero);
      expect(platform.invocations, hasLength(1));
    },
  );
}
