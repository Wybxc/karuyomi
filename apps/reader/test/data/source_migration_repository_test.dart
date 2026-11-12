import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/bookmark_repository.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/data/source_migration_repository.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:protobuf/protobuf.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

wire.LibraryMetadata _metadata(String id) => wire.LibraryMetadata(
  packageName: 'test.extension',
  sourceId: id,
  sourceName: 'Source $id',
  sourceLang: 'zh',
  manga: wire.Manga(url: '/manga/$id', title: '作品 $id'),
);
String _key(wire.LibraryMetadata value) => sha256
    .convert(
      utf8.encode(
        jsonEncode([value.packageName, value.sourceId, value.manga.url]),
      ),
    )
    .toString();
ApiReply _reply(GeneratedMessage value) => ApiReply(
  status: 200,
  headers: const {'content-type': 'application/json'},
  body: jsonEncode(wire.encodeProtoJson(value)),
  redirected: false,
);

void main() {
  final source = _metadata('1');
  final target = _metadata('2');
  final sourceKey = _key(source);
  final targetKey = _key(target);
  final identity = ProgressIdentity(
    origin: Uri.parse('https://reader.example'),
    subject: 'owner-subject',
  );
  late TestBusinessServer server;
  late BusinessStateClient client;
  late MigrationRepository repository;
  List<TestBusinessRequest> posts() =>
      server.requests.where((request) => request.method == 'POST').toList();
  List<wire.ChapterMigration> selection() => [
    wire.ChapterMigration(
      sourceChapterKey: 'opaque-original',
      targetChapterKey: 'opaque-target',
      copyRead: true,
      copyBookmark: true,
    ),
  ];
  Future<void> favorite(
    BusinessStateClient owner,
    wire.LibraryMetadata metadata,
    bool value,
  ) => LibraryRepository(owner).setFavorite(
    packageName: metadata.packageName,
    sourceId: metadata.sourceId,
    sourceName: metadata.sourceName,
    sourceLang: metadata.sourceLang,
    manga: metadata.manga,
    favorite: value,
  );
  Future<MigrationPreview> preview({bool Function()? shouldContinue}) =>
      repository.preview(
        sourceKey: sourceKey,
        targetMetadata: target,
        shouldContinue: shouldContinue,
      );
  setUp(() async {
    server = TestBusinessServer();
    client = BusinessStateClient(api: server, identity: identity);
    repository = MigrationRepository(client);
    await favorite(client, source, true);
    await ProgressRepository(client).setChapterRead(
      mangaKey: sourceKey,
      chapterKey: 'opaque-original',
      read: true,
      basedOnRevision: server.manga(sourceKey)!.revision,
    );
    await BookmarkRepository(client).set(
      mangaKey: sourceKey,
      chapterKey: 'opaque-original',
      bookmarked: true,
      basedOnRevision: server.manga(sourceKey)!.revision,
    );
    server.requests.clear();
  });
  tearDown(() => client.dispose());

  test('preview is read-only and frozen; explicit confirmation copies marks without source anchors', () async {
    final original = server.manga(sourceKey)!.deepCopy();
    final value = await preview();
    expect(posts(), isEmpty);
    expect(value.sourceProgress['opaque-original']!.completed, true);
    expect(value.sourceBookmarks, {'opaque-original'});
    expect(() => value.source.favorite = false, throwsUnsupportedError);
    expect(() => value.sourceProgress.clear(), throwsUnsupportedError);
    final result = await repository.commit(value, chapters: selection());
    expect(posts(), hasLength(1));
    expect(result.migration.copiedReadChapters, 1);
    expect(result.migration.copiedBookmarks, 1);
    expect(server.manga(sourceKey), original);
    expect(server.manga(targetKey)!.favorite, true);
    final progress = server.progress(targetKey, 'opaque-target')!;
    expect(progress.completed, true);
    expect(progress.epoch, 1);
    expect(progress.hasCurrent(), false);
    expect(progress.hasFurthest(), false);
    expect(server.manga(targetKey)!.hasResume(), false);
    expect(repository.pending(sourceKey), isNull);
  });

  test(
    'a changed catalog preview stays read-only without hidden shelf refresh',
    () async {
      final remote = BusinessStateClient(api: server, identity: identity);
      addTearDown(remote.dispose);
      await LibraryRepository(remote).createCategory(
        categoryId: '11111111-1111-4111-8111-111111111111',
        name: '远端分类',
        expectedRevision: 0,
      );
      server.requests.clear();
      final value = await preview();
      expect(value.categories.revision, 1);
      expect(posts(), isEmpty);
      expect(
        server.requests.any((request) => request.uri.path == '/api/library'),
        false,
      );
    },
  );

  test(
    'read-only preview also rejects a catalog older than the confirmed session',
    () async {
      await LibraryRepository(client).createCategory(
        categoryId: '22222222-2222-4222-8222-222222222222',
        name: '已确认分类',
        expectedRevision: 0,
      );
      server.requests.clear();
      server.beforeRequest = (request) {
        if (request.uri.path != '/api/state/manga/$sourceKey') return null;
        return _reply(
          wire.MangaStateResponse(
            schemaVersion: 1,
            accountRevision: server.accountRevision,
            manga: server.manga(sourceKey),
            categoryCatalog: wire.CategoryCatalog(),
          ),
        );
      };
      await expectLater(preview(), throwsStateError);
      expect(posts(), isEmpty);
    },
  );

  test('an already issued write accepts its ACK after page invalidation without issuing another mutation', () async {
    final value = await preview();
    var alive = true;
    server.beforeRequest = (request) {
      if (request.method == 'POST') alive = false;
      return null;
    };
    final result = await repository.commit(
      value,
      chapters: selection(),
      shouldContinue: () => alive,
    );
    expect(alive, false);
    expect(result.migration.copiedReadChapters, 1);
    expect(repository.pending(sourceKey), isNull);
    expect(posts(), hasLength(1));
  });

  test(
    'a failed progress page never becomes an assumed unread preview',
    () async {
      server.beforeRequest = (request) {
        if (request.uri.path.endsWith('/progress')) {
          throw StateError('page unavailable');
        }
        return null;
      };
      await expectLater(preview(), throwsStateError);
      expect(posts(), isEmpty);
      expect(
        server.requests.any((request) => request.path.contains(targetKey)),
        false,
      );
    },
  );

  test(
    'separate list reads at different source revisions cannot form a preview',
    () async {
      final remote = BusinessStateClient(api: server, identity: identity);
      addTearDown(remote.dispose);
      var injected = false;
      server.beforeRequest = (request) async {
        if (!injected &&
            request.uri.path == '/api/state/manga/$sourceKey/bookmarks') {
          injected = true;
          await favorite(remote, source, false);
        }
        return null;
      };
      await expectLater(preview(), throwsA(isA<FormatException>()));
      expect(posts(), hasLength(1));
      expect(repository.pending(sourceKey), isNull);
      expect(server.manga(targetKey), isNull);
    },
  );

  for (final suffix in ['progress', 'bookmarks']) {
    test(
      'closing during $suffix pagination prevents the next actual GET',
      () async {
        var alive = true;
        server.beforeRequest = (request) {
          if (request.uri.path != '/api/state/manga/$sourceKey/$suffix') {
            return null;
          }
          alive = false;
          final revision = server.accountRevision;
          return suffix == 'progress'
              ? _reply(
                  wire.ChapterProgressPageResponse(
                    schemaVersion: 1,
                    accountRevision: revision,
                    mangaKey: sourceKey,
                    entries: [
                      wire.ChapterProgressState(
                        chapterKey: 'first',
                        completed: true,
                        epoch: 1,
                      ),
                    ],
                    nextKey: 'first',
                  ),
                )
              : _reply(
                  wire.BookmarkPageResponse(
                    schemaVersion: 1,
                    accountRevision: revision,
                    mangaKey: sourceKey,
                    entries: [
                      wire.ChapterBookmark(
                        chapterKey: 'first',
                        bookmarked: true,
                      ),
                    ],
                    nextKey: 'first',
                  ),
                );
        };
        await expectLater(
          preview(shouldContinue: () => alive),
          throwsStateError,
        );
        final pages = server.requests
            .where((request) => request.uri.path.endsWith('/$suffix'))
            .toList();
        expect(pages, hasLength(1));
        expect(server.requests.last, same(pages.single));
        expect(posts(), isEmpty);
      },
    );
  }

  test('unknown migration survives wrappers and reads, blocks both works and catalog, and retries exact body', () async {
    final value = await preview();
    server.loseNextResponse = true;
    await expectLater(
      repository.commit(value, chapters: selection()),
      throwsStateError,
    );
    final original = posts().single.body;
    final other = MigrationRepository(client);
    expect(other.pending(sourceKey)!.retryable, true);
    expect(() => other.discardRejected(sourceKey), throwsStateError);
    await client.refreshLibrary();
    await client.readManga(sourceKey);
    await client.readManga(targetKey);
    await client.readBookmarks(sourceKey);
    for (final key in [sourceKey, targetKey]) {
      expect(
        () => client.mutate(
          wire.StateMutation(
            mangaKey: key,
            setFavorite: wire.SetFavorite(favorite: false),
          ),
        ),
        throwsA(isA<BusinessPendingMutationException>()),
      );
    }
    expect(
      () => client.mutateCategories(
        wire.CategoryMutation(
          expectedRevision: value.categories.revision,
          createCategory: wire.CreateCategory(
            category: wire.Category(
              id: '33333333-3333-4333-8333-333333333333',
              name: '新分类',
            ),
          ),
        ),
      ),
      throwsStateError,
    );
    expect(posts(), hasLength(1));
    final result = await other.retry(sourceKey);
    expect(posts(), hasLength(2));
    expect(posts().last.body, original);
    expect(result.migration.copiedReadChapters, 1);
    expect(server.appliedMutations, 4);
    expect(other.pending(sourceKey), isNull);
  });

  test(
    'rejected source CAS remains explicit through refresh until discarded',
    () async {
      final value = await preview();
      final remote = BusinessStateClient(api: server, identity: identity);
      addTearDown(remote.dispose);
      await favorite(remote, source, false);
      server.requests.clear();
      await expectLater(
        repository.commit(value, chapters: selection()),
        throwsA(
          isA<BusinessStateException>().having(
            (error) => error.conflict,
            'source conflict',
            true,
          ),
        ),
      );
      expect(repository.pending(sourceKey)!.retryable, false);
      await client.refreshLibrary();
      await client.readManga(sourceKey);
      await client.readManga(targetKey);
      expect(repository.pending(sourceKey)!.retryable, false);
      await expectLater(repository.retry(sourceKey), throwsStateError);
      expect(posts(), hasLength(1));
      repository.discardRejected(sourceKey);
      expect(repository.pending(sourceKey), isNull);
      final refreshed = await preview();
      expect(refreshed.source.revision, server.manga(sourceKey)!.revision);
      expect(server.manga(targetKey), isNull);
    },
  );

  test('a stale idempotent success cannot replace a newer target or clear the rejected draft', () async {
    final value = await preview();
    server.loseNextResponse = true;
    await expectLater(
      repository.commit(value, chapters: selection()),
      throwsStateError,
    );
    final originalBody = posts().single.body;
    final remote = BusinessStateClient(api: server, identity: identity);
    addTearDown(remote.dispose);
    await favorite(remote, target, false);
    final latest = server.manga(targetKey)!;
    await expectLater(
      repository.retry(sourceKey),
      throwsA(
        isA<BusinessStateException>().having(
          (error) => error.conflict,
          'new target is authoritative',
          true,
        ),
      ),
    );
    expect(posts().last.body, originalBody);
    expect(server.manga(targetKey), latest);
    expect((await client.readManga(targetKey)).manga, latest);
    expect(repository.pending(sourceKey)!.retryable, false);
  });

  for (final retry in [false, true]) {
    test(
      'a queued ${retry ? 'retry' : 'confirmation'} cannot POST after its page is invalidated',
      () async {
        final value = await preview();
        if (retry) {
          server.loseNextResponse = true;
          await expectLater(
            repository.commit(value, chapters: selection()),
            throwsStateError,
          );
        }
        final initialPosts = posts().length;
        final entered = Completer<void>();
        final release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        server.beforeRequest = (request) async {
          if (request.uri.path == '/api/categories') {
            entered.complete();
            await release.future;
          }
          return null;
        };
        final heldRead = client.readCategories();
        await entered.future;
        var alive = true;
        final queued = retry
            ? repository.retry(sourceKey, shouldContinue: () => alive)
            : repository.commit(
                value,
                chapters: selection(),
                shouldContinue: () => alive,
              );
        final rejected = expectLater(queued, throwsStateError);
        alive = false;
        release.complete();
        await heldRead;
        await rejected;
        expect(posts(), hasLength(initialPosts));
        expect(repository.pending(sourceKey) != null, retry);
      },
    );
  }

  test('existing target progress and selected false facts are rejected before transmission', () async {
    await ProgressRepository(client).setChapterRead(
      mangaKey: targetKey,
      chapterKey: 'opaque-target',
      read: false,
      basedOnRevision: 0,
    );
    final value = await preview();
    final count = posts().length;
    expect(
      () => repository.commit(value, chapters: selection()),
      throwsA(isA<FormatException>()),
    );
    expect(posts(), hasLength(count));
    expect(server.progress(targetKey, 'opaque-target')!.completed, false);
  });
}
