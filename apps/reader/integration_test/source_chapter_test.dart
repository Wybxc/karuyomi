import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/main.dart' as app;
import 'package:karuyomi/runtime/platform_runtime_native.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

const _origin = String.fromEnvironment('APP_ORIGIN');
const _testCa = String.fromEnvironment('SOURCE_CHAPTER_TEST_CA_BASE64');
const _packageName = String.fromEnvironment('SOURCE_CHAPTER_PACKAGE');
const _sourceId = String.fromEnvironment('SOURCE_CHAPTER_SOURCE');
const _buildId = String.fromEnvironment('SOURCE_CHAPTER_BUILD');
const _mangaUrl = String.fromEnvironment('SOURCE_CHAPTER_MANGA');
const _firstUrl = String.fromEnvironment('SOURCE_CHAPTER_FIRST');
const _nextUrl = String.fromEnvironment('SOURCE_CHAPTER_NEXT');
const _firstPages = int.fromEnvironment('SOURCE_CHAPTER_FIRST_PAGES');
const _nextPages = int.fromEnvironment('SOURCE_CHAPTER_NEXT_PAGES');
const _savedPage = int.fromEnvironment('SOURCE_CHAPTER_SAVED_PAGE');
const _resumeThrough = int.fromEnvironment('SOURCE_CHAPTER_RESUME_THROUGH');
const _reversed = bool.fromEnvironment('SOURCE_CHAPTER_REVERSED');
const _phase = String.fromEnvironment('SOURCE_CHAPTER_PHASE');
const _subject = 'acceptance-owner';
const _budget = Duration(seconds: 120);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native real Source full chapter: $_phase', (tester) async {
    final origin = Uri.parse(_origin);
    expect(Platform.isIOS || Platform.isAndroid, isTrue);
    expect(origin.scheme, 'https');
    expect(origin.host, '127.0.0.1');
    expect(origin.hasPort, isTrue);
    expect(origin.userInfo, isEmpty);
    expect(origin.origin, _origin);
    expect([
      _packageName,
      _sourceId,
      _buildId,
      _mangaUrl,
      _firstUrl,
      _nextUrl,
    ], everyElement(isNotEmpty));
    expect(_firstUrl, isNot(_nextUrl));
    expect(_phase, anyOf('read', 'resume'));
    expect(_firstPages, greaterThan(1));
    expect(_savedPage, greaterThanOrEqualTo(2));
    if (_nextPages != 0) expect(_nextPages, greaterThanOrEqualTo(_savedPage));
    if (_phase == 'resume') {
      expect(_resumeThrough, greaterThanOrEqualTo(_savedPage));
      if (_nextPages != 0) {
        expect(_resumeThrough, lessThanOrEqualTo(_nextPages));
      }
    }
    if (_testCa.isNotEmpty) {
      expect(Platform.isAndroid, isTrue);
      SecurityContext.defaultContext.setTrustedCertificatesBytes(
        base64Decode(_testCa),
      );
    }

    final identity = ChapterSequence(
      packageName: _packageName,
      sourceId: _sourceId,
      mangaUrl: _mangaUrl,
      chapters: [
        wire.Chapter(url: _firstUrl),
        wire.Chapter(url: _nextUrl),
      ],
    );
    final mangaKey = identity.mangaKey;
    final firstKey = identity.entries.first.key;
    final nextKey = identity.entries.last.key;
    app.main();
    await tester.pump();
    final catalog = tester
        .widget<LibraryPage>(find.byType(LibraryPage))
        .controller!;
    final platform = catalog.api;
    expect(platform, isA<NativePlatformRuntime>());
    expect((platform as NativePlatformRuntime).origin.origin, _origin);

    late final wire.MangaStateResponse firstSaved;
    late final wire.MangaStateResponse nextSaved;
    try {
      await _wait(tester, '正式 Native 书架与同一身份', () {
        if (catalog.accessPaused || catalog.error != null) {
          fail('正式 Native 书架连接失败：${catalog.error}');
        }
        return catalog.status == ServiceStatus.ready && catalog.library != null;
      });
      expect(catalog.subject, _subject);
      final client = catalog.library!.client;
      final entry = (await catalog.library!.watchView().first.timeout(
        _budget,
      )).entries.singleWhere((entry) => entry.mangaKey == mangaKey);
      expect(entry.url, _mangaUrl);
      final firstBefore = await _inspect(client, mangaKey, firstKey);
      final nextBefore = await _inspect(client, mangaKey, nextKey);
      if (_phase == 'read') {
        expect(firstBefore.hasProgress(), isFalse);
        expect(nextBefore.hasProgress(), isFalse);
        final card = find.byKey(ValueKey(mangaKey));
        await _tap(
          tester,
          find.descendant(of: card, matching: find.text(entry.title)),
        );
        final detailsFinder = find.byType(MangaDetailsPage);
        await _wait(
          tester,
          '真实 Source 详情',
          () => detailsFinder.evaluate().length == 1,
        );
        final details = tester.widget<MangaDetailsPage>(detailsFinder);
        expect(details.source.buildId, _buildId);
        expect(details.source.sourceId, _sourceId);
        expect(details.manga.url, _mangaUrl);
        final sequence = ChapterSequence(
          packageName: _packageName,
          sourceId: _sourceId,
          mangaUrl: _mangaUrl,
          chapters: details.chapters.map((chapter) => chapter.snapshot),
        );
        final first = sequence.entries.singleWhere(
          (chapter) => chapter.key == firstKey,
        );
        final order = _reversed ? ChapterOrder.reversed : ChapterOrder.source;
        expect(sequence.adjacent(first.sourceIndex, order, 1)?.key, nextKey);
        final tile = find.byKey(ValueKey(firstKey));
        if (tile.evaluate().isEmpty) {
          final search = find.byKey(const ValueKey('chapter-search'));
          await tester.ensureVisible(search);
          await tester.enterText(search, first.name);
          await tester.testTextInput.receiveAction(TextInputAction.done);
        }
        await _tap(tester, tile);
        final firstManifest = await _open(
          tester,
          mangaKey,
          firstKey,
          _firstPages,
        );
        await _read(tester, firstManifest, 1, _firstPages);
        final orderButton = find.byType(DropdownButton<ChapterOrder>);
        if (tester.widget<DropdownButton<ChapterOrder>>(orderButton).value !=
            order) {
          await _tap(tester, orderButton);
          await _tap(tester, find.text(_reversed ? '反向来源顺序' : '来源顺序').last);
        }
        final complete = find.widgetWithText(TextButton, '读完本章');
        await _wait(
          tester,
          '末页可以显式确认读完',
          () =>
              complete.evaluate().length == 1 &&
              tester.widget<TextButton>(complete).onPressed != null,
        );
        await _tap(tester, complete);
        firstSaved = await _confirmed(
          tester,
          client,
          mangaKey,
          firstManifest,
          _firstPages,
          completed: true,
        );
        final next = find.ancestor(
          of: find.text('下一章'),
          matching: find.byWidgetPredicate((widget) => widget is TextButton),
        );
        await _wait(
          tester,
          '正式下一章入口可用',
          () =>
              next.evaluate().length == 1 &&
              tester.widget<TextButton>(next).onPressed != null,
        );
        await _tap(tester, next);
      } else {
        expect(firstBefore.progress.completed, isTrue);
        expect(firstBefore.progress.current.pageIndexHint, _firstPages - 1);
        expect(firstBefore.progress.furthest.pageIndexHint, _firstPages - 1);
        expect(nextBefore.hasProgress(), isTrue);
        expect(nextBefore.manga.resume.chapterKey, nextKey);
        expect(nextBefore.manga.resume.reversedOrder, _reversed);
        expect(nextBefore.progress.current.pageIndexHint, _savedPage - 1);
        expect(nextBefore.progress.furthest.pageIndexHint, _savedPage - 1);
        expect(nextBefore.progress.completed, isFalse);
        firstSaved = firstBefore;
        await _tap(
          tester,
          find.byKey(ValueKey(('library-continue', mangaKey))),
        );
      }

      final nextManifest = await _open(tester, mangaKey, nextKey, _nextPages);
      if (_phase == 'resume') {
        expect(
          find.byType(MangaDetailsPage, skipOffstage: false),
          findsNothing,
        );
        final anchor = nextBefore.progress.current;
        expect(nextManifest.version, anchor.manifestVersion);
        expect(nextManifest.pages[_savedPage - 1].key, anchor.pageKey);
      }
      final target = _phase == 'read' ? _savedPage : _resumeThrough;
      await _read(
        tester,
        nextManifest,
        _phase == 'read' ? 1 : _savedPage,
        target,
      );
      nextSaved = await _confirmed(
        tester,
        client,
        mangaKey,
        nextManifest,
        target,
      );
      expect(nextSaved.manga.resume.chapterKey, nextKey);
      expect(nextSaved.manga.resume.reversedOrder, _reversed);
      expect(
        (await _inspect(client, mangaKey, firstKey)).progress,
        firstSaved.progress,
      );
      expect(tester.takeException(), isNull);
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink()).timeout(_budget);
        await tester.pump().timeout(_budget);
        await catalog.closeReadingProgress().timeout(_budget);
      } finally {
        await platform.dispose().timeout(_budget);
      }
    }
    final result = <String, Object?>{
      'phase': _phase,
      'platform': Platform.operatingSystem,
      'pid': pid,
      'mangaKey': mangaKey,
      'buildId': _buildId,
      'first': wire.encodeProtoJson(firstSaved),
      'next': wire.encodeProtoJson(nextSaved),
    };
    binding.reportData = {'SOURCE_CHAPTER_RESULT': result};
    debugPrintSynchronously('SOURCE_CHAPTER_RESULT ${jsonEncode(result)}');
  }, timeout: const Timeout(Duration(minutes: 15)));
}

Future<wire.MangaStateResponse> _inspect(
  BusinessStateClient client,
  String mangaKey,
  String chapterKey,
) => client.inspectManga(mangaKey, chapterKey: chapterKey).timeout(_budget);

Future<void> _wait(
  WidgetTester tester,
  String description,
  bool Function() ready,
) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    if (elapsed.elapsed >= _budget) fail('$description 超过 $_budget');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _wait(tester, '正式控件存在：$target', () => target.evaluate().length == 1);
  await tester.ensureVisible(target);
  await _wait(
    tester,
    '正式控件可点击：$target',
    () => target.hitTestable().evaluate().length == 1,
  );
  await tester.tap(target);
  await tester.pump();
}

Future<ChapterManifest> _open(
  WidgetTester tester,
  String mangaKey,
  String chapterKey,
  int pages,
) async {
  final reader = find.byType(ReaderScreen);
  await _wait(
    tester,
    '精确章节的正式 Reader',
    () =>
        reader.evaluate().length == 1 &&
        tester.widget<ReaderScreen>(reader).manifest.chapterKey == chapterKey,
  );
  final route = tester.widget<ChapterReaderRoute>(
    find.byType(ChapterReaderRoute),
  );
  expect(route.source.buildId, _buildId);
  expect(route.source.sourceId, _sourceId);
  expect(route.sequence.mangaKey, mangaKey);
  final manifest = tester.widget<ReaderScreen>(reader).manifest;
  if (pages != 0) expect(manifest.pages, hasLength(pages));
  final layout = tester.widget<SegmentedButton<bool?>>(
    find.byKey(const ValueKey('reader-page-layout')),
  );
  expect(
    layout.selected.contains(false) ||
        (layout.selected.contains(null) && tester.getSize(reader).width < 900),
    isTrue,
    reason: '使用手机自动单页或预先确认的单页设置',
  );
  return manifest;
}

Future<void> _read(
  WidgetTester tester,
  ChapterManifest manifest,
  int from,
  int to,
) async {
  expect(from, inInclusiveRange(1, to));
  expect(to, lessThanOrEqualTo(manifest.pages.length));
  for (var page = from; page <= to; page++) {
    if (page != from) {
      final next = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '下一页',
      );
      await _wait(
        tester,
        '正式下一页控件可用',
        () =>
            next.evaluate().length == 1 &&
            tester.widget<IconButton>(next).onPressed != null,
      );
      await _tap(tester, next);
    }
    final image = find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == '第 $page 页',
      ),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RawImage &&
            widget.image != null &&
            widget.image!.width > 0 &&
            widget.image!.height > 0,
      ),
    );
    await _wait(
      tester,
      '第 $page 页的真实解码帧和当前页码',
      () =>
          find.text('$page / ${manifest.pages.length}').evaluate().length ==
              1 &&
          image.evaluate().isNotEmpty,
    );
    final decoded = tester.widget<RawImage>(image.first).image!;
    debugPrintSynchronously(
      'SOURCE_CHAPTER_FRAME ${manifest.chapterKey} $page ${decoded.width}x${decoded.height}',
    );
  }
}

Future<wire.MangaStateResponse> _confirmed(
  WidgetTester tester,
  BusinessStateClient client,
  String mangaKey,
  ChapterManifest manifest,
  int page, {
  bool completed = false,
}) async {
  final elapsed = Stopwatch()..start();
  while (elapsed.elapsed < _budget) {
    if (find.text('阅读进度已保存到服务端').evaluate().length == 1) {
      final state = await _inspect(client, mangaKey, manifest.chapterKey);
      final progress = state.progress;
      final key = manifest.pages[page - 1].key;
      if (progress.current.pageKey == key &&
          progress.furthest.pageKey == key &&
          progress.completed == completed) {
        expect(progress.current.manifestVersion, manifest.version);
        expect(progress.furthest.manifestVersion, manifest.version);
        return state;
      }
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('D1 未在预算内确认第 $page 页，完成状态：$completed');
}
