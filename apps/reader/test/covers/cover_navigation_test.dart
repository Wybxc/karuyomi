import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/covers/cover_selection.dart';
import 'package:karuyomi/features/covers/custom_cover.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/runtime/api_fetch.dart';

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

XFile _imageFile([int color = 80]) {
  final image = img.Image(width: 32, height: 48);
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

Future<CatalogController> _details(
  WidgetTester tester,
  TestPlatform platform,
) async {
  await tester.pumpWidget(KaruyomiApp(platform: platform));
  await tester.pumpAndSettle();
  for (final text in ['去浏览', 'source.test · 1.0', '测试漫画源 · zh', '真实源 DTO 测试']) {
    await _tap(tester, find.text(text));
  }
  return tester
      .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
      .controller;
}

Future<void> _finish(WidgetTester tester, CatalogController controller) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
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

  test(
    'cover normalization bakes orientation, bounds output and rejects huge headers before decode',
    () {
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
    },
  );

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
      await _tap(tester, find.text('书架').last);
      expect(
        tester.widget<CustomCover>(find.byType(CustomCover)).cover!.assetId,
        first,
      );
      await _tap(tester, find.text('真实源 DTO 测试'));
      await _tap(tester, find.byKey(const ValueKey('custom-cover-editor')));
      picker.files.add(_imageFile(150));
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
      await _tap(tester, find.text('稍后处理'));
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
            .widget<OutlinedButton>(
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
      picker.files.add(_imageFile(180));
      await _tap(tester, find.byKey(const ValueKey('cover-select-image')));
      final remote = BusinessStateClient(
        api: server,
        identity: controller.library!.identity,
        covers: transport,
      );
      await LibraryRepository(remote).setFavorite(
        packageName: 'source.test',
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
