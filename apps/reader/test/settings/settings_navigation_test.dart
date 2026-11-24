import 'package:karuyomi/widgets/choice_field.dart';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';

import 'settings_fixture.dart';
import 'settings_probe.dart';
import '../test_app.dart';
import '../../test_support/cupertino.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_page_navigation.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/features/reader/reader_preferences.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:karuyomi/features/settings/reader_device_settings.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:karuyomi/runtime/platform_runtime_native.dart' as native;
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart' show RuntimeException;

import '../browse/fakes.dart';

List<wire.Chapter> get _chapters => [
  wire.Chapter(url: '/one', name: '第一章'),
  wire.Chapter(url: '/two', name: '第二章'),
];

TestPlatform _platform({bool twoPages = false}) =>
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
              if (twoPages)
                wire.Page(
                  pageKey: 'page-two',
                  index: 1,
                  sourceIndex: 1,
                  url: '${call.pages.chapter.url}/page-two',
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
  await openSettingsSection(
    tester,
    T == AppAppearance ? 'appearance' : 'reading',
  );
  await _tap(tester, find.byType(ChoiceField<T>));
  await _tap(tester, find.widgetWithText(CupertinoMenuItem, label));
}

Finder _field<T>(String label) => find.byWidgetPredicate(
  (widget) => widget is ChoiceField<T> && widget.label == label,
);
Future<void> _chooseField<T>(
  WidgetTester tester,
  String field,
  String value,
) async {
  await openSettingsSection(
    tester,
    T == ReaderInputPreset
        ? 'input'
        : T == ReaderBackground
        ? 'appearance'
        : 'reading',
  );
  await _tap(tester, _field<T>(field));
  await _tap(tester, find.widgetWithText(CupertinoMenuItem, value));
}

Finder _navigation(String label) => find.descendant(
  of: find.byKey(const ValueKey('app-navigation')),
  matching: find.text(label),
);
Future<void> _openSettings(WidgetTester tester) async {
  await _tap(tester, _navigation('设置'));
  await openSettingsSection(tester, 'reading');
}

Future<void> _dim(
  WidgetTester tester,
  String scope, {
  required bool zero,
}) async {
  if (scope == 'global') await openSettingsSection(tester, 'appearance');
  final slider = find.byKey(ValueKey('$scope-dim'));
  await tester.ensureVisible(slider);
  await tester.pumpAndSettle();
  final control = tester.widget<CupertinoSlider>(slider);
  final bounds = tester.getRect(slider);
  final inset = bounds.height / 2;
  final track = bounds.width - inset * 2;
  final fraction = (control.value - control.min) / (control.max - control.min);
  final thumb = Offset(
    bounds.left + inset + track * fraction,
    bounds.center.dy,
  );
  final target = zero ? 0.0 : .5;
  if (target == fraction) return;
  final gesture = await tester.startGesture(thumb);
  await gesture.moveBy(Offset(kDragSlopDefault * (target - fraction).sign, 0));
  await tester.pump();
  // Account for movement consumed while the drag recognizer accepts the gesture.
  final started = tester.widget<CupertinoSlider>(slider);
  final current = (started.value - started.min) / (started.max - started.min);
  await gesture.moveBy(Offset(track * (target - current), 0));
  await gesture.up();
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
    ProviderScope(
      key: const ValueKey('reader-device-settings-tests'),
      overrides: [
        readerDeviceStorageProvider.overrideWithValue(TestDevicePreferences()),
      ],
      child: KaruyomiApp(platform: platform, platformFactory: factory),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _globalDefaults(
  WidgetTester tester, {
  bool dark = false,
  VoidCallback? beforeLastChoice,
}) async {
  await _openSettings(tester);
  if (dark) await _choose<AppAppearance>(tester, '深色');
  await _chooseField<ReaderBackground>(tester, '阅读背景', '白色');
  await _dim(tester, 'global', zero: false);
  await _chooseField<ReaderInputPreset>(tester, '分页点击区', '反向');
  await _chooseField<ReaderInputPreset>(tester, '阅读快捷键', '关闭');
  await _choose<wire.ReaderMode>(tester, '横向分页 · 从右到左');
  await _choose<wire.ReaderPageLayout>(tester, '双页');
  await _chooseField<wire.ReaderFit>(tester, '图像适配', '适宽');
  beforeLastChoice?.call();
  await _chooseField<bool>(tester, '裁白', '开启');
}

Future<CatalogController> _details(WidgetTester tester) async {
  await _tap(tester, _navigation('浏览'));
  await _tap(
    tester,
    find.byKey(
      const ValueKey((
        'source-directory-row',
        'eu.kanade.source.test',
        sourceId,
      )),
    ),
  );
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
  await tester.pumpApp(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(catalog.closeReadingProgress);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'service connection reports confirmed, connecting and Access states in $brightness at ${textScale}x',
        (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final platform = TestPlatform(seedDefaultInstallation: false);
          await _start(tester, platform, size: const Size(360, 1100));
          await _tap(tester, _navigation('设置'));
          await openSettingsSection(tester, 'connection');
          expect(find.text('已连接，身份已确认'), findsOneWidget);
          expect(find.text('owner@example.com'), findsOneWidget);
          final connectAction = find.widgetWithText(CupertinoButton, '连接服务');
          final loginAction = find.widgetWithText(CupertinoButton, '登录');
          Tristate enabledState(Finder action) => tester
              .getSemantics(action)
              .getSemanticsData()
              .flagsCollection
              .isEnabled;
          expect(enabledState(connectAction), Tristate.isTrue);
          expect(enabledState(loginAction), Tristate.isTrue);
          final rebuilding = Completer<void>();
          final rebuilt = Completer<void>();
          final bootstrapping = Completer<void>();
          final bootstrapped = Completer<void>();
          addTearDown(() {
            if (!rebuilt.isCompleted) rebuilt.complete();
            if (!bootstrapped.isCompleted) bootstrapped.complete();
          });
          platform.beforeRebuild = () async {
            rebuilding.complete();
            await rebuilt.future;
          };
          platform.beforeApiFetch = (path) async {
            if (path != '/api/bootstrap') return;
            bootstrapping.complete();
            await bootstrapped.future;
          };
          await tester.runAsync(() async {
            await tester.tap(connectAction);
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pump(const Duration(milliseconds: 500));
          await tester.runAsync(
            () => rebuilding.future.timeout(const Duration(seconds: 5)),
          );
          expect(find.text('正在连接服务'), findsOneWidget);
          expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
          expect(find.text('owner@example.com'), findsNothing);
          expect(enabledState(connectAction), Tristate.isFalse);
          expect(enabledState(loginAction), Tristate.isFalse);
          final disabledLogin = tester.widget<CupertinoButton>(loginAction);
          expect(disabledLogin.enabled, isFalse);
          expect(
            disabledLogin.foregroundColor,
            CupertinoColors.tertiaryLabel.resolveFrom(
              tester.element(loginAction),
            ),
          );
          await tester.runAsync(() async {
            platform.beforeRebuild = null;
            rebuilt.complete();
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pump();
          await tester.runAsync(
            () => bootstrapping.future.timeout(const Duration(seconds: 5)),
          );
          expect(find.text('正在连接服务'), findsOneWidget);
          expect(find.text('owner@example.com'), findsNothing);
          expect(enabledState(connectAction), Tristate.isFalse);
          expect(enabledState(loginAction), Tristate.isFalse);
          await tester.runAsync(() async {
            bootstrapped.complete();
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pumpAndSettle();
          platform.beforeRebuild = null;
          platform.beforeApiFetch = null;
          expect(find.text('已连接，身份已确认'), findsOneWidget);
          expect(find.text('owner@example.com'), findsOneWidget);
          expect(enabledState(connectAction), Tristate.isTrue);
          expect(enabledState(loginAction), Tristate.isTrue);
          for (final (status, label) in [
            (401, '需要重新登录'),
            (403, '访问被拒绝'),
            (503, '连接未完成'),
          ]) {
            platform.bootstrapStatus = status;
            await _tap(tester, find.text('连接服务'));
            expect(find.text(label), findsOneWidget);
            expect(find.text('owner@example.com'), findsNothing);
            expect(find.text('已连接，身份已确认'), findsNothing);
            expect(enabledState(connectAction), Tristate.isTrue);
            expect(enabledState(loginAction), Tristate.isTrue);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    for (final size in [const Size(360, 480), const Size(800, 360)]) {
      testWidgets('first connection is reachable at $size in $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 20);
        tester.view.viewPadding = tester.view.padding;
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final platform = TestPlatform(seedDefaultInstallation: false);
        await tester.pumpApp(
          KaruyomiApp(
            platformFactory: (origin) => origin == platform.origin
                ? platform
                : native.createPlatformRuntime(origin: origin),
          ),
        );
        await tester.pumpAndSettle();

        void expectVisible(Finder finder) {
          final viewport = tester.getRect(
            find.byKey(const ValueKey('app-content')),
          );
          expect(finder.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(finder).bottom,
            lessThanOrEqualTo(viewport.bottom),
          );
        }

        final browse = find.widgetWithText(CupertinoButton, '去浏览');
        expectVisible(browse);
        await tester.tap(browse);
        await tester.pumpAndSettle();
        final configure = find.widgetWithText(CupertinoButton, '填写服务地址');
        expectVisible(configure);
        await tester.tap(configure);
        await tester.pumpAndSettle();
        final origin = find.byKey(const ValueKey('service-origin'));
        final connect = find.widgetWithText(CupertinoButton, '连接服务');
        expectVisible(find.text('尚未连接'));
        expectVisible(origin);
        expectVisible(connect);
        expect(tester.widget<CupertinoTextField>(origin).readOnly, isFalse);
        expect(find.widgetWithText(CupertinoButton, '登录'), findsNothing);
        expect(find.text('账号'), findsNothing);
        expect(find.textContaining('请先在设置中填写'), findsNothing);

        await tester.enterText(origin, 'http://reader.example.com');
        await _tap(tester, connect);
        expect(find.textContaining('请先在设置中填写服务的 HTTPS 地址'), findsOneWidget);
        expect(
          tester.widget<CupertinoTextField>(origin).controller!.text,
          'http://reader.example.com',
        );
        expect(platform.businessServer.requests, isEmpty);

        final bootstrapStarted = Completer<void>();
        final releaseBootstrap = Completer<void>();
        addTearDown(() {
          if (!releaseBootstrap.isCompleted) releaseBootstrap.complete();
        });
        platform.beforeApiFetch = (path) async {
          if (path != '/api/bootstrap') return;
          if (!bootstrapStarted.isCompleted) bootstrapStarted.complete();
          await releaseBootstrap.future;
        };
        await tester.enterText(origin, platform.origin.toString());
        await tester.tap(connect.hitTestable());
        await tester.pump();
        await tester.runAsync(
          () => bootstrapStarted.future.timeout(const Duration(seconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 400));

        expectVisible(find.text('正在连接服务'));
        expect(
          find.byType(CupertinoActivityIndicator).hitTestable(),
          findsOneWidget,
        );
        expectVisible(origin);
        expect(
          tester.widget<CupertinoTextField>(origin).controller!.text,
          platform.origin.toString(),
        );
        expect(tester.widget<CupertinoTextField>(origin).readOnly, isTrue);
        expect(tester.widget<CupertinoButton>(connect).enabled, isFalse);
        expect(find.text('owner@example.com'), findsNothing);
        expect(
          find.byKey(const ValueKey('settings-section-connection')),
          findsNothing,
        );

        platform.bootstrapStatus = 403;
        await tester.runAsync(() async {
          releaseBootstrap.complete();
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expectVisible(find.text('访问被拒绝'));
        expectVisible(origin);
        expect(tester.widget<CupertinoTextField>(origin).readOnly, isFalse);
        expect(find.text('owner@example.com'), findsNothing);

        platform.bootstrapStatus = 200;
        platform.beforeApiFetch = null;
        await _tap(tester, connect);
        expectVisible(find.text('已连接，身份已确认'));
        expect(find.text('owner@example.com'), findsOneWidget);
        expect(platform.businessServer.appliedMutations, 0);

        await _tap(tester, _navigation('浏览'));
        await _tap(tester, _navigation('设置'));
        expect(
          find.byKey(const ValueKey('settings-section-connection')),
          findsOneWidget,
        );
        expect(origin, findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets(
    'returning to the foreground reads the confirmed account reading preference',
    (tester) async {
      final platform = TestPlatform(seedDefaultInstallation: false);
      final remotePlatform = TestPlatform(
        businessServer: platform.businessServer,
        seedDefaultInstallation: false,
      );
      final remote = CatalogController(
        api: remotePlatform,
        runtime: remotePlatform.runtime,
        rebuildRuntime: remotePlatform.rebuild,
        deploymentOrigin: remotePlatform.origin,
      );
      addTearDown(() async {
        remote.dispose();
        await remote.closeReadingProgress();
        await remotePlatform.dispose();
      });
      await tester.runAsync(remote.connect);
      await _start(tester, platform);
      await _openSettings(tester);
      final panel = find.byType(GlobalSettingsPanel);
      final catalog = tester.widget<GlobalSettingsPanel>(panel).catalog!;
      final container = ProviderScope.containerOf(
        tester.element(panel),
        listen: false,
      );
      final provider = settingsControllerProvider(catalog, catalog.settings);
      final controller = container.read(provider.notifier);
      expect(container.read(provider).snapshot!.globalRevision, 0);
      expect(
        tester
            .widget<CupertinoApp>(find.byType(CupertinoApp))
            .theme
            ?.brightness,
        null,
      );

      final binding = tester.binding;
      setAppLifecycleState(binding, AppLifecycleState.inactive);
      setAppLifecycleState(binding, AppLifecycleState.hidden);
      await tester.runAsync(() async {
        final repository = remote.settings!;
        final current = await repository.loadGlobal();
        await repository.setGlobal(
          values: current.global.deepCopy()
            ..reader.fit = wire.ReaderFit.READER_FIT_WIDTH,
          basedOnRevision: current.globalRevision,
        );
      });
      await tester.pump();
      expect(container.read(provider).snapshot!.globalRevision, 0);

      setAppLifecycleState(binding, AppLifecycleState.inactive);
      setAppLifecycleState(binding, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        container.read(
          settingsControllerProvider(catalog, catalog.settings).notifier,
        ),
        same(controller),
      );
      expect(container.read(provider).snapshot!.globalRevision, 1);
      expect(
        tester
            .widget<ChoiceField<wire.ReaderFit>>(
              find.byKey(const ValueKey('global-fit')),
            )
            .value,
        wire.ReaderFit.READER_FIT_WIDTH,
      );
      expect(
        tester
            .widget<CupertinoApp>(find.byType(CupertinoApp))
            .theme
            ?.brightness,
        null,
      );
      expect(platform.businessServer.appliedMutations, 1);
      expect(
        platform.businessServer.requests.where(
          (request) => request.uri.path == '/api/settings/mutations',
        ),
        hasLength(1),
      );
      expect(platform.openedBuilds, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final denied in [false, true]) {
    testWidgets(
      'device appearance remains selected across Access ${denied ? 'denial' : 'expiry'} and account change',
      (tester) async {
        final platformBrightness = denied ? Brightness.light : Brightness.dark;
        final confirmedBrightness = denied ? Brightness.dark : Brightness.light;
        tester.platformDispatcher.platformBrightnessTestValue =
            platformBrightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final platform = TestPlatform(seedDefaultInstallation: false);
        await _start(tester, platform, size: const Size(360, 800));
        await _openSettings(tester);
        final settings = find.byType(GlobalSettingsPanel);
        Brightness appearance() =>
            CupertinoTheme.brightnessOf(tester.element(settings));
        expect(appearance(), platformBrightness);
        await _choose<AppAppearance>(tester, denied ? '深色' : '浅色');
        await openSettingsSection(tester, 'reading');
        expect(appearance(), confirmedBrightness);

        platform.afterBusinessReply = (request, reply) {
          if (request.method == 'GET' && request.uri.path == '/api/settings') {
            throw RuntimeException.fromProto(
              wire.RuntimeError(
                code: denied
                    ? wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_DENIED
                    : wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_REQUIRED,
                message: 'Settings identity is unavailable',
              ),
            );
          }
          return reply;
        };
        await _tap(tester, find.text('重新读取设置'));
        expect(
          find.text(denied ? '当前身份没有访问权限' : '访问验证已失效，请重新登录'),
          findsOneWidget,
        );
        await openSettingsSection(tester, 'appearance');
        expect(find.byKey(const ValueKey('device-theme')), findsOneWidget);
        expect(appearance(), confirmedBrightness);

        platform.bootstrapSubject = 'other-subject';
        await openSettingsSection(tester, 'connection');
        await _tap(tester, find.text('连接服务'));
        expect(find.text(denied ? '访问被拒绝' : '需要重新登录'), findsOneWidget);
        expect(appearance(), confirmedBrightness);

        platform.afterBusinessReply = null;
        await _tap(tester, find.text('连接服务'));
        expect(find.text('已连接，身份已确认'), findsOneWidget);
        expect(appearance(), confirmedBrightness);
        expect(platform.businessServer.appliedMutations, 0);
        expect(platform.openedBuilds, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'zero-Source settings Access ${denied ? 'denial' : 'expiry'} exposes login recovery and retains the exact pending command',
      (tester) async {
        final platform = TestPlatform(seedDefaultInstallation: false);
        await _start(tester, platform);
        await _openSettings(tester);
        final initial = globalSettings(tester);
        platform.afterBusinessReply = (request, reply) {
          if (request.method != 'POST' ||
              request.uri.path != '/api/settings/mutations') {
            return reply;
          }
          platform.afterBusinessReply = null;
          // The host's generated Access control error arrives after the
          // supplier applied this write; only an exact retry can confirm it.
          throw RuntimeException.fromProto(
            wire.RuntimeError(
              code: denied
                  ? wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_DENIED
                  : wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_REQUIRED,
              message: 'Private API Access decision',
            ),
          );
        };
        await _choose<wire.ReaderFit>(tester, '适宽');
        final originalRequest = platform.businessServer.requests
            .where((request) => request.uri.path == '/api/settings/mutations')
            .single;
        expect(initial.state.pending, isNotNull);
        expect(initial.state.available, false);
        expect(initial.state.canRetry, false);
        expect(
          find.text(denied ? '当前身份没有访问权限' : '访问验证已失效，请重新登录'),
          findsOneWidget,
        );
        expect(platform.businessServer.appliedMutations, 1);
        expect(platform.openedBuilds, isEmpty);
        await openSettingsSection(tester, 'connection');
        expect(find.text(denied ? '访问被拒绝' : '需要重新登录'), findsOneWidget);
        expect(
          tester
              .widget<GlobalSettingsPanel>(find.byType(GlobalSettingsPanel))
              .catalog!
              .email,
          'owner@example.com',
        );
        expect(find.text('owner@example.com'), findsNothing);
        await _tap(tester, find.text('登录'));
        expect(find.text('已连接，身份已确认'), findsOneWidget);
        expect(find.text('owner@example.com'), findsOneWidget);
        final recovered = globalSettings(tester);
        expect(platform.authCalls, 1);
        expect(recovered.repository.client, same(initial.repository.client));
        expect(recovered.state.pending, isNotNull);
        expect(recovered.state.canRetry, true);
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
          [originalRequest.body, originalRequest.body],
        );
        expect(platform.businessServer.appliedMutations, 1);
        expect(recovered.state.pending, isNull);
        expect(
          recovered.state.snapshot!.global.reader.fit,
          wire.ReaderFit.READER_FIT_WIDTH,
        );
        expect(platform.openedBuilds, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

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
        await _openSettings(tester);
        final initial = globalSettings(tester);
        final originalRevision = initial.state.snapshot!.globalRevision;
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
        await _choose<wire.ReaderFit>(tester, '适宽');
        final originalRequest = platform.businessServer.requests
            .where((request) => request.uri.path == '/api/settings/mutations')
            .single;
        final originalMutation = wire.decodeProtoJson(
          wire.SettingsMutation(),
          jsonDecode(originalRequest.body!),
        );
        expect(originalMutation.mutationId, isNotEmpty);
        expect(originalMutation.expectedRevision, originalRevision);
        expect(
          originalMutation.setGlobal.reader.fit,
          wire.ReaderFit.READER_FIT_WIDTH,
        );
        expect(initial.state.pending, isNotNull);
        expect(platform.businessServer.appliedMutations, 1);
        expect(platform.openedBuilds, isEmpty);
        await openSettingsSection(tester, 'connection');
        await tester.enterText(
          find.byType(CupertinoTextField),
          '${platform.origin.origin}${trailingSlash ? '/' : ''}',
        );
        await _tap(tester, find.text('连接服务'));
        final reconnected = globalSettings(tester);
        expect(reconnected.state.pending, isNotNull);
        expect(reconnected.state.pending!.basedOnRevision, originalRevision);
        expect(
          reconnected.state.pending!.global!.reader.fit,
          wire.ReaderFit.READER_FIT_WIDTH,
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
        expect(reconnected.state.pending, isNull);
        expect(find.text('重试原设置操作'), findsNothing);
        expect(
          reconnected.state.snapshot!.global.reader.fit,
          wire.ReaderFit.READER_FIT_WIDTH,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
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
        await _openSettings(tester);
        final initial = globalSettings(tester);
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
        await _choose<wire.ReaderFit>(tester, '适宽');
        final originalRequest = platform.businessServer.requests
            .where((request) => request.uri.path == '/api/settings/mutations')
            .single;
        final pending = initial.state.pending;
        expect(pending, isNotNull);
        await openSettingsSection(tester, 'connection');
        await tester.enterText(find.byType(CupertinoTextField), invalidOrigin);
        await _tap(tester, find.text('连接服务'));
        expect(find.byType(GlobalSettingsPanel), findsOneWidget);
        final rejected = globalSettings(tester);
        expect(rejected.commands, same(initial.commands));
        expect(rejected.state.pending, isNotNull);
        expect(
          rejected.state.pending!.basedOnRevision,
          pending!.basedOnRevision,
        );
        expect(rejected.state.pending!.global, pending.global);
        expect(rejected.state.pending!.retryable, pending.retryable);
        expect(rejected.state.available, true);
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
        await openSettingsSection(tester, 'connection');
        await tester.enterText(
          find.byType(CupertinoTextField),
          platform.origin.toString(),
        );
        await _tap(tester, find.text('连接服务'));
        final reconnected = globalSettings(tester);
        expect(reconnected.state.pending, isNotNull);
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
        expect(reconnected.state.pending, isNull);
        expect(platform.openedBuilds, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
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
        await _openSettings(tester);
        final previous = globalSettings(tester);
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
        await _choose<wire.ReaderFit>(tester, '适宽');
        final oldRequest = original.businessServer.requests
            .where((request) => request.uri.path == '/api/settings/mutations')
            .single;
        final oldMutation = wire.decodeProtoJson(
          wire.SettingsMutation(),
          jsonDecode(oldRequest.body!),
        );
        expect(previous.state.pending, isNotNull);
        if (!changeOrigin) {
          original.bootstrapSubject = replacement.bootstrapSubject;
        }
        await openSettingsSection(tester, 'connection');
        await tester.enterText(
          find.byType(CupertinoTextField),
          replacement.origin.toString(),
        );
        await _tap(tester, find.text('连接服务'));
        final current = globalSettings(tester);
        expect(current.repository.identity.origin, replacement.origin);
        expect(
          current.repository.identity.subject,
          replacement.bootstrapSubject,
        );
        expect(current.state.pending, isNull);
        expect(
          current.state.snapshot!.global.reader.fit,
          wire.ReaderFit.READER_FIT_CONTAIN,
        );
        expect(previous.state.available, false);
        expect(previous.state.canRetry, false);
        expect(await tester.runAsync(previous.commands.retry), false);
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
        await _choose<wire.ReaderFit>(tester, '适高');
        final newRequest = replacement.businessServer.requests
            .where((request) => request.uri.path == '/api/settings/mutations')
            .last;
        final newMutation = wire.decodeProtoJson(
          wire.SettingsMutation(),
          jsonDecode(newRequest.body!),
        );
        expect(newMutation.mutationId, isNot(oldMutation.mutationId));
        expect(newMutation.expectedRevision, 0);
        expect(
          newMutation.setGlobal.reader.fit,
          wire.ReaderFit.READER_FIT_HEIGHT,
        );
        expect(
          newRequest.headers['X-App-Subject'],
          replacement.bootstrapSubject,
        );
        expect(current.state.pending, isNull);
        expect(
          current.state.snapshot!.global.reader.fit,
          wire.ReaderFit.READER_FIT_HEIGHT,
        );
        expect(original.businessServer.appliedMutations, changeOrigin ? 1 : 2);
        if (changeOrigin) {
          expect(replacement.businessServer.appliedMutations, 1);
        }
        expect(original.openedBuilds, isEmpty);
        expect(replacement.openedBuilds, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'the saved device appearance and account defaults apply to a manga',
    (tester) async {
      final platform = _platform();
      await _start(tester, platform);
      await _globalDefaults(tester, dark: true);
      expect(
        tester
            .widget<CupertinoApp>(find.byType(CupertinoApp))
            .theme
            ?.brightness,
        Brightness.dark,
      );
      expect(
        platform.businessServer.requests.where(
          (request) => request.uri.path == '/api/settings/mutations',
        ),
        hasLength(4),
      );
      final catalog = await _details(tester);
      final inherited = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(inherited!.overrides!.hasMode(), false);
      expect(inherited.overrides!.hasPageLayout(), false);
      expect(inherited.overrides!.hasFit(), false);
      expect(inherited.overrides!.hasCropBorders(), false);
      expect(inherited.effectiveReader.cropBorders, true);
      expect(inherited.effectiveReader.fit, wire.ReaderFit.READER_FIT_WIDTH);
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
            .widget<ChoiceField<ReadingMode>>(
              find.byType(ChoiceField<ReadingMode>),
            )
            .value,
        ReadingMode.rightToLeft,
      );
      expect(
        tester.widget<ChoiceField<bool>>(find.byType(ChoiceField<bool>)).value,
        true,
      );
      await _leaveReader(tester, catalog);
      await _finish(tester, catalog);
    },
  );

  for (final appearance in Brightness.values) {
    testWidgets(
      'short reader quick settings keep the confirmed layout while saving or retrying in $appearance',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = appearance;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final platform = _platform(twoPages: true);
        await _start(tester, platform, size: const Size(480, 900));
        final catalog = await _details(tester);
        await _tap(tester, find.text('第一章'));
        tester.view.physicalSize = const Size(360, 480);
        await tester.pumpAndSettle();
        final slider = find.byType(CupertinoSlider);
        expect(
          tester.getSize(slider).width,
          greaterThanOrEqualTo(3 * kMinInteractiveDimensionCupertino),
          reason: 'the short reader still needs a usable drag and tap range',
        );
        final mode = find.byType(ChoiceField<ReadingMode>);
        final layout = find.byKey(const ValueKey('reader-page-layout'));
        ReaderPageNavigation pager() => tester.widget<ReaderPageNavigation>(
          find.byType(ReaderPageNavigation),
        );
        final originalMode = tester
            .widget<ChoiceField<ReadingMode>>(mode)
            .value;
        expect(originalMode, ReadingMode.leftToRight);
        expect(tester.widget<ChoiceField<bool>>(layout).value, isNull);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ReaderScreen)),
          listen: false,
        );
        final provider = settingsControllerProvider(
          catalog,
          catalog.settings,
          mangaKey: _mangaKey,
        );
        final originalRevision = container
            .read(provider)
            .snapshot!
            .mangaRevision;
        final entered = Completer<void>(), release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        platform.afterBusinessReply = (request, reply) async {
          if (!release.isCompleted &&
              request.method == 'POST' &&
              request.uri.path == '/api/settings/mutations') {
            entered.complete();
            await release.future;
          }
          return reply;
        };
        await _tap(tester, mode);
        await tester.runAsync(() async {
          await tester.tap(
            find.widgetWithText(CupertinoMenuItem, '横向分页 · 从右到左'),
          );
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(
          () => entered.future.timeout(const Duration(seconds: 5)),
        );
        expect(
          find
              .byKey(const ValueKey(('settings-activity', 'saving')))
              .hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.widget<ChoiceField<ReadingMode>>(mode).value,
          originalMode,
        );
        expect(_reader(tester).initialMode, originalMode);
        expect(pager().direction, TextDirection.ltr);
        expect(
          find.byKey(const ValueKey(('settings-activity', 'reading'))),
          findsNothing,
        );
        expect(
          container.read(provider).snapshot!.mangaRevision,
          originalRevision,
        );
        expect(container.read(provider).snapshot!.overrides!.hasMode(), false);
        expect(
          tester
              .widget<ChoiceField<ReadingMode>>(
                find.byType(ChoiceField<ReadingMode>),
              )
              .onChanged,
          isNull,
        );
        tester.view.physicalSize = const Size(844, 390);
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          find
              .byKey(const ValueKey(('settings-activity', 'saving')))
              .hitTestable(),
          findsOneWidget,
        );
        final nextPage = iconLabel('下一页');
        expect(nextPage.hitTestable(), findsOneWidget);
        await tester.tap(nextPage);
        await tester.pump(const Duration(milliseconds: 250));
        expect(pager().pageIndex, 1);
        expect(pager().direction, TextDirection.ltr);
        tester.view.physicalSize = const Size(360, 480);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.runAsync(() async {
          release.complete();
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey(('settings-activity', 'saving'))),
          findsNothing,
        );
        expect(
          container.read(provider).snapshot!.mangaRevision,
          originalRevision! + 1,
        );
        expect(
          container.read(provider).snapshot!.overrides!.mode,
          wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
        );
        expect(
          tester.widget<ChoiceField<ReadingMode>>(mode).value,
          ReadingMode.rightToLeft,
        );
        expect(pager().pageIndex, 1);
        expect(pager().direction, TextDirection.rtl);
        final writes = platform.businessServer.requests.where(
          (request) =>
              request.method == 'POST' &&
              request.uri.path == '/api/settings/mutations',
        );
        expect(writes, hasLength(1));

        var dropReply = true;
        platform.afterBusinessReply = (request, reply) {
          if (dropReply &&
              request.method == 'POST' &&
              request.uri.path == '/api/settings/mutations') {
            dropReply = false;
            return ApiReply(
              status: reply.status,
              headers: reply.headers,
              body: '{',
              redirected: reply.redirected,
            );
          }
          return reply;
        };
        await _tap(tester, layout);
        await _tap(tester, find.widgetWithText(CupertinoMenuItem, '双页'));
        final unconfirmed = find.text('设置尚未确认，本会话保留原操作。');
        expect(unconfirmed.hitTestable(), findsOneWidget);
        expect(
          tester.getTopLeft(unconfirmed).dy,
          lessThan(tester.getTopLeft(find.byType(ReaderPageNavigation)).dy),
        );
        expect(tester.widget<ChoiceField<bool>>(layout).value, isNull);
        expect(_reader(tester).doublePage, isNull);
        expect(
          container.read(provider).snapshot!.mangaRevision,
          originalRevision + 1,
        );
        expect(writes, hasLength(2));
        final originalWrite = writes.last.body;

        final retry = find.widgetWithText(CupertinoButton, '重试原设置操作');
        expect(retry.hitTestable(), findsOneWidget);
        await _tap(tester, retry);
        expect(writes, hasLength(3));
        expect(writes.last.body, originalWrite);
        expect(tester.widget<ChoiceField<bool>>(layout).value, true);
        expect(
          container.read(provider).snapshot!.mangaRevision,
          originalRevision + 2,
        );
        expect(find.text('设置尚未确认，本会话保留原操作。'), findsNothing);
        await _leaveReader(tester, catalog);
        await _finish(tester, catalog);
      },
    );
  }

  testWidgets(
    'reader choices save manga overrides, modal inheritance is per field, and AUTO survives chapter replacement and reopening',
    (tester) async {
      final platform = _platform();
      await _start(tester, platform);
      await _globalDefaults(tester);
      final catalog = await _details(tester);
      await _tap(tester, find.text('第一章'));
      final leafBeforeFit = _reader(tester).key;
      await _tap(tester, iconButton('阅读设置'));
      expect(
        find.descendant(
          of: find.byType(MangaSettingsEditor),
          matching: find.text(testManga.title),
        ),
        findsOneWidget,
      );
      expect(find.text('zh · 测试漫画源'), findsOneWidget);
      await _tap(tester, find.text('关闭'));
      expect(find.byType(MangaSettingsEditor), findsNothing);
      final untouched = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(untouched!.overrides!.hasFit(), false);
      expect(_reader(tester).key, leafBeforeFit);
      await _tap(tester, iconButton('阅读设置'));
      await _chooseField<wire.ReaderFit>(tester, '图像适配', '适高');
      await _chooseField<bool>(tester, '裁白', '关闭');
      await _closeModal(tester);
      expect(_reader(tester).key, leafBeforeFit);
      expect(_reader(tester).fit, ReaderFit.height);
      expect(_reader(tester).cropBorders, false);
      await _tap(tester, find.byKey(const ValueKey('reader-chapter-options')));
      await _tap(tester, find.text('重新阅读本章'));
      final reset = _reader(tester).positionRequest!.value!;
      expect(reset.normalizedOffset, 0);
      expect(reset.normalizedX, 1);
      expect(reset.viewportX, 1);
      expect(reset.viewportY, 0);
      expect(_reader(tester).key, leafBeforeFit);
      await _tap(tester, find.byType(ChoiceField<ReadingMode>));
      await _tap(tester, find.text('横向分页 · 从左到右').last);
      await _tap(tester, find.byType(ChoiceField<bool>));
      await _tap(tester, find.widgetWithText(CupertinoMenuItem, '单页'));
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
      await _tap(tester, iconButton('阅读设置'));
      expect(find.byType(MangaSettingsEditor), findsOneWidget);
      final leafBeforeAppearance = _reader(tester).key;
      await _chooseField<wire.ReaderFit>(tester, '图像适配', '完整显示');
      final beforeDeviceEdit = platform.businessServer.requests
          .where((request) => request.uri.path == '/api/settings/mutations')
          .length;
      await _chooseField<ReaderBackground>(tester, '阅读背景', '黑色');
      await _tap(tester, find.byKey(const ValueKey('manga-dim-inherit')));
      await _dim(tester, 'manga', zero: true);
      await _chooseField<ReaderInputPreset>(tester, '分页点击区', '标准');
      await _chooseField<ReaderInputPreset>(tester, '阅读快捷键', '反向');
      expect(
        platform.businessServer.requests.where(
          (request) => request.uri.path == '/api/settings/mutations',
        ),
        hasLength(beforeDeviceEdit),
      );
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
      await _choose<wire.ReaderMode>(tester, '跟随全局');
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
      await _tap(tester, iconButton('阅读设置'));
      await _choose<wire.ReaderPageLayout>(tester, '跟随全局');
      snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(snapshot!.overrides!.hasMode(), false);
      expect(snapshot.overrides!.hasPageLayout(), false);
      await _closeModal(tester);
      expect(_reader(tester).doublePage, true);
      await _tap(tester, find.byType(ChoiceField<bool>));
      await _tap(tester, find.widgetWithText(CupertinoMenuItem, '自动'));
      snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(snapshot!.overrides!.hasPageLayout(), true);
      expect(snapshot.overrides!.hasFit(), true);
      expect(snapshot.overrides!.fit, wire.ReaderFit.READER_FIT_CONTAIN);
      expect(snapshot.overrides!.hasCropBorders(), true);
      expect(snapshot.overrides!.cropBorders, false);
      expect(
        snapshot.overrides!.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      );
      expect(_reader(tester).doublePage, isNull);
      expect(
        tester.widget<ChoiceField<bool>>(find.byType(ChoiceField<bool>)).value,
        isNull,
      );
      final writes = platform.businessServer.requests
          .where((request) => request.uri.path == '/api/settings/mutations')
          .length;
      final firstLeaf = _reader(tester).key;
      await tester.ensureVisible(iconButton('下一章'));
      await tester.runAsync(() async {
        await tester.tap(iconButton('下一章'));
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
        tester.widget<ChoiceField<bool>>(find.byType(ChoiceField<bool>)).value,
        isNull,
      );
      await _leaveReader(tester, catalog);
      await _tap(tester, find.text('第一章'));
      expect(_reader(tester).fit, ReaderFit.contain);
      expect(_reader(tester).cropBorders, false);
      expect(_reader(tester).doublePage, isNull);
      expect(
        tester.widget<ChoiceField<bool>>(find.byType(ChoiceField<bool>)).value,
        isNull,
      );
      expect(
        platform.businessServer.requests.where(
          (request) => request.uri.path == '/api/settings/mutations',
        ),
        hasLength(writes),
      );
      await _tap(tester, iconButton('阅读设置'));
      final leafBeforeInheritance = _reader(tester).key;
      await _chooseField<wire.ReaderFit>(tester, '图像适配', '跟随全局');
      await _chooseField<bool>(tester, '裁白', '跟随全局');
      await _chooseField<ReaderBackground>(tester, '阅读背景', '跟随本机默认');
      await _tap(tester, find.byKey(const ValueKey('manga-dim-inherit')));
      await _chooseField<ReaderInputPreset>(tester, '分页点击区', '跟随本机默认');
      await _chooseField<ReaderInputPreset>(tester, '阅读快捷键', '跟随本机默认');
      snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(snapshot!.overrides!.hasFit(), false);
      expect(snapshot.overrides!.hasCropBorders(), false);
      expect(snapshot.effectiveReader.cropBorders, true);
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
      int? priorWrites;
      int? priorApplied;
      var truncateNextAck = false;
      final server = platform.businessServer;
      List<String?> writes() => server.requests
          .where((request) => request.uri.path == '/api/settings/mutations')
          .map((request) => request.body)
          .toList();
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
      await _globalDefaults(
        tester,
        beforeLastChoice: () {
          priorWrites = writes().length;
          priorApplied = server.appliedMutations;
          truncateNextAck = true;
        },
      );
      expect(writes(), hasLength(priorWrites! + 1));
      final original = writes().last;
      expect(find.text('设置尚未确认，本会话保留原操作。'), findsOneWidget);
      await _tap(tester, _navigation('浏览'));
      await _openSettings(tester);
      await openSettingsSection(tester, 'reading');
      expect(tester.widget<ChoiceField<bool>>(_field<bool>('裁白')).value, true);
      expect(
        tester.widget<ChoiceField<bool>>(_field<bool>('裁白')).onChanged,
        isNull,
      );
      expect(
        tester
            .widget<ChoiceField<wire.ReaderFit>>(_field<wire.ReaderFit>('图像适配'))
            .value,
        wire.ReaderFit.READER_FIT_WIDTH,
      );
      await openSettingsSection(tester, 'appearance');
      expect(
        tester
            .widget<ChoiceField<ReaderBackground>>(
              _field<ReaderBackground>('阅读背景'),
            )
            .value,
        ReaderBackground.white,
      );
      expect(
        tester
            .widget<CupertinoSlider>(find.byKey(const ValueKey('global-dim')))
            .value,
        40,
      );
      expect(
        tester
            .widget<CupertinoSlider>(find.byKey(const ValueKey('global-dim')))
            .onChanged,
        isNotNull,
      );
      await openSettingsSection(tester, 'input');
      expect(
        tester
            .widget<ChoiceField<ReaderInputPreset>>(
              _field<ReaderInputPreset>('分页点击区'),
            )
            .value,
        ReaderInputPreset.reversed,
      );
      expect(
        tester
            .widget<ChoiceField<ReaderInputPreset>>(
              _field<ReaderInputPreset>('阅读快捷键'),
            )
            .value,
        ReaderInputPreset.disabled,
      );
      await openSettingsSection(tester, 'reading');
      await _tap(tester, find.text('重新读取设置'));
      expect(writes(), hasLength(priorWrites! + 1));
      await _tap(tester, find.text('重试原设置操作'));
      expect(writes().skip(priorWrites!), [original, original]);
      expect(server.appliedMutations, priorApplied! + 1);
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
