import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/business_state_server.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
wire.GlobalSettingsValues _global({
  wire.AppTheme theme = wire.AppTheme.APP_THEME_DARK,
  wire.ReaderPageLayout layout = wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
}) => wire.GlobalSettingsValues(
  theme: theme,
  reader: wire.ReaderSettings(
    mode: wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
    pageLayout: layout,
    background: wire.ReaderBackground.READER_BACKGROUND_BLACK,
    tapZones: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
    keyboard: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
  ),
);

void main() {
  late TestBusinessServer server;
  late BusinessStateClient client;
  late SettingsRepository repository;
  final editors = <SettingsController>[];

  setUp(() {
    server = TestBusinessServer();
    client = BusinessStateClient(
      api: server,
      identity: ProgressIdentity(
        origin: Uri.parse('https://reader.example'),
        subject: 'owner-subject',
      ),
    );
    repository = SettingsRepository(client);
    editors.clear();
  });
  tearDown(() async {
    for (final editor in editors) {
      editor.dispose();
    }
    await client.dispose();
  });
  SettingsController editor({bool manga = false}) {
    final value = SettingsController(
      repository: repository,
      mangaKey: manga ? _key : null,
      isCurrent: () => true,
    );
    editors.add(value);
    return value;
  }

  Future<void> show(
    WidgetTester tester,
    SettingsController controller, {
    bool manga = false,
  }) async {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: manga
                ? MangaSettingsEditor(controller: controller)
                : GlobalSettingsPanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> hide(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
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
    await tap(tester, find.byType(DropdownButtonFormField<T>));
    await tap(tester, find.text(label).last);
  }

  List<TestBusinessRequest> writes() =>
      server.requests.where((request) => request.method == 'POST').toList();

  testWidgets('an untouched global panel follows newly confirmed snapshots', (
    tester,
  ) async {
    final controller = editor();
    await tester.runAsync(controller.refresh);
    await show(tester, controller);
    expect(
      find.byKey(
        const ValueKey(('global-theme', wire.AppTheme.APP_THEME_SYSTEM)),
      ),
      findsOneWidget,
    );
    await tester.runAsync(
      () => repository.setGlobal(values: _global(), basedOnRevision: 0),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey(('global-theme', wire.AppTheme.APP_THEME_DARK)),
      ),
      findsOneWidget,
    );
    expect(controller.snapshot!.globalRevision, 1);
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
      expect(controller.snapshot!.globalRevision, 1);
      expect(
        find.byKey(
          const ValueKey(('global-theme', wire.AppTheme.APP_THEME_DARK)),
        ),
        findsOneWidget,
      );
      await tap(tester, find.text('保存全局设置'));
      expect(find.text('设置已在其他设备修改，请重新读取后确认。'), findsOneWidget);
      expect(controller.pending!.retryable, false);
      final rejected = wire.decodeProtoJson(
        wire.SettingsMutation(),
        jsonDecode(writes().last.body!),
      );
      expect(rejected.expectedRevision, 0);
      await tap(tester, find.text('重新读取设置'));
      expect(controller.pending, isNull);
      expect(
        find.byKey(
          const ValueKey(('global-theme', wire.AppTheme.APP_THEME_LIGHT)),
        ),
        findsOneWidget,
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
      expect(controller.snapshot!.globalRevision, 2);
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
            .widget<DropdownButtonFormField<wire.ReaderPageLayout>>(
              find.byType(DropdownButtonFormField<wire.ReaderPageLayout>),
            )
            .initialValue,
        isNull,
      );
      await select<wire.ReaderPageLayout>(tester, '自动');
      await tap(tester, find.text('保存本漫画设置'));
      expect(controller.snapshot!.overrides!.hasPageLayout(), true);
      expect(
        controller.snapshot!.effectiveReader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      );
      await select<wire.ReaderPageLayout>(tester, '跟随全局');
      await tap(tester, find.text('保存本漫画设置'));
      expect(controller.snapshot!.overrides!.hasPageLayout(), false);
      expect(
        controller.snapshot!.effectiveReader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
      );
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

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
        server.failWrites = true;
        await tap(tester, find.text(manga ? '保存本漫画设置' : '保存全局设置'));
        final original = writes().single.body;
        expect(find.text('设置尚未确认，本会话保留原操作。'), findsOneWidget);
        await hide(tester);
        controller.dispose();
        editors.remove(controller);
        controller = editor(manga: manga);
        await tester.runAsync(controller.refresh);
        await show(tester, controller, manga: manga);
        if (manga) {
          expect(
            tester
                .widget<DropdownButtonFormField<wire.ReaderPageLayout>>(
                  find.byType(DropdownButtonFormField<wire.ReaderPageLayout>),
                )
                .initialValue,
            wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
          );
        } else {
          expect(
            tester
                .widget<DropdownButtonFormField<wire.AppTheme>>(
                  find.byType(DropdownButtonFormField<wire.AppTheme>),
                )
                .initialValue,
            wire.AppTheme.APP_THEME_DARK,
          );
        }
        if (manga) {
          expect(
            tester
                .widget<DropdownButtonFormField<wire.ReaderPageLayout>>(
                  find.byType(DropdownButtonFormField<wire.ReaderPageLayout>),
                )
                .onChanged,
            isNull,
          );
        } else {
          expect(
            tester
                .widget<DropdownButtonFormField<wire.AppTheme>>(
                  find.byType(DropdownButtonFormField<wire.AppTheme>),
                )
                .onChanged,
            isNull,
          );
        }
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, manga ? '保存本漫画设置' : '保存全局设置'),
              )
              .onPressed,
          isNull,
        );
        await tap(tester, find.text('重新读取设置'));
        expect(writes(), hasLength(1));
        server.failWrites = false;
        await tap(tester, find.text('重试原设置操作'));
        expect(writes().map((request) => request.body), [original, original]);
        expect(server.appliedMutations, 1);
        expect(controller.pending, isNull);
        expect(controller.canEdit, true);
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );
  }
}
