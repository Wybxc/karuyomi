import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/data/source_preferences_repository.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

const _package = 'eu.kanade.source.test';
const _source = '9223372036854775806';
wire.CatalogReference get _catalog => wire.CatalogReference(
  catalogUrl: 'https://reader.example/extensions/index.json',
  repoId: 'keiyoushi',
);
wire.PreferenceEntry _entry(String key, wire.PreferenceValue value) =>
    wire.PreferenceEntry(key: key, value: value);
wire.PreferenceEntry _toggle(bool value) =>
    _entry('enabled', wire.PreferenceValue(boolean: value));
BusinessStateClient _client(ApiFetch api, [String subject = 'owner-subject']) =>
    BusinessStateClient(
      api: api,
      identity: ProgressIdentity(
        origin: Uri.parse('https://reader.example'),
        subject: subject,
      ),
    );

final class _AckGate implements ApiFetch {
  _AckGate(this.api);
  final ApiFetch api;
  final received = Completer<void>();
  final release = Completer<void>();
  @override
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final reply = await api.fetchApi(
      path,
      method: method,
      headers: headers,
      body: body,
    );
    if (method == 'POST') {
      received.complete();
      await release.future;
    }
    return reply;
  }
}

void main() {
  late TestBusinessServer server;
  late BusinessStateClient client;
  late SourcePreferencesRepository repository;
  setUp(() {
    server = TestBusinessServer();
    client = _client(server);
    repository = SourcePreferencesRepository(client);
  });
  tearDown(() => client.dispose());
  List<TestBusinessRequest> writes() => server.requests
      .where(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/api/source-preferences/mutations',
      )
      .toList();
  Future<SourcePreferencesSnapshot> save(
    List<wire.PreferenceEntry> entries, {
    int revision = 0,
    String source = _source,
  }) => repository.save(
    catalog: _catalog,
    packageName: _package,
    sourceId: source,
    basedOnRevision: revision,
    entries: entries,
  );

  test(
    'missing sources have immutable revision zero; full typed replacement preserves false, empty and Long precision',
    () async {
      final first = await repository.load(_package, catalog: _catalog);
      expect(first.sources, isEmpty);
      expect(first.source(_source).revision, 0);
      expect(first.source(_source).isFrozen, true);
      final entries = [
        _toggle(false),
        _entry('text', wire.PreferenceValue(text: '')),
        _entry('int', wire.PreferenceValue(integer: -7)),
        _entry(
          'long',
          wire.decodeProtoJson(wire.PreferenceValue(), {
            'longInteger': '9007199254740993',
          }),
        ),
        _entry('float', wire.PreferenceValue(decimal: 1.5)),
        _entry(
          'set',
          wire.PreferenceValue(strings: wire.PreferenceStringSet()),
        ),
      ];
      final saved = await save(entries);
      expect(saved.source(_source).revision, 1);
      expect(saved.source(_source).entries, hasLength(6));
      final request = jsonDecode(writes().single.body!) as Map<String, Object?>;
      expect(request.toString(), contains('9007199254740993'));
      entries.clear();
      expect(saved.source(_source).entries, hasLength(6));
      final removed = await save([], revision: 1);
      expect(removed.source(_source).revision, 2);
      expect(removed.source(_source).entries, isEmpty);
      expect(server.catalog().categories, isEmpty);
      expect(server.manga('a' * 64), isNull);
    },
  );

  test(
    'lost ACK remains exact across repository replacement and read-only refresh',
    () async {
      server.loseNextResponse = true;
      await expectLater(save([_toggle(true)]), throwsStateError);
      final body = writes().single.body;
      final replacement = SourcePreferencesRepository(client);
      expect(
        replacement
            .pending(_package, _source, catalog: _catalog)!
            .request
            .expectedRevision,
        0,
      );
      expect(
        replacement.pending(_package, _source, catalog: _catalog)!.retryable,
        true,
      );
      expect(
        (await replacement.load(
          _package,
          catalog: _catalog,
        )).source(_source).revision,
        1,
      );
      expect(writes(), hasLength(1));
      expect(
        replacement.pending(_package, _source, catalog: _catalog),
        isNotNull,
      );
      final confirmed = await replacement.retry(
        _package,
        _source,
        catalog: _catalog,
      );
      expect(confirmed.source(_source).revision, 1);
      expect(writes().map((request) => request.body), [body, body]);
      expect(server.appliedMutations, 1);
      expect(repository.pending(_package, _source, catalog: _catalog), isNull);
    },
  );

  test(
    'an old ACK never overwrites newer remote values; rejected drafts clear only on current GET',
    () async {
      server.loseNextResponse = true;
      await expectLater(save([_toggle(true)]), throwsStateError);
      final remote = _client(server);
      addTearDown(remote.dispose);
      await SourcePreferencesRepository(remote).save(
        catalog: _catalog,
        packageName: _package,
        sourceId: _source,
        basedOnRevision: 1,
        entries: [_toggle(false)],
      );
      await expectLater(
        repository.retry(_package, _source, catalog: _catalog),
        throwsA(
          isA<BusinessStateException>().having(
            (failure) => failure.conflict,
            'conflict',
            true,
          ),
        ),
      );
      expect(
        repository.pending(_package, _source, catalog: _catalog)!.retryable,
        false,
      );
      final count = writes().length;
      await expectLater(
        repository.retry(_package, _source, catalog: _catalog),
        throwsA(isA<BusinessStateException>()),
      );
      expect(writes(), hasLength(count));
      final latest = await repository.load(_package, catalog: _catalog);
      expect(latest.source(_source).revision, 2);
      expect(latest.source(_source).entries.single.value.boolean, false);
      expect(repository.pending(_package, _source, catalog: _catalog), isNull);
    },
  );

  test(
    'other sources and reading settings never replay a pending mutation; explicit discard reads before clearing',
    () async {
      server.failWrites = true;
      await expectLater(
        save([_toggle(true)]),
        throwsA(isA<BusinessStateException>()),
      );
      server.failWrites = false;
      final body = writes().single.body;
      await save([_toggle(false)], source: '-123');
      expect(writes(), hasLength(2));
      await repository.load(_package, catalog: _catalog);
      expect(
        repository.pending(_package, _source, catalog: _catalog),
        isNotNull,
      );
      expect(writes().first.body, body);
      expect(repository.pending(_package, '-123', catalog: _catalog), isNull);
      final current = await repository.discard(
        _package,
        _source,
        catalog: _catalog,
      );
      expect(current.source(_source).revision, 0);
      expect(repository.pending(_package, _source, catalog: _catalog), isNull);
      expect(writes(), hasLength(2));
    },
  );

  test(
    'invalid values and response identities do not send or create pending operations',
    () async {
      await expectLater(
        save([_entry('missing', wire.PreferenceValue())]),
        throwsFormatException,
      );
      await expectLater(
        save(
          List.generate(
            129,
            (index) => _entry('$index', wire.PreferenceValue(boolean: false)),
          ),
        ),
        throwsFormatException,
      );
      expect(server.requests, isEmpty);
      expect(repository.pending(_package, _source, catalog: _catalog), isNull);
      server.beforeRequest = (_) => ApiReply(
        status: 200,
        headers: const {'content-type': 'application/json'},
        redirected: false,
        body: jsonEncode(
          wire.encodeProtoJson(
            wire.SourcePreferencesResponse(
              schemaVersion: 1,
              packageName: 'eu.kanade.other',
            ),
          ),
        ),
      );
      await expectLater(
        repository.load(_package, catalog: _catalog),
        throwsFormatException,
      );
      expect(repository.pending(_package, _source, catalog: _catalog), isNull);
    },
  );

  test(
    'closed clients reject late ACKs and the next authenticated identity has independent values',
    () async {
      final gate = _AckGate(server);
      addTearDown(() {
        if (!gate.release.isCompleted) gate.release.complete();
      });
      client.rebindApi(gate, verifiedIdentity: client.identity);
      final writing = save([_toggle(true)]);
      final failed = expectLater(writing, throwsStateError);
      await gate.received.future;
      await client.dispose();
      expect(repository.pending(_package, _source, catalog: _catalog), isNull);
      final next = _client(server.forSubject('other'), 'other');
      addTearDown(next.dispose);
      expect(
        (await SourcePreferencesRepository(
          next,
        ).load(_package, catalog: _catalog)).source(_source).revision,
        0,
      );
      gate.release.complete();
      await failed;
      final original = _client(server);
      addTearDown(original.dispose);
      expect(
        (await SourcePreferencesRepository(original).load(
          _package,
          catalog: _catalog,
        )).source(_source).entries.single.value.boolean,
        true,
      );
    },
  );
}
