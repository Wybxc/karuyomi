import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/runtime/platform_runtime_native.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'native_app.dart';

const _origin = String.fromEnvironment('APP_ORIGIN');
const _phase = String.fromEnvironment('MANGA_SETTINGS_PHASE');
const _buildId = String.fromEnvironment('MANGA_SETTINGS_BUILD_ID');
const _testCa = String.fromEnvironment('MANGA_SETTINGS_TEST_CA_BASE64');
const _controlKey = String.fromEnvironment('MANGA_SETTINGS_CONTROL_KEY');
const _baseAccount = int.fromEnvironment('MANGA_SETTINGS_BASE_ACCOUNT');
const _subject = 'acceptance-owner';
const _pkg = 'eu.kanade.tachiyomi.extension.all.xkcd';
const _source = '1538249443376436084';
const _url = 'SINGLE';
const _chapterUrl = '/3319/';
const _budget = Duration(seconds: 120);

const _overrideMode = wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT;
const _overrideLayout = wire.ReaderPageLayout.READER_PAGE_LAYOUT_SINGLE;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native manga settings sync: $_phase', (tester) async {
    final origin = Uri.tryParse(_origin);
    final prior = switch (_phase) {
      'prime' || 'set' => 0,
      'clear' => 1,
      'verify' => 2,
      _ => fail('MANGA_SETTINGS_PHASE 必须为 prime、set、clear 或 verify'),
    };
    if ((!Platform.isAndroid && !Platform.isIOS) ||
        origin == null ||
        origin.scheme != 'https' ||
        origin.host != '127.0.0.1' ||
        !origin.hasPort ||
        origin.origin != _origin ||
        _buildId.isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(_controlKey) ||
        (_phase != 'prime' && _baseAccount <= 0)) {
      fail('须提供隔离 HTTPS 回环 origin、精确构建与负对照 mangaKey，验收阶段须提供已确认账户基线');
    }
    if (_testCa.isNotEmpty) {
      if (!Platform.isAndroid) fail('测试 CA 仅用于 Android HTTPS 回环');
      SecurityContext.defaultContext.setTrustedCertificatesBytes(
        base64Decode(_testCa),
      );
    }
    final catalog = await startNativeApp(tester);
    final shelf = find.byType(LibraryPage);
    final platform = catalog.api;
    if (platform is! NativePlatformRuntime) fail('必须使用正式 Native 运行时');
    expect(platform.origin.origin, origin.origin);
    late final Map<String, Object?> report;
    try {
      await _wait(tester, '正式书架', () {
        _checkCatalog(catalog);
        return catalog.status == ServiceStatus.ready && catalog.library != null;
      });
      final library = catalog.library!;
      final client = library.client;
      expect(client.identity.subject, _subject);
      expect(client.identity.origin.origin, origin.origin);
      final view = await library.watchView().first.timeout(_budget);
      expect(view.entries, hasLength(2));
      expect(
        view.entries.map((entry) => entry.mangaKey),
        contains(_controlKey),
      );
      final target = view.entries.singleWhere(
        (entry) =>
            entry.packageName == _pkg &&
            entry.sourceId == _source &&
            entry.url == _url,
      );
      expect(target.mangaKey, isNot(_controlKey));
      expect(view.entries.every((entry) => entry.customCover == null), isTrue);
      final before = await _snapshot(client, target.mangaKey, _controlKey);
      _expectSettings(before, prior);
      if (_phase != 'prime') {
        expect(before.global.accountRevision, _baseAccount + prior);
        final progress = before.target.progress.entries.single;
        expect(progress.current.pageIndexHint, 0);
        expect(progress.furthest.pageIndexHint, 1);
        expect(before.target.state.manga.hasResume(), isTrue);
      }

      final shelfCard = find.byKey(ValueKey(target.mangaKey));
      final tile = find.descendant(
        of: shelfCard,
        matching: find.byType(ListTile),
      );
      final title = find.descendant(
        of: tile,
        matching: find.text(target.title),
      );
      await _tap(tester, title, scrollWithin: shelf);
      final detail = find.byType(MangaDetailsPage);
      await _wait(tester, '真实 xkcd 详情', () {
        _checkCatalog(catalog);
        return detail.evaluate().length == 1;
      });
      final details = tester.widget<MangaDetailsPage>(detail);
      expect(details.controller, same(catalog));
      expect(details.source.buildId, _buildId);
      expect(details.source.sourceId, _source);
      expect(details.manga.url, _url);
      final sequence = ChapterSequence(
        packageName: _pkg,
        sourceId: _source,
        mangaUrl: _url,
        chapters: details.chapters.map((chapter) => chapter.snapshot),
      );
      expect(sequence.mangaKey, target.mangaKey);
      final chapter = sequence.entries.singleWhere(
        (entry) => entry.snapshot.url == _chapterUrl,
      );
      expect(chapter.stable, isTrue);
      final chapterTile = find.byKey(ValueKey(chapter.key));
      await _tap(tester, chapterTile, scrollWithin: detail);
      final reader = find.byType(ReaderScreen);
      final settingsButton = find.text('阅读设置');
      await _waitForPage(tester, catalog, reader, 1);
      final route = tester.widget<ChapterReaderRoute>(
        find.byType(ChapterReaderRoute),
      );
      final initialReader = tester.widget<ReaderScreen>(reader);
      expect(route.sequence.mangaKey, target.mangaKey);
      expect(route.initialChapter.key, chapter.key);
      expect(initialReader.manifest.chapterKey, chapter.key);
      expect(initialReader.manifest.pages, hasLength(2));

      var expectedRevision = prior;
      if (_phase == 'prime') {
        // Fully observe the second page before returning to page one. A
        // settings reflow on page one must not create a first furthest anchor.
        await _turnPage(tester, catalog, reader, tooltip: '下一页', page: 2);
        await _waitForSavedFurthest(tester);
        await _turnPage(tester, catalog, reader, tooltip: '上一页', page: 1);
        await _waitForSavedFurthest(tester);
      } else {
        await tester.pump(const Duration(seconds: 1));
        final opened = await _snapshot(client, target.mangaKey, _controlKey);
        _expectTransition(before, opened, writes: 0);
        _expectReader(
          tester.widget<ReaderScreen>(reader),
          overridden: prior == 1,
        );

        await _tap(tester, settingsButton);
        final panel = find.byType(MangaSettingsEditor);
        await _wait(tester, '漫画设置面板取得权威值', () {
          if (panel.evaluate().length != 1) return false;
          final editor = tester.widget<MangaSettingsEditor>(panel).controller;
          if (editor.error != null) fail('设置面板错误：${editor.error}');
          return editor.canEdit && editor.snapshot != null;
        });
        final editor = tester.widget<MangaSettingsEditor>(panel).controller;
        expect(editor.mangaKey, target.mangaKey);
        expect(editor.repository, same(catalog.settings));
        expect(editor.snapshot!.mangaRevision, prior);
        expect(editor.pending, isNull);
        _expectForm(prior == 1);

        if (_phase == 'set' || _phase == 'clear') {
          final set = _phase == 'set';
          await _choose<wire.ReaderMode>(
            tester,
            panel,
            'manga-mode',
            set ? null : _overrideMode,
            set ? '从右到左' : '跟随全局',
          );
          await _choose<wire.ReaderPageLayout>(
            tester,
            panel,
            'manga-layout',
            set ? null : _overrideLayout,
            set ? '单页' : '跟随全局',
          );
          await _choose<bool>(
            tester,
            panel,
            'manga-crop-borders',
            set ? null : false,
            set ? '关闭' : '跟随全局',
          );
          _expectForm(set);
          expect(editor.snapshot!.mangaRevision, prior);
          final draft = await _snapshot(client, target.mangaKey, _controlKey);
          _expectTransition(before, draft, writes: 0);
          await _tap(
            tester,
            find.widgetWithText(FilledButton, '保存本漫画设置'),
            scrollWithin: panel,
          );
          expectedRevision++;
          await _wait(tester, '本漫画设置获得服务端确认', () {
            if (editor.error != null) fail('漫画设置保存失败：${editor.error}');
            return !editor.busy &&
                editor.pending == null &&
                editor.snapshot?.mangaRevision == expectedRevision;
          });
          _expectForm(set);
        }
        await tester.binding.handlePopRoute();
        await _wait(tester, '返回原阅读器', () => panel.evaluate().isEmpty);
        final finalReader = tester.widget<ReaderScreen>(reader);
        expect(finalReader.provider, same(initialReader.provider));
        expect(finalReader.key, initialReader.key);
        _expectReader(finalReader, overridden: expectedRevision == 1);
        expect(find.text('1 / 2'), findsOneWidget);
      }

      await tester.pump(const Duration(seconds: 1));
      await _tap(tester, find.byType(BackButton));
      await _wait(
        tester,
        '返回详情并释放章节资源',
        () =>
            reader.evaluate().isEmpty &&
            chapterTile.evaluate().length == 1 &&
            tester.widget<ListTile>(chapterTile).enabled,
      );
      expect(catalog.hasUnsavedReadingProgress, isFalse);
      expect(tester.takeException(), isNull);
      final after = await _snapshot(client, target.mangaKey, _controlKey);
      _expectSettings(after, expectedRevision);
      if (_phase == 'prime') {
        final progress = after.target.progress.entries.single;
        expect(progress.chapterKey, chapter.key);
        expect(
          progress.current.pageKey,
          initialReader.manifest.pages.first.key,
        );
        expect(
          progress.furthest.pageKey,
          initialReader.manifest.pages.last.key,
        );
        expect(after.target.state.manga.resume.chapterKey, chapter.key);
      } else {
        _expectTransition(before, after, writes: expectedRevision - prior);
      }
      report = {
        'platform': Platform.operatingSystem,
        'phase': _phase,
        'origin': origin.origin,
        'subject': _subject,
        'buildId': _buildId,
        'mangaKey': target.mangaKey,
        'controlMangaKey': _controlKey,
        'chapterKey': chapter.key,
        'pageKey': initialReader.manifest.pages.first.key,
        'accountRevision': after.global.accountRevision,
        'mangaStateRevision': after.target.state.manga.revision,
        'globalRevision': after.global.global.revision,
        'progress': wire.encodeProtoJson(after.target.progress.entries.single),
        'mangaSettings': wire.encodeProtoJson(after.target.settings.manga),
        'effectiveReader': wire.encodeProtoJson(
          after.target.settings.effectiveReader,
        ),
      };
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink()).timeout(_budget);
        await tester.pump().timeout(_budget);
        await catalog.closeReadingProgress().timeout(_budget);
      } finally {
        await platform.dispose().timeout(_budget);
      }
    }
    binding.reportData = {'MANGA_SETTINGS_SYNC_RESULT': report};
    debugPrint('MANGA_SETTINGS_SYNC_RESULT ${jsonEncode(report)}');
  }, timeout: const Timeout(Duration(minutes: 12)));
}

typedef _Scope = ({
  wire.SettingsResponse settings,
  wire.MangaStateResponse state,
  BusinessChapterProgressSnapshot progress,
  BusinessBookmarksSnapshot bookmarks,
});
typedef _Snapshot = ({
  wire.SettingsResponse global,
  _Scope target,
  _Scope control,
});

Future<_Snapshot> _snapshot(
  BusinessStateClient client,
  String target,
  String control,
) async {
  final global = await client.readSettings().timeout(_budget);
  Future<_Scope> manga(String key) async {
    final settings = await client.readSettings(mangaKey: key).timeout(_budget);
    final state = await client.readManga(key).timeout(_budget);
    final progress = await client.readChapterProgress(key).timeout(_budget);
    final bookmarks = await client.readBookmarks(key).timeout(_budget);
    for (final revision in [
      settings.accountRevision,
      state.accountRevision,
      progress.accountRevision,
      bookmarks.accountRevision,
    ]) {
      expect(revision, global.accountRevision);
    }
    expect(settings.manga.mangaKey, key);
    expect(
      wire.encodeProtoJson(settings.global),
      wire.encodeProtoJson(global.global),
    );
    expect(
      wire.encodeProtoJson(progress.manga),
      wire.encodeProtoJson(state.manga),
    );
    expect(
      wire.encodeProtoJson(bookmarks.manga),
      wire.encodeProtoJson(state.manga),
    );
    expect(state.manga.favorite, isTrue);
    return (
      settings: settings,
      state: state,
      progress: progress,
      bookmarks: bookmarks,
    );
  }

  return (
    global: global,
    target: await manga(target),
    control: await manga(control),
  );
}

void _expectSettings(_Snapshot snapshot, int revision) {
  final global = snapshot.global;
  final inherited = global.effectiveReader;
  expect(global.global.revision, 1);
  expect(inherited.mode, wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT);
  expect(inherited.pageLayout, wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO);
  expect(inherited.cropBorders, isFalse);
  expect(snapshot.control.settings.manga.revision, 0);
  expect(
    wire.encodeProtoJson(snapshot.control.settings.manga.overrides),
    isEmpty,
  );
  expect(
    wire.encodeProtoJson(snapshot.control.settings.effectiveReader),
    wire.encodeProtoJson(inherited),
  );
  final target = snapshot.target.settings;
  expect(target.manga.revision, revision);
  final override = wire.ReaderSettingsOverride();
  final effective = inherited.deepCopy();
  if (revision == 1) {
    override
      ..mode = _overrideMode
      ..pageLayout = _overrideLayout
      ..cropBorders = false;
    effective
      ..mode = _overrideMode
      ..pageLayout = _overrideLayout;
  }
  expect(
    wire.encodeProtoJson(target.manga.overrides),
    wire.encodeProtoJson(override),
  );
  expect(
    wire.encodeProtoJson(target.effectiveReader),
    wire.encodeProtoJson(effective),
  );
}

void _expectTransition(
  _Snapshot before,
  _Snapshot after, {
  required int writes,
}) {
  final account = before.global.accountRevision + writes;
  expect(after.global.accountRevision, account);
  expect(
    wire.encodeProtoJson(after.global),
    wire.encodeProtoJson(before.global.deepCopy()..accountRevision = account),
  );
  expect(
    wire.encodeProtoJson(after.control.settings),
    wire.encodeProtoJson(
      before.control.settings.deepCopy()..accountRevision = account,
    ),
  );
  if (writes == 0) {
    expect(
      wire.encodeProtoJson(after.target.settings),
      wire.encodeProtoJson(before.target.settings),
    );
  }
  for (final (a, b) in [
    (before.target, after.target),
    (before.control, after.control),
  ]) {
    expect(
      wire.encodeProtoJson(b.state),
      wire.encodeProtoJson(a.state.deepCopy()..accountRevision = account),
    );
    expect(
      b.progress.entries.map(wire.encodeProtoJson).toList(),
      a.progress.entries.map(wire.encodeProtoJson).toList(),
    );
    expect(
      b.bookmarks.entries.map(wire.encodeProtoJson).toList(),
      a.bookmarks.entries.map(wire.encodeProtoJson).toList(),
    );
  }
}

void _expectReader(ReaderScreen reader, {required bool overridden}) {
  expect(
    reader.initialMode,
    overridden ? ReadingMode.rightToLeft : ReadingMode.leftToRight,
  );
  expect(reader.doublePage, overridden ? false : null);
  expect(reader.cropBorders, isFalse);
}

Finder _field<T>(String id, T? value) => find.byKey(ValueKey((id, value)));

void _expectForm(bool overridden) {
  expect(
    _field<wire.ReaderMode>('manga-mode', overridden ? _overrideMode : null),
    findsOneWidget,
  );
  expect(
    _field<wire.ReaderPageLayout>(
      'manga-layout',
      overridden ? _overrideLayout : null,
    ),
    findsOneWidget,
  );
  expect(
    _field<bool>('manga-crop-borders', overridden ? false : null),
    findsOneWidget,
  );
}

Future<void> _choose<T>(
  WidgetTester tester,
  Finder panel,
  String id,
  T? current,
  String label,
) async {
  await _tap(tester, _field(id, current), scrollWithin: panel);
  await _tap(tester, find.text(label).hitTestable().last);
}

Future<void> _waitForPage(
  WidgetTester tester,
  CatalogController catalog,
  Finder reader,
  int page,
) => _wait(tester, '第 $page 页显示真实解码帧', () {
  _checkCatalog(catalog);
  final image = find.descendant(
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
  return reader.evaluate().length == 1 &&
      find.text('$page / 2').evaluate().length == 1 &&
      image.evaluate().isNotEmpty;
});

Future<void> _turnPage(
  WidgetTester tester,
  CatalogController catalog,
  Finder reader, {
  required String tooltip,
  required int page,
}) async {
  await _tap(
    tester,
    find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == tooltip,
    ),
  );
  await _waitForPage(tester, catalog, reader, page);
}

Future<void> _waitForSavedFurthest(WidgetTester tester) => _wait(
  tester,
  '服务端已确认第 2 页最远进度',
  () =>
      find.text('阅读进度已保存到服务端').evaluate().length == 1 &&
      find.textContaining(RegExp(r'^最远：第 2 页')).evaluate().length == 1,
);

void _checkCatalog(CatalogController catalog) {
  if (catalog.accessPaused || catalog.status == ServiceStatus.failed) {
    fail('正式 Source 或服务不可用：${catalog.error ?? catalog.status.name}');
  }
}

Future<void> _wait(
  WidgetTester tester,
  String label,
  bool Function() done,
) async {
  final elapsed = Stopwatch()..start();
  while (!done()) {
    if (elapsed.elapsed >= _budget) fail('$label 超时');
    await tester.pump(const Duration(milliseconds: 100)).timeout(_budget);
  }
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollWithin,
}) async {
  if (scrollWithin != null && finder.evaluate().isEmpty) {
    final scroll = find
        .descendant(of: scrollWithin, matching: find.byType(Scrollable))
        .first;
    await tester
        .scrollUntilVisible(finder, 280, scrollable: scroll)
        .timeout(_budget);
  }
  await _wait(tester, '正式控件存在：$finder', () => finder.evaluate().length == 1);
  await tester.ensureVisible(finder).timeout(_budget);
  await tester.pump(const Duration(milliseconds: 300));
  await _wait(
    tester,
    '正式控件可点击：$finder',
    () => finder.hitTestable().evaluate().length == 1,
  );
  await tester.tap(finder).timeout(_budget);
  await tester.pump(const Duration(milliseconds: 300));
}
