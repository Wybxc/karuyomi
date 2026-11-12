import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/reader/reading_progress_controller.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/business_state_server.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
ChapterManifest _manifest([String key = 'chapter']) => ChapterManifest(
  chapterKey: key,
  version: 'v1',
  pages: [
    ReaderPage(key: 'one'),
    ReaderPage(key: 'two'),
    ReaderPage(key: 'three'),
  ],
);
ProgressIdentity get _identity => ProgressIdentity(
  origin: Uri.parse('https://reader.example'),
  subject: 'owner-subject',
);

void main() {
  late TestBusinessServer server;
  late BusinessStateClient client;
  late BusinessStateClient remote;
  late ReadingProgressController writer;
  final pages = _manifest();
  setUp(() {
    server = TestBusinessServer();
    client = BusinessStateClient(api: server, identity: _identity);
    remote = BusinessStateClient(api: server, identity: _identity);
    writer = ReadingProgressController(
      repository: ProgressRepository(client),
      mangaKey: _key,
      debounce: const Duration(days: 1),
      maxWait: const Duration(days: 1),
    );
  });
  tearDown(() async {
    writer.dispose();
    await client.dispose();
    await remote.dispose();
  });

  Future<void> saveLocal(int index) async {
    writer.observe(
      manifest: pages,
      current: pages.positionAt(index),
      observed: pages.positionAt(index),
      reversedOrder: false,
    );
    expect(await writer.flush(), true);
  }

  Future<void> saveRemote(int index, {ChapterManifest? manifest}) async {
    final chapter = manifest ?? pages;
    await ProgressRepository(remote).save(
      mangaKey: _key,
      manifest: chapter,
      progress: ChapterProgress(
        current: chapter.positionAt(index),
        furthest: chapter.positionAt(index),
      ),
      reversedOrder: true,
    );
  }

  test(
    'unchanged foreground state preserves viewport and permits further saves',
    () async {
      await writer.restore(pages);
      await saveLocal(1);
      final writes = server.appliedMutations;
      await writer.refreshFromServer(pages);
      expect(server.appliedMutations, writes);
      expect(writer.error, isNull);
      expect(writer.needsReopen('chapter'), false);
      expect(writer.chapter('chapter')!.current.pageKey, 'two');
      await saveLocal(2);
    },
  );

  test('remote navigation and furthest change require reopening without moving the viewport', () async {
    await writer.restore(pages);
    await saveLocal(0);
    await saveRemote(2);
    await writer.refreshFromServer(pages);
    expect(writer.needsReopen('chapter'), true);
    expect(writer.error, contains('其他设备更新'));
    expect(writer.chapter('chapter')!.current.pageKey, 'one');
    expect(writer.chapter('chapter')!.furthest!.pageKey, 'one');
    writer.observe(
      manifest: pages,
      current: pages.positionAt(1),
      reversedOrder: false,
    );
    expect(writer.unsaved, false);
    expect(await writer.flush(), false);
    expect(server.progress(_key, 'chapter')!.current.pageKey, 'three');
    expect((await writer.restore(pages))!.pageKey, 'three');
    expect(writer.reversedOrder, true);
    expect(writer.needsReopen('chapter'), false);
    await saveLocal(1);
    expect(server.progress(_key, 'chapter')!.furthest.pageKey, 'three');
  });

  test(
    'remote epoch reset is announced while the current anchor stays intact',
    () async {
      await writer.restore(pages);
      await saveLocal(2);
      await ProgressRepository(remote)
          .reset(mangaKey: _key, manifest: pages, reversedOrder: true);
      await writer.refreshFromServer(pages);
      expect(writer.error, contains('其他设备重置'));
      expect(writer.needsReopen('chapter'), true);
      expect(writer.chapter('chapter')!.current.pageKey, 'three');
      expect(writer.chapter('chapter')!.epoch, 0);
      await writer.restore(pages);
      expect(writer.chapter('chapter')!.current.pageKey, 'one');
      expect(writer.chapter('chapter')!.epoch, 1);
      expect(writer.chapter('chapter')!.furthest, isNull);
    },
  );

  test(
    'a remote resume change to another chapter does not navigate the reader',
    () async {
      await writer.restore(pages);
      await saveLocal(1);
      await saveRemote(0, manifest: _manifest('another-chapter'));
      await writer.refreshFromServer(pages);
      expect(writer.error, contains('其他设备更新'));
      expect(writer.needsReopen('chapter'), true);
      expect(writer.chapter('chapter')!.current.pageKey, 'two');
      expect(writer.chapter('another-chapter'), isNull);
    },
  );

  test('a background shared-client read cannot lend its new revision to an unsent old draft', () async {
    await writer.restore(pages);
    writer.observe(
      manifest: pages,
      current: pages.positionAt(0),
      reversedOrder: false,
    );
    await saveRemote(2);
    // A details or shelf observer can read the same shared client before the
    // reader's debounce fires. That read must not rebase the reader's draft.
    await ProgressRepository(client).loadResume(_key);
    final writes = server.requests
        .where((request) => request.method == 'POST')
        .length;
    await writer.refreshFromServer(pages);
    expect(writer.needsReopen('chapter'), true);
    expect(writer.chapter('chapter')!.current.pageKey, 'one');
    expect(
      server.requests.where((request) => request.method == 'POST').length,
      writes,
    );
    expect(server.progress(_key, 'chapter')!.current.pageKey, 'three');
  });

  test(
    'same-client favorite changes still share revisions with a dirty reader',
    () async {
      final manga = wire.Manga(url: '/same-client', title: 'Shared');
      final library = LibraryRepository(client);
      Future<void> favorite(bool value) => library.setFavorite(
        packageName: 'test.extension',
        sourceId: '123',
        sourceName: 'Test',
        sourceLang: 'en',
        manga: manga,
        favorite: value,
      );
      await favorite(true);
      final key = (await library.watchEntries().first).single.mangaKey;
      writer.dispose();
      writer = ReadingProgressController(
        repository: ProgressRepository(client),
        mangaKey: key,
      );
      await writer.restore(pages);
      writer.observe(
        manifest: pages,
        current: pages.positionAt(1),
        reversedOrder: false,
      );
      await favorite(false);
      await writer.refreshFromServer(pages);
      expect(writer.needsReopen('chapter'), false);
      expect(writer.unsaved, false);
      expect(writer.error, isNull);
      expect(server.progress(key, 'chapter')!.current.pageKey, 'two');
      expect(server.manga(key)!.revision, 3);
    },
  );

  for (final fromOtherClient in [true, false]) {
    test(
      'metadata-only revision changes are explicit unless confirmed by this client (remote=$fromOtherClient)',
      () async {
        final original = wire.Manga(url: '/metadata-change', title: 'Original');
        final library = LibraryRepository(client);
        await library.setFavorite(
          packageName: 'test.extension',
          sourceId: '123',
          sourceName: 'Test',
          sourceLang: 'en',
          manga: original,
          favorite: true,
        );
        final key = (await library.watchEntries().first).single.mangaKey;
        writer.dispose();
        writer = ReadingProgressController(
          repository: ProgressRepository(client),
          mangaKey: key,
        );
        await writer.restore(pages);
        writer.observe(
          manifest: pages,
          current: pages.positionAt(1),
          reversedOrder: false,
        );
        expect(await writer.flush(), true);
        await LibraryRepository(fromOtherClient ? remote : client)
            .refreshMetadata(
              packageName: 'test.extension',
              sourceId: '123',
              sourceName: 'Test',
              sourceLang: 'en',
              manga: wire.Manga(url: original.url, title: 'Updated'),
            );
        await writer.refreshFromServer(pages);
        expect(writer.chapter('chapter')!.current.pageKey, 'two');
        expect(writer.needsReopen('chapter'), fromOtherClient);
        if (fromOtherClient) {
          expect(writer.error, contains('此作品已在其他设备更新'));
        } else {
          expect(writer.error, isNull);
          writer.observe(
            manifest: pages,
            current: pages.positionAt(2),
            reversedOrder: false,
          );
          expect(await writer.flush(), true);
        }
      },
    );
  }

  test('a failed draft keeps its exact request and is retried before foreground inspection', () async {
    await writer.restore(pages);
    writer.observe(
      manifest: pages,
      current: pages.positionAt(1),
      reversedOrder: false,
    );
    server.failWrites = true;
    await writer.refreshFromServer(pages);
    expect(writer.unsaved, true);
    expect(writer.needsReopen('chapter'), false);
    expect(writer.error, contains('当前会话'));
    final original = server.requests
        .where((request) => request.method == 'POST')
        .single
        .body;
    final reads = server.requests
        .where((request) => request.method == 'GET')
        .length;
    expect(reads, 1);
    server.failWrites = false;
    await writer.refreshFromServer(pages);
    expect(writer.unsaved, false);
    expect(writer.error, isNull);
    expect(
      server.requests.where((request) => request.method == 'POST').last.body,
      original,
    );
    expect(server.progress(_key, 'chapter')!.current.pageKey, 'two');
  });

  test('a failed foreground read can be retried without blocking or moving reading', () async {
    await writer.restore(pages);
    await saveLocal(1);
    server.failNextRequest = true;
    await writer.refreshFromServer(pages);
    expect(writer.error, contains('可重试'));
    expect(writer.needsReopen('chapter'), false);
    expect(writer.chapter('chapter')!.current.pageKey, 'two');
    await writer.refreshFromServer(pages);
    expect(writer.error, isNull);
    expect(writer.needsReopen('chapter'), false);
  });

  test(
    'inspection does not release a sticky conflict owned by another chapter',
    () async {
      await writer.restore(pages);
      await saveRemote(1, manifest: _manifest('another'));
      final repository = ProgressRepository(client);
      final another = _manifest('another');
      Future<ChapterProgress> stale() => repository.save(
        mangaKey: _key,
        manifest: another,
        progress: ChapterProgress(current: another.positionAt(0)),
        reversedOrder: false,
      );
      await expectLater(stale(), throwsA(isA<BusinessStateException>()));
      await writer.refreshFromServer(pages);
      final requests = server.requests.length;
      await expectLater(
        stale(),
        throwsA(
          isA<BusinessStateException>().having(
            (failure) => failure.conflictedChapterKey,
            'owner',
            'another',
          ),
        ),
      );
      expect(server.requests.length, requests);
      expect(server.progress(_key, 'another')!.current.pageKey, 'two');
    },
  );

  test('a late inspection cannot change a newly restored chapter', () async {
    await writer.restore(pages);
    final started = Completer<void>();
    final release = Completer<void>();
    var blocked = false;
    server.beforeRequest = (request) async {
      if (!blocked && request.uri.queryParameters['chapterKey'] == 'chapter') {
        blocked = true;
        started.complete();
        await release.future;
      }
      return null;
    };
    final inspection = writer.refreshFromServer(pages);
    await started.future;
    await saveRemote(2);
    final restoration = writer.restore(_manifest('new-chapter'));
    release.complete();
    await inspection;
    await restoration;
    expect(writer.error, isNull);
    expect(writer.needsReopen('chapter'), false);
    expect(writer.chapter('new-chapter')!.current.pageKey, 'one');
  });

  test(
    'a new viewport invalidates a late inspection and keeps the dirty draft',
    () async {
      await writer.restore(pages);
      await saveLocal(0);
      final started = Completer<void>();
      final release = Completer<void>();
      var blocked = false;
      server.beforeRequest = (request) async {
        if (!blocked &&
            request.uri.queryParameters['chapterKey'] == 'chapter') {
          blocked = true;
          started.complete();
          await release.future;
        }
        return null;
      };
      final inspection = writer.refreshFromServer(pages);
      await started.future;
      writer.observe(
        manifest: pages,
        current: pages.positionAt(1),
        reversedOrder: false,
      );
      await saveRemote(2);
      release.complete();
      await inspection;
      expect(writer.unsaved, true);
      expect(writer.error, isNull);
      expect(writer.chapter('chapter')!.current.pageKey, 'two');
      expect(await writer.flush(), false);
      expect(writer.needsReopen('chapter'), true);
      expect(server.progress(_key, 'chapter')!.current.pageKey, 'three');
    },
  );

  test('a disposed reader ignores an in-flight foreground response', () async {
    await writer.restore(pages);
    final started = Completer<void>();
    final release = Completer<void>();
    server.beforeRequest = (request) async {
      if (request.uri.queryParameters['chapterKey'] == 'chapter') {
        started.complete();
        await release.future;
      }
      return null;
    };
    final inspection = writer.refreshFromServer(pages);
    await started.future;
    writer.dispose();
    release.complete();
    await inspection;
    expect(writer.error, isNull);
  });
}
