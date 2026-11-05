import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/business_state_validation.dart';
import 'package:karuyomi/data/cover_repository.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/runtime/cover_transport.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';
import 'cover_fakes.dart';

ProgressIdentity _identity([String subject = 'owner-subject']) =>
    ProgressIdentity(
      origin: Uri.parse('https://reader.example'),
      subject: subject,
    );

void main() {
  late TestBusinessServer server;
  late TestCoverTransport transport;
  late BusinessStateClient client;
  late CoverRepository covers;
  late LibraryRepository library;
  late String key;
  wire.Manga source() => wire.Manga(
    url: '/test-cover',
    title: 'Original manga',
    thumbnailUrl: '/source-cover',
  );
  Future<void> metadata({bool favorite = true}) => library.setFavorite(
    packageName: 'test.extension',
    sourceId: '123',
    sourceName: 'Test',
    sourceLang: 'en',
    manga: source(),
    favorite: favorite,
  );
  Future<CoverSnapshot> replace({int? revision, int marker = 1}) async =>
      covers.replace(
        mangaKey: key,
        bytes: Uint8List.fromList([marker, 2, 3]),
        contentType: 'image/png',
        basedOnRevision: revision ?? (await covers.load(key)).revision,
      );
  setUp(() async {
    server = TestBusinessServer();
    transport = TestCoverTransport(server);
    client = BusinessStateClient(
      api: server,
      identity: _identity(),
      covers: transport,
    );
    covers = CoverRepository(client);
    library = LibraryRepository(client);
    await metadata();
    key = (await library.watchEntries().first).single.mangaKey;
  });
  tearDown(() async {
    await client.dispose();
    transport.close();
  });

  test(
    'cover uses the shared manga CAS and metadata/favorite changes preserve its identity',
    () async {
      final saved = await replace();
      expect(saved.revision, 2);
      final upload = transport.uploads.single;
      expect(saved.cover!.assetId, isNot(upload.command.mutationId));
      expect(saved.cover!.sha256, sha256.convert(upload.bytes).toString());
      expect(await covers.read(saved.cover!), orderedEquals(upload.bytes));
      final entries = await library.watchEntries().first;
      expect(entries.single.customCover, saved.cover);
      expect(entries.single.snapshot.thumbnailUrl, '/source-cover');
      expect(entries.single.customCover!.isFrozen, true);
      await library.refreshMetadata(
        packageName: 'test.extension',
        sourceId: '123',
        sourceName: 'Test',
        sourceLang: 'en',
        manga: source()..title = 'Refreshed metadata',
      );
      await metadata(favorite: false);
      final after = await covers.load(key);
      expect(after.cover, saved.cover);
      final cleared = await covers.clear(
        mangaKey: key,
        basedOnRevision: after.revision,
      );
      expect(cleared.cover, isNull);
      expect(cleared.revision, after.revision + 1);
      final clearRequest = wire.decodeProtoJson(
        wire.StateMutation(),
        jsonDecode(server.requests.lastWhere((r) => r.method == 'POST').body!),
      );
      expect(clearRequest.hasSetCustomCover(), true);
      expect(clearRequest.setCustomCover.hasCover(), false);
      expect(transport.uploads, hasLength(1));
      await expectLater(
        covers.read(saved.cover!),
        throwsA(
          isA<CoverTransportException>().having(
            (e) => e.status,
            'removed cover is private',
            404,
          ),
        ),
      );
    },
  );

  test(
    'lost upload ACK retains immutable bytes, UUID and CAS across repository recreation and exact retry',
    () async {
      final originalBytes = Uint8List.fromList([5, 6, 7]);
      server.loseNextResponse = true;
      await expectLater(
        covers.replace(
          mangaKey: key,
          bytes: originalBytes,
          contentType: 'image/png',
          basedOnRevision: 1,
        ),
        throwsStateError,
      );
      final first = transport.uploads.single;
      originalBytes[0] = 99;
      covers = CoverRepository(client);
      final pending = covers.pending(key)!;
      expect(pending.retryable, true);
      expect(pending.basedOnRevision, 1);
      expect(pending.bytes, orderedEquals([5, 6, 7]));
      expect(() => pending.bytes![0] = 99, throwsUnsupportedError);
      await covers.load(key);
      expect(covers.pending(key)!.cover, pending.cover);
      await expectLater(
        replace(),
        throwsA(isA<BusinessPendingMutationException>()),
      );
      await expectLater(
        library.removeFavorite(mangaKey: key, expectedMangaRevision: 2),
        throwsA(isA<BusinessPendingMutationException>()),
      );
      expect(transport.uploads, hasLength(1));
      final retried = await covers.retry(key);
      expect(retried.cover, pending.cover);
      expect(covers.pending(key), isNull);
      expect(transport.uploads.last.mutation, first.mutation);
      expect(transport.uploads.last.bytes, orderedEquals(first.bytes));
      expect(server.appliedMutations, 2);
    },
  );

  test(
    'a cover upload and following progress write run in one manga queue',
    () async {
      final received = Completer<void>();
      final release = Completer<void>();
      transport.beforeUpload = (_) async {
        received.complete();
        await release.future;
      };
      final upload = replace(revision: 1);
      await received.future;
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: 'v1',
        pages: [ReaderPage(key: 'page')],
      );
      final progress = ProgressRepository(client).save(
        mangaKey: key,
        manifest: manifest,
        progress: ChapterProgress(current: manifest.positionAt(0)),
        reversedOrder: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(server.appliedMutations, 1);
      release.complete();
      final saved = await upload;
      await progress;
      expect((await covers.load(key)).cover, saved.cover);
      expect(server.progress(key, 'chapter')!.current.pageKey, 'page');
      final writes = server.requests.where((r) => r.method == 'POST').toList();
      expect(writes[1].path, '/api/covers/$key');
      expect(writes[2].path, '/api/state/mutations');
    },
  );

  test(
    'remote cover CAS conflicts require reload and a new clear decision',
    () async {
      final remote = BusinessStateClient(
        api: server,
        identity: _identity(),
        covers: transport,
      );
      addTearDown(remote.dispose);
      final remoteCovers = CoverRepository(remote);
      final old = await covers.load(key);
      final current = await remoteCovers.replace(
        mangaKey: key,
        bytes: Uint8List.fromList([8, 9]),
        contentType: 'image/jpeg',
        basedOnRevision: old.revision,
      );
      await expectLater(
        covers.clear(mangaKey: key, basedOnRevision: old.revision),
        throwsA(
          isA<BusinessStateException>().having(
            (e) => e.conflict,
            'conflict',
            true,
          ),
        ),
      );
      expect(covers.pending(key)!.retryable, false);
      final refreshed = await covers.load(key);
      expect(refreshed.cover, current.cover);
      expect(covers.pending(key), isNull);
      expect(
        (await covers.clear(
          mangaKey: key,
          basedOnRevision: refreshed.revision,
        )).cover,
        isNull,
      );
    },
  );

  test(
    'an old successful upload ACK cannot resurrect a remotely cleared cover',
    () async {
      server.loseNextResponse = true;
      await expectLater(replace(revision: 1), throwsStateError);
      final original = covers.pending(key)!;
      final remote = BusinessStateClient(
        api: server,
        identity: _identity(),
        covers: transport,
      );
      addTearDown(remote.dispose);
      final remoteCovers = CoverRepository(remote);
      final current = await remoteCovers.load(key);
      await remoteCovers.clear(
        mangaKey: key,
        basedOnRevision: current.revision,
      );
      await expectLater(
        covers.retry(key),
        throwsA(
          isA<BusinessStateException>().having(
            (e) => e.conflict,
            'old ACK conflicts',
            true,
          ),
        ),
      );
      expect(covers.pending(key)!.retryable, false);
      expect((await covers.load(key)).cover, isNull);
      expect(covers.pending(key), isNull);
      expect(transport.uploads.last.mutation, transport.uploads.first.mutation);
      await expectLater(
        covers.read(original.cover!),
        throwsA(isA<CoverTransportException>()),
      );
    },
  );

  test(
    'retiring a session discards late cover ACKs and keeps another subject isolated',
    () async {
      final received = Completer<void>();
      final release = Completer<void>();
      transport.beforeUpload = (_) async {
        received.complete();
        await release.future;
      };
      final upload = replace(revision: 1);
      final failure = expectLater(upload, throwsStateError);
      await received.future;
      await client.dispose();
      release.complete();
      await failure;
      final otherTransport = TestCoverTransport(
        server,
        subject: 'another-subject',
      );
      final other = BusinessStateClient(
        api: server.forSubject('another-subject'),
        identity: _identity('another-subject'),
        covers: otherTransport,
      );
      addTearDown(other.dispose);
      final otherCovers = CoverRepository(other);
      expect((await otherCovers.load(key)).cover, isNull);
      final oldCover = transport.uploads.single.command.setCustomCover.cover;
      await expectLater(
        otherCovers.read(oldCover),
        throwsA(isA<CoverTransportException>()),
      );
    },
  );

  test(
    'cover descriptors and upload budgets reject invalid values before transport',
    () async {
      final valid = wire.CustomCover(
        assetId: '12345678-1234-4234-8234-123456789abc',
        contentType: 'image/png',
        byteLength: 1,
        sha256: 'a' * 64,
      );
      validateBusinessCustomCover(valid);
      for (final invalid in [
        valid.deepCopy()..assetId = 'https://example.com/cover',
        valid.deepCopy()..assetId = valid.assetId.toUpperCase(),
        valid.deepCopy()..contentType = 'image/svg+xml',
        valid.deepCopy()..byteLength = 1024 * 1024 + 1,
        valid.deepCopy()..sha256 = 'bad',
      ]) {
        expect(
          () => validateBusinessCustomCover(invalid),
          throwsFormatException,
        );
      }
      await expectLater(
        covers.replace(
          mangaKey: key,
          bytes: Uint8List(1024 * 1024 + 1),
          contentType: 'image/png',
          basedOnRevision: 1,
        ),
        throwsFormatException,
      );
      expect(transport.uploads, isEmpty);
      expect(covers.pending(key), isNull);
    },
  );
}
