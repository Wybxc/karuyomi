import '../test_support/cupertino.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/runtime/platform_runtime_native.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart' show ChapterPageProvider;

import 'native_app.dart';

const _origin = String.fromEnvironment('APP_ORIGIN');
const _chapterLabel = String.fromEnvironment(
  'SYNC_CHAPTER_LABEL',
  defaultValue: '3319: Elevators',
);
const _startPage = int.fromEnvironment('SYNC_START_PAGE', defaultValue: 1);
const _targetPage = int.fromEnvironment('SYNC_TARGET_PAGE', defaultValue: 2);
const _phase = String.fromEnvironment('SYNC_PHASE', defaultValue: 'navigate');
const _entry = String.fromEnvironment('SYNC_ENTRY', defaultValue: 'details');
const _shelfEntry = _entry == 'shelf';
const _subject = String.fromEnvironment('SYNC_SUBJECT');
const _buildId = String.fromEnvironment('SYNC_BUILD_ID');
const _expectedEpoch = int.fromEnvironment(
  'SYNC_EXPECT_EPOCH',
  defaultValue: -1,
);
const _testCaBase64 = String.fromEnvironment('SYNC_TEST_CA_BASE64');
const _operationBudget = Duration(seconds: 120);
const _lifecycleBudget = Duration(minutes: 5);
const _staleWriteBudget = Duration(seconds: 3);
const _xkcdPackage = 'eu.kanade.tachiyomi.extension.all.xkcd';
const _xkcdSourceId = '1538249443376436084';
const _xkcdMangaUrl = 'SINGLE';
const _xkcdChapterUrl = '/3319/';
const _ackLossSubject = 'acceptance-owner';
const _epochChanged = '本章进度已在其他设备重置，当前阅读位置保持不变。请重新打开本章后继续保存。';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Native reads and confirms shared server progress with real Source images',
    (tester) async {
      _validateConfiguration();
      if (_testCaBase64.isNotEmpty) {
        SecurityContext.defaultContext.setTrustedCertificatesBytes(
          base64Decode(_testCaBase64),
        );
      }
      final catalog = await startNativeApp(tester);
      final platform = catalog.api;
      if (platform is! NativePlatformRuntime) {
        fail('此验收必须使用正式 NativePlatformRuntime');
      }
      expect(platform.origin.origin, Uri.parse(_origin).origin);
      late final Map<String, Object?> result;

      try {
        final mangaTile = find.widgetWithText(CupertinoListTile, 'xkcd');
        await _waitFor(tester, '已登录 Native 的服务端 xkcd 书架', () {
          if (catalog.accessPaused) {
            fail('请先在此 Native 安装中完成正式 Access 登录，再运行同步验收');
          }
          return catalog.status == ServiceStatus.ready &&
              mangaTile.evaluate().length == 1 &&
              tester
                      .widget<CupertinoButton>(buttonAbove(mangaTile))
                      .onPressed !=
                  null;
        });
        if (_subject.isNotEmpty) expect(catalog.subject, _subject);
        final shelfSequence = _shelfEntry
            ? ChapterSequence(
                packageName: _xkcdPackage,
                sourceId: _xkcdSourceId,
                mangaUrl: _xkcdMangaUrl,
                chapters: [wire.Chapter(url: _xkcdChapterUrl)],
              )
            : null;
        final shelfChapterKey = shelfSequence?.entries.single.key;
        final shelfClient = _shelfEntry
            ? catalog.readingProgress!.client
            : null;
        Future<wire.MangaStateResponse> inspectShelfState() => shelfClient!
            .inspectManga(shelfSequence!.mangaKey, chapterKey: shelfChapterKey!)
            .timeout(_operationBudget);

        final shelfBefore = _shelfEntry ? await inspectShelfState() : null;
        late final Finder returnTarget;
        late final bool Function() returnEnabled;
        if (_shelfEntry) {
          final shelfButton = find.byKey(
            ValueKey(('library-continue', shelfSequence!.mangaKey)),
          );
          final resume = shelfBefore!.manga.resume;
          expect(resume.chapterKey, shelfChapterKey);
          expect(shelfBefore.progress.current.pageIndexHint, _startPage - 1);
          expect(shelfBefore.progress.furthest.pageIndexHint, 1);
          expect(shelfBefore.progress.epoch, _expectedEpoch);
          expect(shelfBefore.progress.completed, isFalse);
          returnTarget = shelfButton;
          returnEnabled = () =>
              tester.widget<CupertinoButton>(shelfButton).onPressed != null;
          await _waitFor(
            tester,
            '已确认的书架续读按钮',
            () =>
                shelfButton.evaluate().length == 1 &&
                returnEnabled() &&
                find
                        .descendant(
                          of: shelfButton,
                          matching: iconLabel('继续阅读：xkcd'),
                        )
                        .evaluate()
                        .length ==
                    1,
          );
          await _tap(tester, shelfButton);
        } else {
          // A CupertinoListTile's center may hit its nested Continue Reading icon once
          // the shelf has a saved resume. Tap the actual title to open details.
          final mangaTitle = find.descendant(
            of: mangaTile,
            matching: find.text('xkcd'),
          );
          await _tap(tester, mangaTitle);
          final chapterTile = await _chapterTile(tester, catalog);
          returnTarget = chapterTile;
          returnEnabled = () =>
              tester
                  .widget<CupertinoButton>(buttonAbove(chapterTile))
                  .onPressed !=
              null;
          await _tap(tester, chapterTile);
        }
        await _waitFor(
          tester,
          '正式阅读页完成进度恢复',
          () => find.byType(ReaderScreen).evaluate().length == 1,
        );

        final route = tester.widget<ChapterReaderRoute>(
          find.byType(ChapterReaderRoute),
        );
        final reader = _reader(tester);
        final manifest = reader.manifest;
        final mangaKey = route.sequence.mangaKey;
        expect(identical(route.catalog, catalog), isTrue);
        expect(route.initialChapter.name, _chapterLabel);
        if (_shelfEntry) {
          expect(
            find.byType(MangaDetailsPage, skipOffstage: false),
            findsNothing,
          );
          expect(mangaKey, shelfSequence!.mangaKey);
          expect(manifest.chapterKey, shelfChapterKey);
          expect(route.source.sourceId, _xkcdSourceId);
        }
        expect(_startPage, lessThanOrEqualTo(manifest.pages.length));
        expect(_targetPage, lessThanOrEqualTo(manifest.pages.length));
        if (_phase != 'navigate' || _buildId.isNotEmpty) {
          expect(route.source.buildId, _buildId);
          expect(route.initialChapter.snapshot.url, _xkcdChapterUrl);
          expect(manifest.chapterKey, route.initialChapter.key);
          expect(manifest.pages, hasLength(2));
        }
        final repository = catalog.readingProgress;
        expect(repository, isNotNull);
        if (_subject.isNotEmpty) expect(repository!.identity.subject, _subject);

        await _singlePage(tester);
        await _waitForPage(tester, manifest, _startPage);
        if (_shelfEntry) {
          await _confirmedProgress(
            tester,
            repository!,
            mangaKey,
            manifest,
            page: _startPage,
            epoch: _expectedEpoch,
            minimumFurthest: 2,
          );
          await tester.pump(_staleWriteBudget);
          expect(await inspectShelfState(), shelfBefore);
        }
        late final ProgressSnapshot after;
        Map<String, Object?>? phaseEvidence;
        if (_phase == 'reset') {
          final before = await _confirmedProgress(
            tester,
            repository!,
            mangaKey,
            manifest,
            page: _startPage,
            epoch: _expectedEpoch,
            minimumFurthest: _startPage,
          );
          final reset = find.widgetWithText(CupertinoButton, '重新阅读本章');
          expect(tester.widget<CupertinoButton>(reset).onPressed, isNotNull);
          await _tap(tester, reset);
          await _waitForPage(tester, manifest, _targetPage);
          after = await _confirmedProgress(
            tester,
            repository,
            mangaKey,
            manifest,
            page: _targetPage,
            epoch: before.epoch + 1,
          );
          _expectResetState(after);
          phaseEvidence = {'beforeReset': _progressReport(before)};
        } else if (_phase == 'offline') {
          // Decode both pages online, then return to a confirmed page-one
          // baseline. The outage must not rely on a Source image fetch.
          await _turnTo(tester, manifest, _startPage, _targetPage);
          await _confirmedProgress(
            tester,
            repository!,
            mangaKey,
            manifest,
            page: _targetPage,
            epoch: _expectedEpoch,
            minimumFurthest: _targetPage,
          );
          await _turnTo(tester, manifest, _targetPage, _startPage);
          await tester.pump(_staleWriteBudget);
          final before = await _confirmedProgress(
            tester,
            repository,
            mangaKey,
            manifest,
            page: _startPage,
            epoch: _expectedEpoch,
            minimumFurthest: _targetPage,
          );
          after = await _retryAfterOutage(
            tester,
            catalog,
            repository,
            mangaKey,
            manifest,
          );
          phaseEvidence = {
            'beforeDisconnect': _progressReport(before),
            'keptMountedReader': true,
            'explicitRetry': true,
          };
        } else if (_phase == 'ack-loss' || _phase == 'd1-error') {
          await _turnTo(tester, manifest, _startPage, _targetPage);
          final evidence = await _retryAfterCompletionFailure(
            tester,
            catalog,
            repository!,
            mangaKey,
            manifest,
            expectRollback: _phase == 'd1-error',
          );
          after = evidence.confirmed;
          phaseEvidence = {
            'beforeCompletion': _progressReport(evidence.before),
            'whileUnconfirmed': _progressReport(evidence.unconfirmed),
            'afterRetry': _progressReport(after),
            'keptMountedReader': true,
            'explicitRetry': true,
          };
        } else {
          await _turnTo(tester, manifest, _startPage, _targetPage);
          final before = await _confirmedProgress(
            tester,
            repository!,
            mangaKey,
            manifest,
            page: _targetPage,
            epoch: _expectedEpoch < 0 ? null : _expectedEpoch,
            minimumFurthest: _shelfEntry ? 2 : max(_startPage, _targetPage),
          );
          if (_phase == 'resume') {
            final evidence = await _resume(
              tester,
              repository,
              mangaKey,
              manifest,
              before,
            );
            after = evidence.reopened;
            phaseEvidence = {
              'lifecycle': {
                'pid': pid,
                'transitions': ['paused', 'resumed'],
              },
              'beforePause': _progressReport(before),
              'observedRemote': _progressReport(evidence.remote),
              'afterStalePaging': _progressReport(evidence.stale),
            };
          } else {
            after = before;
          }
        }
        final progress = after.progress!;
        final activeReader = _reader(tester);
        final finalPage = _phase == 'resume' ? _startPage : _targetPage;
        result = <String, Object?>{
          'phase': _phase,
          if (_shelfEntry) 'entry': _entry,
          'platform': Platform.operatingSystem,
          'origin': platform.origin.origin,
          'subject': catalog.subject,
          'androidLoopbackTestCa': _testCaBase64.isNotEmpty,
          'buildId': route.source.buildId,
          'sourceId': route.source.sourceId,
          'mangaKey': mangaKey,
          'chapterKey': activeReader.manifest.chapterKey,
          'pageKey': activeReader.manifest.pages[finalPage - 1].key,
          'manifestVersion': activeReader.manifest.version,
          'epoch': progress.epoch,
          'mangaRevision': after.revision,
          'startPage': _startPage,
          'targetPage': _targetPage,
          'finalPage': finalPage,
          'current': _anchor(progress.current),
          'furthest': progress.furthest == null
              ? null
              : _anchor(progress.furthest!),
          ...?phaseEvidence,
        };

        // Wait for the originating UI after route completion and closeChapter
        // ACK before disposing the runtime.
        await tester.tap(find.byType(CupertinoNavigationBarBackButton));
        await _waitFor(
          tester,
          _shelfEntry ? '返回书架并完成章节资源 ACK' : '返回详情并完成章节资源 ACK',
          () =>
              find.byType(ReaderScreen).evaluate().isEmpty &&
              returnTarget.evaluate().length == 1 &&
              returnEnabled(),
        );
        // close() reuses the provider's real ACK future, including failures.
        await _closeProvider(activeReader);
        if (_shelfEntry) {
          final finalShelfState = await inspectShelfState();
          if (_startPage == _targetPage) {
            expect(finalShelfState, shelfBefore);
          } else {
            expect(
              finalShelfState.accountRevision,
              shelfBefore!.accountRevision + 1,
            );
            expect(
              finalShelfState.manga.revision,
              shelfBefore.manga.revision + 1,
            );
            expect(finalShelfState.manga.resume, shelfBefore.manga.resume);
            expect(
              finalShelfState.progress.furthest,
              shelfBefore.progress.furthest,
            );
            expect(finalShelfState.progress.epoch, shelfBefore.progress.epoch);
            expect(finalShelfState.progress.completed, isFalse);
            expect(
              finalShelfState.progress.current.pageIndexHint,
              _targetPage - 1,
            );
          }
        }
        expect(catalog.hasUnsavedReadingProgress, isFalse);
        expect(tester.takeException(), isNull);
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
  if (_testCaBase64.isNotEmpty &&
      (!Platform.isAndroid || origin.host != '127.0.0.1')) {
    fail('SYNC_TEST_CA_BASE64 仅适用于 Android 的 HTTPS 127.0.0.1 验收');
  }
  if (_chapterLabel.isEmpty || _startPage < 1 || _targetPage < 1) {
    fail('SYNC_CHAPTER_LABEL 不能为空，SYNC_START_PAGE / SYNC_TARGET_PAGE 须大于零');
  }
  if (!{'details', 'shelf'}.contains(_entry) ||
      (_shelfEntry &&
          (_phase != 'navigate' ||
              _subject.isEmpty ||
              _buildId.isEmpty ||
              _expectedEpoch < 0 ||
              _startPage > 2 ||
              _targetPage > _startPage))) {
    fail('书架续读阶段须为 navigate，提供同一 subject、构建 ID、原 epoch，仅恢复或回看');
  }
  if (!{
        'navigate',
        'reset',
        'resume',
        'offline',
        'ack-loss',
        'd1-error',
      }.contains(_phase) ||
      _expectedEpoch < -1 ||
      _expectedEpoch >= 0xffffffff ||
      (_phase != 'navigate' &&
          (_subject.isEmpty || _buildId.isEmpty || _expectedEpoch < 0)) ||
      ({'resume', 'offline', 'ack-loss', 'd1-error'}.contains(_phase) &&
          (_startPage != 1 || _targetPage != 2)) ||
      (_phase == 'reset' && (_startPage != 2 || _targetPage != 1))) {
    fail('同步恢复阶段须提供同一 subject、构建 ID、原 epoch；重置 2→1，其余恢复阶段 1→2');
  }
  if (_phase == 'offline' &&
      (!Platform.isAndroid ||
          origin.host != '127.0.0.1' ||
          !origin.hasPort ||
          _testCaBase64.isEmpty)) {
    fail('断连验收仅允许专用 Android 模拟器经本地 HTTPS 端口和测试 CA');
  }
  if ((_phase == 'ack-loss' || _phase == 'd1-error') &&
      (origin.host != '127.0.0.1' ||
          !origin.hasPort ||
          _subject != _ackLossSubject)) {
    fail('完成写入故障验收仅允许本地 HTTPS 夹具及测试身份 $_ackLossSubject');
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

ReaderScreen _reader(WidgetTester tester) =>
    tester.widget<ReaderScreen>(find.byType(ReaderScreen));

Future<void> _closeProvider(ReaderScreen reader) async {
  final provider = reader.provider;
  if (provider is! ChapterPageProvider) fail('阅读须使用正式 Source 页面提供者');
  await provider.close().timeout(_operationBudget);
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _waitFor(tester, '正式控件存在：$target', () {
    return target.evaluate().length == 1;
  });
  await tester.ensureVisible(target);
  await _waitFor(tester, '正式控件可命中：$target', () {
    return target.hitTestable().evaluate().length == 1;
  });
  await tester.tap(target);
  await tester.pump();
}

Future<Finder> _chapterTile(
  WidgetTester tester,
  CatalogController catalog,
) async {
  final page = find.byType(MangaDetailsPage);
  await _waitFor(tester, '正式 Source 返回详情和章节', () {
    return page.evaluate().length == 1;
  });
  if (_phase == 'navigate' && _buildId.isEmpty) {
    return find.widgetWithText(CupertinoListTile, _chapterLabel);
  }
  final details = tester.widget<MangaDetailsPage>(page);
  expect(details.controller, same(catalog));
  expect(catalog.activeBuild!.packageName, _xkcdPackage);
  expect(details.source.sourceId, _xkcdSourceId);
  expect(details.manga.url, _xkcdMangaUrl);
  final sequence = ChapterSequence(
    packageName: _xkcdPackage,
    sourceId: _xkcdSourceId,
    mangaUrl: _xkcdMangaUrl,
    chapters: details.chapters.map((chapter) => chapter.snapshot),
  );
  final chapter = sequence.entries.singleWhere(
    (chapter) => chapter.snapshot.url == _xkcdChapterUrl,
  );
  expect(chapter.stable, isTrue);
  expect(chapter.name, _chapterLabel);
  final tile = find.byKey(ValueKey(chapter.key));
  if (tile.evaluate().isEmpty) {
    final search = find.byKey(const ValueKey('chapter-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, _chapterLabel);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
  }
  await _waitFor(tester, '精确章节可打开', () {
    return tile.evaluate().length == 1 &&
        tester.widget<CupertinoButton>(buttonAbove(tile)).onPressed != null;
  });
  return tile;
}

Future<void> _singlePage(WidgetTester tester) async {
  final layout = find.byKey(const ValueKey('reader-page-layout'));
  await _waitFor(tester, '正式分页控件', () => layout.evaluate().length == 1);
  final selected = tester
      .widget<CupertinoSlidingSegmentedControl<int>>(layout)
      .groupValue;
  final width = tester.getSize(find.byType(ReaderScreen)).width;
  if (selected == 1 || (selected == 0 && width < 900)) {
    return;
  }
  if (_phase != 'navigate' || _shelfEntry) {
    fail('书架续读、前台和重置阶段须预先使用手机自动单页或已确认单页');
  }
  await _waitFor(tester, '正式单页控件可操作', () {
    return !tester
        .widget<CupertinoSlidingSegmentedControl<int>>(layout)
        .disabledChildren
        .contains(1);
  });
  await _tap(tester, find.descendant(of: layout, matching: find.text('单页')));
  await _waitFor(tester, '正式单页控件已应用', () {
    return tester
            .widget<CupertinoSlidingSegmentedControl<int>>(layout)
            .groupValue ==
        1;
  });
}

Future<void> _turnTo(
  WidgetTester tester,
  ChapterManifest manifest,
  int from,
  int to,
) async {
  var page = from;
  while (page != to) {
    final direction = page < to ? 1 : -1;
    final label = direction > 0 ? '下一页' : '上一页';
    final button = iconButton(label);
    expect(tester.widget<CupertinoButton>(button).onPressed, isNotNull);
    await _tap(tester, button);
    page += direction;
    await _waitForPage(tester, manifest, page);
  }
}

Future<ProgressSnapshot> _confirmedProgress(
  WidgetTester tester,
  ProgressRepository repository,
  String mangaKey,
  ChapterManifest manifest, {
  required int page,
  int? epoch,
  int? minimumFurthest,
  bool Function()? ready,
}) async {
  final elapsed = Stopwatch()..start();
  const saved = '阅读进度已保存到服务端';
  while (elapsed.elapsed < _operationBudget) {
    if ((ready?.call() ?? true) &&
        find.text(saved).evaluate().length == 1 &&
        (minimumFurthest == null ||
            (_displayedFurthestPage(tester) ?? 0) >= minimumFurthest)) {
      // Inspection does not advance the mounted reader's write CAS baseline.
      final state = await repository
          .inspectChapter(mangaKey: mangaKey, chapterKey: manifest.chapterKey)
          .timeout(_operationBudget - elapsed.elapsed);
      final progress = state.progress;
      if (progress != null &&
          progress.current.pageIndexHint == page - 1 &&
          (epoch == null || state.epoch == epoch) &&
          (minimumFurthest == null ||
              (progress.furthest?.pageIndexHint ?? -1) >=
                  minimumFurthest - 1) &&
          find.text(saved).evaluate().length == 1 &&
          (ready?.call() ?? true)) {
        _expectProgress(state, manifest, page);
        return state;
      }
    }
    // A decoded frame can precede the post-frame viewport notification.
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('正式 Worker 读回未在预算内确认第 $page 页及预期 epoch');
}

Future<
  ({ProgressSnapshot reopened, ProgressSnapshot remote, ProgressSnapshot stale})
>
_resume(
  WidgetTester tester,
  ProgressRepository repository,
  String mangaKey,
  ChapterManifest manifest,
  ProgressSnapshot before,
) async {
  final oldLeaf = _reader(tester);
  final oldPositionRequest = oldLeaf.positionRequest?.value;
  final oldElement = tester.element(find.byType(ReaderScreen));
  expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
  var paused = false;
  final resumed = Completer<void>();
  final listener = AppLifecycleListener(
    onPause: () {
      if (paused) return;
      paused = true;
      debugPrintSynchronously('SYNC_RESUME_PAUSED pid=$pid');
    },
    onResume: () {
      if (!paused || resumed.isCompleted) return;
      debugPrintSynchronously('SYNC_RESUME_RESUMED pid=$pid');
      resumed.complete();
    },
  );
  try {
    debugPrintSynchronously('SYNC_RESUME_READY pid=$pid');
    // No test reads, gestures or frame pumping while the OS is paused.
    await resumed.future.timeout(
      _lifecycleBudget,
      onTimeout: () => fail('未在预算内观察到系统暂停后恢复'),
    );
  } finally {
    listener.dispose();
  }

  final warning = find.text(_epochChanged);
  final reopen = find.widgetWithText(CupertinoButton, '重新打开本章');
  await _waitFor(tester, '正式前台重取报告远端 epoch 重置', () {
    return warning.evaluate().length == 1 &&
        reopen.evaluate().length == 1 &&
        tester.widget<CupertinoButton>(reopen).onPressed != null;
  });
  await _waitForPage(tester, manifest, _targetPage);
  expect(tester.element(find.byType(ReaderScreen)), same(oldElement));
  expect(_reader(tester).provider, same(oldLeaf.provider));
  expect(_reader(tester).positionRequest?.value, oldPositionRequest);
  for (final label in ['重新阅读本章', '读完本章']) {
    final control = find.widgetWithText(CupertinoButton, label);
    expect(control, findsOneWidget);
    expect(tester.widget<CupertinoButton>(control).onPressed, isNull);
  }
  final remote = await repository
      .inspectChapter(mangaKey: mangaKey, chapterKey: manifest.chapterKey)
      .timeout(_operationBudget);
  expect(remote.epoch, before.epoch + 1);
  expect(remote.revision, greaterThan(before.revision));
  _expectProgress(remote, manifest, _startPage);
  _expectResetState(remote);
  debugPrintSynchronously('SYNC_RESUME_CONFLICT pid=$pid');

  await _turnTo(tester, manifest, _targetPage, _startPage);
  expect(warning, findsOneWidget);
  await _turnTo(tester, manifest, _startPage, _targetPage);
  debugPrintSynchronously('SYNC_RESUME_STALE_VIEW pid=$pid');
  // Observe beyond the product's two-second maximum scheduled save window.
  final elapsed = Stopwatch()..start();
  while (elapsed.elapsed < _staleWriteBudget) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(warning, findsOneWidget);
  expect(tester.element(find.byType(ReaderScreen)), same(oldElement));
  final stale = await repository
      .inspectChapter(mangaKey: mangaKey, chapterKey: manifest.chapterKey)
      .timeout(_operationBudget);
  expect(_progressReport(stale), _progressReport(remote));
  debugPrintSynchronously('SYNC_RESUME_STALE_VERIFIED pid=$pid');

  await _tap(tester, reopen);
  await _waitFor(tester, '显式重开替换原阅读叶并清除冲突', () {
    final leaves = find.byType(ReaderScreen);
    return leaves.evaluate().length == 1 &&
        !identical(_reader(tester).provider, oldLeaf.provider) &&
        warning.evaluate().isEmpty;
  });
  final replacement = _reader(tester);
  expect(tester.element(find.byType(ReaderScreen)), isNot(same(oldElement)));
  expect(
    _anchor(replacement.initialPosition!),
    _anchor(remote.progress!.current),
  );
  expect(replacement.manifest.chapterKey, manifest.chapterKey);
  expect(replacement.manifest.version, manifest.version);
  await _closeProvider(oldLeaf);
  await _waitForPage(tester, replacement.manifest, _startPage);
  final reopened = await _confirmedProgress(
    tester,
    repository,
    mangaKey,
    replacement.manifest,
    page: _startPage,
    epoch: remote.epoch,
    minimumFurthest: _startPage,
  );
  _expectResetState(reopened);
  debugPrintSynchronously('SYNC_RESUME_REOPENED pid=$pid');
  return (reopened: reopened, remote: remote, stale: stale);
}

Future<ProgressSnapshot> _retryAfterOutage(
  WidgetTester tester,
  CatalogController catalog,
  ProgressRepository repository,
  String mangaKey,
  ChapterManifest manifest,
) async {
  final oldElement = tester.element(find.byType(ReaderScreen));
  final oldProvider = _reader(tester).provider;
  final retry = find.widgetWithText(CupertinoButton, '重试保存');
  final pending = find.textContaining('草稿仅保留在当前会话。');
  final origin = Uri.parse(_origin);

  void sameReader() {
    expect(tester.element(find.byType(ReaderScreen)), same(oldElement));
    expect(_reader(tester).provider, same(oldProvider));
  }

  debugPrintSynchronously('SYNC_OFFLINE_READY pid=$pid');
  await _waitForLoopback(tester, origin, connected: false);
  debugPrintSynchronously('SYNC_OFFLINE_SOCKET_DOWN pid=$pid');
  await _turnTo(tester, manifest, _startPage, _targetPage);
  await _waitFor(tester, '真实断连后保留进度草稿和正式重试控件', () {
    return catalog.hasUnsavedReadingProgress &&
        pending.evaluate().length == 1 &&
        retry.evaluate().length == 1 &&
        tester.widget<CupertinoButton>(retry).onPressed != null;
  });
  sameReader();
  await _waitForPage(tester, manifest, _targetPage);
  debugPrintSynchronously('SYNC_OFFLINE_PENDING pid=$pid');

  await _waitForLoopback(tester, origin, connected: true);
  sameReader();
  expect(catalog.hasUnsavedReadingProgress, isTrue);
  expect(pending, findsOneWidget);
  expect(retry, findsOneWidget);
  debugPrintSynchronously('SYNC_OFFLINE_SOCKET_RESTORED pid=$pid');
  await _tap(tester, retry);
  final after = await _confirmedProgress(
    tester,
    repository,
    mangaKey,
    manifest,
    page: _targetPage,
    epoch: _expectedEpoch,
    minimumFurthest: _targetPage,
  );
  sameReader();
  expect(catalog.hasUnsavedReadingProgress, isFalse);
  expect(pending, findsNothing);
  expect(retry, findsNothing);
  debugPrintSynchronously('SYNC_OFFLINE_RETRY_CONFIRMED pid=$pid');
  return after;
}

Future<
  ({
    ProgressSnapshot before,
    ProgressSnapshot unconfirmed,
    ProgressSnapshot confirmed,
  })
>
_retryAfterCompletionFailure(
  WidgetTester tester,
  CatalogController catalog,
  ProgressRepository repository,
  String mangaKey,
  ChapterManifest manifest, {
  required bool expectRollback,
}) async {
  final oldElement = tester.element(find.byType(ReaderScreen));
  final oldProvider = _reader(tester).provider;
  final complete = find.widgetWithText(CupertinoButton, '读完本章');
  final retry = find.widgetWithText(CupertinoButton, '重试保存');
  final pending = find.textContaining('进度尚未获服务器确认');

  // A new viewport observation can be queued before the saved label is
  // repainted. Wait for the actual draft queue and the last-page UI together.
  final before = await _confirmedProgress(
    tester,
    repository,
    mangaKey,
    manifest,
    page: _targetPage,
    epoch: _expectedEpoch,
    minimumFurthest: _targetPage,
    ready: () =>
        !catalog.hasUnsavedReadingProgress &&
        complete.evaluate().length == 1 &&
        tester.widget<CupertinoButton>(complete).onPressed != null,
  );
  expect(before.completed, isFalse, reason: '不能重跑已提交的末页完成');
  expect(before.progress!.furthest!.pageIndexHint, _targetPage - 1);
  void sameReader() {
    expect(tester.element(find.byType(ReaderScreen)), same(oldElement));
    expect(_reader(tester).provider, same(oldProvider));
  }

  sameReader();
  final label = expectRollback ? 'SYNC_D1_ERROR' : 'SYNC_ACK_LOSS';
  debugPrintSynchronously('${label}_READY pid=$pid');
  await _tap(tester, complete);
  await _waitFor(tester, '完成写入未确认后保留草稿和正式重试控件', () {
    return catalog.hasUnsavedReadingProgress &&
        pending.evaluate().length == 1 &&
        retry.evaluate().length == 1 &&
        tester.widget<CupertinoButton>(retry).onPressed != null;
  });
  sameReader();
  await _waitForPage(tester, manifest, _targetPage);

  // Inspection leaves the mounted writer's CAS and pending command intact.
  if (expectRollback) await tester.pump(_staleWriteBudget);
  final unconfirmed = await repository
      .inspectChapter(mangaKey: mangaKey, chapterKey: manifest.chapterKey)
      .timeout(_operationBudget);
  _expectProgress(unconfirmed, manifest, _targetPage);
  final completed = {
    ..._progressReport(before),
    'mangaRevision': before.revision + 1,
    'completed': true,
  };
  expect(
    _progressReport(unconfirmed),
    expectRollback ? _progressReport(before) : completed,
  );
  expect(catalog.hasUnsavedReadingProgress, isTrue);
  expect(pending, findsOneWidget);
  expect(retry, findsOneWidget);
  final outcome = expectRollback ? 'ROLLED_BACK' : 'COMMITTED';
  debugPrintSynchronously('${label}_${outcome}_UNCONFIRMED pid=$pid');

  await _tap(tester, retry);
  final confirmed = await _confirmedProgress(
    tester,
    repository,
    mangaKey,
    manifest,
    page: _targetPage,
    epoch: before.epoch,
    minimumFurthest: _targetPage,
    ready: () => !catalog.hasUnsavedReadingProgress,
  );
  sameReader();
  await _waitForPage(tester, manifest, _targetPage);
  expect(_progressReport(confirmed), completed);
  expect(catalog.hasUnsavedReadingProgress, isFalse);
  expect(pending, findsNothing);
  expect(retry, findsNothing);
  expect(find.text('最远：第 $_targetPage 页 · 本章已读完'), findsOneWidget);
  debugPrintSynchronously('${label}_RETRY_CONFIRMED pid=$pid');
  return (before: before, unconfirmed: unconfirmed, confirmed: confirmed);
}

Future<void> _waitForLoopback(
  WidgetTester tester,
  Uri origin, {
  required bool connected,
}) async {
  // Probe only whether the exact loopback route can accept a connection.
  // Actual app requests still use HTTPS and normal certificate validation.
  final elapsed = Stopwatch()..start();
  while (elapsed.elapsed < _operationBudget) {
    bool reachable;
    try {
      final socket = await Socket.connect(
        origin.host,
        origin.port,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      reachable = true;
    } on SocketException {
      reachable = false;
    }
    if (reachable == connected) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail('专用模拟器未观察到预期的本地连接状态：$connected');
}

void _expectResetState(ProgressSnapshot state) {
  expect(state.completed, isFalse);
  final furthest = state.progress!.furthest;
  if (furthest != null) expect(furthest.pageIndexHint, 0);
}

void _expectProgress(
  ProgressSnapshot state,
  ChapterManifest manifest,
  int page,
) {
  final progress = state.progress!;
  expect(progress.epoch, state.epoch);
  expect(progress.completed, state.completed);
  expect(progress.current.chapterKey, manifest.chapterKey);
  expect(progress.current.manifestVersion, manifest.version);
  expect(progress.current.pageIndexHint, page - 1);
  expect(progress.current.pageKey, manifest.pages[page - 1].key);
  if (progress.furthest case final furthest?) {
    expect(furthest.chapterKey, manifest.chapterKey);
    expect(furthest.manifestVersion, manifest.version);
    expect(
      furthest.pageIndexHint,
      inInclusiveRange(0, manifest.pages.length - 1),
    );
    expect(furthest.pageKey, manifest.pages[furthest.pageIndexHint].key);
  }
}

Map<String, Object?> _progressReport(ProgressSnapshot state) => {
  'mangaRevision': state.revision,
  'epoch': state.epoch,
  'completed': state.completed,
  'current': state.progress == null ? null : _anchor(state.progress!.current),
  'furthest': state.progress?.furthest == null
      ? null
      : _anchor(state.progress!.furthest!),
  'resume': state.resume == null
      ? null
      : {
          'chapterKey': state.resume!.chapterKey,
          'reversedOrder': state.resume!.reversedOrder,
        },
};

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
