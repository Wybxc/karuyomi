import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
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
  }) => tester.pumpWidget(
    CupertinoApp(
      home: CupertinoPageScaffold(
        child: Center(
          child: ChoiceField<String>(
            key: field,
            label: '选择',
            value: 'one',
            options: options,
            disabledValues: disabled,
            onChanged: onChanged,
          ),
        ),
      ),
    ),
  );

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
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
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
