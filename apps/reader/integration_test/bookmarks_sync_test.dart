import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:karuyomi/data/bookmark_repository.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/business_state_validation.dart';
import 'package:karuyomi/features/bookmarks/bookmark_status.dart';
import 'package:karuyomi/features/bookmarks/chapter_bookmarks_controller.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/main.dart' as app;
import 'package:karuyomi/runtime/platform_runtime_native.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

const _origin = String.fromEnvironment('APP_ORIGIN');
const _subject = String.fromEnvironment('BOOKMARKS_SUBJECT');
const _packageName = String.fromEnvironment('BOOKMARKS_PACKAGE_NAME');
const _sourceId = String.fromEnvironment('BOOKMARKS_SOURCE_ID');
const _mangaUrl = String.fromEnvironment('BOOKMARKS_MANGA_URL');
const _chapterUrl = String.fromEnvironment('BOOKMARKS_CHAPTER_URL');
const _phase = String.fromEnvironment('BOOKMARKS_PHASE');
const _settingsJson = String.fromEnvironment('BOOKMARKS_EXPECT_SETTINGS_JSON');
const _stateJson = String.fromEnvironment('BOOKMARKS_EXPECT_STATE_JSON');
const _bookmarksJson = String.fromEnvironment(
  'BOOKMARKS_EXPECT_BOOKMARKS_JSON',
);
const _testCaBase64 = String.fromEnvironment('BOOKMARKS_TEST_CA_BASE64');
const _operationBudget = Duration(seconds: 120);
const _totalBudget = Duration(minutes: 10);
final _elapsed = Stopwatch();

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Native chapter bookmarks sync: $_phase', (tester) async {
    _elapsed.start();
    final expected = _validateConfiguration();
    if (_testCaBase64.isNotEmpty) {
      SecurityContext.defaultContext.setTrustedCertificatesBytes(
        base64Decode(_testCaBase64),
      );
    }
    app.main();
    await tester.pump();
    final catalog = tester
        .widget<LibraryPage>(find.byType(LibraryPage))
        .controller;
    if (catalog == null) fail('正式 App 必须创建 CatalogController');
    final platform = catalog.api;
    if (platform is! NativePlatformRuntime) {
      fail('此验收必须使用正式 NativePlatformRuntime');
    }
    expect(platform.origin.origin, Uri.parse(_origin).origin);
    late final Map<String, Object?> result;

    try {
      await _waitFor(tester, 'Native 连接并取得同身份书架和书签仓储', () {
        _checkCatalog(catalog);
        return catalog.status == ServiceStatus.ready &&
            catalog.library != null &&
            catalog.bookmarks != null;
      });
      final library = catalog.library!;
      final repository = catalog.bookmarks!;
      final client = library.client;
      expect(identical(repository.client, client), isTrue);
      expect(client.identity.subject, _subject);
      expect(client.identity.origin.origin, platform.origin.origin);
      expect(catalog.session, isNull);
      final shelf = await library.watchView().first.timeout(_remaining());
      final matches = shelf.entries.where(
        (entry) =>
            entry.packageName == _packageName &&
            entry.sourceId == _sourceId &&
            entry.url == _mangaUrl,
      );
      expect(matches, hasLength(1), reason: '正式书架必须包含唯一精确 Source 作品');
      final entry = matches.single;
      expect(entry.mangaKey, expected.state.manga.mangaKey);
      expect(
        shelf.entries.every((entry) => entry.customCover == null),
        isTrue,
        reason: '本轮只验收书签，不加载任何书架自定义封面图片',
      );
      final before = await _readSnapshot(client, repository, entry.mangaKey);
      _expectConfigured(before, expected);
      expect(client.hasPendingMetadata(entry.mangaKey), isFalse);

      // Follow the product shelf's real onTap. Opening an unchanged Source
      // snapshot must remain read-only, including its metadata refresh path.
      final shelfCard = find.descendant(
        of: find.byType(LibraryPage),
        matching: find.byKey(ValueKey(entry.mangaKey)),
      );
      final shelfTile = find.descendant(
        of: shelfCard,
        matching: find.byType(ListTile),
      );
      await _reveal(tester, shelfTile, find.byType(LibraryPage));
      await _tap(tester, shelfTile);
      await _waitFor(tester, '真实 Source 详情和章节', () {
        _checkCatalog(catalog);
        return find.byType(MangaDetailsPage).evaluate().length == 1;
      });
      final details = tester.widget<MangaDetailsPage>(
        find.byType(MangaDetailsPage),
      );
      expect(identical(details.controller, catalog), isTrue);
      expect(catalog.activeBuild!.packageName, _packageName);
      expect(details.source.sourceId, _sourceId);
      expect(details.manga.url, _mangaUrl);
      final sequence = ChapterSequence(
        packageName: _packageName,
        sourceId: _sourceId,
        mangaUrl: details.manga.url,
        chapters: details.chapters.map((chapter) => chapter.snapshot),
      );
      expect(sequence.mangaKey, entry.mangaKey);
      final chapters = sequence.entries.where(
        (chapter) => chapter.snapshot.url == _chapterUrl,
      );
      expect(chapters, hasLength(1), reason: '章节必须按唯一 exact Source URL 识别');
      final chapter = chapters.single;
      expect(chapter.stable, isTrue);
      expect(chapter.name, isNotEmpty, reason: '本轮真实xkcd章节须有可搜索的显示名');
      // The name only narrows the visible list. Identity and the tapped key
      // always come from the unique exact URL in the real ChapterSequence.
      final chapterSearch = find.byKey(const ValueKey('chapter-search'));
      await _reveal(tester, chapterSearch, find.byType(MangaDetailsPage));
      await tester.enterText(chapterSearch, chapter.name).timeout(_remaining());
      await tester
          .pump(const Duration(milliseconds: 300))
          .timeout(_remaining());
      final button = find.byKey(ValueKey('chapter-bookmark-${chapter.key}'));
      await _reveal(tester, button, find.byType(MangaDetailsPage));
      await _waitFor(tester, '精确章节的正式书签按钮', () {
        return button.evaluate().length == 1;
      });
      final owner = find.ancestor(
        of: button,
        matching: find.byType(ChapterBookmarkButton),
      );
      expect(owner, findsOneWidget);
      final editor = tester.widget<ChapterBookmarkButton>(owner).controller;
      expect(identical(editor.repository, repository), isTrue);
      expect(editor.mangaKey, entry.mangaKey);
      await _waitForEditor(tester, editor);
      final beforeKeys = before.bookmarks.chapterKeys;
      _expectEditor(editor, beforeKeys);
      _expectNoReader(tester, catalog);

      // Reject drift before clicking a write. Source metadata that changed
      // during preparation must be stabilized and snapshotted outside this run.
      final opened = await _readSnapshot(client, repository, entry.mangaKey);
      _expectTransition(before, opened, beforeKeys, mutations: 0);
      expect(client.hasPendingMetadata(entry.mangaKey), isFalse);
      final afterKeys = {...beforeKeys};
      if (_phase == 'set') {
        expect(beforeKeys, isNot(contains(chapter.key)), reason: '不能盲目重跑已添加阶段');
        afterKeys.add(chapter.key);
      } else if (_phase == 'remove') {
        expect(beforeKeys, contains(chapter.key), reason: '移除前必须已有目标书签');
        afterKeys.remove(chapter.key);
      }
      if (_phase != 'verify') {
        expect(tester.widget<IconButton>(button).onPressed, isNotNull);
        await _tap(tester, button);
        await _waitForEditor(tester, editor);
      }
      _expectEditor(editor, afterKeys);
      final after = await _readSnapshot(client, repository, entry.mangaKey);
      _expectTransition(
        before,
        after,
        afterKeys,
        mutations: _phase == 'verify' ? 0 : 1,
      );
      expect(identical(catalog.library!.client, client), isTrue);
      expect(identical(catalog.bookmarks, repository), isTrue);
      expect(client.hasPendingMetadata(entry.mangaKey), isFalse);
      _expectNoReader(tester, catalog);
      expect(tester.takeException(), isNull);
      result = {
        'phase': _phase,
        'platform': Platform.operatingSystem,
        'androidLoopbackTestCa': _testCaBase64.isNotEmpty,
        'origin': client.identity.origin.origin,
        'subject': client.identity.subject,
        'packageName': _packageName,
        'sourceId': _sourceId,
        'buildId': catalog.activeBuild!.id,
        'mangaUrl': _mangaUrl,
        'mangaKey': entry.mangaKey,
        'chapterUrl': chapter.snapshot.url,
        'chapterKey': chapter.key,
        'before': _report(before),
        'after': _report(after),
      };
    } finally {
      try {
        await tester
            .pumpWidget(const SizedBox.shrink())
            .timeout(_operationBudget);
        await tester.pump().timeout(_operationBudget);
        await catalog.closeReadingProgress().timeout(_operationBudget);
      } finally {
        // AppShell initiates this idempotent Native cleanup on unmount. Await
        // the real disposal ACK before reporting this phase as successful.
        await platform.dispose().timeout(_operationBudget);
      }
    }
    binding.reportData = {'BOOKMARKS_SYNC_RESULT': result};
    debugPrint('BOOKMARKS_SYNC_RESULT ${jsonEncode(result)}');
  }, timeout: const Timeout(Duration(minutes: 15)));
}

final class _Expected {
  const _Expected(this.settings, this.state, this.bookmarks);
  final wire.SettingsResponse settings;
  final wire.MangaStateResponse state;
  final wire.BookmarkPageResponse bookmarks;
}

final class _Snapshot {
  const _Snapshot({
    required this.settings,
    required this.mangaSettings,
    required this.state,
    required this.bookmarks,
    required this.progress,
  });
  final wire.SettingsResponse settings;
  final wire.SettingsResponse mangaSettings;
  final wire.MangaStateResponse state;
  final MangaBookmarksSnapshot bookmarks;
  final BusinessChapterProgressSnapshot progress;
}

Future<_Snapshot> _readSnapshot(
  BusinessStateClient client,
  BookmarkRepository repository,
  String mangaKey,
) async {
  final settings = await client.readSettings().timeout(_remaining());
  final mangaSettings = await client
      .readSettings(mangaKey: mangaKey)
      .timeout(_remaining());
  final state = await client.readManga(mangaKey).timeout(_remaining());
  final bookmarks = await repository.loadAll(mangaKey).timeout(_remaining());
  final progress = await client
      .readChapterProgress(mangaKey)
      .timeout(_remaining());
  expect(
    progress.entries.length,
    lessThanOrEqualTo(64),
    reason: '本轮进度快照最多64项，不截断',
  );
  final revision = state.accountRevision;
  expect(settings.accountRevision, revision);
  expect(mangaSettings.accountRevision, revision);
  expect(bookmarks.accountRevision, revision);
  expect(progress.accountRevision, revision);
  expect(bookmarks.revision, state.manga.revision);
  expect(
    wire.encodeProtoJson(progress.manga),
    wire.encodeProtoJson(state.manga),
  );
  return _Snapshot(
    settings: settings,
    mangaSettings: mangaSettings,
    state: state,
    bookmarks: bookmarks,
    progress: progress,
  );
}

void _expectConfigured(_Snapshot actual, _Expected expected) {
  expect(
    wire.encodeProtoJson(actual.settings),
    wire.encodeProtoJson(expected.settings),
  );
  expect(
    wire.encodeProtoJson(actual.state),
    wire.encodeProtoJson(expected.state),
  );
  expect(actual.bookmarks.revision, expected.state.manga.revision);
  expect(actual.bookmarks.accountRevision, expected.bookmarks.accountRevision);
  expect(
    actual.bookmarks.chapterKeys,
    unorderedEquals(
      expected.bookmarks.entries.map((entry) => entry.chapterKey),
    ),
  );
}

void _expectTransition(
  _Snapshot before,
  _Snapshot after,
  Set<String> keys, {
  required int mutations,
}) {
  final settings = before.settings.deepCopy()
    ..accountRevision = before.settings.accountRevision + mutations;
  final mangaSettings = before.mangaSettings.deepCopy()
    ..accountRevision = before.mangaSettings.accountRevision + mutations;
  final state = before.state.deepCopy()
    ..accountRevision = before.state.accountRevision + mutations;
  state.manga.revision = before.state.manga.revision + mutations;
  expect(wire.encodeProtoJson(after.settings), wire.encodeProtoJson(settings));
  expect(
    wire.encodeProtoJson(after.mangaSettings),
    wire.encodeProtoJson(mangaSettings),
  );
  expect(wire.encodeProtoJson(after.state), wire.encodeProtoJson(state));
  expect(after.bookmarks.chapterKeys, unorderedEquals(keys));
  expect(after.bookmarks.revision, state.manga.revision);
  expect(after.bookmarks.accountRevision, state.accountRevision);
  expect(after.progress.accountRevision, state.accountRevision);
  expect(
    wire.encodeProtoJson(after.progress.manga),
    wire.encodeProtoJson(state.manga),
  );
  expect(
    after.progress.entries.map(wire.encodeProtoJson),
    orderedEquals(before.progress.entries.map(wire.encodeProtoJson)),
    reason: '书签操作不能修改任何章节的进度、epoch、完成标记或锚点',
  );
}

void _expectEditor(ChapterBookmarksController editor, Set<String> keys) {
  expect(editor.available, isTrue);
  expect(editor.loaded, isTrue);
  expect(editor.busy, isFalse);
  expect(editor.pending, isNull);
  expect(editor.error, isNull);
  expect(editor.chapterKeys, unorderedEquals(keys));
}

Future<void> _waitForEditor(
  WidgetTester tester,
  ChapterBookmarksController editor,
) => _waitFor(tester, '书签获确认且完整列表重读完成', () {
  if (!editor.available || editor.error != null) {
    fail('正式书签页面未就绪：${editor.error ?? '身份或Source已失效'}');
  }
  return editor.loaded && !editor.busy && editor.pending == null;
});

void _expectNoReader(WidgetTester tester, CatalogController catalog) {
  expect(find.byType(ChapterReaderRoute), findsNothing);
  expect(find.byType(ReaderScreen), findsNothing);
  expect(catalog.hasUnsavedReadingProgress, isFalse);
}

void _checkCatalog(CatalogController catalog) {
  if (catalog.accessPaused || catalog.status == ServiceStatus.failed) {
    fail('Native 正式服务或Source未就绪：${catalog.error ?? catalog.status.name}');
  }
}

Duration _remaining() {
  final left = _totalBudget - _elapsed.elapsed;
  if (left <= Duration.zero) fail('书签验收超过10分钟总操作预算');
  return left < _operationBudget ? left : _operationBudget;
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
    await tester.pump(const Duration(milliseconds: 100)).timeout(_remaining());
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _waitFor(
    tester,
    '唯一正式操作控件 $finder',
    () => finder.evaluate().length == 1,
  );
  await tester.ensureVisible(finder).timeout(_remaining());
  await tester.pump(const Duration(milliseconds: 300)).timeout(_remaining());
  await _waitFor(
    tester,
    '正式控件可点击',
    () => finder.hitTestable().evaluate().length == 1,
  );
  await tester.tap(finder).timeout(_remaining());
  await tester.pump(const Duration(milliseconds: 300)).timeout(_remaining());
}

Future<void> _reveal(WidgetTester tester, Finder finder, Finder page) async {
  final scrollable = find
      .descendant(of: page, matching: find.byType(Scrollable))
      .first;
  await tester
      .scrollUntilVisible(finder, 300, scrollable: scrollable, maxScrolls: 100)
      .timeout(_remaining());
}

_Expected _validateConfiguration() {
  final origin = Uri.tryParse(_origin);
  if (origin == null ||
      origin.scheme != 'https' ||
      origin.host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      (origin.path.isNotEmpty && origin.path != '/')) {
    fail('APP_ORIGIN 必须是单一 HTTPS 服务源');
  }
  if (!Platform.isAndroid && !Platform.isIOS) {
    fail('此正式书签同步验收仅适用于 Android 或 iOS 设备/模拟器');
  }
  if (_testCaBase64.isNotEmpty &&
      (!Platform.isAndroid || origin.host != '127.0.0.1')) {
    fail('BOOKMARKS_TEST_CA_BASE64 仅适用于 Android 的 HTTPS 127.0.0.1 验收');
  }
  if (_subject.isEmpty ||
      _subject.length > 1000 ||
      _packageName.isEmpty ||
      _sourceId.isEmpty ||
      _mangaUrl.isEmpty ||
      _chapterUrl.isEmpty ||
      _chapterUrl.length > 8192 ||
      !{'verify', 'set', 'remove'}.contains(_phase)) {
    fail('须提供精确的 BOOKMARKS 身份、Source作品/章节URL及 verify/set/remove 阶段');
  }
  final settings = wire.decodeProtoJson(
    wire.SettingsResponse(),
    jsonDecode(_settingsJson),
    maxBytes: wire.controlRequestLimit,
  );
  validateBusinessSettingsResponse(settings);
  expect(settings.hasError(), isFalse);
  expect(settings.hasManga(), isFalse);
  final state = wire.decodeProtoJson(
    wire.MangaStateResponse(),
    jsonDecode(_stateJson),
    maxBytes: wire.controlRequestLimit,
  );
  expect(state.schemaVersion, 1);
  expect(state.hasError(), isFalse);
  expect(state.hasManga(), isTrue);
  expect(state.hasCategoryCatalog(), isTrue);
  expect(state.hasProgress(), isFalse);
  expect(state.hasBookmark(), isFalse);
  validateBusinessManga(state.manga);
  validateBusinessCategoryCatalog(state.categoryCatalog);
  validateBusinessMangaCategories(state.manga, state.categoryCatalog);
  validateBusinessRevision(state.accountRevision);
  expect(state.accountRevision, greaterThanOrEqualTo(state.manga.revision));
  expect(
    state.accountRevision,
    greaterThanOrEqualTo(state.categoryCatalog.revision),
  );
  expect(state.accountRevision, settings.accountRevision);
  expect(state.manga.favorite, isTrue);
  expect(state.manga.hasCustomCover(), isFalse);
  expect(state.manga.metadata.packageName, _packageName);
  expect(state.manga.metadata.sourceId, _sourceId);
  expect(state.manga.metadata.manga.url, _mangaUrl);
  final bookmarks = wire.decodeProtoJson(
    wire.BookmarkPageResponse(),
    jsonDecode(_bookmarksJson),
    maxBytes: wire.controlRequestLimit,
  );
  validateBusinessBookmarkPage(bookmarks, mangaKey: state.manga.mangaKey);
  expect(bookmarks.hasError(), isFalse);
  expect(bookmarks.nextKey, isEmpty, reason: '本轮期望必须包含完整集合，最多64书签，不接受分页截断');
  expect(bookmarks.accountRevision, state.accountRevision);
  return _Expected(settings, state, bookmarks);
}

Map<String, Object?> _report(_Snapshot value) => {
  'settings': wire.encodeProtoJson(value.settings),
  'mangaSettings': wire.encodeProtoJson(value.mangaSettings),
  'state': wire.encodeProtoJson(value.state),
  'bookmarks': {
    'revision': value.bookmarks.revision,
    'accountRevision': value.bookmarks.accountRevision,
    'chapterKeys': value.bookmarks.chapterKeys.toList()..sort(),
  },
  'progress': {
    'accountRevision': value.progress.accountRevision,
    'entries': value.progress.entries.map(wire.encodeProtoJson).toList(),
  },
};
