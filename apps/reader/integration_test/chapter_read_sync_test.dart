import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/runtime/platform_runtime_native.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'native_app.dart';

const _origin = String.fromEnvironment('APP_ORIGIN');
const _subject = String.fromEnvironment('CHAPTER_READ_SUBJECT');
const _phase = String.fromEnvironment('CHAPTER_READ_PHASE');
const _buildId = String.fromEnvironment('CHAPTER_READ_BUILD_ID');
const _testCa = String.fromEnvironment('CHAPTER_READ_TEST_CA_BASE64');
const _packageName = 'eu.kanade.tachiyomi.extension.all.xkcd';
const _sourceId = '1538249443376436084';
const _mangaUrl = 'SINGLE';
const _urls = ['/3317/', '/3318/', '/3319/'];
const _untouched = '/3316/';
const _budget = Duration(seconds: 120);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Native chapter range sync: $_phase', (tester) async {
    final origin = Uri.parse(_origin);
    final beforeEpoch = switch (_phase) {
      'read' => 0,
      'unread' => 1,
      'verify' => 2,
      _ => fail('CHAPTER_READ_PHASE must be read, unread or verify'),
    };
    if ((!Platform.isIOS && !Platform.isAndroid) ||
        origin.scheme != 'https' ||
        origin.origin != _origin ||
        _subject.isEmpty ||
        _buildId.isEmpty) {
      fail('须提供 iOS 或 Android、精确 HTTPS origin、测试身份和构建 ID');
    }
    if (_testCa.isNotEmpty) {
      if (!Platform.isAndroid || origin.host != '127.0.0.1') {
        fail('测试 CA 仅用于 Android HTTPS 127.0.0.1');
      }
      SecurityContext.defaultContext.setTrustedCertificatesBytes(
        base64Decode(_testCa),
      );
    }
    final catalog = await startNativeApp(tester);
    final shelf = find.byType(LibraryPage);
    final platform = catalog.api;
    if (platform is! NativePlatformRuntime) fail('必须使用正式 Native 运行时');
    expect(platform.origin.origin, origin.origin);
    late final Map<String, Object?> result;
    try {
      await _waitFor(tester, '正式服务及书架可用', () {
        _checkConnection(catalog);
        return catalog.status == ServiceStatus.ready && catalog.library != null;
      });
      final library = catalog.library!;
      final client = library.client;
      expect(client.identity.subject, _subject);
      expect(client.identity.origin.origin, origin.origin);
      expect(catalog.session, isNull);
      final view = await library.watchView().first.timeout(_budget);
      expect(view.entries, hasLength(1));
      final entry = view.entries.single;
      expect(entry.packageName, _packageName);
      expect(entry.sourceId, _sourceId);
      expect(entry.url, _mangaUrl);
      expect(entry.customCover, isNull);
      final before = await _snapshot(client, entry.mangaKey);
      expect(before.state.accountRevision, 2 + _urls.length * beforeEpoch);
      expect(before.state.manga.revision, before.state.accountRevision - 1);
      expect(before.settings.global.revision, 1);
      expect(before.state.manga.favorite, isTrue);
      expect(before.state.manga.hasResume(), isFalse);
      expect(before.bookmarks.entries, isEmpty);

      await _tap(
        tester,
        find.descendant(
          of: find.byKey(ValueKey(entry.mangaKey)),
          matching: find.byType(ListTile),
        ),
        page: shelf,
      );
      final detailPage = find.byType(MangaDetailsPage);
      await _waitFor(tester, '真实 xkcd 详情', () {
        _checkConnection(catalog);
        return detailPage.evaluate().length == 1;
      });
      final details = tester.widget<MangaDetailsPage>(detailPage);
      expect(identical(details.controller, catalog), isTrue);
      expect(catalog.activeBuild!.packageName, _packageName);
      expect(catalog.activeBuild!.id, _buildId);
      expect(details.source.sourceId, _sourceId);
      expect(details.manga.url, _mangaUrl);
      final sequence = ChapterSequence(
        packageName: _packageName,
        sourceId: _sourceId,
        mangaUrl: details.manga.url,
        chapters: details.chapters.map((chapter) => chapter.snapshot),
      );
      expect(sequence.mangaKey, entry.mangaKey);
      final targets = [for (final url in _urls) _chapter(sequence, url)]
        ..sort((a, b) => a.sourceIndex.compareTo(b.sourceIndex));
      final keys = targets.map((chapter) => chapter.key).toSet();
      final untouched = _chapter(sequence, _untouched);
      expect(targets.last.sourceIndex - targets.first.sourceIndex, 2);
      expect(keys, isNot(contains(untouched.key)));
      _expectProgress(before.progress, keys, beforeEpoch);

      final order = _control('chapter-list-order');
      await _show(tester, order, detailPage);
      if (tester.widget<DropdownButton<ChapterOrder>>(order).value !=
          ChapterOrder.source) {
        await _tap(tester, order);
        await _tap(tester, find.text('来源顺序').last);
      }
      expect(
        tester.widget<DropdownButton<ChapterOrder>>(order).value,
        ChapterOrder.source,
      );
      final filter = find.byKey(
        const ValueKey(('chapter-read-filter', 'read')),
      );
      await _show(tester, filter, detailPage);
      await _waitFor(tester, '正式已读筛选就绪', () {
        _checkConnection(catalog);
        return tester.widget<ChoiceChip>(filter).onSelected != null;
      });
      final opened = await _snapshot(client, entry.mangaKey);
      _expectSameBusiness(before, opened, mutations: 0);
      _expectProgress(opened.progress, keys, beforeEpoch);

      if (_phase != 'read') {
        await _tap(tester, filter);
        expect(tester.widget<ChoiceChip>(filter).selected, isTrue);
        final count = beforeEpoch == 1 ? _urls.length : 0;
        final shown = find.text('显示 $count / ${details.chapters.length} 章');
        await _show(tester, shown, detailPage);
        expect(shown, findsOneWidget);
        if (_phase == 'unread') {
          for (final target in targets) {
            final row = find.byKey(ValueKey(target.key));
            await _show(tester, row, detailPage);
            expect(
              tester.widget<ListTile>(row).subtitle,
              isA<Text>().having(
                (text) => text.data,
                'subtitle',
                endsWith('已读'),
              ),
            );
          }
        }
      }
      if (_phase != 'verify') {
        final selection = _control('chapter-selection-toggle');
        await _show(
          tester,
          selection,
          detailPage,
          delta: _phase == 'unread' ? -280 : 280,
        );
        await _waitFor(tester, '章节选择可用', () {
          return tester.widget<TextButton>(selection).onPressed != null;
        });
        await _tap(tester, selection);
        for (final (control, chapter) in [
          ('chapter-range-start', targets.last),
          ('chapter-range-end', targets.first),
        ]) {
          await _tap(tester, _control(control), page: detailPage);
          final option = find
              .text('${chapter.name} · 来源第 ${chapter.sourceIndex + 1} 项')
              .last;
          await _tap(tester, option, page: find.byType(Scrollable).last);
        }
        await _tap(tester, _control('chapter-select-range'), page: detailPage);
        await _tap(tester, _control('chapter-mark-$_phase'), page: detailPage);
        final dialog = find.byType(AlertDialog);
        final preview = find.text('确认清单：3 章');
        await _show(tester, preview, dialog);
        expect(preview, findsOneWidget);
        for (final key in keys) {
          await _show(
            tester,
            find.byKey(ValueKey(('chapter-read-item', key))),
            dialog,
          );
        }
        await _tap(tester, find.widgetWithText(FilledButton, '确认并开始'));
        final confirmed = find.text('全部标记已由服务端确认。');
        await _waitFor(tester, '三章均获服务端确认', () {
          _checkConnection(catalog);
          return confirmed.evaluate().isNotEmpty;
        });
        await _show(tester, find.text('已确认 3 / 3 章 · 未开始 0 章'), dialog);
        await _tap(tester, find.widgetWithText(TextButton, '完成'));
      }
      final after = await _snapshot(client, entry.mangaKey);
      final mutations = _phase == 'verify' ? 0 : keys.length;
      _expectSameBusiness(before, after, mutations: mutations);
      _expectProgress(
        after.progress,
        keys,
        beforeEpoch + (mutations > 0 ? 1 : 0),
      );
      expect(find.byType(ChapterReaderRoute), findsNothing);
      expect(catalog.hasUnsavedReadingProgress, isFalse);
      expect(tester.takeException(), isNull);
      result = {
        'phase': _phase,
        'platform': Platform.operatingSystem,
        'subject': client.identity.subject,
        'origin': client.identity.origin.origin,
        'buildId': _buildId,
        'mangaKey': sequence.mangaKey,
        'targetKeys': {
          for (final chapter in targets) chapter.snapshot.url: chapter.key,
        },
        'untouchedKey': untouched.key,
        'accountRevision': after.state.accountRevision,
        'mangaRevision': after.state.manga.revision,
        'progress': after.progress.entries.map(wire.encodeProtoJson).toList(),
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
    binding.reportData = {'CHAPTER_READ_SYNC_RESULT': result};
    debugPrint('CHAPTER_READ_SYNC_RESULT ${jsonEncode(result)}');
  }, timeout: const Timeout(Duration(minutes: 12)));
}

typedef _Snapshot = ({
  wire.SettingsResponse settings,
  wire.SettingsResponse mangaSettings,
  wire.MangaStateResponse state,
  BusinessBookmarksSnapshot bookmarks,
  BusinessChapterProgressSnapshot progress,
});

Future<_Snapshot> _snapshot(BusinessStateClient client, String key) async {
  final settings = await client.readSettings().timeout(_budget);
  final mangaSettings = await client
      .readSettings(mangaKey: key)
      .timeout(_budget);
  final state = await client.readManga(key).timeout(_budget);
  final bookmarks = await client.readBookmarks(key).timeout(_budget);
  final progress = await client.readChapterProgress(key).timeout(_budget);
  for (final revision in [
    settings.accountRevision,
    mangaSettings.accountRevision,
    bookmarks.accountRevision,
    progress.accountRevision,
  ]) {
    expect(revision, state.accountRevision);
  }
  expect(
    wire.encodeProtoJson(bookmarks.manga),
    wire.encodeProtoJson(state.manga),
  );
  expect(
    wire.encodeProtoJson(progress.manga),
    wire.encodeProtoJson(state.manga),
  );
  return (
    settings: settings,
    mangaSettings: mangaSettings,
    state: state,
    bookmarks: bookmarks,
    progress: progress,
  );
}

void _expectSameBusiness(
  _Snapshot before,
  _Snapshot after, {
  required int mutations,
}) {
  final account = before.state.accountRevision + mutations;
  final state = before.state.deepCopy()..accountRevision = account;
  state.manga.revision += mutations;
  expect(wire.encodeProtoJson(after.state), wire.encodeProtoJson(state));
  expect(
    wire.encodeProtoJson(after.settings),
    wire.encodeProtoJson(before.settings.deepCopy()..accountRevision = account),
  );
  expect(
    wire.encodeProtoJson(after.mangaSettings),
    wire.encodeProtoJson(
      before.mangaSettings.deepCopy()..accountRevision = account,
    ),
  );
  expect(
    after.bookmarks.entries.map(wire.encodeProtoJson).toList(),
    before.bookmarks.entries.map(wire.encodeProtoJson).toList(),
  );
  if (mutations == 0) {
    expect(
      after.progress.entries.map(wire.encodeProtoJson).toList(),
      before.progress.entries.map(wire.encodeProtoJson).toList(),
    );
  }
}

void _expectProgress(
  BusinessChapterProgressSnapshot snapshot,
  Set<String> keys,
  int epoch,
) {
  if (epoch == 0) {
    expect(snapshot.entries, isEmpty);
    return;
  }
  expect(
    snapshot.entries.map((entry) => entry.chapterKey),
    unorderedEquals(keys),
  );
  for (final entry in snapshot.entries) {
    expect(entry.epoch, epoch);
    expect(entry.completed, epoch == 1);
    expect(entry.hasCurrent(), isFalse);
    expect(entry.hasFurthest(), isFalse);
  }
}

SequenceChapter _chapter(ChapterSequence sequence, String url) {
  final matches = sequence.entries.where((entry) => entry.snapshot.url == url);
  expect(matches, hasLength(1));
  expect(matches.single.stable, isTrue);
  return matches.single;
}

Finder _control(String key) => find.byKey(ValueKey(key));

void _checkConnection(CatalogController catalog) {
  if (catalog.accessPaused || catalog.status == ServiceStatus.failed) {
    fail('正式 Source 或服务不可用：${catalog.error ?? catalog.status.name}');
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  String label,
  bool Function() ready,
) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsed >= _budget) fail('$label 超时');
    await tester.pump(const Duration(milliseconds: 100)).timeout(_budget);
  }
}

Future<void> _show(
  WidgetTester tester,
  Finder target,
  Finder page, {
  double delta = 280,
}) async {
  if (target.evaluate().isEmpty) {
    final scrollable = page.evaluate().single.widget is Scrollable
        ? page
        : find.descendant(of: page, matching: find.byType(Scrollable)).first;
    await tester
        .scrollUntilVisible(target, delta, scrollable: scrollable)
        .timeout(_budget);
  }
  await tester.ensureVisible(target).timeout(_budget);
  await tester.pump(const Duration(milliseconds: 300)).timeout(_budget);
}

Future<void> _tap(WidgetTester tester, Finder target, {Finder? page}) async {
  if (page != null) await _show(tester, target, page);
  await _waitFor(tester, '正式控件可点击：$target', () {
    return target.hitTestable().evaluate().length == 1;
  });
  await tester.tap(target).timeout(_budget);
  await tester.pump(const Duration(milliseconds: 300)).timeout(_budget);
}
