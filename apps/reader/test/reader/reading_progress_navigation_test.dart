import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/reader_database.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/main.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';

TestPlatform _platform({Uri? origin, String subject = 'owner-subject'}) {
  var session = 0;
  return TestPlatform(origin: origin, bootstrapSubject: subject)
    ..invokeHandler = (call) async => switch (call.whichRequest()) {
      wire.SourceCall_Request.details => wire.SourceResult(manga: testManga),
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
          pageSessionId: 'session-${++session}',
          pages: [
            for (var index = 0; index < 3; index++)
              wire.Page(
                pageKey: 'p-$index',
                index: index,
                sourceIndex: index,
                url: '${call.pages.chapter.url}/page-$index',
              ),
          ],
        ),
      ),
      _ => wire.SourceResult(mangaPage: wire.MangaPage(mangas: [testManga])),
    };
}

Future<CatalogController> _details(
  WidgetTester tester,
  TestPlatform platform,
  ReaderDatabase database, {
  TestPlatform Function(Uri? origin)? factory,
}) async {
  await tester.pumpWidget(
    KaruyomiApp(
      platform: platform,
      database: database,
      platformFactory: factory,
    ),
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
  return tester
      .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
      .controller;
}

void main() {
  testWidgets(
    'failed storage never blocks service replacement; old identity writer retries without old runtime',
    (tester) async {
      final database = ReaderDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final original = _platform();
      final replacement = _platform(
        origin: Uri.parse('https://other.example'),
        subject: 'other-subject',
      );
      final catalog = await _details(
        tester,
        original,
        database,
        factory: (origin) {
          expect(origin, replacement.origin);
          return replacement;
        },
      );
      await tester.tap(find.text('第一章'));
      await tester.pumpAndSettle();
      await catalog.flushReadingProgress();
      final leaf = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      final manifest = leaf.manifest;
      final mangaKey = ChapterSequence(
        packageName: 'source.test',
        sourceId: sourceId,
        mangaUrl: testManga.url,
        chapters: const [],
      ).mangaKey;
      final oldRepository = catalog.readingProgress!;
      await database.customStatement(
        "CREATE TRIGGER reject_progress BEFORE UPDATE ON manga_resume_rows BEGIN SELECT RAISE(ABORT, 'fixture disk failure'); END",
      );
      (leaf.positionRequest! as ValueNotifier<ReadingPosition?>).value =
          manifest.positionAt(1, offset: .4);
      await tester.pumpAndSettle();
      expect(await catalog.flushReadingProgress(), false);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        replacement.origin.toString(),
      );
      await tester.tap(find.text('连接服务'));
      await tester.pumpAndSettle();
      expect(original.disposalCount, 1);
      expect(find.text('重试保存所有进度'), findsOneWidget);
      final oldControls = original.controlCommands.length;
      await tester.tap(find.text('浏览').last);
      await tester.pumpAndSettle();
      final nextCatalog = tester
          .widget<CatalogPage>(find.byType(CatalogPage))
          .controller!;
      expect(nextCatalog.readingProgress!.identity.subject, 'other-subject');
      expect(nextCatalog.readingProgress!.identity.origin, replacement.origin);
      expect(
        await nextCatalog.readingProgress!.loadChapter(
          mangaKey: mangaKey,
          chapterKey: manifest.chapterKey,
        ),
        isNull,
      );
      final nextWriter = nextCatalog.createReadingProgress(mangaKey)!;
      await nextWriter.restore(manifest);
      nextWriter.observe(
        manifest: manifest,
        current: manifest.positionAt(2),
        reversedOrder: false,
      );
      expect(await nextWriter.flush(), true);
      await nextCatalog.releaseReadingProgress(nextWriter);
      expect(
        (await oldRepository.loadChapter(
          mangaKey: mangaKey,
          chapterKey: manifest.chapterKey,
        ))!.current.pageIndexHint,
        0,
      );
      await database.customStatement('DROP TRIGGER reject_progress');
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试保存所有进度'));
      await tester.pumpAndSettle();
      expect(find.text('重试保存所有进度'), findsNothing);
      expect(
        (await oldRepository.loadChapter(
          mangaKey: mangaKey,
          chapterKey: manifest.chapterKey,
        ))!.current.pageIndexHint,
        1,
      );
      expect(
        (await nextCatalog.readingProgress!.loadChapter(
          mangaKey: mangaKey,
          chapterKey: manifest.chapterKey,
        ))!.current.pageIndexHint,
        2,
      );
      expect(original.controlCommands.length, oldControls);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await nextCatalog.closeReadingProgress();
    },
  );

  testWidgets(
    'product routes save and resume exact chapter/offset after SQLite close and reopen',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('karuyomi-product-progress-'),
      ))!;
      final file = File('${directory.path}/reader.sqlite');
      var database = ReaderDatabase(
        NativeDatabase(file),
        storageMode: ProgressStorageMode.persistent,
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      var platform = _platform();
      var catalog = await _details(tester, platform, database);
      final mangaKey = ChapterSequence(
        packageName: 'source.test',
        sourceId: sourceId,
        mangaUrl: testManga.url,
        chapters: const [],
      ).mangaKey;
      await tester.tap(find.text('第一章'));
      await tester.pumpAndSettle();
      var leaf = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      final firstManifest = leaf.manifest;
      (leaf.positionRequest! as ValueNotifier<ReadingPosition?>).value =
          firstManifest.positionAt(2);
      await tester.pumpAndSettle();
      // These callbacks exercise product navigation/persistence. Actual decode
      // visibility and zoom gates are separately tested in ReaderScreen tests.
      leaf.onViewportChanged!(
        ReaderViewportState(
          current: firstManifest.positionAt(2),
          observed: firstManifest.positionAt(2, offset: 1),
          atEnd: true,
          windowReady: false,
        ),
      );
      await tester.tap(find.text('下一章'));
      await tester.pumpAndSettle();
      expect(find.text('真实源 DTO 测试 · 第二章'), findsOneWidget);
      expect(
        (await catalog.readingProgress!.loadChapter(
          mangaKey: mangaKey,
          chapterKey: firstManifest.chapterKey,
        ))!.completed,
        true,
      );
      leaf = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      final secondManifest = leaf.manifest;
      tester
          .widget<DropdownButton<ChapterOrder>>(
            find.byType(DropdownButton<ChapterOrder>),
          )
          .onChanged!(ChapterOrder.reversed);
      await tester.pumpAndSettle();
      (leaf.positionRequest! as ValueNotifier<ReadingPosition?>).value =
          secondManifest.positionAt(1, offset: .35);
      await tester.pumpAndSettle();
      leaf.onViewportChanged!(
        ReaderViewportState(
          current: secondManifest.positionAt(1, offset: .35),
          observed: secondManifest.positionAt(1, offset: .8),
          atEnd: false,
          windowReady: false,
        ),
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('继续阅读'), findsOneWidget);
      expect(find.byType(ReaderScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await catalog.closeReadingProgress();
      await database.close();
      final bytes = (await tester.runAsync(file.readAsBytes))!;
      expect(String.fromCharCodes(bytes.take(15)), 'SQLite format 3');

      database = ReaderDatabase(
        NativeDatabase(file),
        storageMode: ProgressStorageMode.persistent,
      );
      platform = _platform();
      catalog = await _details(tester, platform, database);
      expect(find.text('继续阅读'), findsOneWidget);
      await tester.tap(find.text('继续阅读'));
      await tester.pumpAndSettle();
      leaf = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect(leaf.manifest.chapterKey, secondManifest.chapterKey);
      expect(leaf.initialPosition!.pageKey, secondManifest.pages[1].key);
      expect(leaf.initialPosition!.normalizedOffset, .35);
      expect(
        tester
            .widget<DropdownButton<ChapterOrder>>(
              find.byType(DropdownButton<ChapterOrder>),
            )
            .value,
        ChapterOrder.reversed,
      );
      var stored = (await catalog.readingProgress!.loadChapter(
        mangaKey: mangaKey,
        chapterKey: secondManifest.chapterKey,
      ))!;
      expect(stored.furthest!.pageKey, secondManifest.pages[1].key);
      expect(stored.furthest!.normalizedOffset, .8);
      expect(stored.completed, false);
      final pagesBeforeReset = platform.invocations
          .where((call) => call.whichRequest() == wire.SourceCall_Request.pages)
          .length;
      await tester.tap(find.text('重新阅读本章'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      expect(
        platform.invocations.where(
          (call) => call.whichRequest() == wire.SourceCall_Request.pages,
        ),
        hasLength(pagesBeforeReset),
      );
      stored = (await catalog.readingProgress!.loadChapter(
        mangaKey: mangaKey,
        chapterKey: secondManifest.chapterKey,
      ))!;
      expect(stored.epoch, 1);
      expect(stored.current.pageIndexHint, 0);
      expect(stored.furthest, isNull);
      expect(stored.completed, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await catalog.closeReadingProgress();
    },
  );

  testWidgets('memory and failed writes are honest and never remove the Reader', (
    tester,
  ) async {
    final database = ReaderDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final platform = _platform();
    final catalog = await _details(tester, platform, database);
    await tester.tap(find.text('第一章'));
    await tester.pumpAndSettle();
    expect(find.text('仅当前会话记录，关闭后不会保留'), findsOneWidget);
    expect(find.text('本地进度已保存'), findsNothing);
    await catalog.flushReadingProgress();
    await database.customStatement(
      "CREATE TRIGGER reject_progress BEFORE UPDATE ON manga_resume_rows BEGIN SELECT RAISE(ABORT, 'fixture disk failure'); END",
    );
    final leaf = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
    leaf.onViewportChanged!(
      ReaderViewportState(
        current: leaf.manifest.positionAt(1),
        observed: null,
        atEnd: false,
        windowReady: false,
      ),
    );
    expect(await catalog.flushReadingProgress(), false);
    await tester.pump();
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('本地进度尚未保存，可重试；阅读仍可继续。'), findsOneWidget);
    expect(find.text('重试保存'), findsOneWidget);
    expect(find.text('本地进度已保存'), findsNothing);
    await database.customStatement('DROP TRIGGER reject_progress');
    await tester.tap(find.text('重试保存'));
    await tester.pumpAndSettle();
    expect(catalog.hasUnsavedReadingProgress, false);
    expect(find.text('仅当前会话记录，关闭后不会保留'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await catalog.closeReadingProgress();
  });
}
