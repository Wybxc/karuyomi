import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import '../browse/fakes.dart';

wire.ExtensionBuildDescriptor _build(String name, List<String> sources) =>
    wire.ExtensionBuildDescriptor(
      buildId: 'build-$name',
      packageName: 'eu.kanade.source.$name',
      repoId: 'keiyoushi',
      version: '1',
      manifestPath: '/extensions/builds/build-$name/manifest.json',
      sourceIds: sources,
      sources: sources.map(
        (id) => wire.CatalogSource(id: id, name: 'Source $id', lang: 'en'),
      ),
    );

wire.SourceResult _page(String name) => wire.SourceResult(
  mangaPage: wire.MangaPage(
    mangas: [wire.Manga(url: '/manga/$name', title: name)],
    hasNextPage: true,
  ),
);

/// Independent typed control supplier. Catalog/BSC remain the production
/// implementations; this supplier models two host slots and active-cancel loss.
final class _Slots implements RuntimeTransport {
  _Slots(this.builds);
  final List<wire.ExtensionBuildDescriptor> builds;
  final live = <wire.RuntimeSlot, wire.RuntimeSession>{};
  final pending = <wire.RuntimeSlot, Completer<wire.SourceResult>>{};
  final pendingOpen = <wire.RuntimeSlot, Completer<void>>{};
  final events = <String>[];
  final calls = <wire.SourceCall>[];
  int sequence = 0;
  int maxLive = 0;
  Future<void> Function(wire.OpenRequest request)? beforeOpen;
  Future<wire.SourceResult> Function(wire.SourceCall call)? invoke;
  Future<void> Function(wire.CloseBuildRequest request)? beforeClose;
  Future<void> Function()? beforeReset;

  void _retire(wire.RuntimeSlot slot) {
    live.remove(slot);
    final opening = pendingOpen.remove(slot);
    if (opening != null && !opening.isCompleted) {
      opening.completeError(
        const RuntimeException(RuntimeErrorCode.runtimeLost, 'Slot reset'),
      );
    }
    final invoking = pending.remove(slot);
    if (invoking != null && !invoking.isCompleted) {
      invoking.completeError(
        const RuntimeException(RuntimeErrorCode.runtimeLost, 'Slot reset'),
      );
    }
  }

  @override
  Future<Object?> control(Map<String, Object?> json) async {
    final request = wire.decodeProtoJson(wire.ControlRequest(), json);
    final slot = request.slotId;
    final response = wire.ControlResponse(
      requestId: request.requestId,
      slotId: slot,
    );
    try {
      switch (request.whichCommand()) {
        case wire.ControlRequest_Command.ready:
          response.hello = wire.RuntimeHello(
            protocolVersion: protocolVersion,
            hostAbi: hostAbi,
            runtimeBaseline: runtimeBaseline,
          );
        case wire.ControlRequest_Command.open:
          final build = builds.singleWhere(
            (value) => value.buildId == request.open.expectedBuildId,
          );
          final session = wire.RuntimeSession(
            protocolVersion: protocolVersion,
            catalog: request.open.catalog.deepCopy(),
            workerInstanceId: 'worker-${++sequence}',
            generation: 'generation-$sequence',
            buildId: build.buildId,
            sources: build.sources.map(
              (value) => wire.SourceInfo(
                id: value.id,
                name: value.name,
                lang: value.lang,
                supportsLatest: false,
              ),
            ),
            capabilities: ['source-rpc'],
          );
          expect(
            live.containsKey(slot),
            false,
            reason: 'Close ACK before reuse',
          );
          live[slot] = session;
          if (live.length > maxLive) maxLive = live.length;
          events.add('open:${build.buildId}');
          final cancelled = Completer<void>();
          pendingOpen[slot] = cancelled;
          try {
            await Future.any([
              Future<void>.sync(() async {
                await beforeOpen?.call(request.open);
              }),
              cancelled.future,
            ]);
            response.session = session.deepCopy();
          } finally {
            if (identical(pendingOpen[slot], cancelled)) {
              pendingOpen.remove(slot);
            }
          }
        case wire.ControlRequest_Command.invoke:
          final call = request.invoke.deepCopy();
          final session = live[slot];
          if (session == null || session.generation != call.generation) {
            throw const RuntimeException(
              RuntimeErrorCode.runtimeLost,
              'No matching slot generation',
            );
          }
          calls.add(call);
          events.add('invoke:${call.sourceId}:${call.whichRequest().name}');
          final cancelled = Completer<wire.SourceResult>();
          pending[slot] = cancelled;
          try {
            final value = await Future.any([
              Future<wire.SourceResult>.sync(
                () => invoke?.call(call) ?? _defaultResult(call),
              ),
              cancelled.future,
            ]);
            response.source = value.deepCopy()
              ..requestId = call.requestId
              ..generation = call.generation
              ..buildId = session.buildId;
          } finally {
            if (identical(pending[slot], cancelled)) pending.remove(slot);
          }
        case wire.ControlRequest_Command.cancel:
          events.add('cancel:${request.cancel.requestId}');
          _retire(slot);
          // The production manager intentionally reports the retired generation.
          throw const RuntimeException(
            RuntimeErrorCode.runtimeLost,
            'Active Source cancellation invalidated the generation',
          );
        case wire.ControlRequest_Command.closeBuild:
          events.add('close:${request.closeBuild.buildId}');
          await beforeClose?.call(request.closeBuild);
          if (live[slot]?.generation != request.closeBuild.generation) {
            throw const RuntimeException(
              RuntimeErrorCode.runtimeLost,
              'The old generation is already retired',
            );
          }
          _retire(slot);
          events.add('closed:${request.closeBuild.buildId}');
          response.closed = wire.Closed(closed: true);
        case wire.ControlRequest_Command.rebuild:
          await beforeReset?.call();
          _retire(slot);
          events.add('reset:$slot');
          response.completed = wire.Completed(completed: true);
        case wire.ControlRequest_Command.closePageSession:
          events.add('page-closed');
          response.closed = wire.Closed(closed: true);
        case wire.ControlRequest_Command.dispose:
          _retire(slot);
          response.completed = wire.Completed(completed: true);
        default:
          throw StateError(
            'Unexpected Source control ${request.whichCommand()}',
          );
      }
    } on RuntimeException catch (failure) {
      response.error = wire.RuntimeError(
        code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST,
        message: failure.message,
      );
    }
    return wire.encodeProtoJson(response);
  }

  wire.SourceResult _defaultResult(wire.SourceCall call) => switch (call
      .whichRequest()) {
    wire.SourceCall_Request.details => wire.SourceResult(
      manga: call.details.manga.deepCopy(),
    ),
    wire.SourceCall_Request.chapters => wire.SourceResult(
      chapters: wire.ChapterList(
        chapters: [
          wire.Chapter(url: '/chapter/1', name: 'Chapter 1', dateUpload: '0'),
        ],
      ),
    ),
    wire.SourceCall_Request.pages => wire.SourceResult(
      pageList: wire.PageList(
        pageSessionId: 'pages-1',
        pages: [wire.Page(pageKey: 'p1', url: '/page/1', sourceIndex: 0)],
      ),
    ),
    _ => _page(call.sourceId),
  };
}

Future<void> _started(SourceSearchTask task, Future<void> entered) =>
    Future.any([
      entered,
      task.result.then<void>((_) {
        throw StateError(
          'Search completed without reaching its expected boundary',
        );
      }),
    ]);

void main() {
  late TestPlatform platform;
  late _Slots slots;
  late TransportSourceRuntime foreground;
  late TransportSourceRuntime secondary;
  late CatalogController catalog;
  late CatalogSourceSearch search;
  late List<SourceSearchTarget> targets;
  final builds = [
    _build('a', ['11', '12']),
    _build('b', ['21']),
    _build('c', ['31']),
  ];

  SourceSearchTarget target(String id) =>
      targets.singleWhere((value) => value.source.id == id);

  setUp(() async {
    platform = TestPlatform(seedDefaultInstallation: false);
    platform.inventory = wire.encodeProtoJson(
      wire.ExtensionIndex(
        schemaVersion: 1,
        repoId: 'keiyoushi',
        builds: builds,
      ),
    );
    platform.seedInstalledBuilds(builds);
    for (final build in builds) {
      platform.publicDocuments[platform.origin
          .resolve(build.manifestPath)
          .toString()] = wire.encodeProtoJson(
        wire.BuildManifest(
          buildId: build.buildId,
          packageName: build.packageName,
          repoId: build.repoId,
          version: build.version,
          sourceIds: build.sourceIds,
          sources: build.sources,
          bundle: wire.BundleArtifact(sha256: 'a' * 64),
        ),
      );
    }
    slots = _Slots(builds);
    foreground = TransportSourceRuntime(slots);
    secondary = TransportSourceRuntime(
      slots,
      slotId: wire.RuntimeSlot.RUNTIME_SLOT_SEARCH,
    );
    catalog = CatalogController(
      api: platform,
      runtime: foreground,
      searchRuntime: secondary,
      rebuildRuntime: () async {
        await foreground.rebuildHost();
        await secondary.rebuildHost();
      },
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    expect(catalog.status, ServiceStatus.ready, reason: catalog.error);
    search = catalog.createSourceSearch();
    targets = await search.loadTargets();
    expect(targets, hasLength(4));
  });

  tearDown(() async {
    await search.close();
    search.dispose();
    catalog.dispose();
    await catalog.closeReadingProgress();
    await foreground.dispose();
    await secondary.dispose();
    await platform.dispose();
  });

  test(
    'different packages return independently with at most two live slots',
    () async {
      final gates = {
        for (final id in ['11', '21', '31']) id: Completer<wire.SourceResult>(),
      };
      final entered = {for (final id in gates.keys) id: Completer<void>()};
      slots.invoke = (call) {
        entered[call.sourceId]!.complete();
        return gates[call.sourceId]!.future;
      };
      final slow = search.search(target('11'), 'query');
      final fast = search.search(target('21'), 'query');
      final third = search.search(target('31'), 'query');
      await Future.wait([
        _started(slow, entered['11']!.future),
        _started(fast, entered['21']!.future),
      ], eagerError: true);
      expect(entered['31']!.isCompleted, false);
      var slowReturned = false;
      unawaited(
        slow.result.then((_) {
          slowReturned = true;
        }),
      );
      gates['21']!.complete(_page('fast'));
      expect((await fast.result).mangas.single.title, 'fast');
      expect(slowReturned, false);
      await _started(third, entered['31']!.future);
      expect(slots.maxLive, 2);
      gates['31']!.complete(_page('third'));
      gates['11']!.complete(_page('slow'));
      await Future.wait([slow.result, third.result]);
      await search.stop();
      expect(slots.live, isEmpty);
      expect(catalog.status, ServiceStatus.ready);
    },
  );

  test(
    'Sources in one package share a generation and execute serially',
    () async {
      final firstEntered = Completer<void>();
      final gate = Completer<wire.SourceResult>();
      slots.invoke = (call) {
        if (call.sourceId == '11') {
          firstEntered.complete();
          return gate.future;
        }
        return Future.value(_page('second'));
      };
      final first = search.search(target('11'), 'query');
      final second = search.search(target('12'), 'query');
      await _started(first, firstEntered.future);
      expect(slots.calls.map((call) => call.sourceId), ['11']);
      gate.complete(_page('first'));
      await Future.wait([first.result, second.result]);
      await search.stop();
      expect(
        slots.events.where((event) => event == 'open:build-a'),
        hasLength(1),
      );
      expect(slots.calls.map((call) => call.sourceId), ['11', '12']);
      expect(slots.calls.map((call) => call.generation).toSet(), hasLength(1));
    },
  );

  test(
    'queued cancellation never opens or invokes the third package',
    () async {
      final gates = {
        for (final id in ['11', '21']) id: Completer<wire.SourceResult>(),
      };
      final entered = {for (final id in gates.keys) id: Completer<void>()};
      slots.invoke = (call) {
        entered[call.sourceId]!.complete();
        return gates[call.sourceId]!.future;
      };
      final first = search.search(target('11'), 'query');
      final second = search.search(target('21'), 'query');
      final queued = search.search(target('31'), 'query');
      final rejected = expectLater(
        queued.result,
        throwsA(isA<RuntimeException>()),
      );
      await Future.wait([
        _started(first, entered['11']!.future),
        _started(second, entered['21']!.future),
      ], eagerError: true);
      await queued.cancel();
      gates['11']!.complete(_page('first'));
      gates['21']!.complete(_page('second'));
      await Future.wait([first.result, second.result]);
      await rejected;
      await search.stop();
      expect(slots.events, isNot(contains('open:build-c')));
      expect(slots.calls.map((call) => call.sourceId), isNot(contains('31')));
    },
  );

  test(
    'startup cancellation resets its slot and discards a late open',
    () async {
      final entered = Completer<void>();
      final gate = Completer<void>();
      slots.beforeOpen = (_) {
        entered.complete();
        return gate.future;
      };
      final job = search.search(target('11'), 'query');
      final rejected = expectLater(
        job.result,
        throwsA(isA<RuntimeException>()),
      );
      await _started(job, entered.future);
      await job.cancel();
      await rejected;
      gate.complete();
      await search.stop();
      expect(slots.calls, isEmpty);
      expect(slots.live, isEmpty);
    },
  );

  test(
    'startup reset ACK loss cannot release an unconfirmed live slot',
    () async {
      final entered = Completer<void>();
      final gate = Completer<void>();
      slots.beforeOpen = (_) {
        entered.complete();
        return gate.future;
      };
      slots.beforeReset = () async {
        throw const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Reset ACK lost',
        );
      };
      final job = search.search(target('11'), 'query');
      final rejected = expectLater(
        job.result,
        throwsA(isA<RuntimeException>()),
      );
      await _started(job, entered.future);
      await expectLater(job.cancel(), throwsA(isA<RuntimeException>()));
      gate.complete();
      await rejected;
      await expectLater(search.stop(), throwsA(anything));
      expect(search.available, false);
      slots.beforeReset = null;
      await search.stop();
      expect(slots.live, isEmpty);
      expect(search.available, true);
    },
  );

  test(
    'active cancel waits for physical cleanup after the real runtimeLost reply',
    () async {
      final entered = Completer<void>();
      final late = Completer<wire.SourceResult>();
      slots.invoke = (_) {
        entered.complete();
        return late.future;
      };
      final job = search.search(target('11'), 'query');
      final rejected = expectLater(
        job.result,
        throwsA(isA<RuntimeException>()),
      );
      await _started(job, entered.future);
      await job.cancel();
      await rejected;
      late.complete(_page('must not publish'));
      await search.stop();
      expect(slots.live, isEmpty);
      expect(slots.events.any((event) => event.startsWith('reset:')), true);
      expect(search.available, true);
      expect(catalog.status, ServiceStatus.ready);
    },
  );

  test('failed reset ACK keeps cleanup blocked until explicit retry', () async {
    final entered = Completer<void>();
    final late = Completer<wire.SourceResult>();
    slots.invoke = (_) {
      entered.complete();
      return late.future;
    };
    slots.beforeReset = () async {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Reset ACK lost',
      );
    };
    final job = search.search(target('11'), 'query');
    final rejected = expectLater(job.result, throwsA(isA<RuntimeException>()));
    await _started(job, entered.future);
    await expectLater(job.cancel(), throwsA(isA<RuntimeException>()));
    await rejected;
    await expectLater(search.stop(), throwsA(anything));
    expect(search.available, false);
    expect(search.unavailableReason, contains('关闭'));
    slots.beforeReset = null;
    await search.stop();
    expect(search.available, true);
    expect(slots.live, isEmpty);
    late.complete(_page('late after reset'));
  });

  test(
    'a confirmed exact-origin replacement cancels the old search result',
    () async {
      final entered = Completer<void>();
      final late = Completer<wire.SourceResult>();
      slots.invoke = (_) {
        entered.complete();
        return late.future;
      };
      final job = search.search(target('11'), 'query');
      final rejected = expectLater(
        job.result,
        throwsA(isA<RuntimeException>()),
      );
      await _started(job, entered.future);
      platform.businessServer.seedInstalledExtensions([
        testInstalledExtension(
          packageName: 'eu.kanade.source.a',
          buildId: 'build-a',
          catalogUrl: 'https://other.example/extensions/index.json',
          repoId: 'other',
        ),
      ], advanceRevision: true);
      await catalog.refreshInstallations();
      await rejected;
      late.complete(_page('old origin'));
      await search.stop();
      expect(slots.calls, hasLength(1));
      expect(slots.live, isEmpty);
    },
  );

  test(
    'an active chapter rejects search without touching its reader generation',
    () async {
      await catalog.openSelectedSource(
        packageName: 'eu.kanade.source.a',
        sourceId: '11',
        shouldContinue: () => true,
      );
      final details = await catalog.details(MangaEntry(testManga));
      final chapter = await catalog.openChapter(
        details!.manga,
        details.chapters.single,
        reference: details.source,
      );
      expect(chapter, isNotNull);
      final before = slots.events.toList();
      final job = search.search(target('21'), 'query');
      await expectLater(job.result, throwsA(isA<StateError>()));
      expect(slots.events, before);
      expect(chapter!.provider.isClosed, false);
      expect(catalog.session!.generation, chapter.generation);
      await catalog.closeChapter(chapter);
    },
  );

  test(
    'opening a result waits for search close ACK before ordinary details',
    () async {
      final closing = Completer<void>();
      final closeGate = Completer<void>();
      slots.beforeClose = (_) {
        if (!closing.isCompleted) closing.complete();
        return closeGate.future;
      };
      final job = search.search(target('11'), 'query');
      final page = await job.result;
      await closing.future;
      final opened = search.openResult(target('11'), page.mangas.single);
      await Future<void>.delayed(Duration.zero);
      expect(slots.calls.map((call) => call.whichRequest()), [
        wire.SourceCall_Request.search,
      ]);
      expect(
        slots.events.where((event) => event == 'open:build-a'),
        hasLength(1),
      );
      closeGate.complete();
      final details = await opened;
      expect(details, isNotNull, reason: catalog.error);
      expect(details!.manga.url, page.mangas.single.url);
      expect(details.chapters, hasLength(1));
      expect(
        slots.events.indexOf('closed:build-a'),
        lessThan(slots.events.lastIndexOf('open:build-a')),
      );
      expect(catalog.isCurrentSource(details.source), true);
    },
  );
}
