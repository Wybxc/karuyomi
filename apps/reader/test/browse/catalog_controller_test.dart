import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'fakes.dart';

void main() {
  late TestPlatform platform;
  late CatalogController controller;
  setUp(() {
    platform = TestPlatform();
    controller = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
    );
  });
  tearDown(() async {
    controller.dispose();
    await platform.dispose();
  });

  Future<void> open() async {
    await controller.connect();
    await controller.openBuild(controller.builds.single);
    await controller.selectSource(controller.session!.sources.single);
  }

  test(
    'browse passes page/query and details preserve explicit Source references',
    () async {
      await open();
      expect(controller.email, 'owner@example.com');
      expect(controller.activeSource!.id, sourceId);
      await controller.loadMangas(search: '原始 搜索');
      expect(
        platform.invocations.last.whichRequest(),
        wire.SourceCall_Request.search,
      );
      expect(platform.invocations.last.search.page, 1);
      expect(platform.invocations.last.search.query, '原始 搜索');
      final entry = controller.mangas.single;
      final result = await controller.details(entry);
      expect(result!.chapters.single.url, '/chapter/opaque-ref');
      final detailCall = platform.invocations[platform.invocations.length - 2];
      expect(detailCall.sourceId, sourceId);
      expect(detailCall.details.manga, testManga);
      expect(platform.invocations.last.chapters.manga, result.manga.snapshot);
      expect(result.manga.description, '漫画源返回的完整简介');
    },
  );

  test(
    'Access expiry removes Source data and asks for authentication',
    () async {
      await open();
      platform.invokeHandler = (_) async => throw const RuntimeException(
        RuntimeErrorCode.accessRequired,
        'Expired Access cookie',
      );
      await controller.loadMangas(search: '失效');
      expect(controller.status, ServiceStatus.loginRequired);
      expect(controller.session, isNull);
      expect(controller.mangas, isEmpty);
      expect(controller.error, contains('重新登录'));
    },
  );

  test('HTTP 200 login HTML never becomes a connected catalog', () async {
    platform.loginHtml = true;
    await controller.connect();
    expect(controller.status, ServiceStatus.loginRequired);
    expect(controller.builds, isEmpty);
  });

  test('an occupied Source names the conflicting tab or window', () async {
    await open();
    platform.invokeHandler = (_) async => throw const RuntimeException(
      RuntimeErrorCode.storageBusy,
      'Source storage namespace is already in use',
    );
    await controller.loadMangas(search: 'occupied');
    expect(controller.error, '这个漫画源已在其他标签页或窗口运行，请先关闭后再连接');
    expect(controller.accessPaused, false);
  });

  test(
    'Source data errors are visible and do not invent or discard prior items',
    () async {
      await open();
      final prior = controller.mangas.single;
      platform.invokeHandler = (_) async => wire.SourceResult(
        mangaPage: wire.MangaPage(
          mangas: [wire.Manga(title: 'missing original Source reference')],
        ),
      );
      await controller.loadMangas(more: true);
      expect(controller.mangas.single, same(prior));
      expect(controller.error, '服务返回的数据不完整');
      expect(controller.busy, false);
      expect(controller.page, 1);
    },
  );

  test(
    'container loss prevents late Source data from repopulating the catalog',
    () async {
      await open();
      final delayed = Completer<wire.SourceResult>();
      platform.invokeHandler = (_) => delayed.future;
      final loading = controller.loadMangas(more: true);
      await Future<void>.delayed(Duration.zero);
      platform.runtime.containerLost('Process terminated');
      await Future<void>.delayed(Duration.zero);
      delayed.complete(
        wire.SourceResult(
          mangaPage: wire.MangaPage(mangas: [testManga], hasNextPage: true),
        ),
      );
      await loading;
      expect(controller.session, isNull);
      expect(controller.mangas, isEmpty);
      expect(controller.hasNextPage, false);
      expect(controller.busy, false);
    },
  );

  test('malformed inventory never becomes ready', () async {
    platform.inventory = {'schemaVersion': 1, 'builds': 'invalid'};
    await controller.connect();
    expect(controller.status, ServiceStatus.failed);
    expect(controller.builds, isEmpty);
    expect(controller.error, isNotNull);
  });

  test(
    'reconnect refreshes the current static index and drops old selection',
    () async {
      await open();
      platform.inventory = {
        'schemaVersion': 1,
        'repoId': 'keiyoushi',
        'builds': [
          {
            'buildId': 'build-2',
            'packageName': 'eu.kanade.source.test',
            'repoId': 'keiyoushi',
            'sourceIds': [sourceId],
            'sources': [wire.encodeProtoJson(testCatalogSource)],
            'version': '2.0',
            'manifestPath': '/extensions/builds/build-2/manifest.json',
          },
        ],
      };
      await controller.connect();
      expect(controller.status, ServiceStatus.ready);
      expect(controller.builds.single.id, 'build-2');
      expect(controller.activeBuild, isNull);
      expect(controller.session, isNull);
    },
  );

  for (final path in ['/api/bootstrap', '/extensions/index.json']) {
    test('container loss rejects late reconnect response at $path', () async {
      await controller.connect();
      final entered = Completer<void>();
      final release = Completer<void>();
      platform.beforeApiFetch = (requested) async {
        if (requested != path) return;
        entered.complete();
        await release.future;
      };
      final reconnecting = controller.connect();
      await entered.future;
      platform.runtime.containerLost('Container lost during catalog refresh');
      await Future<void>.delayed(Duration.zero);
      expect(controller.status, ServiceStatus.failed);
      release.complete();
      await reconnecting;
      expect(controller.status, ServiceStatus.failed);
      expect(controller.subject, isNull);
      expect(controller.email, isNull);
      expect(controller.builds, isEmpty);
      expect(controller.session, isNull);
      expect(controller.busy, false);
    });
  }

  test(
    'loaded runtime is rebuilt before reconnect verifies another subject',
    () async {
      await open();
      platform.bootstrapSubject = 'other-subject';
      platform.seedInstalledBuilds(
        wire.decodeProtoJson(wire.ExtensionIndex(), platform.inventory).builds,
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      platform.beforeApiFetch = (path) async {
        if (path != '/api/bootstrap') return;
        entered.complete();
        await release.future;
      };
      final reconnecting = controller.connect();
      await entered.future;
      expect(platform.rebuildCount, 1);
      expect(controller.subject, isNull);
      expect(controller.email, isNull);
      expect(controller.session, isNull);
      expect(controller.busy, true);
      expect(controller.status, ServiceStatus.connecting);
      final invokes = platform.invocations.length;
      await expectLater(
        platform.runtime.invoke(
          SourceRequest(
            packageId: 'eu.kanade.source.test',
            call: wire.SourceCall(
              requestId: 'old-after-reconnect',
              generation: 'generation-1',
              sourceId: sourceId,
              popular: wire.PageRequest(page: 1),
            ),
          ),
        ),
        throwsA(
          isA<RuntimeException>().having(
            (error) => error.code,
            'code',
            RuntimeErrorCode.runtimeLost,
          ),
        ),
      );
      expect(platform.invocations.length, invokes);
      release.complete();
      await reconnecting;
      expect(controller.status, ServiceStatus.ready);
      expect(controller.subject, 'other-subject');
      expect(controller.busy, false);
      await controller.openBuild(controller.builds.single);
      expect(platform.openedIdentities, ['owner-subject', 'other-subject']);
      expect(controller.session, isNotNull);
    },
  );

  test('failed reconnect rebuild retains no verified subject and can retry cleanup', () async {
    await open();
    final before = platform.controlCommands.length;
    platform.beforeRebuild = () async =>
        throw StateError('Controlled rebuild cleanup failure');
    await controller.connect();
    expect(platform.rebuildCount, 1);
    expect(platform.controlCommands.length, before);
    expect(controller.subject, isNull);
    expect(controller.email, isNull);
    expect(controller.session, isNull);
    expect(controller.builds, isEmpty);
    expect(controller.status, ServiceStatus.failed);
    expect(controller.busy, false);
    expect(controller.error, isNotNull);
    platform.beforeRebuild = null;
    await controller.connect();
    expect(platform.rebuildCount, 2);
    expect(controller.status, ServiceStatus.ready);
    expect(controller.subject, 'owner-subject');
  });

  test('catalog-only refresh does not rebuild an unopened runtime', () async {
    await controller.connect();
    await controller.connect();
    expect(platform.rebuildCount, 0);
    expect(controller.status, ServiceStatus.ready);
  });

  test('late manifest cannot open a Source after container loss', () async {
    await controller.connect();
    final entered = Completer<void>();
    final release = Completer<void>();
    platform.beforeApiFetch = (path) async {
      if (!path.endsWith('/manifest.json')) return;
      entered.complete();
      await release.future;
    };
    final opening = controller.openBuild(controller.builds.single);
    await entered.future;
    platform.runtime.containerLost('Lost while manifest was pending');
    await Future<void>.delayed(Duration.zero);
    release.complete();
    await opening;
    expect(platform.openedIdentities, isEmpty);
    expect(controller.session, isNull);
    expect(controller.activeBuild, isNull);
    expect(controller.status, ServiceStatus.failed);
  });

  test('empty page URLs use content version so same-length reorders cannot claim a stable page', () async {
    await open();
    final manga = controller.mangas.single;
    final chapter = ChapterEntry(
      wire.Chapter(url: '/chapter/ref', name: 'chapter'),
    );
    var images = ['first', 'second'];
    platform.invokeHandler = (payload) async => wire.SourceResult(
      pageList: wire.PageList(
        pageSessionId: 'pages-empty',
        pages: [
          for (var i = 0; i < images.length; i++)
            wire.Page(
              pageKey: 'p-$i',
              index: i,
              sourceIndex: i,
              url: '',
              imageUrl: 'https://source.invalid/${images[i]}.png',
            ),
        ],
      ),
    );
    final first = await controller.openChapter(
      manga,
      chapter,
      reference: controller.sourceReference,
    );
    final position = first!.manifest.positionAt(0, offset: 0.3);
    await controller.closeChapter(first);
    images = images.reversed.toList();
    final second = await controller.openChapter(
      manga,
      chapter,
      reference: controller.sourceReference,
    );
    expect(second!.manifest.version, isNot(first.manifest.version));
    final resolved = resolvePosition(second.manifest, position);
    expect(resolved.kind, PositionResolutionKind.missingPage);
    expect(resolved.position!.pageIndexHint, 0);
    await controller.closeChapter(second);
  });

  test('static index rejects duplicate package versions', () async {
    final entry = {
      'buildId': 'build-1',
      'packageName': 'eu.kanade.source.test',
      'repoId': 'keiyoushi',
      'sourceIds': [sourceId],
      'sources': [wire.encodeProtoJson(testCatalogSource)],
      'version': '1.0',
      'manifestPath': '/extensions/builds/build-1/manifest.json',
    };
    platform.inventory = {
      'schemaVersion': 1,
      'repoId': 'keiyoushi',
      'builds': [entry, entry],
    };
    await controller.connect();
    expect(controller.status, ServiceStatus.failed);
    expect(controller.builds, isEmpty);
    expect(controller.error, contains('每包只包含一个当前版本'));
  });

  test(
    'chapter manifests separate stable reading keys from opaque Page handles',
    () async {
      await open();
      final manga = controller.mangas.single;
      final details = await controller.details(manga);
      final first = await controller.openChapter(
        manga,
        details!.chapters.single,
        reference: details.source,
      );
      expect(first!.provider.pageSessionId, 'pages-1');
      expect(first.provider.pageKeys.values, ['p-0']);
      expect(first.manifest.pages.single.width, isNull);
      expect(first.manifest.pages.single.key, isNot('p-0'));
      await controller.closeChapter(first);
      platform.invokeHandler = (payload) async => wire.SourceResult(
        pageList: wire.PageList(
          pageSessionId: 'replacement-session',
          pages: [
            wire.Page(
              pageKey: 'new-opaque-key',
              index: 0,
              sourceIndex: 7,
              url: '/page/stable-1',
              imageUrl: 'https://source.invalid/rotated-token.png',
            ),
          ],
        ),
      );
      final second = await controller.openChapter(
        manga,
        details.chapters.single,
        reference: details.source,
      );
      expect(second!.manifest.chapterKey, first.manifest.chapterKey);
      expect(second.manifest.pages.single.key, first.manifest.pages.single.key);
      expect(second.provider.pageKeys.values, ['new-opaque-key']);
      expect(second.manifest.version, isNot(first.manifest.version));
      await controller.closeChapter(second);
    },
  );

  test(
    'malformed page references close their original Java page session',
    () async {
      await open();
      platform.invokeHandler = (payload) async => wire.SourceResult(
        pageList: wire.PageList(
          pageSessionId: 'malformed-session',
          pages: [wire.Page(pageKey: 'p-0', index: 1, sourceIndex: 0, url: '')],
        ),
      );
      final chapter = ChapterEntry(
        wire.Chapter(url: '/chapter/ref', name: 'chapter'),
      );
      expect(
        await controller.openChapter(
          controller.mangas.single,
          chapter,
          reference: controller.sourceReference,
        ),
        isNull,
      );
      expect(controller.error, '漫画源页面引用无效');
      expect(platform.imageControls.last.$1, 'closePageSession');
      expect(platform.imageControls.last.$2, {
        'pageSessionId': 'malformed-session',
        'generation': 'generation-1',
      });
    },
  );

  test(
    'old details never submit their chapter to another Source slot',
    () async {
      await open();
      final manga = controller.mangas.single;
      final chapter = ChapterEntry(
        wire.Chapter(url: '/chapter/ref', name: 'chapter'),
      );
      final before = platform.invocations.length;
      for (final reference in [
        CatalogSourceRef(
          buildId: 'different-build',
          sourceId: sourceId,
          generation: 'generation-1',
        ),
        CatalogSourceRef(
          buildId: 'build-1',
          sourceId: 'different-source',
          generation: 'generation-1',
        ),
        CatalogSourceRef(
          buildId: 'build-1',
          sourceId: sourceId,
          generation: 'old-generation',
        ),
      ]) {
        expect(
          await controller.openChapter(manga, chapter, reference: reference),
          isNull,
        );
        expect(controller.error, contains('会话已过期'));
      }
      expect(platform.invocations.length, before);
      expect(controller.session, isNotNull);
    },
  );
}
