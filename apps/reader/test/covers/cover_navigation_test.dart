import '../test_app.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Tristate;

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/covers/cover_selection.dart';
import 'package:karuyomi/features/covers/custom_cover.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/runtime/api_fetch.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import '../data/business_state_server.dart';
import '../data/cover_fakes.dart';

final class _Picker extends FileSelectorPlatform {
  final files = Queue<XFile?>();
  Completer<XFile?>? waiting;
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => waiting != null ? waiting!.future : files.removeFirst();
}

XFile _imageFile({int color = 80, int width = 32, int height = 48}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(color, 70, 180));
  return XFile.fromData(
    img.encodePng(image),
    name: 'cover.png',
    mimeType: 'image/png',
  );
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _decodeImage(WidgetTester tester, Finder image) async {
  await tester.runAsync(
    () => precacheImage(
      tester.widget<Image>(image).image,
      tester.element(image),
    ).timeout(const Duration(seconds: 5)),
  );
  await tester.pumpAndSettle();
}

Future<CatalogController> _details(
  WidgetTester tester,
  TestPlatform platform,
) async {
  await tester.pumpApp(KaruyomiApp(platform: platform));
  await tester.pumpAndSettle();
  await _tap(tester, find.text('去浏览'));
  for (final target in [
    find.byKey(
      const ValueKey((
        'source-directory-row',
        'eu.kanade.source.test',
        sourceId,
      )),
    ),
    find.text('真实源 DTO 测试'),
  ]) {
    await tester.ensureVisible(target);
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }
  await _tap(tester, find.byKey(const ValueKey('chapter-options')));
  return tester
      .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
      .controller;
}

Future<void> _finish(WidgetTester tester, CatalogController controller) async {
  expect(tester.takeException(), isNull);
  await tester.pumpApp(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(controller.closeReadingProgress);
}

void main() {
  late _Picker picker;
  late FileSelectorPlatform previous;
  setUp(() {
    previous = FileSelectorPlatform.instance;
    picker = _Picker();
    FileSelectorPlatform.instance = picker;
  });
  tearDown(() {
    FileSelectorPlatform.instance = previous;
  });

  testWidgets('wide cover previews follow the image and fit a short sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = TestBusinessServer();
    final transport = TestCoverTransport(server);
    final platform = TestPlatform(businessServer: server)..covers = transport;
    final catalog = await _details(tester, platform);
    await _tap(tester, find.byKey(const ValueKey('custom-cover-editor')));
    final editor = find.byKey(const ValueKey('cover-editor'));
    final select = find.byKey(const ValueKey('cover-select-image'));
    picker.files.add(_imageFile(width: 300, height: 150));
    await _tap(tester, select);
    final draft = find.byWidgetPredicate(
      (widget) => widget is Image && widget.semanticLabel == '待保存的封面预览',
    );
    await _decodeImage(tester, draft);
    final draftSize = tester.getSize(draft);
    expect(draftSize.width, greaterThan(200));
    expect(draftSize.height, closeTo(draftSize.width / 2, 1));
    expect(transport.uploads, isEmpty);

    await _tap(tester, find.byKey(const ValueKey('cover-save')));
    final confirmed = find.descendant(
      of: editor,
      matching: find.byType(CustomCover),
    );
    final image = find.descendant(of: confirmed, matching: find.byType(Image));
    await _decodeImage(tester, image);
    expect(tester.getSize(confirmed), draftSize);
    expect(transport.uploads, hasLength(1));

    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    await _decodeImage(tester, image);
    final scrollView = find.descendant(
      of: editor,
      matching: find.byType(SingleChildScrollView),
    );
    final scrollable = find
        .descendant(of: scrollView, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.minScrollExtent);
    await tester.pumpAndSettle();
    final shortPreview = tester.getRect(confirmed);
    expect(
      shortPreview.bottom,
      lessThanOrEqualTo(tester.getRect(scrollView).bottom),
    );
    expect(shortPreview.center.dx, closeTo(tester.getCenter(editor).dx, 1));
    final confirmedWrites = server.appliedMutations;
    await _tap(tester, find.byKey(const ValueKey('cover-clear')));
    expect(find.text('清除自定义封面'), findsOneWidget);
    await _tap(tester, find.text('关闭'));
    expect(editor, findsNothing);
    expect(transport.uploads, hasLength(1));
    expect(server.appliedMutations, confirmedWrites);
    await _finish(tester, catalog);
  });

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'cover reads can be closed before a late reply in $brightness at ${scale}x',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final server = TestBusinessServer();
          final platform = TestPlatform(businessServer: server)
            ..covers = TestCoverTransport(server);
          final controller = await _details(tester, platform);
          final sourceCalls = platform.invocations.length;
          final writes = server.appliedMutations;
          final mangaKey = ChapterSequence(
            packageName: 'eu.kanade.source.test',
            sourceId: sourceId,
            mangaUrl: testManga.url,
            chapters: const [],
          ).mangaKey;
          final readGate = Completer<void>();
          addTearDown(() {
            if (!readGate.isCompleted) readGate.complete();
          });
          platform.beforeApiFetch = (path) async {
            if (Uri.parse(path).path == '/api/state/manga/$mangaKey') {
              await readGate.future;
            }
          };
          await _tap(
            tester,
            find.byKey(const ValueKey('custom-cover-editor')),
            settle: false,
          );
          await tester.pump(const Duration(milliseconds: 500));
          final editor = find.byKey(const ValueKey('cover-editor'));
          expect(editor, findsOneWidget);
          expect(
            find.descendant(of: editor, matching: find.text(testManga.title)),
            findsOneWidget,
          );
          expect(find.text('zh · 测试漫画源'), findsOneWidget);
          expect(find.text('正在读取封面'), findsOneWidget);
          final close = find.widgetWithText(CupertinoButton, '关闭');
          expect(
            tester.widget<CupertinoButton>(close).onPressed,
            isNotNull,
            reason: 'A read must not trap the user in the editor.',
          );
          expect(ModalRoute.of(tester.element(close))?.isCurrent, isTrue);
          await tester.tap(close);
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 3),
          );
          expect(find.byKey(const ValueKey('cover-editor')), findsNothing);
          readGate.complete();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('cover-editor')), findsNothing);
          expect(find.byType(MangaDetailsPage), findsOneWidget);
          expect(platform.invocations.length, sourceCalls);
          expect(server.appliedMutations, writes);
          await _finish(tester, controller);
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'cover states separate reads, drafts and server confirmation in $brightness at ${scale}x',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final server = TestBusinessServer();
          final transport = TestCoverTransport(server);
          final platform = TestPlatform(businessServer: server)
            ..covers = transport;
          final controller = await _details(tester, platform);
          final sourceCalls = platform.invocations.length;
          final writes = server.appliedMutations;
          final mangaKey = ChapterSequence(
            packageName: 'eu.kanade.source.test',
            sourceId: sourceId,
            mangaUrl: testManga.url,
            chapters: const [],
          ).mangaKey;
          final readPath = '/api/state/manga/$mangaKey';
          final readGate = Completer<void>();
          var failRead = true;
          platform.beforeApiFetch = (path) async {
            if (Uri.parse(path).path == readPath) await readGate.future;
          };
          platform.afterBusinessReply = (request, reply) async {
            if (failRead &&
                request.method == 'GET' &&
                request.uri.path == readPath) {
              failRead = false;
              return ApiReply(
                status: 503,
                redirected: false,
                headers: reply.headers,
                body: reply.body,
              );
            }
            return reply;
          };
          addTearDown(() {
            if (!readGate.isCompleted) readGate.complete();
          });
          Finder control(String key) => find.byKey(ValueKey(key));
          void expectContentBelowNavigation() {
            final editor = control('cover-editor');
            final navigation = find.descendant(
              of: editor,
              matching: find.byType(CupertinoNavigationBar),
            );
            final scroll = find.descendant(
              of: editor,
              matching: find.byType(SingleChildScrollView),
            );
            expect(
              tester.getTopLeft(scroll).dy,
              closeTo(tester.getBottomLeft(navigation).dy, 1),
              reason: 'Short cover content must start below the navigation.',
            );
          }

          await _tap(tester, control('custom-cover-editor'), settle: false);
          await tester.pump(const Duration(milliseconds: 500));
          expect(control('cover-editor'), findsOneWidget);
          expect(find.text('服务端已确认'), findsNothing);
          expect(find.text('正在读取封面'), findsOneWidget);
          expectContentBelowNavigation();
          expect(
            tester
                .widget<CupertinoButton>(control('cover-select-image'))
                .onPressed,
            isNull,
          );
          readGate.complete();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          platform.beforeApiFetch = null;
          expect(find.text('服务端已确认'), findsNothing);
          expect(find.text('正在读取封面'), findsNothing);
          expect(find.text('尚未读取服务端封面'), findsOneWidget);
          expect(find.byType(CupertinoActivityIndicator), findsNothing);
          void expectErrorColor() {
            final error = control('cover-error');
            expect(error, findsOneWidget);
            final text = tester.renderObject<RenderParagraph>(error);
            expect(
              text.text.style?.color,
              AppColors.error.resolveFrom(tester.element(error)),
            );
          }

          expectErrorColor();
          await _tap(tester, find.text('重新读取'));
          expect(find.text('服务端已确认'), findsOneWidget);
          expect(find.text('未设置自定义封面'), findsOneWidget);
          expect(find.byType(CupertinoFormSection), findsWidgets);
          expect(control('cover-error'), findsNothing);
          expectContentBelowNavigation();
          picker.files.add(null);
          await _tap(tester, control('cover-select-image'));
          expect(control('cover-save'), findsNothing);
          expect(server.appliedMutations, writes);
          picker.files.add(
            XFile.fromData(
              Uint8List.fromList([1, 2, 3]),
              name: 'invalid.png',
              mimeType: 'image/png',
            ),
          );
          await _tap(tester, control('cover-select-image'));
          expectErrorColor();
          expect(control('cover-save'), findsNothing);
          expect(server.appliedMutations, writes);
          final pickGate = Completer<XFile?>();
          addTearDown(() {
            if (!pickGate.isCompleted) pickGate.complete(null);
          });
          picker.waiting = pickGate;
          await _tap(tester, control('cover-select-image'), settle: false);
          expect(find.text('正在读取所选图片'), findsOneWidget);
          final close = find.widgetWithText(CupertinoButton, '关闭');
          final chooseImage = control('cover-select-image');
          final clearCover = control('cover-clear');
          Tristate enabled(Finder action) => tester
              .getSemantics(action)
              .getSemanticsData()
              .flagsCollection
              .isEnabled;
          expect(tester.widget<CupertinoButton>(close).enabled, isFalse);
          expect(enabled(close), Tristate.isFalse);
          expect(enabled(chooseImage), Tristate.isFalse);
          expect(server.appliedMutations, writes);
          pickGate.complete(_imageFile());
          picker.waiting = null;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(find.text('待保存的修改'), findsOneWidget);
          expect(transport.uploads, isEmpty);
          expectContentBelowNavigation();
          final draftPreview = find.byWidgetPredicate(
            (widget) => widget is Image && widget.semanticLabel == '待保存的封面预览',
          );
          expect(tester.getSize(draftPreview).width, greaterThan(200));
          expect(tester.widget<Image>(draftPreview).fit, BoxFit.contain);
          final saveGate = Completer<void>();
          addTearDown(() {
            if (!saveGate.isCompleted) saveGate.complete();
          });
          transport.beforeUpload = (_) => saveGate.future;
          server.loseNextResponse = true;
          await _tap(tester, control('cover-save'), settle: false);
          expect(find.text('正在等待服务端确认'), findsOneWidget);
          expect(find.text('保存中'), findsOneWidget);
          expect(enabled(control('cover-save')), Tristate.isFalse);
          expect(control('cover-retry'), findsNothing);
          expect(find.textContaining('重试不会更换图片'), findsNothing);
          expect(enabled(close), Tristate.isFalse);
          expect(find.text('服务端已确认'), findsNothing);
          expect(find.text('上次服务端确认'), findsOneWidget);
          expect(find.text('正在提交的修改'), findsOneWidget);
          expect(find.text('未设置自定义封面'), findsOneWidget);
          expect(server.appliedMutations, writes);
          saveGate.complete();
          transport.beforeUpload = null;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(find.text('正在等待服务端确认'), findsNothing);
          expectErrorColor();
          expect(control('cover-retry'), findsOneWidget);
          expect(server.appliedMutations, writes + 1);
          final original = transport.uploads.single;
          final asset = server.manga(mangaKey)!.customCover.assetId;
          await _tap(tester, find.text('稍后'));
          failRead = true;
          await _tap(tester, control('custom-cover-editor'));
          expect(find.text('服务端已确认'), findsNothing);
          expect(find.text('尚未确认的修改'), findsOneWidget);
          expectErrorColor();
          await _tap(tester, control('cover-retry'));
          expect(transport.uploads, hasLength(2));
          expect(transport.uploads.last.mutation, original.mutation);
          expect(transport.uploads.last.bytes, orderedEquals(original.bytes));
          expect(server.appliedMutations, writes + 1);
          expect(find.text('服务端已确认'), findsOneWidget);
          expect(find.text('尚未确认的修改'), findsNothing);
          expect(control('cover-error'), findsNothing);
          final editorPreview = find.descendant(
            of: control('cover-editor'),
            matching: find.byType(CustomCover),
          );
          final confirmedImage = find.descendant(
            of: editorPreview,
            matching: find.byType(Image),
          );
          await _decodeImage(tester, confirmedImage);
          final portraitPreview = tester.getSize(editorPreview);
          expect(portraitPreview.width, greaterThan(200));
          expect(
            tester.getCenter(editorPreview).dx,
            closeTo(tester.getCenter(control('cover-editor')).dx, 1),
          );
          expect(tester.widget<Image>(confirmedImage).fit, BoxFit.contain);
          tester.view.physicalSize = const Size(844, 390);
          await tester.pumpAndSettle();
          await _decodeImage(tester, confirmedImage);
          expect(
            tester.getSize(editorPreview).height,
            lessThan(portraitPreview.height),
          );
          tester.view.physicalSize = const Size(360, 800);
          await tester.pumpAndSettle();
          final replacementPicker = Completer<XFile?>();
          addTearDown(() {
            if (!replacementPicker.isCompleted) {
              replacementPicker.complete(null);
            }
          });
          picker.waiting = replacementPicker;
          await _tap(tester, chooseImage, settle: false);
          expect(find.text('正在读取所选图片'), findsOneWidget);
          expect(find.text('当前自定义封面'), findsOneWidget);
          expect(enabled(close), Tristate.isFalse);
          expect(enabled(chooseImage), Tristate.isFalse);
          expect(enabled(clearCover), Tristate.isFalse);
          replacementPicker.complete(null);
          picker.waiting = null;
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(find.text('正在读取所选图片'), findsNothing);
          expect(enabled(close), Tristate.isTrue);
          expect(enabled(chooseImage), Tristate.isTrue);
          expect(enabled(clearCover), Tristate.isTrue);
          expect(server.manga(mangaKey)!.customCover.assetId, asset);
          expect(server.appliedMutations, writes + 1);
          final clearText = find.descendant(
            of: control('cover-clear'),
            matching: find.text('清除封面'),
          );
          expect(
            tester.renderObject<RenderParagraph>(clearText).text.style?.color,
            AppColors.error.resolveFrom(tester.element(clearText)),
          );
          await _tap(tester, control('cover-clear'));
          expect(find.text('清除自定义封面'), findsOneWidget);
          expect(server.manga(mangaKey)!.customCover.assetId, asset);
          picker.files.add(null);
          await _tap(tester, control('cover-select-image'));
          expect(find.text('清除自定义封面'), findsOneWidget);
          expect(server.appliedMutations, writes + 1);
          await _tap(tester, find.text('关闭'));
          await _tap(tester, control('custom-cover-editor'));
          expect(find.text('待保存的修改'), findsNothing);
          expect(server.manga(mangaKey)!.customCover.assetId, asset);
          await _tap(tester, control('cover-clear'));
          final clearGate = Completer<void>();
          addTearDown(() {
            if (!clearGate.isCompleted) clearGate.complete();
          });
          server.beforeRequest = (request) async {
            if (request.method == 'POST' &&
                request.uri.path == '/api/state/mutations') {
              await clearGate.future;
            }
            return null;
          };
          await _tap(tester, control('cover-save'), settle: false);
          expect(find.text('正在等待服务端确认'), findsOneWidget);
          expect(find.text('上次服务端确认'), findsOneWidget);
          expect(server.manga(mangaKey)!.customCover.assetId, asset);
          expect(server.appliedMutations, writes + 1);
          clearGate.complete();
          server.beforeRequest = null;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();
          expect(server.appliedMutations, writes + 2);
          expect(server.manga(mangaKey)!.hasCustomCover(), false);
          expect(find.text('未设置自定义封面'), findsOneWidget);
          expect(find.text('待保存的修改'), findsNothing);
          expect(transport.uploads, hasLength(2));
          expect(platform.invocations, hasLength(sourceCalls));
          expect(platform.imageControls, isEmpty);
          await _tap(tester, find.text('关闭'));
          await _finish(tester, controller);
        },
      );
    }
  }

  test('cover normalization bakes orientation, bounds output and rejects huge headers before decode', () {
    final oriented = img.Image(width: 20, height: 40);
    oriented.exif.imageIfd.orientation = 6;
    final normalized = normalizeCoverImage(img.encodeJpg(oriented));
    final decoded = img.decodeJpg(normalized)!;
    expect((decoded.width, decoded.height), (40, 20));
    expect(decoded.exif.imageIfd.hasOrientation, false);
    final large = normalizeCoverImage(
      img.encodePng(img.Image(width: 2048, height: 1024)),
    );
    final output = img.decodeJpg(large)!;
    expect((output.width, output.height), (1024, 512));
    expect(large.length, lessThanOrEqualTo(1024 * 1024));
    final header = img.encodeBmp(img.Image(width: 1, height: 1));
    final dimensions = ByteData.sublistView(header);
    dimensions.setInt32(18, 100000, Endian.little);
    dimensions.setInt32(22, 100000, Endian.little);
    expect(
      () => normalizeCoverImage(header),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'budget',
          contains('3200'),
        ),
      ),
    );
    expect(
      () => normalizeCoverImage(Uint8List(16 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
  });

  testWidgets(
    'selected, replaced and cleared covers update details and shelf without Source thumbnails',
    (tester) async {
      tester.view.physicalSize = const Size(480, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = TestBusinessServer();
      final transport = TestCoverTransport(server);
      final platform = TestPlatform(businessServer: server)..covers = transport;
      final controller = await _details(tester, platform);
      final calls = platform.invocations.length;
      await _tap(tester, find.byKey(const ValueKey('custom-cover-editor')));
      picker.files.add(null);
      await _tap(tester, find.byKey(const ValueKey('cover-select-image')));
      expect(find.byKey(const ValueKey('cover-save')), findsNothing);
      picker.files.add(_imageFile());
      await _tap(tester, find.byKey(const ValueKey('cover-select-image')));
      await _tap(tester, find.byKey(const ValueKey('cover-save')));
      expect(transport.uploads.length, 1);
      expect(transport.uploads.single.contentType, 'image/jpeg');
      expect(img.decodeJpg(transport.uploads.single.bytes), isNotNull);
      final key = transport.uploads.single.mangaKey;
      final first = server.manga(key)!.customCover.assetId;
      await _tap(tester, find.text('关闭'));
      expect(
        tester.widget<CustomCover>(find.byType(CustomCover)).cover!.assetId,
        first,
      );
      expect(find.text('加入书架'), findsOneWidget);
      expect(platform.invocations.length, calls);
      expect(platform.imageControls, isEmpty);
      await _tap(tester, find.text('加入书架'));
      await tester.runAsync(() async {
        await tester.binding.handlePopRoute();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      await _tap(tester, find.byType(CupertinoNavigationBarBackButton));
      await _tap(tester, find.text('书架').last);
      expect(
        tester.widget<CustomCover>(find.byType(CustomCover)).cover!.assetId,
        first,
      );
      await _tap(tester, find.text('真实源 DTO 测试'));
      await _tap(tester, find.byKey(const ValueKey('custom-cover-editor')));
      picker.files.add(_imageFile(color: 150));
      await _tap(tester, find.byKey(const ValueKey('cover-select-image')));
      await _tap(tester, find.byKey(const ValueKey('cover-save')));
      final replaced = server.manga(key)!.customCover.assetId;
      expect(replaced, isNot(first));
      await _tap(tester, find.text('关闭'));
      expect(
        tester.widget<CustomCover>(find.byType(CustomCover)).cover!.assetId,
        replaced,
      );
      expect(find.text('移出书架'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('custom-cover-editor')));
      await _tap(tester, find.byKey(const ValueKey('cover-clear')));
      await _tap(tester, find.byKey(const ValueKey('cover-save')));
      await _tap(tester, find.text('关闭'));
      expect(server.manga(key)!.hasCustomCover(), false);
      expect(
        tester.widget<CustomCover>(find.byType(CustomCover)).cover,
        isNull,
      );
      await tester.runAsync(() async {
        await tester.binding.handlePopRoute();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(
        tester.widget<CustomCover>(find.byType(CustomCover)).cover,
        isNull,
      );
      await _finish(tester, controller);
    },
  );

  for (final save in [true, false]) {
    testWidgets(
      'same-detail cover editor updates range revision only after a save: $save',
      (tester) async {
        tester.view.physicalSize = const Size(1100, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final server = TestBusinessServer();
        final transport = TestCoverTransport(server);
        final chapters = [
          wire.Chapter(url: '/one', name: '第一章'),
          wire.Chapter(url: '/two', name: '第二章'),
          wire.Chapter(url: '/other', name: '对照章'),
        ];
        final sequence = ChapterSequence(
          packageName: 'eu.kanade.source.test',
          sourceId: sourceId,
          mangaUrl: testManga.url,
          chapters: chapters,
        );
        final platform = TestPlatform(businessServer: server)
          ..covers = transport
          ..invokeHandler = (call) async => switch (call.whichRequest()) {
            wire.SourceCall_Request.details => wire.SourceResult(
              manga: testManga,
            ),
            wire.SourceCall_Request.chapters => wire.SourceResult(
              chapters: wire.ChapterList(chapters: chapters),
            ),
            wire.SourceCall_Request.pages => throw StateError(
              'Chapter marking must not fetch Source pages',
            ),
            _ => wire.SourceResult(
              mangaPage: wire.MangaPage(mangas: [testManga]),
            ),
          };
        final controller = await _details(tester, platform);

        if (!save) {
          // The editor reads the newer remote revision even if it never saves.
          final remote = BusinessStateClient(
            api: server,
            identity: controller.library!.identity,
          );
          addTearDown(remote.dispose);
          await tester.runAsync(
            () => LibraryRepository(remote).setFavorite(
              packageName: 'eu.kanade.source.test',
              sourceId: sourceId,
              sourceName: '测试漫画源',
              sourceLang: 'zh',
              manga: testManga,
              favorite: true,
            ),
          );
        }
        server.requests.clear();

        Finder control(String key) => find.byKey(ValueKey(key));
        await _tap(tester, control('custom-cover-editor'));
        picker.files.add(_imageFile());
        await _tap(tester, control('cover-select-image'));
        if (save) await _tap(tester, control('cover-save'));
        await _tap(tester, find.text('关闭'));
        expect(transport.uploads, hasLength(save ? 1 : 0));
        if (save) {
          expect(transport.uploads.single.command.expectedRevision, 0);
          expect(server.manga(sequence.mangaKey)?.hasCustomCover(), isTrue);
        }

        await _tap(tester, control('chapter-selection-toggle'));
        await _tap(tester, control('chapter-range-start'));
        await _tap(tester, find.text('第一章 · 来源第 1 项').last);
        await _tap(tester, control('chapter-range-end'));
        await _tap(tester, find.text('第二章 · 来源第 2 项').last);
        await _tap(tester, control('chapter-select-range'));
        await _tap(tester, control('chapter-mark-read'));
        expect(find.text('确认清单：2 章'), findsOneWidget);
        await _tap(tester, find.text('开始'));

        final range = server.requests
            .where(
              (request) =>
                  request.method == 'POST' &&
                  request.uri.path == '/api/state/mutations',
            )
            .map(
              (request) => wire.decodeProtoJson(
                wire.StateMutation(),
                jsonDecode(request.body!),
              ),
            )
            .toList();
        if (save) {
          expect(find.text('全部标记已由服务端确认。'), findsOneWidget);
          expect(range.map((command) => command.expectedRevision), [1, 2]);
          expect(range.map((command) => command.setChapterRead.chapterKey), [
            for (final chapter in sequence.entries.take(2)) chapter.key,
          ]);
        } else {
          expect(find.textContaining('作品已在其他操作或设备更新'), findsWidgets);
          expect(range, isEmpty);
          expect(server.manga(sequence.mangaKey)?.favorite, isTrue);
        }
        expect(
          server.progress(sequence.mangaKey, sequence.entries.last.key),
          isNull,
        );
        await _finish(tester, controller);
      },
    );
  }

  testWidgets(
    'lost ACK retries the immutable original while CAS conflict only reloads',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = TestBusinessServer();
      final transport = TestCoverTransport(server);
      final platform = TestPlatform(businessServer: server)..covers = transport;
      final controller = await _details(tester, platform);
      await _tap(tester, find.byKey(const ValueKey('custom-cover-editor')));
      picker.files.add(_imageFile());
      await _tap(tester, find.byKey(const ValueKey('cover-select-image')));
      server.loseNextResponse = true;
      await _tap(tester, find.byKey(const ValueKey('cover-save')));
      expect(find.byKey(const ValueKey('cover-retry')), findsOneWidget);
      final original = transport.uploads.single;
      final asset = server.manga(original.mangaKey)!.customCover.assetId;
      await _tap(tester, find.text('稍后'));
      var failRead = true;
      platform.afterBusinessReply = (request, reply) async {
        if (failRead &&
            request.method == 'GET' &&
            request.uri.path == '/api/state/manga/${original.mangaKey}') {
          failRead = false;
          return ApiReply(
            status: 503,
            redirected: false,
            headers: reply.headers,
            body: reply.body,
          );
        }
        return reply;
      };
      await _tap(tester, find.byKey(const ValueKey('custom-cover-editor')));
      expect(find.text('未能读取服务端封面，请重试。'), findsOneWidget);
      expect(
        tester
            .widget<CupertinoButton>(
              find.byKey(const ValueKey('cover-select-image')),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, find.byKey(const ValueKey('cover-retry')));
      expect(transport.uploads.length, 2);
      expect(transport.uploads.last.mutation, original.mutation);
      expect(transport.uploads.last.bytes, orderedEquals(original.bytes));
      expect(server.appliedMutations, 1);
      platform.afterBusinessReply = null;
      await _tap(tester, find.text('关闭'));
      expect(
        tester.widget<CustomCover>(find.byType(CustomCover)).cover!.assetId,
        asset,
      );
      await _tap(tester, find.byKey(const ValueKey('custom-cover-editor')));
      picker.files.add(_imageFile(color: 180));
      await _tap(tester, find.byKey(const ValueKey('cover-select-image')));
      final remote = BusinessStateClient(
        api: server,
        identity: controller.library!.identity,
        covers: transport,
      );
      await LibraryRepository(remote).setFavorite(
        packageName: 'eu.kanade.source.test',
        sourceId: sourceId,
        sourceName: '测试漫画源',
        sourceLang: 'zh',
        manga: testManga,
        favorite: true,
      );
      await _tap(tester, find.byKey(const ValueKey('cover-save')));
      expect(find.textContaining('其他设备更新'), findsOneWidget);
      expect(find.byKey(const ValueKey('cover-retry')), findsNothing);
      expect(server.manga(original.mangaKey)!.customCover.assetId, asset);
      final uploads = transport.uploads.length;
      await _tap(tester, find.text('重新读取'));
      expect(transport.uploads.length, uploads);
      expect(find.byKey(const ValueKey('cover-save')), findsNothing);
      expect(server.manga(original.mangaKey)!.customCover.assetId, asset);
      await _tap(tester, find.text('关闭'));
      await remote.dispose();
      await _finish(tester, controller);
    },
  );

  testWidgets(
    'a picker finishing after identity replacement cannot publish or upload into the new account',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = TestBusinessServer();
      final transport = TestCoverTransport(server);
      final platform = TestPlatform(businessServer: server)..covers = transport;
      final controller = await _details(tester, platform);
      await _tap(tester, find.byKey(const ValueKey('custom-cover-editor')));
      final gate = Completer<XFile?>();
      picker.waiting = gate;
      await _tap(
        tester,
        find.byKey(const ValueKey('cover-select-image')),
        settle: false,
      );
      platform.bootstrapSubject = 'another-owner';
      final replacement = TestCoverTransport(server, subject: 'another-owner');
      platform.covers = replacement;
      await tester.runAsync(controller.connect);
      await tester.pumpAndSettle();
      expect(find.textContaining('原窗口已停用'), findsOneWidget);
      gate.complete(_imageFile());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(transport.uploads, isEmpty);
      expect(replacement.uploads, isEmpty);
      expect(find.byKey(const ValueKey('cover-save')), findsNothing);
      await _tap(tester, find.text('关闭'));
      expect(find.textContaining('会话已变化'), findsOneWidget);
      await _finish(tester, controller);
    },
  );
}
