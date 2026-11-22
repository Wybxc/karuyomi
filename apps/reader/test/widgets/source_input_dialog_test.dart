import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'package:karuyomi/features/reader/source_input_dialog.dart';

void main() {
  testWidgets('a password is masked and requires confirmation', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const CupertinoPageScaffold(child: SizedBox());
          },
        ),
      ),
    );
    final ended = Completer<void>();
    final result = showSourceInputDialog(
      context,
      sourceName: 'Fixture Source',
      prompt: wire.SourceInputPrompt(
        title: 'Locked chapter',
        hint: 'Password',
        password: true,
        required: true,
      ),
      operationEnded: ended.future,
    );
    await tester.pumpAndSettle();
    final field = find.byType(CupertinoTextField);
    expect(tester.widget<CupertinoTextField>(field).obscureText, isTrue);
    expect(find.text('来源 · Fixture Source'), findsOneWidget);
    final confirm = find.ancestor(
      of: find.text('确认'),
      matching: find.byType(CupertinoDialogAction),
    );
    expect(tester.widget<CupertinoDialogAction>(confirm).onPressed, isNull);
    await tester.enterText(field, 'fixture-secret');
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(await result, 'fixture-secret');
    ended.complete();
    await tester.pump();
  });

  testWidgets('operation expiry dismisses its prompt under a newer route', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    late BuildContext context;
    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: navigator,
        home: Builder(
          builder: (value) {
            context = value;
            return const CupertinoPageScaffold(child: SizedBox());
          },
        ),
      ),
    );
    final ended = Completer<void>();
    final result = showSourceInputDialog(
      context,
      sourceName: 'Fixture Source',
      prompt: wire.SourceInputPrompt(title: 'Reader input'),
      operationEnded: ended.future,
    );
    await tester.pumpAndSettle();
    unawaited(
      navigator.currentState!.push<void>(
        CupertinoPageRoute(
          builder: (_) => const CupertinoPageScaffold(child: Text('New route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    ended.complete();
    await tester.pumpAndSettle();
    expect(await result, isNull);
    expect(find.text('New route'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Reader input'), findsNothing);
  });
}
