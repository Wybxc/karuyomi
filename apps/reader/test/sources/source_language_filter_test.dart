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

  Finder source(String id) => find.byKey(ValueKey(('catalog-source', id)));
  Finder languageFilter() =>
      find.byKey(const ValueKey('source-language-filter'));
  Finder clearFilter() => find.byKey(const ValueKey('source-language-clear'));

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

  Future<void> hide(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
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
    'loaded language projection preserves active source and requests, with distinct all and long source IDs',
    (tester) async {
      await catalog.selectSource(catalog.session!.sources.first);
      await show(tester);
      await reveal(tester, languageFilter());
      expect(find.text('匹配 5 / 5 个漫画源'), findsOneWidget);
      final controlsBefore = platform.controlCommands.length;
      final businessBefore = platform.businessServer.requests.length;
      final callsBefore = platform.invocations.length;

      await chooseLanguage(tester, 'en');
      expect(source('42'), findsOneWidget);
      expect(source(sourceId), findsNothing);
      expect(find.text('匹配 1 / 5 个漫画源'), findsOneWidget);
      expect(find.text('当前使用：中文甲 · zh（不在当前筛选中）'), findsOneWidget);
      expect(catalog.activeSource!.id, sourceId);
      expect(catalog.mangas.single.title, testManga.title);

      await chooseLanguage(tester, 'all');
      expect(source('44'), findsOneWidget);
      expect(source('42'), findsNothing);
      expect(find.text('匹配 1 / 5 个漫画源'), findsOneWidget);
      await tap(tester, clearFilter());
      expect(find.text('匹配 5 / 5 个漫画源'), findsOneWidget);
      expect(tester.widget<FilterChip>(source(sourceId)).selected, true);
      await chooseLanguage(tester, '全部语言');
      expect(find.text('匹配 5 / 5 个漫画源'), findsOneWidget);
      await chooseLanguage(tester, 'zh');
      expect(find.text('匹配 2 / 5 个漫画源'), findsOneWidget);
      expect(platform.controlCommands, hasLength(controlsBefore));
      expect(platform.businessServer.requests, hasLength(businessBefore));
      expect(platform.invocations, hasLength(callsBefore));
      expect(catalog.activeSource!.id, sourceId);

      await tap(tester, source(_secondSourceId));
      expect(catalog.activeSource!.id, _secondSourceId);
      expect(platform.invocations, hasLength(callsBefore + 1));
      expect(platform.invocations.last.sourceId, _secondSourceId);
      expect(tester.widget<FilterChip>(source(_secondSourceId)).selected, true);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'switching package and generation clears only the session filter',
    (tester) async {
      await show(tester);
      await chooseLanguage(tester, 'zh');
      expect(find.text('匹配 2 / 5 个漫画源'), findsOneWidget);
      platform.manifestBuildId = 'build-2';
      await tap(tester, find.text('eu.kanade.source.other · 2.0'));
      await reveal(tester, languageFilter());
      expect(catalog.activeBuild!.packageName, 'eu.kanade.source.other');
      expect(
        tester.widget<DropdownButton<String>>(languageFilter()).value,
        isNull,
      );
      expect(find.text('匹配 5 / 5 个漫画源'), findsOneWidget);
      expect(catalog.activeSource, isNull);

      await chooseLanguage(tester, 'en');
      expect(find.text('匹配 1 / 5 个漫画源'), findsOneWidget);
      platform.runtimeGeneration = 'generation-2';
      await catalog.connect();
      await tester.pumpAndSettle();
      await tap(tester, find.text('eu.kanade.source.other · 2.0'));
      await reveal(tester, languageFilter());
      expect(catalog.session!.generation, 'generation-2');
      expect(
        tester.widget<DropdownButton<String>>(languageFilter()).value,
        isNull,
      );
      expect(find.text('匹配 5 / 5 个漫画源'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'no loaded session hides language controls until a confirmed extension opens',
    (tester) async {
      await catalog.connect();
      await show(tester);
      expect(catalog.session, isNull);
      expect(languageFilter(), findsNothing);
      expect(clearFilter(), findsNothing);
      expect(find.byKey(const ValueKey('source-language-count')), findsNothing);
      expect(platform.invocations, isEmpty);
      await tap(tester, find.text('eu.kanade.source.test · 1.0'));
      await reveal(tester, languageFilter());
      expect(find.text('匹配 5 / 5 个漫画源'), findsOneWidget);
      expect(
        tester.widget<DropdownButton<String>>(languageFilter()).onChanged,
        isNotNull,
      );
      expect(tester.widget<TextButton>(clearFilter()).onPressed, isNull);
      expect(platform.invocations, isEmpty);
      expect(catalog.activeSource, isNull);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'busy loading prevents source changes and resumes the same filter',
    (tester) async {
      await catalog.selectSource(catalog.session!.sources.first);
      await show(tester);
      await chooseLanguage(tester, 'zh');
      await reveal(tester, source(_secondSourceId));
      final pending = Completer<void>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete();
      });
      platform.invokeHandler = (call) async {
        if (call.whichRequest() == wire.SourceCall_Request.latest) {
          await pending.future;
        }
        return wire.SourceResult(
          mangaPage: wire.MangaPage(mangas: [testManga]),
        );
      };
      final loading = catalog.loadMangas(operation: 'latest');
      await tester.pump();
      expect(catalog.busy, true);
      await tester.ensureVisible(source(_secondSourceId));
      await tester.pump();
      expect(
        tester.widget<FilterChip>(source(_secondSourceId)).onSelected,
        isNull,
      );
      expect(
        tester.widget<DropdownButton<String>>(languageFilter()).onChanged,
        isNull,
      );
      expect(tester.widget<TextButton>(clearFilter()).onPressed, isNull);
      final callsBefore = platform.invocations.length;
      await tester.tap(source(_secondSourceId));
      await tester.pump();
      expect(catalog.activeSource!.id, sourceId);
      expect(platform.invocations, hasLength(callsBefore));
      expect(find.text('匹配 2 / 5 个漫画源'), findsOneWidget);

      pending.complete();
      await loading;
      await tester.pumpAndSettle();
      expect(catalog.busy, false);
      expect(
        tester.widget<DropdownButton<String>>(languageFilter()).value,
        'zh',
      );
      await tap(tester, source(_secondSourceId));
      expect(catalog.activeSource!.id, _secondSourceId);
      expect(platform.invocations.last.sourceId, _secondSourceId);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );
}
