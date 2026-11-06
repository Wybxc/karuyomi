import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/business_state_validation.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/extensions/extensions_controller.dart';
import 'package:karuyomi/features/extensions/extensions_page.dart';
import 'package:karuyomi/runtime/catalog_transport.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import '../data/business_state_server.dart';
import 'package:karuyomi/features/migration/migration_controller.dart';
import '../sources/preference_fixtures.dart';

const extraUrl = 'https://community.example/extensions/index.json';
wire.CatalogReference get extraCatalog =>
    wire.CatalogReference(catalogUrl: extraUrl, repoId: 'community');
wire.ExtensionBuildDescriptor get extraDescriptor =>
    wire.ExtensionBuildDescriptor(
      buildId: 'community-1',
      packageName: preferencePackage,
      repoId: 'community',
      version: '1.0',
      sourceIds: [sourceId],
      sources: [testCatalogSource],
      manifestPath: '/extensions/builds/community-1/manifest.json',
    );
void seedPublic(TestPlatform platform) {
  platform.publicDocuments[extraUrl] = wire.encodeProtoJson(
    wire.ExtensionIndex(
      schemaVersion: 1,
      repoId: 'community',
      builds: [extraDescriptor],
    ),
  );
  platform.publicDocuments['https://community.example/extensions/builds/community-1/manifest.json'] =
      wire.encodeProtoJson(
        wire.BuildManifest(
          buildId: 'community-1',
          packageName: preferencePackage,
          repoId: 'community',
          version: '1.0',
          sourceIds: [sourceId],
          sources: [testCatalogSource],
          bundle: wire.BundleArtifact(sha256: 'a' * 64),
        ),
      );
}

void seedNetwork(TestPlatform platform) {
  platform.policyDocuments[extraUrl] = wire.ExtensionNetworkPoliciesResponse(
    schemaVersion: 1,
    catalog: extraCatalog,
    builds: [
      wire.ExtensionNetworkPolicy(
        buildId: 'community-1',
        packageName: preferencePackage,
        bundleSha256: 'a' * 64,
      ),
    ],
  );
}

void main() {
  late TestPlatform platform;
  late CatalogController catalog;
  late ExtensionsController manager;
  setUp(() async {
    platform = TestPlatform();
    seedPublic(platform);
    catalog = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    manager = ExtensionsController(
      catalog: catalog,
      repository: catalog.settings!,
      isCurrent: () => true,
    );
    await manager.refresh();
  });
  tearDown(() async {
    manager.dispose();
    catalog.dispose();
    await catalog.closeReadingProgress();
    await platform.dispose();
  });
  Iterable<TestBusinessRequest> posts() => platform.businessServer.requests
      .where((request) => request.method == 'POST');
  Future<CatalogBuild> addExtra() async {
    final preview = await manager.previewRepository(
      'https://community.example',
      '社区',
    );
    expect(preview, isNotNull, reason: manager.error);
    await manager.addRepository(preview!);
    expect(manager.error, isNull);
    return catalog.builds.singleWhere((build) => build.catalogUrl == extraUrl);
  }

  test(
    'preview is read-only; confirming one global CAS synchronizes the repository without installing',
    () async {
      final before = manager.installed.single.deepCopy();
      final preview = await manager.previewRepository(extraUrl, '社区');
      expect(preview!.builds.single.catalog, extraCatalog);
      expect(posts(), isEmpty);
      expect(platform.preparations, isEmpty);
      expect(platform.openedBuilds, isEmpty);
      await manager.addRepository(preview);
      expect(posts(), hasLength(1));
      expect(manager.installed.single, before);
      expect(catalog.builds, hasLength(2));
      final remote = BusinessStateClient(
        api: platform.businessServer,
        identity: catalog.settings!.identity,
      );
      addTearDown(remote.dispose);
      final snapshot = await SettingsRepository(remote).loadGlobal();
      expect(snapshot.global.repositories.single.catalogUrl, extraUrl);
      final count = posts().length;
      await manager.refresh(catalogToo: true);
      expect(posts(), hasLength(count));
    },
  );

  test(
    'same package requires explicit replacement; code preparation is separate from exact network readiness',
    () async {
      await catalog.openBuild(catalog.builds.single);
      expect(catalog.session, isNotNull);
      final extra = await addExtra();
      final count = posts().length;
      await manager.install(extra);
      expect(manager.error, contains('明确确认替换'));
      expect(platform.preparations, isEmpty);
      expect(posts(), hasLength(count));
      await manager.install(
        extra,
        replacing: manager.installed.single.deepCopy()..freeze(),
      );
      expect(manager.installed.single.catalogUrl, extraUrl);
      expect(platform.preparations.single.catalog, extraCatalog);
      expect(platform.buildClosures.single.buildId, 'build-1');
      expect(catalog.session, isNull);
      await catalog.openSelectedBuild(preferencePackage);
      expect(catalog.error, contains('尚未登记'));
      expect(platform.openedBuilds, ['build-1']);
      seedNetwork(platform);
      final opened = await catalog.openSelectedBuild(preferencePackage);
      expect(opened?.catalog, extraCatalog, reason: catalog.error);
      expect(catalog.session!.catalog, extraCatalog);
      expect(platform.openedBuilds, ['build-1', 'community-1']);
      final favorite = wire.FavoriteSource(
        packageName: preferencePackage,
        sourceId: sourceId,
        sourceName: '源',
        sourceLang: 'zh',
      );
      expect(
        await catalog.openFavoriteSource(
          favorite,
          identityKey: catalog.settings!.identity.key,
        ),
        true,
        reason: catalog.error,
      );
      expect(catalog.activeBuild!.catalog, extraCatalog);
    },
  );

  test(
    'removal keeps installed intent, gates every open and closes only the removed repository slot; re-add restores selection',
    () async {
      seedNetwork(platform);
      final extra = await addExtra();
      await manager.install(
        extra,
        replacing: manager.installed.single.deepCopy()..freeze(),
      );
      await catalog.openSelectedBuild(preferencePackage);
      expect(catalog.session, isNotNull, reason: catalog.error);
      final selected = manager.installed.single.deepCopy();
      await manager.removeRepository(
        manager.settings.snapshot!.global.repositories.single,
      );
      expect(manager.installed.single, selected);
      expect(catalog.session, isNull);
      expect(platform.buildClosures.single.buildId, 'community-1');
      final openedCount = platform.openedBuilds.length;
      expect(await catalog.openSelectedBuild(preferencePackage), isNull);
      expect(catalog.error, contains('仓库已移除'));
      expect(platform.openedBuilds, hasLength(openedCount));
      await addExtra();
      expect(
        (await catalog.openSelectedBuild(preferencePackage))?.catalog,
        extraCatalog,
        reason: catalog.error,
      );
    },
  );

  test(
    'cross-repository replacement retains the initial CAS and cannot overwrite a concurrent selection',
    () async {
      final extra = await addExtra();
      final original = manager.installed.single.deepCopy()..freeze();
      final entered = Completer<void>();
      final release = Completer<void>();
      platform.beforePrepare = (_) async {
        entered.complete();
        await release.future;
      };
      final changing = manager.install(extra, replacing: original);
      await entered.future;
      final remote = BusinessStateClient(
        api: platform.businessServer,
        identity: catalog.settings!.identity,
      );
      addTearDown(remote.dispose);
      final repository = SettingsRepository(remote);
      final snapshot = await repository.loadGlobal();
      await repository.setGlobal(
        values: snapshot.global.deepCopy()
          ..theme = wire.AppTheme.APP_THEME_DARK,
        basedOnRevision: snapshot.globalRevision,
      );
      release.complete();
      await changing;
      expect(manager.settings.pending!.retryable, false);
      expect(manager.installed.single, original);
      final before = posts().length;
      await manager.refresh(catalogToo: true);
      expect(posts(), hasLength(before));
      expect(
        manager.settings.snapshot!.global.theme,
        wire.AppTheme.APP_THEME_DARK,
      );
    },
  );

  test(
    'unknown repository mutation only retries its original UUID/body and read-only refresh never writes',
    () async {
      final preview = (await manager.previewRepository(extraUrl, '社区'))!;
      platform.businessServer.loseNextResponse = true;
      await manager.addRepository(preview);
      expect(manager.settings.pending!.retryable, true);
      final first = platform.businessServer.requests.lastWhere(
        (request) => request.method == 'POST',
      );
      await manager.refresh(catalogToo: true);
      expect(posts(), hasLength(1));
      await manager.install(catalog.builds.first);
      expect(platform.preparations, isEmpty);
      await manager.retry();
      expect(posts(), hasLength(2));
      expect(
        platform.businessServer.requests
            .lastWhere((request) => request.method == 'POST')
            .body,
        first.body,
      );
    },
  );

  test(
    'invalid credentials, reserved and duplicate repository identities never mutate the account',
    () async {
      expect(
        await manager.previewRepository(
          'https://user:pass@community.example',
          '社区',
        ),
        isNull,
      );
      expect(
        platform.publicReads.where((uri) => uri.host == 'community.example'),
        isEmpty,
      );
      await addExtra();
      final count = posts().length;
      expect(await manager.previewRepository(extraUrl, '重复'), isNull);
      platform.publicDocuments['https://other.example/extensions/index.json'] =
          wire.encodeProtoJson(
            wire.ExtensionIndex(schemaVersion: 1, repoId: 'community'),
          );
      expect(
        await manager.previewRepository('https://other.example', '重复身份'),
        isNull,
      );
      expect(posts(), hasLength(count));
      final repositories = List.generate(
        16,
        (i) => wire.ExtensionRepository(
          catalogUrl: 'https://repo$i.example/extensions/index.json',
          repoId: 'repo$i',
          name: '仓库$i',
        ),
      );
      expect(() => validateBusinessRepositories(repositories), returnsNormally);
      expect(
        () => validateBusinessRepositories([
          ...repositories,
          wire.ExtensionRepository(
            catalogUrl: extraUrl,
            repoId: 'community',
            name: '多余',
          ),
        ]),
        throwsFormatException,
      );
      expect(
        () => validateBusinessRepositories([
          wire.ExtensionRepository(
            catalogUrl: extraUrl,
            repoId: 'keiyoushi',
            name: '保留',
          ),
        ]),
        throwsFormatException,
      );
      expect(
        () => validateBusinessRepositories([
          wire.ExtensionRepository(
            catalogUrl: extraUrl,
            repoId: 'bad\nrepo',
            name: '非法',
          ),
        ]),
        throwsFormatException,
      );
      expect(
        () => validateBusinessRepositories([
          wire.ExtensionRepository(
            catalogUrl: 'http://127.0.0.1:9000/extensions/index.json',
            repoId: 'local',
            name: '本地',
          ),
        ]),
        returnsNormally,
      );
      expect(
        () => validateBusinessRepositories([
          wire.ExtensionRepository(
            catalogUrl: extraUrl,
            repoId: 'community',
            name: '中' * 100,
          ),
        ]),
        returnsNormally,
      );
      expect(
        () => validateBusinessRepositories([
          wire.ExtensionRepository(
            catalogUrl: extraUrl,
            repoId: 'community',
            name: '😀' * 51,
          ),
        ]),
        throwsFormatException,
      );
    },
  );

  test(
    'external same-package preferences and secrets stay in that repository session',
    () async {
      final fixture = PreferenceFixture();
      await fixture.open();
      addTearDown(fixture.close);
      final officialEditor = fixture.editor();
      addTearDown(officialEditor.dispose);
      expect(await officialEditor.load(), true);
      expect(
        await officialEditor.change([
          1,
        ], wire.PreferenceValue(text: 'official-secret')),
        true,
      );
      final owner = fixture.catalog;
      final management = ExtensionsController(
        catalog: owner,
        repository: owner.settings!,
        isCurrent: () => true,
      );
      addTearDown(management.dispose);
      seedPublic(fixture.platform);
      seedNetwork(fixture.platform);
      await management.refresh();
      await management.addRepository(
        (await management.previewRepository(extraUrl, '社区'))!,
      );
      final foreign = owner.builds.singleWhere(
        (build) => build.catalogUrl == extraUrl,
      );
      await management.install(
        foreign,
        replacing: management.installed.single.deepCopy()..freeze(),
      );
      await owner.openSelectedSource(
        packageName: preferencePackage,
        sourceId: sourceId,
        shouldContinue: () => true,
      );
      expect(owner.activeBuild!.catalog, extraCatalog, reason: owner.error);
      expect(fixture.platform.preferenceBootstraps.last.sources, isEmpty);
      final externalEditor = fixture.editor();
      addTearDown(externalEditor.dispose);
      expect(await externalEditor.load(), true);
      expect(externalEditor.snapshot!.nodes.first.syncScope, sessionScope);
      final count = fixture.postedBodies.length;
      expect(
        await externalEditor.change([0], wire.PreferenceValue(boolean: true)),
        true,
        reason: externalEditor.error,
      );
      expect(fixture.postedBodies, hasLength(count));
      expect(
        fixture
            .platform
            .preferenceBootstraps
            .last
            .sources
            .single
            .entries
            .single
            .key,
        'alias',
      );
      final official = owner.builds.singleWhere(
        (build) => build.catalogUrl == owner.catalogUrl,
      );
      await management.install(
        official,
        replacing: management.installed.single.deepCopy()..freeze(),
      );
      await owner.openSelectedSource(
        packageName: preferencePackage,
        sourceId: sourceId,
        shouldContinue: () => true,
      );
      expect(
        owner.activeBuild!.catalog,
        owner.defaultCatalog,
        reason: owner.error,
      );
      final entries =
          fixture.platform.preferenceBootstraps.last.sources.single.entries;
      expect(entries.single.key, 'password');
      expect(entries.single.value.text, 'official-secret');
    },
  );

  for (final retire in [false, true]) {
    test(
      'held public preview is actively cancelled on ${retire ? 'identity retirement' : 'page disposal'}',
      () async {
        final held = HeldCatalogTransport()..document = platform.inventory;
        final owner = CatalogController(
          api: platform,
          runtime: platform.runtime,
          rebuildRuntime: platform.rebuild,
          deploymentOrigin: platform.origin,
          catalogs: held,
        );
        await owner.connect();
        addTearDown(owner.dispose);
        final management = ExtensionsController(
          catalog: owner,
          repository: owner.settings!,
          isCurrent: () => true,
        );
        await management.refresh();
        held.hold = true;
        final pending = management.previewRepository(extraUrl, '社区');
        await held.started.future;
        if (retire) {
          platform.bootstrapStatus = 403;
          await owner.connect();
        } else {
          management.dispose();
        }
        await held.cancelled.future.timeout(const Duration(seconds: 1));
        expect(await pending, isNull);
        expect(posts(), isEmpty);
        expect(platform.preparations, isEmpty);
        if (retire) management.dispose();
      },
    );
  }

  test(
    'closing migration during the first catalog read cancels it and prevents later repository reads',
    () async {
      final held = HeldCatalogTransport()..document = platform.inventory;
      final owner = CatalogController(
        api: platform,
        runtime: platform.runtime,
        rebuildRuntime: platform.rebuild,
        deploymentOrigin: platform.origin,
        catalogs: held,
      );
      await owner.connect();
      addTearDown(owner.dispose);
      final migration = MigrationController(
        catalog: owner,
        client: owner.library!.client,
        seed: MigrationSeed(
          metadata: wire.LibraryMetadata(
            packageName: preferencePackage,
            sourceId: sourceId,
            sourceName: '源',
            sourceLang: 'zh',
            manga: testManga,
          ),
        ),
        isCurrent: () => true,
      );
      held.hold = true;
      final count = held.reads.length;
      final refreshing = migration.refreshSources();
      await held.started.future;
      migration.dispose();
      await held.cancelled.future.timeout(const Duration(seconds: 1));
      await refreshing;
      expect(held.reads, hasLength(count + 1));
      expect(posts(), isEmpty);
    },
  );

  testWidgets(
    'repository dialog previews before an explicit second confirmation writes the account',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ExtensionsPage(catalog: catalog, repository: catalog.settings!),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('repositories-add')),
      );
      await tester.tap(find.byKey(const ValueKey('repositories-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('repository-url')),
        'https://community.example',
      );
      await tester.enterText(
        find.byKey(const ValueKey('repository-name')),
        '社区',
      );
      await tester.tap(find.byKey(const ValueKey('repository-preview-submit')));
      await tester.pumpAndSettle();
      expect(find.text('确认添加仓库'), findsOneWidget);
      expect(posts(), isEmpty);
      expect(platform.preparations, isEmpty);
      await tester.tap(find.byKey(const ValueKey('repository-add-confirm')));
      await tester.pumpAndSettle();
      expect(posts(), hasLength(1));
      expect(
        catalog.repositories.any(
          (repository) => repository.catalogUrl == extraUrl,
        ),
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final denied in [true, false]) {
    testWidgets(
      'lazy extension page permanently retires when ${denied ? 'Access fails' : 'the account changes'} before construction',
      (tester) async {
        final clicked = catalog.settings!;
        if (denied) {
          platform.bootstrapStatus = 403;
        } else {
          platform.bootstrapSubject = 'other-subject';
        }
        await catalog.connect();
        final before = platform.businessServer.requests.length;
        await tester.pumpWidget(
          MaterialApp(
            home: ExtensionsPage(catalog: catalog, repository: clicked),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(platform.businessServer.requests, hasLength(before));
        expect(platform.preparations, isEmpty);
        platform.bootstrapStatus = 200;
        platform.bootstrapSubject = 'owner-subject';
        await catalog.connect();
        final resumed = platform.businessServer.requests.length;
        await tester.pumpAndSettle();
        expect(platform.businessServer.requests, hasLength(resumed));
        expect(platform.preparations, isEmpty);
        expect(posts(), isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

final class HeldCatalogTransport implements CatalogTransport {
  final started = Completer<void>();
  final cancelled = Completer<void>();
  bool hold = false;
  final reads = <Uri>[];
  Object? document;
  @override
  Future<Object?> read(
    Uri uri, {
    bool Function()? shouldContinue,
    Future<void>? cancelled,
  }) async {
    reads.add(uri);
    if (hold) {
      if (!started.isCompleted) started.complete();
      await cancelled;
      if (!this.cancelled.isCompleted) this.cancelled.complete();
      throw StateError('Cancelled');
    }
    return document;
  }

  @override
  void close() {}
}
