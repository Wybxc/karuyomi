import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/features/reader/reader_preferences.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:karuyomi/runtime/platform_runtime_native.dart' as native;
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';

List<wire.Chapter> get _chapters => [
  wire.Chapter(url: '/one', name: '第一章'),
  wire.Chapter(url: '/two', name: '第二章'),
];

TestPlatform _platform() =>
    TestPlatform()
      ..invokeHandler = (call) async => switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(manga: testManga),
        wire.SourceCall_Request.chapters => wire.SourceResult(
          chapters: wire.ChapterList(chapters: _chapters),
        ),
        wire.SourceCall_Request.pages => wire.SourceResult(
          pageList: wire.PageList(
            pageSessionId: 'settings-${call.pages.chapter.url}',
            pages: [
              wire.Page(
                pageKey: 'page-one',
                url: '${call.pages.chapter.url}/page-one',
              ),
            ],
          ),
        ),
        _ => wire.SourceResult(mangaPage: wire.MangaPage(mangas: [testManga])),
      };

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final page = find.byType(MangaDetailsPage).evaluate().isNotEmpty
        ? find.byType(MangaDetailsPage)
        : find.byType(CatalogPage);
    final scrollable = find
        .descendant(of: page, matching: find.byType(Scrollable))
        .first;
    await tester.drag(scrollable, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 250, scrollable: scrollable);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Future<void> _choose<T>(WidgetTester tester, String label) async {
  await _tap(tester, find.byType(DropdownButtonFormField<T>));
  await _tap(tester, find.text(label).last);
}

Finder _field<T>(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is DropdownButtonFormField<T> &&
      widget.decoration.labelText == label,
);
Future<void> _chooseField<T>(
  WidgetTester tester,
  String field,
  String value,
) async {
  await _tap(tester, _field<T>(field));
  await _tap(tester, find.text(value).last);
}

Finder _navigation(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is NavigationRail || widget is NavigationBar,
  ),
  matching: find.text(label),
);
Future<void> _dim(
  WidgetTester tester,
  String scope, {
  required bool zero,
}) async {
  final slider = find.byKey(ValueKey('$scope-dim'));
  await tester.ensureVisible(slider);
  await tester.pumpAndSettle();
  if (zero) {
    await tester.drag(slider, const Offset(-500, 0));
  } else {
    await tester.tap(slider);
  }
  await tester.pumpAndSettle();
}

Future<void> _start(
  WidgetTester tester,
  TestPlatform platform, {
  Size size = const Size(1100, 1800),
  PlatformRuntime Function(Uri? origin)? factory,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    KaruyomiApp(platform: platform, platformFactory: factory),
  );
  await tester.pumpAndSettle();
}

Future<void> _globalDefaults(WidgetTester tester, {bool dark = false}) async {
  await _tap(tester, _navigation('设置'));
  if (dark) await _choose<wire.AppTheme>(tester, '深色');
  await _choose<wire.ReaderMode>(tester, '从右到左');
  await _choose<wire.ReaderPageLayout>(tester, '双页');
  await _chooseField<wire.ReaderFit>(tester, '图像适配', '适宽');
  await _chooseField<bool>(tester, '裁白', '开启');
  await _chooseField<wire.ReaderBackground>(tester, '阅读背景', '白色');
  await _dim(tester, 'global', zero: false);
  await _chooseField<wire.ReaderInputPreset>(tester, '分页点击区', '反向');
  await _chooseField<wire.ReaderInputPreset>(tester, '阅读快捷键', '关闭');
}

Future<CatalogController> _details(WidgetTester tester) async {
  await _tap(tester, _navigation('浏览'));
  await _tap(tester, find.text('eu.kanade.source.test · 1.0'));
  await _tap(tester, find.byKey(ValueKey(('catalog-source', sourceId))));
  await _tap(tester, find.text('真实源 DTO 测试'));
  return tester
      .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
      .controller;
}

String get _mangaKey => ChapterSequence(
  packageName: 'eu.kanade.source.test',
  sourceId: sourceId,
  mangaUrl: testManga.url,
  chapters: _chapters,
).mangaKey;

ReaderScreen _reader(WidgetTester tester) =>
    tester.widget<ReaderScreen>(find.byType(ReaderScreen));

Future<void> _closeModal(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.binding.handlePopRoute();
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Future<void> _leaveReader(
  WidgetTester tester,
  CatalogController catalog,
) async {
  final route = ModalRoute.of(tester.element(find.byType(ReaderScreen)))!;
  await tester.runAsync(catalog.flushReadingProgress);
  await tester.pumpAndSettle();
  await _closeModal(tester);
  await tester.runAsync(() async {
    await route.completed;
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
  expect(find.byType(MangaDetailsPage), findsOneWidget);
}

Future<void> _finish(WidgetTester tester, CatalogController catalog) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(catalog.closeReadingProgress);
}

void main() {
  for (final trailingSlash in [false, true]) {
    testWidgets(
      'native same-service reconnect${trailingSlash ? ' with a trailing slash' : ''} preserves the exact pending settings mutation',
      (tester) async {
        final platform = TestPlatform(seedDefaultInstallation: false);
        final replacement = TestPlatform(
          businessServer: platform.businessServer,
          seedDefaultInstallation: false,
        );
        final factoryOrigins = <Uri?>[];
        await _start(
          tester,
          platform,
          factory: (origin) {
            factoryOrigins.add(origin);
            return replacement;
          },
        );
        await _tap(tester, _navigation('设置'));
        final initial = tester
            .widget<GlobalSettingsPanel>(find.byType(GlobalSettingsPanel))
            .controller;
        final originalRevision = initial.snapshot!.globalRevision;
        await _choose<wire.AppTheme>(tester, '深色');
        platform.afterBusinessReply = (request, reply) {
          if (request.method != 'POST' ||
              request.uri.path != '/api/settings/mutations') {
            return reply;
          }
          platform.afterBusinessReply = null;
          return ApiReply(
            status: reply.status,
            headers: reply.headers,
            redirected: reply.redirected,
            body: '{',
          );
        };
        await _tap(tester, find.text('保存全局设置'));
        final originalRequest = platform.businessServer.requests
            .where((request) => request.uri.path == '/api/settings/mutations')
            .single;
        final originalMutation = wire.decodeProtoJson(
          wire.SettingsMutation(),
          jsonDecode(originalRequest.body!),
        );
        expect(originalMutation.mutationId, isNotEmpty);
        expect(originalMutation.expectedRevision, originalRevision);
        expect(originalMutation.setGlobal.theme, wire.AppTheme.APP_THEME_DARK);
        expect(initial.pending, isNotNull);
        expect(platform.businessServer.appliedMutations, 1);
        expect(platform.openedBuilds, isEmpty);
        await tester.enterText(
          find.byType(TextField),
          '${platform.origin.origin}${trailingSlash ? '/' : ''}',
        );
        await _tap(tester, find.text('连接服务'));
        final reconnected = tester
            .widget<GlobalSettingsPanel>(find.byType(GlobalSettingsPanel))
            .controller;
        expect(reconnected.pending, isNotNull);
        expect(reconnected.pending!.basedOnRevision, originalRevision);
        expect(
          reconnected.pending!.global!.theme,
          wire.AppTheme.APP_THEME_DARK,
        );
        expect(reconnected.repository.client, same(initial.repository.client));
        expect(factoryOrigins, isEmpty);
        expect(platform.rebuildCount, 1);
        expect(platform.disposalCount, 0);
        expect(
          platform.businessServer.requests.where(
            (request) => request.uri.path == '/api/settings/mutations',
          ),
          hasLength(1),
        );
        expect(find.text('设置尚未确认，本会话保留原操作。'), findsOneWidget);
        await _tap(tester, find.text('重试原设置操作'));
        final requests = platform.businessServer.requests
            .where((request) => request.uri.path == '/api/settings/mutations')
            .toList();
        final retriedMutation = wire.decodeProtoJson(
          wire.SettingsMutation(),
          jsonDecode(requests.last.body!),
        );
        expect(requests.map((request) => request.body), [
          originalRequest.body,
          originalRequest.body,
        ]);
        expect(retriedMutation.mutationId, originalMutation.mutationId);
        expect(retriedMutation.expectedRevision, originalRevision);
        expect(platform.businessServer.appliedMutations, 1);
        expect(reconnected.pending, isNull);
        expect(find.text('重试原设置操作'), findsNothing);
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
          ThemeMode.dark,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  for (final invalidOrigin in [
    'https://reader.example.com/path',
    'http://reader.example.com',
    'https://[',
  ]) {
    testWidgets(
      'rejected service address $invalidOrigin preserves pending settings for an exact retry',
      (tester) async {
        final platform = TestPlatform(seedDefaultInstallation: false);
        final factoryOrigins = <Uri?>[];
        await _start(
          tester,
          platform,
          factory: (origin) {
            factoryOrigins.add(origin);
            return native.createPlatformRuntime(origin: origin);
          },
        );
        await _tap(tester, _navigation('设置'));
        final initial = tester
            .widget<GlobalSettingsPanel>(find.byType(GlobalSettingsPanel))
            .controller;
        await _choose<wire.AppTheme>(tester, '深色');
        platform.afterBusinessReply = (request, reply) {
          if (request.method != 'POST' ||
              request.uri.path != '/api/settings/mutations') {
            return reply;
          }
          platform.afterBusinessReply = null;
          return ApiReply(
            status: reply.status,
            headers: reply.headers,
            redirected: reply.redirected,
            body: '{',
          );
        };
        await _tap(tester, find.text('保存全局设置'));
        final originalRequest = platform.businessServer.requests
            .where((request) => request.uri.path == '/api/settings/mutations')
            .single;
        final pending = initial.pending;
        expect(pending, isNotNull);
        await tester.enterText(find.byType(TextField), invalidOrigin);
        await _tap(tester, find.text('连接服务'));
        expect(find.byType(GlobalSettingsPanel), findsOneWidget);
        final rejected = tester
            .widget<GlobalSettingsPanel>(find.byType(GlobalSettingsPanel))
            .controller;
        expect(rejected, same(initial));
        expect(rejected.pending, isNotNull);
        expect(rejected.pending!.basedOnRevision, pending!.basedOnRevision);
        expect(rejected.pending!.global, pending.global);
        expect(rejected.pending!.retryable, pending.retryable);
        expect(rejected.available, true);
        expect(platform.disposalCount, 0);
        expect(platform.rebuildCount, 0);
        expect(platform.businessServer.appliedMutations, 1);
        expect(
          platform.businessServer.requests.where(
            (request) => request.uri.path == '/api/settings/mutations',
          ),
          hasLength(1),
        );
        expect(find.textContaining('请先在设置中填写服务的 HTTPS 地址'), findsOneWidget);
        expect(
          factoryOrigins,
          Uri.tryParse(invalidOrigin) == null
              ? isEmpty
              : [Uri.parse(invalidOrigin)],
        );
        await tester.enterText(
          find.byType(TextField),
          platform.origin.toString(),
        );
        await _tap(tester, find.text('连接服务'));
        final reconnected = tester
            .widget<GlobalSettingsPanel>(find.byType(GlobalSettingsPanel))
            .controller;
        expect(reconnected.pending, isNotNull);
        expect(reconnected.repository.client, same(initial.repository.client));
        expect(find.textContaining('请先在设置中填写服务的 HTTPS 地址'), findsNothing);
        await _tap(tester, find.text('重试原设置操作'));
        expect(
          platform.businessServer.requests
              .where((request) => request.uri.path == '/api/settings/mutations')
              .map((request) => request.body),
          [originalRequest.body, originalRequest.body],
        );
        expect(platform.businessServer.appliedMutations, 1);
        expect(reconnected.pending, isNull);
        expect(platform.openedBuilds, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  for (final changeOrigin in [true, false]) {
    testWidgets(
      'native ${changeOrigin ? 'service' : 'subject'} changes isolate pending settings from the new identity',
      (tester) async {
        final original = TestPlatform(seedDefaultInstallation: false);
        final replacement = TestPlatform(
          origin: changeOrigin
              ? Uri.parse('https://other.example')
              : original.origin,
          bootstrapSubject: changeOrigin ? 'owner-subject' : 'other-subject',
          businessServer: changeOrigin ? null : original.businessServer,
          seedDefaultInstallation: false,
        );
        final factoryOrigins = <Uri?>[];
        await _start(
          tester,
          original,
          factory: (origin) {
            factoryOrigins.add(origin);
            return replacement;
          },
        );
        await _tap(tester, _navigation('设置'));
        final previous = tester
            .widget<GlobalSettingsPanel>(find.byType(GlobalSettingsPanel))
            .controller;
        await _choose<wire.AppTheme>(tester, '深色');
        original.afterBusinessReply = (request, reply) {
          if (request.method != 'POST' ||
              request.uri.path != '/api/settings/mutations') {
            return reply;
          }
          original.afterBusinessReply = null;
          return ApiReply(
            status: reply.status,
            headers: reply.headers,
            redirected: reply.redirected,
            body: '{',
          );
        };
        await _tap(tester, find.text('保存全局设置'));
        final oldRequest = original.businessServer.requests
            .where((request) => request.uri.path == '/api/settings/mutations')
            .single;
        final oldMutation = wire.decodeProtoJson(
          wire.SettingsMutation(),
          jsonDecode(oldRequest.body!),
        );
        expect(previous.pending, isNotNull);
        if (!changeOrigin) {
          original.bootstrapSubject = replacement.bootstrapSubject;
        }
        await tester.enterText(
          find.byType(TextField),
          replacement.origin.toString(),
        );
        await _tap(tester, find.text('连接服务'));
        final current = tester
            .widget<GlobalSettingsPanel>(find.byType(GlobalSettingsPanel))
            .controller;
        expect(current.repository.identity.origin, replacement.origin);
        expect(
          current.repository.identity.subject,
          replacement.bootstrapSubject,
        );
        expect(current.pending, isNull);
        expect(current.snapshot!.global.theme, wire.AppTheme.APP_THEME_SYSTEM);
        expect(previous.available, false);
        expect(previous.canRetry, false);
        expect(await tester.runAsync(previous.retry), false);
        expect(find.text('重试原设置操作'), findsNothing);
        expect(
          original.businessServer.requests.where(
            (request) => request.uri.path == '/api/settings/mutations',
          ),
          hasLength(1),
        );
        if (changeOrigin) {
          expect(factoryOrigins, [replacement.origin]);
          expect(original.disposalCount, 1);
          expect(
            replacement.businessServer.requests.where(
              (request) => request.uri.path == '/api/settings/mutations',
            ),
            isEmpty,
          );
        } else {
          expect(factoryOrigins, isEmpty);
          expect(original.rebuildCount, 1);
          expect(original.disposalCount, 0);
        }
        await _choose<wire.AppTheme>(tester, '浅色');
        await _tap(tester, find.text('保存全局设置'));
        final newRequest = replacement.businessServer.requests
            .where((request) => request.uri.path == '/api/settings/mutations')
            .last;
        final newMutation = wire.decodeProtoJson(
          wire.SettingsMutation(),
          jsonDecode(newRequest.body!),
        );
        expect(newMutation.mutationId, isNot(oldMutation.mutationId));
        expect(newMutation.expectedRevision, 0);
        expect(newMutation.setGlobal.theme, wire.AppTheme.APP_THEME_LIGHT);
        expect(
          newRequest.headers['X-App-Subject'],
          replacement.bootstrapSubject,
        );
        expect(current.pending, isNull);
        expect(current.snapshot!.global.theme, wire.AppTheme.APP_THEME_LIGHT);
        expect(original.businessServer.appliedMutations, changeOrigin ? 1 : 2);
        if (changeOrigin) {
          expect(replacement.businessServer.appliedMutations, 1);
        }
        expect(original.openedBuilds, isEmpty);
        expect(replacement.openedBuilds, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'global settings save confirms the app theme and reader defaults are inherited by a manga',
    (tester) async {
      final platform = _platform();
      await _start(tester, platform);
      await _globalDefaults(tester, dark: true);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      expect(
        platform.businessServer.requests.where(
          (request) => request.uri.path == '/api/settings/mutations',
        ),
        isEmpty,
      );
      await _tap(tester, find.text('保存全局设置'));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      final catalog = await _details(tester);
      final inherited = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(inherited!.global.theme, wire.AppTheme.APP_THEME_DARK);
      expect(inherited.overrides!.hasMode(), false);
      expect(inherited.overrides!.hasPageLayout(), false);
      expect(inherited.overrides!.hasFit(), false);
      expect(inherited.overrides!.hasCropBorders(), false);
      expect(inherited.effectiveReader.cropBorders, true);
      expect(inherited.effectiveReader.fit, wire.ReaderFit.READER_FIT_WIDTH);
      expect(inherited.overrides!.hasBackground(), false);
      expect(inherited.overrides!.hasDimPercent(), false);
      expect(inherited.overrides!.hasTapZones(), false);
      expect(inherited.overrides!.hasKeyboard(), false);
      expect(
        inherited.effectiveReader.background,
        wire.ReaderBackground.READER_BACKGROUND_WHITE,
      );
      expect(inherited.effectiveReader.dimPercent, 40);
      expect(
        inherited.effectiveReader.tapZones,
        wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED,
      );
      expect(
        inherited.effectiveReader.keyboard,
        wire.ReaderInputPreset.READER_INPUT_PRESET_DISABLED,
      );
      expect(
        inherited.effectiveReader.mode,
        wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
      );
      expect(
        inherited.effectiveReader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
      );
      await _tap(tester, find.text('第一章'));
      expect(_reader(tester).initialMode, ReadingMode.rightToLeft);
      expect(_reader(tester).doublePage, true);
      expect(_reader(tester).fit, ReaderFit.width);
      expect(_reader(tester).cropBorders, true);
      expect(_reader(tester).background, ReaderBackground.white);
      expect(_reader(tester).dimPercent, 40);
      expect(_reader(tester).tapZones, ReaderInputPreset.reversed);
      expect(_reader(tester).keyboard, ReaderInputPreset.disabled);
      expect(
        tester
            .widget<DropdownButton<ReadingMode>>(
              find.byType(DropdownButton<ReadingMode>),
            )
            .value,
        ReadingMode.rightToLeft,
      );
      expect(
        tester
            .widget<SegmentedButton<bool?>>(find.byType(SegmentedButton<bool?>))
            .selected,
        {true},
      );
      await _leaveReader(tester, catalog);
      await _finish(tester, catalog);
    },
  );

  testWidgets(
    'reader choices save manga overrides, modal inheritance is per field, and AUTO survives chapter replacement and reopening',
    (tester) async {
      final platform = _platform();
      await _start(tester, platform);
      await _globalDefaults(tester);
      await _tap(tester, find.text('保存全局设置'));
      final catalog = await _details(tester);
      await _tap(tester, find.text('第一章'));
      final leafBeforeFit = _reader(tester).key;
      await _tap(tester, find.text('阅读设置'));
      await _chooseField<wire.ReaderFit>(tester, '图像适配', '适高');
      await _chooseField<bool>(tester, '裁白', '关闭');
      await _tap(tester, find.text('保存本漫画设置'));
      await _closeModal(tester);
      expect(_reader(tester).key, leafBeforeFit);
      expect(_reader(tester).fit, ReaderFit.height);
      expect(_reader(tester).cropBorders, false);
      await _tap(tester, find.text('重新阅读本章'));
      final reset = _reader(tester).positionRequest!.value!;
      expect(reset.normalizedOffset, 0);
      expect(reset.normalizedX, 1);
      expect(reset.viewportX, 1);
      expect(reset.viewportY, 0);
      expect(_reader(tester).key, leafBeforeFit);
      await _tap(tester, find.byType(DropdownButton<ReadingMode>));
      await _tap(tester, find.text('从左到右').last);
      await _tap(
        tester,
        find.descendant(
          of: find.byType(SegmentedButton<bool?>),
          matching: find.text('单页'),
        ),
      );
      var snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(
        snapshot!.overrides!.mode,
        wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
      );
      expect(
        snapshot.overrides!.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_SINGLE,
      );
      expect(snapshot.overrides!.fit, wire.ReaderFit.READER_FIT_HEIGHT);
      expect(snapshot.overrides!.hasCropBorders(), true);
      expect(snapshot.overrides!.cropBorders, false);
      expect(
        snapshot.global.reader.mode,
        wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
      );
      expect(
        snapshot.global.reader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
      );
      await _tap(tester, find.text('阅读设置'));
      expect(find.byType(MangaSettingsEditor), findsOneWidget);
      final leafBeforeAppearance = _reader(tester).key;
      await _chooseField<wire.ReaderFit>(tester, '图像适配', '完整显示');
      await _chooseField<wire.ReaderBackground>(tester, '阅读背景', '黑色');
      await _tap(tester, find.byKey(const ValueKey('manga-dim-inherit')));
      await _dim(tester, 'manga', zero: true);
      await _chooseField<wire.ReaderInputPreset>(tester, '分页点击区', '标准');
      await _chooseField<wire.ReaderInputPreset>(tester, '阅读快捷键', '反向');
      await _tap(tester, find.text('保存本漫画设置'));
      expect(_reader(tester).key, leafBeforeAppearance);
      expect(_reader(tester).fit, ReaderFit.contain);
      expect(_reader(tester).cropBorders, false);
      expect(_reader(tester).background, ReaderBackground.black);
      expect(_reader(tester).dimPercent, 0);
      expect(_reader(tester).tapZones, ReaderInputPreset.standard);
      expect(_reader(tester).keyboard, ReaderInputPreset.reversed);
      snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(snapshot!.overrides!.hasFit(), true);
      expect(snapshot.overrides!.fit, wire.ReaderFit.READER_FIT_CONTAIN);
      expect(snapshot.overrides!.hasCropBorders(), true);
      expect(snapshot.overrides!.cropBorders, false);
      expect(snapshot.overrides!.hasDimPercent(), true);
      expect(snapshot.overrides!.dimPercent, 0);
      await _choose<wire.ReaderMode>(tester, '跟随全局');
      await _tap(tester, find.text('保存本漫画设置'));
      snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(snapshot!.overrides!.hasMode(), false);
      expect(
        snapshot.overrides!.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_SINGLE,
      );
      await _closeModal(tester);
      expect(_reader(tester).initialMode, ReadingMode.rightToLeft);
      expect(_reader(tester).doublePage, false);
      await _tap(tester, find.text('阅读设置'));
      await _choose<wire.ReaderPageLayout>(tester, '跟随全局');
      await _tap(tester, find.text('保存本漫画设置'));
      snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(snapshot!.overrides!.hasMode(), false);
      expect(snapshot.overrides!.hasPageLayout(), false);
      await _closeModal(tester);
      expect(_reader(tester).doublePage, true);
      await _tap(
        tester,
        find.descendant(
          of: find.byType(SegmentedButton<bool?>),
          matching: find.text('自动'),
        ),
      );
      snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(snapshot!.overrides!.hasPageLayout(), true);
      expect(snapshot.overrides!.hasFit(), true);
      expect(snapshot.overrides!.fit, wire.ReaderFit.READER_FIT_CONTAIN);
      expect(snapshot.overrides!.hasCropBorders(), true);
      expect(snapshot.overrides!.cropBorders, false);
      expect(snapshot.overrides!.hasDimPercent(), true);
      expect(snapshot.overrides!.dimPercent, 0);
      expect(
        snapshot.overrides!.background,
        wire.ReaderBackground.READER_BACKGROUND_BLACK,
      );
      expect(
        snapshot.overrides!.tapZones,
        wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
      );
      expect(
        snapshot.overrides!.keyboard,
        wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED,
      );
      expect(
        snapshot.overrides!.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      );
      expect(_reader(tester).doublePage, isNull);
      expect(
        tester
            .widget<SegmentedButton<bool?>>(find.byType(SegmentedButton<bool?>))
            .selected,
        {null},
      );
      final writes = platform.businessServer.requests
          .where((request) => request.uri.path == '/api/settings/mutations')
          .length;
      final firstLeaf = _reader(tester).key;
      await tester.ensureVisible(find.text('下一章'));
      await tester.runAsync(() async {
        await tester.tap(find.text('下一章'));
        await Future<void>.delayed(Duration.zero);
      });
      // Replacing the leaf first disposes its resources in a frame, then
      // restores the next chapter through the real supplier continuation.
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(_reader(tester).key, isNot(firstLeaf));
      expect(_reader(tester).fit, ReaderFit.contain);
      expect(_reader(tester).cropBorders, false);
      expect(_reader(tester).background, ReaderBackground.black);
      expect(_reader(tester).dimPercent, 0);
      expect(_reader(tester).tapZones, ReaderInputPreset.standard);
      expect(_reader(tester).keyboard, ReaderInputPreset.reversed);
      expect(_reader(tester).initialMode, ReadingMode.rightToLeft);
      expect(_reader(tester).doublePage, isNull);
      expect(
        tester
            .widget<SegmentedButton<bool?>>(find.byType(SegmentedButton<bool?>))
            .selected,
        {null},
      );
      await _leaveReader(tester, catalog);
      await _tap(tester, find.text('第一章'));
      expect(_reader(tester).fit, ReaderFit.contain);
      expect(_reader(tester).cropBorders, false);
      expect(_reader(tester).doublePage, isNull);
      expect(
        tester
            .widget<SegmentedButton<bool?>>(find.byType(SegmentedButton<bool?>))
            .selected,
        {null},
      );
      expect(
        platform.businessServer.requests.where(
          (request) => request.uri.path == '/api/settings/mutations',
        ),
        hasLength(writes),
      );
      await _tap(tester, find.text('阅读设置'));
      await _chooseField<wire.ReaderFit>(tester, '图像适配', '跟随全局');
      await _chooseField<bool>(tester, '裁白', '跟随全局');
      await _chooseField<wire.ReaderBackground>(tester, '阅读背景', '跟随全局');
      await _tap(tester, find.byKey(const ValueKey('manga-dim-inherit')));
      await _chooseField<wire.ReaderInputPreset>(tester, '分页点击区', '跟随全局');
      await _chooseField<wire.ReaderInputPreset>(tester, '阅读快捷键', '跟随全局');
      final leafBeforeInheritance = _reader(tester).key;
      await _tap(tester, find.text('保存本漫画设置'));
      snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(snapshot!.overrides!.hasFit(), false);
      expect(snapshot.overrides!.hasCropBorders(), false);
      expect(snapshot.effectiveReader.cropBorders, true);
      expect(snapshot.overrides!.hasBackground(), false);
      expect(snapshot.overrides!.hasDimPercent(), false);
      expect(snapshot.overrides!.hasTapZones(), false);
      expect(snapshot.overrides!.hasKeyboard(), false);
      await _closeModal(tester);
      expect(_reader(tester).key, leafBeforeInheritance);
      expect(_reader(tester).fit, ReaderFit.width);
      expect(_reader(tester).cropBorders, true);
      expect(_reader(tester).background, ReaderBackground.white);
      expect(_reader(tester).dimPercent, 40);
      expect(_reader(tester).tapZones, ReaderInputPreset.reversed);
      expect(_reader(tester).keyboard, ReaderInputPreset.disabled);
      await _leaveReader(tester, catalog);
      await _finish(tester, catalog);
    },
  );

  testWidgets(
    'narrow settings retain all submitted preferences across lost ACK and exact retry',
    (tester) async {
      final platform = _platform();
      await _start(tester, platform, size: const Size(480, 800));
      await _globalDefaults(tester);
      var truncateNextAck = true;
      platform.afterBusinessReply = (request, reply) {
        if (truncateNextAck &&
            request.method == 'POST' &&
            request.uri.path == '/api/settings/mutations') {
          truncateNextAck = false;
          return ApiReply(
            status: reply.status,
            headers: reply.headers,
            redirected: reply.redirected,
            body: '{',
          );
        }
        return reply;
      };
      await _tap(tester, find.text('保存全局设置'));
      final writes = platform.businessServer.requests
          .where((request) => request.uri.path == '/api/settings/mutations')
          .toList();
      expect(writes, hasLength(1));
      final original = writes.single.body;
      expect(find.text('设置尚未确认，本会话保留原操作。'), findsOneWidget);
      await _tap(tester, _navigation('浏览'));
      await _tap(tester, _navigation('设置'));
      expect(
        tester
            .widget<DropdownButtonFormField<bool>>(_field<bool>('裁白'))
            .initialValue,
        true,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<bool>>(_field<bool>('裁白'))
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<wire.ReaderFit>>(
              _field<wire.ReaderFit>('图像适配'),
            )
            .initialValue,
        wire.ReaderFit.READER_FIT_WIDTH,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<wire.ReaderBackground>>(
              _field<wire.ReaderBackground>('阅读背景'),
            )
            .initialValue,
        wire.ReaderBackground.READER_BACKGROUND_WHITE,
      );
      expect(
        tester.widget<Slider>(find.byKey(const ValueKey('global-dim'))).value,
        40,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<wire.ReaderInputPreset>>(
              _field<wire.ReaderInputPreset>('分页点击区'),
            )
            .initialValue,
        wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<wire.ReaderInputPreset>>(
              _field<wire.ReaderInputPreset>('阅读快捷键'),
            )
            .initialValue,
        wire.ReaderInputPreset.READER_INPUT_PRESET_DISABLED,
      );
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('global-dim')))
            .onChanged,
        isNull,
      );
      await _tap(tester, find.text('重新读取设置'));
      expect(
        platform.businessServer.requests.where(
          (request) => request.uri.path == '/api/settings/mutations',
        ),
        hasLength(1),
      );
      await _tap(tester, find.text('重试原设置操作'));
      expect(
        platform.businessServer.requests
            .where((request) => request.uri.path == '/api/settings/mutations')
            .map((request) => request.body),
        [original, original],
      );
      expect(platform.businessServer.appliedMutations, 1);
      final catalog = await _details(tester);
      await _tap(tester, find.text('第一章'));
      expect(_reader(tester).fit, ReaderFit.width);
      expect(_reader(tester).cropBorders, true);
      expect(_reader(tester).background, ReaderBackground.white);
      expect(_reader(tester).dimPercent, 40);
      expect(_reader(tester).tapZones, ReaderInputPreset.reversed);
      expect(_reader(tester).keyboard, ReaderInputPreset.disabled);
      await _leaveReader(tester, catalog);
      await _finish(tester, catalog);
    },
  );
}
