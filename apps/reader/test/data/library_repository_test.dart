import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

wire.Manga manga({String title = 'Original', String url = '/manga/42'}) =>
    wire.Manga(
      title: title,
      url: url,
      author: 'Author',
      artist: 'Artist',
      description: 'Description',
      genres: ['science', 'fiction'],
      status: 2,
      thumbnailUrl: 'https://image.example/42.jpg',
      initialized: true,
      updateStrategy: 'ALWAYS_UPDATE',
      memoJson: '{"id":9223372036854775807,"url":"/manga/42"}',
    );

Future<void> favorite(
  LibraryRepository repository, {
  wire.Manga? value,
  bool enabled = true,
  String packageName = 'test.extension',
  String sourceId = '1234567890123456789',
}) => repository.setFavorite(
  packageName: packageName,
  sourceId: sourceId,
  sourceName: 'Test Source',
  sourceLang: 'en',
  manga: value ?? manga(),
  favorite: enabled,
);

BusinessStateClient client(
  TestBusinessServer server, {
  String subject = 'owner-subject',
  String origin = 'https://reader.example',
}) => BusinessStateClient(
  api: server.forSubject(subject),
  identity: ProgressIdentity(origin: Uri.parse(origin), subject: subject),
);

void main() {
  test('a second device reads a confirmed full Source snapshot', () async {
    final now = DateTime.utc(2026, 11, 5, 9, 10, 11);
    final server = TestBusinessServer(now: () => now);
    final first = client(server);
    final second = client(server);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final original = manga();
    await favorite(LibraryRepository(first), value: original);
    final saved = (await LibraryRepository(second).watchEntries().first).single;
    expect(saved.addedAt, now);
    expect(saved.snapshot.isFrozen, true);
    expect(
      wire.encodeProtoJson(saved.snapshot),
      wire.encodeProtoJson(original),
    );
    expect(saved.snapshot.memoJson, contains('9223372036854775807'));
    expect(
      saved.mangaKey,
      ChapterSequence(
        packageName: saved.packageName,
        sourceId: saved.sourceId,
        mangaUrl: saved.url,
        chapters: const [],
      ).mangaKey,
    );
    original.title = 'Mutated caller';
    expect(saved.title, 'Original');
    expect(
      server.requests.every(
        (request) => request.headers['X-App-Subject'] == 'owner-subject',
      ),
      true,
    );
  });

  test(
    'favorite and progress share revisions and removal keeps progress',
    () async {
      final server = TestBusinessServer();
      final shared = client(server);
      addTearDown(shared.dispose);
      final library = LibraryRepository(shared);
      await favorite(library);
      final entry = (await library.watchEntries().first).single;
      expect(entry.resume, isNull);
      final pages = ChapterManifest(
        chapterKey: 'chapter',
        version: 'v1',
        pages: [ReaderPage(key: 'one')],
      );
      final progress = ProgressRepository(shared);
      await progress.save(
        mangaKey: entry.mangaKey,
        manifest: pages,
        progress: ChapterProgress(current: pages.positionAt(0, offset: .7)),
        reversedOrder: true,
      );
      final confirmed = (await library.watchEntries().first).single;
      expect(confirmed.resume!.chapterKey, 'chapter');
      expect(confirmed.resume!.reversedOrder, true);
      // A previous shelf projection remains an immutable confirmed snapshot.
      expect(entry.resume, isNull);
      final second = client(server);
      addTearDown(second.dispose);
      final remote = (await LibraryRepository(
        second,
      ).watchEntries().first).single;
      expect(remote.resume!.chapterKey, confirmed.resume!.chapterKey);
      expect(remote.resume!.reversedOrder, true);
      final updates = StreamIterator(library.watchFavorite(entry.mangaKey));
      addTearDown(updates.cancel);
      expect(await updates.moveNext(), true);
      expect(updates.current, true);
      await favorite(library, enabled: false);
      expect(await updates.moveNext(), true);
      expect(updates.current, false);
      expect(await library.watchEntries().first, isEmpty);
      expect(
        (await progress.loadChapter(
          mangaKey: entry.mangaKey,
          chapterKey: 'chapter',
        ))!.current.normalizedOffset,
        .7,
      );
      expect((await progress.loadResume(entry.mangaKey))!.reversedOrder, true);
      expect(server.manga(entry.mangaKey)!.revision, 3);
    },
  );

  test(
    'metadata refresh and repeat favorite retain server added time',
    () async {
      var now = DateTime.utc(2026, 11, 5);
      final server = TestBusinessServer(now: () => now);
      final shared = client(server);
      addTearDown(shared.dispose);
      final repository = LibraryRepository(shared);
      await favorite(repository);
      final addedAt = now;
      now = now.add(const Duration(days: 1));
      await favorite(repository, value: manga(title: 'Updated'));
      await repository.refreshMetadata(
        packageName: 'test.extension',
        sourceId: '1234567890123456789',
        sourceName: 'Renamed',
        sourceLang: 'zh',
        manga: manga(title: 'Refreshed'),
      );
      final saved = (await repository.watchEntries().first).single;
      expect(saved.title, 'Refreshed');
      expect(saved.sourceName, 'Renamed');
      expect(saved.addedAt, addedAt);
    },
  );

  test('library resume projection rejects an invalid chapter identity', () {
    expect(
      () => LibraryEntry(
        packageName: 'test.extension',
        sourceId: '1234567890123456789',
        sourceName: 'Test Source',
        sourceLang: 'en',
        manga: manga(),
        addedAt: DateTime.utc(2026),
        resume: const MangaResume(chapterKey: '', reversedOrder: false),
      ),
      throwsFormatException,
    );
  });

  test('subjects and source/package identities are isolated', () async {
    final server = TestBusinessServer();
    final shared = client(server);
    final other = client(server, subject: 'other');
    addTearDown(shared.dispose);
    addTearDown(other.dispose);
    final library = LibraryRepository(shared);
    await favorite(library);
    await favorite(library, packageName: 'other.extension');
    await favorite(library, sourceId: '1234');
    expect(await library.watchEntries().first, hasLength(3));
    expect(await LibraryRepository(other).watchEntries().first, isEmpty);
    expect(
      () => shared.rebindApi(server, verifiedIdentity: other.identity),
      throwsArgumentError,
    );
  });

  test(
    'failed favorite stays absent until exact mutation is confirmed',
    () async {
      final server = TestBusinessServer()..failWrites = true;
      final shared = client(server);
      addTearDown(shared.dispose);
      final library = LibraryRepository(shared);
      await expectLater(
        favorite(library),
        throwsA(isA<BusinessStateException>()),
      );
      expect(await library.watchEntries().first, isEmpty);
      final firstBody = server.requests
          .where((request) => request.method == 'POST')
          .single
          .body;
      server.failWrites = false;
      await favorite(library);
      expect(await library.watchEntries().first, hasLength(1));
      expect(
        server.requests.where((request) => request.method == 'POST').last.body,
        firstBody,
      );
    },
  );

  test(
    'library fetch crosses pages and refresh reflects remote removal',
    () async {
      final server = TestBusinessServer();
      final first = client(server);
      final second = client(server);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final library = LibraryRepository(first);
      for (var i = 0; i < 10; i++) {
        await favorite(library, value: manga(url: '/manga/$i'));
      }
      expect(
        await LibraryRepository(second).watchEntries().first,
        hasLength(10),
      );
      await favorite(library, value: manga(url: '/manga/0'), enabled: false);
      expect(
        await LibraryRepository(second).watchEntries().first,
        hasLength(9),
      );
      expect(
        server.requests.any(
          (request) => request.uri.queryParameters.containsKey('afterKey'),
        ),
        true,
      );
    },
  );
}
