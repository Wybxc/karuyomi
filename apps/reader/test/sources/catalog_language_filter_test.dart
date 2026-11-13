import 'package:karuyomi/widgets/choice_field.dart';

import '../test_app.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
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
    wire.encodeProtoJson(
      wire.ExtensionIndex(
        schemaVersion: 1,
        repoId: 'keiyoushi',
        builds: builds,
      ),
    );

void main() {
  test(
    'catalog metadata retains exact Source identities and frozen snapshots',
    () {
      final descriptor = _builds().first;
      final build = CatalogBuild.fromProto(
        descriptor,
        catalogUrl: 'https://reader.example/extensions/index.json',
      );
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
      expect(
        CatalogBuild.fromProto(
          _builds()[2],
          catalogUrl: 'https://reader.example/extensions/index.json',
        ).sources.single.id,
        '0043',
      );
      expect(
        CatalogBuild.fromProto(
          _builds()[3],
          catalogUrl: 'https://reader.example/extensions/index.json',
        ).sources.single.lang,
        '',
      );
    },
  );

  test('catalog metadata rejects missing, duplicate, malformed and oversized values', () {
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
        () => CatalogBuild.fromProto(
          entry.value,
          catalogUrl: 'https://reader.example/extensions/index.json',
        ),
        throwsFormatException,
        reason: entry.key,
      );
    }
  });

  group('formal catalog navigation', () {
    late TestPlatform platform;
    late CatalogController catalog;

    setUp(() async {
      platform = TestPlatform()..inventory = _index(_builds());
      platform.seedInstalledBuilds(_builds());
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
        find.byKey(const ValueKey('source-language-filter'));
    Finder clearFilter() => find.byKey(const ValueKey('source-language-clear'));

    Future<void> show(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpApp(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: CatalogPage(
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
            of: find.byKey(const PageStorageKey('source-directory-scroll')),
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
      await tester.tap(find.widgetWithText(CupertinoMenuItem, value));
      await tester.pumpAndSettle();
    }

    Future<void> hide(WidgetTester tester) async {
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }

    test('manifest identity and metadata mismatch never opens a runtime or injects preferences', () async {
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
    });

    testWidgets(
      'static Source names and languages filter without executing extensions',
      (tester) async {
        await show(tester);
        expect(find.text('中文目录源'), findsOneWidget);
        final controls = platform.controlCommands.length;
        final requests = platform.businessServer.requests.length;
        await choose(tester, languageFilter(), 'all');
        expect(find.text('多语言目录源'), findsOneWidget);
        expect(find.text('中文目录源'), findsNothing);
        await choose(tester, languageFilter(), '未标注语言');
        expect(tester.widget<ChoiceField<String>>(languageFilter()).value, '');
        expect(find.text('未标注目录源'), findsOneWidget);
        await tester.tap(clearFilter());
        await tester.pumpAndSettle();
        expect(find.text('中文目录源'), findsOneWidget);
        expect(platform.controlCommands, hasLength(controls));
        expect(platform.businessServer.requests, hasLength(requests));
        expect(platform.openedBuilds, isEmpty);
        expect(platform.invocations, isEmpty);
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );

    testWidgets(
      'filtering preserves existing reading context and reconciles removed languages',
      (tester) async {
        platform.sourceInventory = [
          wire.SourceInfo(id: sourceId, name: '中文目录源', lang: 'zh'),
        ];
        await catalog.openBuild(catalog.builds.first);
        await catalog.selectSource(catalog.session!.sources.first);
        final active = catalog.activeSource;
        final manga = catalog.mangas.single;
        await show(tester);
        expect(catalog.activeSource, same(active), reason: '挂载目录保留已打开的 Source');
        final commands = platform.controlCommands.length;
        await choose(tester, languageFilter(), 'ja');
        expect(catalog.activeSource, same(active));
        expect(catalog.mangas.single, same(manga));
        expect(platform.controlCommands, hasLength(commands));
        platform.inventory = _index([_builds()[0]]);
        await catalog.connect();
        await tester.pumpAndSettle();
        expect(
          tester.widget<ChoiceField<String>>(languageFilter()).value,
          isNull,
        );
        await choose(tester, languageFilter(), 'en');
        platform.bootstrapSubject = 'another-subject';
        await catalog.connect();
        await tester.pumpAndSettle();
        expect(
          tester.widget<ChoiceField<String>>(languageFilter()).value,
          isNull,
        );
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );

    testWidgets(
      'missing installed version is a blocked extension row rather than new Source metadata',
      (tester) async {
        final changed = _build('replacement', [
          wire.CatalogSource(id: '99', name: '新版本独有漫画源', lang: 'en'),
        ])..packageName = _builds().first.packageName;
        platform.inventory = _index([changed]);
        await catalog.connect();
        await show(tester);
        expect(
          find.byKey(
            ValueKey(('source-extension-blocked', changed.packageName)),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            ValueKey(('source-directory-row', changed.packageName, '99')),
          ),
          findsNothing,
        );
        expect(
          find.byKey(
            ValueKey(('source-favorite-toggle', changed.packageName, '99')),
          ),
          findsNothing,
        );
        expect(find.textContaining('尚无漫画源'), findsNothing);
        expect(platform.openedBuilds, isEmpty);
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );

    testWidgets(
      'no account installations leads to extension installation and refreshes the Source tab',
      (tester) async {
        platform.seedInstalledBuilds(const []);
        await catalog.connect();
        await show(tester);
        expect(find.text('尚无漫画源'), findsOneWidget);
        await tester.tap(find.text('前往扩展'));
        await tester.pumpAndSettle();
        final target = _builds().first;
        await tester.enterText(
          find.byKey(const ValueKey('extensions-search')),
          '中文目录源',
        );
        await tester.pumpAndSettle();
        final install = find.byKey(
          ValueKey((
            'extension-install',
            catalog.catalogUrl,
            target.packageName,
          )),
        );
        await tester.ensureVisible(install);
        await tester.tap(install);
        await tester.pumpAndSettle();
        await tester.tap(find.text('漫画源').first);
        await tester.pumpAndSettle();
        expect(find.text('中文目录源'), findsOneWidget);
        expect(
          catalog.installedExtensions.single.packageName,
          target.packageName,
        );
        expect(platform.openedBuilds, isEmpty);
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );
  });
}
