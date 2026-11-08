import 'dart:async';

import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';
import 'package:test/test.dart';

import 'support/fake_runtime_transport.dart';

const _package = 'eu.kanade.test';
const _sessionScope =
    wire.PreferenceSyncScope.PREFERENCE_SYNC_SCOPE_CLIENT_SESSION;
const _accountScope = wire.PreferenceSyncScope.PREFERENCE_SYNC_SCOPE_ACCOUNT;

wire.PreferenceEntry _text(String key, String value) => wire.PreferenceEntry(
  key: key,
  value: wire.PreferenceValue(text: value),
);
wire.PreferenceSnapshot _snapshot() => wire.PreferenceSnapshot(
  snapshotId: 'preferences-1',
  nodes: [
    wire.PreferenceNode(
      key: 'flag',
      syncScope: _accountScope,
      defaultValue: wire.PreferenceValue(boolean: false),
      toggle: wire.PreferenceToggle(value: false),
    ),
    wire.PreferenceNode(
      key: 'secret',
      syncScope: _sessionScope,
      text: wire.PreferenceText(secret: true),
    ),
    wire.PreferenceNode(
      key: 'empty',
      syncScope: _sessionScope,
      text: wire.PreferenceText(
        value: '',
        hint: 'https://example.org',
        selectAllOnOpen: true,
      ),
    ),
    // Android can retain a value no longer listed by the current Source.
    wire.PreferenceNode(
      key: 'choice',
      syncScope: _accountScope,
      choice: wire.PreferenceChoice(value: 'old-value', options: []),
    ),
    wire.PreferenceNode(
      key: 'multi',
      syncScope: _accountScope,
      multiChoice: wire.PreferenceMultiChoice(
        values: ['old-value'],
        options: [],
      ),
    ),
    wire.PreferenceNode(
      syncScope: _sessionScope,
      group: wire.PreferenceGroup(
        nodes: [
          wire.PreferenceNode(syncScope: _sessionScope, action: wire.Empty()),
          wire.PreferenceNode(
            syncScope: _sessionScope,
            unsupported: wire.PreferenceUnsupported(
              reason: 'Requires Android Activity',
            ),
          ),
        ],
      ),
    ),
  ],
  syncValues: [
    wire.PreferenceEntry(
      key: 'flag',
      value: wire.PreferenceValue(boolean: false),
    ),
  ],
  sessionValues: [_text('token', 'session-secret')],
);
BuildDescriptor _build([wire.PreferenceBootstrap? bootstrap]) {
  final original = build();
  return BuildDescriptor(
    buildId: original.buildId,
    catalog: original.catalog,
    manifestUri: original.manifestUri,
    sha256: original.sha256,
    identity: original.identity,
    packageId: _package,
    preferenceBootstrap: bootstrap,
  );
}

SourceRequest _get({String generation = 'generation-1'}) => SourceRequest(
  packageId: _package,
  call: wire.SourceCall(
    requestId: 'get-preferences',
    sourceId: sourceId,
    generation: generation,
    getPreferences: wire.Empty(),
  ),
);
SourceRequest _edit({String generation = 'generation-1'}) => SourceRequest(
  packageId: _package,
  call: wire.SourceCall(
    requestId: 'edit-once',
    sourceId: sourceId,
    generation: generation,
    editPreference: wire.PreferenceEditRequest(
      snapshotId: 'preferences-1',
      path: [0],
      change: wire.PreferenceValue(boolean: false),
    ),
  ),
);

void main() {
  test(
    'typed preferences preserve Android int/long/float widths, false, empty values and optional text presence',
    () {
      final values = [
        wire.PreferenceValue(boolean: false),
        wire.PreferenceValue(text: ''),
        wire.PreferenceValue(integer: -2147483648),
        wire.PreferenceValue(
          longInteger: fixnum.Int64.parseInt('9223372036854775807'),
        ),
        wire.PreferenceValue(decimal: 1.5),
        wire.PreferenceValue(strings: wire.PreferenceStringSet(values: [])),
      ];
      final expected = <Map<String, Object?>>[
        {'boolean': false},
        {'text': ''},
        {'integer': -2147483648},
        {'longInteger': '9223372036854775807'},
        {'decimal': 1.5},
        {'strings': <String, Object?>{}},
      ];
      for (var index = 0; index < values.length; index++) {
        wire.validatePreferenceValue(values[index]);
        final json = wire.encodeProtoJson(values[index]);
        expect(json, expected[index]);
        final restored = wire.decodeProtoJson(wire.PreferenceValue(), json);
        expect(restored.whichValue(), values[index].whichValue());
        expect(restored, values[index]);
      }
      final described = _snapshot();
      wire.validatePreferenceSnapshot(described);
      expect(described.nodes[1].text.hasValue(), false);
      expect(described.nodes[2].text.hasValue(), true);
      expect(described.nodes[2].text.value, '');
      final decoded = wire.decodeProtoJson(
        wire.PreferenceSnapshot(),
        wire.encodeProtoJson(described),
      );
      expect(decoded.nodes[2].text.hint, 'https://example.org');
      expect(decoded.nodes[2].text.selectAllOnOpen, true);
      decoded.nodes[2].text.hint = '界' * 171;
      expect(
        () => wire.validatePreferenceSnapshot(decoded),
        throwsFormatException,
      );
      decoded.nodes[2].text.hint = 'secret hint';
      decoded.nodes[2].text.secret = true;
      expect(
        () => wire.validatePreferenceSnapshot(decoded),
        throwsFormatException,
      );
      for (final invalid in [
        wire.PreferenceValue(),
        wire.PreferenceValue(decimal: double.nan),
        wire.PreferenceValue(decimal: double.infinity),
        wire.PreferenceValue(
          strings: wire.PreferenceStringSet(values: ['same', 'same']),
        ),
        wire.PreferenceValue(text: 'x' * 4097),
      ]) {
        expect(
          () => wire.validatePreferenceValue(invalid),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'raw long integers reject overflow, numeric values and conflicting oneofs before nested bootstrap decoding',
    () {
      for (final invalid in <Map<String, Object?>>[
        {'longInteger': '9223372036854775808'},
        {'longInteger': '-9223372036854775809'},
        {'longInteger': 9007199254740992},
        {'longInteger': '1.0'},
        {'integer': 0, 'longInteger': '0'},
      ]) {
        expect(
          () => wire.decodeProtoJson(wire.PreferenceValue(), invalid),
          throwsFormatException,
        );
        expect(
          () => wire.decodeProtoJson(wire.PreferenceBootstrap(), {
            'packageName': _package,
            'sources': [
              {
                'sourceId': sourceId,
                'entries': [
                  {'key': 'long', 'value': invalid},
                ],
              },
            ],
          }),
          throwsFormatException,
        );
      }
      for (final boundary in ['-9223372036854775808', '9223372036854775807']) {
        final value = wire.decodeProtoJson(wire.PreferenceValue(), {
          'longInteger': boundary,
        });
        expect(value.longInteger.toString(), boundary);
        expect(wire.encodeProtoJson(value), {'longInteger': boundary});
      }
    },
  );

  test(
    'descriptions retain unknown selected values and empty options while rejecting invalid secret partitions, defaults and shape',
    () {
      final described = _snapshot();
      expect(() => wire.validatePreferenceSnapshot(described), returnsNormally);
      expect(described.nodes[3].choice.options, isEmpty);
      expect(described.nodes[3].choice.value, 'old-value');
      expect(described.nodes[4].multiChoice.values, ['old-value']);
      for (final invalid in [
        _snapshot()..nodes[1].syncScope = _accountScope,
        _snapshot()
          ..nodes[0].defaultValue = wire.PreferenceValue(text: 'false'),
        _snapshot()
          ..sessionValues.add(
            wire.PreferenceEntry(
              key: 'flag',
              value: wire.PreferenceValue(boolean: true),
            ),
          ),
        _snapshot()..nodes.add(wire.PreferenceNode(syncScope: _sessionScope)),
        _snapshot()..nodes[5].group.nodes[1].unsupported.reason = '',
        _snapshot()..nodes[0].title = 'x' * 513,
      ]) {
        expect(
          () => wire.validatePreferenceSnapshot(invalid),
          throwsFormatException,
        );
      }
      var leaf = wire.PreferenceNode(
        key: 'leaf',
        syncScope: _sessionScope,
        toggle: wire.PreferenceToggle(),
      );
      for (var depth = 1; depth < 8; depth++) {
        leaf = wire.PreferenceNode(
          syncScope: _sessionScope,
          group: wire.PreferenceGroup(nodes: [leaf]),
        );
      }
      expect(
        () => wire.validatePreferenceSnapshot(
          wire.PreferenceSnapshot(snapshotId: 'depth', nodes: [leaf]),
        ),
        returnsNormally,
      );
      expect(
        () => wire.validatePreferenceSnapshot(
          wire.PreferenceSnapshot(
            snapshotId: 'depth',
            nodes: [
              wire.PreferenceNode(
                syncScope: _sessionScope,
                group: wire.PreferenceGroup(nodes: [leaf]),
              ),
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => wire.validatePreferenceEditResult(
          wire.PreferenceEditResult(accepted: true),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'entries and bootstrap enforce per-source and aggregate UTF-8 budgets without an artificial 512-entry limit',
    () {
      final small = wire.PreferenceBootstrap(
        packageName: _package,
        sources: List.generate(
          8,
          (source) => wire.SourcePreferenceValues(
            sourceId: '$source',
            entries: List.generate(
              100,
              (key) => wire.PreferenceEntry(
                key: '$key',
                value: wire.PreferenceValue(boolean: false),
              ),
            ),
          ),
        ),
      );
      expect(() => wire.validatePreferenceBootstrap(small), returnsNormally);
      final large = wire.PreferenceEntry(
        key: 'set',
        value: wire.PreferenceValue(
          strings: wire.PreferenceStringSet(
            values: List.generate(7, (index) => '$index${'字' * 1199}'),
          ),
        ),
      );
      final bootstrap = wire.PreferenceBootstrap(
        packageName: _package,
        sources: [
          wire.SourcePreferenceValues(sourceId: '1', entries: [large]),
          wire.SourcePreferenceValues(
            sourceId: '2',
            entries: [large.deepCopy()],
          ),
        ],
      );
      expect(
        () => wire.validatePreferenceBootstrap(bootstrap),
        returnsNormally,
      );
      bootstrap.sources.add(
        wire.SourcePreferenceValues(sourceId: '3', entries: [large.deepCopy()]),
      );
      expect(
        () => wire.validatePreferenceBootstrap(bootstrap),
        throwsFormatException,
      );
      final oversized = wire.PreferenceEntry(
        key: 'big',
        value: wire.PreferenceValue(
          strings: wire.PreferenceStringSet(
            values: List.generate(9, (index) => '$index${'x' * 4095}'),
          ),
        ),
      );
      for (final entries in [
        [oversized],
        [wire.PreferenceEntry(key: 'missing')],
        [_text('same', ''), _text('same', 'other')],
        List.generate(129, (index) => _text('$index', '')),
      ]) {
        expect(
          () => wire.validatePreferenceEntries(entries),
          throwsFormatException,
        );
      }
      for (final invalid in [
        wire.PreferenceBootstrap(packageName: 'invalid'),
        wire.PreferenceBootstrap(
          packageName: _package,
          sources: [
            wire.SourcePreferenceValues(sourceId: '9223372036854775808'),
          ],
        ),
        wire.PreferenceBootstrap(
          packageName: _package,
          sources: [
            wire.SourcePreferenceValues(sourceId: '1'),
            wire.SourcePreferenceValues(sourceId: '1'),
          ],
        ),
        wire.PreferenceBootstrap(
          packageName: _package,
          sources: List.generate(
            65,
            (index) => wire.SourcePreferenceValues(sourceId: '$index'),
          ),
        ),
      ]) {
        expect(
          () => wire.validatePreferenceBootstrap(invalid),
          throwsFormatException,
        );
      }
    },
  );

  test('bootstrap validates typed account rules alongside session values', () {
    const textKind = wire.PreferenceValueKind.PREFERENCE_VALUE_KIND_TEXT;
    final rule = wire.PreferenceSyncRule(key: 'appearance', kind: textKind);
    final scoped = wire.PreferenceSyncRule(
      key: 'appearance',
      kind: textKind,
      sourceId: '-9223372036854775808',
    );
    final bootstrap = wire.PreferenceBootstrap(
      packageName: _package,
      syncRules: [rule, scoped],
      sources: [
        wire.SourcePreferenceValues(
          sourceId: scoped.sourceId,
          entries: [_text('session-token', 'local-only')],
        ),
      ],
    );
    expect(() => wire.validatePreferenceBootstrap(bootstrap), returnsNormally);
    for (final rules in [
      [rule, rule.deepCopy()],
      [wire.PreferenceSyncRule(key: 'appearance')],
      [wire.PreferenceSyncRule(key: '', kind: textKind)],
      [scoped.deepCopy()..sourceId = '9223372036854775808'],
      [scoped.deepCopy()..sourceId = ''],
      List.generate(
        129,
        (i) => wire.PreferenceSyncRule(key: '$i', kind: textKind),
      ),
    ]) {
      bootstrap.syncRules
        ..clear()
        ..addAll(rules);
      expect(
        () => wire.validatePreferenceBootstrap(bootstrap),
        throwsFormatException,
      );
    }
  });

  test(
    'edit requests preserve click and explicit typed state while rejecting missing commands and invalid paths',
    () {
      expect(
        () => wire.validatePreferenceEditRequest(
          wire.PreferenceEditRequest(
            snapshotId: 'p',
            path: [0],
            click: wire.Empty(),
          ),
        ),
        returnsNormally,
      );
      expect(
        () => wire.validatePreferenceEditRequest(
          wire.PreferenceEditRequest(
            snapshotId: 'p',
            path: [0],
            change: wire.PreferenceValue(text: ''),
          ),
        ),
        returnsNormally,
      );
      for (final invalid in [
        wire.PreferenceEditRequest(
          snapshotId: 'p',
          path: [],
          click: wire.Empty(),
        ),
        wire.PreferenceEditRequest(
          snapshotId: 'p',
          path: [256],
          click: wire.Empty(),
        ),
        wire.PreferenceEditRequest(
          snapshotId: 'p',
          path: List.filled(9, 0),
          click: wire.Empty(),
        ),
        wire.PreferenceEditRequest(snapshotId: 'p', path: [0]),
        wire.PreferenceEditRequest(
          snapshotId: 'p',
          path: [0],
          change: wire.PreferenceValue(),
        ),
      ]) {
        expect(
          () => wire.validatePreferenceEditRequest(invalid),
          throwsFormatException,
        );
      }
      expect(
        () => wire.decodeProtoJson(wire.PreferenceEditRequest(), {
          'snapshotId': 'p',
          'path': [0],
          'click': <String, Object?>{},
          'change': {'boolean': false},
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'formal descriptor replies are validated before exposure and invalid edits do not dirty or reach transport',
    () async {
      final transport = FakeTransport();
      var described = _snapshot();
      transport.handler = (call) async {
        final response = transport.respond(call);
        if (call.hasInvoke()) response.source.preferences = described;
        return response;
      };
      final runtime = TransportSourceRuntime(transport);
      addTearDown(runtime.dispose);
      await runtime.open(_build());
      final result = await runtime.invoke(_get());
      expect(result.whichPayload(), wire.SourceResult_Payload.preferences);
      expect(result.preferences, _snapshot());
      expect(result.isFrozen, true);
      final invalid = _edit()..call.editPreference.path.clear();
      final controls = transport.calls.length;
      await expectLater(
        runtime.invoke(invalid),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(transport.calls, hasLength(controls));
      described = _snapshot()..nodes[1].syncScope = _accountScope;
      await expectLater(
        runtime.invoke(_get()),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      described = _snapshot();
      expect((await runtime.invoke(_get())).preferences, described);
    },
  );

  test(
    'open copies bootstrap before awaiting ready and changed values are sent through a new open',
    () async {
      final transport = FakeTransport();
      final entered = Completer<void>(), release = Completer<void>();
      var firstReady = true, opens = 0;
      transport.handler = (call) async {
        if (call.hasReady() && firstReady) {
          firstReady = false;
          entered.complete();
          await release.future;
        }
        final response = transport.respond(call);
        if (call.hasOpen()) {
          response.session.generation = 'generation-${++opens}';
        }
        return response;
      };
      final runtime = TransportSourceRuntime(transport);
      addTearDown(runtime.dispose);
      final bootstrap = wire.PreferenceBootstrap(
        packageName: _package,
        sources: [
          wire.SourcePreferenceValues(
            sourceId: sourceId,
            entries: [
              _text('mirror', '1'),
              wire.PreferenceEntry(
                key: 'long',
                value: wire.PreferenceValue(
                  longInteger: fixnum.Int64.parseInt('9223372036854775807'),
                ),
              ),
            ],
          ),
        ],
      );
      final opening = runtime.open(_build(bootstrap));
      await entered.future;
      bootstrap.sources.first.entries.first.value.text = 'changed-after-open';
      release.complete();
      final first = await opening;
      final sent = transport.calls
          .singleWhere((call) => call.hasOpen())
          .open
          .preferenceBootstrap;
      expect(sent.sources.first.entries.first.value.text, '1');
      expect(
        sent.sources.first.entries.last.value.longInteger.toString(),
        '9223372036854775807',
      );
      final second = await runtime.open(_build(bootstrap));
      expect(second.generation, isNot(first.generation));
      expect(opens, 2);
      expect(
        transport
            .calls
            .last
            .open
            .preferenceBootstrap
            .sources
            .first
            .entries
            .first
            .value
            .text,
        'changed-after-open',
      );
      expect(await runtime.open(_build(bootstrap)), same(second));
      expect(opens, 2);
    },
  );

  for (final outcome in ['accepted', 'vetoed', 'failed']) {
    test(
      '$outcome edit dispatches once and gates Source/image work until reopen while cleanup remains available',
      () async {
        final transport = FakeTransport();
        final editEntered = Completer<void>();
        final editResult = Completer<void>();
        var opens = 0;
        transport.handler = (call) async {
          final response = transport.respond(call);
          if (call.hasOpen()) {
            response.session.generation = 'generation-${++opens}';
          }
          if (call.hasInvoke()) {
            response.source.generation = 'generation-$opens';
            if (call.invoke.hasEditPreference()) {
              editEntered.complete();
              await editResult.future;
              if (outcome == 'failed') {
                return wire.ControlResponse(
                  slotId: call.slotId,
                  requestId: call.requestId,
                  error: wire.RuntimeError(
                    code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_SOURCE_ERROR,
                    message: 'Listener failed after writing storage',
                  ),
                );
              }
              response.source.preferenceEdit = wire.PreferenceEditResult(
                accepted: outcome == 'accepted',
                snapshot: _snapshot(),
              );
            } else {
              response.source.preferences = _snapshot();
            }
          }
          return response;
        };
        final runtime = TransportSourceRuntime(transport);
        addTearDown(runtime.dispose);
        final first = await runtime.open(_build());
        final original = _edit();
        final editing = runtime.invoke(original);
        final checked = outcome == 'failed'
            ? expectLater(
                editing,
                throwsA(failure(RuntimeErrorCode.sourceError)),
              )
            : expectLater(
                editing,
                completion(
                  isA<wire.SourceResult>().having(
                    (result) => result.preferenceEdit.accepted,
                    'accepted',
                    outcome == 'accepted',
                  ),
                ),
              );
        await editEntered.future;
        original.call.editPreference.change.boolean = true;
        expect(
          transport.calls.last.invoke.editPreference.change.boolean,
          false,
        );
        final controls = transport.calls.length;
        await expectLater(
          runtime.invoke(_get()),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
        await expectLater(
          runtime.invoke(_edit()),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
        await expectLater(
          runtime.acquireImage(imageRequest()),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
        expect(transport.calls, hasLength(controls));
        await runtime.cancelImage(
          const ImageCancelRequest(
            requestId: 'old-image',
            generation: 'generation-1',
          ),
        );
        await runtime.releaseImage(
          const ImageReleaseRequest(
            resourceId: 'old-resource',
            generation: 'generation-1',
          ),
        );
        await runtime.closePageSession(
          const PageSessionRef(
            pageSessionId: 'pages-1',
            generation: 'generation-1',
          ),
        );
        expect(
          transport.calls.skip(controls).map((call) => call.whichCommand()),
          [
            wire.ControlRequest_Command.cancelImage,
            wire.ControlRequest_Command.releaseImage,
            wire.ControlRequest_Command.closePageSession,
          ],
        );
        editResult.complete();
        await checked;
        await expectLater(
          runtime.invoke(_get()),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
        expect(
          transport.calls.where(
            (call) => call.hasInvoke() && call.invoke.hasEditPreference(),
          ),
          hasLength(1),
        );
        final second = await runtime.open(_build());
        expect(second.generation, isNot(first.generation));
        expect(
          (await runtime.invoke(
            _get(generation: second.generation),
          )).preferences,
          _snapshot(),
        );
        final beforeOldCall = transport.calls.length;
        await expectLater(
          runtime.invoke(_get()),
          throwsA(failure(RuntimeErrorCode.runtimeLost)),
        );
        expect(transport.calls, hasLength(beforeOldCall));
      },
    );
  }

  test(
    'discarding an in-flight edit reopens confirmed values and a late old result cannot replace the new generation',
    () async {
      final transport = FakeTransport();
      final entered = Completer<void>(), finish = Completer<void>();
      var opens = 0;
      transport.handler = (call) async {
        final response = transport.respond(call);
        if (call.hasOpen()) {
          response.session.generation = 'generation-${++opens}';
        }
        if (call.hasInvoke()) {
          response.source.generation = call.invoke.generation;
          if (call.invoke.hasEditPreference()) {
            entered.complete();
            await finish.future;
            response.source.preferenceEdit = wire.PreferenceEditResult(
              accepted: true,
              snapshot: _snapshot(),
            );
          } else {
            response.source.preferences = _snapshot();
          }
        }
        return response;
      };
      final runtime = TransportSourceRuntime(transport);
      addTearDown(runtime.dispose);
      await runtime.open(_build());
      final original = expectLater(
        runtime.invoke(_edit()),
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      await entered.future;
      final confirmed = await runtime.open(_build());
      expect(confirmed.generation, 'generation-2');
      finish.complete();
      await original;
      expect(
        (await runtime.invoke(
          _get(generation: confirmed.generation),
        )).generation,
        confirmed.generation,
      );
      expect(
        transport.calls.where(
          (call) => call.hasInvoke() && call.invoke.hasEditPreference(),
        ),
        hasLength(1),
      );
    },
  );
}
