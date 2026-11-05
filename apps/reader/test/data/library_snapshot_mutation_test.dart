import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/bookmark_repository.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

const _categoryId = '10000000-0000-4000-8000-000000000001';
wire.Manga get _manga => wire.Manga(
  url: '/manga/snapshot',
  title: 'Current Source metadata',
  author: 'Author',
  memoJson: '{"opaque":"retained"}',
);
String get _mangaKey => ChapterSequence(
  packageName: 'source.test',
  sourceId: '123',
  mangaUrl: _manga.url,
  chapters: const [],
).mangaKey;

BusinessStateClient _client(ApiFetch api) => BusinessStateClient(
  api: api,
  identity: ProgressIdentity(
    origin: Uri.parse('https://reader.example'),
    subject: 'owner-subject',
  ),
);

Future<void> _favorite(LibraryRepository library) => library.setFavorite(
  packageName: 'source.test',
  sourceId: '123',
  sourceName: 'Source',
  sourceLang: 'zh',
  manga: _manga,
  favorite: true,
);
Future<void> _createCategory(LibraryRepository library) => library
    .createCategory(categoryId: _categoryId, name: 'Read', expectedRevision: 0);
Future<LibraryEntry> _entry(LibraryRepository library) async =>
    (await library.watchEntries().first).single;

ChapterManifest get _manifest => ChapterManifest(
  chapterKey: 'chapter',
  version: 'manifest',
  pages: [ReaderPage(key: 'one')],
);
Future<void> _saveProgress(BusinessStateClient client) async {
  final manifest = _manifest;
  await ProgressRepository(client).save(
    mangaKey: _mangaKey,
    manifest: manifest,
    progress: ChapterProgress(
      current: manifest.positionAt(0, offset: .35),
      furthest: manifest.positionAt(0, offset: .7),
    ),
    reversedOrder: true,
  );
}

List<TestBusinessRequest> _posts(TestBusinessServer server) => server.requests
    .where(
      (request) =>
          request.method == 'POST' &&
          request.uri.path == '/api/state/mutations',
    )
    .toList();

Matcher get _pending => isA<BusinessPendingMutationException>().having(
  (error) => error.mangaKey,
  'mangaKey',
  _mangaKey,
);
Matcher get _conflict => isA<BusinessStateException>().having(
  (error) => error.conflict,
  'revision conflict',
  true,
);

enum _AckFault { revision, favorite, categories }

/// Corrupts one committed mutation ACK, leaving the supplier's state and
/// idempotency record intact so the same original command can be retried.
final class _InvalidAck implements ApiFetch {
  _InvalidAck(this.server, this.fault);
  final TestBusinessServer server;
  final _AckFault fault;
  bool enabled = false;

  @override
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final reply = await server.fetchApi(
      path,
      method: method,
      headers: headers,
      body: body,
    );
    if (!enabled || method != 'POST' || path != '/api/state/mutations') {
      return reply;
    }
    enabled = false;
    final value = wire.decodeProtoJson(
      wire.StateMutationResponse(),
      jsonDecode(reply.body),
    );
    switch (fault) {
      case _AckFault.revision:
        value.manga.revision++;
        if (value.accountRevision < value.manga.revision) {
          value.accountRevision = value.manga.revision;
        }
      case _AckFault.favorite:
        value.manga.favorite = !value.manga.favorite;
      case _AckFault.categories:
        value.manga.categoryIds.clear();
    }
    return ApiReply(
      status: reply.status,
      headers: reply.headers,
      body: jsonEncode(wire.encodeProtoJson(value)),
      redirected: reply.redirected,
    );
  }
}

void main() {
  late TestBusinessServer server;
  late BusinessStateClient client;
  late LibraryRepository library;
  setUp(() {
    server = TestBusinessServer();
    client = _client(server);
    library = LibraryRepository(client);
  });
  tearDown(() => client.dispose());

  test(
    'exact commands require a valid confirmed revision before transport',
    () {
      final operation = wire.StateMutation(
        mangaKey: _mangaKey,
        setFavorite: wire.SetFavorite(favorite: false),
      );
      expect(
        () => client.mutate(operation, requireExactRevision: true),
        throwsArgumentError,
      );
      for (final revision in [-1, 0x100000000]) {
        expect(
          () => client.mutate(
            operation,
            basedOnRevision: revision,
            requireExactRevision: true,
          ),
          throwsFormatException,
        );
      }
      expect(server.requests, isEmpty);
    },
  );

  test(
    'shelf commands do not adopt progress written after their snapshot',
    () async {
      await _favorite(library);
      await _createCategory(library);
      final entry = await _entry(library);
      await _saveProgress(client);
      final posts = _posts(server).length;
      await expectLater(
        library.setCategories(
          mangaKey: _mangaKey,
          categoryIds: [_categoryId],
          expectedCatalogRevision: 1,
          expectedMangaRevision: entry.revision,
        ),
        throwsA(_conflict),
      );
      await expectLater(
        library.removeFavorite(
          mangaKey: _mangaKey,
          expectedMangaRevision: entry.revision,
        ),
        throwsA(_conflict),
      );
      expect(_posts(server), hasLength(posts));
      expect(server.manga(_mangaKey)!.favorite, true);
      expect(server.manga(_mangaKey)!.categoryIds, isEmpty);
    },
  );

  for (final previous in ['favorite', 'progress']) {
    test(
      'exact shelf edits do not resend a pending $previous command',
      () async {
        await _favorite(library);
        final entry = await _entry(library);
        Future<void> previousCommand() async {
          if (previous == 'favorite') {
            await client.mutate(
              wire.StateMutation(
                mangaKey: _mangaKey,
                setFavorite: wire.SetFavorite(favorite: false),
              ),
            );
          } else {
            await _saveProgress(client);
          }
        }

        server.loseNextResponse = true;
        await expectLater(previousCommand(), throwsStateError);
        final original = _posts(server).last.body;
        final requests = server.requests.length;
        await expectLater(
          library.removeFavorite(
            mangaKey: _mangaKey,
            expectedMangaRevision: entry.revision,
          ),
          throwsA(_pending),
        );
        await expectLater(
          library.setCategories(
            mangaKey: _mangaKey,
            categoryIds: const [],
            expectedCatalogRevision: 0,
            expectedMangaRevision: entry.revision,
          ),
          throwsA(_pending),
        );
        expect(server.requests, hasLength(requests));
        final applied = server.appliedMutations;
        await previousCommand();
        expect(_posts(server).last.body, original);
        expect(server.appliedMutations, applied);
      },
    );
  }

  test(
    'an exact pending edit only accepts its same payload revision and mode',
    () async {
      await _favorite(library);
      await _createCategory(library);
      final entry = await _entry(library);
      Future<void> original() => library.setCategories(
        mangaKey: _mangaKey,
        categoryIds: [_categoryId],
        expectedCatalogRevision: 1,
        expectedMangaRevision: entry.revision,
      );
      server.loseNextResponse = true;
      await expectLater(original(), throwsStateError);
      final body = _posts(server).last.body;
      final requests = server.requests.length;
      for (final retry in <Future<void> Function()>[
        () => library.removeFavorite(
          mangaKey: _mangaKey,
          expectedMangaRevision: entry.revision,
        ),
        () => library.setCategories(
          mangaKey: _mangaKey,
          categoryIds: [_categoryId],
          expectedCatalogRevision: 1,
          expectedMangaRevision: entry.revision + 1,
        ),
        () async {
          await client.mutate(
            wire.StateMutation(
              mangaKey: _mangaKey,
              setCategories: wire.SetCategories(
                categoryIds: [_categoryId],
                expectedCatalogRevision: 1,
              ),
            ),
            basedOnRevision: entry.revision,
          );
        },
        () => _favorite(library),
        () => _saveProgress(client),
      ]) {
        await expectLater(retry(), throwsA(_pending));
      }
      expect(server.requests, hasLength(requests));
      final applied = server.appliedMutations;
      await original();
      expect(_posts(server).last.body, body);
      expect(server.appliedMutations, applied);
    },
  );

  test(
    'lost removal retries its UUID without replacing metadata or deleting reading state',
    () async {
      await _favorite(library);
      await _createCategory(library);
      var entry = await _entry(library);
      await library.setCategories(
        mangaKey: _mangaKey,
        categoryIds: [_categoryId],
        expectedCatalogRevision: 1,
        expectedMangaRevision: entry.revision,
      );
      await _saveProgress(client);
      final bookmarks = BookmarkRepository(client);
      final bookmark = await bookmarks.loadChapter(
        mangaKey: _mangaKey,
        chapterKey: 'chapter',
      );
      await bookmarks.set(
        mangaKey: _mangaKey,
        chapterKey: 'chapter',
        bookmarked: true,
        basedOnRevision: bookmark.revision,
      );
      entry = await _entry(library);
      final before = server.manga(_mangaKey)!;
      final progress = server.progress(_mangaKey, 'chapter')!;
      Future<void> remove() => library.removeFavorite(
        mangaKey: _mangaKey,
        expectedMangaRevision: entry.revision,
      );
      server.loseNextResponse = true;
      await expectLater(remove(), throwsStateError);
      final original = _posts(server).last.body;
      final command = wire.decodeProtoJson(
        wire.StateMutation(),
        jsonDecode(original!),
      );
      expect(command.setFavorite.hasMetadata(), false);
      expect(command.setFavorite.favorite, false);
      expect(server.manga(_mangaKey)!.favorite, false);
      // A shelf refresh may evict the removed favorite from the session cache;
      // the pending original command must still retain its transport identity.
      await library.refresh();
      final applied = server.appliedMutations;
      await remove();
      expect(_posts(server).last.body, original);
      expect(server.appliedMutations, applied);
      final after = server.manga(_mangaKey)!;
      expect(after.metadata, before.metadata);
      expect(after.categoryIds, before.categoryIds);
      expect(after.resume, before.resume);
      expect(server.progress(_mangaKey, 'chapter'), progress);
      expect(server.bookmarked(_mangaKey, 'chapter'), true);
      expect(await library.watchEntries().first, isEmpty);
    },
  );

  test(
    'an ACK followed by a failed catalog shelf read retains the original UUID',
    () async {
      await _favorite(library);
      await _createCategory(library);
      final entry = await _entry(library);
      final remote = _client(server);
      addTearDown(remote.dispose);
      await LibraryRepository(remote).renameCategory(
        categoryId: _categoryId,
        name: 'Renamed remotely',
        expectedRevision: 1,
      );
      server.beforeRequest = (request) {
        if (request.method == 'GET' && request.uri.path == '/api/library') {
          throw StateError('Injected catalog shelf read failure');
        }
        return null;
      };
      Future<void> remove() => library.removeFavorite(
        mangaKey: _mangaKey,
        expectedMangaRevision: entry.revision,
      );
      await expectLater(remove(), throwsStateError);
      final original = _posts(server).last.body;
      expect(server.manga(_mangaKey)!.favorite, false);
      final applied = server.appliedMutations;
      server.beforeRequest = null;
      await remove();
      expect(_posts(server).last.body, original);
      expect(server.appliedMutations, applied);
      expect(await library.watchEntries().first, isEmpty);
    },
  );

  for (final fault in _AckFault.values) {
    test(
      'an exact mutation rejects a wrong ${fault.name} ACK and retries the original body',
      () async {
        final api = _InvalidAck(server, fault);
        await client.dispose();
        client = _client(api);
        library = LibraryRepository(client);
        await _favorite(library);
        await _createCategory(library);
        final entry = await _entry(library);
        Future<void> save() => fault == _AckFault.categories
            ? library.setCategories(
                mangaKey: _mangaKey,
                categoryIds: [_categoryId],
                expectedCatalogRevision: 1,
                expectedMangaRevision: entry.revision,
              )
            : library.removeFavorite(
                mangaKey: _mangaKey,
                expectedMangaRevision: entry.revision,
              );
        api.enabled = true;
        await expectLater(save(), throwsFormatException);
        final original = _posts(server).last.body;
        final applied = server.appliedMutations;
        await save();
        expect(_posts(server).last.body, original);
        expect(server.appliedMutations, applied);
      },
    );
  }
}
