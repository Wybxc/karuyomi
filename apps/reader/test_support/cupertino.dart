import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';

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
