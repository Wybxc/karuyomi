import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

extension TestApp on WidgetTester {
  Future<void> pumpApp(Widget widget, {ProviderContainer? container}) =>
      pumpWidget(
        container == null
            ? ProviderScope(child: widget)
            : UncontrolledProviderScope(container: container, child: widget),
      );
}

void setAppLifecycleState(WidgetsBinding binding, AppLifecycleState target) {
  const path = [
    AppLifecycleState.resumed,
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  final from = path.indexOf(
    binding.lifecycleState ?? AppLifecycleState.detached,
  );
  final to = path.indexOf(target);
  if (from < 0 || to < 0) {
    binding.handleAppLifecycleStateChanged(target);
    return;
  }
  final step = to > from ? 1 : -1;
  for (var index = from; index != to;) {
    index += step;
    binding.handleAppLifecycleStateChanged(path[index]);
  }
}
