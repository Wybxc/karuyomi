import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reader_database.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/reader/reading_progress_controller.dart';
import 'package:reader_core/reader_core.dart';

import '../browse/fakes.dart';

ChapterManifest get _manifest => ChapterManifest(
  chapterKey: 'chapter',
  version: 'v1',
  pages: [
    ReaderPage(key: 'one'),
    ReaderPage(key: 'two'),
    ReaderPage(key: 'three'),
  ],
);

void main() {
  late ReaderDatabase database;
  late ProgressRepository repository;
  late ReadingProgressController controller;
  setUp(() {
    database = ReaderDatabase(
      NativeDatabase.memory(),
      storageMode: ProgressStorageMode.persistent,
    );
    repository = ProgressRepository(
      database,
      ProgressIdentity(
        origin: Uri.parse('https://reader.example.com'),
        subject: 'owner-subject',
      ),
    );
    controller = ReadingProgressController(
      repository: repository,
      mangaKey: 'manga',
    );
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'navigation alone saves current, while only observed pages advance furthest',
    () async {
      final manifest = _manifest;
      expect(await controller.restore(manifest), isNull);
      controller.observe(
        manifest: manifest,
        current: manifest.positionAt(0),
        reversedOrder: false,
      );
      expect(controller.unsaved, true);
      expect(await controller.flush(), true);
      var saved = (await repository.loadChapter(
        mangaKey: 'manga',
        chapterKey: 'chapter',
      ))!;
      expect(saved.current.pageKey, 'one');
      expect(saved.furthest, isNull);
      expect(saved.completed, false);
      controller.observe(
        manifest: manifest,
        current: manifest.positionAt(2),
        observed: manifest.positionAt(2, offset: .9),
        reversedOrder: true,
      );
      controller.observe(
        manifest: manifest,
        current: manifest.positionAt(0, offset: .2),
        reversedOrder: true,
      );
      expect(await controller.flush(), true);
      saved = (await repository.loadChapter(
        mangaKey: 'manga',
        chapterKey: 'chapter',
      ))!;
      expect(saved.current.pageIndexHint, 0);
      expect(saved.current.normalizedOffset, .2);
      expect(saved.furthest!.pageIndexHint, 2);
      expect(saved.furthest!.normalizedOffset, .9);
      expect(saved.completed, false);
      expect((await repository.loadResume('manga'))!.reversedOrder, true);
    },
  );

  test('failed SQLite transaction keeps dirty draft for exact retry', () async {
    final manifest = _manifest;
    await controller.restore(manifest);
    await database.customStatement(
      "CREATE TRIGGER reject_progress BEFORE INSERT ON manga_resume_rows BEGIN SELECT RAISE(ABORT, 'injected storage failure'); END",
    );
    controller.observe(
      manifest: manifest,
      current: manifest.positionAt(1),
      observed: manifest.positionAt(1, offset: .7),
      reversedOrder: false,
    );
    expect(await controller.flush(), false);
    expect(controller.unsaved, true);
    expect(controller.error, contains('尚未保存'));
    expect(
      await repository.loadChapter(mangaKey: 'manga', chapterKey: 'chapter'),
      isNull,
    );
    await database.customStatement('DROP TRIGGER reject_progress');
    expect(await controller.flush(), true);
    expect(controller.error, isNull);
    expect(controller.unsaved, false);
    final saved = (await repository.loadChapter(
      mangaKey: 'manga',
      chapterKey: 'chapter',
    ))!;
    expect(saved.current.pageKey, 'two');
    expect(saved.furthest!.normalizedOffset, .7);
  });

  test(
    'missing old anchors return original notice and preserve unresolved far',
    () async {
      final old = _manifest;
      await repository.save(
        mangaKey: 'manga',
        manifest: old,
        progress: ChapterProgress(
          current: old.positionAt(2),
          furthest: old.positionAt(2, offset: 1),
        ),
        reversedOrder: false,
      );
      final changed = ChapterManifest(
        chapterKey: 'chapter',
        version: 'v2',
        pages: [ReaderPage(key: 'new')],
      );
      final original = await controller.restore(changed);
      expect(original!.pageKey, 'three');
      expect(controller.chapter('chapter')!.current.pageKey, 'new');
      expect(controller.chapter('chapter')!.furthestUnresolved(changed), true);
      controller.observe(
        manifest: changed,
        current: changed.positionAt(0),
        reversedOrder: false,
      );
      await controller.flush();
      expect(controller.chapter('chapter')!.furthest!.pageKey, 'three');
    },
  );

  test(
    'external epoch reset wins and stops stale route from rewriting it',
    () async {
      final manifest = _manifest;
      await controller.restore(manifest);
      controller.observe(
        manifest: manifest,
        current: manifest.positionAt(2),
        observed: manifest.positionAt(2),
        reversedOrder: true,
      );
      await repository.reset(
        mangaKey: 'manga',
        manifest: manifest,
        reversedOrder: false,
      );
      await controller.flush();
      expect(controller.chapter('chapter')!.epoch, 1);
      expect(controller.error, contains('其他窗口重置'));
      controller.observe(
        manifest: manifest,
        current: manifest.positionAt(2),
        observed: manifest.positionAt(2),
        reversedOrder: true,
      );
      expect(controller.unsaved, false);
      final saved = (await repository.loadChapter(
        mangaKey: 'manga',
        chapterKey: 'chapter',
      ))!;
      expect(saved.current.pageKey, 'one');
      expect(saved.furthest, isNull);
      expect((await repository.loadResume('manga'))!.reversedOrder, false);
    },
  );

  test(
    'reset is the only local operation advancing epoch and clearing completion',
    () async {
      final manifest = _manifest;
      await controller.restore(manifest);
      controller.observe(
        manifest: manifest,
        current: manifest.positionAt(2),
        observed: manifest.positionAt(2, offset: 1),
        reversedOrder: false,
        complete: true,
      );
      await controller.flush();
      expect(controller.chapter('chapter')!.completed, true);
      final reset = (await controller.reset(manifest))!;
      expect(reset.epoch, 1);
      expect(reset.current.pageKey, 'one');
      expect(reset.furthest, isNull);
      expect(reset.completed, false);
    },
  );

  testWidgets(
    'continuous navigation is bounded by max wait, not just trailing debounce',
    (tester) async {
      controller.dispose();
      controller = ReadingProgressController(
        repository: repository,
        mangaKey: 'manga',
        debounce: const Duration(seconds: 1),
        maxWait: const Duration(milliseconds: 50),
      );
      final manifest = _manifest;
      await controller.restore(manifest);
      controller.observe(
        manifest: manifest,
        current: manifest.positionAt(0),
        reversedOrder: false,
      );
      await tester.pump(const Duration(milliseconds: 30));
      controller.observe(
        manifest: manifest,
        current: manifest.positionAt(1),
        reversedOrder: false,
      );
      await tester.pump(const Duration(milliseconds: 21));
      final saved = (await repository.loadChapter(
        mangaKey: 'manga',
        chapterKey: 'chapter',
      ))!;
      expect(saved.current.pageKey, 'two');
      expect(controller.unsaved, false);
    },
  );

  test(
    'Catalog keeps failed detached owner, reuses it, then retires after retry',
    () async {
      final platform = TestPlatform();
      final catalog = CatalogController(
        api: platform,
        runtime: platform.runtime,
        rebuildRuntime: platform.rebuild,
        progressDatabase: database,
        deploymentOrigin: platform.origin,
      );
      addTearDown(() async {
        catalog.dispose();
        await catalog.closeReadingProgress();
        await platform.dispose();
      });
      expect(catalog.readingProgress, isNull); // No unverified test identity.
      await catalog.connect();
      expect(catalog.readingProgress!.identity.subject, 'owner-subject');
      final client = catalog.createReadingProgress('retained')!;
      final manifest = _manifest;
      await client.restore(manifest);
      await database.customStatement(
        "CREATE TRIGGER reject_progress BEFORE INSERT ON manga_resume_rows BEGIN SELECT RAISE(ABORT, 'injected storage failure'); END",
      );
      client.observe(
        manifest: manifest,
        current: manifest.positionAt(2),
        reversedOrder: true,
      );
      await catalog.releaseReadingProgress(client);
      expect(catalog.hasUnsavedReadingProgress, true);
      expect(catalog.readingDraftResume('retained')!.chapterKey, 'chapter');
      final reused = catalog.createReadingProgress('retained')!;
      expect(reused, same(client));
      await database.customStatement('DROP TRIGGER reject_progress');
      expect(await catalog.flushReadingProgress(), true);
      await catalog.releaseReadingProgress(reused);
      expect(catalog.hasUnsavedReadingProgress, false);
      expect(
        (await catalog.readingProgress!.loadResume('retained'))!.reversedOrder,
        true,
      );
    },
  );

  test(
    'returning to the verified identity adopts its draft instead of creating a stale competing writer',
    () async {
      final firstPlatform = TestPlatform();
      final first = CatalogController(
        api: firstPlatform,
        runtime: firstPlatform.runtime,
        rebuildRuntime: firstPlatform.rebuild,
        progressDatabase: database,
        deploymentOrigin: firstPlatform.origin,
      );
      await first.connect();
      final draft = first.createReadingProgress('manga')!;
      await draft.restore(_manifest);
      draft.observe(
        manifest: _manifest,
        current: _manifest.positionAt(1),
        reversedOrder: true,
      );
      final writers = first.takeUnsavedReadingProgress();
      expect(writers.single, same(draft));
      first.dispose();
      await first.closeReadingProgress();
      await firstPlatform.dispose();
      final wrongPlatform = TestPlatform(bootstrapSubject: 'other');
      final wrong = CatalogController(
        api: wrongPlatform,
        runtime: wrongPlatform.runtime,
        rebuildRuntime: wrongPlatform.rebuild,
        progressDatabase: database,
        deploymentOrigin: wrongPlatform.origin,
      );
      await wrong.connect();
      expect(wrong.adoptReadingProgress(draft), false);
      wrong.dispose();
      await wrong.closeReadingProgress();
      await wrongPlatform.dispose();
      final nextPlatform = TestPlatform();
      final next = CatalogController(
        api: nextPlatform,
        runtime: nextPlatform.runtime,
        rebuildRuntime: nextPlatform.rebuild,
        progressDatabase: database,
        deploymentOrigin: nextPlatform.origin,
      );
      await next.connect();
      expect(next.adoptReadingProgress(draft), true);
      final reused = next.createReadingProgress('manga')!;
      expect(reused, same(draft));
      expect(next.readingDraftResume('manga')!.reversedOrder, true);
      await next.releaseReadingProgress(reused);
      next.dispose();
      await next.closeReadingProgress();
      await nextPlatform.dispose();
      expect(
        (await repository.loadChapter(
          mangaKey: 'manga',
          chapterKey: 'chapter',
        ))!.current.pageIndexHint,
        1,
      );
    },
  );
  for (final failSave in [false, true]) {
    test(
      'same Catalog subject change retains original progress ownership (save failure=$failSave)',
      () async {
        final platform = TestPlatform();
        final catalog = CatalogController(
          api: platform,
          runtime: platform.runtime,
          rebuildRuntime: platform.rebuild,
          progressDatabase: database,
          deploymentOrigin: platform.origin,
        );
        addTearDown(() async {
          catalog.dispose();
          await catalog.closeReadingProgress();
          await platform.dispose();
        });
        await catalog.connect();
        await catalog.openBuild(catalog.builds.single);
        final oldRepository = catalog.readingProgress!;
        final oldWriter = catalog.createReadingProgress('manga')!;
        await oldWriter.restore(_manifest);
        oldWriter.observe(
          manifest: _manifest,
          current: _manifest.positionAt(1),
          reversedOrder: true,
        );
        if (failSave) {
          await database.customStatement(
            "CREATE TRIGGER reject_switch_progress BEFORE INSERT ON manga_resume_rows BEGIN SELECT RAISE(ABORT, 'controlled switch write failure'); END",
          );
        }
        platform.bootstrapSubject = 'other-subject';
        await catalog.connect();
        expect(catalog.status, ServiceStatus.ready);
        expect(catalog.readingProgress!.identity.subject, 'other-subject');
        expect(oldWriter.repository.identity.subject, 'owner-subject');
        expect(oldWriter.unsaved, failSave);
        expect(catalog.hasUnsavedReadingProgress, failSave);
        final nextWriter = catalog.createReadingProgress('manga')!;
        expect(nextWriter, isNot(same(oldWriter)));
        expect(await nextWriter.restore(_manifest), isNull);
        expect(await catalog.readingProgress!.loadResume('manga'), isNull);
        expect(catalog.adoptReadingProgress(oldWriter), false);
        if (failSave) {
          await database.customStatement('DROP TRIGGER reject_switch_progress');
          expect(await catalog.flushReadingProgress(), true);
        }
        final oldSaved = (await oldRepository.loadChapter(
          mangaKey: 'manga',
          chapterKey: 'chapter',
        ))!;
        expect(oldSaved.current.pageKey, 'two');
        nextWriter.observe(
          manifest: _manifest,
          current: _manifest.positionAt(2),
          reversedOrder: false,
        );
        await catalog.releaseReadingProgress(nextWriter);
        await catalog.releaseReadingProgress(oldWriter);
        expect(
          (await oldRepository.loadChapter(
            mangaKey: 'manga',
            chapterKey: 'chapter',
          ))!.current.pageKey,
          'two',
        );
        expect(
          (await catalog.readingProgress!.loadChapter(
            mangaKey: 'manga',
            chapterKey: 'chapter',
          ))!.current.pageKey,
          'three',
        );
      },
    );
  }
}
