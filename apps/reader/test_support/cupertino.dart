import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

Finder iconLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Icon && widget.semanticLabel == label,
);

Finder checkboxLabel(String label) => find.descendant(
  of: find.widgetWithText(CupertinoFormRow, label),
  matching: find.byType(CupertinoCheckbox),
);

Finder iconButton(String label) => buttonAbove(iconLabel(label));

Finder buttonAbove(Finder child) =>
    find.ancestor(of: child, matching: find.byType(CupertinoButton)).first;

final selectionControls = find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.selected != null,
);

bool selectedState(WidgetTester tester, Finder control) {
  final selected = find.descendant(of: control, matching: selectionControls);
  final semantics = selected.evaluate().isEmpty
      ? find.ancestor(of: control, matching: selectionControls).first
      : selected;
  return tester.widget<Semantics>(semantics).properties.selected!;
}

/// Follow the visible route control, independent of the toolkit's back class.
final appBackButton = find.byWidgetPredicate(
  (widget) =>
      widget is CupertinoNavigationBarBackButton ||
      (widget is GlassButton && const ['Back', '返回'].contains(widget.label)) ||
      (widget is CupertinoButton &&
          widget.child is Icon &&
          (widget.child as Icon).semanticLabel == '返回'),
);

Future<void> openReaderTools(WidgetTester tester) async {
  if (find.byKey(const ValueKey('reader-tools-panel')).evaluate().isNotEmpty) {
    return;
  }
  final show = iconLabel('显示阅读工具');
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('reader-tools-toggle')));
  await tester.pumpAndSettle();
}

Finder appNavigation(String label) => find
    .descendant(
      of: find.byKey(const ValueKey('app-navigation')),
      matching: find.bySemanticsLabel(label),
    )
    .first;
