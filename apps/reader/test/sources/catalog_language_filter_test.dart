import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';

wire.ExtensionBuildDescriptor _build(
  String id,
  List<wire.CatalogSource> sources,
) => wire.ExtensionBuildDescriptor(
  buildId: id,
  packageName: 'eu.kanade.source.${id.replaceAll('-', '_')}',
  repoId: 'keiyoushi',
  version: '1.0',
  manifestPath: '/extensions/builds/$id/manifest.json',
  sourceIds: sources.map((source) => source.id),
  sources: sources,
);

List<wire.ExtensionBuildDescriptor> _builds() => [
  _build('build-1', [
    wire.CatalogSource(id: sourceId, name: '中文目录源', lang: 'zh'),
    wire.CatalogSource(
      id: '-9223372036854775808',
      name: 'English source',
      lang: 'en',
    ),
  ]),
  _build('build-2', [wire.CatalogSource(id: '42', name: '日本語目录源', lang: 'ja')]),
  _build('build-3', [
    wire.CatalogSource(id: '0043', name: '多语言目录源', lang: 'all'),
  ]),
  _build('build-4', [wire.CatalogSource(id: '44', name: '未标注目录源', lang: '')]),
];

Object _index(List<wire.ExtensionBuildDescriptor> builds) =>
    wire.encodeProtoJson(wire.ExtensionIndex(schemaVersion: 1, builds: builds));

void main() {
  test(
    'catalog metadata retains exact Source identities and frozen snapshots',
    () {
      final descriptor = _builds().first;
      final build = CatalogBuild.fromProto(descriptor);
      expect(build.repoId, 'keiyoushi');
      expect(build.sources.map((source) => source.id), [
        sourceId,
        '-9223372036854775808',
      ]);
      descriptor.sources.first.name = 'later input mutation';
      descriptor.sources.clear();
      expect(build.sources.first.name, '中文目录源');
      expect(
        () => build.sources.add(testCatalogSource),
        throwsUnsupportedError,
      );
      expect(
        () => build.sources.first.name = 'mutation',
        throwsUnsupportedError,
      );
      expect(CatalogBuild.fromProto(_builds()[2]).sources.single.id, '0043');
      expect(CatalogBuild.fromProto(_builds()[3]).sources.single.lang, '');
    },
  );

  test(
    'catalog metadata rejects missing, duplicate, malformed and oversized values',
    () {
      final invalid = <String, wire.ExtensionBuildDescriptor>{
        'missing metadata': _builds().first..sources.clear(),
        'duplicate declared ID': _builds().first..sourceIds[1] = sourceId,
        'duplicate metadata ID': _builds().first..sources[1].id = sourceId,
        'mismatched ID set': _builds().first..sources[1].id = '123',
        'signed range': _builds().first
          ..sourceIds[0] = '9223372036854775808'
          ..sources[0].id = '9223372036854775808',
        'nondecimal ID': _builds().first
          ..sourceIds[0] = 'source-one'
          ..sources[0].id = 'source-one',
        'blank name': _builds().first..sources.first.name = ' \t ',
        'long name': _builds().first..sources.first.name = 'x' * 501,
        'long language': _builds().first..sources.first.lang = 'x' * 65,
        'empty repository': _builds().first..repoId = '',
        'empty source list': _build('empty', []),
        'source count': _build('many', [
          for (var id = 0; id < 501; id++)
            wire.CatalogSource(id: '$id', name: 'Source $id', lang: 'en'),
        ]),
      };
      for (final entry in invalid.entries) {
        expect(
          () => CatalogBuild.fromProto(entry.value),
          throwsFormatException,
          reason: entry.key,
        );
      }
    },
  );

  group('formal catalog navigation', () {
    late TestPlatform platform;
    late CatalogController catalog;

    setUp(() async {
      platform = TestPlatform()..inventory = _index(_builds());
      catalog = CatalogController(
        api: platform,
        runtime: platform.runtime,
        rebuildRuntime: platform.rebuild,
        deploymentOrigin: platform.origin,
      );
      await catalog.connect();
    });

    tearDown(() async {
      catalog.dispose();
      await catalog.closeReadingProgress();
      await platform.dispose();
    });

    Finder languageFilter() =>
        find.byKey(const ValueKey('catalog-language-filter'));
    Finder clearFilter() =>
        find.byKey(const ValueKey('catalog-language-clear'));
    Finder build(String id) => find.byKey(ValueKey(('catalog-build', id)));

    Future<void> show(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogPage(
              controller: catalog,
              onConnect: () {},
              onAuthenticate: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> reveal(WidgetTester tester, Finder target) async {
      final scrollable = find
          .descendant(
            of: find.byType(CatalogPage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(target, 220, scrollable: scrollable);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
    }

    Future<void> choose(
      WidgetTester tester,
      Finder filter,
      String value,
    ) async {
      await reveal(tester, filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      await tester.tap(find.text(value).last);
      await tester.pumpAndSettle();
    }

    Future<void> hide(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    test(
      'manifest identity and metadata mismatch never opens a runtime or injects preferences',
      () async {
        final current = _builds().first;
        wire.BuildManifest manifest() => wire.BuildManifest(
          buildId: current.buildId,
          packageName: current.packageName,
          repoId: current.repoId,
          version: current.version,
          sourceIds: current.sourceIds,
          sources: current.sources.map((source) => source.deepCopy()),
          bundle: wire.BundleArtifact(sha256: 'a' * 64),
        );
        final mismatches = [
          manifest()..packageName = 'eu.kanade.source.another',
          manifest()..repoId = 'another-repository',
          manifest()..sources.first.name = 'different name',
          manifest()..sources.last.lang = 'ja',
          manifest()..sourceIds.removeLast(),
        ];
        for (final value in mismatches) {
          platform.manifestOverride = value;
          await catalog.openBuild(catalog.builds.first);
          expect(catalog.error, contains('重新连接以刷新目录'));
          expect(catalog.activeBuild, isNull);
          expect(platform.openedBuilds, isEmpty);
          expect(platform.preferenceBootstraps, isEmpty);
          expect(platform.invocations, isEmpty);
        }
        expect(
          platform.businessServer.requests.where(
            (request) => request.method == 'POST',
          ),
          isEmpty,
        );
      },
    );

    testWidgets(
      'static names and language projection work before executing any extension',
      (tester) async {
        await show(tester);
        await reveal(tester, languageFilter());
        expect(find.text('匹配 4 / 4 个扩展 · 5 / 5 个漫画源'), findsOneWidget);
        expect(find.text('中文目录源 · zh'), findsOneWidget);
        expect(find.text('English source · en'), findsOneWidget);
        final commands = platform.controlCommands.length;
        final business = platform.businessServer.requests.length;

        await choose(tester, languageFilter(), 'all');
        expect(build('build-3'), findsOneWidget);
        expect(build('build-1'), findsNothing);
        expect(find.text('多语言目录源 · all'), findsOneWidget);
        expect(find.text('匹配 1 / 4 个扩展 · 1 / 5 个漫画源'), findsOneWidget);
        await choose(tester, languageFilter(), '未标注语言');
        expect(
          tester.widget<DropdownButton<String>>(languageFilter()).value,
          '',
        );
        expect(build('build-4'), findsOneWidget);
        expect(find.text('未标注目录源 · 未标注语言'), findsOneWidget);
        await reveal(tester, clearFilter());
        await tester.tap(clearFilter());
        await tester.pumpAndSettle();
        expect(find.text('匹配 4 / 4 个扩展 · 5 / 5 个漫画源'), findsOneWidget);
        expect(platform.controlCommands, hasLength(commands));
        expect(platform.businessServer.requests, hasLength(business));
        expect(platform.openedBuilds, isEmpty);
        expect(platform.invocations, isEmpty);
        expect(catalog.session, isNull);
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );

    testWidgets(
      'directory filtering preserves current manga context and is independent of loaded languages',
      (tester) async {
        await catalog.openBuild(catalog.builds.first);
        await catalog.selectSource(catalog.session!.sources.first);
        final activeBuild = catalog.activeBuild;
        final activeSource = catalog.activeSource;
        final manga = catalog.mangas.single;
        await show(tester);
        final commands = platform.controlCommands.length;
        final business = platform.businessServer.requests.length;
        await choose(tester, languageFilter(), 'ja');
        expect(build('build-1'), findsNothing);
        expect(
          find.text('当前使用扩展：${activeBuild!.packageName}（不在当前目录筛选中）'),
          findsOneWidget,
        );
        final loadedFilter = find.byKey(
          const ValueKey('source-language-filter'),
        );
        await choose(tester, loadedFilter, 'zh');
        expect(catalog.activeBuild, same(activeBuild));
        expect(catalog.activeSource, same(activeSource));
        expect(catalog.mangas.single, same(manga));
        expect(platform.controlCommands, hasLength(commands));
        expect(platform.businessServer.requests, hasLength(business));
        await reveal(tester, languageFilter());
        expect(
          tester.widget<DropdownButton<String>>(languageFilter()).value,
          'ja',
        );
        platform.runtimeGeneration = 'generation-2';
        platform.manifestBuildId = 'build-2';
        final nextBuild = find.byKey(
          const ValueKey(('catalog-build-open', 'build-2')),
        );
        await reveal(tester, nextBuild);
        await tester.tap(nextBuild);
        await tester.pumpAndSettle();
        await reveal(tester, loadedFilter);
        expect(catalog.session!.generation, 'generation-2');
        expect(
          tester.widget<DropdownButton<String>>(loadedFilter).value,
          isNull,
        );
        await reveal(tester, languageFilter());
        expect(
          tester.widget<DropdownButton<String>>(languageFilter()).value,
          'ja',
        );
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );

    testWidgets(
      'refresh reconciles removed languages and changed identities without stale dropdown values',
      (tester) async {
        await show(tester);
        await choose(tester, languageFilter(), 'en');
        await catalog.connect();
        await tester.pumpAndSettle();
        await reveal(tester, languageFilter());
        expect(
          tester.widget<DropdownButton<String>>(languageFilter()).value,
          'en',
        );
        platform.inventory = _index([_builds()[1]]);
        await catalog.connect();
        await tester.pumpAndSettle();
        await reveal(tester, languageFilter());
        expect(
          tester.widget<DropdownButton<String>>(languageFilter()).value,
          isNull,
        );
        expect(find.text('匹配 1 / 1 个扩展 · 1 / 1 个漫画源'), findsOneWidget);
        await choose(tester, languageFilter(), 'ja');
        platform.bootstrapSubject = 'another-subject';
        await catalog.connect();
        await tester.pumpAndSettle();
        await reveal(tester, languageFilter());
        expect(
          tester.widget<DropdownButton<String>>(languageFilter()).value,
          isNull,
        );
        expect(platform.invocations, isEmpty);
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );

    testWidgets(
      'an empty directory has no installed claim and busy loading disables directory actions',
      (tester) async {
        platform.inventory = _index([]);
        await catalog.connect();
        await show(tester);
        expect(find.text('当前目录没有可用构建，请稍后重新连接以刷新目录。'), findsOneWidget);
        expect(languageFilter(), findsNothing);
        expect(find.textContaining('已安装'), findsNothing);
        platform.inventory = _index(_builds());
        await catalog.connect();
        await tester.pumpAndSettle();
        await choose(tester, languageFilter(), 'en');
        final entered = Completer<void>(), release = Completer<void>();
        addTearDown(() {
          if (!release.isCompleted) release.complete();
        });
        platform.beforeApiFetch = (path) async {
          if (!path.endsWith('/manifest.json')) return;
          entered.complete();
          await release.future;
        };
        final loading = catalog.openBuild(catalog.builds.first);
        for (var pump = 0; pump < 20 && !entered.isCompleted; pump++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(entered.isCompleted, true);
        await tester.pump();
        await tester.ensureVisible(languageFilter());
        await tester.pump();
        expect(catalog.busy, true);
        expect(
          tester.widget<DropdownButton<String>>(languageFilter()).onChanged,
          isNull,
        );
        expect(tester.widget<TextButton>(clearFilter()).onPressed, isNull);
        expect(platform.openedBuilds, isEmpty);
        release.complete();
        await loading;
        await tester.pumpAndSettle();
        expect(
          tester.widget<DropdownButton<String>>(languageFilter()).value,
          'en',
        );
        expect(
          tester.widget<DropdownButton<String>>(languageFilter()).onChanged,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );
  });
}
