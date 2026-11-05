import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/business_state_server.dart';

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
    background: wire.ReaderBackground.READER_BACKGROUND_BLACK,
    tapZones: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
    keyboard: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
  ),
);

final class _ResponseGate implements ApiFetch {
  _ResponseGate(this.api);
  final ApiFetch api;
  final received = Completer<void>();
  final release = Completer<void>();
  bool holdNextWrite = false;

  @override
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final hold = holdNextWrite && method == 'POST';
    if (hold) holdNextWrite = false;
    final reply = await api.fetchApi(
      path,
      method: method,
      headers: headers,
      body: body,
    );
    if (hold) {
      received.complete();
      await release.future;
    }
    return reply;
  }
}

void main() {
  late TestBusinessServer server;
  late _ResponseGate gate;
  late BusinessStateClient client;
  late SettingsRepository repository;
  late SettingsController controller;
  late bool current;

  setUp(() {
    server = TestBusinessServer();
    gate = _ResponseGate(server);
    client = BusinessStateClient(
      api: gate,
      identity: ProgressIdentity(
        origin: Uri.parse('https://reader.example'),
        subject: 'owner-subject',
      ),
    );
    repository = SettingsRepository(client);
    current = true;
    controller = SettingsController(
      repository: repository,
      isCurrent: () => current,
    );
  });
  tearDown(() async {
    controller.dispose();
    await client.dispose();
  });

  List<TestBusinessRequest> writes() =>
      server.requests.where((request) => request.method == 'POST').toList();

  test(
    'only ACKs confirm settings and an uncertain command requires exact explicit retry',
    () async {
      expect(await controller.refresh(), true);
      gate.holdNextWrite = true;
      final write = controller.saveGlobal(_global(), 0);
      await gate.received.future;
      expect(controller.busy, true);
      expect(controller.canEdit, false);
      expect(controller.snapshot!.global.theme, wire.AppTheme.APP_THEME_SYSTEM);
      expect(controller.snapshot!.globalRevision, 0);
      gate.release.complete();
      expect(await write, true);
      expect(controller.snapshot!.global.theme, wire.AppTheme.APP_THEME_DARK);
      expect(controller.snapshot!.globalRevision, 1);
      server.loseNextResponse = true;
      expect(
        await controller.saveGlobal(
          _global(theme: wire.AppTheme.APP_THEME_LIGHT),
          1,
        ),
        false,
      );
      expect(controller.error, contains('尚未确认'));
      expect(controller.pending!.retryable, true);
      expect(controller.snapshot!.global.theme, wire.AppTheme.APP_THEME_DARK);
      final original = writes().last.body;
      expect(await controller.saveGlobal(_global(), 1), false);
      expect(writes(), hasLength(2));
      expect(await controller.refresh(), true);
      expect(writes(), hasLength(2));
      expect(controller.pending, isNotNull);
      expect(controller.canEdit, false);
      expect(await controller.retry(), true);
      expect(writes().last.body, original);
      expect(server.appliedMutations, 2);
      expect(controller.pending, isNull);
      expect(controller.canEdit, true);
      expect(controller.snapshot!.global.theme, wire.AppTheme.APP_THEME_LIGHT);
      expect(controller.snapshot!.globalRevision, 2);
    },
  );

  test(
    'identity changes permanently retire an editor before its late ACK',
    () async {
      await controller.refresh();
      gate.holdNextWrite = true;
      final write = controller.saveGlobal(_global(), 0);
      await gate.received.future;
      current = false;
      controller.checkCurrent();
      expect(controller.error, contains('身份或服务已改变'));
      expect(controller.available, false);
      gate.release.complete();
      expect(await write, false);
      expect(controller.snapshot!.global.theme, wire.AppTheme.APP_THEME_SYSTEM);
      current = true;
      final count = server.requests.length;
      expect(await controller.refresh(), false);
      expect(await controller.saveGlobal(_global(), 0), false);
      expect(controller.available, false);
      expect(server.requests, hasLength(count));
    },
  );

  test(
    'global confirmation refreshes inherited manga values while explicit overrides remain',
    () async {
      final manga = SettingsController(
        repository: repository,
        mangaKey: _key,
        isCurrent: () => true,
      );
      addTearDown(manga.dispose);
      await manga.refresh();
      await controller.refresh();
      Future<void> untilRevision(int revision) {
        final done = Completer<void>();
        void changed() {
          if (!manga.busy &&
              manga.snapshot?.globalRevision == revision &&
              !done.isCompleted) {
            manga.removeListener(changed);
            done.complete();
          }
        }

        manga.addListener(changed);
        changed();
        return done.future;
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
      expect(manga.snapshot!.overrides!.hasMode(), false);
      expect(
        manga.snapshot!.effectiveReader.mode,
        wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
      );
      expect(
        manga.snapshot!.effectiveReader.pageLayout,
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
      expect(manga.snapshot!.globalRevision, 2);
      expect(manga.snapshot!.mangaRevision, 1);
      expect(
        manga.snapshot!.effectiveReader.mode,
        wire.ReaderMode.READER_MODE_WEBTOON,
      );
      expect(
        manga.snapshot!.effectiveReader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      );
    },
  );
}
