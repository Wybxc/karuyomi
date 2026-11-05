import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

const mangaKey =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
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
BusinessStateClient client(
  TestBusinessServer server, {
  String subject = 'owner-subject',
}) => BusinessStateClient(
  api: server.forSubject(subject),
  identity: ProgressIdentity(
    origin: Uri.parse('https://reader.example'),
    subject: subject,
  ),
);
ChapterProgress observed(
  ChapterManifest pages,
  int index, {
  double offset = 0,
  double normalizedX = 0,
  double viewportX = 0,
  double viewportY = 0,
}) => ChapterProgress(current: pages.positionAt(0)).advance(
  manifest: pages,
  current: pages.positionAt(
    index,
    offset: offset,
    normalizedX: normalizedX,
    viewportX: viewportX,
    viewportY: viewportY,
  ),
  observed: pages.positionAt(
    index,
    offset: offset,
    normalizedX: normalizedX,
    viewportX: viewportX,
    viewportY: viewportY,
  ),
);

void main() {
  late TestBusinessServer server;
  late BusinessStateClient shared;
  late ProgressRepository repository;
  setUp(() {
    server = TestBusinessServer();
    shared = client(server);
    repository = ProgressRepository(shared);
  });
  tearDown(() => shared.dispose());

  test('a fresh device reads server current, furthest and resume', () async {
    final pages = manifest();
    await repository.save(
      mangaKey: mangaKey,
      manifest: pages,
      progress: observed(
        pages,
        2,
        offset: .8,
        normalizedX: .2,
        viewportX: .6,
        viewportY: .9,
      ),
      reversedOrder: true,
    );
    await repository.save(
      mangaKey: mangaKey,
      manifest: pages,
      progress: observed(
        pages,
        0,
        offset: .2,
        normalizedX: .8,
        viewportX: .3,
        viewportY: .4,
      ),
      reversedOrder: true,
    );
    final second = client(server);
    addTearDown(second.dispose);
    final remote = ProgressRepository(second);
    final saved = (await remote.loadChapter(
      mangaKey: mangaKey,
      chapterKey: pages.chapterKey,
    ))!;
    expect(saved.current.pageKey, 'one');
    expect(saved.current.normalizedOffset, .2);
    expect(saved.current.normalizedX, .8);
    expect(saved.current.viewportX, .3);
    expect(saved.current.viewportY, .4);
    expect(saved.furthest!.pageKey, 'three');
    expect(saved.furthest!.normalizedOffset, .8);
    expect(saved.furthest!.normalizedX, .2);
    expect(saved.furthest!.viewportX, .6);
    expect(saved.furthest!.viewportY, .9);
    final reordered = ChapterManifest(
      chapterKey: pages.chapterKey,
      version: 'v2',
      pages: pages.pages.reversed,
    );
    final projected = saved.advance(
      manifest: reordered,
      current: saved.current,
    );
    expect(projected.current.pageIndexHint, 2);
    expect(projected.current.normalizedX, .8);
    expect(projected.current.viewportX, .3);
    expect(projected.current.viewportY, .4);
    expect(projected.furthest!.pageIndexHint, 0);
    expect(projected.furthest!.normalizedX, .2);
    expect((await remote.loadResume(mangaKey))!.reversedOrder, true);
  });

  test(
    'reset advances epoch and stale epoch is an explicit conflict',
    () async {
      final pages = manifest();
      final before = observed(pages, 2).advance(
        manifest: pages,
        current: pages.positionAt(2),
        observed: pages.positionAt(2),
        complete: true,
      );
      await repository.save(
        mangaKey: mangaKey,
        manifest: pages,
        progress: before,
        reversedOrder: true,
      );
      final reset = await repository.reset(
        mangaKey: mangaKey,
        manifest: pages,
        reversedOrder: false,
      );
      expect(reset.epoch, 1);
      expect(reset.current.pageKey, 'one');
      expect(reset.furthest, isNull);
      expect(reset.completed, false);
      await expectLater(
        repository.save(
          mangaKey: mangaKey,
          manifest: pages,
          progress: before,
          reversedOrder: true,
        ),
        throwsA(
          isA<BusinessStateException>().having(
            (error) => error.error.code,
            'code',
            wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_STALE_EPOCH,
          ),
        ),
      );
      expect((await repository.loadResume(mangaKey))!.reversedOrder, false);
      await repository.loadChapter(
        mangaKey: mangaKey,
        chapterKey: pages.chapterKey,
      );
      expect(
        (await repository.save(
          mangaKey: mangaKey,
          manifest: pages,
          progress: reset.advance(
            manifest: pages,
            current: pages.positionAt(1),
            observed: pages.positionAt(1),
          ),
          reversedOrder: false,
        )).furthest!.pageKey,
        'two',
      );
    },
  );

  test(
    'response loss retries identical mutation without a second reset',
    () async {
      final pages = manifest();
      server.loseNextResponse = true;
      await expectLater(
        repository.reset(
          mangaKey: mangaKey,
          manifest: pages,
          reversedOrder: true,
        ),
        throwsStateError,
      );
      final first = server.requests
          .where((request) => request.method == 'POST')
          .single;
      expect(server.progress(mangaKey, pages.chapterKey)!.epoch, 1);
      final confirmed = await repository.reset(
        mangaKey: mangaKey,
        manifest: pages,
        reversedOrder: true,
      );
      expect(confirmed.epoch, 1);
      expect(server.appliedMutations, 1);
      expect(
        server.requests.where((request) => request.method == 'POST').last.body,
        first.body,
      );
    },
  );

  test(
    'a newer draft settles a lost prior write before sending next revision',
    () async {
      final pages = manifest();
      server.loseNextResponse = true;
      await expectLater(
        repository.save(
          mangaKey: mangaKey,
          manifest: pages,
          progress: observed(pages, 0),
          reversedOrder: false,
        ),
        throwsStateError,
      );
      final saved = await repository.save(
        mangaKey: mangaKey,
        manifest: pages,
        progress: observed(pages, 2),
        reversedOrder: true,
      );
      expect(saved.current.pageKey, 'three');
      final requests = server.requests
          .where((request) => request.method == 'POST')
          .map(
            (request) => wire.decodeProtoJson(
              wire.StateMutation(),
              jsonDecode(request.body!),
            ),
          )
          .toList();
      expect(requests, hasLength(3));
      expect(requests[0].mutationId, requests[1].mutationId);
      expect(requests[2].mutationId, isNot(requests[1].mutationId));
      expect(requests[2].expectedRevision, 1);
      expect(server.appliedMutations, 2);
    },
  );

  test('remote CAS conflicts never silently overwrite a stale view', () async {
    final pages = manifest();
    await repository.loadChapter(
      mangaKey: mangaKey,
      chapterKey: pages.chapterKey,
    );
    final remote = client(server);
    addTearDown(remote.dispose);
    await ProgressRepository(remote).save(
      mangaKey: mangaKey,
      manifest: pages,
      progress: observed(pages, 2),
      reversedOrder: false,
    );
    await expectLater(
      repository.save(
        mangaKey: mangaKey,
        manifest: pages,
        progress: observed(pages, 0),
        reversedOrder: true,
      ),
      throwsA(
        isA<BusinessStateException>().having(
          (error) => error.conflict,
          'CAS conflict',
          true,
        ),
      ),
    );
    await expectLater(
      repository.save(
        mangaKey: mangaKey,
        manifest: pages,
        progress: observed(pages, 0),
        reversedOrder: true,
      ),
      throwsA(isA<BusinessStateException>()),
    );
    expect(server.appliedMutations, 1);
    expect(
      server.progress(mangaKey, pages.chapterKey)!.current.pageKey,
      'three',
    );
  });

  test('shared-client concurrent saves preserve maximum observation', () async {
    final pages = manifest();
    await Future.wait([
      repository.save(
        mangaKey: mangaKey,
        manifest: pages,
        progress: observed(pages, 2, offset: .8),
        reversedOrder: false,
      ),
      repository.save(
        mangaKey: mangaKey,
        manifest: pages,
        progress: observed(pages, 1),
        reversedOrder: false,
      ),
    ]);
    final saved = (await repository.loadChapter(
      mangaKey: mangaKey,
      chapterKey: pages.chapterKey,
    ))!;
    expect(saved.current.pageKey, 'two');
    expect(saved.furthest!.pageKey, 'three');
    expect(saved.furthest!.normalizedOffset, .8);
  });

  test(
    'changed snapshot preserves unresolved far and chapter completion',
    () async {
      final before = manifest();
      final completed = observed(before, 2).advance(
        manifest: before,
        current: before.positionAt(2),
        observed: before.positionAt(2),
        complete: true,
      );
      await repository.save(
        mangaKey: mangaKey,
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
      final saved = await repository.save(
        mangaKey: mangaKey,
        manifest: after,
        progress: completed.advance(
          manifest: after,
          current: after.positionAt(1),
          observed: after.positionAt(1),
        ),
        reversedOrder: false,
      );
      expect(saved.completed, true);
      expect(saved.furthest!.pageKey, 'three');
      expect(saved.furthestUnresolved(after), true);
      expect(saved.current.pageKey, 'new');
    },
  );
}
