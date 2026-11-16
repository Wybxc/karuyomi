import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:karuyomi/widgets/edit_sheet.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'edit actions remain at the top with the keyboard in $brightness at ${scale}x text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 640);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetViewInsets);
          final input = TextEditingController(text: '未提交的长名称');
          addTearDown(input.dispose);
          var saved = 0;
          await tester.pumpWidget(
            CupertinoApp(
              theme: readerAppTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: EditSheet(
                title: const Text('长标题的编辑设置'),
                leading: CupertinoButton(
                  key: const ValueKey('close-edit'),
                  padding: EdgeInsets.zero,
                  onPressed: () {},
                  child: const Text('取消'),
                ),
                trailing: CupertinoButton(
                  key: const ValueKey('save-edit'),
                  padding: EdgeInsets.zero,
                  onPressed: () => saved++,
                  child: const Text('保存', semanticsLabel: '保存完整设置'),
                ),
                content: ListView(
                  children: [
                    CupertinoTextField(controller: input),
                    for (var i = 0; i < 16; i++)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('设置说明 $i'),
                      ),
                    const Text('表单末端'),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final close = find.byKey(const ValueKey('close-edit'));
          final save = find.byKey(const ValueKey('save-edit'));
          void expectTopActions() {
            expect(close.hitTestable(), findsOneWidget);
            expect(save.hitTestable(), findsOneWidget);
            expect(tester.getRect(close).bottom, lessThanOrEqualTo(64));
            expect(tester.getRect(save).bottom, lessThanOrEqualTo(64));
            expect(tester.getCenter(close).dx, lessThan(160));
            expect(tester.getCenter(save).dx, greaterThan(160));
            expect(tester.takeException(), isNull);
          }

          expectTopActions();
          final semantics = tester.ensureSemantics();
          await tester.pump();
          try {
            expect(find.bySemanticsLabel('保存完整设置'), findsOneWidget);
          } finally {
            semantics.dispose();
          }
          await tester.tap(find.byType(CupertinoTextField));
          tester.view.viewInsets = const FakeViewPadding(bottom: 240);
          await tester.pumpAndSettle();
          expectTopActions();
          await tester.scrollUntilVisible(
            find.text('表单末端'),
            200,
            scrollable: find
                .descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(find.text('表单末端').hitTestable(), findsOneWidget);
          expectTopActions();
          expect(input.text, '未提交的长名称');
          expect(saved, 0);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(saved, 1);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
