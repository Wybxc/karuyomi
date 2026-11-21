import '../test_app.dart';
import '../../test_support/cupertino.dart';

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import '../browse/fakes.dart';

void main() {
  testWidgets(
    'turning past the chapter displays and retries its own page list',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final platform = TestPlatform();
      final catalog = CatalogController(
        api: platform,
        runtime: platform.runtime,
        rebuildRuntime: platform.rebuild,
      );
      addTearDown(() async {
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
        catalog.dispose();
        await platform.dispose();
      });
      await catalog.connect();
      await catalog.openBuild(catalog.builds.single);
      await catalog.selectSource(catalog.session!.sources.single);
      final manga = catalog.mangas.single;
      final sequence = ChapterSequence(
        packageName: 'eu.kanade.source.test',
        sourceId: sourceId,
        mangaUrl: manga.url,
        chapters: [
          wire.Chapter(url: '/one', name: '原章'),
          wire.Chapter(url: '/two', name: '目标章节及较长标题', scanlator: '示例翻译组'),
        ],
      );
      final original = sequence.entries.first;
      final opened = (await catalog.openChapter(
        manga,
        ChapterEntry(original.snapshot),
        reference: catalog.sourceReference,
        logicalChapterKey: original.key,
      ))!;
      final firstReply = Completer<wire.SourceResult>();
      final closeEmpty = Completer<void>();
      final closeOriginal = Completer<void>();
      addTearDown(() {
        if (!firstReply.isCompleted) {
          firstReply.complete(
            wire.SourceResult(
              pageList: wire.PageList(pageSessionId: 'empty-pages'),
            ),
          );
        }
        if (!closeEmpty.isCompleted) closeEmpty.complete();
        if (!closeOriginal.isCompleted) closeOriginal.complete();
      });
      var requests = 0;
      platform.invokeHandler = (call) async {
        expect(call.pages.chapter.url, '/two');
        if (++requests == 1) return firstReply.future;
        return wire.SourceResult(
          pageList: wire.PageList(
            pageSessionId: 'target-pages',
            pages: [
              wire.Page(pageKey: 'p-0', index: 0, sourceIndex: 0, url: '/p'),
            ],
          ),
        );
      };
      platform.closePageSessionHandler = (id) => switch (id) {
        'empty-pages' => closeEmpty.future,
        'pages-1' => closeOriginal.future,
        _ => Future.value(),
      };
      await tester.pumpApp(
        CupertinoApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: ChapterReaderRoute(
            catalog: catalog,
            manga: manga,
            source: catalog.sourceReference,
            sequence: sequence,
            initialChapter: original,
            initialOpened: opened,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final panel = find.byType(ReaderChapterTransition);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(find.text('前面没有章节'), findsOneWidget);
      expect(requests, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(
        find.descendant(of: panel, matching: find.text('原章')),
        findsOneWidget,
      );
      expect(find.text('目标章节及较长标题'), findsOneWidget);
      expect(find.text('示例翻译组'), findsOneWidget);
      expect(find.text('正在加载章节页面'), findsOneWidget);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(requests, 1);
      expect(find.semantics.byLabel('页码跳转').evaluate(), isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 240));
      expect(panel, findsNothing);
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).provider,
        same(opened.provider),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      firstReply.complete(
        wire.SourceResult(
          pageList: wire.PageList(pageSessionId: 'empty-pages'),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(find.text('目标章节没有页面'), findsOneWidget);
      await tester.tap(find.descendant(of: panel, matching: find.text('重试')));
      await tester.pump();
      await tester.pump();
      expect(find.text('正在加载章节页面'), findsOneWidget);
      expect(requests, 1);
      closeEmpty.complete();
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('进入下一章'), findsOneWidget);
      expect(
        platform.imageControls.where((entry) => entry.$1 == 'acquireImage'),
        hasLength(1),
      );

      await tester.tap(find.text('进入下一章'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(find.text('正在加载章节页面'), findsOneWidget);
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      closeOriginal.complete();
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).subtitle,
        '目标章节及较长标题',
      );
      expect(
        platform.imageControls.where((entry) => entry.$1 == 'acquireImage'),
        hasLength(2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final appearance in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'reader preserves its canvas and reachable actions in $appearance at ${scale}x text',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final platform = TestPlatform();
          final catalog = CatalogController(
            api: platform,
            runtime: platform.runtime,
            rebuildRuntime: platform.rebuild,
            deploymentOrigin: platform.origin,
          );
          addTearDown(() async {
            await tester.pumpApp(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await catalog.closeReadingProgress();
            catalog.dispose();
            await platform.dispose();
          });
          await catalog.connect();
          await catalog.openBuild(catalog.builds.single);
          await catalog.selectSource(catalog.session!.sources.single);
          final manga = catalog.mangas.single;
          final sequence = ChapterSequence(
            packageName: 'eu.kanade.source.test',
            sourceId: sourceId,
            mangaUrl: manga.url,
            chapters: [wire.Chapter(url: '/one', name: '用于核对较长中文标题的第一章')],
          );
          final rtl = appearance == Brightness.dark;
          if (rtl) {
            final settings = catalog.settings!;
            final before = await settings.loadManga(sequence.mangaKey);
            await settings.setManga(
              mangaKey: sequence.mangaKey,
              overrides: wire.ReaderSettingsOverride(
                mode: wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
              ),
              basedOnRevision: before.mangaRevision!,
            );
          }
          final opened = (await catalog.openChapter(
            manga,
            ChapterEntry(sequence.entries.first.snapshot),
            reference: catalog.sourceReference,
            logicalChapterKey: sequence.entries.first.key,
          ))!;
          await tester.pumpApp(
            CupertinoApp(
              theme: readerAppTheme(appearance),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: ChapterReaderRoute(
                catalog: catalog,
                manga: manga,
                source: catalog.sourceReference,
                sequence: sequence,
                initialChapter: sequence.entries.first,
                initialOpened: opened,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.getSize(find.byType(InteractiveViewer).first).height,
            greaterThan(scale == 1 ? 640 : 240),
          );
          final nav = tester.getRect(find.byType(CupertinoNavigationBar));
          final workTitle = tester.getRect(find.text(manga.title));
          final chapterTitle = tester.getRect(
            find.text(sequence.entries.first.name),
          );
          expect(nav.contains(workTitle.center), isTrue);
          expect(nav.contains(chapterTitle.center), isTrue);
          expect(workTitle.bottom, lessThanOrEqualTo(chapterTitle.top + .1));
          expect(
            find.semantics
                .byLabel('${manga.title} · ${sequence.entries.first.name}')
                .evaluate(),
            hasLength(1),
          );
          final bookmark = iconButton('标记章节书签 ${sequence.entries.first.name}');
          expect(bookmark.hitTestable(), findsOneWidget);
          expect(nav.contains(tester.getCenter(bookmark)), isTrue);
          final settings = iconButton('阅读设置');
          expect(settings.hitTestable(), findsOneWidget);
          expect(
            tester.getCenter(settings).dy,
            greaterThan(
              tester.getRect(find.byType(InteractiveViewer).first).bottom,
            ),
          );
          for (final label in ['上一页', '下一页']) {
            final icon = find.byWidgetPredicate(
              (widget) => widget is Icon && widget.semanticLabel == label,
            );
            expect(
              tester
                  .getSemantics(icon)
                  .getSemanticsData()
                  .flagsCollection
                  .isEnabled,
              Tristate.isFalse,
            );
          }
          for (final label in ['没有上一章', '没有下一章']) {
            final button = iconButton(label);
            expect(button, findsOneWidget);
            expect(
              tester.getSize(button).width,
              kMinInteractiveDimensionCupertino,
            );
            expect(
              tester
                  .getSemantics(button)
                  .getSemanticsData()
                  .flagsCollection
                  .isEnabled,
              Tristate.isFalse,
            );
          }
          final previous = tester.getCenter(iconButton('没有上一章'));
          final next = tester.getCenter(iconButton('没有下一章'));
          expect(previous.dy, next.dy);
          expect(rtl ? next.dx : previous.dx, lessThan(180));
          expect(rtl ? previous.dx : next.dx, greaterThan(180));
          expect(find.byType(CupertinoSlider), findsNothing);
          expect(find.text('1 / 1'), findsOneWidget);
          await tester.longPress(iconButton('没有上一章'));
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('没有上一章').hitTestable(), findsNothing);
          expect(find.text('没有上一章'), findsOneWidget);
          await tester.pump(const Duration(seconds: 2));
          await tester.pumpAndSettle();
          expect(find.text('重新阅读本章'), findsNothing);
          expect(find.text('刷新书签'), findsNothing);
          final options = find.byKey(const ValueKey('reader-chapter-options'));
          expect(options.hitTestable(), findsOneWidget);
          expect(nav.contains(tester.getCenter(options)), isTrue);
          await catalog.flushReadingProgress();
          await tester.pumpAndSettle();
          final writes = platform.businessServer.requests
              .where((r) => r.method == 'POST')
              .length;
          await tester.tap(options);
          await tester.pumpAndSettle();
          expect(find.text('重新阅读本章').hitTestable(), findsOneWidget);
          expect(find.text('刷新进度').hitTestable(), findsOneWidget);
          expect(
            platform.businessServer.requests.where((r) => r.method == 'POST'),
            hasLength(writes),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'exit during delayed progress restore closes unmounted provider and ignores late result',
    (tester) async {
      final progressGate = Completer<void>();
      final platform = TestPlatform();
      final catalog = CatalogController(
        api: platform,
        runtime: platform.runtime,
        rebuildRuntime: platform.rebuild,
        deploymentOrigin: platform.origin,
      );
      await catalog.connect();
      await catalog.openBuild(catalog.builds.single);
      await catalog.selectSource(catalog.session!.sources.single);
      final manga = catalog.mangas.single;
      final sequence = ChapterSequence(
        packageName: 'eu.kanade.source.test',
        sourceId: sourceId,
        mangaUrl: manga.url,
        chapters: [wire.Chapter(url: '/one', name: '一')],
      );
      final opened = (await catalog.openChapter(
        manga,
        ChapterEntry(sequence.entries.first.snapshot),
        reference: catalog.sourceReference,
        logicalChapterKey: sequence.entries.first.key,
      ))!;
      platform.beforeApiFetch = (path) async {
        if (path.startsWith('/api/state/manga/')) await progressGate.future;
      };
      await tester.pumpApp(
        CupertinoApp(
          home: ChapterReaderRoute(
            catalog: catalog,
            manga: manga,
            source: catalog.sourceReference,
            sequence: sequence,
            initialChapter: sequence.entries.first,
            initialOpened: opened,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ReaderScreen), findsNothing);
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pump();
      expect(platform.imageControls.map((entry) => entry.$1), [
        'closePageSession',
      ]);
      progressGate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(catalog.hasUnsavedReadingProgress, false);
      expect(tester.takeException(), isNull);
      await catalog.closeReadingProgress();
      catalog.dispose();
      await platform.dispose();
    },
  );

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
          rebuildRuntime: platform.rebuild,
        );
        await catalog.connect();
        await catalog.openBuild(catalog.builds.single);
        await catalog.selectSource(catalog.session!.sources.single);
        final manga = catalog.mangas.single;
        final sequence = ChapterSequence(
          packageName: 'eu.kanade.source.test',
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
        await tester.pumpApp(
          CupertinoApp(
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
        await tester.tap(iconButton('下一章'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(ReaderScreen), findsNothing);
        expect(find.text('正在切换章节'), findsOneWidget);
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
          await tester.pumpApp(const SizedBox.shrink());
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
        expect(find.byType(CupertinoAlertDialog), findsNothing);
        expect(
          find.semantics.byLabel('${manga.title} · 二').evaluate(),
          hasLength(1),
        );
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
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(platform.imageControls.last.$1, 'closePageSession');
        expect(tester.takeException(), isNull);
        catalog.dispose();
        await platform.dispose();
      },
    );
  }

  for (final exit in [false, true]) {
    testWidgets(
      exit ? 'route exit closes a late next chapter without acquiring images' : 'a failed toolbar hop keeps the original chapter and its error during prefetch',
      (tester) async {
        final platform = TestPlatform();
        final catalog = CatalogController(
          api: platform,
          runtime: platform.runtime,
          rebuildRuntime: platform.rebuild,
        );
        await catalog.connect();
        await catalog.openBuild(catalog.builds.single);
        await catalog.selectSource(catalog.session!.sources.single);
        final manga = catalog.mangas.single;
        final sequence = ChapterSequence(
          packageName: 'eu.kanade.source.test',
          sourceId: sourceId,
          mangaUrl: manga.url,
          chapters: [
            if (!exit) wire.Chapter(url: '/previous', name: '上一话'),
            wire.Chapter(url: '/one', name: '一'),
            wire.Chapter(url: '/two', name: '二'),
          ],
        );
        final original = sequence.entries[exit ? 0 : 1];
        final direction = exit ? '下一章' : '上一章';
        final targetName = exit ? '二' : '上一话';
        final opened = await catalog.openChapter(
          manga,
          ChapterEntry(original.snapshot),
          reference: catalog.sourceReference,
          logicalChapterKey: original.key,
        );
        final delayed = Completer<wire.SourceResult>();
        platform.invokeHandler = (_) => delayed.future;
        await tester.pumpApp(
          CupertinoApp(
            home: ChapterReaderRoute(
              catalog: catalog,
              manga: manga,
              source: catalog.sourceReference,
              sequence: sequence,
              initialChapter: original,
              initialOpened: opened!,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final chapterLocation = tester.getCenter(iconButton(direction));
        await tester.tap(iconButton(direction));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final waiting = find.byType(CupertinoAlertDialog);
        expect(find.text('正在切换章节'), findsOneWidget);
        expect(
          find.descendant(of: waiting, matching: find.text(targetName)),
          findsOneWidget,
        );
        expect(find.text('一'), findsOneWidget);
        expect(find.semantics.byLabel(direction).evaluate(), isEmpty);
        await tester.tapAt(chapterLocation);
        await tester.binding.handlePopRoute();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(waiting, findsOneWidget);
        expect(
          platform.invocations.where((call) => call.hasPages()),
          hasLength(2),
        );

        if (!exit) {
          delayed.completeError(
            const RuntimeException(RuntimeErrorCode.sourceError, 'Page error'),
          );
          await tester.pumpAndSettle();
          expect(waiting, findsNothing);
          final error = find.text('漫画源请求失败，请重试');
          expect(error, findsOneWidget);
          expect(iconButton(direction).hitTestable(), findsOneWidget);
          final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
          expect(reader.provider, same(opened.provider));
          expect(
            platform.imageControls.where(
              (entry) => entry.$1 == 'closePageSession',
            ),
            isEmpty,
          );
          final prefetch = Completer<wire.SourceResult>();
          platform.invokeHandler = (_) => prefetch.future;
          reader.onViewportChanged!(
            ReaderViewportState(
              current: opened.manifest.positionAt(0),
              observed: opened.manifest.positionAt(0, offset: 1),
              atEnd: true,
              windowReady: true,
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(platform.invocations.last.pages.chapter.url, '/two');
          final visibleDuringPrefetch = error.evaluate().isNotEmpty;
          prefetch.complete(
            wire.SourceResult(
              pageList: wire.PageList(pageSessionId: 'prefetched-next'),
            ),
          );
          await tester.pumpAndSettle();
          expect(visibleDuringPrefetch, true);
          expect(error, findsOneWidget);
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          catalog.dispose();
          await platform.dispose();
          return;
        }

        await tester.pumpApp(const SizedBox.shrink());
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
}
