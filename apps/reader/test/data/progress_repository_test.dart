import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reader_database.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:reader_core/reader_core.dart';

ChapterManifest manifest({String key = 'chapter', String version = 'v1'}) =>
    ChapterManifest(
      chapterKey: key,
      version: version,
      pages: [
        ReaderPage(key: 'one'),
        ReaderPage(key: 'two'),
        ReaderPage(key: 'three'),
      ],
    );

ProgressIdentity identity({
  String subject = 'user',
  String origin = 'https://reader.example',
}) => ProgressIdentity(origin: Uri.parse(origin), subject: subject);

ChapterProgress observed(
  ChapterManifest pages,
  int index, {
  double offset = 0,
}) => ChapterProgress(current: pages.positionAt(0)).advance(
  manifest: pages,
  current: pages.positionAt(index, offset: offset),
  observed: pages.positionAt(index, offset: offset),
);

void main() {
  test(
    'real SQLite file survives close/reopen with current/far/resume',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'karuyomi-progress-',
      );
      final file = File('${directory.path}/reader.sqlite');
      final pages = manifest();
      var database = ReaderDatabase(
        NativeDatabase(file),
        storageMode: ProgressStorageMode.persistent,
      );
      try {
        var repository = ProgressRepository(database, identity());
        await repository.save(
          mangaKey: 'manga',
          manifest: pages,
          progress: observed(pages, 2, offset: .8),
          reversedOrder: true,
        );
        await repository.save(
          mangaKey: 'manga',
          manifest: pages,
          progress: observed(pages, 0, offset: .2),
          reversedOrder: true,
        );
        expect(await database.storageMode, ProgressStorageMode.persistent);
        await database.close();
        expect(await file.length(), greaterThan(0));
        expect(
          String.fromCharCodes((await file.readAsBytes()).take(15)),
          'SQLite format 3',
        );
        database = ReaderDatabase(
          NativeDatabase(file),
          storageMode: ProgressStorageMode.persistent,
        );
        repository = ProgressRepository(database, identity());
        final saved = (await repository.loadChapter(
          mangaKey: 'manga',
          chapterKey: pages.chapterKey,
        ))!;
        expect(saved.current.pageKey, 'one');
        expect(saved.current.normalizedOffset, .2);
        expect(saved.furthest!.pageKey, 'three');
        expect(saved.furthest!.normalizedOffset, .8);
        expect(saved.epoch, 0);
        final resume = (await repository.loadResume('manga'))!;
        expect(resume.chapterKey, pages.chapterKey);
        expect(resume.reversedOrder, true);
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'subject, origin, manga and snapshot chapter keys are isolated',
    () async {
      final database = ReaderDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      expect(await database.storageMode, ProgressStorageMode.memoryOnly);
      final repository = ProgressRepository(database, identity());
      final pages = manifest(key: 'snapshot-manga-list-occurrence-1');
      await repository.save(
        mangaKey: 'manga',
        manifest: pages,
        progress: observed(pages, 1),
        reversedOrder: false,
      );
      for (final other in [
        ProgressRepository(database, identity(subject: 'other-user')),
        ProgressRepository(database, identity(origin: 'https://other.example')),
      ]) {
        expect(
          await other.loadChapter(
            mangaKey: 'manga',
            chapterKey: pages.chapterKey,
          ),
          isNull,
        );
        expect(await other.loadResume('manga'), isNull);
      }
      expect(
        await repository.loadChapter(
          mangaKey: 'other-manga',
          chapterKey: pages.chapterKey,
        ),
        isNull,
      );
      expect(
        await repository.loadChapter(
          mangaKey: 'manga',
          chapterKey: 'snapshot-manga-list-occurrence-2',
        ),
        isNull,
      );
    },
  );

  test(
    'reset increments epoch and rejects stale saves without changing resume',
    () async {
      final database = ReaderDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ProgressRepository(database, identity());
      final pages = manifest();
      final complete = observed(pages, 2).advance(
        manifest: pages,
        current: pages.positionAt(2),
        observed: pages.positionAt(2),
        complete: true,
      );
      await repository.save(
        mangaKey: 'manga',
        manifest: pages,
        progress: complete,
        reversedOrder: true,
      );
      final reset = await repository.reset(
        mangaKey: 'manga',
        manifest: pages,
        reversedOrder: false,
      );
      expect(reset.epoch, 1);
      expect(reset.current.pageKey, 'one');
      expect(reset.furthest, isNull);
      expect(reset.completed, false);
      final staleResult = await repository.save(
        mangaKey: 'manga',
        manifest: pages,
        progress: complete,
        reversedOrder: true,
      );
      expect(staleResult.epoch, 1);
      expect(staleResult.furthest, isNull);
      expect(staleResult.completed, false);
      expect((await repository.loadResume('manga'))!.reversedOrder, false);
      final next = reset.advance(
        manifest: pages,
        current: pages.positionAt(1),
        observed: pages.positionAt(1),
      );
      expect(
        (await repository.save(
          mangaKey: 'manga',
          manifest: pages,
          progress: next,
          reversedOrder: false,
        )).furthest!.pageKey,
        'two',
      );
      expect(
        (await repository.reset(
          mangaKey: 'manga',
          manifest: pages,
          reversedOrder: false,
        )).epoch,
        2,
      );
    },
  );

  test(
    'transaction rollback cannot split chapter progress and manga resume',
    () async {
      final database = ReaderDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ProgressRepository(database, identity());
      final pages = manifest();
      await repository.save(
        mangaKey: 'manga',
        manifest: pages,
        progress: observed(pages, 0),
        reversedOrder: false,
      );
      await database.customStatement(
        "CREATE TRIGGER reject_resume BEFORE UPDATE ON manga_resume_rows BEGIN SELECT RAISE(ABORT, 'injected resume failure'); END",
      );
      await expectLater(
        repository.save(
          mangaKey: 'manga',
          manifest: pages,
          progress: observed(pages, 2),
          reversedOrder: true,
        ),
        throwsException,
      );
      final saved = (await repository.loadChapter(
        mangaKey: 'manga',
        chapterKey: pages.chapterKey,
      ))!;
      expect(saved.current.pageKey, 'one');
      expect(saved.furthest!.pageKey, 'one');
      expect((await repository.loadResume('manga'))!.reversedOrder, false);
    },
  );

  test(
    'transaction merge keeps maximum observation from concurrent callers',
    () async {
      final database = ReaderDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ProgressRepository(database, identity());
      final pages = manifest();
      await Future.wait([
        repository.save(
          mangaKey: 'manga',
          manifest: pages,
          progress: observed(pages, 2, offset: .8),
          reversedOrder: false,
        ),
        repository.save(
          mangaKey: 'manga',
          manifest: pages,
          progress: observed(pages, 1),
          reversedOrder: false,
        ),
      ]);
      final saved = (await repository.loadChapter(
        mangaKey: 'manga',
        chapterKey: pages.chapterKey,
      ))!;
      expect(saved.furthest!.pageKey, 'three');
      expect(saved.furthest!.normalizedOffset, .8);
    },
  );

  test(
    'changed manifest preserves missing far but invalidates old completion',
    () async {
      final database = ReaderDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = ProgressRepository(database, identity());
      final before = manifest();
      final completed = observed(before, 2).advance(
        manifest: before,
        current: before.positionAt(2),
        observed: before.positionAt(2),
        complete: true,
      );
      await repository.save(
        mangaKey: 'manga',
        manifest: before,
        progress: completed,
        reversedOrder: false,
      );
      final after = ChapterManifest(
        chapterKey: before.chapterKey,
        version: 'v2',
        pages: [
          ReaderPage(key: 'one'),
          ReaderPage(key: 'new'),
        ],
      );
      final changed = completed.advance(
        manifest: after,
        current: after.positionAt(1),
        observed: after.positionAt(1),
      );
      final saved = await repository.save(
        mangaKey: 'manga',
        manifest: after,
        progress: changed,
        reversedOrder: false,
      );
      expect(saved.completed, false);
      expect(saved.furthest!.pageKey, 'three');
      expect(saved.furthestUnresolved(after), true);
      expect(saved.current.pageKey, 'new');
    },
  );
}
