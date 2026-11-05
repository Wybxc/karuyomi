import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/bookmark_repository.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:protobuf/protobuf.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

const _key = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _otherKey =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

ProgressIdentity _identity([String subject = 'owner-subject']) =>
    ProgressIdentity(
      origin: Uri.parse('https://reader.example'),
      subject: subject,
    );
BusinessStateClient _client(ApiFetch api, {String subject = 'owner-subject'}) =>
    BusinessStateClient(api: api, identity: _identity(subject));

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
    fit: wire.ReaderFit.READER_FIT_CONTAIN,
    tapZones: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
    keyboard: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
  ),
);

ApiReply _reply(GeneratedMessage value) => ApiReply(
  status: 200,
  headers: const {'content-type': 'application/json'},
  body: jsonEncode(wire.encodeProtoJson(value)),
  redirected: false,
);

wire.SettingsResponse _snapshot() => wire.SettingsResponse(
  schemaVersion: 1,
  global: wire.GlobalSettings(
    values: _global(theme: wire.AppTheme.APP_THEME_SYSTEM),
  ),
  manga: wire.MangaReaderSettings(
    mangaKey: _key,
    overrides: wire.ReaderSettingsOverride(),
  ),
  effectiveReader: wire.ReaderSettings(
    mode: wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
    pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
    background: wire.ReaderBackground.READER_BACKGROUND_BLACK,
    fit: wire.ReaderFit.READER_FIT_CONTAIN,
    tapZones: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
    keyboard: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
  ),
);

/// Holds a real supplier ACK after the server has committed the mutation.
final class _ResponseGate implements ApiFetch {
  _ResponseGate(this.api);
  final ApiFetch api;
  final received = Completer<void>();
  final release = Completer<void>();
  bool _held = false;

  @override
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final hold = method == 'POST' && !_held;
    if (hold) _held = true;
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
  late BusinessStateClient client;
  late SettingsRepository repository;

  setUp(() {
    server = TestBusinessServer();
    client = _client(server);
    repository = SettingsRepository(client);
  });
  tearDown(() => client.dispose());

  List<TestBusinessRequest> writes() => server.requests
      .where(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/api/settings/mutations',
      )
      .toList();

  test(
    'empty accounts expose SYSTEM, left-to-right and automatic defaults',
    () async {
      final value = await repository.loadGlobal();
      expect(value.globalRevision, 0);
      expect(value.accountRevision, 0);
      expect(value.global.theme, wire.AppTheme.APP_THEME_SYSTEM);
      expect(
        value.effectiveReader.mode,
        wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
      );
      expect(
        value.effectiveReader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      );
      expect(value.effectiveReader.cropBorders, false);
      expect(value.mangaKey, isNull);
      expect(value.mangaRevision, isNull);
      expect(value.overrides, isNull);
      expect(writes(), isEmpty);
    },
  );

  test(
    'manga presence distinguishes inheritance from AUTO and revisions do not alter business state',
    () async {
      await BookmarkRepository(client).set(
        mangaKey: _key,
        chapterKey: 'chapter',
        bookmarked: true,
        basedOnRevision: 0,
      );
      final business = server.manga(_key)!;
      final defaults = _global(
        mode: wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
        layout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
      )..reader.fit = wire.ReaderFit.READER_FIT_WIDTH;
      await repository.setGlobal(values: defaults, basedOnRevision: 0);
      final inherited = await repository.loadManga(_key);
      expect(inherited.mangaRevision, 0);
      expect(inherited.overrides!.hasMode(), false);
      expect(inherited.overrides!.hasPageLayout(), false);
      expect(inherited.overrides!.hasFit(), false);
      expect(inherited.effectiveReader.fit, wire.ReaderFit.READER_FIT_WIDTH);
      expect(
        inherited.effectiveReader.mode,
        wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
      );
      expect(
        inherited.effectiveReader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
      );
      final explicit = await repository.setManga(
        mangaKey: _key,
        overrides: wire.ReaderSettingsOverride(
          pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
          fit: wire.ReaderFit.READER_FIT_CONTAIN,
        ),
        basedOnRevision: 0,
      );
      expect(explicit.mangaRevision, 1);
      expect(explicit.globalRevision, 1);
      expect(explicit.overrides!.hasMode(), false);
      expect(explicit.overrides!.hasPageLayout(), true);
      expect(explicit.overrides!.hasFit(), true);
      expect(explicit.effectiveReader.fit, wire.ReaderFit.READER_FIT_CONTAIN);
      expect(
        explicit.effectiveReader.mode,
        wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
      );
      expect(
        explicit.effectiveReader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      );
      final cleared = await repository.setManga(
        mangaKey: _key,
        overrides: wire.ReaderSettingsOverride(),
        basedOnRevision: 1,
      );
      expect(cleared.mangaRevision, 2);
      expect(cleared.globalRevision, 1);
      expect(cleared.overrides!.hasPageLayout(), false);
      expect(cleared.overrides!.hasFit(), false);
      expect(cleared.effectiveReader.fit, wire.ReaderFit.READER_FIT_WIDTH);
      expect(
        cleared.effectiveReader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
      );
      expect(server.manga(_key), business);
      expect(server.bookmarked(_key, 'chapter'), true);
    },
  );

  test(
    'reader overrides distinguish explicit zero and false from inheritance and preserve unrelated defaults',
    () async {
      final global = _global();
      global.reader
        ..cropBorders = true
        ..background = wire.ReaderBackground.READER_BACKGROUND_THEME
        ..dimPercent = 80
        ..tapZones = wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED
        ..keyboard = wire.ReaderInputPreset.READER_INPUT_PRESET_DISABLED;
      await repository.setGlobal(values: global, basedOnRevision: 0);
      final explicit = await repository.setManga(
        mangaKey: _key,
        basedOnRevision: 0,
        overrides: wire.ReaderSettingsOverride(
          dimPercent: 0,
          cropBorders: false,
        ),
      );
      expect(explicit.overrides!.hasDimPercent(), true);
      expect(explicit.overrides!.hasCropBorders(), true);
      expect(explicit.effectiveReader.cropBorders, false);
      expect(explicit.effectiveReader.dimPercent, 0);
      expect(explicit.effectiveReader.background, global.reader.background);
      expect(explicit.effectiveReader.tapZones, global.reader.tapZones);
      expect(explicit.effectiveReader.keyboard, global.reader.keyboard);
      final cleared = await repository.setManga(
        mangaKey: _key,
        basedOnRevision: 1,
        overrides: wire.ReaderSettingsOverride(),
      );
      expect(cleared.overrides!.hasDimPercent(), false);
      expect(cleared.overrides!.hasCropBorders(), false);
      expect(cleared.effectiveReader.cropBorders, true);
      expect(cleared.effectiveReader, global.reader);
    },
  );

  test(
    'different settings scopes never implicitly resend each other',
    () async {
      server.failNextRequest = true;
      await expectLater(
        repository.setGlobal(values: _global(), basedOnRevision: 0),
        throwsStateError,
      );
      final original = writes().single.body;
      await repository.setManga(
        mangaKey: _key,
        overrides: wire.ReaderSettingsOverride(
          mode: wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
        ),
        basedOnRevision: 0,
      );
      expect(repository.pendingGlobal(), isNotNull);
      server.failNextRequest = true;
      await expectLater(
        repository.setManga(
          mangaKey: _key,
          overrides: wire.ReaderSettingsOverride(),
          basedOnRevision: 1,
        ),
        throwsStateError,
      );
      final mangaDraft = repository.pendingManga(_key)!;
      await expectLater(
        repository.setGlobal(
          values: _global(theme: wire.AppTheme.APP_THEME_LIGHT),
          basedOnRevision: 0,
        ),
        throwsStateError,
      );
      await repository.loadGlobal();
      expect(writes(), hasLength(3));
      expect(repository.pendingGlobal(), isNotNull);
      await repository.setGlobal(values: _global(), basedOnRevision: 0);
      expect(writes().last.body, original);
      expect(
        repository.pendingManga(_key)!.basedOnRevision,
        mangaDraft.basedOnRevision,
      );
      await repository.setManga(
        mangaKey: _otherKey,
        overrides: wire.ReaderSettingsOverride(),
        basedOnRevision: 0,
      );
      expect(writes(), hasLength(5));
      expect(repository.pendingManga(_key), isNotNull);
      expect(repository.pendingManga(_otherKey), isNull);
      expect(repository.pendingGlobal(), isNull);
    },
  );

  for (final mangaScope in [false, true]) {
    test(
      '${mangaScope ? 'manga lost ACK' : 'global pre-send failure'} retains the exact UUID, body and CAS for explicit retry',
      () async {
        Future<SettingsSnapshot> submit() => mangaScope
            ? repository.setManga(
                mangaKey: _key,
                overrides: wire.ReaderSettingsOverride(
                  pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
                  background: wire.ReaderBackground.READER_BACKGROUND_WHITE,
                  dimPercent: 0,
                  tapZones: wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED,
                  keyboard: wire.ReaderInputPreset.READER_INPUT_PRESET_DISABLED,
                  fit: wire.ReaderFit.READER_FIT_HEIGHT,
                  cropBorders: false,
                ),
                basedOnRevision: 0,
              )
            : repository.setGlobal(values: _global(), basedOnRevision: 0);
        if (mangaScope) {
          server.loseNextResponse = true;
        } else {
          server.failNextRequest = true;
        }
        await expectLater(submit(), throwsStateError);
        final original = writes().single.body;
        final draft = mangaScope
            ? repository.pendingManga(_key)!
            : repository.pendingGlobal()!;
        expect(draft.basedOnRevision, 0);
        expect(draft.retryable, true);
        if (mangaScope) {
          await repository.loadManga(_key);
        } else {
          await repository.loadGlobal();
        }
        expect(writes(), hasLength(1));
        final result = await submit();
        expect(writes().map((request) => request.body), [original, original]);
        final sent = wire.decodeProtoJson(
          wire.SettingsMutation(),
          jsonDecode(original!),
        );
        expect(sent.mutationId, isNotEmpty);
        expect(sent.expectedRevision, 0);
        if (mangaScope) {
          expect(sent.setManga.overrides.hasDimPercent(), true);
          expect(sent.setManga.overrides.hasFit(), true);
          expect(sent.setManga.overrides.hasCropBorders(), true);
          expect(result.effectiveReader.cropBorders, false);
          expect(result.effectiveReader.fit, wire.ReaderFit.READER_FIT_HEIGHT);
          expect(
            result.effectiveReader.background,
            wire.ReaderBackground.READER_BACKGROUND_WHITE,
          );
          expect(result.effectiveReader.dimPercent, 0);
          expect(
            result.effectiveReader.tapZones,
            wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED,
          );
          expect(
            result.effectiveReader.keyboard,
            wire.ReaderInputPreset.READER_INPUT_PRESET_DISABLED,
          );
        }
        expect(server.appliedMutations, 1);
        expect(mangaScope ? result.mangaRevision : result.globalRevision, 1);
        expect(
          mangaScope
              ? repository.pendingManga(_key)
              : repository.pendingGlobal(),
          isNull,
        );
      },
    );
  }

  test(
    'an old ACK cannot acknowledge remotely changed values; refresh clears only the rejected draft',
    () async {
      server.loseNextResponse = true;
      await expectLater(
        repository.setGlobal(values: _global(), basedOnRevision: 0),
        throwsStateError,
      );
      final remoteClient = _client(server);
      addTearDown(remoteClient.dispose);
      final remote = SettingsRepository(remoteClient);
      await remote.setGlobal(
        values: _global(theme: wire.AppTheme.APP_THEME_LIGHT),
        basedOnRevision: 1,
      );
      await expectLater(
        repository.setGlobal(values: _global(), basedOnRevision: 0),
        throwsA(
          isA<BusinessStateException>().having(
            (error) => error.conflict,
            'conflict',
            true,
          ),
        ),
      );
      expect(repository.pendingGlobal()!.retryable, false);
      final count = writes().length;
      await expectLater(
        repository.setGlobal(values: _global(), basedOnRevision: 0),
        throwsA(isA<BusinessStateException>()),
      );
      expect(writes(), hasLength(count));
      final current = await repository.loadGlobal();
      expect(current.globalRevision, 2);
      expect(current.global.theme, wire.AppTheme.APP_THEME_LIGHT);
      expect(repository.pendingGlobal(), isNull);
      final saved = await repository.setGlobal(
        values: _global(),
        basedOnRevision: 2,
      );
      expect(saved.globalRevision, 3);
    },
  );

  test(
    'an old ACK with unchanged values confirms the current manga revision',
    () async {
      final overrides = wire.ReaderSettingsOverride(
        pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      );
      server.loseNextResponse = true;
      await expectLater(
        repository.setManga(
          mangaKey: _key,
          overrides: overrides,
          basedOnRevision: 0,
        ),
        throwsStateError,
      );
      final remoteClient = _client(server);
      addTearDown(remoteClient.dispose);
      await SettingsRepository(
        remoteClient,
      ).setManga(mangaKey: _key, overrides: overrides, basedOnRevision: 1);
      final confirmed = await repository.setManga(
        mangaKey: _key,
        overrides: overrides,
        basedOnRevision: 0,
      );
      expect(confirmed.mangaRevision, 2);
      expect(confirmed.accountRevision, 2);
      expect(confirmed.overrides!.hasPageLayout(), true);
      expect(
        confirmed.overrides!.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      );
      expect(repository.pendingManga(_key), isNull);
      expect(server.appliedMutations, 2);
    },
  );

  test(
    'settings boundaries reject malformed identity, enums, effective values and missing overrides',
    () async {
      final invalid = <wire.SettingsResponse>[
        _snapshot()..schemaVersion = 2,
        _snapshot()..effectiveReader.cropBorders = true,
        _snapshot()..manga.mangaKey = _otherKey,
        _snapshot()..global.values.theme = wire.AppTheme.APP_THEME_UNSPECIFIED,
        _snapshot()
          ..global.values.reader.fit = wire.ReaderFit.READER_FIT_UNSPECIFIED,
        _snapshot()
          ..manga.overrides.fit = wire.ReaderFit.READER_FIT_UNSPECIFIED,
        _snapshot()..effectiveReader.fit = wire.ReaderFit.READER_FIT_HEIGHT,
        _snapshot()
          ..manga.overrides.mode = wire.ReaderMode.READER_MODE_UNSPECIFIED,
        _snapshot()
          ..manga.overrides.pageLayout =
              wire.ReaderPageLayout.READER_PAGE_LAYOUT_UNSPECIFIED,
        _snapshot()
          ..effectiveReader.mode = wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
        _snapshot()..manga.clearOverrides(),
        _snapshot()
          ..global.values.reader.background =
              wire.ReaderBackground.READER_BACKGROUND_UNSPECIFIED,
        _snapshot()
          ..manga.overrides.background =
              wire.ReaderBackground.READER_BACKGROUND_UNSPECIFIED,
        _snapshot()..manga.overrides.dimPercent = 81,
        _snapshot()
          ..manga.overrides.tapZones =
              wire.ReaderInputPreset.READER_INPUT_PRESET_UNSPECIFIED,
        _snapshot()
          ..manga.overrides.keyboard =
              wire.ReaderInputPreset.READER_INPUT_PRESET_UNSPECIFIED,
        _snapshot()
          ..effectiveReader.background =
              wire.ReaderBackground.READER_BACKGROUND_THEME,
        _snapshot()..effectiveReader.dimPercent = 1,
        _snapshot()
          ..effectiveReader.tapZones =
              wire.ReaderInputPreset.READER_INPUT_PRESET_DISABLED,
        _snapshot()
          ..effectiveReader.keyboard =
              wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED,
      ];
      for (final value in invalid) {
        server.beforeRequest = (_) => _reply(value);
        await expectLater(repository.loadManga(_key), throwsFormatException);
      }
      server.beforeRequest = null;
      expect((await repository.loadManga(_key)).mangaRevision, 0);
      final count = server.requests.length;
      await expectLater(
        repository.setGlobal(
          values: wire.GlobalSettingsValues(),
          basedOnRevision: 0,
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.setManga(
          mangaKey: _key,
          overrides: wire.ReaderSettingsOverride(
            mode: wire.ReaderMode.READER_MODE_UNSPECIFIED,
          ),
          basedOnRevision: 0,
        ),
        throwsFormatException,
      );
      await expectLater(
        repository.setManga(
          mangaKey: 'invalid',
          overrides: wire.ReaderSettingsOverride(),
          basedOnRevision: 0,
        ),
        throwsFormatException,
      );
      expect(server.requests, hasLength(count));
      expect(repository.pendingGlobal(), isNull);
      expect(repository.pendingManga(_key), isNull);
    },
  );

  test(
    'watchConfirmed publishes reads and acknowledged state, never a submitted draft',
    () async {
      final gate = _ResponseGate(server);
      client.rebindApi(gate, verifiedIdentity: client.identity);
      final events = <SettingsSnapshot>[];
      final subscription = repository.watchConfirmed().listen(events.add);
      addTearDown(subscription.cancel);
      await repository.loadGlobal();
      await Future<void>.delayed(Duration.zero);
      expect(events.map((value) => value.global.theme), [
        wire.AppTheme.APP_THEME_SYSTEM,
      ]);
      final write = repository.setGlobal(values: _global(), basedOnRevision: 0);
      await gate.received.future;
      await Future<void>.delayed(Duration.zero);
      expect(repository.pendingGlobal(), isNotNull);
      expect(events, hasLength(1));
      gate.release.complete();
      final confirmed = await write;
      await Future<void>.delayed(Duration.zero);
      expect(confirmed.globalRevision, 1);
      expect(events.map((value) => value.global.theme), [
        wire.AppTheme.APP_THEME_SYSTEM,
        wire.AppTheme.APP_THEME_DARK,
      ]);
    },
  );

  test(
    'closing a session drops late settings ACKs and isolates the next identity',
    () async {
      final gate = _ResponseGate(server);
      client.rebindApi(gate, verifiedIdentity: client.identity);
      final events = <SettingsSnapshot>[];
      final subscription = repository.watchConfirmed().listen(events.add);
      addTearDown(subscription.cancel);
      final write = repository.setGlobal(values: _global(), basedOnRevision: 0);
      final failed = expectLater(write, throwsStateError);
      await gate.received.future;
      expect(repository.pendingGlobal(), isNotNull);
      await client.dispose();
      expect(repository.pendingGlobal(), isNull);
      expect(repository.pendingManga(_key), isNull);
      final nextClient = _client(server.forSubject('other'), subject: 'other');
      addTearDown(nextClient.dispose);
      final next = await SettingsRepository(nextClient).loadGlobal();
      expect(next.globalRevision, 0);
      expect(next.global.theme, wire.AppTheme.APP_THEME_SYSTEM);
      expect(
        () => nextClient.rebindApi(server, verifiedIdentity: _identity()),
        throwsArgumentError,
      );
      gate.release.complete();
      await failed;
      expect(events, isEmpty);
      final originalClient = _client(server);
      addTearDown(originalClient.dispose);
      expect(
        (await SettingsRepository(originalClient).loadGlobal()).global.theme,
        wire.AppTheme.APP_THEME_DARK,
      );
    },
  );
}
