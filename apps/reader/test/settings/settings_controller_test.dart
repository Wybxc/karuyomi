import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/business_state_server.dart';
import 'settings_fixture.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
wire.GlobalSettingsValues _global({
  wire.AppTheme theme = wire.AppTheme.APP_THEME_DARK,
  wire.ReaderMode mode = wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
  wire.ReaderPageLayout layout = wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
}) => wire.GlobalSettingsValues(
  theme: theme,
  reader: wire.ReaderSettings(
    mode: mode,
    pageLayout: layout,
    fit: wire.ReaderFit.READER_FIT_CONTAIN,
    background: wire.ReaderBackground.READER_BACKGROUND_BLACK,
    tapZones: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
    keyboard: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
  ),
);

void main() {
  late SettingsFixture fixture;
  late TestBusinessServer server;
  late SettingsController controller;
  SettingsState state() => fixture.state();
  late Completer<void> received;
  late Completer<void> release;
  bool holdNextWrite = false;

  setUp(() async {
    fixture = SettingsFixture();
    await fixture.connect();
    server = fixture.platform.businessServer;
    controller = fixture.editor();
    received = Completer<void>();
    release = Completer<void>();
    holdNextWrite = false;
    fixture.platform.afterBusinessReply = (request, reply) async {
      if (holdNextWrite && request.method == 'POST') {
        holdNextWrite = false;
        received.complete();
        await release.future;
      }
      return reply;
    };
  });
  tearDown(() async {
    if (!release.isCompleted) release.complete();
    await fixture.dispose();
  });

  List<TestBusinessRequest> writes() =>
      server.requests.where((request) => request.method == 'POST').toList();

  test('only ACKs confirm settings and an uncertain command requires exact explicit retry', () async {
    expect(await controller.refresh(), true);
    holdNextWrite = true;
    final write = controller.saveGlobal(_global(), 0);
    await received.future;
    expect(state().busy, true);
    expect(state().canEdit, false);
    expect(state().snapshot!.global.theme, wire.AppTheme.APP_THEME_SYSTEM);
    expect(state().snapshot!.globalRevision, 0);
    release.complete();
    expect(await write, true);
    expect(state().snapshot!.global.theme, wire.AppTheme.APP_THEME_DARK);
    expect(state().snapshot!.globalRevision, 1);
    server.loseNextResponse = true;
    expect(
      await controller.saveGlobal(
        _global(theme: wire.AppTheme.APP_THEME_LIGHT),
        1,
      ),
      false,
    );
    expect(state().error, contains('尚未确认'));
    expect(state().pending!.retryable, true);
    expect(state().snapshot!.global.theme, wire.AppTheme.APP_THEME_DARK);
    final original = writes().last.body;
    expect(await controller.saveGlobal(_global(), 1), false);
    expect(writes(), hasLength(2));
    expect(await controller.refresh(), true);
    expect(writes(), hasLength(2));
    expect(state().pending, isNotNull);
    expect(state().canEdit, false);
    expect(await controller.retry(), true);
    expect(writes().last.body, original);
    expect(server.appliedMutations, 2);
    expect(state().pending, isNull);
    expect(state().canEdit, true);
    expect(state().snapshot!.global.theme, wire.AppTheme.APP_THEME_LIGHT);
    expect(state().snapshot!.globalRevision, 2);
  });

  test(
    'identity changes discard old views before a late settings ACK',
    () async {
      await controller.refresh();
      holdNextWrite = true;
      final write = controller.saveGlobal(_global(), 0);
      await received.future;
      fixture.platform.bootstrapSubject = 'another-owner';
      await fixture.catalog.connect();
      expect(state().snapshot!.global.theme, wire.AppTheme.APP_THEME_SYSTEM);
      expect(state().pending, isNull);
      release.complete();
      expect(await write, false);
      expect(state().snapshot!.globalRevision, 0);
      expect(state().snapshot!.global.theme, wire.AppTheme.APP_THEME_SYSTEM);
    },
  );

  test('global confirmation refreshes inherited manga values while explicit overrides remain', () async {
    final manga = fixture.editor(mangaKey: _key);
    SettingsState mangaState() => fixture.state(mangaKey: _key);
    await manga.refresh();
    await controller.refresh();
    Future<void> untilRevision(int revision) async {
      for (var turn = 0; turn < 100; turn++) {
        if (!mangaState().busy &&
            mangaState().snapshot?.globalRevision == revision) {
          return;
        }
        await Future<void>.delayed(Duration.zero);
      }
      fail('Inherited settings did not reach revision $revision');
    }

    final inherited = untilRevision(1);
    expect(
      await controller.saveGlobal(
        _global(
          mode: wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
          layout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
        ),
        0,
      ),
      true,
    );
    await inherited;
    expect(mangaState().snapshot!.overrides!.hasMode(), false);
    expect(
      mangaState().snapshot!.effectiveReader.mode,
      wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
    );
    expect(
      mangaState().snapshot!.effectiveReader.pageLayout,
      wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
    );
    expect(
      await manga.saveOverrides(
        wire.ReaderSettingsOverride(
          mode: wire.ReaderMode.READER_MODE_WEBTOON,
          pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
        ),
        0,
      ),
      true,
    );
    final explicit = untilRevision(2);
    expect(
      await controller.saveGlobal(
        _global(layout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_SINGLE),
        1,
      ),
      true,
    );
    await explicit;
    expect(mangaState().snapshot!.globalRevision, 2);
    expect(mangaState().snapshot!.mangaRevision, 1);
    expect(
      mangaState().snapshot!.effectiveReader.mode,
      wire.ReaderMode.READER_MODE_WEBTOON,
    );
    expect(
      mangaState().snapshot!.effectiveReader.pageLayout,
      wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
    );
  });
}
