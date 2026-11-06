import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import '../browse/fakes.dart';
import 'filter_fixtures.dart';

void main() {
  late TestPlatform platform;
  late CatalogController catalog;
  late TransportSourceRuntime runtime;
  var snapshotNumber = 0;
  var failDescription = false;
  var failSearch = false;

  setUp(() async {
    snapshotNumber = 0;
    failDescription = false;
    failSearch = false;
    platform = TestPlatform()
      ..invokeHandler = (call) async {
        if (call.hasGetFilters()) {
          if (failDescription) {
            throw const RuntimeException(
              RuntimeErrorCode.sourceError,
              'filters failed',
            );
          }
          return wire.SourceResult(
            filters: filterSnapshot('snapshot-${++snapshotNumber}'),
          );
        }
        if (call.hasSearch() && failSearch) {
          throw const RuntimeException(
            RuntimeErrorCode.sourceError,
            'search failed',
          );
        }
        return wire.SourceResult(
          mangaPage: wire.MangaPage(mangas: [testManga], hasNextPage: true),
        );
      };
    runtime = TransportSourceRuntime(FilterRuntimeTransport(platform));
    catalog = CatalogController(
      api: platform,
      runtime: runtime,
      rebuildRuntime: () async {
        runtime.containerLost('Rebuilt filter test container');
        await platform.rebuild();
      },
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    await catalog.openBuild(catalog.builds.single);
    await catalog.selectSource(catalog.session!.sources.single);
  });
  tearDown(() async {
    catalog.dispose();
    await catalog.closeReadingProgress();
    await runtime.dispose();
    await platform.dispose();
  });

  test(
    'descriptions are explicit and cached, typed application uses empty-query search and immutable pagination',
    () async {
      expect(platform.invocations.single.hasPopular(), true);
      final prior = catalog.mangas.single;
      expect(await catalog.loadSourceFilters(), true);
      expect(await catalog.loadSourceFilters(), true);
      expect(
        platform.invocations.where((call) => call.hasGetFilters()),
        hasLength(1),
      );
      expect(
        platform.invocations.last.getFilters.hasRetainedSnapshotId(),
        false,
      );
      expect(catalog.mangas.single, same(prior));
      final draft = filterSelection(
        'snapshot-1',
        text: '作者',
        check: true,
        tri: 2,
        select: 1,
      );
      expect(await catalog.applySourceFilters(draft, search: ''), true);
      final applied = catalog.appliedSourceFilters!.deepCopy();
      expect(catalog.listing, 'search');
      expect(platform.invocations.last.search.query, '');
      expect(platform.invocations.last.search.filters, applied);
      expect(applied.updates[4].whichState(), wire.FilterUpdate_State.sort);
      expect(applied.updates[4].sort.hasSelection(), false);
      draft.updates[0].text = '未应用改动';
      await catalog.loadMangas(more: true);
      expect(platform.invocations.last.search.page, 2);
      expect(platform.invocations.last.search.filters, applied);
      expect(catalog.appliedSourceFilters, applied);
      expect(platform.businessServer.requests, isEmpty);
    },
  );

  test(
    'reset retains the confirmed snapshot; failure preserves applied query and explicit popular clears filters only on success',
    () async {
      await catalog.loadSourceFilters();
      final first = filterSelection('snapshot-1', text: '第一份');
      await catalog.applySourceFilters(first, search: '关键词');
      expect(await catalog.loadSourceFilters(reset: true), true);
      expect(
        platform.invocations.last.getFilters.retainedSnapshotId,
        'snapshot-1',
      );
      expect(catalog.sourceFilterSnapshot!.snapshotId, 'snapshot-2');
      expect(catalog.appliedSourceFilters, first);
      await catalog.loadMangas(more: true);
      expect(platform.invocations.last.search.filters, first);
      expect(platform.invocations.last.search.query, '关键词');
      final second = filterSelection('snapshot-2', text: '第二份', sortIndex: 1);
      failSearch = true;
      expect(await catalog.applySourceFilters(second, search: ''), false);
      expect(catalog.appliedSourceFilters, first);
      expect(catalog.query, '关键词');
      expect(catalog.page, 2);
      failSearch = false;
      expect(await catalog.applySourceFilters(second, search: ''), true);
      await catalog.loadSourceFilters(reset: true);
      expect(
        platform.invocations.last.getFilters.retainedSnapshotId,
        'snapshot-2',
      );
      await catalog.loadMangas(search: '');
      expect(platform.invocations.last.hasSearch(), true);
      expect(platform.invocations.last.search.filters, second);
      await catalog.loadMangas(search: '', operation: 'popular');
      expect(platform.invocations.last.hasPopular(), true);
      expect(catalog.appliedSourceFilters, isNull);
      await catalog.loadMangas(search: '');
      expect(platform.invocations.last.hasPopular(), true);
    },
  );

  test(
    'description failure permits default browsing and explicit retry',
    () async {
      failDescription = true;
      final prior = catalog.mangas.single;
      expect(await catalog.loadSourceFilters(), false);
      expect(catalog.sourceFilterSnapshot, isNull);
      expect(catalog.sourceFilterError, isNotNull);
      expect(catalog.status, ServiceStatus.ready);
      expect(catalog.mangas.single, same(prior));
      await catalog.loadMangas(operation: 'latest');
      expect(platform.invocations.last.hasLatest(), true);
      failDescription = false;
      expect(await catalog.loadSourceFilters(), true);
      expect(catalog.sourceFilterError, isNull);
    },
  );

  test(
    'a completed reset discarded by a closing route clears only its stale draft cache',
    () async {
      await catalog.loadSourceFilters();
      final applied = filterSelection('snapshot-1', text: '已应用');
      await catalog.applySourceFilters(applied, search: '原关键词');
      await catalog.loadSourceFilters(reset: true);
      expect(catalog.sourceFilterSnapshot!.snapshotId, 'snapshot-2');
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final original = platform.invokeHandler!;
      platform.invokeHandler = (call) async {
        await release.future;
        return original(call);
      };
      var routeCurrent = true;
      final resetting = catalog.loadSourceFilters(
        reset: true,
        shouldContinue: () => routeCurrent,
      );
      routeCurrent = false;
      release.complete();
      expect(await resetting, false);
      expect(catalog.sourceFilterSnapshot, isNull);
      expect(catalog.appliedSourceFilters, applied);
      expect(catalog.query, '原关键词');
      expect(catalog.listing, 'search');
      expect(catalog.busy, false);
      expect(
        platform.controlCommands,
        isNot(contains(wire.ControlRequest_Command.cancel)),
      );
      expect(await catalog.loadSourceFilters(), true);
      expect(
        platform.invocations.last.getFilters.retainedSnapshotId,
        'snapshot-1',
      );
      expect(catalog.sourceFilterSnapshot!.snapshotId, 'snapshot-4');
      await catalog.loadMangas(more: true);
      expect(platform.invocations.last.search.filters, applied);
      expect(platform.invocations.last.search.query, '原关键词');
    },
  );

  test(
    'cancelled active descriptor releases UI and real container loss invalidates all filter state',
    () async {
      await catalog.loadSourceFilters();
      await catalog.applySourceFilters(
        filterSelection('snapshot-1'),
        search: '',
      );
      final delayed = Completer<wire.SourceResult>();
      addTearDown(() {
        if (!delayed.isCompleted) {
          delayed.complete(wire.SourceResult(filters: filterSnapshot('late')));
        }
      });
      platform.invokeHandler = (_) => delayed.future;
      String? requestId;
      final loading = catalog.loadSourceFilters(
        reset: true,
        onRequest: (id) => requestId = id,
      );
      expect(catalog.busy, true);
      await catalog.cancelSourceFilterRequest(requestId!);
      expect(catalog.busy, false);
      expect(
        platform.controlCommands,
        contains(wire.ControlRequest_Command.cancel),
      );
      await Future<void>.delayed(Duration.zero);
      delayed.complete(wire.SourceResult(filters: filterSnapshot('late')));
      expect(await loading, false);
      expect(catalog.status, ServiceStatus.failed);
      expect(catalog.session, isNull);
      expect(catalog.sourceFilterSnapshot, isNull);
      expect(catalog.appliedSourceFilters, isNull);
      expect(catalog.mangas, isEmpty);
    },
  );

  for (final applying in [false, true]) {
    test(
      'late ${applying ? 'applied search' : 'description'} cannot cross identity and generation',
      () async {
        await catalog.loadSourceFilters();
        final delayed = Completer<wire.SourceResult>();
        addTearDown(() {
          if (!delayed.isCompleted) {
            delayed.complete(
              wire.SourceResult(filters: filterSnapshot('late')),
            );
          }
        });
        platform.invokeHandler = (_) => delayed.future;
        final pending = applying
            ? catalog.applySourceFilters(
                filterSelection('snapshot-1'),
                search: 'old',
              )
            : catalog.loadSourceFilters(reset: true);
        runtime.containerLost('Expired old generation');
        await Future<void>.delayed(Duration.zero);
        platform.bootstrapSubject = 'new-subject';
        platform.runtimeGeneration = 'new-generation';
        platform.invokeHandler = (call) async => call.hasGetFilters()
            ? wire.SourceResult(filters: filterSnapshot('new-snapshot'))
            : wire.SourceResult(mangaPage: wire.MangaPage(mangas: [testManga]));
        await catalog.connect();
        await catalog.openBuild(catalog.builds.single);
        await catalog.selectSource(catalog.session!.sources.single);
        await catalog.loadSourceFilters();
        delayed.complete(
          applying
              ? wire.SourceResult(
                  mangaPage: wire.MangaPage(
                    mangas: [wire.Manga(url: '/late', title: '旧结果')],
                  ),
                )
              : wire.SourceResult(filters: filterSnapshot('late')),
        );
        expect(await pending, false);
        expect(catalog.subject, 'new-subject');
        expect(catalog.sourceFilterSnapshot!.snapshotId, 'new-snapshot');
        expect(catalog.appliedSourceFilters, isNull);
        expect(catalog.mangas.single.title, testManga.title);
        expect(catalog.busy, false);
      },
    );
  }
}
