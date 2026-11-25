import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../theme/app_theme.dart';
import 'adaptive_layout.dart';
import 'app_routes.dart';

typedef AdaptiveDetailBuilder = Widget Function(
  BuildContext context,
  VoidCallback? close,
);
typedef AdaptiveDetailSelection = ({
  Object token,
  AdaptiveDetailBuilder builder,
});

Future<void> openAdaptiveDetail(
  BuildContext context,
  AdaptiveDetailBuilder builder,
) async {
  final layout = context.findAncestorStateOfType<_AdaptiveDetailLayoutState>();
  if (layout?.open(builder) == true) return;
  await Navigator.of(
    context,
    rootNavigator: true,
  ).push<void>(AppPageRoute(builder: (context) => builder(context, null)));
}

Future<bool> backFromAdaptiveDetail(BuildContext context) async {
  final layout = context.findAncestorStateOfType<_AdaptiveDetailLayoutState>();
  return await layout?.back() ?? false;
}

/// A wide selection keeps both panes. Shrinking brings the same detail forward
/// while its list keeps its state and scroll position.
class const AdaptiveDetailLayout({
  super.key,
  required final Widget child,
  final Object? owner,
  final bool handleSystemBack = true,
  final AdaptiveDetailSelection? detail,
  final VoidCallback? onCloseDetail,
  final bool singleColumn = false,
}) extends StatefulWidget {
  @override
  State<AdaptiveDetailLayout> createState() => _AdaptiveDetailLayoutState();
}

class _AdaptiveDetailLayoutState extends State<AdaptiveDetailLayout> {
  final _details = GlobalKey<NavigatorState>();
  AdaptiveDetailSelection? _selection;
  AdaptiveDetailSelection? get _detail => widget.detail ?? _selection;
  bool _wide = false;

  bool open(AdaptiveDetailBuilder builder) {
    if (!_wide) return false;
    setState(() => _selection = (token: Object(), builder: builder));
    return true;
  }

  void _close() {
    if (widget.detail != null) {
      widget.onCloseDetail?.call();
    } else {
      setState(() => _selection = null);
    }
  }

  Future<bool> back() async {
    final selection = _detail;
    if (selection == null) return false;
    // An inline detail can consume Back to exit chapter selection first.
    final handled = await _details.currentState?.maybePop() ?? false;
    if (!handled && mounted && _detail == selection) _close();
    return true;
  }

  @override
  void didUpdateWidget(AdaptiveDetailLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.owner, oldWidget.owner)) _selection = null;
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !widget.handleSystemBack || _detail == null,
    onPopInvokedWithResult: (didPop, _) {
      if (widget.handleSystemBack && !didPop) unawaited(back());
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        _wide =
            !widget.singleColumn &&
            fitsColumns(context, constraints, minimumWidth: 832);
        final selected = _detail;
        final both = _wide && selected != null;
        final hideList = !_wide && selected != null;
        final detailWidth = (constraints.maxWidth * .44).clamp(352.0, 520.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            PositionedDirectional(
              key: const ValueKey('adaptive-list'),
              start: 0,
              end: both ? detailWidth : 0,
              top: 0,
              bottom: 0,
              child: Offstage(
                offstage: hideList,
                child: ExcludeFocus(
                  excluding: hideList,
                  child: TickerMode(enabled: !hideList, child: widget.child),
                ),
              ),
            ),
            PositionedDirectional(
              key: const ValueKey('adaptive-detail'),
              start: both ? constraints.maxWidth - detailWidth : 0,
              end: 0,
              top: 0,
              bottom: 0,
              child: Offstage(
                offstage: selected == null,
                child: ExcludeFocus(
                  excluding: selected == null,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.background.resolveFrom(context),
                      border: both
                          ? BorderDirectional(
                              start: BorderSide(
                                color: AppColors.separator.resolveFrom(context),
                              ),
                            )
                          : null,
                    ),
                    child: Navigator(
                      key: _details,
                      requestFocus: false,
                      pages: [
                        const AppPage<void>(
                          key: ValueKey('adaptive-detail-empty'),
                          child: SizedBox.shrink(),
                        ),
                        if (selected != null)
                          AppPage<void>(
                            key: ValueKey<Object?>(selected.token),
                            animate: !_wide,
                            child: Builder(
                              builder: (context) =>
                                  selected.builder(context, _close),
                            ),
                          ),
                      ],
                      onDidRemovePage: (page) {
                        if (page.key == ValueKey<Object?>(_detail?.token)) {
                          _close();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
