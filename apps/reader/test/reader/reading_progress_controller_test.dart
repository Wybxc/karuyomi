import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/reader/reading_progress_controller.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/source_runtime.dart';

import '../browse/fakes.dart';
import '../data/business_state_server.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
ChapterManifest get _manifest => ChapterManifest(
  chapterKey: 'chapter',
  version: 'v1',
  pages: [
    ReaderPage(key: 'one'),
    ReaderPage(key: 'two'),
    ReaderPage(key: 'three'),
  ],
);
ProgressIdentity get _identity => ProgressIdentity(
  origin: Uri.parse('https://reader.example.com'),
  subject: 'owner-subject',
);

void main() {
  late TestBusinessServer server;
  late BusinessStateClient shared;
  late ProgressRepository repository;
  late ReadingProgressController controller;
  setUp(() {
    server = TestBusinessServer();
    shared = BusinessStateClient(api: server, identity: _identity);
    repository = ProgressRepository(shared);
    controller = ReadingProgressController(
      repository: repository,
      mangaKey: _key,
    );
  });
  tearDown(() async {
    controller.dispose();
    await shared.dispose();
  });

  test(
    'two readers can resume the same saved chapter before a real navigation writes',
    () async {
      final manifest = _manifest;
      final otherChapter = ChapterManifest(
        chapterKey: 'other-chapter',
        version: 'v1',
        pages: [ReaderPage(key: 'only')],
      );
      final otherAnchor = otherChapter.positionAt(0, offset: .7);
      await repository.save(
        mangaKey: _key,
        manifest: otherChapter,
        progress: ChapterProgress(current: otherAnchor, furthest: otherAnchor),
        reversedOrder: true,
      );
      final anchor = manifest.positionAt(2, offset: .4, viewportY: .2);
      final furthest = manifest.positionAt(2, offset: 1);
      final saved = await repository.saveState(
        mangaKey: _key,
        manifest: manifest,
        progress: ChapterProgress(current: anchor, furthest: furthest),
        reversedOrder: true,
      );

      final secondClient = BusinessStateClient(
        api: server,
        identity: _identity,
      );
      final second = ReadingProgressController(
        repository: ProgressRepository(secondClient),
        mangaKey: _key,
      );
      addTearDown(() async {
        second.dispose();
        await secondClient.dispose();
      });
      for (final reader in [controller, second]) {
        final restored = (await reader.restore(manifest))!;
        expect(reader.awaitingViewport, false);
        expect(reader.reversedOrder, true);
        reader.observe(
          manifest: manifest,
          current: restored,
          observed: furthest,
          reversedOrder: true,
        );
        expect(reader.unsaved, false);
        expect(await reader.flush(), true);
      }
      await controller.refreshFromServer(manifest);
      expect(controller.needsReopen(manifest.chapterKey), false);
      expect(server.appliedMutations, 2);
      expect(server.manga(_key)!.revision, saved.revision);

      final restored = (await second.restore(otherChapter))!;
      expect(second.awaitingViewport, true);
      second.observe(
        manifest: otherChapter,
        current: restored,
        observed: otherAnchor,
        reversedOrder: true,
      );
      expect(await second.flush(), true);
      expect(server.appliedMutations, 3);
      expect(server.manga(_key)!.resume.chapterKey, otherChapter.chapterKey);
    },
  );

  test(
    'navigation is saved only after server confirmation; only viewport observation advances furthest',
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
      expect(controller.storageMode, ProgressStorageMode.serverConfirmed);
      expect(server.progress(_key, 'chapter')!.hasFurthest(), false);
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
      final saved = server.progress(_key, 'chapter')!;
      expect(saved.current.pageIndexHint, 0);
      expect(saved.current.normalizedOffset, .2);
      expect(saved.furthest.pageIndexHint, 2);
      expect(saved.furthest.normalizedOffset, .9);
      expect(saved.completed, false);
      expect(server.manga(_key)!.resume.reversedOrder, true);
    },
  );

  testWidgets(
    'horizontal-only viewport changes debounce to a new confirmed current anchor',
    (tester) async {
      final pages = _manifest;
      await controller.restore(pages);
      controller.observe(
        manifest: pages,
        current: pages.positionAt(1, offset: .4),
        reversedOrder: false,
      );
      expect(await controller.flush(), true);
      for (final (x, viewportX, viewportY) in [
        (.8, 0.0, 0.0),
        (.8, .6, 0.0),
        (.8, .6, .2),
      ]) {
        final revisions = server.appliedMutations;
        controller.observe(
          manifest: pages,
          current: pages.positionAt(
            1,
            offset: .4,
            normalizedX: x,
            viewportX: viewportX,
            viewportY: viewportY,
          ),
          reversedOrder: false,
        );
        expect(controller.unsaved, true);
        await tester.pump(const Duration(milliseconds: 599));
        expect(server.appliedMutations, revisions);
        await tester.pump(const Duration(milliseconds: 1));
        expect(controller.unsaved, false);
        expect(server.appliedMutations, revisions + 1);
        final stored = server.progress(_key, pages.chapterKey)!.current;
        expect(stored.normalizedOffset, .4);
        expect(stored.normalizedX, x);
        expect(stored.viewportX, viewportX);
        expect(stored.viewportY, viewportY);
      }
    },
  );

  test(
    'read failure does not block reading and write failure retains session draft for retry',
    () async {
      final manifest = _manifest;
      server.failNextRequest = true;
      expect(await controller.restore(manifest), isNull);
      expect(controller.error, contains('阅读仍可继续'));
      server.failWrites = true;
      controller.observe(
        manifest: manifest,
        current: manifest.positionAt(1),
        observed: manifest.positionAt(1, offset: .7),
        reversedOrder: false,
      );
      expect(await controller.flush(), false);
      expect(controller.unsaved, true);
      expect(controller.error, contains('当前会话'));
      expect(server.progress(_key, 'chapter'), isNull);
      final firstBody = server.requests
          .where((request) => request.method == 'POST')
          .single
          .body;
      server.failWrites = false;
      expect(await controller.flush(), true);
      expect(controller.unsaved, false);
      expect(controller.error, isNull);
      expect(
        server.requests.where((request) => request.method == 'POST').last.body,
        firstBody,
      );
      expect(server.progress(_key, 'chapter')!.furthest.normalizedOffset, .7);
    },
  );

  test(
    'lost save response keeps same mutation and only confirmation marks saved',
    () async {
      await controller.restore(_manifest);
      controller.observe(
        manifest: _manifest,
        current: _manifest.positionAt(2),
        reversedOrder: false,
      );
      server.loseNextResponse = true;
      expect(await controller.flush(), false);
      expect(controller.unsaved, true);
      expect(server.appliedMutations, 1);
      expect(await controller.flush(), true);
      expect(server.appliedMutations, 1);
      expect(controller.unsaved, false);
    },
  );

  test(
    'missing old anchor returns notice while unresolved furthest survives',
    () async {
      final old = _manifest;
      await repository.save(
        mangaKey: _key,
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
      expect((await controller.restore(changed))!.pageKey, 'three');
      expect(controller.chapter('chapter')!.current.pageKey, 'new');
      expect(controller.chapter('chapter')!.furthestUnresolved(changed), true);
      controller.observe(
        manifest: changed,
        current: changed.positionAt(0),
        reversedOrder: false,
      );
      expect(await controller.flush(), true);
      expect(server.progress(_key, 'chapter')!.current.pageKey, 'new');
      expect(server.progress(_key, 'chapter')!.furthest.pageKey, 'three');
    },
  );

  test(
    'epoch conflict stops stale view and reopening permits the new epoch',
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
        mangaKey: _key,
        manifest: manifest,
        reversedOrder: false,
      );
      expect(await controller.flush(), false);
      expect(controller.error, contains('其他窗口重置'));
      expect(controller.chapter('chapter')!.epoch, 1);
      expect(controller.unsaved, false);
      controller.observe(
        manifest: manifest,
        current: manifest.positionAt(2),
        reversedOrder: true,
      );
      expect(controller.unsaved, false);
      expect(server.progress(_key, 'chapter')!.current.pageKey, 'one');
      await controller.restore(manifest);
      controller.observe(
        manifest: manifest,
        current: manifest.positionAt(1),
        reversedOrder: false,
      );
      expect(await controller.flush(), true);
      expect(server.progress(_key, 'chapter')!.epoch, 1);
      expect(server.progress(_key, 'chapter')!.current.pageKey, 'two');
    },
  );

  test(
    'remote revision conflict requires reopening and does not overwrite',
    () async {
      await controller.restore(_manifest);
      controller.observe(
        manifest: _manifest,
        current: _manifest.positionAt(0),
        reversedOrder: false,
      );
      final remote = BusinessStateClient(api: server, identity: _identity);
      addTearDown(remote.dispose);
      await ProgressRepository(remote).save(
        mangaKey: _key,
        manifest: _manifest,
        progress: ChapterProgress(current: _manifest.positionAt(2)),
        reversedOrder: true,
      );
      expect(await controller.flush(), false);
      expect(controller.error, contains('其他设备更新'));
      controller.observe(
        manifest: _manifest,
        current: _manifest.positionAt(1),
        reversedOrder: false,
      );
      expect(controller.unsaved, false);
      expect(server.progress(_key, 'chapter')!.current.pageKey, 'three');
    },
  );

  test(
    'lost reset response is an unsaved draft and flush cannot reset twice',
    () async {
      await controller.restore(_manifest);
      controller.observe(
        manifest: _manifest,
        current: _manifest.positionAt(2),
        observed: _manifest.positionAt(2),
        reversedOrder: false,
        complete: true,
      );
      expect(await controller.flush(), true);
      server.loseNextResponse = true;
      expect(await controller.reset(_manifest), isNull);
      expect(controller.unsaved, true);
      expect(server.progress(_key, 'chapter')!.epoch, 1);
      controller.observe(
        manifest: _manifest,
        current: _manifest.positionAt(2),
        reversedOrder: true,
      );
      expect(await controller.flush(), true);
      expect(controller.unsaved, false);
      expect(controller.chapter('chapter')!.epoch, 1);
      expect(controller.chapter('chapter')!.furthest, isNull);
      expect(controller.chapter('chapter')!.completed, false);
      expect(server.progress(_key, 'chapter')!.epoch, 1);
    },
  );

  test(
    'a disposed client rejects late replies without notifying a replacement',
    () async {
      await controller.restore(_manifest);
      final started = Completer<void>();
      final release = Completer<void>();
      server.beforeRequest = (request) async {
        if (request.method == 'POST') {
          started.complete();
          await release.future;
        }
        return null;
      };
      controller.observe(
        manifest: _manifest,
        current: _manifest.positionAt(1),
        reversedOrder: false,
      );
      final flushing = controller.flush();
      await started.future;
      controller.dispose();
      await shared.dispose();
      final replacement = BusinessStateClient(
        api: server.forSubject('other'),
        identity: ProgressIdentity(origin: _identity.origin, subject: 'other'),
      );
      addTearDown(replacement.dispose);
      release.complete();
      await flushing;
      expect(await ProgressRepository(replacement).loadResume(_key), isNull);
      expect(server.manga(_key, subject: 'other'), isNull);
    },
  );

  testWidgets('continuous navigation flushes at maximum wait', (tester) async {
    controller.dispose();
    controller = ReadingProgressController(
      repository: repository,
      mangaKey: _key,
      debounce: const Duration(seconds: 1),
      maxWait: const Duration(milliseconds: 50),
    );
    await controller.restore(_manifest);
    controller.observe(
      manifest: _manifest,
      current: _manifest.positionAt(0),
      reversedOrder: false,
    );
    await tester.pump(const Duration(milliseconds: 30));
    controller.observe(
      manifest: _manifest,
      current: _manifest.positionAt(1),
      reversedOrder: false,
    );
    await tester.pump(const Duration(milliseconds: 21));
    await tester.pump();
    expect(server.progress(_key, 'chapter')!.current.pageKey, 'two');
    expect(controller.unsaved, false);
  });

  test(
    'Catalog retains failed detached writer, reuses it and retires after confirmation',
    () async {
      final platform = TestPlatform(businessServer: server);
      final catalog = CatalogController(
        api: platform,
        runtime: platform.runtime,
        rebuildRuntime: platform.rebuild,
        deploymentOrigin: platform.origin,
      );
      addTearDown(() async {
        catalog.dispose();
        await catalog.closeReadingProgress();
        await platform.dispose();
      });
      expect(catalog.readingProgress, isNull);
      await catalog.connect();
      final writer = catalog.createReadingProgress(_key)!;
      await writer.restore(_manifest);
      server.failWrites = true;
      writer.observe(
        manifest: _manifest,
        current: _manifest.positionAt(2),
        reversedOrder: true,
      );
      await catalog.releaseReadingProgress(writer);
      expect(catalog.hasUnsavedReadingProgress, true);
      expect(catalog.readingDraftResume(_key)!.chapterKey, 'chapter');
      final reused = catalog.createReadingProgress(_key)!;
      expect(reused, same(writer));
      server.failWrites = false;
      expect(await catalog.flushReadingProgress(), true);
      await catalog.releaseReadingProgress(reused);
      expect(catalog.hasUnsavedReadingProgress, false);
      expect(
        (await catalog.readingProgress!.loadResume(_key))!.reversedOrder,
        true,
      );
    },
  );

  test(
    'new service adopts only matching identity and rebinds the retained request',
    () async {
      final original = TestPlatform(businessServer: server);
      final first = CatalogController(
        api: original,
        runtime: original.runtime,
        rebuildRuntime: original.rebuild,
        deploymentOrigin: original.origin,
      );
      await first.connect();
      final draft = first.createReadingProgress(_key)!;
      await draft.restore(_manifest);
      server.failWrites = true;
      draft.observe(
        manifest: _manifest,
        current: _manifest.positionAt(1),
        reversedOrder: true,
      );
      await draft.flush();
      final initialBody = server.requests
          .where((request) => request.method == 'POST')
          .last
          .body;
      expect(first.takeUnsavedReadingProgress().single, same(draft));
      first.dispose();
      await first.closeReadingProgress();
      await original.dispose();
      final wrongPlatform = TestPlatform(
        businessServer: server,
        bootstrapSubject: 'other',
      );
      final wrong = CatalogController(
        api: wrongPlatform,
        runtime: wrongPlatform.runtime,
        rebuildRuntime: wrongPlatform.rebuild,
        deploymentOrigin: wrongPlatform.origin,
      );
      await wrong.connect();
      expect(wrong.adoptReadingProgress(draft), false);
      wrong.dispose();
      await wrong.closeReadingProgress();
      await wrongPlatform.dispose();
      final nextPlatform = TestPlatform(businessServer: server);
      final next = CatalogController(
        api: nextPlatform,
        runtime: nextPlatform.runtime,
        rebuildRuntime: nextPlatform.rebuild,
        deploymentOrigin: nextPlatform.origin,
      );
      addTearDown(() async {
        next.dispose();
        await next.closeReadingProgress();
        await nextPlatform.dispose();
      });
      await next.connect();
      expect(next.adoptReadingProgress(draft), true);
      expect(next.createReadingProgress(_key), same(draft));
      server.failWrites = false;
      expect(await next.flushReadingProgress(), true);
      expect(
        server.requests.where((request) => request.method == 'POST').last.body,
        initialBody,
      );
      expect(server.progress(_key, 'chapter')!.current.pageKey, 'two');
    },
  );

  test(
    'identity bootstrap and current-session flush never submit an old identity draft',
    () async {
      final platform = TestPlatform(businessServer: server);
      final catalog = CatalogController(
        api: platform,
        runtime: platform.runtime,
        rebuildRuntime: platform.rebuild,
        deploymentOrigin: platform.origin,
      );
      addTearDown(() async {
        catalog.dispose();
        await catalog.closeReadingProgress();
        await platform.dispose();
      });
      await catalog.connect();
      final original = catalog.createReadingProgress(_key)!;
      await original.restore(_manifest);
      server.failWrites = true;
      original.observe(
        manifest: _manifest,
        current: _manifest.positionAt(1),
        reversedOrder: true,
      );
      expect(await original.flush(), false);
      final originalBody = server.requests
          .where((request) => request.method == 'POST')
          .single
          .body;
      server.failWrites = false;
      var rejectedWrites = 0;
      platform.bootstrapSubject = 'other';
      platform.beforeApiFetch = (path) async {
        if (path == '/api/state/mutations') {
          rejectedWrites++;
          // The real host emits this failure as an Access event, invalidating
          // Catalog's epoch. Merely catching the write error cannot save the
          // bootstrap that a pre-confirmation flush would interrupt.
          throw const RuntimeException(
            RuntimeErrorCode.accessDenied,
            'The active cookie belongs to another identity',
          );
        }
      };
      await catalog.connect();
      expect(catalog.status, ServiceStatus.ready);
      expect(catalog.readingProgress!.identity.subject, 'other');
      expect(rejectedWrites, 0);
      expect(original.unsaved, true);
      expect(await catalog.flushReadingProgress(), false);
      expect(rejectedWrites, 0);
      expect(catalog.status, ServiceStatus.ready);
      expect(server.appliedMutations, 0);
      platform.beforeApiFetch = null;
      platform.bootstrapSubject = 'owner-subject';
      await catalog.connect();
      expect(catalog.status, ServiceStatus.ready);
      expect(catalog.createReadingProgress(_key), same(original));
      expect(await catalog.flushReadingProgress(), true);
      expect(original.unsaved, false);
      expect(server.progress(_key, 'chapter')!.current.pageKey, 'two');
      expect(server.progress(_key, 'chapter', subject: 'other'), isNull);
      expect(
        server.requests.where((request) => request.method == 'POST').last.body,
        originalBody,
      );
      expect(server.appliedMutations, 1);
    },
  );

  test(
    'same Catalog subject switch never sends old drafts as the next identity',
    () async {
      final platform = TestPlatform(businessServer: server);
      final catalog = CatalogController(
        api: platform,
        runtime: platform.runtime,
        rebuildRuntime: platform.rebuild,
        deploymentOrigin: platform.origin,
      );
      addTearDown(() async {
        catalog.dispose();
        await catalog.closeReadingProgress();
        await platform.dispose();
      });
      await catalog.connect();
      final oldWriter = catalog.createReadingProgress(_key)!;
      await oldWriter.restore(_manifest);
      server.failWrites = true;
      oldWriter.observe(
        manifest: _manifest,
        current: _manifest.positionAt(1),
        reversedOrder: true,
      );
      await oldWriter.flush();
      platform.bootstrapSubject = 'other';
      await catalog.connect();
      expect(catalog.readingProgress!.identity.subject, 'other');
      expect(oldWriter.repository.identity.subject, 'owner-subject');
      expect(catalog.adoptReadingProgress(oldWriter), false);
      server.failWrites = false;
      final nextWriter = catalog.createReadingProgress(_key)!;
      expect(await nextWriter.restore(_manifest), isNull);
      nextWriter.observe(
        manifest: _manifest,
        current: _manifest.positionAt(2),
        reversedOrder: false,
      );
      expect(await nextWriter.flush(), true);
      expect(
        server.progress(_key, 'chapter', subject: 'other')!.current.pageKey,
        'three',
      );
      expect(server.progress(_key, 'chapter'), isNull);
      platform.bootstrapSubject = 'owner-subject';
      await catalog.connect();
      expect(catalog.createReadingProgress(_key), same(oldWriter));
      expect(await catalog.flushReadingProgress(), true);
      expect(server.progress(_key, 'chapter')!.current.pageKey, 'two');
      expect(
        server.progress(_key, 'chapter', subject: 'other')!.current.pageKey,
        'three',
      );
      expect(
        identical(oldWriter.repository.client, catalog.readingProgress!.client),
        true,
      );
    },
  );
}
