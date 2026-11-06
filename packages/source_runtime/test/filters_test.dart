import 'dart:async';

import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';
import 'package:test/test.dart';

import 'support/fake_runtime_transport.dart';

wire.FilterSnapshot snapshot() => wire.FilterSnapshot(
  snapshotId: 'filters-1',
  nodes: [
    wire.FilterNode(name: 'Filters', header: wire.Empty()),
    wire.FilterNode(separator: wire.Empty()),
    wire.FilterNode(
      name: 'Title',
      text: wire.FilterText(state: ''),
    ),
    wire.FilterNode(
      name: 'Available',
      checkBox: wire.FilterCheckBox(state: false),
    ),
    wire.FilterNode(name: 'Status', triState: wire.FilterTriState(state: 0)),
    wire.FilterNode(
      name: 'Language',
      select: wire.FilterSelect(options: ['日本語', 'English'], state: 0),
    ),
    wire.FilterNode(
      name: 'Sort',
      sort: wire.FilterSort(
        options: ['Updated', 'Name'],
        state: wire.FilterSortState(),
      ),
    ),
    wire.FilterNode(
      name: 'Tags',
      group: wire.FilterGroup(
        nodes: [
          wire.FilterNode(
            name: 'Fantasy',
            checkBox: wire.FilterCheckBox(state: true),
          ),
          wire.FilterNode(
            name: 'Selected sort',
            sort: wire.FilterSort(
              options: ['Updated'],
              state: wire.FilterSortState(
                selection: wire.FilterSortSelection(index: 0, ascending: false),
              ),
            ),
          ),
        ],
      ),
    ),
  ],
);
wire.FilterSelection selection() => wire.FilterSelection(
  snapshotId: 'filters-1',
  updates: [
    wire.FilterUpdate(path: [2], text: ''),
    wire.FilterUpdate(path: [3], checkBox: false),
    wire.FilterUpdate(path: [4], triState: 0),
    wire.FilterUpdate(path: [5], select: 0),
    wire.FilterUpdate(path: [6], sort: wire.FilterSortState()),
    wire.FilterUpdate(path: [7, 0], checkBox: true),
    wire.FilterUpdate(
      path: [7, 1],
      sort: wire.FilterSortState(
        selection: wire.FilterSortSelection(index: 0, ascending: false),
      ),
    ),
  ],
);
SourceRequest filterRequest({
  wire.GetFiltersRequest? get,
  wire.SearchRequest? search,
}) => SourceRequest(
  packageId: 'package-1',
  call: wire.SourceCall(
    requestId: 'filters-request',
    sourceId: sourceId,
    generation: 'generation-1',
    getFilters: get,
    search: search,
  ),
);

void main() {
  for (final retired in [true, false]) {
    test(
      '${retired ? 'active Source cancellation reports runtime loss' : 'queued Source cancellation completes'} through the formal control response',
      () async {
        final transport = FakeTransport();
        final runtime = TransportSourceRuntime(transport);
        addTearDown(runtime.dispose);
        final events = <RuntimeEvent>[];
        final subscription = runtime.events.listen(events.add);
        addTearDown(subscription.cancel);
        await runtime.open(build());
        final entered = Completer<void>();
        final finish = Completer<void>();
        transport.handler = (call) async {
          if (call.hasInvoke() && call.invoke.hasGetFilters()) {
            entered.complete();
            await finish.future;
            return wire.ControlResponse(
              requestId: call.requestId,
              error: wire.RuntimeError(
                code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_CANCELLED,
                message: 'Original Source request was cancelled',
              ),
            );
          }
          if (retired && call.hasCancel()) {
            return wire.ControlResponse(
              requestId: call.requestId,
              error: wire.RuntimeError(
                code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST,
                message: 'Active Source cancellation retired the Worker',
              ),
            );
          }
          return transport.respond(call);
        };
        final original = expectLater(
          runtime.invoke(filterRequest(get: wire.GetFiltersRequest())),
          throwsA(failure(RuntimeErrorCode.cancelled)),
        );
        await entered.future;
        if (retired) {
          await expectLater(
            runtime.cancel('filters-request'),
            throwsA(failure(RuntimeErrorCode.runtimeLost)),
          );
          final controls = transport.calls.length;
          await expectLater(
            runtime.invoke(request()),
            throwsA(failure(RuntimeErrorCode.runtimeLost)),
          );
          expect(transport.calls, hasLength(controls));
        } else {
          await runtime.cancel('filters-request');
        }
        finish.complete();
        await original;
        await Future<void>.delayed(Duration.zero);
        expect(
          events.where((event) => event.code == RuntimeErrorCode.runtimeLost),
          hasLength(retired ? 1 : 0),
        );
        transport.handler = null;
        if (retired) await runtime.open(build());
        expect(
          (await runtime.invoke(request())).whichPayload(),
          wire.SourceResult_Payload.mangaPage,
        );
        expect(
          transport.calls.where((call) => call.hasOpen()),
          hasLength(retired ? 2 : 1),
        );
      },
    );
  }

  test(
    'formal filter RPC preserves all typed nodes and explicit zero/false/null state through search',
    () async {
      final transport = FakeTransport();
      transport.handler = (call) async {
        final reply = transport.respond(call);
        if (call.hasInvoke() && call.invoke.hasGetFilters()) {
          reply.source.filters = snapshot();
        }
        return reply;
      };
      final runtime = TransportSourceRuntime(transport);
      addTearDown(runtime.dispose);
      await runtime.open(build());
      final result = await runtime.invoke(
        filterRequest(
          get: wire.GetFiltersRequest(retainedSnapshotId: 'filters-1'),
        ),
      );
      expect(result.whichPayload(), wire.SourceResult_Payload.filters);
      expect(result.filters.nodes.map((node) => node.whichKind()), [
        wire.FilterNode_Kind.header,
        wire.FilterNode_Kind.separator,
        wire.FilterNode_Kind.text,
        wire.FilterNode_Kind.checkBox,
        wire.FilterNode_Kind.triState,
        wire.FilterNode_Kind.select,
        wire.FilterNode_Kind.sort,
        wire.FilterNode_Kind.group,
      ]);
      expect(result.filters.nodes[6].sort.hasState(), true);
      expect(result.filters.nodes[6].sort.state.hasSelection(), false);
      final selectedSort = result.filters.nodes[7].group.nodes[1].sort.state;
      expect(selectedSort.hasSelection(), true);
      expect(selectedSort.selection.index, 0);
      expect(selectedSort.selection.ascending, false);
      expect(
        transport.calls.last.invoke.getFilters.retainedSnapshotId,
        'filters-1',
      );

      final selected = selection();
      final page = await runtime.invoke(
        filterRequest(
          search: wire.SearchRequest(page: 1, query: '', filters: selected),
        ),
      );
      expect(page.whichPayload(), wire.SourceResult_Payload.mangaPage);
      final sent = transport.calls.last.invoke.search;
      expect(sent.query, '');
      expect(sent.filters, selected);
      expect(
        sent.filters.updates[1].whichState(),
        wire.FilterUpdate_State.checkBox,
      );
      expect(sent.filters.updates[1].checkBox, false);
      expect(
        sent.filters.updates[2].whichState(),
        wire.FilterUpdate_State.triState,
      );
      expect(sent.filters.updates[2].triState, 0);
      expect(
        sent.filters.updates[3].whichState(),
        wire.FilterUpdate_State.select,
      );
      expect(sent.filters.updates[3].select, 0);
      expect(
        sent.filters.updates[4].whichState(),
        wire.FilterUpdate_State.sort,
      );
      expect(sent.filters.updates[4].sort.hasSelection(), false);
      expect(sent.filters.updates.last.sort.hasSelection(), true);
    },
  );

  test(
    'malformed filter descriptions fail before exposure and invalid selections never reach transport',
    () async {
      final transport = FakeTransport();
      var described = snapshot();
      transport.handler = (call) async {
        final reply = transport.respond(call);
        if (call.hasInvoke()) reply.source.filters = described;
        return reply;
      };
      final runtime = TransportSourceRuntime(transport);
      addTearDown(runtime.dispose);
      await runtime.open(build());
      for (final invalid in [
        snapshot()..nodes[6].sort.clearState(),
        snapshot()..nodes[4].triState.state = 3,
        snapshot()..nodes.add(wire.FilterNode(name: 'Unknown')),
      ]) {
        described = invalid;
        await expectLater(
          runtime.invoke(filterRequest(get: wire.GetFiltersRequest())),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
      }
      final before = transport.calls.length;
      final duplicate = selection()
        ..updates.add(wire.FilterUpdate(path: [3], checkBox: true));
      await expectLater(
        runtime.invoke(
          filterRequest(
            search: wire.SearchRequest(page: 1, filters: duplicate),
          ),
        ),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      await expectLater(
        runtime.invoke(
          filterRequest(get: wire.GetFiltersRequest(retainedSnapshotId: '')),
        ),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(transport.calls, hasLength(before));
    },
  );

  test(
    'filter trees and selections enforce matching bounded typed states and UTF-8 budgets',
    () {
      expect(() => wire.validateFilterSnapshot(snapshot()), returnsNormally);
      expect(() => wire.validateFilterSelection(selection()), returnsNormally);
      for (final invalid in [
        snapshot()..snapshotId = '',
        snapshot()..snapshotId = 'x' * 201,
        snapshot()..nodes.first.name = 'x' * 513,
        snapshot()..nodes[2].text.state = 'x' * 4097,
        snapshot()..nodes[5].select.options.clear(),
        snapshot()..nodes[5].select.state = 2,
        snapshot()
          ..nodes[6].sort.state.selection = wire.FilterSortSelection(index: 2),
        wire.FilterSnapshot(
          snapshotId: 'f',
          nodes: List.generate(
            257,
            (_) => wire.FilterNode(header: wire.Empty()),
          ),
        ),
        wire.FilterSnapshot(
          snapshotId: 'f',
          nodes: [
            wire.FilterNode(
              select: wire.FilterSelect(options: List.filled(256, '界' * 512)),
            ),
          ],
        ),
      ]) {
        expect(
          () => wire.validateFilterSnapshot(invalid),
          throwsFormatException,
        );
      }
      var leaf = wire.FilterNode(text: wire.FilterText());
      for (var depth = 1; depth < 8; depth++) {
        leaf = wire.FilterNode(group: wire.FilterGroup(nodes: [leaf]));
      }
      expect(
        () => wire.validateFilterSnapshot(
          wire.FilterSnapshot(snapshotId: 'f', nodes: [leaf]),
        ),
        returnsNormally,
      );
      expect(
        () => wire.validateFilterSnapshot(
          wire.FilterSnapshot(
            snapshotId: 'f',
            nodes: [
              wire.FilterNode(group: wire.FilterGroup(nodes: [leaf])),
            ],
          ),
        ),
        throwsFormatException,
      );
      for (final updates in [
        [wire.FilterUpdate(path: [], text: '')],
        [wire.FilterUpdate(path: List.filled(9, 0), text: '')],
        [
          wire.FilterUpdate(path: [256], text: ''),
        ],
        [
          wire.FilterUpdate(path: [1]),
        ],
        [
          wire.FilterUpdate(path: [1], checkBox: false),
          wire.FilterUpdate(path: [1], text: ''),
        ],
        [
          wire.FilterUpdate(path: [1], triState: 3),
        ],
        [
          wire.FilterUpdate(path: [1], select: 256),
        ],
        [
          wire.FilterUpdate(
            path: [1],
            sort: wire.FilterSortState(
              selection: wire.FilterSortSelection(index: 256),
            ),
          ),
        ],
        [
          wire.FilterUpdate(path: [1], text: 'x' * 4097),
        ],
        List.generate(
          33,
          (i) => wire.FilterUpdate(path: [i], text: 'x' * 4096),
        ),
      ]) {
        expect(
          () => wire.validateFilterSelection(
            wire.FilterSelection(snapshotId: 'f', updates: updates),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => wire.decodeProtoJson(wire.FilterNode(), {
          'text': <String, Object?>{},
          'checkBox': <String, Object?>{},
        }),
        throwsFormatException,
      );
      expect(
        () => wire.decodeProtoJson(wire.FilterUpdate(), {
          'path': [0],
          'text': '',
          'checkBox': false,
        }),
        throwsFormatException,
      );
    },
  );
}
