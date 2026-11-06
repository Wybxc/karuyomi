import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/library/library_batch.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/business_state_server.dart';

const _firstCategory = '10000000-0000-4000-8000-000000000001';
const _secondCategory = '10000000-0000-4000-8000-000000000002';

BusinessStateClient _client(ApiFetch api) => BusinessStateClient(
  api: api,
  identity: ProgressIdentity(
    origin: Uri.parse('https://reader.example'),
    subject: 'owner-subject',
  ),
);

Future<LibraryView> _seed(LibraryRepository repository) async {
  for (final title in ['甲', '乙', '丙']) {
    await repository.setFavorite(
      packageName: 'eu.kanade.source.test',
      sourceId: '123',
      sourceName: 'Test Source',
      sourceLang: 'zh',
      manga: wire.Manga(url: '/batch/$title', title: title),
      favorite: true,
    );
  }
  await repository.createCategory(
    categoryId: _firstCategory,
    name: 'First',
    expectedRevision: 0,
  );
  await repository.createCategory(
    categoryId: _secondCategory,
    name: 'Second',
    expectedRevision: 1,
  );
  return repository.watchView().first;
}

List<TestBusinessRequest> _posts(TestBusinessServer server) => server.requests
    .where(
      (request) =>
          request.method == 'POST' &&
          request.uri.path == '/api/state/mutations',
    )
    .toList();

wire.StateMutation _command(TestBusinessRequest request) =>
    wire.decodeProtoJson(wire.StateMutation(), jsonDecode(request.body!));

/// Holds one actual supplier ACK after the write and idempotency record have
/// committed. Pausing or losing the caller cannot retract that first write.
final class _AckGate implements ApiFetch {
  _AckGate(this.server);
  final TestBusinessServer server;
  bool _hold = false;
  Completer<void>? received;
  Completer<void>? _released;

  void holdNext() {
    _hold = true;
    received = Completer<void>();
    _released = Completer<void>();
  }

  void release() {
    final gate = _released;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final hold = _hold && method == 'POST' && path == '/api/state/mutations';
    if (hold) _hold = false;
    final reply = await server.fetchApi(
      path,
      method: method,
      headers: headers,
      body: body,
    );
    if (hold) {
      received!.complete();
      await _released!.future;
    }
    return reply;
  }
}

void main() {
  late TestBusinessServer server;
  late _AckGate gate;
  late BusinessStateClient client;
  late LibraryRepository repository;
  setUp(() {
    server = TestBusinessServer();
    gate = _AckGate(server);
    client = _client(gate);
    repository = LibraryRepository(client);
  });
  tearDown(() async {
    gate.release();
    await client.dispose();
  });

  LibraryBatchDraft batch(
    LibraryView view, {
    LibraryBatchAction action = LibraryBatchAction.removeFavorites,
    Set<String> categoryIds = const {},
  }) {
    final draft = LibraryBatchDraft(
      repository: repository,
      view: view,
      mangaKeys: view.entries.map((entry) => entry.mangaKey).toSet(),
      action: action,
      categoryIds: categoryIds,
    );
    addTearDown(draft.dispose);
    return draft;
  }

  Future<void> startHeld(LibraryBatchDraft draft, bool Function() isCurrent) {
    gate.holdNext();
    final running = draft.start(isCurrent: isCurrent);
    addTearDown(() async {
      gate.release();
      await running;
    });
    return running;
  }

  test(
    'pause waits for the in-flight ACK and only explicit continuation sends the remainder',
    () async {
      final view = await _seed(repository);
      final draft = batch(view);
      final before = _posts(server).length;
      final running = startHeld(draft, () => true);
      await gate.received!.future;
      expect(draft.items.first.status, LibraryBatchItemStatus.sending);
      expect(server.manga(view.entries.first.mangaKey)!.favorite, false);
      draft.pause();
      expect(draft.pauseRequested, true);
      draft.finishRemaining();
      expect(draft.finished, false);
      expect(pendingLibraryBatch(repository), same(draft));
      gate.release();
      await running;
      expect(draft.items.map((item) => item.status), [
        LibraryBatchItemStatus.confirmed,
        LibraryBatchItemStatus.notStarted,
        LibraryBatchItemStatus.notStarted,
      ]);
      expect(_posts(server), hasLength(before + 1));
      expect(draft.confirmedCount, 1);
      expect(draft.canContinue, true);
      final wrapper = LibraryRepository(client);
      expect(pendingLibraryBatch(wrapper), same(draft));
      await pendingLibraryBatch(
        wrapper,
      )!.continueRemaining(isCurrent: () => true);
      expect(draft.completed, true);
      expect(draft.finished, true);
      expect(draft.confirmedCount, 3);
      expect(_posts(server), hasLength(before + 3));
      expect(pendingLibraryBatch(wrapper), isNull);
      expect(await wrapper.watchEntries().first, isEmpty);
    },
  );

  test(
    'ending the remainder requires all attempted writes to be confirmed and sends nothing else',
    () async {
      final view = await _seed(repository);
      final draft = batch(view);
      server.loseNextResponse = true;
      await draft.start(isCurrent: () => true);
      expect(draft.items.first.status, LibraryBatchItemStatus.uncertain);
      final original = _posts(server).last.body;
      final beforeRetry = _posts(server).length;
      draft.finishRemaining();
      expect(draft.finished, false);
      expect(pendingLibraryBatch(repository), same(draft));
      expect(_posts(server), hasLength(beforeRetry));
      await draft.retry(isCurrent: () => true);
      expect(_posts(server).last.body, original);
      expect(draft.confirmedCount, 1);
      expect(draft.canContinue, true);
      final remaining = {view.entries[1].mangaKey, view.entries[2].mangaKey};
      final afterRetry = _posts(server).length;
      draft.finishRemaining();
      expect(draft.finished, true);
      expect(draft.completed, false);
      expect(draft.remainingKeys, remaining);
      expect(pendingLibraryBatch(repository), isNull);
      await draft.continueRemaining(isCurrent: () => true);
      expect(_posts(server), hasLength(afterRetry));
      for (final key in remaining) {
        expect(server.manga(key)!.favorite, true);
      }
    },
  );

  test(
    'a late ACK settles only its retired caller and another draft cannot replace the session batch',
    () async {
      final view = await _seed(repository);
      final draft = batch(view);
      var current = true;
      final before = _posts(server).length;
      final running = startHeld(draft, () => current);
      await gate.received!.future;
      current = false;
      gate.release();
      await running;
      expect(draft.confirmedCount, 1);
      expect(draft.notStartedCount, 2);
      expect(draft.pauseRequested, true);
      expect(draft.busy, false);
      await draft.continueRemaining(isCurrent: () => current);
      expect(_posts(server), hasLength(before + 1));
      final wrapper = LibraryRepository(client);
      expect(pendingLibraryBatch(wrapper), same(draft));
      final replacement = LibraryBatchDraft(
        repository: wrapper,
        view: view,
        mangaKeys: view.entries.map((entry) => entry.mangaKey).toSet(),
        action: LibraryBatchAction.removeFavorites,
      );
      addTearDown(replacement.dispose);
      await replacement.start(isCurrent: () => true);
      expect(replacement.attempted, false);
      expect(replacement.error, isNotNull);
      expect(pendingLibraryBatch(repository), same(draft));
      expect(_posts(server), hasLength(before + 1));
      final nextClient = _client(server);
      addTearDown(nextClient.dispose);
      expect(pendingLibraryBatch(LibraryRepository(nextClient)), isNull);
    },
  );

  for (final change in ['catalog', 'manga']) {
    test(
      'a remote $change change after the first write blocks the frozen remainder without rebasing',
      () async {
        final view = await _seed(repository);
        final draft = batch(
          view,
          action: LibraryBatchAction.addCategories,
          categoryIds: {_firstCategory},
        );
        final before = _posts(server).length;
        final running = startHeld(draft, () => true);
        await gate.received!.future;
        final remote = _client(server);
        addTearDown(remote.dispose);
        final remoteRepository = LibraryRepository(remote);
        if (change == 'catalog') {
          await remoteRepository.renameCategory(
            categoryId: _firstCategory,
            name: 'Changed on another client',
            expectedRevision: view.categoryRevision,
          );
        } else {
          final entry = view.entries[1];
          await remoteRepository.refreshMetadata(
            packageName: entry.packageName,
            sourceId: entry.sourceId,
            sourceName: entry.sourceName,
            sourceLang: entry.sourceLang,
            manga: entry.snapshot.deepCopy()
              ..title = 'Changed on another client',
          );
        }
        gate.release();
        await running;
        expect(draft.items.map((item) => item.status), [
          LibraryBatchItemStatus.confirmed,
          LibraryBatchItemStatus.blocked,
          LibraryBatchItemStatus.notStarted,
        ]);
        expect(draft.confirmedCount, 1);
        expect(draft.canRetry, false);
        expect(draft.canContinue, false);
        expect(draft.canReloadAndFinish, true);
        final commands = _posts(
          server,
        ).map(_command).where((command) => command.hasSetCategories()).toList();
        expect(commands, hasLength(2));
        expect(commands.last.mangaKey, view.entries[1].mangaKey);
        expect(commands.last.expectedRevision, view.entries[1].revision);
        expect(
          commands.last.setCategories.expectedCatalogRevision,
          view.categoryRevision,
        );
        final expectedPosts = before + (change == 'manga' ? 3 : 2);
        expect(_posts(server), hasLength(expectedPosts));
        expect(draft.remainingKeys, {
          view.entries[1].mangaKey,
          view.entries[2].mangaKey,
        });
        expect(await draft.reloadAndFinish(isCurrent: () => true), true);
        expect(draft.finished, true);
        expect(draft.completed, false);
        expect(pendingLibraryBatch(repository), isNull);
        expect(_posts(server), hasLength(expectedPosts));
        expect(server.manga(view.entries[2].mangaKey)!.categoryIds, isEmpty);
      },
    );
  }

  test(
    'category union and difference preserve other memberships and still ACK no-op targets',
    () async {
      var view = await _seed(repository);
      for (final entry in view.entries) {
        final ids = switch (entry.title) {
          '甲' => [_firstCategory, _secondCategory],
          '乙' => [_secondCategory],
          _ => <String>[],
        };
        if (ids.isEmpty) continue;
        await repository.setCategories(
          mangaKey: entry.mangaKey,
          categoryIds: ids,
          expectedCatalogRevision: view.categoryRevision,
          expectedMangaRevision: entry.revision,
        );
      }
      view = await repository.watchView().first;
      final addition = batch(
        view,
        action: LibraryBatchAction.addCategories,
        categoryIds: {_firstCategory},
      );
      final beforeAdd = _posts(server).length;
      await addition.start(isCurrent: () => true);
      expect(addition.confirmedCount, 3);
      expect(addition.finished, true);
      expect(_posts(server), hasLength(beforeAdd + 3));
      for (final item in addition.items) {
        final expected = item.entry.title == '丙'
            ? [_firstCategory]
            : [_firstCategory, _secondCategory];
        expect(server.manga(item.entry.mangaKey)!.categoryIds, expected);
        expect(
          server.manga(item.entry.mangaKey)!.revision,
          item.entry.revision + 1,
        );
      }
      final removal = batch(
        await repository.watchView().first,
        action: LibraryBatchAction.removeCategories,
        categoryIds: {_secondCategory},
      );
      final beforeRemove = _posts(server).length;
      await removal.start(isCurrent: () => true);
      expect(removal.confirmedCount, 3);
      expect(removal.finished, true);
      expect(_posts(server), hasLength(beforeRemove + 3));
      for (final item in removal.items) {
        expect(server.manga(item.entry.mangaKey)!.categoryIds, [
          _firstCategory,
        ]);
        expect(
          server.manga(item.entry.mangaKey)!.revision,
          item.entry.revision + 1,
        );
      }
    },
  );
}
