import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

const _first = '10000000-0000-4000-8000-000000000001';
const _second = '10000000-0000-4000-8000-000000000002';
ProgressIdentity _identity([String subject = 'owner-subject']) =>
    ProgressIdentity(
      origin: Uri.parse('https://reader.example'),
      subject: subject,
    );
BusinessStateClient _client(ApiFetch api, {String subject = 'owner-subject'}) =>
    BusinessStateClient(api: api, identity: _identity(subject));
Future<void> _create(
  LibraryRepository repository, {
  String id = _first,
  int revision = 0,
}) => repository.createCategory(
  categoryId: id,
  name: 'Read',
  expectedRevision: revision,
);
Future<void> _favorite(
  LibraryRepository repository, [
  String url = '/manga/test',
]) => repository.setFavorite(
  packageName: 'eu.kanade.source.test',
  sourceId: '123',
  sourceName: 'Test',
  sourceLang: 'en',
  manga: wire.Manga(url: url, title: 'Test'),
  favorite: true,
);

/// Holds a real component-supplier reply after its write has been committed.
final class _ResponseGate implements ApiFetch {
  _ResponseGate(this.api);
  final ApiFetch api;
  String? path;
  String method = 'GET';
  Completer<void>? received;
  Completer<void>? release;
  void hold(String value, {String verb = 'GET'}) {
    path = value;
    method = verb;
    received = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final shouldHold =
        this.path == Uri.parse(path).path && this.method == method;
    if (shouldHold) this.path = null;
    final reply = await api.fetchApi(
      path,
      method: method,
      headers: headers,
      body: body,
    );
    if (shouldHold) {
      received!.complete();
      await release!.future;
    }
    return reply;
  }
}

void main() {
  for (final loseReply in [false, true]) {
    test(
      'only explicit directory retry sends an uncertain command (lost reply: $loseReply)',
      () async {
        final server = TestBusinessServer();
        final client = _client(server);
        addTearDown(client.dispose);
        final repository = LibraryRepository(client);
        if (loseReply) {
          server.loseNextResponse = true;
        } else {
          server.beforeRequest = (request) {
            if (request.method == 'POST') {
              throw StateError('Injected transport failure');
            }
            return null;
          };
        }
        await expectLater(_create(repository), throwsStateError);
        server.beforeRequest = null;
        final original = server.requests.last.body;
        final requestCount = server.requests.length;
        await expectLater(_create(repository, id: _second), throwsStateError);
        expect(server.requests, hasLength(requestCount));
        expect(server.appliedMutations, loseReply ? 1 : 0);
        await _create(repository);
        expect(
          server.requests
              .where((request) => request.method == 'POST')
              .map((request) => request.body),
          [original, original],
        );
        expect(server.appliedMutations, 1);
        await _create(repository, id: _second, revision: 1);
        expect((await repository.watchView().first).categories, hasLength(2));
      },
    );

    test(
      'metadata and changed membership cannot implicitly retry a category edit (lost reply: $loseReply)',
      () async {
        final server = TestBusinessServer();
        final client = _client(server);
        addTearDown(client.dispose);
        final repository = LibraryRepository(client);
        await _create(repository);
        await _favorite(repository);
        final entry = (await repository.watchEntries().first).single;
        Future<void> edit(List<String> ids) => repository.setCategories(
          mangaKey: entry.mangaKey,
          categoryIds: ids,
          expectedCatalogRevision: 1,
          expectedMangaRevision: entry.revision,
        );
        Future<void> metadata() => repository.refreshMetadata(
          packageName: entry.packageName,
          sourceId: entry.sourceId,
          sourceName: entry.sourceName,
          sourceLang: entry.sourceLang,
          manga: wire.Manga(url: entry.url, title: 'Refreshed'),
        );
        if (loseReply) {
          server.loseNextResponse = true;
        } else {
          server.beforeRequest = (request) {
            if (request.method == 'POST') {
              throw StateError('Injected transport failure');
            }
            return null;
          };
        }
        await expectLater(edit([_first]), throwsStateError);
        server.beforeRequest = null;
        final original = server.requests.last.body;
        final requestCount = server.requests.length;
        await expectLater(metadata(), throwsStateError);
        await expectLater(edit([]), throwsStateError);
        expect(server.requests, hasLength(requestCount));
        expect(server.appliedMutations, loseReply ? 3 : 2);
        await edit([_first]);
        final posts = server.requests
            .where((request) => request.method == 'POST')
            .toList();
        expect(posts[2].body, original);
        expect(posts[3].body, original);
        expect(server.appliedMutations, 3);
        await metadata();
        expect(
          (await repository.watchEntries().first).single.title,
          'Refreshed',
        );
      },
    );
  }
  test(
    'lost category replies retry the exact UUID and body only once',
    () async {
      final server = TestBusinessServer()..loseNextResponse = true;
      final client = _client(server);
      addTearDown(client.dispose);
      final repository = LibraryRepository(client);
      await expectLater(_create(repository), throwsStateError);
      final first = server.requests
          .where((request) => request.method == 'POST')
          .single
          .body;
      await _create(repository);
      expect(
        server.requests
            .where((request) => request.method == 'POST')
            .map((request) => request.body),
        [first, first],
      );
      expect(server.appliedMutations, 1);
      final view = await repository.watchView().first;
      expect(view.categoryRevision, 1);
      expect(view.categories.single.id, _first);
      expect(() => view.categories.clear(), throwsUnsupportedError);
      expect(() => view.entries.clear(), throwsUnsupportedError);
    },
  );

  test(
    'an old creation ACK cannot resurrect a remotely deleted category',
    () async {
      final server = TestBusinessServer()..loseNextResponse = true;
      final client = _client(server);
      final remote = _client(server);
      addTearDown(client.dispose);
      addTearDown(remote.dispose);
      final repository = LibraryRepository(client);
      await expectLater(_create(repository), throwsStateError);
      await LibraryRepository(
        remote,
      ).deleteCategory(categoryId: _first, expectedRevision: 1);
      await expectLater(
        _create(repository),
        throwsA(
          isA<BusinessStateException>().having(
            (error) => error.conflict,
            'stale ACK',
            true,
          ),
        ),
      );
      final view = await repository.watchView().first;
      expect(view.categoryRevision, 2);
      expect(view.categories, isEmpty);
      expect(server.appliedMutations, 2);
    },
  );

  test(
    'deleting a category removes associations and preserves reading state on another device',
    () async {
      final server = TestBusinessServer();
      final client = _client(server);
      final remote = _client(server);
      addTearDown(client.dispose);
      addTearDown(remote.dispose);
      final repository = LibraryRepository(client);
      await _create(repository);
      await _favorite(repository);
      final entry = (await repository.watchEntries().first).single;
      await repository.setCategories(
        mangaKey: entry.mangaKey,
        categoryIds: [_first],
        expectedCatalogRevision: 1,
        expectedMangaRevision: entry.revision,
      );
      final pages = ChapterManifest(
        chapterKey: 'chapter',
        version: 'v1',
        pages: [ReaderPage(key: 'page')],
      );
      await ProgressRepository(client).save(
        mangaKey: entry.mangaKey,
        manifest: pages,
        progress: ChapterProgress(current: pages.positionAt(0, offset: .6)),
        reversedOrder: true,
      );
      final before = server.manga(entry.mangaKey)!;
      await LibraryRepository(
        remote,
      ).deleteCategory(categoryId: _first, expectedRevision: 1);
      final view = await repository.watchView().first;
      expect(view.categories, isEmpty);
      expect(view.entries.single.categoryIds, isEmpty);
      expect(view.entries.single.revision, before.revision + 1);
      expect(view.entries.single.addedAt, entry.addedAt);
      expect(
        (await ProgressRepository(client).loadChapter(
          mangaKey: entry.mangaKey,
          chapterKey: 'chapter',
        ))!.current.normalizedOffset,
        .6,
      );
      expect(
        (await ProgressRepository(
          client,
        ).loadResume(entry.mangaKey))!.reversedOrder,
        true,
      );
      expect(server.progress(entry.mangaKey, 'chapter')!.epoch, 0);
      expect(server.manga(entry.mangaKey)!.favorite, true);
    },
  );

  test(
    'catalog commands progress independently while a manga ACK is delayed',
    () async {
      final server = TestBusinessServer();
      final gate = _ResponseGate(server);
      final client = _client(gate);
      addTearDown(client.dispose);
      final repository = LibraryRepository(client);
      await _create(repository);
      await _favorite(repository);
      final entry = (await repository.watchEntries().first).single;
      gate.hold('/api/state/mutations', verb: 'POST');
      final write = repository.setCategories(
        mangaKey: entry.mangaKey,
        categoryIds: [_first],
        expectedCatalogRevision: 1,
        expectedMangaRevision: entry.revision,
      );
      await gate.received!.future;
      await repository.renameCategory(
        categoryId: _first,
        name: 'Renamed',
        expectedRevision: 1,
      );
      expect(
        (await repository.watchView().first).categories.single.name,
        'Renamed',
      );
      gate.release!.complete();
      await write;
      final view = await repository.watchView().first;
      expect(view.entries.single.categoryIds, [_first]);
      expect(view.categoryRevision, 2);
    },
  );

  test(
    'late association ACK after category deletion cannot restore its ID',
    () async {
      final server = TestBusinessServer();
      final gate = _ResponseGate(server);
      final client = _client(gate);
      final remote = _client(server);
      addTearDown(client.dispose);
      addTearDown(remote.dispose);
      final repository = LibraryRepository(client);
      await _create(repository);
      await _favorite(repository);
      final entry = (await repository.watchEntries().first).single;
      gate.hold('/api/state/mutations', verb: 'POST');
      final write = repository.setCategories(
        mangaKey: entry.mangaKey,
        categoryIds: [_first],
        expectedCatalogRevision: 1,
        expectedMangaRevision: entry.revision,
      );
      final failed = expectLater(
        write,
        throwsA(
          isA<BusinessStateException>().having(
            (error) => error.conflict,
            'stale association',
            true,
          ),
        ),
      );
      await gate.received!.future;
      await LibraryRepository(
        remote,
      ).deleteCategory(categoryId: _first, expectedRevision: 1);
      await repository.refresh();
      gate.release!.complete();
      await failed;
      final view = await repository.watchView().first;
      expect(view.categories, isEmpty);
      expect(view.entries.single.categoryIds, isEmpty);
    },
  );

  test(
    'association edits preserve both dialog CAS values instead of rebasing',
    () async {
      final server = TestBusinessServer();
      final client = _client(server);
      final remote = _client(server);
      addTearDown(client.dispose);
      addTearDown(remote.dispose);
      final repository = LibraryRepository(client);
      await _create(repository);
      await _favorite(repository);
      final entry = (await repository.watchEntries().first).single;
      await LibraryRepository(
        remote,
      ).renameCategory(categoryId: _first, name: 'New', expectedRevision: 1);
      await repository.refresh();
      await expectLater(
        repository.setCategories(
          mangaKey: entry.mangaKey,
          categoryIds: [_first],
          expectedCatalogRevision: 1,
          expectedMangaRevision: entry.revision,
        ),
        throwsA(
          isA<BusinessStateException>().having(
            (error) => error.conflict,
            'catalog CAS',
            true,
          ),
        ),
      );
      final attempted = wire.decodeProtoJson(
        wire.StateMutation(),
        jsonDecode(
          server.requests
              .where((request) => request.uri.path == '/api/state/mutations')
              .last
              .body!,
        ),
      );
      expect(attempted.setCategories.expectedCatalogRevision, 1);
      await repository.refresh();
      await repository.refreshMetadata(
        packageName: entry.packageName,
        sourceId: entry.sourceId,
        sourceName: entry.sourceName,
        sourceLang: entry.sourceLang,
        manga: wire.Manga(url: entry.url, title: 'Refreshed'),
      );
      final posts = server.requests
          .where((request) => request.method == 'POST')
          .length;
      await expectLater(
        repository.setCategories(
          mangaKey: entry.mangaKey,
          categoryIds: [_first],
          expectedCatalogRevision: 2,
          expectedMangaRevision: entry.revision,
        ),
        throwsA(
          isA<BusinessStateException>().having(
            (error) => error.conflict,
            'manga CAS',
            true,
          ),
        ),
      );
      expect(
        server.requests.where((request) => request.method == 'POST'),
        hasLength(posts),
      );
      expect(server.manga(entry.mangaKey)!.categoryIds, isEmpty);
    },
  );

  test(
    'watchView publishes entries and catalog together through a deletion refresh',
    () async {
      final server = TestBusinessServer();
      final gate = _ResponseGate(server);
      final client = _client(gate);
      addTearDown(client.dispose);
      final repository = LibraryRepository(client);
      await _create(repository);
      await _favorite(repository);
      final entry = (await repository.watchEntries().first).single;
      await repository.setCategories(
        mangaKey: entry.mangaKey,
        categoryIds: [_first],
        expectedCatalogRevision: 1,
        expectedMangaRevision: entry.revision,
      );
      final views = <LibraryView>[];
      final updated = Completer<void>();
      final subscription = repository.watchView().listen((view) {
        views.add(view);
        if (view.categoryRevision == 2 && !updated.isCompleted) {
          updated.complete();
        }
      });
      addTearDown(subscription.cancel);
      await repository.refresh();
      gate.hold('/api/library');
      final deleting = repository.deleteCategory(
        categoryId: _first,
        expectedRevision: 1,
      );
      await gate.received!.future;
      expect(views.last.categoryRevision, 1);
      expect(views.last.entries.single.categoryIds, [_first]);
      gate.release!.complete();
      await deleting;
      await updated.future;
      expect(views.last.categoryRevision, 2);
      for (final view in views) {
        expect(
          view.entries.single.categoryIds,
          view.categories.map((category) => category.id).toList(),
        );
      }
      expect(
        () => views.first.entries.single.categoryIds.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'reorder is authoritative and names may repeat across devices',
    () async {
      final server = TestBusinessServer();
      final client = _client(server);
      final remote = _client(server);
      addTearDown(client.dispose);
      addTearDown(remote.dispose);
      final repository = LibraryRepository(client);
      await _create(repository);
      await _create(repository, id: _second, revision: 1);
      await _favorite(repository);
      final entry = (await repository.watchEntries().first).single;
      await repository.setCategories(
        mangaKey: entry.mangaKey,
        categoryIds: [_second, _first],
        expectedCatalogRevision: 2,
        expectedMangaRevision: entry.revision,
      );
      await repository.reorderCategories(
        categoryIds: [_second, _first],
        expectedRevision: 2,
      );
      final view = await LibraryRepository(remote).watchView().first;
      expect(view.categories.map((category) => category.id), [_second, _first]);
      expect(view.categories.map((category) => category.name), [
        'Read',
        'Read',
      ]);
      expect(view.entries.single.categoryIds, [_second, _first]);
      expect(view.entries.single.revision, entry.revision + 1);
    },
  );

  test(
    'closing a subject drops a late category ACK and leaves the next identity isolated',
    () async {
      final server = TestBusinessServer();
      final gate = _ResponseGate(server)
        ..hold('/api/categories/mutations', verb: 'POST');
      final client = _client(gate);
      final write = _create(LibraryRepository(client));
      final failed = expectLater(write, throwsStateError);
      await gate.received!.future;
      await client.dispose();
      final next = _client(server.forSubject('other'), subject: 'other');
      addTearDown(next.dispose);
      expect(
        (await LibraryRepository(next).watchView().first).categories,
        isEmpty,
      );
      gate.release!.complete();
      await failed;
      expect(server.catalog().categories.single.id, _first);
      expect(server.catalog(subject: 'other').categories, isEmpty);
    },
  );

  test(
    'category responses reject invalid IDs, catalogs and oversized bodies',
    () async {
      final server = TestBusinessServer();
      final client = _client(server);
      addTearDown(client.dispose);
      final repository = LibraryRepository(client);
      server.beforeRequest = (request) {
        if (request.uri.path != '/api/categories/mutations') return null;
        return ApiReply(
          status: 200,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(
            wire.encodeProtoJson(
              wire.CategoryMutationResponse(
                schemaVersion: 1,
                mutationId: 'wrong-id',
                accountRevision: 1,
                categoryCatalog: wire.CategoryCatalog(revision: 1),
              ),
            ),
          ),
          redirected: false,
        );
      };
      await expectLater(_create(repository), throwsFormatException);
      server.beforeRequest = (request) => request.uri.path == '/api/categories'
          ? const ApiReply(
              status: 200,
              headers: {'content-type': 'application/json'},
              body:
                  '{"schemaVersion":1,"categoryCatalog":{"categories":[{"id":"invalid","name":"Name"}]}}',
              redirected: false,
            )
          : null;
      await expectLater(client.readCategories(), throwsFormatException);
      server.beforeRequest = (request) => request.uri.path == '/api/categories'
          ? ApiReply(
              status: 200,
              headers: const {'content-type': 'application/json'},
              body: ' ' * (2 * 1024 * 1024 + 1),
              redirected: false,
            )
          : null;
      await expectLater(client.readCategories(), throwsFormatException);
      server.beforeRequest = null;
      expect((await repository.watchView().first).categories, isEmpty);
    },
  );

  test(
    'pagination refuses mismatched catalogs at the same account revision',
    () async {
      final server = TestBusinessServer();
      final client = _client(server);
      addTearDown(client.dispose);
      final repository = LibraryRepository(client);
      for (var i = 0; i < 9; i++) {
        await _favorite(repository, '/manga/$i');
      }
      server.beforeRequest = (request) {
        if (request.uri.path != '/api/library' ||
            !request.uri.queryParameters.containsKey('afterKey')) {
          return null;
        }
        return ApiReply(
          status: 200,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(
            wire.encodeProtoJson(
              wire.LibraryPageResponse(
                schemaVersion: 1,
                accountRevision: server.accountRevision,
                categoryCatalog: wire.CategoryCatalog(
                  revision: 1,
                  categories: [wire.Category(id: _first, name: 'Corrupt')],
                ),
              ),
            ),
          ),
          redirected: false,
        );
      };
      await expectLater(repository.refresh(), throwsFormatException);
      server.beforeRequest = null;
      expect((await repository.watchView().first).entries, hasLength(9));
    },
  );
}
