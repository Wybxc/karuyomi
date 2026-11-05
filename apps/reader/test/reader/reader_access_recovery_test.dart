import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/reader_database.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_recovery.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/main.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';

const _memo = '{"id":9223372036854775806,"nested":{"huge":1e1000}}';

final class _Fixture {
  _Fixture() {
    platform.invokeHandler = (call) async {
      if (expire) {
        throw const RuntimeException(
          RuntimeErrorCode.accessRequired,
          'Access expired',
        );
      }
      if (call.hasDetails() && detailsGate != null) await detailsGate!.future;
      if (call.hasPages() && pagesGate != null) await pagesGate!.future;
      return switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(
          manga: testManga..memoJson = _memo,
        ),
        wire.SourceCall_Request.chapters => wire.SourceResult(
          chapters: wire.ChapterList(
            chapters: [
              wire.Chapter(url: '/one', name: '第一章'),
              wire.Chapter(url: '/two', name: '第二章'),
            ],
          ),
        ),
        wire.SourceCall_Request.pages => wire.SourceResult(
          pageList: wire.PageList(
            pageSessionId: 'pages-${++_sessions}',
            pages: [
              for (var index = 0; index < 4; index++)
                wire.Page(
                  pageKey: 'opaque-$index',
                  index: index,
                  sourceIndex: index,
                  url:
                      '${call.pages.chapter.url}/${changedPages ? 'changed' : 'original'}-$index',
                ),
            ],
          ),
        ),
        _ => wire.SourceResult(mangaPage: wire.MangaPage(mangas: [testManga])),
      };
    };
  }

  final platform = TestPlatform();
  final database = ReaderDatabase(NativeDatabase.memory());
  late CatalogController catalog;
  bool expire = false;
  bool changedPages = false;
  int _sessions = 0;
  Completer<void>? detailsGate;
  Completer<void>? pagesGate;

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      KaruyomiApp(platform: platform, database: database),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('去浏览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('source.test · 1.0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试漫画源 · zh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('真实源 DTO 测试'));
    await tester.pumpAndSettle();
    catalog = tester
        .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
        .controller;
    await tester.tap(find.text('第一章'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsOneWidget);
  }

  Future<void> pause(WidgetTester tester) async {
    final session = catalog.session!;
    expire = true;
    await expectLater(
      platform.runtime.invoke(
        SourceRequest(
          packageId: 'source.test',
          call: wire.SourceCall(
            requestId: 'expire',
            generation: session.generation,
            sourceId: sourceId,
            popular: wire.PageRequest(page: 1),
          ),
        ),
      ),
      throwsA(
        isA<RuntimeException>().having(
          (error) => error.code,
          'code',
          RuntimeErrorCode.accessRequired,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(catalog.status, ServiceStatus.loginRequired);
    expect(tester.widget<ReaderScreen>(find.byType(ReaderScreen)).paused, true);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await catalog.closeReadingProgress();
    await database.close();
    expect(tester.takeException(), isNull);
  }
}

void main() {
  test(
    'stored login context retains opaque DTO, logical anchor and layout, and rejects oversized state',
    () {
      final original = ReaderRecoveryContext(
        origin: 'https://reader.example.com',
        subject: 'owner',
        packageName: 'source.test',
        sourceId: sourceId,
        manga: testManga..memoJson = _memo,
        chapterKey: 'chapter',
        position: ReadingPosition(
          chapterKey: 'chapter',
          pageKey: 'missing-page',
          manifestVersion: 'old',
          pageIndexHint: 2,
          normalizedOffset: .4,
        ),
        order: ChapterOrder.reversed,
        mode: ReadingMode.webtoon,
        doublePage: false,
      );
      final restored = ReaderRecoveryContext.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(restored.manga.memoJson, _memo);
      expect(restored.sourceId, sourceId);
      expect(restored.position!.pageKey, 'missing-page');
      expect(restored.position!.normalizedOffset, .4);
      expect(restored.order, ChapterOrder.reversed);
      expect(restored.mode, ReadingMode.webtoon);
      expect(restored.doublePage, false);
      expect(
        () => ReaderRecoveryContext.fromJson({
          ...original.toJson(),
          'origin': 'x' * wire.controlRequestLimit,
        }),
        throwsFormatException,
      );
    },
  );

  for (final changedPages in [false, true]) {
    testWidgets(
      'same identity restores current chapter, epoch and original anchor with layout (changed pages: $changedPages)',
      (tester) async {
        final fixture = _Fixture();
        await fixture.open(tester);
        await tester.tap(find.text('重新阅读本章'));
        await tester.pumpAndSettle();
        tester
            .widget<DropdownButton<ReadingMode>>(
              find.byType(DropdownButton<ReadingMode>),
            )
            .onChanged!(ReadingMode.rightToLeft);
        await tester.pumpAndSettle();
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '双页'))
            .onSelected!(true);
        await tester.pumpAndSettle();
        final original = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
        final anchor = original.manifest.positionAt(1, offset: .4);
        (original.positionRequest! as ValueNotifier<ReadingPosition?>).value =
            anchor;
        await tester.pumpAndSettle();
        await fixture.catalog.flushReadingProgress();
        final repository = fixture.catalog.readingProgress!;
        final mangaKey = ChapterSequence(
          packageName: 'source.test',
          sourceId: sourceId,
          mangaUrl: testManga.url,
          chapters: const [],
        ).mangaKey;
        expect(
          (await repository.loadChapter(
            mangaKey: mangaKey,
            chapterKey: anchor.chapterKey,
          ))!.epoch,
          1,
        );
        await fixture.pause(tester);
        expect(
          tester.widget<ReaderScreen>(find.byType(ReaderScreen)).key,
          original.key,
        );
        final callsAtPause = fixture.platform.invocations.length;
        await tester.pump(const Duration(seconds: 2));
        expect(fixture.platform.invocations, hasLength(callsAtPause));
        expect(
          fixture.platform.imageControls.where(
            (entry) => entry.$1 == 'closePageSession',
          ),
          isEmpty,
        );
        fixture.expire = false;
        fixture.changedPages = changedPages;
        fixture.platform.beforeRebuild = () async {
          expect(find.byType(ReaderScreen), findsNothing);
          expect(
            fixture.platform.imageControls.where(
              (entry) => entry.$1 == 'closePageSession',
            ),
            hasLength(1),
          );
          fixture.platform.runtimeGeneration = 'generation-2';
        };
        await tester.tap(find.text('重新登录并恢复本章'));
        await tester.pumpAndSettle();
        final resumed = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
        expect(resumed.paused, false);
        expect(resumed.generation, 'generation-2');
        expect(resumed.initialPosition!.pageKey, anchor.pageKey);
        expect(
          resumed.initialPosition!.manifestVersion,
          anchor.manifestVersion,
        );
        expect(resumed.initialPosition!.normalizedOffset, .4);
        expect(resumed.initialMode, ReadingMode.rightToLeft);
        expect(resumed.doublePage, true);
        expect(
          find.text('页面清单发生变化，已定位到最接近的页码。'),
          changedPages ? findsOneWidget : findsNothing,
        );
        expect(fixture.platform.authCalls, 1);
        expect(fixture.platform.openedIdentities, [
          'owner-subject',
          'owner-subject',
        ]);
        expect(
          fixture.platform.invocations
              .where((call) => call.hasPages())
              .map((call) => call.pages.chapter.url),
          ['/one', '/one'],
        );
        expect(
          fixture.platform.invocations
              .lastWhere((call) => call.hasDetails())
              .details
              .manga
              .memoJson,
          _memo,
        );
        await fixture.catalog.flushReadingProgress();
        expect(
          (await repository.loadChapter(
            mangaKey: mangaKey,
            chapterKey: anchor.chapterKey,
          ))!.epoch,
          1,
        );
        await fixture.close(tester);
      },
    );
  }

  testWidgets(
    'cancelled login retains the paused Reader without rebuilding or replaying Source calls',
    (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      await fixture.pause(tester);
      final readerKey = tester
          .widget<ReaderScreen>(find.byType(ReaderScreen))
          .key;
      final sourceCalls = fixture.platform.invocations.length;
      fixture.platform.authenticateHandler = () async => false;
      await tester.tap(find.text('重新登录并恢复本章'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).key,
        readerKey,
      );
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).paused,
        true,
      );
      expect(fixture.platform.rebuildCount, 0);
      expect(fixture.platform.invocations, hasLength(sourceCalls));
      expect(
        fixture.platform.imageControls.where(
          (entry) => entry.$1 == 'closePageSession',
        ),
        isEmpty,
      );
      await fixture.close(tester);
    },
  );

  testWidgets(
    'different bootstrap identity retires old Reader and never opens its Source or imports its progress',
    (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      final original = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      final mangaKey = ChapterSequence(
        packageName: 'source.test',
        sourceId: sourceId,
        mangaUrl: testManga.url,
        chapters: const [],
      ).mangaKey;
      final oldRepository = fixture.catalog.readingProgress!;
      await fixture.catalog.flushReadingProgress();
      await fixture.pause(tester);
      final callsAtPause = fixture.platform.invocations.length;
      fixture.expire = false;
      fixture.platform.bootstrapSubject = 'different-owner';
      await tester.tap(find.text('重新登录并恢复本章'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(find.byType(MangaDetailsPage), findsNothing);
      expect(fixture.catalog.subject, 'different-owner');
      expect(fixture.platform.openedIdentities, ['owner-subject']);
      expect(fixture.platform.invocations, hasLength(callsAtPause));
      expect(
        fixture.platform.imageControls.where(
          (entry) => entry.$1 == 'closePageSession',
        ),
        hasLength(1),
      );
      expect(
        await fixture.catalog.readingProgress!.loadChapter(
          mangaKey: mangaKey,
          chapterKey: original.manifest.chapterKey,
        ),
        isNull,
      );
      expect(
        await oldRepository.loadChapter(
          mangaKey: mangaKey,
          chapterKey: original.manifest.chapterKey,
        ),
        isNotNull,
      );
      await fixture.close(tester);
    },
  );

  for (final gatePages in [false, true]) {
    testWidgets(
      'exit during recovery ${gatePages ? 'pages' : 'details'} stops follow-up work and cleans a late provider',
      (tester) async {
        final fixture = _Fixture();
        await fixture.open(tester);
        await fixture.pause(tester);
        final acquiredAtPause = fixture.platform.imageControls
            .where((entry) => entry.$1 == 'acquireImage')
            .length;
        fixture.expire = false;
        final gate = Completer<void>();
        if (gatePages) {
          fixture.pagesGate = gate;
        } else {
          fixture.detailsGate = gate;
        }
        await tester.tap(find.text('重新登录并恢复本章'));
        for (var index = 0; index < 12; index++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.text('正在恢复阅读'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        for (
          var index = 0;
          index < 40 && find.byType(ChapterReaderRoute).evaluate().isNotEmpty;
          index++
        ) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(ChapterReaderRoute), findsNothing);
        gate.complete();
        await tester.pumpAndSettle();
        expect(
          fixture.platform.invocations.where((call) => call.hasPages()),
          hasLength(gatePages ? 2 : 1),
        );
        expect(
          fixture.platform.invocations.where((call) => call.hasChapters()),
          hasLength(gatePages ? 2 : 1),
        );
        expect(
          fixture.platform.imageControls.where(
            (entry) => entry.$1 == 'closePageSession',
          ),
          hasLength(gatePages ? 2 : 1),
        );
        expect(
          fixture.platform.imageControls.where(
            (entry) => entry.$1 == 'acquireImage',
          ),
          hasLength(acquiredAtPause),
        );
        await fixture.close(tester);
      },
    );
  }

  testWidgets(
    'Access login cannot race a chapter hop; the late old hop does not replace the Reader',
    (tester) async {
      final fixture = _Fixture();
      await fixture.open(tester);
      final oldKey = tester.widget<ReaderScreen>(find.byType(ReaderScreen)).key;
      final gate = Completer<void>();
      fixture.pagesGate = gate;
      await tester.tap(find.text('下一章'));
      await tester.pump();
      fixture.expire = true;
      final session = fixture.catalog.session!;
      await expectLater(
        fixture.platform.runtime.invoke(
          SourceRequest(
            packageId: 'source.test',
            call: wire.SourceCall(
              requestId: 'expire-hop',
              generation: session.generation,
              sourceId: sourceId,
              popular: wire.PageRequest(page: 1),
            ),
          ),
        ),
        throwsA(isA<RuntimeException>()),
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '重新登录并恢复本章'),
            )
            .onPressed,
        isNull,
      );
      expect(fixture.platform.authCalls, 0);
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).key,
        oldKey,
      );
      expect(
        tester.widget<ReaderScreen>(find.byType(ReaderScreen)).paused,
        true,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '重新登录并恢复本章'),
            )
            .onPressed,
        isNotNull,
      );
      await fixture.close(tester);
    },
  );
}
