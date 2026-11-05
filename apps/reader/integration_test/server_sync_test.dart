import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/main.dart' as app;
import 'package:karuyomi/runtime/platform_runtime_native.dart';
import 'package:reader_core/reader_core.dart';

const _origin = String.fromEnvironment('APP_ORIGIN');
const _chapterLabel = String.fromEnvironment(
  'SYNC_CHAPTER_LABEL',
  defaultValue: '3319: Elevators',
);
const _startPage = int.fromEnvironment('SYNC_START_PAGE', defaultValue: 1);
const _targetPage = int.fromEnvironment('SYNC_TARGET_PAGE', defaultValue: 2);
const _operationBudget = Duration(seconds: 120);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Native reads and confirms shared server progress with real Source images',
    (tester) async {
      _validateConfiguration();
      app.main();
      await tester.pump();

      final catalog = tester
          .widget<LibraryPage>(find.byType(LibraryPage))
          .controller;
      expect(catalog, isNotNull, reason: '正式 App 必须创建 CatalogController');
      final platform = catalog!.api;
      if (platform is! NativePlatformRuntime) {
        fail('此验收必须使用正式 NativePlatformRuntime');
      }
      expect(platform.origin.origin, Uri.parse(_origin).origin);
      late final Map<String, Object?> result;

      try {
        final mangaTile = find.widgetWithText(ListTile, 'xkcd');
        await _waitFor(tester, '已登录 Native 的服务端 xkcd 书架', () {
          if (catalog.accessPaused) {
            fail('请先在此 Native 安装中完成正式 Access 登录，再运行同步验收');
          }
          return catalog.status == ServiceStatus.ready &&
              mangaTile.evaluate().length == 1 &&
              tester.widget<ListTile>(mangaTile).onTap != null;
        });
        await tester.ensureVisible(mangaTile);
        await tester.pump();
        await tester.tap(mangaTile);
        await _waitFor(
          tester,
          '正式 Source 返回漫画详情和指定章节',
          () =>
              find.byType(MangaDetailsPage).evaluate().length == 1 &&
              find.widgetWithText(ListTile, _chapterLabel).evaluate().length ==
                  1,
        );
        final chapterTile = find.widgetWithText(ListTile, _chapterLabel);
        await tester.ensureVisible(chapterTile);
        await tester.pump();
        await tester.tap(chapterTile);
        await _waitFor(
          tester,
          '正式阅读页完成进度恢复',
          () => find.byType(ReaderScreen).evaluate().length == 1,
        );

        final route = tester.widget<ChapterReaderRoute>(
          find.byType(ChapterReaderRoute),
        );
        final reader = tester.widget<ReaderScreen>(find.byType(ReaderScreen));
        final manifest = reader.manifest;
        final mangaKey = route.sequence.mangaKey;
        expect(identical(route.catalog, catalog), isTrue);
        expect(route.initialChapter.name, _chapterLabel);
        expect(_startPage, lessThanOrEqualTo(manifest.pages.length));
        expect(_targetPage, lessThanOrEqualTo(manifest.pages.length));

        // Use the reader's ordinary preference so one button press is one page
        // on phones and wider native windows alike.
        final doublePage = find.widgetWithText(FilterChip, '双页');
        expect(doublePage, findsOneWidget);
        if (tester.widget<FilterChip>(doublePage).selected) {
          await tester.tap(doublePage);
          await tester.pump();
        }
        await _waitForPage(tester, manifest, _startPage);

        var page = _startPage;
        while (page != _targetPage) {
          final direction = page < _targetPage ? 1 : -1;
          final label = direction > 0 ? '下一页' : '上一页';
          final button = find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == label,
          );
          expect(tester.widget<IconButton>(button).onPressed, isNotNull);
          await tester.tap(button);
          page += direction;
          await _waitForPage(tester, manifest, page);
        }

        await _waitFor(tester, '当前页和最远进度获得服务端确认', () {
          final furthest = _displayedFurthestPage(tester);
          return find.text('阅读进度已保存到服务端').evaluate().length == 1 &&
              furthest != null &&
              furthest >= max(_startPage, _targetPage);
        });
        final repository = catalog.readingProgress;
        expect(repository, isNotNull);
        final verification = Stopwatch()..start();
        ChapterProgress? progress;
        while (true) {
          final remaining = _operationBudget - verification.elapsed;
          if (remaining <= Duration.zero) {
            fail('正式 Worker 读回未在预算内确认目标页及最远进度');
          }
          progress = await repository!
              .loadChapter(mangaKey: mangaKey, chapterKey: manifest.chapterKey)
              .timeout(remaining);
          if (progress != null &&
              progress.current.pageIndexHint == _targetPage - 1 &&
              (progress.furthest?.pageIndexHint ?? -1) >=
                  max(_startPage, _targetPage) - 1 &&
              find.text('阅读进度已保存到服务端').evaluate().length == 1) {
            break;
          }
          // A decoded frame can precede its post-frame viewport notification.
          // In reverse navigation the old saved/furthest labels alone are not
          // proof that the new current page has reached the Worker.
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(progress, isNotNull);
        _expectConfirmedProgress(progress, manifest);

        result = <String, Object?>{
          'platform': Platform.operatingSystem,
          'origin': platform.origin.origin,
          'mangaKey': mangaKey,
          'chapterKey': manifest.chapterKey,
          'pageKey': manifest.pages[_targetPage - 1].key,
          'manifestVersion': manifest.version,
          'epoch': progress.epoch,
          'startPage': _startPage,
          'targetPage': _targetPage,
          'current': _anchor(progress.current),
          'furthest': _anchor(progress.furthest!),
        };

        // The details page enables its chapters only after the actual route
        // completion and closeChapter ACK. Do not dispose the runtime first.
        await tester.tap(find.byType(BackButton));
        await _waitFor(
          tester,
          '返回详情并完成章节资源 ACK',
          () =>
              find.byType(ReaderScreen).evaluate().isEmpty &&
              chapterTile.evaluate().length == 1 &&
              tester.widget<ListTile>(chapterTile).enabled,
        );
        // close() reuses the provider's real ACK future, including failures.
        await route.initialOpened.provider.close().timeout(_operationBudget);
        expect(catalog.hasUnsavedReadingProgress, isFalse);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await catalog.closeReadingProgress().timeout(_operationBudget);
        } finally {
          // AppShell starts this same idempotent disposal future on unmount.
          // Await it explicitly so WebView/file cleanup errors fail this test.
          await platform.dispose().timeout(_operationBudget);
        }
      }
      binding.reportData = {'SYNC_RESULT': result};
      debugPrint('SYNC_RESULT ${jsonEncode(result)}');
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

void _validateConfiguration() {
  final origin = Uri.tryParse(_origin);
  if (origin == null ||
      origin.scheme != 'https' ||
      origin.host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      (origin.path.isNotEmpty && origin.path != '/')) {
    fail('APP_ORIGIN 必须是单一 HTTPS 服务源，不能含凭据、路径、查询或 fragment');
  }
  if (!Platform.isAndroid && !Platform.isIOS) {
    fail('此正式 Native 同步验收仅适用于 Android 或 iOS 设备/模拟器');
  }
  if (_chapterLabel.isEmpty || _startPage < 1 || _targetPage < 1) {
    fail('SYNC_CHAPTER_LABEL 不能为空，SYNC_START_PAGE / SYNC_TARGET_PAGE 须大于零');
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  String operation,
  bool Function() ready,
) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    if (elapsed.elapsed >= _operationBudget) {
      fail('$operation 超过 ${_operationBudget.inSeconds} 秒预算');
    }
    // Real integration binding keeps network/plugin events running. A bounded
    // pump also works while loading indicators or image animations keep ticking.
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForPage(
  WidgetTester tester,
  ChapterManifest manifest,
  int page,
) => _waitFor(tester, '第 $page 页的真实 UI 解码帧及当前页码', () {
  final pageImage = find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == '第 $page 页',
    ),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is RawImage &&
          widget.image != null &&
          widget.image!.width > 0 &&
          widget.image!.height > 0,
    ),
  );
  return find.text('$page / ${manifest.pages.length}').evaluate().length == 1 &&
      pageImage.evaluate().isNotEmpty;
});

int? _displayedFurthestPage(WidgetTester tester) {
  final expression = RegExp(r'^最远：第 (\d+) 页');
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final match = expression.firstMatch(text.data ?? '');
    if (match != null) return int.parse(match.group(1)!);
  }
  return null;
}

void _expectConfirmedProgress(
  ChapterProgress progress,
  ChapterManifest manifest,
) {
  expect(progress.current.chapterKey, manifest.chapterKey);
  expect(progress.current.manifestVersion, manifest.version);
  expect(progress.current.pageIndexHint, _targetPage - 1);
  expect(progress.current.pageKey, manifest.pages[_targetPage - 1].key);
  expect(progress.furthest, isNotNull);
  final furthest = progress.furthest!;
  expect(furthest.chapterKey, manifest.chapterKey);
  expect(furthest.manifestVersion, manifest.version);
  expect(
    furthest.pageIndexHint,
    greaterThanOrEqualTo(max(_startPage, _targetPage) - 1),
  );
  expect(furthest.pageIndexHint, lessThan(manifest.pages.length));
  expect(furthest.pageKey, manifest.pages[furthest.pageIndexHint].key);
}

Map<String, Object?> _anchor(ReadingPosition value) => {
  'chapterKey': value.chapterKey,
  'pageKey': value.pageKey,
  'manifestVersion': value.manifestVersion,
  'pageIndex': value.pageIndexHint,
  'page': value.pageIndexHint + 1,
  'normalizedOffset': value.normalizedOffset,
  'normalizedX': value.normalizedX,
  'viewportX': value.viewportX,
  'viewportY': value.viewportY,
};
