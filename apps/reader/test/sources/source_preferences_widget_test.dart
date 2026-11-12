import '../test_app.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/source_browse_page.dart';
import 'package:karuyomi/features/sources/source_preferences.dart';

import 'preference_fixtures.dart';

void main() {
  late PreferenceFixture fixture;
  setUp(() async {
    fixture = PreferenceFixture();
    await fixture.open();
  });
  tearDown(() => fixture.close());

  Future<void> open(
    WidgetTester tester, {
    Future<void> Function()? beforeFirstFrame,
  }) async {
    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpApp(
      MaterialApp(
        home: Scaffold(
          body: SourceBrowsePage(
            catalog: fixture.catalog,
            build: fixture.catalog.activeBuild!,
            source: fixture.catalog.activeBuild!.sources.single,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('source-preferences-open'));
    final scrollable = find
        .descendant(
          of: find.byType(SourceBrowsePage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(button, 300, scrollable: scrollable);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await beforeFirstFrame?.call();
    await tester.pumpAndSettle();
    expect(find.byType(SourcePreferencesSheet), findsOneWidget);
  }

  Future<void> item(WidgetTester tester, String path) async {
    final finder = find.byKey(ValueKey(('source-preference', path)));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> apply(WidgetTester tester) async {
    await tester.tap(find.text('应用此设置'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the formal phone sheet edits typed controls, dependency and session fields without uploading secrets',
    (tester) async {
      await open(tester);
      expect(find.text('不应回显的密码摘要'), findsNothing);
      await item(tester, '0');
      expect(fixture.postedBodies, hasLength(1));
      await item(tester, '1');
      await tester.enterText(
        find.byType(TextField).last,
        'secret-on-this-client',
      );
      await apply(tester);
      expect(fixture.postedBodies, hasLength(1));
      expect(find.text('secret-on-this-client'), findsNothing);
      await item(tester, '2');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('服务器乙').last);
      await tester.pumpAndSettle();
      await apply(tester);
      await item(tester, '3');
      await tester.tap(find.text('中文').last);
      await tester.pumpAndSettle();
      await apply(tester);
      await item(tester, '4.0');
      await item(tester, '4.1');
      final noteInput = find.byType(TextField).last;
      final noteField = tester.widget<TextField>(noteInput);
      expect(noteField.decoration?.hintText, '可填写备注');
      final noteController = noteField.controller!;
      expect(noteController.selection.textInside(noteController.text), '原备注');
      await tester.enterText(noteInput, 'session-note');
      await apply(tester);
      await item(tester, '5');
      expect(fixture.callbacks, 7);
      expect(fixture.postedBodies, hasLength(4));
      expect(
        fixture.postedBodies.join(),
        isNot(contains('secret-on-this-client')),
      );
      expect(fixture.postedBodies.join(), isNot(contains('session-note')));
      final unsupported = find.text('需要 Android Activity，当前不支持。');
      await tester.ensureVisible(unsupported);
      await tester.pumpAndSettle();
      expect(unsupported, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭设置'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'unavailable dynamic values are explicit, a new valid option is selectable and empty options stay disabled',
    (tester) async {
      fixture.missingChoice = true;
      await open(tester);
      expect(find.textContaining('当前值已不在可选列表中'), findsOneWidget);
      await item(tester, '2');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('服务器乙').last);
      await tester.pumpAndSettle();
      await apply(tester);
      expect(fixture.postedBodies.single, contains('"text":"b"'));
      fixture.emptyOptions = true;
      await tester.tap(
        find.byKey(const ValueKey('source-preferences-refresh')),
      );
      await tester.pumpAndSettle();
      final choice = find.byKey(const ValueKey(('source-preference', '2')));
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      expect(find.textContaining('目前没有可选项'), findsOneWidget);
      expect(tester.widget<ListTile>(choice).onTap, isNull);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭设置'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'lost ACK exposes only exact retry; closing and reopening preserves pending recovery',
    (tester) async {
      await open(tester);
      fixture.loseNextPreferenceAck();
      await item(tester, '0');
      final original = fixture.postedBodies.single;
      expect(find.text('未确认的原保存请求 · 基于版本 0'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭设置'));
      await tester.pumpAndSettle();
      final recovery = find.text('处理漫画源设置');
      final scrollable = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(recovery, -300, scrollable: scrollable);
      await tester.ensureVisible(recovery);
      await tester.tap(recovery);
      await tester.pumpAndSettle();
      expect(fixture.postedBodies, [original]);
      final retry = find.byKey(const ValueKey('source-preferences-retry'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(fixture.postedBodies, [original, original]);
      expect(fixture.callbacks, 1);
      expect(fixture.platform.businessServer.appliedMutations, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭设置'));
      await tester.pumpAndSettle();
    },
  );
  for (final denied in [true, false]) {
    testWidgets(
      'settings sheet keeps the clicked repository when ${denied ? 'Access fails' : 'the account changes'} before its first frame',
      (tester) async {
        final clicked = fixture.repository;
        var requests = 0;
        final invocations = fixture.platform.invocations.length;
        final opened = fixture.platform.openedBuilds.length;
        await open(
          tester,
          beforeFirstFrame: () async {
            if (denied) {
              fixture.platform.bootstrapStatus = 403;
            } else {
              fixture.platform.bootstrapSubject = 'other-subject';
            }
            await fixture.catalog.connect();
            requests = fixture.platform.businessServer.requests
                .where(
                  (request) =>
                      request.uri.path.startsWith('/api/source-preferences/'),
                )
                .length;
          },
        );
        expect(tester.takeException(), isNull);
        expect(
          fixture.platform.businessServer.requests.where(
            (request) =>
                request.uri.path.startsWith('/api/source-preferences/'),
          ),
          hasLength(requests),
        );
        expect(
          fixture.platform.businessServer.requests.where(
            (request) => request.method == 'POST',
          ),
          isEmpty,
        );
        expect(fixture.platform.invocations, hasLength(invocations));
        expect(fixture.platform.openedBuilds, hasLength(opened));
        expect(fixture.postedBodies, isEmpty);
        expect(find.text('身份或服务已改变，请关闭后重新打开漫画源设置。'), findsOneWidget);
        fixture.platform.bootstrapStatus = 200;
        fixture.platform.bootstrapSubject = 'owner-subject';
        await fixture.catalog.connect();
        if (denied) {
          expect(identical(fixture.repository, clicked), true);
        }
        requests = fixture.platform.businessServer.requests
            .where(
              (request) =>
                  request.uri.path.startsWith('/api/source-preferences/'),
            )
            .length;
        await tester.pumpAndSettle();
        final refresh = find.byKey(
          const ValueKey('source-preferences-refresh'),
        );
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(
          fixture.platform.businessServer.requests.where(
            (request) =>
                request.uri.path.startsWith('/api/source-preferences/'),
          ),
          hasLength(requests),
        );
        expect(
          fixture.platform.businessServer.requests.where(
            (request) => request.method == 'POST',
          ),
          isEmpty,
        );
        expect(fixture.platform.invocations, hasLength(invocations));
        expect(fixture.platform.openedBuilds, hasLength(opened));
        expect(fixture.postedBodies, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('关闭设置'));
        await tester.pumpAndSettle();
      },
    );
  }
}
