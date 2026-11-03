import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/reader/chapter_preparation.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import '../browse/fakes.dart';

void main() {
  late TestPlatform platform;
  late CatalogController catalog;
  late ChapterSequence sequence;
  late OpenedChapter current;
  late ChapterPreparation preparation;
  final liveSessions = <String>{};
  Completer<void>? pagesGate;

  setUp(() async {
    liveSessions.clear();
    pagesGate = null;
    platform = TestPlatform();
    catalog = CatalogController(api: platform, runtime: platform.runtime);
    await catalog.connect();
    await catalog.openBuild(catalog.builds.single);
    await catalog.selectSource(catalog.session!.sources.single);
    sequence = ChapterSequence(
      packageName: 'source.test',
      sourceId: sourceId,
      mangaUrl: '/manga',
      chapters: [
        for (var i = 0; i < 3; i++) wire.Chapter(url: '/$i', name: '$i'),
      ],
    );
    platform.invokeHandler = (call) async {
      await pagesGate?.future;
      final id = 'pages-${call.pages.chapter.url}';
      if (liveSessions.length >= 2) {
        throw StateError('Two-session limit exceeded');
      }
      liveSessions.add(id);
      return wire.SourceResult(
        pageList: wire.PageList(
          pageSessionId: id,
          pages: [
            wire.Page(pageKey: 'p-0', index: 0, sourceIndex: 0, url: '/page'),
          ],
        ),
      );
    };
    platform.closePageSessionHandler = (id) async {
      liveSessions.remove(id);
    };
    Future<OpenedChapter?> open(SequenceChapter chapter) => catalog.openChapter(
      catalog.mangas.single,
      ChapterEntry(chapter.snapshot),
      reference: catalog.sourceReference,
      logicalChapterKey: chapter.key,
    );
    current = (await open(sequence.entries.first))!;
    preparation = ChapterPreparation(open);
  });

  tearDown(() async {
    await current.provider.close();
    if (preparation.blocked) {
      // A failed ACK remains owned until a whole runtime rebuild disposes the
      // fixture's Java-session table; it must not be mistaken for a release.
      await platform.rebuild();
      liveSessions.clear();
    } else {
      await preparation.close();
    }
    expect(liveSessions, isEmpty);
    catalog.dispose();
    await platform.dispose();
  });

  test(
    'preparation reserves one metadata session and no neighbor images',
    () async {
      final before = platform.invocations.length;
      final pending = preparation.prepare(sequence.entries[1]);
      await preparation.prepare(sequence.entries[2]);
      await pending;
      expect(platform.invocations.length, before + 1);
      expect(liveSessions, hasLength(2));
      expect(
        platform.imageControls.where((item) => item.$1 == 'acquireImage'),
        isEmpty,
      );
      final next = await preparation.take(sequence.entries[1]);
      expect(next, isNotNull);
      expect(preparation.ready, false);
      await next!.provider.close();
    },
  );

  test(
    'obsolete active prepare finishes and closes without cancelling Source',
    () async {
      pagesGate = Completer<void>();
      final pending = preparation.prepare(sequence.entries[1]);
      await Future<void>.delayed(Duration.zero);
      final discarded = preparation.discard();
      final before = platform.invocations.length;
      await preparation.prepare(sequence.entries[2]);
      expect(platform.invocations.length, before);
      pagesGate!.complete();
      await pending;
      await discarded;
      expect(preparation.ready, false);
      expect(liveSessions, {'pages-/0'});
      expect(
        platform.controlCommands,
        isNot(contains(wire.ControlRequest_Command.cancel)),
      );
      expect(catalog.session, isNotNull);
      await preparation.prepare(sequence.entries[2]);
      expect(liveSessions, {'pages-/0', 'pages-/2'});
    },
  );

  test(
    'close fences a late pages result and preserves current chapter',
    () async {
      pagesGate = Completer<void>();
      final pending = preparation.prepare(sequence.entries[1]);
      await Future<void>.delayed(Duration.zero);
      final closed = preparation.close();
      pagesGate!.complete();
      await pending;
      await closed;
      expect(liveSessions, {'pages-/0'});
      expect(await preparation.take(sequence.entries[1]), isNull);
      expect(catalog.session, isNotNull);
    },
  );

  for (final obsoleteBeforeResult in [false, true]) {
    test(
      'rejected close ACK fences later opens; obsolete: $obsoleteBeforeResult',
      () async {
        platform.closePageSessionHandler = (id) async {
          platform.closeAcknowledged = id != 'pages-/1';
          if (platform.closeAcknowledged) liveSessions.remove(id);
        };
        final rejectedAck = throwsA(isA<RuntimeException>());
        if (obsoleteBeforeResult) pagesGate = Completer<void>();
        final pending = preparation.prepare(sequence.entries[1]);
        if (obsoleteBeforeResult) {
          final failedLoad = expectLater(pending, rejectedAck);
          final failedDiscard = expectLater(preparation.discard(), rejectedAck);
          pagesGate!.complete();
          await failedLoad;
          await failedDiscard;
        } else {
          await pending;
          await expectLater(preparation.discard(), rejectedAck);
        }
        expect(preparation.blocked, true);
        expect(liveSessions, {'pages-/0', 'pages-/1'});
        final before = platform.invocations.length;
        await expectLater(
          preparation.prepare(sequence.entries[2]),
          rejectedAck,
        );
        await expectLater(preparation.take(sequence.entries[2]), rejectedAck);
        await expectLater(preparation.close(), rejectedAck);
        expect(platform.invocations.length, before);
        expect(catalog.session, isNotNull);
      },
    );
  }
}
