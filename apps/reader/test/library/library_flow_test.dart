import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/reader_database.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/main.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';

Future<CatalogController> _browseDetails(WidgetTester tester) async {
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
    'favorites and exact reading anchor survive a product SQLite reopen',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('karuyomi-library-flow-'),
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
      var platform = TestPlatform();
      await tester.pumpWidget(
        KaruyomiApp(platform: platform, database: database),
      );
      await tester.pumpAndSettle();
      var catalog = await _browseDetails(tester);
      await tester.tap(find.text('加入书架'));
      await tester.pumpAndSettle();
      expect(find.text('移出书架'), findsOneWidget);
      await tester.tap(find.text('第 1 章'));
      await tester.pumpAndSettle();
      final initialReader = tester.widget<ReaderScreen>(
        find.byType(ReaderScreen),
      );
      final manifest = initialReader.manifest;
      // This tests product persistence, not image decoding or actual visibility.
      initialReader.onViewportChanged!(
        ReaderViewportState(
          current: manifest.positionAt(0, offset: .35),
          observed: null,
          atEnd: false,
          windowReady: false,
        ),
      );
      await catalog.flushReadingProgress();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('继续阅读'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await catalog.closeReadingProgress();
      await database.close();

      database = ReaderDatabase(
        NativeDatabase(file),
        storageMode: ProgressStorageMode.persistent,
      );
      platform = TestPlatform()..runtimeGeneration = 'reopened-generation';
      await tester.pumpWidget(
        KaruyomiApp(platform: platform, database: database),
      );
      await tester.pumpAndSettle();
      expect(find.text('真实源 DTO 测试'), findsOneWidget);
      expect(platform.invocations, isEmpty);
      await tester.tap(find.text('真实源 DTO 测试'));
      await tester.pumpAndSettle();
      catalog = tester
          .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
          .controller;
      expect(find.text('移出书架'), findsOneWidget);
      expect(find.text('继续阅读'), findsOneWidget);
      expect(platform.invocations.map((call) => call.whichRequest()), [
        wire.SourceCall_Request.details,
        wire.SourceCall_Request.chapters,
      ]);
      await tester.tap(find.text('继续阅读'));
      await tester.pumpAndSettle();
      final resumed = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
      expect(resumed.initialPosition!.chapterKey, manifest.chapterKey);
      expect(resumed.initialPosition!.pageKey, manifest.pages.single.key);
      expect(resumed.initialPosition!.normalizedOffset, .35);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移出书架'));
      await tester.pumpAndSettle();
      expect(find.text('加入书架'), findsOneWidget);
      expect(find.text('继续阅读'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('书架还是空的'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await catalog.closeReadingProgress();
    },
  );

  testWidgets(
    'failed favorite write stays retryable and does not block chapter reading',
    (tester) async {
      final database = ReaderDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final platform = TestPlatform();
      await tester.pumpWidget(
        KaruyomiApp(platform: platform, database: database),
      );
      await tester.pumpAndSettle();
      final catalog = await _browseDetails(tester);
      await database.customStatement(
        "CREATE TRIGGER reject_favorite BEFORE INSERT ON library_favorite_rows BEGIN SELECT RAISE(ABORT, 'fixture storage full'); END",
      );
      await tester.tap(find.text('加入书架'));
      await tester.pumpAndSettle();
      expect(find.text('收藏未能保存，请重试；仍可继续阅读。'), findsOneWidget);
      expect(find.text('加入书架'), findsOneWidget);
      expect(
        await tester.runAsync(() => catalog.library!.watchEntries().first),
        isEmpty,
      );
      await tester.tap(find.text('第 1 章'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await database.customStatement('DROP TRIGGER reject_favorite');
      await tester.tap(find.text('加入书架'));
      await tester.pumpAndSettle();
      expect(find.text('移出书架'), findsOneWidget);
      expect(find.text('收藏未能保存，请重试；仍可继续阅读。'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await catalog.closeReadingProgress();
    },
  );
}
