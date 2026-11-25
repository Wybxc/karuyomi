import 'package:cupertino_ui/cupertino_ui.dart';

/// Declarative settings navigation shares the same reduced-motion route policy.
class AppPage<T> extends CupertinoPage<T> {
  const AppPage({
    super.key,
    required super.child,
    super.title,
    this.onCompleted,
    this.animate = true,
  });

  final void Function(Future<T?>)? onCompleted;
  final bool animate;

  @override
  Route<T> createRoute(BuildContext context) {
    final route = _AppPageRoute<T>(this);
    onCompleted?.call(route.completed);
    return route;
  }
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

  @override
  Duration get transitionDuration =>
      _page.animate ? super.transitionDuration : Duration.zero;

  @override
  Duration get reverseTransitionDuration =>
      _page.animate ? super.reverseTransitionDuration : Duration.zero;
}

/// Keep the application's reduced-motion policy across all business routes.
class AppPageRoute<T> extends CupertinoPageRoute<T> with _RouteMotion<T> {
  AppPageRoute({required super.builder, super.settings, super.title});

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final page = super.buildPage(context, animation, secondaryAnimation);
    // Heroes fly outside the page transition. Listen for motion changes in
    // this wrapper so updating it keeps the route's existing page.
    return Builder(
      builder: (context) => HeroMode(
        enabled:
            !MediaQuery.disableAnimationsOf(context) &&
            !MediaQuery.reduceMotionOf(context),
        child: page,
      ),
    );
  }

  static final _backdrop = _motionAwareBackdrop((
    context,
    _,
    secondary,
    _,
    child,
  ) {
    if (child == null) return null;
    return CupertinoPageTransition(
      primaryRouteAnimation: const AlwaysStoppedAnimation<double>(1),
      secondaryRouteAnimation: secondary,
      linearTransition: Navigator.of(context).userGestureInProgress,
      child: child,
    );
  });

  @override
  DelegatedTransitionBuilder get delegatedTransition => _backdrop;
}

mixin _RouteMotion<T> on ModalRoute<T> {
  bool get _animationsDisabled {
    final context = navigator?.context;
    return context != null && MediaQuery.disableAnimationsOf(context);
  }

  @override
  Duration get transitionDuration =>
      _animationsDisabled ? Duration.zero : super.transitionDuration;

  @override
  bool didPop(T? result) {
    // The system motion preference can change while a route is open.
    controller!.reverseDuration = reverseTransitionDuration;
    return super.didPop(result);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (disabled || MediaQuery.reduceMotionOf(context)) {
      // Keep the native resting geometry and gesture handling.
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

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required ScrollableWidgetBuilder scrollableBuilder,
  required bool enableDrag,
}) => Navigator.of(context, rootNavigator: true).push<T>(
  _AppSheetRoute<T>(
    scrollableBuilder: scrollableBuilder,
    enableDrag: enableDrag,
  ),
);

class _AppSheetRoute<T> extends CupertinoSheetRoute<T> with _RouteMotion<T> {
  _AppSheetRoute({required super.scrollableBuilder, required super.enableDrag});

  static final _backdrop = _motionAwareBackdrop(
    CupertinoSheetTransition.delegateTransition,
  );

  @override
  DelegatedTransitionBuilder get delegatedTransition => _backdrop;
}

DelegatedTransitionBuilder _motionAwareBackdrop(
  DelegatedTransitionBuilder transition,
) {
  // Navigator retains the builder on the route underneath. Read the preference
  // during build so both routes respond when the system setting changes.
  return (context, animation, secondaryAnimation, allowSnapshotting, child) {
    if (MediaQuery.reduceMotionOf(context) ||
        MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    return transition(
      context,
      animation,
      secondaryAnimation,
      allowSnapshotting,
      child,
    );
  };
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => Navigator.of(
  context,
  rootNavigator: true,
).push<T>(AppDialogRoute<T>(context: context, builder: builder));

class AppDialogRoute<T> extends CupertinoDialogRoute<T> with _RouteMotion<T> {
  AppDialogRoute({required super.context, required super.builder})
    : super(barrierDismissible: false);

  @override
  Simulation createSimulation({required bool forward}) {
    // The platform dialog's spring also drives its barrier and route lifetime.
    if (_animationsDisabled) return _ImmediateSimulation(forward ? 1 : 0);
    return super.createSimulation(forward: forward);
  }
}

class _ImmediateSimulation extends Simulation {
  _ImmediateSimulation(this.value);

  final double value;

  @override
  double x(double time) => value;

  @override
  double dx(double time) => 0;

  @override
  bool isDone(double time) => true;
}
