import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/bookmark_repository.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/business_state_validation.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:protobuf/protobuf.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
ProgressIdentity _identity([String subject = 'owner-subject']) =>
    ProgressIdentity(
      origin: Uri.parse('https://reader.example'),
      subject: subject,
    );
BusinessStateClient _client(ApiFetch api, {String subject = 'owner-subject'}) =>
    BusinessStateClient(api: api, identity: _identity(subject));
ChapterManifest get _manifest => ChapterManifest(
  chapterKey: 'chapter',
  version: 'version',
  pages: [
    ReaderPage(key: 'first'),
    ReaderPage(key: 'second'),
  ],
);
ApiReply _reply(GeneratedMessage value) => ApiReply(
  status: 200,
  headers: const {'content-type': 'application/json'},
  body: jsonEncode(wire.encodeProtoJson(value, maxBytes: 2 * 1024 * 1024)),
  redirected: false,
);
Future<void> _saveProgress(BusinessStateClient client, String key) =>
    ProgressRepository(client).saveState(
      mangaKey: key,
      manifest: _manifest,
      progress: ChapterProgress(current: _manifest.positionAt(1)),
      reversedOrder: false,
    );

void main() {
  late TestBusinessServer server;
  late BusinessStateClient client;
  late BookmarkRepository repository;
  setUp(() {
    server = TestBusinessServer();
    client = _client(server);
    repository = BookmarkRepository(client);
  });
  tearDown(() => client.dispose());

  test(
    'unfavorited chapters expose explicit false and confirmed true/false',
    () async {
      final initial = await repository.loadChapter(
        mangaKey: _key,
        chapterKey: 'chapter',
      );
      expect(initial.revision, 0);
      expect(initial.bookmarked, isFalse);
      final saved = await repository.set(
        mangaKey: _key,
        chapterKey: 'chapter',
        bookmarked: true,
        basedOnRevision: initial.revision,
      );
      expect(saved.bookmarked, isTrue);
      expect(saved.revision, 1);
      expect(server.manga(_key)!.favorite, isFalse);
      expect(server.manga(_key)!.hasMetadata(), isFalse);
      expect((await repository.loadAll(_key)).chapterKeys, {'chapter'});
      final cleared = await repository.set(
        mangaKey: _key,
        chapterKey: 'chapter',
        bookmarked: false,
        basedOnRevision: saved.revision,
      );
      expect(cleared.bookmarked, isFalse);
      expect(cleared.revision, 2);
      expect((await repository.loadAll(_key)).chapterKeys, isEmpty);
      expect(
        (await repository.loadChapter(
          mangaKey: _key,
          chapterKey: 'chapter',
        )).bookmarked,
        isFalse,
      );
    },
  );

  test(
    'local confirmed progress may advance CAS; reset and unfavorite preserve bookmarks',
    () async {
      final library = LibraryRepository(client);
      final manga = wire.Manga(url: '/manga/bookmarks', title: 'Bookmarks');
      Future<void> favorite(bool value) => library.setFavorite(
        packageName: 'source.test',
        sourceId: '123',
        sourceName: 'Test',
        sourceLang: 'en',
        manga: manga,
        favorite: value,
      );
      await favorite(true);
      final key = (await library.watchEntries().first).single.mangaKey;
      final view = await repository.loadAll(key);
      await _saveProgress(client, key);
      final saved = await repository.set(
        mangaKey: key,
        chapterKey: 'chapter',
        bookmarked: true,
        basedOnRevision: view.revision,
      );
      final request = wire.decodeProtoJson(
        wire.StateMutation(),
        jsonDecode(server.requests.lastWhere((r) => r.method == 'POST').body!),
      );
      expect(request.expectedRevision, view.revision + 1);
      expect(saved.revision, view.revision + 2);
      await ProgressRepository(
        client,
      ).resetState(mangaKey: key, manifest: _manifest, reversedOrder: false);
      await favorite(false);
      expect((await repository.loadAll(key)).chapterKeys, {'chapter'});
      expect(server.progress(key, 'chapter')!.current.pageKey, 'first');
      expect(server.manga(key)!.favorite, isFalse);
    },
  );

  test(
    'observed remote writes reject an old view and reload clears only rejected bookmark commands',
    () async {
      final initial = await repository.loadAll(_key);
      final other = _client(server);
      addTearDown(other.dispose);
      await _saveProgress(other, _key);
      await expectLater(
        repository.set(
          mangaKey: _key,
          chapterKey: 'chapter',
          bookmarked: true,
          basedOnRevision: initial.revision,
        ),
        throwsA(
          isA<BusinessStateException>().having(
            (e) => e.conflict,
            'conflict',
            true,
          ),
        ),
      );
      expect(repository.pending(_key)!.retryable, isFalse);
      final before = server.appliedMutations;
      final fresh = await repository.loadAll(_key);
      expect(server.appliedMutations, before);
      expect(repository.pending(_key), isNull);
      final writes = server.requests.where((r) => r.method == 'POST').length;
      await expectLater(
        repository.set(
          mangaKey: _key,
          chapterKey: 'chapter',
          bookmarked: true,
          basedOnRevision: initial.revision,
        ),
        throwsA(
          isA<BusinessStateException>().having(
            (e) => e.conflict,
            'observed remote revision',
            true,
          ),
        ),
      );
      expect(server.requests.where((r) => r.method == 'POST').length, writes);
      await repository.set(
        mangaKey: _key,
        chapterKey: 'chapter',
        bookmarked: true,
        basedOnRevision: fresh.revision,
      );
    },
  );

  for (final loseReply in [false, true]) {
    test(
      'only the explicit pending bookmark retries exact UUID and body (lost reply: $loseReply)',
      () async {
        final initial = await repository.loadAll(_key);
        if (loseReply) {
          server.loseNextResponse = true;
        } else {
          server.beforeRequest = (request) {
            if (request.method == 'POST') {
              throw StateError('Before-send failure');
            }
            return null;
          };
        }
        Future<BookmarkSnapshot> save() => repository.set(
          mangaKey: _key,
          chapterKey: 'chapter',
          bookmarked: true,
          basedOnRevision: initial.revision,
        );
        await expectLater(save(), throwsStateError);
        server.beforeRequest = null;
        final original = server.requests
            .lastWhere((r) => r.method == 'POST')
            .body;
        expect(repository.pending(_key)!.retryable, isTrue);
        expect(repository.pending(_key)!.chapterKey, 'chapter');
        final requests = server.requests.length;
        await expectLater(
          repository.set(
            mangaKey: _key,
            chapterKey: 'another',
            bookmarked: true,
            basedOnRevision: initial.revision,
          ),
          throwsStateError,
        );
        await expectLater(
          repository.set(
            mangaKey: _key,
            chapterKey: 'chapter',
            bookmarked: false,
            basedOnRevision: initial.revision,
          ),
          throwsStateError,
        );
        await expectLater(_saveProgress(client, _key), throwsStateError);
        await expectLater(
          client.mutate(
            wire.StateMutation(
              mangaKey: _key,
              setFavorite: wire.SetFavorite(favorite: false),
            ),
          ),
          throwsStateError,
        );
        expect(server.requests.length, requests);
        await repository.loadAll(_key);
        expect(repository.pending(_key)!.retryable, isTrue);
        expect((await save()).bookmarked, isTrue);
        final bodies = server.requests
            .where((r) => r.method == 'POST')
            .map((r) => r.body)
            .toList();
        expect(bodies, [original, original]);
        expect(server.appliedMutations, 1);
        expect(repository.pending(_key), isNull);
      },
    );
  }

  test(
    'a historical ACK cannot confirm a bookmark removed by another device',
    () async {
      await repository.loadAll(_key);
      server.loseNextResponse = true;
      Future<BookmarkSnapshot> save() => repository.set(
        mangaKey: _key,
        chapterKey: 'chapter',
        bookmarked: true,
        basedOnRevision: 0,
      );
      await expectLater(save(), throwsStateError);
      final other = _client(server);
      addTearDown(other.dispose);
      final remote = BookmarkRepository(other);
      final current = await remote.loadChapter(
        mangaKey: _key,
        chapterKey: 'chapter',
      );
      await remote.set(
        mangaKey: _key,
        chapterKey: 'chapter',
        bookmarked: false,
        basedOnRevision: current.revision,
      );
      await expectLater(
        save(),
        throwsA(
          isA<BusinessStateException>()
              .having((e) => e.conflict, 'conflict', true)
              .having((e) => e.bookmark?.bookmarked, 'current bookmark', false),
        ),
      );
      expect(repository.pending(_key)!.retryable, isFalse);
      final fresh = await repository.loadAll(_key);
      expect(fresh.chapterKeys, isEmpty);
      expect(repository.pending(_key), isNull);
      await repository.set(
        mangaKey: _key,
        chapterKey: 'chapter',
        bookmarked: true,
        basedOnRevision: fresh.revision,
      );
    },
  );

  test(
    'a historical ACK with unchanged bookmark returns the current manga revision',
    () async {
      await repository.loadAll(_key);
      server.loseNextResponse = true;
      Future<BookmarkSnapshot> save() => repository.set(
        mangaKey: _key,
        chapterKey: 'chapter',
        bookmarked: true,
        basedOnRevision: 0,
      );
      await expectLater(save(), throwsStateError);
      final other = _client(server);
      addTearDown(other.dispose);
      await _saveProgress(other, _key);
      final result = await save();
      expect(result.bookmarked, isTrue);
      expect(result.revision, 2);
      expect(repository.pending(_key), isNull);
    },
  );

  test(
    'pagination restarts its entire snapshot on account revision changes',
    () async {
      var revision = 0;
      for (var i = 0; i < 65; i++) {
        revision = (await repository.set(
          mangaKey: _key,
          chapterKey: 'chapter-${i.toString().padLeft(3, '0')}',
          bookmarked: true,
          basedOnRevision: revision,
        )).revision;
      }
      final other = _client(server);
      addTearDown(other.dispose);
      var changed = false;
      server.beforeRequest = (request) async {
        if (!changed &&
            request.uri.path.endsWith('/bookmarks') &&
            request.uri.queryParameters.containsKey('afterKey')) {
          changed = true;
          final remote = BookmarkRepository(other);
          final current = await remote.loadChapter(
            mangaKey: _key,
            chapterKey: 'new',
          );
          await remote.set(
            mangaKey: _key,
            chapterKey: 'new',
            bookmarked: true,
            basedOnRevision: current.revision,
          );
        }
        return null;
      };
      final value = await repository.loadAll(_key);
      expect(changed, isTrue);
      expect(value.chapterKeys, hasLength(66));
      expect(value.chapterKeys, contains('new'));
      expect(value.revision, 66);
      expect(value.accountRevision, 66);
      final pages = server.requests.where(
        (r) => r.uri.path.endsWith('/bookmarks'),
      );
      expect(
        pages
            .where((r) => !r.uri.queryParameters.containsKey('afterKey'))
            .map((r) => r.uri.queryParameters['revision']),
        ['65', '66'],
      );
    },
  );

  test(
    'bookmark pages enforce identity, saved flags, budgets and UTF-8 cursor order',
    () {
      wire.BookmarkPageResponse page(Iterable<String> keys) =>
          wire.BookmarkPageResponse(
            schemaVersion: 1,
            mangaKey: _key,
            entries: keys.map(
              (key) => wire.ChapterBookmark(chapterKey: key, bookmarked: true),
            ),
          );
      final ordered = page(['\uE000', '😀']);
      expect(
        () => validateBusinessBookmarkPage(ordered, mangaKey: _key),
        returnsNormally,
      );
      for (final value in [
        page(['chapter'])..mangaKey = 'b' * 64,
        page(['chapter'])..entries.first.bookmarked = false,
        page(['chapter', 'chapter']),
        page(['b', 'a']),
        page(['😀', '\uE000']),
        page(['chapter'])..nextKey = 'different',
        page(List.generate(65, (i) => 'chapter-$i')),
      ]) {
        expect(
          () => validateBusinessBookmarkPage(value, mangaKey: _key),
          throwsFormatException,
        );
      }
      expect(
        () => validateBusinessBookmarkPage(
          page(['a']),
          mangaKey: _key,
          afterKey: 'a',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'wrong or missing bookmark ACK stays unconfirmed; requested GET requires explicit bookmark',
    () async {
      await repository.loadAll(_key);
      server.beforeRequest = (request) {
        if (request.method != 'POST') return null;
        final mutation = wire.decodeProtoJson(
          wire.StateMutation(),
          jsonDecode(request.body!),
        );
        return _reply(
          wire.StateMutationResponse(
            schemaVersion: 1,
            mutationId: mutation.mutationId,
            accountRevision: 1,
            manga: wire.MangaState(mangaKey: _key, revision: 1),
            categoryCatalog: wire.CategoryCatalog(),
            bookmark: wire.ChapterBookmark(
              chapterKey: 'wrong',
              bookmarked: true,
            ),
          ),
        );
      };
      await expectLater(
        repository.set(
          mangaKey: _key,
          chapterKey: 'chapter',
          bookmarked: true,
          basedOnRevision: 0,
        ),
        throwsFormatException,
      );
      expect(repository.pending(_key)!.retryable, isTrue);
      server.beforeRequest = (request) => _reply(
        wire.MangaStateResponse(
          schemaVersion: 1,
          manga: wire.MangaState(mangaKey: _key),
          categoryCatalog: wire.CategoryCatalog(),
        ),
      );
      await expectLater(
        repository.loadChapter(mangaKey: _key, chapterKey: 'chapter'),
        throwsFormatException,
      );
    },
  );

  test(
    'subjects stay isolated and a closed session drops its late ACK and pending draft',
    () async {
      await repository.loadAll(_key);
      final started = Completer<void>();
      final release = Completer<void>();
      server.beforeRequest = (request) async {
        if (request.method == 'POST') {
          started.complete();
          await release.future;
        }
        return null;
      };
      final saving = repository.set(
        mangaKey: _key,
        chapterKey: 'chapter',
        bookmarked: true,
        basedOnRevision: 0,
      );
      final rejected = expectLater(saving, throwsStateError);
      await started.future;
      await client.dispose();
      expect(repository.pending(_key), isNull);
      release.complete();
      await rejected;
      server.beforeRequest = null;
      final other = _client(server.forSubject('other'), subject: 'other');
      addTearDown(other.dispose);
      expect(
        (await BookmarkRepository(other).loadAll(_key)).chapterKeys,
        isEmpty,
      );
      expect(server.bookmarked(_key, 'chapter'), isTrue);
      expect(
        () => other.rebindApi(server, verifiedIdentity: _identity()),
        throwsArgumentError,
      );
    },
  );
}
