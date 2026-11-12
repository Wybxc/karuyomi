import '../test_app.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/features/library/library_page.dart';

import '../browse/fakes.dart';

void main() {
  testWidgets('navigation and foreground refresh only read confirmed state', (
    tester,
  ) async {
    final platform = TestPlatform();
    final phases = <String, Map<String, int>>{};
    void record(String phase) {
      final counts = <String, int>{};
      for (final request in platform.businessServer.requests) {
        final key = '${request.method} ${request.uri.path}';
        counts.update(key, (value) => value + 1, ifAbsent: () => 1);
      }
      phases[phase] = counts;
    }

    await tester.pumpApp(KaruyomiApp(platform: platform));
    await tester.pumpAndSettle();
    record('initial');
    final catalog = tester
        .widget<LibraryPage>(find.byType(LibraryPage))
        .controller!;
    await catalog.library!.setFavorite(
      packageName: 'eu.kanade.source.test',
      sourceId: sourceId,
      sourceName: '测试漫画源',
      sourceLang: 'zh',
      manga: testManga,
      favorite: true,
    );
    await tester.pumpAndSettle();
    expect(find.text(testManga.title), findsOneWidget);

    await tester.tap(find.text('浏览').last);
    await tester.pumpAndSettle();
    record('browse');
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    record('settings');
    await tester.tap(find.text('书架').last);
    await tester.pumpAndSettle();
    expect(find.text(testManga.title), findsOneWidget);
    record('remount');
    setAppLifecycleState(tester.binding, AppLifecycleState.inactive);
    setAppLifecycleState(tester.binding, AppLifecycleState.paused);
    setAppLifecycleState(tester.binding, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    record('foreground');

    expect(
      platform.businessServer.requests.where(
        (request) => request.method != 'GET',
      ),
      hasLength(1),
    );
    expect(platform.invocations, isEmpty);
    expect(tester.takeException(), isNull);
    debugPrint('STATE_REQUEST_BUDGET ${jsonEncode(phases)}');
    await tester.pumpApp(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(platform.disposalCount, 1);
  });
}
