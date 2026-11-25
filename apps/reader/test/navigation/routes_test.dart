import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/extensions/extensions_page.dart';
import 'package:karuyomi/features/history/browsing_history_page.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/navigation/app_location.dart';
import 'package:karuyomi/navigation/app_navigation.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import '../test_app.dart';

const _package = 'eu.kanade.source.test';
const _source = (packageName: _package, sourceId: sourceId);
const _sourceAddress = AppLocation(AppTab.browse, source: _source);

Uri _address(WidgetTester tester) =>
    GoRouter.of(tester.element(find.byType(AppShell, skipOffstage: false)))
        .routeInformationProvider
        .value
        .uri;

Future<void> _browserLocation(WidgetTester tester, String location) async {
  final response = Completer<void>();
  unawaited(
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          SystemChannels.navigation.name,
          const JSONMethodCodec().encodeMethodCall(
            MethodCall('pushRouteInformation', {
              'location': location,
              'state': null,
            }),
          ),
          (_) => response.complete(),
        ),
  );
  await tester.pumpAndSettle();
  await response.future;
}

Future<void> _openSource(WidgetTester tester) async {
  await tester.tap(find.text('去浏览'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey(('source-directory-row', _package, sourceId))),
  );
  await tester.pumpAndSettle();
}

Future<void> _start(
  WidgetTester tester,
  TestPlatform platform, {
  String initialLocation = '/',
}) async {
  tester.binding.platformDispatcher.defaultRouteNameTestValue = initialLocation;
  await tester.pumpApp(KaruyomiApp(platform: platform));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'route keys retain exact Source IDs and snapshot chapter occurrences',
    () {
      final key = 'a' * 64;
      final chapter = 'snapshot-${'b' * 64}';
      final location = const AppLocation(
        AppTab.browse,
        source: (packageName: _package, sourceId: '-9223372036854775808'),
      ).withManga(key).withChapter(key, chapter);
      expect(AppLocation.parse(Uri.parse(location.path)), location);
      expect(location.parent.mangaKey, key);
      expect(location.parent.parent.source?.sourceId, '-9223372036854775808');
      expect(
        AppLocation.parse(
          Uri.parse('/app/browse/source/$_package/9223372036854775808'),
        ),
        isNull,
      );
    },
  );

  testWidgets(
    'cold tab and browser back and forward drive the same adaptive views',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final platform = TestPlatform();
      await _start(tester, platform, initialLocation: '/app/history');
      expect(find.byType(BrowsingHistoryPage), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey(('app-destination', 'browse'))),
      );
      await tester.pumpAndSettle();
      expect(_address(tester).path, '/app/browse');

      await _browserLocation(tester, '/app/history');
      expect(find.byType(BrowsingHistoryPage), findsOneWidget);
      await _browserLocation(tester, '/app/browse');
      expect(_address(tester).path, '/app/browse');
      expect(find.byType(BrowsingHistoryPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('extension and settings subpages accept direct links', (
    tester,
  ) async {
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final platform = TestPlatform();
    await _start(tester, platform, initialLocation: '/app/settings/about');
    expect(
      find.byKey(const ValueKey(('settings-content', SettingsSection.about))),
      findsOneWidget,
    );

    final repository = wire.CatalogReference(
      catalogUrl: '${platform.origin}/extensions/index.json',
      repoId: 'keiyoushi',
    );
    final itemAddress =
        '/app/extensions/item/${catalogLocationKey(repository)}/$_package';
    await _browserLocation(tester, itemAddress);
    expect(find.byType(ExtensionDetailsPage), findsOneWidget);
    await _browserLocation(tester, '/app/extensions/storage');
    expect(find.byType(ExtensionStoragePage), findsOneWidget);
    await _browserLocation(tester, '/app/extensions/repositories');
    expect(find.byType(ExtensionRepositoriesPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'uncollected Source result and reader links reopen in a fresh client of the same account',
    (tester) async {
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final first = TestPlatform();
      await _start(tester, first);
      await _openSource(tester);
      expect(_address(tester).path, _sourceAddress.path);
      await tester.tap(find.text(testManga.title));
      await tester.pumpAndSettle();
      final detailsAddress = _address(tester).path;
      expect(detailsAddress, startsWith('${_sourceAddress.path}/manga/'));
      expect(detailsAddress, isNot(contains(testManga.url)));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_address(tester).path, _sourceAddress.path);

      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final fresh = TestPlatform(businessServer: first.businessServer);
      await _start(tester, fresh, initialLocation: detailsAddress);
      final detail = find.byType(MangaDetailsPage);
      expect(detail, findsOneWidget);
      final fromLink = tester.widget<MangaDetailsPage>(detail);
      expect(fromLink.manga.url, testManga.url);
      final sequence = ChapterSequence(
        packageName: _package,
        sourceId: sourceId,
        mangaUrl: fromLink.manga.url,
        chapters: fromLink.chapters.map((value) => value.snapshot),
      );
      final chapter = sequence.entries.single;
      final readerAddress = '$detailsAddress/read/${chapter.key}';
      await _browserLocation(tester, readerAddress);
      expect(
        tester
            .widget<ChapterReaderRoute>(find.byType(ChapterReaderRoute))
            .initialChapter
            .key,
        chapter.key,
      );
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _start(
        tester,
        TestPlatform(businessServer: first.businessServer),
        initialLocation: readerAddress,
      );
      expect(find.byType(ChapterReaderRoute), findsOneWidget);
      await _browserLocation(tester, detailsAddress);
      expect(find.byType(ChapterReaderRoute), findsNothing);
      expect(detail, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an account link cannot resolve a work held only by another account',
    (tester) async {
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );
      final platform = TestPlatform(bootstrapSubject: 'other-reader');
      await _start(
        tester,
        platform,
        initialLocation: '/app/history/manga/${'a' * 64}',
      );
      expect(find.text('在当前账号的书架和浏览记录中找不到这部作品。'), findsOneWidget);
      expect(
        platform.invocations.where((wire.SourceCall call) => call.hasDetails()),
        isEmpty,
      );
    },
  );
}
