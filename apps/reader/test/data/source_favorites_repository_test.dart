import '../test_app.dart';
import '../settings/settings_fixture.dart';

import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

wire.FavoriteSource _source(String packageName) => wire.FavoriteSource(
  packageName: packageName,
  sourceId: '9223372036854775806',
  sourceName: '同名源',
  sourceLang: 'zh',
);

wire.GlobalSettingsValues _values({
  Iterable<wire.FavoriteSource> favorites = const [],
}) => wire.GlobalSettingsValues(
  theme: wire.AppTheme.APP_THEME_DARK,
  reader: wire.ReaderSettings(
    mode: wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
    pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
    background: wire.ReaderBackground.READER_BACKGROUND_THEME,
    dimPercent: 30,
    fit: wire.ReaderFit.READER_FIT_WIDTH,
    cropBorders: true,
    tapZones: wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED,
    keyboard: wire.ReaderInputPreset.READER_INPUT_PRESET_DISABLED,
  ),
  favoriteSources: favorites,
);

BusinessStateClient _client(ApiFetch api, {String subject = 'owner-subject'}) =>
    BusinessStateClient(
      api: api,
      identity: ProgressIdentity(
        origin: Uri.parse('https://reader.example'),
        subject: subject,
      ),
    );

List<TestBusinessRequest> _writes(TestBusinessServer server) =>
    server.requests.where((request) => request.method == 'POST').toList();

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
    final response = await api.fetchApi(
      path,
      method: method,
      headers: headers,
      body: body,
    );
    if (hold) {
      received.complete();
      await release.future;
    }
    return response;
  }
}

void main() {
  late TestBusinessServer server;
  late BusinessStateClient client;
  late SettingsRepository repository;
  late SettingsFixture fixture;

  setUp(() {
    server = TestBusinessServer();
    client = _client(server);
    repository = SettingsRepository(client);
  });
  tearDown(() => client.dispose());
  Future<void> attachFixture() async {
    await client.dispose();
    fixture = SettingsFixture(server: server);
    await fixture.connect();
    repository = fixture.catalog.settings!;
    client = repository.client;
    addTearDown(fixture.dispose);
  }

  test('source favorites round-trip across clients, isolate subjects and distinguish packages with the same source ID', () async {
    final a = _source('source.a');
    final b = _source('source.b');
    final original = _values(favorites: [a, b]);
    await repository.setGlobal(values: original, basedOnRevision: 0);
    final remoteClient = _client(server);
    addTearDown(remoteClient.dispose);
    final remote = SettingsRepository(remoteClient);
    final loaded = await remote.loadGlobal();
    expect(loaded.global, original);
    expect(loaded.global.favoriteSources, [a, b]);
    final removed = loaded.global.deepCopy();
    removed.favoriteSources.removeWhere(
      (source) =>
          source.packageName == a.packageName && source.sourceId == a.sourceId,
    );
    await remote.setGlobal(
      values: removed,
      basedOnRevision: loaded.globalRevision,
    );
    final current = await repository.loadGlobal();
    expect(current.global.favoriteSources, [b]);
    expect(current.global.theme, original.theme);
    expect(current.global.reader, original.reader);
    expect(current.globalRevision, 2);
    final otherClient = _client(server.forSubject('other'), subject: 'other');
    addTearDown(otherClient.dispose);
    final other = await SettingsRepository(otherClient).loadGlobal();
    expect(other.global.favoriteSources, isEmpty);
    expect(other.global.theme, wire.AppTheme.APP_THEME_SYSTEM);
    expect(other.globalRevision, 0);
    expect(server.appliedMutations, 2);
  });

  test('lost favorite ACK survives repository and controller recreation with the original UUID body and CAS', () async {
    await attachFixture();
    var controller = fixture.editor();
    expect(await controller.refresh(), true);
    final favorite = _values(favorites: [_source('source.a')]);
    server.loseNextResponse = true;
    expect(await controller.saveGlobal(favorite, 0), false);
    final original = _writes(server).single.body!;
    final sent = wire.decodeProtoJson(
      wire.SettingsMutation(),
      jsonDecode(original),
    );
    expect(
      sent.mutationId,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(sent.expectedRevision, 0);
    expect(fixture.state().pending!.global, favorite);
    fixture.invalidate();
    final recreated = SettingsRepository(client);
    controller = fixture.editor();
    expect(await controller.refresh(), true);
    expect(_writes(server), hasLength(1));
    expect(fixture.state().pending!.global, favorite);
    expect(fixture.state().pending!.basedOnRevision, 0);
    expect(fixture.state().canEdit, false);
    expect(fixture.state().canRetry, true);
    final changed = favorite.deepCopy()..favoriteSources.clear();
    await expectLater(
      recreated.setGlobal(values: changed, basedOnRevision: 1),
      throwsStateError,
    );
    expect(_writes(server), hasLength(1));
    expect(await controller.retry(), true);
    expect(_writes(server).map((request) => request.body), [
      original,
      original,
    ]);
    expect(fixture.state().snapshot!.global, favorite);
    expect(fixture.state().snapshot!.globalRevision, 1);
    expect(fixture.state().pending, isNull);
    expect(server.appliedMutations, 1);
  });

  test('a stale favorite edit cannot overwrite another client global preferences or canceled favorites', () async {
    final initial = await repository.setGlobal(
      values: _values(favorites: [_source('source.a')]),
      basedOnRevision: 0,
    );
    final remoteClient = _client(server);
    addTearDown(remoteClient.dispose);
    final remote = SettingsRepository(remoteClient);
    final remotelyChanged = initial.global.deepCopy()
      ..theme = wire.AppTheme.APP_THEME_LIGHT
      ..favoriteSources.clear();
    remotelyChanged.reader.mode = wire.ReaderMode.READER_MODE_CONTINUOUS;
    await remote.setGlobal(values: remotelyChanged, basedOnRevision: 1);
    final stale = initial.global.deepCopy()
      ..favoriteSources.add(_source('source.b'));
    await expectLater(
      repository.setGlobal(
        values: stale,
        basedOnRevision: initial.globalRevision,
      ),
      throwsA(
        isA<BusinessStateException>().having(
          (error) => error.conflict,
          'conflict',
          true,
        ),
      ),
    );
    expect(repository.pendingGlobal()!.retryable, false);
    final count = _writes(server).length;
    await expectLater(
      repository.setGlobal(
        values: stale,
        basedOnRevision: initial.globalRevision,
      ),
      throwsA(isA<BusinessStateException>()),
    );
    expect(_writes(server), hasLength(count));
    final current = await repository.loadGlobal();
    expect(current.global, remotelyChanged);
    expect(current.global.favoriteSources, isEmpty);
    expect(current.globalRevision, 2);
    expect(repository.pendingGlobal(), isNull);
    expect(server.appliedMutations, 2);
  });

  test(
    'an old favorite ACK cannot resurrect a source canceled by another client',
    () async {
      final added = _values(favorites: [_source('source.a')]);
      final events = <SettingsSnapshot>[];
      final subscription = repository.watchConfirmed().listen(events.add);
      addTearDown(subscription.cancel);
      await repository.loadGlobal();
      server.loseNextResponse = true;
      await expectLater(
        repository.setGlobal(values: added, basedOnRevision: 0),
        throwsStateError,
      );
      final original = _writes(server).single.body;
      final remoteClient = _client(server);
      addTearDown(remoteClient.dispose);
      final remote = SettingsRepository(remoteClient);
      final remoteSnapshot = await remote.loadGlobal();
      final canceled = remoteSnapshot.global.deepCopy()
        ..favoriteSources.clear();
      await remote.setGlobal(
        values: canceled,
        basedOnRevision: remoteSnapshot.globalRevision,
      );
      await expectLater(
        repository.setGlobal(values: added, basedOnRevision: 0),
        throwsA(
          isA<BusinessStateException>().having(
            (error) => error.conflict,
            'conflict',
            true,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(_writes(server).map((request) => request.body), [
        original,
        _writes(server)[1].body,
        original,
      ]);
      expect(events, isNotEmpty);
      expect(
        events.every((event) => event.global.favoriteSources.isEmpty),
        true,
      );
      expect(events.last.globalRevision, 2);
      expect(repository.pendingGlobal()!.retryable, false);
      final current = await repository.loadGlobal();
      expect(current.global, canceled);
      expect(current.globalRevision, 2);
      expect(repository.pendingGlobal(), isNull);
      expect(server.appliedMutations, 2);
    },
  );

  test('closing the identity rejects late favorite ACKs and leaves another subject empty', () async {
    final gate = _ResponseGate(server);
    addTearDown(() {
      if (!gate.release.isCompleted) gate.release.complete();
    });
    client.rebindApi(gate, verifiedIdentity: client.identity);
    final events = <SettingsSnapshot>[];
    final subscription = repository.watchConfirmed().listen(events.add);
    addTearDown(subscription.cancel);
    final write = repository.setGlobal(
      values: _values(favorites: [_source('source.a')]),
      basedOnRevision: 0,
    );
    final rejected = expectLater(write, throwsStateError);
    await gate.received.future;
    expect(repository.pendingGlobal(), isNotNull);
    await client.dispose();
    expect(repository.pendingGlobal(), isNull);
    final otherClient = _client(server.forSubject('other'), subject: 'other');
    addTearDown(otherClient.dispose);
    final other = await SettingsRepository(otherClient).loadGlobal();
    expect(other.global.favoriteSources, isEmpty);
    expect(other.globalRevision, 0);
    gate.release.complete();
    await rejected;
    expect(events, isEmpty);
    final sameIdentity = _client(server);
    addTearDown(sameIdentity.dispose);
    expect(
      (await SettingsRepository(
        sameIdentity,
      ).loadGlobal()).global.favoriteSources,
      [_source('source.a')],
    );
  });

  testWidgets(
    'editing the global theme preserves source favorites and reader preferences',
    (tester) async {
      await attachFixture();
      tester.view.physicalSize = const Size(480, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = _values(
        favorites: [_source('source.a'), _source('source.b')],
      );
      await tester.runAsync(
        () => repository.setGlobal(values: original, basedOnRevision: 0),
      );
      final controller = fixture.editor();
      await tester.runAsync(controller.refresh);
      await tester.pumpApp(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: GlobalSettingsPanel(catalog: fixture.catalog),
            ),
          ),
        ),
        container: fixture.container,
      );
      await tester.pumpAndSettle();
      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.runAsync(() async {
          await tester.tap(finder);
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
      }

      await tap(find.byType(DropdownButtonFormField<wire.AppTheme>));
      await tap(find.text('浅色').last);
      await tap(find.text('保存全局设置'));
      final current = await tester.runAsync(repository.loadGlobal);
      expect(current!.global.theme, wire.AppTheme.APP_THEME_LIGHT);
      expect(current.global.reader, original.reader);
      expect(current.global.favoriteSources, original.favoriteSources);
      final sent = wire.decodeProtoJson(
        wire.SettingsMutation(),
        jsonDecode(_writes(server).last.body!),
      );
      expect(sent.setGlobal.favoriteSources, original.favoriteSources);
      expect(tester.takeException(), isNull);
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
