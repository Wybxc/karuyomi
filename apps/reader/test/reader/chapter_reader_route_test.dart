import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';

void main() {
  for (final (exitBeforeMount, usePreparation) in [
    (false, false),
    (true, false),
    (false, true),
  ]) {
    testWidgets(
      'chapter hop awaits cleanup; exit before mount: $exitBeforeMount, prepared: $usePreparation',
      (tester) async {
        final platform = TestPlatform();
        final catalog = CatalogController(
          api: platform,
          runtime: platform.runtime,
        );
        await catalog.connect();
        await catalog.openBuild(catalog.builds.single);
        await catalog.selectSource(catalog.session!.sources.single);
        final manga = catalog.mangas.single;
        final sequence = ChapterSequence(
          packageName: 'source.test',
          sourceId: sourceId,
          mangaUrl: manga.url,
          chapters: [
            wire.Chapter(url: '/one', name: '一'),
            wire.Chapter(
              url: '/two',
              name: '二',
              memoJson: '{"ref":"preserved"}',
            ),
          ],
        );
        platform.invokeHandler = (call) async => wire.SourceResult(
          pageList: wire.PageList(
            pageSessionId: 'session-${call.pages.chapter.url}',
            pages: [
              wire.Page(pageKey: 'p-0', index: 0, sourceIndex: 0, url: '/page'),
            ],
          ),
        );
        final opened = await catalog.openChapter(
          manga,
          ChapterEntry(sequence.entries.first.snapshot),
          reference: catalog.sourceReference,
          logicalChapterKey: sequence.entries.first.key,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ChapterReaderRoute(
              catalog: catalog,
              manga: manga,
              source: catalog.sourceReference,
              sequence: sequence,
              initialChapter: sequence.entries.first,
              initialOpened: opened!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (usePreparation) {
          final leaf = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
          leaf.onViewportChanged!(
            ReaderViewportState(
              current: opened.manifest.positionAt(0),
              observed: opened.manifest.positionAt(0, offset: 1),
              atEnd: true,
              windowReady: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            platform.invocations.where(
              (call) => call.whichRequest() == wire.SourceCall_Request.pages,
            ),
            hasLength(2),
          );
          expect(
            platform.imageControls.where((entry) => entry.$1 == 'acquireImage'),
            hasLength(1),
          );
        }
        final closeGate = Completer<void>();
        platform.closePageSessionHandler = (_) => closeGate.future;
        await tester.tap(find.text('下一章'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(ReaderScreen), findsNothing);
        expect(
          platform.invocations.last.pages.chapter,
          sequence.entries[1].snapshot,
        );
        expect(
          platform.imageControls.where((entry) => entry.$1 == 'acquireImage'),
          hasLength(1),
        );
        closeGate.complete();
        await tester.idle();
        if (exitBeforeMount) {
          // Complete the old close and transfer ownership in microtasks, without
          // allowing the next frame to mount the new Reader leaf.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(find.byType(ReaderScreen), findsNothing);
          expect(
            platform.imageControls.where((entry) => entry.$1 == 'acquireImage'),
            hasLength(1),
          );
          expect(
            platform.imageControls
                .where((entry) => entry.$1 == 'closePageSession')
                .map((entry) => entry.$2['pageSessionId']),
            containsAll(['session-/one', 'session-/two']),
          );
          expect(tester.takeException(), isNull);
          catalog.dispose();
          await platform.dispose();
          return;
        }
        await tester.pumpAndSettle();
        expect(find.byType(ReaderScreen), findsOneWidget);
        expect(find.text('${manga.title} · 二'), findsOneWidget);
        expect(
          platform.invocations.where(
            (call) => call.whichRequest() == wire.SourceCall_Request.pages,
          ),
          hasLength(2),
        );
        expect(
          platform.imageControls.where((entry) => entry.$1 == 'acquireImage'),
          hasLength(2),
        );
        expect(
          platform.imageControls.where(
            (entry) => entry.$1 == 'closePageSession',
          ),
          hasLength(1),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(platform.imageControls.last.$1, 'closePageSession');
        expect(tester.takeException(), isNull);
        catalog.dispose();
        await platform.dispose();
      },
    );
  }

  testWidgets(
    'route exit closes a late next chapter without acquiring images',
    (tester) async {
      final platform = TestPlatform();
      final catalog = CatalogController(
        api: platform,
        runtime: platform.runtime,
      );
      await catalog.connect();
      await catalog.openBuild(catalog.builds.single);
      await catalog.selectSource(catalog.session!.sources.single);
      final manga = catalog.mangas.single;
      final sequence = ChapterSequence(
        packageName: 'source.test',
        sourceId: sourceId,
        mangaUrl: manga.url,
        chapters: [
          wire.Chapter(url: '/one', name: '一'),
          wire.Chapter(url: '/two', name: '二'),
        ],
      );
      final opened = await catalog.openChapter(
        manga,
        ChapterEntry(sequence.entries.first.snapshot),
        reference: catalog.sourceReference,
        logicalChapterKey: sequence.entries.first.key,
      );
      final delayed = Completer<wire.SourceResult>();
      platform.invokeHandler = (_) => delayed.future;
      await tester.pumpWidget(
        MaterialApp(
          home: ChapterReaderRoute(
            catalog: catalog,
            manga: manga,
            source: catalog.sourceReference,
            sequence: sequence,
            initialChapter: sequence.entries.first,
            initialOpened: opened!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一章'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      delayed.complete(
        wire.SourceResult(
          pageList: wire.PageList(
            pageSessionId: 'late-next',
            pages: [
              wire.Page(pageKey: 'p-0', index: 0, sourceIndex: 0, url: '/p'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(
        platform.imageControls.where((entry) => entry.$1 == 'acquireImage'),
        hasLength(1),
      );
      expect(
        platform.imageControls
            .where((entry) => entry.$1 == 'closePageSession')
            .map((entry) => entry.$2['pageSessionId']),
        containsAll(['pages-1', 'late-next']),
      );
      expect(tester.takeException(), isNull);
      catalog.dispose();
      await platform.dispose();
    },
  );
}
