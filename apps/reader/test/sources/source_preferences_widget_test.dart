import '../../test_support/cupertino.dart';

import 'dart:async';

import 'package:karuyomi/widgets/choice_field.dart';

import '../test_app.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/source_browse_page.dart';
import 'package:karuyomi/features/sources/source_preferences.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

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
    Brightness? appearance,
    double textScale = 1,
    Size size = const Size(480, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpApp(
      CupertinoApp(
        theme: readerAppTheme(appearance),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: CupertinoPageScaffold(
          child: SourceBrowsePage(
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
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
  }

  for (final appearance in Brightness.values) {
    testWidgets(
      'an account choice shows a repeated option label once and keeps distinct help in $appearance',
      (tester) async {
        final invoke = fixture.platform.invokeHandler!;
        fixture.platform.invokeHandler = (call) async {
          final result = await invoke(call);
          if (result.hasPreferences()) {
            final node = result.preferences.nodes[2];
            node.summary = node.choice.value == 'a' ? '服务器甲' : '优先使用该镜像浏览';
          }
          return result;
        };
        await open(tester, appearance: appearance, size: const Size(360, 800));
        expect(find.textContaining('服务器甲'), findsOneWidget);
        final choice = find.byKey(const ValueKey(('source-preference', '2')));
        await item(tester, '2');
        await tester.tap(find.widgetWithText(CupertinoMenuItem, '服务器乙'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: choice, matching: find.text('服务器乙')),
          findsOneWidget,
        );
        expect(find.text('优先使用该镜像浏览\n服务端确认后同步'), findsOneWidget);
        expect(fixture.callbacks, 1);
        expect(fixture.postedBodies, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.tap(iconLabel('关闭设置'));
        await tester.pumpAndSettle();
      },
    );

    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'rejected session input uses the error role and remains correctable in $appearance at $textScale',
        (tester) async {
          fixture.editGate = (_) async => wire.SourceResult(
            preferenceEdit: wire.PreferenceEditResult(
              snapshot: fixture.snapshot(),
            ),
          );
          await open(
            tester,
            appearance: appearance,
            textScale: textScale,
            size: const Size(360, 800),
          );
          await item(tester, '4.1');
          await tester.enterText(
            find.byType(CupertinoTextField).last,
            'not-accepted-value',
          );
          await apply(tester);
          final rejection = find.text('漫画源未接受输入；设置未更改。');
          final scrollable = find
              .descendant(
                of: find.byKey(const ValueKey('source-preferences-form')),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            rejection,
            -250,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          expect(rejection, findsOneWidget);
          await tester.ensureVisible(rejection);
          await tester.pumpAndSettle();
          expect(
            tester.widget<Text>(rejection).style?.color,
            AppColors.error.resolveFrom(tester.element(rejection)),
          );
          expect(find.text('设置已确认。'), findsNothing);
          expect(fixture.callbacks, 1);
          expect(fixture.postedBodies, isEmpty);

          await item(tester, '4.1');
          expect(
            tester
                .widget<CupertinoTextField>(
                  find.byType(CupertinoTextField).last,
                )
                .controller!
                .text,
            '原备注',
          );
          fixture.editGate = null;
          await tester.enterText(
            find.byType(CupertinoTextField).last,
            '已修正的会话备注',
          );
          await apply(tester);
          await tester.scrollUntilVisible(
            find.text('设置已确认。'),
            -250,
            scrollable: scrollable,
          );
          await tester.pumpAndSettle();
          expect(rejection, findsNothing);
          expect(find.text('设置已确认。'), findsOneWidget);
          expect(fixture.values['note']!.value.text, '已修正的会话备注');
          expect(fixture.callbacks, 2);
          expect(fixture.postedBodies, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.tap(iconLabel('关闭设置'));
          await tester.pumpAndSettle();
        },
      );
      testWidgets(
        'multi-choice preferences group long options and keep cancel and apply explicit in $appearance at $textScale',
        (tester) async {
          final original = fixture.platform.invokeHandler!;
          final longLabel = '中文章节与完整扫描组名称' * 6;
          fixture.platform.invokeHandler = (call) async {
            final result = await original(call);
            if (call.hasGetPreferences()) {
              final multi = result.preferences.nodes[3].multiChoice;
              multi.values
                ..clear()
                ..addAll(['en', 'removed']);
              multi.options.first.label = longLabel;
            }
            return result;
          };
          await open(
            tester,
            appearance: appearance,
            textScale: textScale,
            size: const Size(360, 800),
          );
          await item(tester, '3');
          final label = find.text(longLabel);
          expect(
            find.ancestor(
              of: label,
              matching: find.byType(CupertinoFormSection),
            ),
            findsOneWidget,
            reason: 'multi-choice rows use the same native grouped form as other preference controls',
          );
          expect(
            tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
            isFalse,
          );
          final note = tester.element(
            find.text('部分当前值已不在可选列表中。应用新的选择时将移除这些不可用项。'),
          );
          expect(DefaultTextStyle.of(note).style.fontSize, 13);
          expect(
            DefaultTextStyle.of(note).style.color,
            CupertinoColors.secondaryLabel.resolveFrom(note),
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(label);
          await tester.tap(label);
          await tester.pumpAndSettle();
          expect(fixture.callbacks, 0);
          expect(fixture.postedBodies, isEmpty);
          await tester.tap(find.widgetWithText(CupertinoButton, '取消').last);
          await tester.pumpAndSettle();
          expect(fixture.callbacks, 0);
          await item(tester, '3');
          final options = tester.widgetList<CupertinoCheckbox>(
            find.byType(CupertinoCheckbox),
          );
          expect(options.map((option) => option.value), [false, true]);
          await tester.ensureVisible(label);
          await tester.tap(label);
          await tester.pumpAndSettle();
          await tester.tap(find.text('应用'));
          await tester.pump();
          expect(find.text('身份或漫画源已变化，请关闭后重新打开设置。'), findsNothing);
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('身份或漫画源已变化，请关闭后重新打开设置。'), findsNothing);
          await tester.pumpAndSettle();
          expect(fixture.callbacks, 1);
          expect(fixture.edits.single.change.strings.values.toSet(), {
            'en',
            'zh',
          });
          expect(fixture.postedBodies, hasLength(1));
          expect(fixture.postedBodies.single, isNot(contains('removed')));
          expect(tester.takeException(), isNull);
          await tester.tap(iconLabel('关闭设置'));
          await tester.pumpAndSettle();
        },
      );
      for (final multi in [false, true]) {
        for (final denied in [false, true]) {
          testWidgets(
            '${multi ? 'multi-choice' : 'text'} subeditor hides its draft after ${denied ? 'Access loss' : 'identity change'} in $appearance at $textScale',
            (tester) async {
              await open(
                tester,
                appearance: appearance,
                textScale: textScale,
                size: const Size(360, 800),
              );
              await item(tester, multi ? '3' : '1');
              if (multi) {
                await tester.tap(find.text('中文').last);
              } else {
                await tester.enterText(
                  find.byType(CupertinoTextField).last,
                  'unsaved-private-value',
                );
              }
              await tester.pumpAndSettle();
              if (denied) {
                fixture.platform.bootstrapStatus = 403;
              } else {
                fixture.platform.bootstrapSubject = 'other-subject';
              }
              await fixture.catalog.connect();
              await tester.pumpAndSettle();
              expect(find.text('身份或漫画源已变化，请关闭后重新打开设置。'), findsOneWidget);
              expect(find.widgetWithText(CupertinoButton, '应用'), findsNothing);
              if (multi) {
                expect(find.byType(CupertinoCheckbox), findsNothing);
              } else {
                expect(
                  find.descendant(
                    of: find.byType(CupertinoAlertDialog),
                    matching: find.byType(CupertinoTextField),
                  ),
                  findsNothing,
                );
              }
              expect(fixture.callbacks, 0);
              expect(fixture.postedBodies, isEmpty);
              await tester.tap(find.widgetWithText(CupertinoButton, '关闭').last);
              await tester.pumpAndSettle();
              expect(fixture.callbacks, 0);
              expect(fixture.postedBodies, isEmpty);
              expect(tester.takeException(), isNull);
              await tester.tap(iconLabel('关闭设置'));
              await tester.pumpAndSettle();
            },
          );
        }
      }
    }
    testWidgets(
      'empty and group-first Source preferences keep their labels and inherited disabled state in $appearance',
      (tester) async {
        final original = fixture.platform.invokeHandler!;
        var empty = false;
        fixture.platform.invokeHandler = (call) async {
          final result = await original(call);
          if (call.hasGetPreferences()) {
            final toggle = result.preferences.nodes.first.deepCopy();
            result.preferences.nodes
              ..clear()
              ..addAll(
                empty
                    ? []
                    : [
                        wire.PreferenceNode(
                          title: '父级已禁用',
                          visible: true,
                          enabled: false,
                          syncScope: accountScope,
                          group: wire.PreferenceGroup(
                            nodes: [
                              wire.PreferenceNode(
                                title: '空分组说明',
                                visible: true,
                                enabled: true,
                                syncScope: accountScope,
                                group: wire.PreferenceGroup(),
                              ),
                              wire.PreferenceNode(
                                title: '嵌套条件',
                                visible: true,
                                enabled: true,
                                syncScope: accountScope,
                                group: wire.PreferenceGroup(nodes: [toggle]),
                              ),
                            ],
                          ),
                        ),
                      ],
              );
          }
          return result;
        };
        await open(tester, appearance: appearance);
        expect(tester.takeException(), isNull);
        expect(find.text('父级已禁用'), findsOneWidget);
        expect(find.text('空分组说明'), findsOneWidget);
        expect(find.text('嵌套条件'), findsOneWidget);
        final toggle = find.byKey(
          const ValueKey(('source-preference', '0.1.0')),
        );
        expect(tester.widget<CupertinoSwitch>(toggle).onChanged, isNull);
        final footer = tester.element(find.textContaining('每次修改只执行一次漫画源操作。'));
        expect(DefaultTextStyle.of(footer).style.fontSize, 13);
        expect(
          DefaultTextStyle.of(footer).style.color,
          CupertinoColors.secondaryLabel.resolveFrom(footer),
        );
        empty = true;
        final refresh = find.byKey(
          const ValueKey('source-preferences-refresh'),
        );
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final noPreferences = tester.element(find.text('这个漫画源没有额外设置。'));
        expect(DefaultTextStyle.of(noPreferences).style.fontSize, 13);
        expect(
          DefaultTextStyle.of(noPreferences).style.color,
          CupertinoColors.secondaryLabel.resolveFrom(noPreferences),
        );
        expect(find.text('父级已禁用'), findsNothing);
        expect(fixture.postedBodies, isEmpty);
        expect(fixture.callbacks, 0);
        await tester.tap(iconLabel('关闭设置'));
        await tester.pumpAndSettle();
      },
    );
    testWidgets(
      'source preference controls and help keep separate semantic roles in $appearance',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await open(tester, appearance: appearance);
          final toggle = find.byKey(const ValueKey(('source-preference', '0')));
          final label = tester.getSemantics(toggle).label;
          expect(label, contains('隐藏付费章节'));
          expect(label, isNot(contains('登录密码')));
          expect(label, isNot(contains('服务器')));
          final help = tester.element(find.text('显示全部章节\n服务端确认后同步'));
          expect(
            tester.widget<Text>(find.text('显示全部章节\n服务端确认后同步')).style!.fontSize,
            13,
          );
          expect(
            tester.widget<Text>(find.text('显示全部章节\n服务端确认后同步')).style!.color,
            CupertinoColors.secondaryLabel.resolveFrom(help),
          );
          final footer = tester.element(find.textContaining('每次修改只执行一次漫画源操作。'));
          expect(DefaultTextStyle.of(footer).style.fontSize, 13);
          expect(
            DefaultTextStyle.of(footer).style.color,
            CupertinoColors.secondaryLabel.resolveFrom(footer),
          );
          expect(fixture.postedBodies, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.tap(iconLabel('关闭设置'));
          await tester.pumpAndSettle();
        } finally {
          semantics.dispose();
        }
      },
    );
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
        find.byType(CupertinoTextField).last,
        'secret-on-this-client',
      );
      expect(
        tester
            .widget<CupertinoTextField>(find.byType(CupertinoTextField).last)
            .onSubmitted,
        isNull,
      );
      await apply(tester);
      expect(fixture.postedBodies, hasLength(1));
      expect(find.text('secret-on-this-client'), findsNothing);
      await item(tester, '2');
      await tester.tap(find.widgetWithText(CupertinoMenuItem, '服务器乙'));
      await tester.pumpAndSettle();
      await item(tester, '3');
      await tester.tap(find.text('中文').last);
      await tester.pumpAndSettle();
      await apply(tester);
      await item(tester, '4.0');
      await item(tester, '4.1');
      final noteInput = find.byType(CupertinoTextField).last;
      final noteField = tester.widget<CupertinoTextField>(noteInput);
      expect(noteField.placeholder, '可填写备注');
      final noteController = noteField.controller!;
      expect(noteController.selection.textInside(noteController.text), '原备注');
      await tester.enterText(noteInput, 'session-note');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
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
      await tester.tap(iconLabel('关闭设置'));
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
      await tester.tap(find.widgetWithText(CupertinoMenuItem, '服务器乙'));
      await tester.pumpAndSettle();
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
      expect(tester.widget<ChoiceField<String>>(choice).onChanged, isNull);
      expect(tester.takeException(), isNull);
      await tester.tap(iconLabel('关闭设置'));
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
      expect(find.text('测试漫画源 · zh'), findsOneWidget);
      await tester.tap(find.text('查看原提交值'));
      await tester.pumpAndSettle();
      expect(find.text('alias：开启'), findsOneWidget);
      expect(find.textContaining('password：'), findsNothing);
      await tester.tap(iconLabel('关闭设置'));
      await tester.pumpAndSettle();
      final recovery = find.text('处理漫画源设置');
      final scrollable = find
          .descendant(
            of: find.byType(SourceBrowsePage),
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
      await tester.tap(iconLabel('关闭设置'));
      await tester.pumpAndSettle();
    },
  );

  for (final appearance in Brightness.values) {
    testWidgets(
      'Source save transitions from confirmed reading to recoverable failure in $appearance',
      (tester) async {
        await open(
          tester,
          appearance: appearance,
          textScale: 2,
          size: const Size(360, 800),
        );
        final entered = Completer<void>();
        final release = Completer<void>();
        var failReads = true;
        fixture.platform.afterBusinessReply = (request, reply) async {
          if (request.method == 'GET' &&
              request.uri.path.startsWith(
                '/api/source-preferences/packages/',
              ) &&
              fixture.postedBodies.isNotEmpty &&
              failReads) {
            if (!entered.isCompleted) {
              entered.complete();
              await release.future;
            }
            return const ApiReply(
              status: 503,
              headers: {'content-type': 'application/json'},
              body: '{}',
              redirected: false,
            );
          }
          return reply;
        };
        await tester.tap(
          find.byKey(const ValueKey(('source-preference', '0'))),
        );
        await tester.pump();
        try {
          expect(entered.isCompleted, true);
          expect(find.text('保存已确认，正在读取最新设置。'), findsOneWidget);
          expect(find.text('未确认的原保存请求 · 基于版本 0'), findsNothing);
          expect(fixture.postedBodies, hasLength(1));
        } finally {
          release.complete();
          await tester.pumpAndSettle();
        }
        expect(find.text('已确认的原保存请求 · 基于版本 0'), findsOneWidget);
        expect(find.text('重试原保存请求'), findsNothing);
        await tester.tap(iconLabel('关闭设置'));
        await tester.pumpAndSettle();
        final recovery = find.text('处理漫画源设置');
        final scrollable = find
            .descendant(
              of: find.byType(SourceBrowsePage),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(recovery, -300, scrollable: scrollable);
        await tester.ensureVisible(recovery);
        await tester.tap(recovery);
        await tester.pumpAndSettle();
        expect(find.text('已确认的原保存请求 · 基于版本 0'), findsOneWidget);
        expect(fixture.postedBodies, hasLength(1));
        final retry = find.text('重试读取最新设置');
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(find.text('已确认的原保存请求 · 基于版本 0'), findsOneWidget);
        expect(fixture.postedBodies, hasLength(1));
        failReads = false;
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(find.text('已确认的原保存请求 · 基于版本 0'), findsNothing);
        expect(fixture.postedBodies, hasLength(1));
        expect(fixture.callbacks, 1);
        expect(fixture.platform.businessServer.appliedMutations, 1);
        expect(tester.takeException(), isNull);
        await tester.tap(iconLabel('关闭设置'));
        await tester.pumpAndSettle();
      },
    );
  }
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
        await tester.tap(iconLabel('关闭设置'));
        await tester.pumpAndSettle();
      },
    );
  }
}
