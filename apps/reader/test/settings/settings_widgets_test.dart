import 'package:karuyomi/widgets/choice_field.dart';

import '../test_app.dart';

import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/business_state_server.dart';
import 'settings_fixture.dart';
import 'settings_probe.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
wire.GlobalSettingsValues _global({
  wire.AppTheme theme = wire.AppTheme.APP_THEME_DARK,
  wire.ReaderPageLayout layout = wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
}) => wire.GlobalSettingsValues(
  theme: theme,
  reader: wire.ReaderSettings(
    mode: wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
    pageLayout: layout,
    fit: wire.ReaderFit.READER_FIT_CONTAIN,
    background: wire.ReaderBackground.READER_BACKGROUND_BLACK,
    tapZones: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
    keyboard: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
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
    bool openAppearance = true,
  }) async {
    tester.view.physicalSize = const Size(480, 1000);
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
          ),
          child: child!,
        ),
        home: manga
            ? MangaSettingsEditor(catalog: fixture.catalog, mangaKey: _key)
            : GlobalSettingsPanel(catalog: fixture.catalog),
      ),
      container: fixture.container,
    );
    await tester.pumpAndSettle();
    if (!manga && openAppearance) {
      await openSettingsSection(tester, 'appearance');
    }
  }

  Future<void> hide(WidgetTester tester) async {
    await tester.pumpApp(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  Future<void> select<T>(WidgetTester tester, String label) async {
    await tap(tester, find.byType(ChoiceField<T>));
    await tap(tester, find.widgetWithText(CupertinoMenuItem, label));
  }

  List<TestBusinessRequest> writes() =>
      server.requests.where((request) => request.method == 'POST').toList();

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
          openAppearance: false,
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
      'settings directory opens a detail by keyboard in $appearance',
      (tester) async {
        final controller = editor();
        await tester.runAsync(controller.refresh);
        await show(
          tester,
          controller,
          appearance: appearance,
          openAppearance: false,
        );
        const key = ValueKey(('settings-navigation', 'appearance'));
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
        expect(find.byKey(const ValueKey('global-theme')), findsOneWidget);
        expect(writes(), isEmpty);
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );

    testWidgets(
      'settings directory preserves its draft through categories and resize in $appearance',
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
        await select<wire.AppTheme>(tester, '深色');
        await openSettingsSection(tester, 'reading');
        expect(find.byKey(const ValueKey('global-theme')), findsNothing);
        tester.view.physicalSize = const Size(768, 1024);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settings-directory')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('global-mode')), findsOneWidget);
        await openSettingsSection(tester, 'appearance');
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
        tester.view.physicalSize = const Size(360, 800);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('settings-directory')), findsNothing);
        expect(
          tester
              .widget<ChoiceField<wire.AppTheme>>(
                find.byKey(const ValueKey('global-theme')),
              )
              .value,
          wire.AppTheme.APP_THEME_DARK,
        );
        await tap(tester, find.byType(CupertinoNavigationBarBackButton));
        expect(find.byKey(const ValueKey('global-theme')), findsNothing);
        expect(find.text('修改尚未保存。'), findsOneWidget);
        await openSettingsSection(tester, 'appearance');
        expect(
          tester
              .widget<ChoiceField<wire.AppTheme>>(
                find.byKey(const ValueKey('global-theme')),
              )
              .value,
          wire.AppTheme.APP_THEME_DARK,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('global-theme')), findsNothing);
        expect(find.text('修改尚未保存。'), findsOneWidget);
        expect(writes(), isEmpty);
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
          .widget<ChoiceField<wire.AppTheme>>(
            find.byKey(const ValueKey('global-theme')),
          )
          .value,
      wire.AppTheme.APP_THEME_SYSTEM,
    );
    await tester.runAsync(
      () => repository.setGlobal(values: _global(), basedOnRevision: 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceField<wire.AppTheme>>(
            find.byKey(const ValueKey('global-theme')),
          )
          .value,
      wire.AppTheme.APP_THEME_DARK,
    );
    expect(state().snapshot!.globalRevision, 1);
    expect(tester.takeException(), isNull);
    await hide(tester);
  });

  testWidgets(
    'a dirty global draft keeps its opening CAS until explicit conflict reload',
    (tester) async {
      final controller = editor();
      await tester.runAsync(controller.refresh);
      await show(tester, controller);
      await select<wire.AppTheme>(tester, '深色');
      final remoteClient = BusinessStateClient(
        api: server,
        identity: client.identity,
      );
      addTearDown(remoteClient.dispose);
      await tester.runAsync(() async {
        await SettingsRepository(remoteClient).setGlobal(
          values: _global(theme: wire.AppTheme.APP_THEME_LIGHT),
          basedOnRevision: 0,
        );
        await repository.loadGlobal();
      });
      await tester.pumpAndSettle();
      expect(state().snapshot!.globalRevision, 1);
      expect(
        tester
            .widget<ChoiceField<wire.AppTheme>>(
              find.byKey(const ValueKey('global-theme')),
            )
            .value,
        wire.AppTheme.APP_THEME_DARK,
      );
      await tap(tester, find.text('保存全局设置'));
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
            .widget<ChoiceField<wire.AppTheme>>(
              find.byKey(const ValueKey('global-theme')),
            )
            .value,
        wire.AppTheme.APP_THEME_LIGHT,
      );
      await tap(tester, find.text('保存全局设置'));
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
      await tap(tester, find.text('保存本漫画设置'));
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
      await tap(tester, find.text('保存本漫画设置'));
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
    await select<wire.ReaderPageLayout>(tester, '自动');
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
    await tap(tester, find.text('保存本漫画设置'));
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
        if (manga) {
          await select<wire.ReaderPageLayout>(tester, '自动');
        } else {
          await select<wire.AppTheme>(tester, '深色');
        }
        server.loseNextResponse = true;
        await tap(tester, find.text(manga ? '保存本漫画设置' : '保存全局设置'));
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
                .widget<ChoiceField<wire.AppTheme>>(
                  find.byType(ChoiceField<wire.AppTheme>),
                )
                .value,
            wire.AppTheme.APP_THEME_DARK,
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
                .widget<ChoiceField<wire.AppTheme>>(
                  find.byType(ChoiceField<wire.AppTheme>),
                )
                .onChanged,
            isNull,
          );
        }
        expect(
          tester
              .widget<CupertinoButton>(
                find.widgetWithText(
                  CupertinoButton,
                  manga ? '保存本漫画设置' : '保存全局设置',
                ),
              )
              .onPressed,
          isNull,
        );
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
