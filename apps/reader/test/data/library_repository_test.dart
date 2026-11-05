import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reader_database.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

ProgressIdentity identity({
  String subject = 'user',
  String origin = 'https://reader.example',
}) => ProgressIdentity(origin: Uri.parse(origin), subject: subject);

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

void main() {
  test(
    'SQLite file reopen preserves full Source snapshot and favorite time',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'karuyomi-library-',
      );
      final file = File('${directory.path}/reader.sqlite');
      final addedAt = DateTime.utc(2026, 11, 5, 9, 10, 11);
      var database = ReaderDatabase(NativeDatabase(file));
      try {
        var repository = LibraryRepository(
          database,
          identity(),
          now: () => addedAt,
        );
        final original = manga();
        await favorite(repository, value: original);
        await database.close();
        expect(await file.length(), greaterThan(0));
        expect(
          String.fromCharCodes((await file.readAsBytes()).take(15)),
          'SQLite format 3',
        );
        database = ReaderDatabase(NativeDatabase(file));
        repository = LibraryRepository(database, identity());
        final entries = await repository.watchEntries().first;
        expect(entries, hasLength(1));
        final saved = entries.single;
        expect(saved.packageName, 'test.extension');
        expect(saved.sourceId, '1234567890123456789');
        expect(saved.sourceName, 'Test Source');
        expect(saved.sourceLang, 'en');
        expect(saved.addedAt.toUtc(), addedAt);
        expect(
          wire.encodeProtoJson(saved.snapshot),
          wire.encodeProtoJson(original),
        );
        expect(saved.snapshot.isFrozen, isTrue);
        expect(
          saved.mangaKey,
          ChapterSequence(
            packageName: saved.packageName,
            sourceId: saved.sourceId,
            mangaUrl: original.url,
            chapters: const [],
          ).mangaKey,
        );
        original.title = 'Mutated caller';
        expect(saved.title, 'Original');
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('metadata refresh and repeated favorite preserve added order', () async {
    final database = ReaderDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var now = DateTime.utc(2026, 11, 5);
    final repository = LibraryRepository(database, identity(), now: () => now);
    await favorite(repository);
    final firstTime = now;
    now = now.add(const Duration(days: 1));
    await favorite(
      repository,
      value: manga(title: 'Second', url: '/manga/2'),
    );
    await favorite(repository, value: manga(title: 'Updated'));
    var entries = await repository.watchEntries().first;
    expect(entries.map((entry) => entry.title), ['Second', 'Updated']);
    expect(entries.last.addedAt.toUtc(), firstTime);
    await repository.refreshMetadata(
      packageName: 'test.extension',
      sourceId: '1234567890123456789',
      sourceName: 'Renamed Source',
      sourceLang: 'zh',
      manga: manga(title: 'Refreshed'),
    );
    entries = await repository.watchEntries().first;
    expect(entries.last.title, 'Refreshed');
    expect(entries.last.sourceName, 'Renamed Source');
    expect(entries.last.sourceLang, 'zh');
    expect(entries.last.addedAt.toUtc(), firstTime);
    await repository.refreshMetadata(
      packageName: 'test.extension',
      sourceId: '1234567890123456789',
      sourceName: 'Test Source',
      sourceLang: 'en',
      manga: manga(url: '/never-favorited'),
    );
    expect(
      await database.select(database.libraryMangaRows).get(),
      hasLength(2),
    );
  });

  test('subject, origin, package and Source keep distinct favorites', () async {
    final database = ReaderDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = LibraryRepository(database, identity());
    await favorite(repository);
    final original = (await repository.watchEntries().first).single;
    for (final other in [
      LibraryRepository(database, identity(subject: 'other')),
      LibraryRepository(database, identity(origin: 'https://other.example')),
    ]) {
      expect(await other.watchEntries().first, isEmpty);
      expect(await other.contains(original.mangaKey), isFalse);
      await favorite(other, value: manga(title: 'Other identity'));
    }
    await favorite(repository, packageName: 'other.extension');
    await favorite(repository, sourceId: 'other-source');
    final entries = await repository.watchEntries().first;
    expect(entries, hasLength(3));
    expect(entries.map((entry) => entry.mangaKey).toSet(), hasLength(3));
    expect(entries.every((entry) => entry.title == 'Original'), isTrue);
  });

  test(
    'favorite stream tracks add/remove while metadata and reading survive',
    () async {
      final database = ReaderDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = LibraryRepository(database, identity());
      await favorite(repository);
      final entry = (await repository.watchEntries().first).single;
      final pages = ChapterManifest(
        chapterKey: 'chapter-1',
        version: 'v1',
        pages: [ReaderPage(key: 'page-1')],
      );
      final progress = ProgressRepository(database, identity());
      await progress.save(
        mangaKey: entry.mangaKey,
        manifest: pages,
        progress: ChapterProgress(current: pages.positionAt(0, offset: .7)),
        reversedOrder: true,
      );
      final updates = StreamIterator(repository.watchFavorite(entry.mangaKey));
      try {
        expect(await updates.moveNext(), isTrue);
        expect(updates.current, isTrue);
        await favorite(
          repository,
          enabled: false,
          value: manga(title: 'Stale removal metadata'),
        );
        expect(await updates.moveNext(), isTrue);
        expect(updates.current, isFalse);
        expect(await repository.watchEntries().first, isEmpty);
        final metadata = await database
            .select(database.libraryMangaRows)
            .getSingle();
        expect(
          wire
              .decodeProtoJson(wire.Manga(), jsonDecode(metadata.mangaJson))
              .title,
          'Original',
        );
        expect(
          (await progress.loadResume(entry.mangaKey))!.chapterKey,
          'chapter-1',
        );
        expect(
          (await progress.loadChapter(
            mangaKey: entry.mangaKey,
            chapterKey: 'chapter-1',
          ))!.current.normalizedOffset,
          .7,
        );
        await favorite(repository);
        expect(await updates.moveNext(), isTrue);
        expect(updates.current, isTrue);
      } finally {
        await updates.cancel();
      }
    },
  );

  test(
    'failed favorite transaction rolls metadata back with the favorite',
    () async {
      final database = ReaderDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = LibraryRepository(database, identity());
      await database.customStatement(
        "CREATE TRIGGER reject_favorite BEFORE INSERT ON library_favorite_rows BEGIN SELECT RAISE(ABORT, 'injected favorite failure'); END",
      );
      await expectLater(favorite(repository), throwsException);
      expect(await repository.watchEntries().first, isEmpty);
      expect(await database.select(database.libraryMangaRows).get(), isEmpty);
      expect(
        await database.select(database.libraryFavoriteRows).get(),
        isEmpty,
      );
    },
  );

  test(
    'adding the current library tables preserves previous progress rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'karuyomi-library-schema-',
      );
      final file = File('${directory.path}/reader.sqlite');
      var database = ReaderDatabase(NativeDatabase(file));
      try {
        final progress = ProgressRepository(database, identity());
        final pages = ChapterManifest(
          chapterKey: 'old-chapter',
          version: 'v1',
          pages: [ReaderPage(key: 'old-page')],
        );
        await progress.save(
          mangaKey: 'old-manga',
          manifest: pages,
          progress: ChapterProgress(current: pages.positionAt(0)),
          reversedOrder: false,
        );
        // Recreate the previous prototype's two-table schema in a real file.
        await database.customStatement('DROP TABLE library_favorite_rows');
        await database.customStatement('DROP TABLE library_manga_rows');
        await database.customStatement('PRAGMA user_version = 1');
        await database.close();
        database = ReaderDatabase(NativeDatabase(file));
        final restoredProgress = ProgressRepository(database, identity());
        expect(
          (await restoredProgress.loadResume('old-manga'))!.chapterKey,
          'old-chapter',
        );
        expect(
          (await restoredProgress.loadChapter(
            mangaKey: 'old-manga',
            chapterKey: 'old-chapter',
          ))!.current.pageKey,
          'old-page',
        );
        final library = LibraryRepository(database, identity());
        await favorite(library);
        expect(await library.watchEntries().first, hasLength(1));
        expect(
          await database.select(database.chapterProgressRows).get(),
          hasLength(1),
        );
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
