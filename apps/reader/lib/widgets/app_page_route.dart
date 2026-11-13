import 'package:cupertino_ui/cupertino_ui.dart';

/// Keep the application's reduced-motion policy across all business routes.
class AppPageRoute<T> extends CupertinoPageRoute<T> {
  AppPageRoute({required super.builder, super.settings, super.title});

  bool get _reduced {
    final context = navigator?.context;
    return context != null &&
        (MediaQuery.reduceMotionOf(context) ||
            MediaQuery.disableAnimationsOf(context));
  }

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _reduced ? null : super.delegatedTransition;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    if (MediaQuery.reduceMotionOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
