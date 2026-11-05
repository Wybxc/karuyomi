import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/business_state_validation.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/reader/reading_progress_controller.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
BusinessStateClient _client(ApiFetch api) => BusinessStateClient(
  api: api,
  identity: ProgressIdentity(
    origin: Uri.parse('https://reader.example'),
    subject: 'owner-subject',
  ),
);
ChapterManifest _manifest({String version = 'v1'}) => ChapterManifest(
  chapterKey: 'chapter',
  version: version,
  pages: [
    ReaderPage(key: 'first'),
    ReaderPage(key: 'last'),
  ],
);
List<TestBusinessRequest> _posts(TestBusinessServer server) =>
    server.requests.where((request) => request.method == 'POST').toList();
Matcher get _conflict => isA<BusinessStateException>().having(
  (error) => error.conflict,
  'conflict',
  true,
);

/// Alter a real committed reply while retaining the supplier's idempotency
/// record, so recovery must still send the exact original command.
final class _AckFault implements ApiFetch {
  _AckFault(this.server, this.fault);
  final TestBusinessServer server;
  final String fault;
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
      case 'completed':
        value.progress.completed = !value.progress.completed;
      case 'epoch':
        value.progress.epoch = 0;
      case 'anchor':
        value.progress.current = wire.ReadingAnchor(
          chapterKey: 'chapter',
          pageKey: 'invented',
          manifestVersion: 'invented',
        );
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
  late ProgressRepository repository;
  setUp(() {
    server = TestBusinessServer();
    client = _client(server);
    repository = ProgressRepository(client);
  });
  tearDown(() => client.dispose());

  Future<ProgressSnapshot> mark(
    bool read, {
    String chapterKey = 'chapter',
    required int revision,
  }) => repository.setChapterRead(
    mangaKey: _key,
    chapterKey: chapterKey,
    read: read,
    basedOnRevision: revision,
  );

  test('unpositioned response state cannot contain only a furthest anchor', () {
    expect(
      () => validateBusinessProgress(
        wire.ChapterProgressState(
          chapterKey: 'chapter',
          epoch: 1,
          furthest: wire.ReadingAnchor(
            chapterKey: 'chapter',
            pageKey: 'last',
            manifestVersion: 'v1',
          ),
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'an unopened chapter can be read or unread without a fabricated anchor or resume',
    () async {
      final read = await mark(true, revision: 0);
      expect(read.revision, 1);
      expect(read.epoch, 1);
      expect(read.completed, true);
      expect(read.progress, isNull);
      expect(read.resume, isNull);
      final unread = await mark(false, revision: 1);
      expect(unread.epoch, 2);
      expect(unread.completed, false);
      expect(unread.progress, isNull);
      expect(unread.resume, isNull);
      expect(server.progress(_key, 'chapter')!.hasCurrent(), false);
      expect(server.progress(_key, 'chapter')!.hasFurthest(), false);
      final all = await repository.loadAll(_key);
      expect(all.chapters['chapter']!.completed, false);
      expect(all.chapters['chapter']!.epoch, 2);
      expect(() => all.chapters.clear(), throwsUnsupportedError);
      expect(
        server.requests.every(
          (request) => request.uri.path.startsWith('/api/state/'),
        ),
        true,
      );
    },
  );

  test(
    'Reader inherits an unpositioned read epoch and keeps it across a new manifest',
    () async {
      await mark(false, revision: 0);
      await mark(true, revision: 1);
      final reader = ReadingProgressController(
        repository: repository,
        mangaKey: _key,
      );
      addTearDown(reader.dispose);
      final pages = _manifest();
      expect(await reader.restore(pages), isNull);
      expect(reader.chapter('chapter')!.current.pageKey, 'first');
      expect(reader.chapter('chapter')!.epoch, 2);
      expect(reader.chapter('chapter')!.completed, true);
      expect(reader.chapter('chapter')!.furthest, isNull);
      reader.observe(
        manifest: pages,
        current: pages.positionAt(0),
        reversedOrder: false,
      );
      expect(await reader.flush(), true);
      final stored = server.progress(_key, 'chapter')!;
      expect(stored.current.pageKey, 'first');
      expect(stored.completed, true);
      expect(stored.epoch, 2);
      final changed = _manifest(version: 'v2');
      await reader.restore(changed);
      reader.observe(
        manifest: changed,
        current: changed.positionAt(0),
        reversedOrder: false,
      );
      expect(await reader.flush(), true);
      expect(server.progress(_key, 'chapter')!.completed, true);
      expect(server.progress(_key, 'chapter')!.current.manifestVersion, 'v2');
    },
  );

  test(
    'remote unpositioned epochs stop the old reader and an explicit reopen starts at the real first page',
    () async {
      final reader = ReadingProgressController(
        repository: repository,
        mangaKey: _key,
      );
      addTearDown(reader.dispose);
      final pages = _manifest();
      await reader.restore(pages);
      reader.observe(
        manifest: pages,
        current: pages.positionAt(1),
        observed: pages.positionAt(1),
        reversedOrder: true,
      );
      expect(await reader.flush(), true);
      final remoteClient = _client(server);
      addTearDown(remoteClient.dispose);
      final remote = ProgressRepository(remoteClient);
      await remote.setChapterRead(
        mangaKey: _key,
        chapterKey: 'chapter',
        read: false,
        basedOnRevision: 1,
      );
      reader.observe(
        manifest: pages,
        current: pages.positionAt(0),
        reversedOrder: true,
      );
      expect(await reader.flush(), false);
      expect(reader.needsReopen('chapter'), true);
      expect(reader.error, contains('重新打开本章'));
      expect(server.progress(_key, 'chapter')!.hasCurrent(), false);
      expect(server.progress(_key, 'chapter')!.epoch, 1);
      await reader.restore(pages);
      expect(reader.needsReopen('chapter'), false);
      expect(reader.chapter('chapter')!.current.pageKey, 'first');
      expect(reader.chapter('chapter')!.epoch, 1);
      expect(reader.chapter('chapter')!.completed, false);
      expect(reader.chapter('chapter')!.furthest, isNull);
    },
  );

  test(
    'foreground refresh detects read state changes even when both states have no anchors',
    () async {
      await mark(true, revision: 0);
      final reader = ReadingProgressController(
        repository: repository,
        mangaKey: _key,
      );
      addTearDown(reader.dispose);
      await reader.restore(_manifest());
      final remoteClient = _client(server);
      addTearDown(remoteClient.dispose);
      await ProgressRepository(remoteClient).setChapterRead(
        mangaKey: _key,
        chapterKey: 'chapter',
        read: false,
        basedOnRevision: 1,
      );
      await reader.refreshFromServer(_manifest());
      expect(reader.needsReopen('chapter'), true);
      expect(reader.chapter('chapter')!.completed, true);
      expect(reader.chapter('chapter')!.current.pageKey, 'first');
      expect(reader.error, contains('已在其他设备重置'));
    },
  );

  test(
    'read marking preserves existing navigation anchors and bookmark while unread clears only its chapter anchors',
    () async {
      final pages = _manifest();
      await repository.save(
        mangaKey: _key,
        manifest: pages,
        progress: ChapterProgress(
          current: pages.positionAt(1),
          furthest: pages.positionAt(1),
        ),
        reversedOrder: true,
      );
      await client.mutate(
        wire.StateMutation(
          mangaKey: _key,
          setBookmark: wire.SetBookmark(
            chapterKey: 'chapter',
            bookmarked: true,
          ),
        ),
        basedOnRevision: 1,
      );
      final read = await mark(true, revision: 2);
      expect(read.progress!.current.pageKey, 'last');
      expect(read.progress!.furthest!.pageKey, 'last');
      final other = await mark(true, chapterKey: 'other', revision: 3);
      expect(other.resume!.chapterKey, 'chapter');
      expect(other.resume!.reversedOrder, true);
      await mark(false, revision: 4);
      expect(server.manga(_key)!.resume.chapterKey, 'chapter');
      expect(server.bookmarked(_key, 'chapter'), true);
      expect(server.progress(_key, 'chapter')!.completed, false);
      expect(server.progress(_key, 'other')!.completed, true);
    },
  );

  test(
    'an uncertain read command survives shelf and full progress reads and retries only its exact UUID',
    () async {
      server.loseNextResponse = true;
      await expectLater(mark(true, revision: 0), throwsStateError);
      final original = _posts(server).single.body;
      await client.refreshLibrary();
      final confirmed = await repository.loadAll(_key);
      expect(confirmed.chapters['chapter']!.completed, true);
      final sent = _posts(server).length;
      await expectLater(
        mark(false, revision: 1),
        throwsA(isA<BusinessPendingMutationException>()),
      );
      expect(_posts(server), hasLength(sent));
      await mark(true, revision: 0);
      expect(_posts(server).map((request) => request.body), [
        original,
        original,
      ]);
      expect(server.appliedMutations, 1);
    },
  );

  test(
    'an old read ACK cannot resurrect a remotely cleared unpositioned state',
    () async {
      server.loseNextResponse = true;
      await expectLater(mark(true, revision: 0), throwsStateError);
      final remote = _client(server);
      addTearDown(remote.dispose);
      await ProgressRepository(remote).setChapterRead(
        mangaKey: _key,
        chapterKey: 'chapter',
        read: false,
        basedOnRevision: 1,
      );
      await expectLater(mark(true, revision: 0), throwsA(_conflict));
      final posts = _posts(server).length;
      await client.refreshLibrary();
      await expectLater(mark(true, revision: 0), throwsA(_conflict));
      expect(_posts(server), hasLength(posts));
      final current = await repository.loadAll(_key);
      expect(current.chapters['chapter']!.completed, false);
      expect(current.chapters['chapter']!.epoch, 2);
      expect(server.appliedMutations, 2);
      await mark(true, revision: current.revision);
      expect(server.progress(_key, 'chapter')!.epoch, 3);
    },
  );

  test(
    'progress pagination restarts after an intervening write and includes unread tombstones',
    () async {
      for (var index = 0; index < 65; index++) {
        await mark(
          index.isEven,
          chapterKey: 'chapter-${index.toString().padLeft(3, '0')}',
          revision: index,
        );
      }
      final remoteClient = _client(server);
      addTearDown(remoteClient.dispose);
      var changed = false;
      server.beforeRequest = (request) async {
        if (!changed &&
            request.uri.path.endsWith('/progress') &&
            request.uri.queryParameters.containsKey('afterKey')) {
          changed = true;
          await ProgressRepository(remoteClient).setChapterRead(
            mangaKey: _key,
            chapterKey: 'new-chapter',
            read: true,
            basedOnRevision: 65,
          );
        }
        return null;
      };
      final all = await repository.loadAll(_key);
      expect(changed, true);
      expect(all.revision, 66);
      expect(all.accountRevision, 66);
      expect(all.chapters, hasLength(66));
      expect(all.chapters['chapter-001']!.completed, false);
      expect(all.chapters['new-chapter']!.completed, true);
      expect(
        server.requests
            .where((request) => request.uri.path.endsWith('/progress'))
            .length,
        4,
      );
    },
  );

  for (final fault in ['completed', 'epoch', 'anchor']) {
    test(
      'a wrong $fault read ACK stays unconfirmed and preserves the original request',
      () async {
        final api = _AckFault(server, fault)..enabled = true;
        final faultyClient = _client(api);
        addTearDown(faultyClient.dispose);
        final faulty = ProgressRepository(faultyClient);
        Future<ProgressSnapshot> unread() => faulty.setChapterRead(
          mangaKey: _key,
          chapterKey: 'chapter',
          read: false,
          basedOnRevision: 0,
        );
        await expectLater(unread(), throwsFormatException);
        final original = _posts(server).single.body;
        await unread();
        expect(_posts(server).map((request) => request.body), [
          original,
          original,
        ]);
        expect(server.appliedMutations, 1);
      },
    );
  }
}
