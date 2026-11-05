import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/reader/reading_progress_controller.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:protobuf/protobuf.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
ProgressIdentity get _identity => ProgressIdentity(
  origin: Uri.parse('https://reader.example'),
  subject: 'owner-subject',
);
ChapterManifest get _pages => ChapterManifest(
  chapterKey: 'chapter',
  version: 'v1',
  pages: [
    ReaderPage(key: 'one'),
    ReaderPage(key: 'two'),
  ],
);
ApiReply _reply(GeneratedMessage value, {int status = 200}) => ApiReply(
  status: status,
  headers: const {'content-type': 'application/json'},
  body: jsonEncode(wire.encodeProtoJson(value, maxBytes: 2 * 1024 * 1024)),
  redirected: false,
);

void main() {
  late TestBusinessServer server;
  late BusinessStateClient client;
  setUp(() {
    server = TestBusinessServer();
    client = BusinessStateClient(api: server, identity: _identity);
  });
  tearDown(() => client.dispose());

  test(
    'favorite retries and shelf refresh cannot clear a reader-owned CAS conflict',
    () async {
      final library = LibraryRepository(client);
      final manga = wire.Manga(url: '/manga/shared-conflict', title: 'Shared');
      Future<void> favorite(bool enabled) => library.setFavorite(
        packageName: 'test.extension',
        sourceId: '123',
        sourceName: 'Test',
        sourceLang: 'en',
        manga: manga,
        favorite: enabled,
      );
      await favorite(true);
      final key = (await library.watchEntries().first).single.mangaKey;
      final writer = ReadingProgressController(
        repository: ProgressRepository(client),
        mangaKey: key,
      );
      addTearDown(writer.dispose);
      await writer.restore(_pages);
      server.failWrites = true;
      writer.observe(
        manifest: _pages,
        current: _pages.positionAt(0),
        reversedOrder: false,
      );
      expect(await writer.flush(), false);
      expect(writer.unsaved, true);
      server.failWrites = false;
      final remote = BusinessStateClient(api: server, identity: _identity);
      addTearDown(remote.dispose);
      await ProgressRepository(remote).save(
        mangaKey: key,
        manifest: _pages,
        progress: ChapterProgress(current: _pages.positionAt(1)),
        reversedOrder: true,
      );
      final progressConflict = throwsA(
        isA<BusinessStateException>()
            .having((failure) => failure.conflict, 'conflict', true)
            .having(
              (failure) => failure.conflictedChapterKey,
              'original chapter',
              'chapter',
            ),
      );
      await expectLater(favorite(false), progressConflict);
      // These are the exact reads performed by the favorite conflict handler
      // and foreground shelf refresh; neither owns the pending reader draft.
      await library.contains(key);
      await library.refresh();
      final requests = server.requests.length;
      expect(await writer.flush(), false);
      expect(server.requests.length, requests);
      expect(writer.error, contains('其他设备更新'));
      expect(writer.unsaved, false);
      expect(server.progress(key, 'chapter')!.current.pageKey, 'two');
      expect(server.appliedMutations, 2);
      await expectLater(favorite(false), progressConflict);
      await writer.restore(_pages);
      await favorite(false);
      expect(server.manga(key)!.favorite, false);
      expect(server.progress(key, 'chapter')!.current.pageKey, 'two');
      expect(server.appliedMutations, 3);
    },
  );

  for (final refreshShelf in [true, false]) {
    test(
      'a lost save cannot be confirmed after remote removal and reset (shelf refreshed=$refreshShelf)',
      () async {
        final library = LibraryRepository(client);
        final manga = wire.Manga(url: '/manga/reset', title: 'Reset');
        Future<void> favorite(LibraryRepository repository, bool enabled) =>
            repository.setFavorite(
              packageName: 'test.extension',
              sourceId: '123',
              sourceName: 'Test',
              sourceLang: 'en',
              manga: manga,
              favorite: enabled,
            );
        await favorite(library, true);
        final key = (await library.watchEntries().first).single.mangaKey;
        final writer = ReadingProgressController(
          repository: ProgressRepository(client),
          mangaKey: key,
        );
        addTearDown(writer.dispose);
        await writer.restore(_pages);
        writer.observe(
          manifest: _pages,
          current: _pages.positionAt(1),
          reversedOrder: true,
        );
        server.loseNextResponse = true;
        expect(await writer.flush(), false);
        expect(writer.unsaved, true);
        final remote = BusinessStateClient(api: server, identity: _identity);
        addTearDown(remote.dispose);
        await favorite(LibraryRepository(remote), false);
        await ProgressRepository(
          remote,
        ).reset(mangaKey: key, manifest: _pages, reversedOrder: false);
        if (refreshShelf) {
          await library.refresh();
        }
        expect(await writer.flush(), false);
        expect(writer.error, contains('其他窗口重置'));
        expect(writer.chapter('chapter')!.epoch, 1);
        expect(server.progress(key, 'chapter')!.epoch, 1);
        expect(server.manga(key)!.favorite, false);
        expect(await library.watchEntries().first, isEmpty);
        expect(server.appliedMutations, 4);
      },
    );
  }

  test(
    'an unrelated account change does not block confirmation of a retried write',
    () async {
      final repository = ProgressRepository(client);
      final draft = ChapterProgress(current: _pages.positionAt(1));
      server.loseNextResponse = true;
      await expectLater(
        repository.save(
          mangaKey: _key,
          manifest: _pages,
          progress: draft,
          reversedOrder: true,
        ),
        throwsStateError,
      );
      final remote = BusinessStateClient(api: server, identity: _identity);
      addTearDown(remote.dispose);
      await LibraryRepository(remote).setFavorite(
        packageName: 'test.extension',
        sourceId: '123',
        sourceName: 'Test',
        sourceLang: 'en',
        manga: wire.Manga(url: '/other', title: 'Other'),
        favorite: true,
      );
      await client.refreshLibrary();
      final confirmed = await repository.save(
        mangaKey: _key,
        manifest: _pages,
        progress: draft,
        reversedOrder: true,
      );
      expect(confirmed.current.pageKey, 'two');
      expect(confirmed.epoch, 0);
      expect(server.appliedMutations, 2);
    },
  );

  test(
    'unsupported schema and redirected responses never populate the cache',
    () async {
      server.beforeRequest = (_) => _reply(
        wire.MangaStateResponse(
          schemaVersion: 2,
          manga: wire.MangaState(mangaKey: _key),
        ),
      );
      await expectLater(client.readManga(_key), throwsFormatException);
      server.beforeRequest = (_) => const ApiReply(
        status: 200,
        headers: {'content-type': 'application/json'},
        body: '{}',
        redirected: true,
      );
      await expectLater(client.readManga(_key), throwsFormatException);
      server.beforeRequest = null;
      expect((await client.readManga(_key)).manga.revision, 0);
    },
  );

  for (final wrongId in [true, false]) {
    test(
      'invalid mutation ${wrongId ? 'ID' : 'chapter'} cannot acknowledge a reset',
      () async {
        final repository = ProgressRepository(client);
        await client.readManga(_key);
        server.beforeRequest = (request) {
          if (request.method != 'POST') return null;
          final mutation = wire.decodeProtoJson(
            wire.StateMutation(),
            jsonDecode(request.body!),
          );
          final chapter = wrongId ? 'chapter' : 'wrong-chapter';
          return _reply(
            wire.StateMutationResponse(
              schemaVersion: 1,
              mutationId: wrongId ? 'wrong-id' : mutation.mutationId,
              accountRevision: 1,
              manga: wire.MangaState(mangaKey: _key, revision: 1),
              progress: wire.ChapterProgressState(
                chapterKey: chapter,
                epoch: 1,
                current: wire.ReadingAnchor(
                  chapterKey: chapter,
                  pageKey: 'one',
                  manifestVersion: 'v1',
                ),
              ),
            ),
          );
        };
        await expectLater(
          repository.reset(
            mangaKey: _key,
            manifest: _pages,
            reversedOrder: false,
          ),
          throwsFormatException,
        );
        final original = server.requests
            .where((request) => request.method == 'POST')
            .single
            .body;
        server.beforeRequest = null;
        expect(
          (await repository.reset(
            mangaKey: _key,
            manifest: _pages,
            reversedOrder: false,
          )).epoch,
          1,
        );
        expect(
          server.requests
              .where((request) => request.method == 'POST')
              .last
              .body,
          original,
        );
        expect(server.appliedMutations, 1);
      },
    );
  }

  test('library conflicts restart only a bounded number of times', () async {
    server.beforeRequest = (request) => request.uri.path == '/api/library'
        ? _reply(
            wire.LibraryPageResponse(
              schemaVersion: 1,
              error: wire.BusinessStateError(
                code: wire
                    .BusinessStateErrorCode
                    .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
                message: 'Changed during pagination',
              ),
            ),
            status: 409,
          )
        : null;
    await expectLater(client.refreshLibrary(), throwsStateError);
    expect(
      server.requests.where((request) => request.uri.path == '/api/library'),
      hasLength(3),
    );
  });

  test(
    'a revision change between library pages discards the partial snapshot',
    () async {
      final library = LibraryRepository(client);
      Future<void> favorite(int i) => library.setFavorite(
        packageName: 'test.extension',
        sourceId: '123',
        sourceName: 'Test',
        sourceLang: 'en',
        manga: wire.Manga(url: '/manga/$i', title: '$i'),
        favorite: true,
      );
      for (var i = 0; i < 9; i++) {
        await favorite(i);
      }
      final remote = BusinessStateClient(api: server, identity: _identity);
      addTearDown(remote.dispose);
      var changed = false;
      server.beforeRequest = (request) async {
        if (!changed &&
            request.uri.path == '/api/library' &&
            request.uri.queryParameters.containsKey('afterKey')) {
          changed = true;
          await LibraryRepository(remote).setFavorite(
            packageName: 'test.extension',
            sourceId: '123',
            sourceName: 'Test',
            sourceLang: 'en',
            manga: wire.Manga(url: '/manga/remote', title: 'Remote'),
            favorite: true,
          );
        }
        return null;
      };
      expect(await library.watchEntries().first, hasLength(10));
      expect(changed, true);
      expect(
        server.requests.where((request) => request.uri.path == '/api/library'),
        hasLength(4),
      );
    },
  );

  test(
    'an old idempotent success cannot acknowledge a view after a known remote reset',
    () async {
      final repository = ProgressRepository(client);
      final draft = ChapterProgress(current: _pages.positionAt(1));
      server.loseNextResponse = true;
      await expectLater(
        repository.save(
          mangaKey: _key,
          manifest: _pages,
          progress: draft,
          reversedOrder: true,
        ),
        throwsStateError,
      );
      final remote = BusinessStateClient(api: server, identity: _identity);
      addTearDown(remote.dispose);
      await ProgressRepository(
        remote,
      ).reset(mangaKey: _key, manifest: _pages, reversedOrder: false);
      expect(
        (await repository.loadChapter(
          mangaKey: _key,
          chapterKey: 'chapter',
        ))!.epoch,
        1,
      );
      await expectLater(
        repository.save(
          mangaKey: _key,
          manifest: _pages,
          progress: draft,
          reversedOrder: true,
        ),
        throwsA(
          isA<BusinessStateException>().having(
            (error) => error.conflict,
            'stale confirmation',
            true,
          ),
        ),
      );
      expect(server.progress(_key, 'chapter')!.epoch, 1);
      expect(server.appliedMutations, 2);
    },
  );
}
