import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/business_state_server.dart';
import 'settings_fixture.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
wire.GlobalSettingsValues _global({
  wire.ReaderFit fit = wire.ReaderFit.READER_FIT_WIDTH,
  wire.ReaderMode mode = wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
  wire.ReaderPageLayout layout = wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
}) => wire.GlobalSettingsValues(
  reader: wire.ReaderSettings(mode: mode, pageLayout: layout, fit: fit),
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

  Future<void> until(bool Function() condition) async {
    for (var turn = 0; turn < 100; turn++) {
      if (condition()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('Settings autosave did not reach the expected state');
  }

  test('autosave waits for confirmation and merges the remaining choices into one write', () async {
    expect(await controller.refresh(), true);
    holdNextWrite = true;
    controller.queueGlobal(_global());
    await received.future;
    expect(state().snapshot!.globalRevision, 0);
    expect(state().canChange, true);
    expect(state().canEdit, false);
    controller.queueGlobal(_global(fit: wire.ReaderFit.READER_FIT_HEIGHT));
    controller.queueGlobal(
      _global(
        fit: wire.ReaderFit.READER_FIT_HEIGHT,
        layout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
      ),
    );
    expect(state().unsent!.expectedRevision, 1);
    expect(writes(), hasLength(1));

    release.complete();
    await until(() => state().canEdit && state().snapshot!.globalRevision == 2);
    expect(state().unsent, isNull);
    expect(writes(), hasLength(2));
    expect(
      state().snapshot!.effectiveReader.fit,
      wire.ReaderFit.READER_FIT_HEIGHT,
    );
    expect(
      state().snapshot!.effectiveReader.pageLayout,
      wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
    );
  });

  test('autosave pauses later changes until the lost acknowledgment is retried exactly', () async {
    expect(await controller.refresh(), true);
    var first = true;
    fixture.platform.afterBusinessReply = (request, reply) async {
      if (first && request.method == 'POST') {
        first = false;
        received.complete();
        await release.future;
        throw StateError('Simulated lost acknowledgment');
      }
      return reply;
    };
    controller.queueGlobal(_global());
    await received.future;
    final original = writes().single.body;
    controller.queueGlobal(_global(fit: wire.ReaderFit.READER_FIT_HEIGHT));
    release.complete();
    await until(() => state().canRetry && state().submitting == null);
    expect(state().snapshot!.globalRevision, 0);
    expect(state().canChange, false);
    expect(
      state().unsent!.setGlobal.reader.fit,
      wire.ReaderFit.READER_FIT_HEIGHT,
    );
    expect(writes(), hasLength(1));

    expect(await controller.retry(), true);
    await until(() => state().canEdit && state().snapshot!.globalRevision == 2);
    expect(writes(), hasLength(3));
    expect(writes()[1].body, original);
    expect(writes()[2].body, isNot(original));
    expect(server.appliedMutations, 2);
  });

  test('recreating a settings editor retains the known rejection instead of calling it unknown', () async {
    await controller.refresh();
    expect(await controller.saveGlobal(_global(), 1), false);
    expect(state().failure, SettingsFailure.conflict);
    fixture.invalidate();
    controller = fixture.editor();
    expect(state().failure, SettingsFailure.conflict);
    expect(state().error, contains('其他设备'));
    expect(state().canRetry, false);
    expect(await controller.refresh(), true);
    expect(state().pending, isNull);
    expect(writes(), hasLength(1));
  });

  test(
    'acknowledged settings move to reading before authoritative reply arrives',
    () async {
      await controller.refresh();
      final entered = Completer<void>();
      final proceed = Completer<void>();
      addTearDown(() {
        if (!proceed.isCompleted) proceed.complete();
      });
      fixture.platform.afterBusinessReply = (request, reply) async {
        if (request.method == 'GET' && request.uri.path == '/api/settings') {
          entered.complete();
          await proceed.future;
        }
        return reply;
      };
      final saving = controller.saveGlobal(_global(), 0);
      await entered.future.timeout(const Duration(seconds: 5));
      expect(state().activity, SettingsActivity.reading);
      expect(state().canEdit, false);
      proceed.complete();
      expect(await saving, true);
      expect(writes(), hasLength(1));
    },
  );

  test('acknowledged settings read failure stays confirmed and retries only the read', () async {
    await controller.refresh();
    var failReads = true;
    fixture.platform.afterBusinessReply = (request, reply) {
      if (failReads &&
          request.method == 'GET' &&
          request.uri.path == '/api/settings') {
        throw StateError('Current settings read failed');
      }
      return reply;
    };
    expect(await controller.saveGlobal(_global(), 0), false);
    expect(state().error, contains('已确认'));
    expect(state().error, isNot(contains('尚未确认')));
    expect(state().pending, isNotNull);
    expect(state().canEdit, false);
    expect(await controller.retry(), false);
    expect(writes(), hasLength(1));
    failReads = false;
    expect(await controller.retry(), true);
    expect(writes(), hasLength(1));
    expect(server.appliedMutations, 1);
    expect(state().pending, isNull);
    expect(
      state().snapshot!.global.reader.fit,
      wire.ReaderFit.READER_FIT_WIDTH,
    );
  });

  test('only ACKs confirm settings and an uncertain command requires exact explicit retry', () async {
    expect(await controller.refresh(), true);
    holdNextWrite = true;
    final write = controller.saveGlobal(_global(), 0);
    await received.future;
    expect(state().busy, true);
    expect(state().canEdit, false);
    expect(
      state().snapshot!.global.reader.fit,
      wire.ReaderFit.READER_FIT_CONTAIN,
    );
    expect(state().snapshot!.globalRevision, 0);
    release.complete();
    expect(await write, true);
    expect(
      state().snapshot!.global.reader.fit,
      wire.ReaderFit.READER_FIT_WIDTH,
    );
    expect(state().snapshot!.globalRevision, 1);
    server.loseNextResponse = true;
    expect(
      await controller.saveGlobal(
        _global(fit: wire.ReaderFit.READER_FIT_HEIGHT),
        1,
      ),
      false,
    );
    expect(state().error, contains('尚未确认'));
    expect(state().pending!.retryable, true);
    expect(
      state().snapshot!.global.reader.fit,
      wire.ReaderFit.READER_FIT_WIDTH,
    );
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
    expect(
      state().snapshot!.global.reader.fit,
      wire.ReaderFit.READER_FIT_HEIGHT,
    );
    expect(state().snapshot!.globalRevision, 2);
  });

  test(
    'identity changes discard queued preferences before a late settings ACK',
    () async {
      await controller.refresh();
      holdNextWrite = true;
      controller.queueGlobal(_global());
      await received.future;
      controller.queueGlobal(_global(fit: wire.ReaderFit.READER_FIT_HEIGHT));
      expect(state().unsent, isNotNull);
      fixture.platform.bootstrapSubject = 'another-owner';
      await fixture.catalog.connect();
      expect(state().unsent, isNull);
      expect(
        state().snapshot!.global.reader.fit,
        wire.ReaderFit.READER_FIT_CONTAIN,
      );
      expect(state().pending, isNull);
      release.complete();
      await Future<void>.delayed(Duration.zero);
      expect(writes(), hasLength(1));
      expect(state().snapshot!.globalRevision, 0);
      expect(
        state().snapshot!.global.reader.fit,
        wire.ReaderFit.READER_FIT_CONTAIN,
      );
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
