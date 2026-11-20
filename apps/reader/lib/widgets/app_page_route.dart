import 'package:cupertino_ui/cupertino_ui.dart';

/// Declarative settings navigation shares the same reduced-motion route policy.
class AppPage<T> extends CupertinoPage<T> {
  const AppPage({super.key, required super.child, super.title});

  @override
  Route<T> createRoute(BuildContext context) => _AppPageRoute<T>(this);
}

class _AppPageRoute<T> extends AppPageRoute<T> {
  _AppPageRoute(AppPage<T> page)
    : super(builder: (_) => page.child, settings: page);

  AppPage<T> get _page => switch (settings) {
    AppPage<T> page => page,
    _ => throw StateError('Expected an AppPage'),
  };

  // Navigator keeps this route when the page key survives a pane resize or a
  // category change. Read its current settings instead of the original child.
  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  String? get title => _page.title;
}

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
  Duration get transitionDuration {
    final context = navigator?.context;
    return context != null && MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : super.transitionDuration;
  }

  @override
  bool didPop(T? result) {
    // A page can outlive a change in the system motion preference.
    controller!.reverseDuration = reverseTransitionDuration;
    return super.didPop(result);
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
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (disabled || MediaQuery.reduceMotionOf(context)) {
      // Keep the native edge-back recognizer while removing page displacement.
      return super.buildTransitions(
        context,
        const AlwaysStoppedAnimation<double>(1),
        const AlwaysStoppedAnimation<double>(0),
        disabled ? child : FadeTransition(opacity: animation, child: child),
      );
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
