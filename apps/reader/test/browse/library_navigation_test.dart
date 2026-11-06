import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import 'fakes.dart';

void main() {
  late TestPlatform platform;
  late CatalogController catalog;
  late LibraryRepository library;
  late LibraryEntry entry;

  setUp(() async {
    platform = TestPlatform();
    catalog = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    library = catalog.library!;
    await library.setFavorite(
      packageName: 'eu.kanade.source.test',
      sourceId: sourceId,
      sourceName: '测试漫画源',
      sourceLang: 'zh',
      manga: testManga,
      favorite: true,
    );
    entry = (await library.watchEntries().first).single;
  });

  tearDown(() async {
    catalog.dispose();
    await catalog.closeReadingProgress();
    await platform.dispose();
  });

  test(
    'saved Source snapshot opens through the current build without a listing',
    () async {
      platform.inventory = wire.encodeProtoJson(
        wire.ExtensionIndex(
          schemaVersion: 1,
          builds: [
            wire.ExtensionBuildDescriptor(
              buildId: 'build-2',
              packageName: 'eu.kanade.source.test',
              repoId: 'keiyoushi',
              sourceIds: [sourceId],
              sources: [testCatalogSource],
              version: '2.0',
              manifestPath: '/extensions/builds/build-2/manifest.json',
            ),
          ],
        ),
      );
      platform.manifestBuildId = 'build-2';
      platform.runtimeGeneration = 'generation-2';
      await catalog.connect();
      final details = await catalog.openLibraryEntry(
        entry,
        identityKey: library.identity.key,
      );
      expect(details, isNotNull);
      expect(details!.source.buildId, 'build-2');
      expect(details.source.generation, 'generation-2');
      expect(platform.openedBuilds, ['build-2']);
      expect(platform.invocations.map((call) => call.whichRequest()), [
        wire.SourceCall_Request.details,
        wire.SourceCall_Request.chapters,
      ]);
      expect(platform.invocations.first.details.manga, testManga);
      expect(details.chapters.single.url, '/chapter/opaque-ref');
    },
  );

  test(
    'unavailable package keeps the favorite and never opens another Source',
    () async {
      catalog.builds = const [];
      expect(
        await catalog.openLibraryEntry(
          entry,
          identityKey: library.identity.key,
        ),
        isNull,
      );
      expect(catalog.error, contains('漫画源当前不可用'));
      expect(platform.openedBuilds, isEmpty);
      expect(platform.invocations, isEmpty);
      expect(
        (await library.watchEntries().first).single.mangaKey,
        entry.mangaKey,
      );
    },
  );

  test(
    'missing Source does not fall back to another Source in the package',
    () async {
      platform.sourceInventory = [
        wire.SourceInfo(id: '9223372036854775805', name: '另一来源', lang: 'en'),
      ];
      expect(
        await catalog.openLibraryEntry(
          entry,
          identityKey: library.identity.key,
        ),
        isNull,
      );
      expect(catalog.error, contains('找不到原漫画源'));
      expect(platform.invocations, isEmpty);
      expect(await library.watchFavorite(entry.mangaKey).first, true);
    },
  );

  test(
    'a stale library row cannot be opened after bootstrap changes identity',
    () async {
      platform.bootstrapSubject = 'another-owner';
      await catalog.connect();
      expect(
        await catalog.openLibraryEntry(
          entry,
          identityKey: library.identity.key,
        ),
        isNull,
      );
      expect(platform.openedBuilds, isEmpty);
      expect(await catalog.library!.watchEntries().first, isEmpty);
      expect(platform.businessServer.manga(entry.mangaKey)!.favorite, true);
    },
  );

  test(
    'leaving the library during details prevents the following chapter call',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var current = true;
      platform.invokeHandler = (call) async {
        expect(call.whichRequest(), wire.SourceCall_Request.details);
        entered.complete();
        await release.future;
        return wire.SourceResult(manga: testManga);
      };
      final opening = catalog.openLibraryEntry(
        entry,
        identityKey: library.identity.key,
        shouldContinue: () => current,
      );
      await entered.future;
      current = false;
      release.complete();
      expect(await opening, isNull);
      expect(platform.invocations, hasLength(1));
      expect(catalog.busy, false);
    },
  );

  test(
    'Access expiry preserves the confirmed favorite and stops navigation',
    () async {
      platform.invokeHandler = (_) async => throw const RuntimeException(
        RuntimeErrorCode.accessRequired,
        'Expired Access session',
      );
      expect(
        await catalog.openLibraryEntry(
          entry,
          identityKey: library.identity.key,
        ),
        isNull,
      );
      expect(catalog.status, ServiceStatus.loginRequired);
      expect(platform.invocations, hasLength(1));
      expect(await library.watchFavorite(entry.mangaKey).first, true);
      expect(catalog.error, isNotNull);
    },
  );

  test(
    'opening details refreshes metadata without changing favorite time',
    () async {
      platform.invokeHandler = (call) async => switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(
          manga: testManga..title = '更新后的标题',
        ),
        wire.SourceCall_Request.chapters => wire.SourceResult(
          chapters: wire.ChapterList(),
        ),
        _ => throw StateError('Unexpected listing'),
      };
      final details = await catalog.openLibraryEntry(
        entry,
        identityKey: library.identity.key,
      );
      expect(details!.manga.title, '更新后的标题');
      final updated = (await library.watchEntries().first).single;
      expect(updated.title, '更新后的标题');
      expect(updated.mangaKey, entry.mangaKey);
      expect(updated.addedAt, entry.addedAt);
    },
  );

  test(
    'metadata write failure keeps the successfully fetched details usable',
    () async {
      platform.businessServer.failWrites = true;
      final details = await catalog.openLibraryEntry(
        entry,
        identityKey: library.identity.key,
      );
      expect(details, isNotNull);
      expect(details!.chapters, hasLength(1));
      expect(catalog.isCurrentSource(details.source), true);
      expect(catalog.error, contains('仍可继续阅读'));
      expect(await library.watchFavorite(entry.mangaKey).first, true);
    },
  );
}
