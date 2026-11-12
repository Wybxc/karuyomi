import '../test_app.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';

const _secondSourceId = '-9223372036854775807';

void main() {
  late TestPlatform platform;
  late CatalogController catalog;

  setUp(() async {
    platform = TestPlatform()
      ..sourceInventory = [
        wire.SourceInfo(id: sourceId, name: '中文甲', lang: 'zh'),
        wire.SourceInfo(id: _secondSourceId, name: '中文乙', lang: 'zh'),
        wire.SourceInfo(id: '42', name: 'English', lang: 'en'),
        wire.SourceInfo(id: '43', name: '日本語', lang: 'ja'),
        wire.SourceInfo(id: '44', name: '多语言', lang: 'all'),
      ]
      ..inventory = wire.encodeProtoJson(
        wire.ExtensionIndex(
          schemaVersion: 1,
          repoId: 'keiyoushi',
          builds: [
            wire.ExtensionBuildDescriptor(
              buildId: 'build-1',
              packageName: 'eu.kanade.source.test',
              sourceIds: [sourceId, _secondSourceId, '42', '43', '44'],
              repoId: 'keiyoushi',
              sources: [
                wire.CatalogSource(id: sourceId, name: '中文甲', lang: 'zh'),
                wire.CatalogSource(
                  id: _secondSourceId,
                  name: '中文乙',
                  lang: 'zh',
                ),
                wire.CatalogSource(id: '42', name: 'English', lang: 'en'),
                wire.CatalogSource(id: '43', name: '日本語', lang: 'ja'),
                wire.CatalogSource(id: '44', name: '多语言', lang: 'all'),
              ],
              version: '1.0',
              manifestPath: '/extensions/builds/build-1/manifest.json',
            ),
            wire.ExtensionBuildDescriptor(
              buildId: 'build-2',
              packageName: 'eu.kanade.source.other',
              sourceIds: [sourceId, _secondSourceId, '42', '43', '44'],
              repoId: 'keiyoushi',
              sources: [
                wire.CatalogSource(id: sourceId, name: '中文甲', lang: 'zh'),
                wire.CatalogSource(
                  id: _secondSourceId,
                  name: '中文乙',
                  lang: 'zh',
                ),
                wire.CatalogSource(id: '42', name: 'English', lang: 'en'),
                wire.CatalogSource(id: '43', name: '日本語', lang: 'ja'),
                wire.CatalogSource(id: '44', name: '多语言', lang: 'all'),
              ],
              version: '2.0',
              manifestPath: '/extensions/builds/build-2/manifest.json',
            ),
          ],
        ),
      );
    platform.seedInstalledBuilds(
      wire.decodeProtoJson(wire.ExtensionIndex(), platform.inventory).builds,
    );
    catalog = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    await catalog.openBuild(catalog.builds.first);
  });

  tearDown(() async {
    catalog.dispose();
    await catalog.closeReadingProgress();
    await platform.dispose();
  });

  Finder source(String id, [String package = 'eu.kanade.source.test']) =>
      find.byKey(ValueKey(('source-directory-row', package, id)));
  Finder languageFilter() =>
      find.byKey(const ValueKey('source-language-filter'));
  Finder clearFilter() => find.byKey(const ValueKey('source-language-clear'));

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpApp(
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

  Future<void> hide(WidgetTester tester) async {
    await tester.pumpApp(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scrollable = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    if (target.evaluate().isEmpty) {
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.minScrollExtent);
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(target, 220, scrollable: scrollable);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await reveal(tester, target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> chooseLanguage(WidgetTester tester, String language) async {
    await tap(tester, languageFilter());
    await tester.tap(find.text(language).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'language projection uses installed static metadata before opening and preserves the active Source',
    (tester) async {
      await catalog.selectSource(catalog.session!.sources.first);
      await show(tester);
      final active = catalog.activeSource;
      final manga = catalog.mangas.single;
      final controls = platform.controlCommands.length;
      final calls = platform.invocations.length;
      final business = platform.businessServer.requests.length;
      await chooseLanguage(tester, 'en');
      expect(source('42'), findsOneWidget);
      expect(source(sourceId), findsNothing);
      await chooseLanguage(tester, 'all');
      expect(source('44'), findsOneWidget);
      expect(source('42'), findsNothing);
      await tap(tester, clearFilter());
      await chooseLanguage(tester, 'zh');
      expect(source(sourceId), findsOneWidget);
      expect(source(_secondSourceId), findsOneWidget);
      expect(catalog.activeSource, same(active));
      expect(catalog.mangas.single, same(manga));
      expect(platform.controlCommands, hasLength(controls));
      expect(platform.invocations, hasLength(calls));
      expect(platform.businessServer.requests, hasLength(business));
      await tap(tester, source(_secondSourceId));
      expect(catalog.activeSource!.id, _secondSourceId);
      expect(platform.invocations.last.sourceId, _secondSourceId);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButton<String>>(languageFilter()).value,
        'zh',
      );
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'no runtime session is required to search, filter or favorite Source names',
    (tester) async {
      await catalog.connect();
      await show(tester);
      expect(catalog.session, isNull);
      expect(languageFilter(), findsOneWidget);
      await chooseLanguage(tester, 'en');
      expect(source('42'), findsOneWidget);
      expect(platform.invocations, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('source-directory-search')),
        '不存在的名称',
      );
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的漫画源'), findsOneWidget);
      expect(find.text('尚无漫画源'), findsNothing);
      expect(platform.invocations, isEmpty);
      await hide(tester);
    },
  );

  testWidgets(
    'busy loading disables opening other Sources without losing the directory filter',
    (tester) async {
      await catalog.selectSource(catalog.session!.sources.first);
      await show(tester);
      await chooseLanguage(tester, 'zh');
      final pending = Completer<void>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete();
      });
      platform.invokeHandler = (_) async {
        await pending.future;
        return wire.SourceResult(
          mangaPage: wire.MangaPage(mangas: [testManga]),
        );
      };
      final loading = catalog.loadMangas(operation: 'latest');
      await tester.pump();
      expect(tester.widget<ListTile>(source(_secondSourceId)).onTap, isNull);
      final before = platform.invocations.length;
      await tester.tap(source(_secondSourceId));
      await tester.pump();
      expect(platform.invocations, hasLength(before));
      pending.complete();
      await loading;
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButton<String>>(languageFilter()).value,
        'zh',
      );
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );
}
