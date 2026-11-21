import 'package:karuyomi/widgets/choice_field.dart';

import '../test_app.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:karuyomi/widgets/app_routes.dart';
import 'package:karuyomi/widgets/edit_sheet.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/business_state_server.dart';
import 'settings_fixture.dart';
import 'settings_probe.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _target = MangaEditContext(
  title: '同名作品在书架和阅读设置中需要保留完整的标题与漫画源',
  sourceName: '测试漫画源',
  sourceLang: 'zh',
);
wire.GlobalSettingsValues _global({
  wire.ReaderFit fit = wire.ReaderFit.READER_FIT_WIDTH,
  wire.ReaderPageLayout layout = wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
}) => wire.GlobalSettingsValues(
  reader: wire.ReaderSettings(
    mode: wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
    pageLayout: layout,
    fit: fit,
  ),
);

void main() {
  late TestBusinessServer server;
  late BusinessStateClient client;
  late SettingsRepository repository;
  late SettingsFixture fixture;

  setUp(() async {
    fixture = SettingsFixture();
    await fixture.connect();
    server = fixture.platform.businessServer;
    repository = fixture.catalog.settings!;
    client = repository.client;
  });
  tearDown(() => fixture.dispose());
  SettingsController editor({bool manga = false}) =>
      fixture.editor(mangaKey: manga ? _key : null);
  SettingsState state({bool manga = false}) =>
      fixture.state(mangaKey: manga ? _key : null);

  Future<void> show(
    WidgetTester tester,
    SettingsController controller, {
    bool manga = false,
    Brightness? appearance,
    bool reduceMotion = false,
    bool disableAnimations = false,
    bool openReading = true,
    bool settle = true,
    double textScale = 1,
    Size size = const Size(480, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpApp(
      CupertinoApp(
        theme: appearance == null ? null : readerAppTheme(appearance),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            reduceMotion: reduceMotion,
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: manga
            ? MangaSettingsEditor(
                catalog: fixture.catalog,
                mangaKey: _key,
                target: _target,
              )
            : GlobalSettingsPanel(catalog: fixture.catalog),
      ),
      container: fixture.container,
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    if (!manga && openReading) {
      await openSettingsSection(tester, 'reading');
    }
  }

  Future<void> hide(WidgetTester tester) async {
    await tester.pumpApp(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> tap(
    WidgetTester tester,
    Finder finder, {
    bool settle = true,
  }) async {
    await tester.ensureVisible(finder);
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(Duration.zero);
    });
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> select<T>(
    WidgetTester tester,
    String label, {
    bool settle = true,
  }) async {
    await tap(tester, find.byType(ChoiceField<T>));
    await tap(
      tester,
      find.widgetWithText(CupertinoMenuItem, label),
      settle: settle,
    );
  }

  List<TestBusinessRequest> writes() =>
      server.requests.where((request) => request.method == 'POST').toList();

  for (final appearance in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'manga settings can close during a read without a late navigation or write in $appearance at ${scale}x text',
        (tester) async {
          final reading = Completer<void>();
          final releaseRead = Completer<void>();
          addTearDown(() {
            if (!releaseRead.isCompleted) releaseRead.complete();
          });
          server.beforeRequest = (request) async {
            if (request.method == 'GET' &&
                request.uri.path == '/api/settings/manga/$_key' &&
                !releaseRead.isCompleted) {
              reading.complete();
              await releaseRead.future;
            }
            return null;
          };
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpApp(
            CupertinoApp(
              theme: readerAppTheme(appearance),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => CupertinoPageScaffold(
                  child: Center(
                    child: CupertinoButton(
                      onPressed: () => Navigator.of(context).push<void>(
                        AppPageRoute<void>(
                          builder: (_) => MangaSettingsEditor(
                            catalog: fixture.catalog,
                            mangaKey: _key,
                            target: _target,
                          ),
                        ),
                      ),
                      child: const Text('打开漫画设置'),
                    ),
                  ),
                ),
              ),
            ),
            container: fixture.container,
          );
          await tester.tap(find.text('打开漫画设置'));
          await tester.pump();
          await tester.runAsync(() => reading.future);
          await tester.pump(const Duration(milliseconds: 600));
          expect(find.text('正在读取服务端设置').hitTestable(), findsOneWidget);
          final pop = find.descendant(
            of: find.byType(MangaSettingsEditor),
            matching: find.byType(PopScope),
          );
          expect(tester.widget<PopScope>(pop).canPop, true);
          await tester.tap(find.text('关闭'));
          await tester.pumpAndSettle();
          expect(find.byType(MangaSettingsEditor), findsNothing);
          expect(find.text('打开漫画设置').hitTestable(), findsOneWidget);
          releaseRead.complete();
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(find.byType(MangaSettingsEditor), findsNothing);
          expect(writes(), isEmpty);
          expect(server.appliedMutations, 0);
          expect(tester.takeException(), isNull);
          await hide(tester);
        },
      );

      testWidgets(
        'manga settings distinguish reading, saving and recovery in $appearance at ${scale}x text',
        (tester) async {
          final initialRead = Completer<void>();
          final saving = Completer<void>();
          final releaseSave = Completer<void>();
          Completer<void>? reloadGate;
          addTearDown(() {
            if (!initialRead.isCompleted) initialRead.complete();
            if (!releaseSave.isCompleted) releaseSave.complete();
            if (reloadGate case final gate? when !gate.isCompleted) {
              gate.complete();
            }
          });
          final refresh = find.widgetWithText(CupertinoButton, '重新读取设置');
          final retry = find.widgetWithText(CupertinoButton, '重试原设置操作');
          Tristate enabled(Finder action) => tester
              .getSemantics(action)
              .getSemanticsData()
              .flagsCollection
              .isEnabled;
          var failRead = true;
          server.beforeRequest = (request) async {
            if (request.method == 'GET' &&
                request.uri.path == '/api/settings/manga/$_key') {
              if (!initialRead.isCompleted) await initialRead.future;
              if (reloadGate case final gate?) await gate.future;
              if (failRead) throw StateError('Settings read unavailable');
            }
            return null;
          };
          var holdSave = true;
          fixture.platform.afterBusinessReply = (request, reply) async {
            if (holdSave &&
                request.method == 'POST' &&
                request.uri.path == '/api/settings/mutations') {
              saving.complete();
              await releaseSave.future;
              throw StateError('Settings acknowledgement lost');
            }
            return reply;
          };
          final controller = editor(manga: true);
          await show(
            tester,
            controller,
            manga: true,
            appearance: appearance,
            textScale: scale,
            size: const Size(360, 800),
            settle: false,
          );
          expect(find.text('正在读取服务端设置'), findsOneWidget);
          expect(find.text('连接并确认身份后可读取和保存同步设置。'), findsNothing);
          expect(find.text('当前设置已获服务端确认。'), findsNothing);
          expect(find.byType(ChoiceField<wire.ReaderMode>), findsNothing);
          expect(enabled(refresh), Tristate.isFalse);
          expect(writes(), isEmpty);

          initialRead.complete();
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(find.text('未能读取服务端设置；当前阅读仍可继续。'), findsOneWidget);
          expect(find.text('正在读取服务端设置'), findsNothing);
          expect(find.text('当前设置已获服务端确认。'), findsNothing);
          expect(enabled(refresh), Tristate.isTrue);
          failRead = false;
          await tap(tester, find.text('重新读取设置'));
          expect(find.text('当前设置已获服务端确认。'), findsOneWidget);
          expect(find.text('当前设置已获服务端确认。').hitTestable(), findsOneWidget);
          expect(find.text(_target.title).hitTestable(), findsOneWidget);
          expect(find.text('zh · 测试漫画源').hitTestable(), findsOneWidget);
          final inheritance = find.text('选择“跟随全局”时，之后的账户默认值会应用到此漫画。');
          expect(
            find.ancestor(
              of: inheritance,
              matching: find.byType(CupertinoFormSection),
            ),
            findsOneWidget,
          );
          await select<wire.ReaderMode>(tester, '从右到左', settle: false);
          await tester.runAsync(() => saving.future);
          await tester.pump();
          expect(find.text('正在等待服务端确认设置修改'), findsOneWidget);
          expect(find.text('正在等待服务端确认设置修改').hitTestable(), findsOneWidget);
          expect(find.text('正在读取服务端设置'), findsNothing);
          expect(find.text('有修改等待发送。'), findsNothing);
          expect(find.text('当前设置已获服务端确认。'), findsNothing);
          expect(
            enabled(find.widgetWithText(CupertinoButton, '关闭')),
            Tristate.isTrue,
          );
          expect(state(manga: true).canEdit, false);
          expect(state(manga: true).canChange, true);
          expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, true);
          releaseSave.complete();
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(find.text('设置尚未确认，本会话保留原操作。'), findsOneWidget);
          expect(find.text('设置尚未确认，本会话保留原操作。').hitTestable(), findsOneWidget);
          expect(find.text('当前设置已获服务端确认。'), findsNothing);
          expect(enabled(retry), Tristate.isTrue);
          expect(writes(), hasLength(1));
          final original = writes().single.body;
          failRead = true;
          await tap(tester, find.text('重新读取设置'));
          expect(find.text('未能读取服务端设置；当前阅读仍可继续。'), findsOneWidget);
          expect(find.text('设置尚未确认，本会话保留原操作。'), findsOneWidget);
          expect(state(manga: true).pending?.retryable, true);
          expect(writes(), hasLength(1));

          holdSave = false;
          failRead = false;
          await tap(tester, find.text('重试原设置操作'));
          expect(writes().map((request) => request.body), [original, original]);
          expect(server.appliedMutations, 1);
          expect(state(manga: true).pending, isNull);
          expect(
            state(manga: true).snapshot!.overrides!.mode,
            wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
          );
          expect(find.text('当前设置已获服务端确认。'), findsOneWidget);

          reloadGate = Completer<void>();
          await tester.ensureVisible(find.text('重新读取设置'));
          await tester.tap(find.text('重新读取设置'));
          await tester.pump();
          expect(find.text('正在读取服务端设置'), findsOneWidget);
          expect(find.text('有修改等待发送。'), findsNothing);
          expect(find.text('正在读取服务端设置').hitTestable(), findsOneWidget);
          expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, true);
          expect(find.text('正在等待服务端确认设置修改'), findsNothing);
          expect(writes(), hasLength(2));
          reloadGate.complete();
          reloadGate = null;
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(
            state(manga: true).snapshot!.overrides!.mode,
            wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
          );
          expect(writes(), hasLength(2));
          final remoteClient = BusinessStateClient(
            api: server,
            identity: client.identity,
          );
          addTearDown(remoteClient.dispose);
          await tester.runAsync(
            () => SettingsRepository(remoteClient).setManga(
              mangaKey: _key,
              overrides: wire.ReaderSettingsOverride(
                pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
              ),
              basedOnRevision: 1,
            ),
          );
          await select<wire.ReaderMode>(tester, '竖向连续');
          expect(find.text('设置已在其他设备修改，请重新读取后确认。'), findsOneWidget);
          expect(find.text('重试原设置操作'), findsNothing);
          expect(state(manga: true).canEdit, false);
          final writesBeforeRead = writes().length;
          await tap(tester, find.text('重新读取设置'));
          expect(writes(), hasLength(writesBeforeRead));
          expect(
            state(manga: true).snapshot!.overrides!.pageLayout,
            wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
          );
          expect(state(manga: true).snapshot!.overrides!.hasMode(), false);

          fixture.platform.loginHtml = true;
          await tester.runAsync(fixture.catalog.connect);
          await tester.pumpAndSettle();
          expect(find.text('连接并确认身份后可读取和保存同步设置。'), findsOneWidget);
          expect(find.byType(ChoiceField<wire.ReaderMode>), findsNothing);
          expect(find.text('当前设置已获服务端确认。'), findsNothing);
          expect(enabled(refresh), Tristate.isFalse);
          expect(writes(), hasLength(writesBeforeRead));
          expect(tester.takeException(), isNull);
          await hide(tester);
        },
      );
    }
  }

  for (final disabled in [false, true]) {
    testWidgets(
      'settings detail respects reduced motion and system back (disabled: $disabled)',
      (tester) async {
        final controller = editor();
        await tester.runAsync(controller.refresh);
        await show(
          tester,
          controller,
          reduceMotion: true,
          disableAnimations: disabled,
          openReading: false,
        );
        await tester.tap(
          find.byKey(const ValueKey('settings-section-reading')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final detail = find
            .ancestor(
              of: find.byKey(const ValueKey('global-mode')),
              matching: find.byType(CupertinoPageScaffold),
            )
            .first;
        expect(tester.getTopLeft(detail), Offset.zero);
        final fades = tester.widgetList<FadeTransition>(
          find.ancestor(of: detail, matching: find.byType(FadeTransition)),
        );
        expect(
          fades.any((fade) => fade.opacity.value > 0 && fade.opacity.value < 1),
          !disabled,
        );
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pump();
        if (disabled) {
          expect(
            find.byKey(const ValueKey('global-mode'), skipOffstage: false),
            findsNothing,
          );
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('global-mode')), findsNothing);
        expect(
          find.byKey(const ValueKey('settings-section-reading')),
          findsOneWidget,
        );
        expect(writes(), isEmpty);
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );
  }

  for (final appearance in Brightness.values) {
    testWidgets(
      'settings preserve navigation focus at both layout changes in $appearance',
      (tester) async {
        final controller = editor();
        await tester.runAsync(controller.refresh);
        await show(
          tester,
          controller,
          appearance: appearance,
          openReading: false,
          size: const Size(360, 800),
        );
        await openSettingsSection(tester, 'about');
        Widget? focusedBack() => FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<CupertinoNavigationBarBackButton>();
        for (var i = 0; i < 10 && focusedBack() == null; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(focusedBack(), isA<CupertinoNavigationBarBackButton>());

        tester.view.physicalSize = const Size(768, 1024);
        await tester.pumpAndSettle();
        final focusedRow = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<CupertinoButton>();
        expect(
          focusedRow?.key,
          const ValueKey(('settings-navigation', 'about')),
        );
        tester.view.physicalSize = const Size(844, 390);
        await tester.pumpAndSettle();
        expect(focusedBack(), isA<CupertinoNavigationBarBackButton>());
        expect(find.text('轻松翻开下一页'), findsOneWidget);
        expect(writes(), isEmpty);
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );

    testWidgets(
      'settings directory opens a detail by keyboard in $appearance',
      (tester) async {
        final controller = editor();
        await tester.runAsync(controller.refresh);
        await show(
          tester,
          controller,
          appearance: appearance,
          openReading: false,
        );
        const key = ValueKey(('settings-navigation', 'reading'));
        Key? focusedButton() => FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<CupertinoButton>()
            ?.key;
        for (
          var attempt = 0;
          attempt < 10 && focusedButton() != key;
          attempt++
        ) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(focusedButton(), key);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('global-fit')), findsOneWidget);
        expect(writes(), isEmpty);
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );

    testWidgets(
      'settings directory keeps the saved choice through categories and resize in $appearance',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue =
            appearance == Brightness.light ? Brightness.dark : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final controller = editor();
        await tester.runAsync(controller.refresh);
        await show(
          tester,
          controller,
          appearance: appearance,
          reduceMotion: true,
        );
        await select<wire.ReaderFit>(tester, '适宽');
        await openSettingsSection(tester, 'appearance');
        expect(find.byKey(const ValueKey('global-fit')), findsNothing);
        tester.view.physicalSize = const Size(768, 1024);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-directory')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('global-mode')), findsNothing);
        final row = find.byKey(const ValueKey('settings-section-appearance'));
        expect(
          tester.widget<CupertinoListTile>(row).backgroundColor,
          AppColors.selection.resolveFrom(tester.element(row)),
        );
        final subtitle = tester.element(
          find.descendant(of: row, matching: find.text('跟随系统、浅色与深色')),
        );
        expect(
          DefaultTextStyle.of(subtitle).style.color,
          CupertinoColors.secondaryLabel.resolveFrom(subtitle),
        );
        await openSettingsSection(tester, 'reading');
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('settings-directory')), findsNothing);
        expect(
          tester
              .widget<ChoiceField<wire.ReaderFit>>(
                find.byKey(const ValueKey('global-fit')),
              )
              .value,
          wire.ReaderFit.READER_FIT_WIDTH,
        );
        await tap(tester, find.byType(CupertinoNavigationBarBackButton));
        expect(find.byKey(const ValueKey('global-fit')), findsNothing);
        expect(find.text('有修改等待发送。'), findsNothing);
        await openSettingsSection(tester, 'reading');
        expect(
          tester
              .widget<ChoiceField<wire.ReaderFit>>(
                find.byKey(const ValueKey('global-fit')),
              )
              .value,
          wire.ReaderFit.READER_FIT_WIDTH,
        );
        await select<wire.ReaderFit>(tester, '适宽');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('global-fit')), findsNothing);
        expect(find.text('有修改等待发送。'), findsNothing);
        expect(writes(), hasLength(1));
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );
  }

  testWidgets('an untouched global panel follows newly confirmed snapshots', (
    tester,
  ) async {
    final controller = editor();
    await tester.runAsync(controller.refresh);
    await show(tester, controller);
    expect(
      tester
          .widget<ChoiceField<wire.ReaderFit>>(
            find.byKey(const ValueKey('global-fit')),
          )
          .value,
      wire.ReaderFit.READER_FIT_CONTAIN,
    );
    await tester.runAsync(
      () => repository.setGlobal(values: _global(), basedOnRevision: 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceField<wire.ReaderFit>>(
            find.byKey(const ValueKey('global-fit')),
          )
          .value,
      wire.ReaderFit.READER_FIT_WIDTH,
    );
    expect(state().snapshot!.globalRevision, 1);
    expect(tester.takeException(), isNull);
    await hide(tester);
  });

  testWidgets(
    'autosave keeps the opening CAS and requires explicit conflict reload',
    (tester) async {
      final controller = editor();
      await tester.runAsync(controller.refresh);
      await show(tester, controller);
      final remoteClient = BusinessStateClient(
        api: server,
        identity: client.identity,
      );
      addTearDown(remoteClient.dispose);
      await tester.runAsync(() async {
        await SettingsRepository(remoteClient).setGlobal(
          values: _global(fit: wire.ReaderFit.READER_FIT_HEIGHT),
          basedOnRevision: 0,
        );
      });
      expect(state().snapshot!.globalRevision, 0);
      await select<wire.ReaderFit>(tester, '适宽');
      expect(find.text('设置已在其他设备修改，请重新读取后确认。'), findsOneWidget);
      expect(find.text('设置尚未确认，本会话保留原操作。'), findsNothing);
      expect(find.text('重试原设置操作'), findsNothing);
      expect(state().pending!.retryable, false);
      final rejected = wire.decodeProtoJson(
        wire.SettingsMutation(),
        jsonDecode(writes().last.body!),
      );
      expect(rejected.expectedRevision, 0);
      await tap(tester, find.text('重新读取设置'));
      expect(state().pending, isNull);
      expect(
        tester
            .widget<ChoiceField<wire.ReaderFit>>(
              find.byKey(const ValueKey('global-fit')),
            )
            .value,
        wire.ReaderFit.READER_FIT_HEIGHT,
      );
      await select<wire.ReaderFit>(tester, '适宽');
      expect(
        wire
            .decodeProtoJson(
              wire.SettingsMutation(),
              jsonDecode(writes().last.body!),
            )
            .expectedRevision,
        1,
      );
      expect(state().snapshot!.globalRevision, 2);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'manga editor distinguishes inherited layout from explicit AUTO',
    (tester) async {
      await tester.runAsync(
        () => repository.setGlobal(
          values: _global(
            layout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
          ),
          basedOnRevision: 0,
        ),
      );
      final controller = editor(manga: true);
      await tester.runAsync(controller.refresh);
      await show(tester, controller, manga: true);
      expect(
        tester
            .widget<ChoiceField<wire.ReaderPageLayout>>(
              find.byType(ChoiceField<wire.ReaderPageLayout>),
            )
            .value,
        isNull,
      );
      await select<wire.ReaderPageLayout>(tester, '自动');
      expect(state(manga: true).snapshot!.overrides!.hasPageLayout(), true);
      expect(
        state(manga: true).snapshot!.effectiveReader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      );
      await select<wire.ReaderPageLayout>(tester, '跟随全局');
      expect(
        tester
            .widget<ChoiceField<wire.ReaderPageLayout>>(
              find.byType(ChoiceField<wire.ReaderPageLayout>),
            )
            .value,
        isNull,
      );
      expect(state(manga: true).snapshot!.overrides!.hasPageLayout(), false);
      expect(
        state(manga: true).snapshot!.effectiveReader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
      );
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets('manga settings conflict requires a read, not an exact retry', (
    tester,
  ) async {
    final controller = editor(manga: true);
    await tester.runAsync(controller.refresh);
    await show(tester, controller, manga: true);
    final remoteClient = BusinessStateClient(
      api: server,
      identity: client.identity,
    );
    addTearDown(remoteClient.dispose);
    await tester.runAsync(
      () => SettingsRepository(remoteClient).setManga(
        mangaKey: _key,
        overrides: wire.ReaderSettingsOverride(
          pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
        ),
        basedOnRevision: 0,
      ),
    );
    await select<wire.ReaderPageLayout>(tester, '自动');
    expect(find.text('设置已在其他设备修改，请重新读取后确认。'), findsOneWidget);
    expect(find.text('设置尚未确认，本会话保留原操作。'), findsNothing);
    expect(find.text('重试原设置操作'), findsNothing);
    expect(state(manga: true).pending?.retryable, false);
    expect(state(manga: true).canEdit, false);
    expect(server.appliedMutations, 1);

    await tap(tester, find.text('重新读取设置'));
    expect(writes(), hasLength(2));
    expect(state(manga: true).pending, isNull);
    expect(state(manga: true).canEdit, true);
    expect(
      state(manga: true).snapshot?.overrides?.pageLayout,
      wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
    );
    expect(tester.takeException(), isNull);
    await hide(tester);
  });

  for (final manga in [false, true]) {
    testWidgets(
      'reopening ${manga ? 'manga' : 'global'} pending editor shows the submitted value and only permits exact retry',
      (tester) async {
        var controller = editor(manga: manga);
        await tester.runAsync(controller.refresh);
        await show(tester, controller, manga: manga);
        server.loseNextResponse = true;
        if (manga) {
          await select<wire.ReaderPageLayout>(tester, '自动');
        } else {
          await select<wire.ReaderFit>(tester, '适宽');
        }
        final original = writes().single.body;
        expect(server.appliedMutations, 1);
        expect(state(manga: manga).pending?.retryable, true);
        expect(find.text('设置尚未确认，本会话保留原操作。'), findsOneWidget);
        await hide(tester);
        fixture.invalidate(mangaKey: manga ? _key : null);
        controller = editor(manga: manga);
        await tester.runAsync(controller.refresh);
        await show(tester, controller, manga: manga);
        if (manga) {
          expect(
            tester
                .widget<ChoiceField<wire.ReaderPageLayout>>(
                  find.byType(ChoiceField<wire.ReaderPageLayout>),
                )
                .value,
            wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
          );
        } else {
          expect(
            tester
                .widget<ChoiceField<wire.ReaderFit>>(
                  find.byType(ChoiceField<wire.ReaderFit>),
                )
                .value,
            wire.ReaderFit.READER_FIT_WIDTH,
          );
        }
        if (manga) {
          expect(
            tester
                .widget<ChoiceField<wire.ReaderPageLayout>>(
                  find.byType(ChoiceField<wire.ReaderPageLayout>),
                )
                .onChanged,
            isNull,
          );
        } else {
          expect(
            tester
                .widget<ChoiceField<wire.ReaderFit>>(
                  find.byType(ChoiceField<wire.ReaderFit>),
                )
                .onChanged,
            isNull,
          );
        }
        await tap(tester, find.text('重新读取设置'));
        expect(writes(), hasLength(1));
        await tap(tester, find.text('重试原设置操作'));
        expect(writes().map((request) => request.body), [original, original]);
        expect(server.appliedMutations, 1);
        expect(state(manga: manga).pending, isNull);
        expect(state(manga: manga).canEdit, true);
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );
  }
}
