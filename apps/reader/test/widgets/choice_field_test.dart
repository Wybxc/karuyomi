import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/widgets/choice_field.dart';

void main() {
  const field = ValueKey('choice');
  const short = <String?, String>{null: '跟随全局', 'one': '单页', 'two': '双页'};
  final long = <String?, String>{
    null: '全部语言',
    for (var index = 0; index < 10; index++) '$index': '语言 $index',
  };

  Future<void> show(
    WidgetTester tester, {
    required Map<String?, String> options,
    required ValueChanged<String?>? onChanged,
    Set<String?> disabled = const {},
    bool inline = true,
    Brightness? brightness,
  }) => tester.pumpWidget(
    CupertinoApp(
      theme: CupertinoThemeData(brightness: brightness),
      home: CupertinoPageScaffold(
        child: Center(
          child: ChoiceField<String>(
            key: field,
            label: '选择',
            inline: inline,
            value: 'one',
            options: options,
            disabledValues: disabled,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'disabled choice labels use the Cupertino disabled color in $brightness',
      (tester) async {
        for (final inline in [true, false]) {
          await show(
            tester,
            options: short,
            onChanged: null,
            inline: inline,
            brightness: brightness,
          );
          for (final label in [inline ? '选择：' : '选择', '单页']) {
            final text = find.text(label);
            expect(
              tester.widget<Text>(text).style?.color,
              CupertinoColors.tertiaryLabel.resolveFrom(tester.element(text)),
            );
          }
        }
      },
    );

    for (final scale in [1.0, 2.0]) {
      for (final searchable in [false, true]) {
        testWidgets(
          '${searchable ? 'searchable choices' : 'short menu'} expose selection on each named action in $brightness at ${scale}x',
          (tester) async {
            tester.view.physicalSize = const Size(360, 800);
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final semantics = tester.ensureSemantics();
            try {
              final changed = <String?>[];
              await show(
                tester,
                options: {
                  ...short,
                  if (searchable)
                    for (var index = 3; index < 10; index++)
                      '$index': '其它选项 $index',
                },
                onChanged: changed.add,
                disabled: {'two'},
                brightness: brightness,
              );
              await tester.tap(find.byKey(field));
              await tester.pumpAndSettle();
              void expectChoice(String label, bool selected, bool enabled) {
                expect(
                  tester.getSemantics(find.text(label).last),
                  isSemantics(
                    label: label,
                    hasSelectedState: true,
                    isSelected: selected,
                    hasEnabledState: true,
                    isEnabled: enabled,
                    isInMutuallyExclusiveGroup: true,
                    hasTapAction: enabled,
                  ),
                );
              }

              expectChoice('单页', true, true);
              expectChoice('跟随全局', false, true);
              expectChoice('双页', false, false);
              if (searchable) {
                await tester.enterText(
                  find.widgetWithText(CupertinoTextField, '查找选择'),
                  '单页',
                );
                await tester.pumpAndSettle();
                expectChoice('单页', true, true);
                await tester.tap(find.bySemanticsLabel('清空选项搜索'));
                await tester.pumpAndSettle();
                expectChoice('跟随全局', false, true);
                await tester.tap(find.byType(CupertinoNavigationBarBackButton));
              } else {
                await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              }
              await tester.pumpAndSettle();
              expect(changed, isEmpty);
              expect(tester.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }

      testWidgets(
        'long choices preserve the visible occurrence and keyboard selection in $brightness at ${scale}x',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final semantics = tester.ensureSemantics();
          try {
            const title = '同名的很长章节名称，需要完整保留最后的来源序号才能区分独立条目';
            const first = '$title · 来源第 1 项';
            const second = '$title · 来源第 2 项';
            final options = <String?, String>{
              'one': first,
              'two': second,
              for (var index = 3; index < 12; index++) '$index': '其它章 $index',
            };
            final changed = <String?>[];
            await show(
              tester,
              options: options,
              onChanged: changed.add,
              inline: false,
              brightness: brightness,
            );
            expect(
              tester
                  .renderObject<RenderParagraph>(find.text(first))
                  .didExceedMaxLines,
              false,
              reason:
                  'the selected value must expose its full occurrence identity',
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            final query = find.widgetWithText(CupertinoTextField, '查找选择');
            await tester.enterText(query, '没有此来源');
            await tester.pumpAndSettle();
            expect(find.text('没有匹配的选项'), findsOneWidget);
            expect(changed, isEmpty);
            await tester.tap(find.bySemanticsLabel('清空选项搜索'));
            await tester.pumpAndSettle();
            expect(
              tester.widget<CupertinoTextField>(query).controller!.text,
              isEmpty,
            );
            await tester.enterText(query, '来源第 2 项');
            await tester.pumpAndSettle();
            expect(
              tester
                  .renderObject<RenderParagraph>(find.text(second))
                  .didExceedMaxLines,
              false,
              reason: 'search results must retain the suffix distinguishing duplicate names',
            );
            await tester.tap(find.byType(CupertinoNavigationBarBackButton));
            await tester.pumpAndSettle();
            expect(changed, isEmpty);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            await tester.enterText(query, '来源第 2 项');
            await tester.pumpAndSettle();
            Focus.of(tester.element(find.text(second))).requestFocus();
            await tester.pumpAndSettle();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(changed, ['two']);
            expect(find.byType(ChoicePage<String>), findsNothing);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets('a short menu can select null and restores trigger focus', (
    tester,
  ) async {
    final changed = <String?>[];
    await show(tester, options: short, onChanged: changed.add);
    await tester.tap(find.byKey(field));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跟随全局'));
    await tester.pumpAndSettle();
    expect(changed, [null]);
    final trigger = tester.widget<CupertinoButton>(
      find.descendant(
        of: find.byKey(field),
        matching: find.byType(CupertinoButton),
      ),
    );
    expect(trigger.focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled values and Escape keep the draft unchanged', (
    tester,
  ) async {
    final changed = <String?>[];
    await show(
      tester,
      options: short,
      onChanged: changed.add,
      disabled: {'two'},
    );
    await tester.tap(find.byKey(field));
    await tester.pumpAndSettle();
    final blocked = tester.widget<CupertinoMenuItem>(
      find.widgetWithText(CupertinoMenuItem, '双页'),
    );
    expect(blocked.onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoMenuItem), findsNothing);
    expect(changed, isEmpty);
    await show(tester, options: short, onChanged: null);
    final trigger = tester.widget<CupertinoButton>(
      find.descendant(
        of: find.byKey(field),
        matching: find.byType(CupertinoButton),
      ),
    );
    expect(trigger.onPressed, isNull);
  });

  testWidgets('Tab and Enter open and select a menu without a pointer', (
    tester,
  ) async {
    final changed = <String?>[];
    await show(tester, options: short, onChanged: changed.add);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoMenuItem), findsNWidgets(3));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changed, ['one']);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changed, ['one', 'two']);
    expect(find.byType(CupertinoMenuItem), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a disabled current choice focuses the first enabled value', (
    tester,
  ) async {
    final changed = <String?>[];
    await show(
      tester,
      options: short,
      onChanged: changed.add,
      disabled: {'one'},
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changed, [null]);
    expect(find.byType(CupertinoMenuItem), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Chinese search remains usable at 360px and twice the text size',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final changed = <String?>[];
      await show(
        tester,
        options: {
          for (var index = 0; index < 12; index++) '$index': '中文漫画源分区 $index',
        },
        onChanged: changed.add,
      );
      await tester.tap(find.byKey(field));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(CupertinoTextField, '查找选择'),
        '中文漫画源分区 7',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CupertinoListTile, '中文漫画源分区 7'));
      await tester.pumpAndSettle();
      expect(changed, ['7']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a searchable choice separates cancellation, null and a selected value',
    (tester) async {
      final changed = <String?>[];
      await show(tester, options: long, onChanged: changed.add);
      await tester.tap(find.byKey(field));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pumpAndSettle();
      expect(changed, isEmpty);
      await tester.tap(find.byKey(field));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(CupertinoTextField, '查找选择'),
        '语言 7',
      );
      expect(tester.testTextInput.setClientArgs, isNotNull);
      expect(tester.testTextInput.setClientArgs!['autofill'], isNull);
      await tester.pumpAndSettle();
      expect(find.text('语言 6'), findsNothing);
      await tester.tap(find.widgetWithText(CupertinoListTile, '语言 7'));
      await tester.pumpAndSettle();
      expect(changed, ['7']);
      await tester.tap(find.byKey(field));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部语言'));
      await tester.pumpAndSettle();
      expect(changed, ['7', null]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a choice opened before editing is disabled cannot update its owner',
    (tester) async {
      final changed = <String?>[];
      var enabled = true;
      late StateSetter rebuild;
      await tester.pumpWidget(
        CupertinoApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return CupertinoPageScaffold(
                child: Center(
                  child: ChoiceField<String>(
                    key: field,
                    label: '语言',
                    value: null,
                    options: long,
                    onChanged: enabled ? changed.add : null,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.byKey(field));
      await tester.pumpAndSettle();
      rebuild(() => enabled = false);
      await tester.pump();
      await tester.tap(find.text('语言 0'));
      await tester.pumpAndSettle();
      expect(changed, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
