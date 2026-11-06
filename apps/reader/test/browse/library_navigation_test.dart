import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/bookmark_repository.dart';
import 'package:karuyomi/data/business_state_client.dart';
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
          repoId: 'keiyoushi',
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
      platform.seedInstalledBuilds(
        wire.decodeProtoJson(wire.ExtensionIndex(), platform.inventory).builds,
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
      platform.inventory = wire.encodeProtoJson(
        wire.ExtensionIndex(schemaVersion: 1, repoId: 'keiyoushi'),
      );
      expect(
        await catalog.openLibraryEntry(
          entry,
          identityKey: library.identity.key,
        ),
        isNull,
      );
      expect(catalog.error, contains('已下架'));
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
    'unchanged shelf details do not write or invalidate another device bookmark',
    () async {
      platform.invokeHandler = (call) async => switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(
          manga: entry.snapshot,
        ),
        wire.SourceCall_Request.chapters => wire.SourceResult(
          chapters: wire.ChapterList(),
        ),
        _ => throw StateError('Unexpected listing'),
      };
      final remote = BusinessStateClient(
        api: platform.businessServer.forSubject(library.identity.subject),
        identity: library.identity,
      );
      addTearDown(remote.dispose);
      final before = await remote.readManga(entry.mangaKey);
      final writes = platform.businessServer.appliedMutations;
      for (var i = 0; i < 2; i++) {
        final details = await catalog.openLibraryEntry(
          entry,
          identityKey: library.identity.key,
        );
        expect(details, isNotNull);
        expect(catalog.error, isNull);
      }
      expect(platform.businessServer.appliedMutations, writes);
      expect(platform.businessServer.accountRevision, before.accountRevision);
      final bookmark = await BookmarkRepository(remote).set(
        mangaKey: entry.mangaKey,
        chapterKey: 'chapter',
        bookmarked: true,
        basedOnRevision: before.manga.revision,
      );
      expect(bookmark.bookmarked, true);
      expect(bookmark.revision, before.manga.revision + 1);
      expect(platform.businessServer.appliedMutations, writes + 1);
    },
  );

  test(
    'unchanged stale shelf details preserve another client metadata without a POST',
    () async {
      final remote = BusinessStateClient(
        api: platform.businessServer.forSubject(library.identity.subject),
        identity: library.identity,
      );
      addTearDown(remote.dispose);
      final changed = entry.snapshot.deepCopy()
        ..title = 'Another device confirmed this title';
      await LibraryRepository(remote).refreshMetadata(
        packageName: entry.packageName,
        sourceId: entry.sourceId,
        sourceName: entry.sourceName,
        sourceLang: entry.sourceLang,
        manga: changed,
      );
      final confirmed = await remote.readManga(entry.mangaKey);
      expect(confirmed.manga.metadata.manga.title, isNot(entry.title));
      final posts = platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length;
      final writes = platform.businessServer.appliedMutations;
      platform.invokeHandler = (call) async => switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(
          manga: entry.snapshot,
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
      expect(details, isNotNull);
      expect(details!.manga.snapshot, entry.snapshot);
      expect(catalog.error, isNull);
      expect(
        platform.businessServer.requests.where(
          (request) => request.method == 'POST',
        ),
        hasLength(posts),
      );
      expect(platform.businessServer.appliedMutations, writes);
      expect(
        platform.businessServer.accountRevision,
        confirmed.accountRevision,
      );
      expect(library.client.hasPendingMetadata(entry.mangaKey), false);
      final after = await remote.readManga(entry.mangaKey);
      expect(wire.encodeProtoJson(after), wire.encodeProtoJson(confirmed));
    },
  );

  test(
    'unchanged shelf details keep a lost metadata command for its exact explicit retry',
    () async {
      final changed = entry.snapshot.deepCopy()
        ..title = 'Metadata whose acknowledgement was lost';
      platform.invokeHandler = (call) async => switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(manga: changed),
        wire.SourceCall_Request.chapters => wire.SourceResult(
          chapters: wire.ChapterList(),
        ),
        _ => throw StateError('Unexpected listing'),
      };
      platform.businessServer.loseNextResponse = true;
      final firstDetails = await catalog.openLibraryEntry(
        entry,
        identityKey: library.identity.key,
      );
      expect(firstDetails, isNotNull);
      expect(firstDetails!.manga.snapshot, changed);
      expect(catalog.error, contains('尚未确认'));
      expect(library.client.hasPendingMetadata(entry.mangaKey), true);
      final original = platform.businessServer.requests.lastWhere(
        (request) => request.method == 'POST',
      );
      final originalCommand = wire.decodeProtoJson(
        wire.StateMutation(),
        jsonDecode(original.body!),
      );
      expect(originalCommand.hasUpdateMetadata(), true);
      expect(originalCommand.mutationId, isNotEmpty);
      expect(originalCommand.expectedRevision, entry.revision);
      expect(originalCommand.updateMetadata.manga, changed);
      final posts = platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length;
      final writes = platform.businessServer.appliedMutations;
      final revision = platform.businessServer.accountRevision;
      final applied = platform.businessServer.manga(entry.mangaKey)!;
      expect(applied.metadata.manga, changed);

      // The Source now reports exactly the old row. Its read-only open must
      // neither replay the uncertain write nor discard its immutable command.
      platform.invokeHandler = (call) async => switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(
          manga: entry.snapshot,
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
      expect(details, isNotNull);
      expect(details!.manga.snapshot, entry.snapshot);
      expect(library.client.hasPendingMetadata(entry.mangaKey), true);
      expect(
        platform.businessServer.requests.where(
          (request) => request.method == 'POST',
        ),
        hasLength(posts),
      );
      expect(platform.businessServer.appliedMutations, writes);
      expect(platform.businessServer.accountRevision, revision);
      expect(
        wire.encodeProtoJson(platform.businessServer.manga(entry.mangaKey)!),
        wire.encodeProtoJson(applied),
      );

      final confirmed = await library.client.retryMetadata(entry.mangaKey);
      final retried = platform.businessServer.requests.lastWhere(
        (request) => request.method == 'POST',
      );
      final retriedCommand = wire.decodeProtoJson(
        wire.StateMutation(),
        jsonDecode(retried.body!),
      );
      expect(retried.body, original.body);
      expect(retriedCommand.mutationId, originalCommand.mutationId);
      expect(retriedCommand.expectedRevision, originalCommand.expectedRevision);
      expect(confirmed.mutationId, originalCommand.mutationId);
      expect(confirmed.manga.metadata.manga, changed);
      expect(confirmed.manga.revision, applied.revision);
      expect(library.client.hasPendingMetadata(entry.mangaKey), false);
      expect(
        platform.businessServer.requests.where(
          (request) => request.method == 'POST',
        ),
        hasLength(posts + 1),
      );
      expect(platform.businessServer.appliedMutations, writes);
      expect(platform.businessServer.accountRevision, revision);
      expect(
        wire.encodeProtoJson(platform.businessServer.manga(entry.mangaKey)!),
        wire.encodeProtoJson(applied),
      );
    },
  );

  for (final field in ['name', 'language', 'memo']) {
    test('shelf refresh persists a changed Source $field', () async {
      platform.sourceInventory = [
        wire.SourceInfo(
          id: sourceId,
          name: field == 'name' ? 'Renamed Source' : entry.sourceName,
          lang: field == 'language' ? 'en' : entry.sourceLang,
        ),
      ];
      final manga = testManga;
      if (field == 'memo') manga.memoJson = '{"opaque":"new memo"}';
      platform.invokeHandler = (call) async => switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(manga: manga),
        wire.SourceCall_Request.chapters => wire.SourceResult(
          chapters: wire.ChapterList(),
        ),
        _ => throw StateError('Unexpected listing'),
      };
      final revision = platform.businessServer.accountRevision;
      final details = await catalog.openLibraryEntry(
        entry,
        identityKey: library.identity.key,
      );
      expect(details, isNotNull);
      expect(catalog.error, isNull);
      final updated = (await library.watchEntries().first).single;
      expect(updated.snapshot, manga);
      expect(updated.sourceName, platform.sourceInventory!.single.name);
      expect(updated.sourceLang, platform.sourceInventory!.single.lang);
      expect(updated.addedAt, entry.addedAt);
      expect(platform.businessServer.accountRevision, revision + 1);
    });
  }

  test(
    'metadata write failure keeps the successfully fetched details usable',
    () async {
      platform.invokeHandler = (call) async => switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(
          manga: testManga..title = 'Changed before failed save',
        ),
        wire.SourceCall_Request.chapters => wire.SourceResult(
          chapters: wire.ChapterList(
            chapters: [wire.Chapter(url: '/chapter', name: 'Chapter')],
          ),
        ),
        _ => throw StateError('Unexpected listing'),
      };
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
