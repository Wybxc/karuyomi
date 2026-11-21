import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

const readerPageSliderIdentifier = 'reader-page-slider';

class ReaderPageNavigation extends StatefulWidget {
  const ReaderPageNavigation({
    super.key,
    required this.pageIndex,
    required this.pageCount,
    required this.direction,
    required this.onSelect,
    required this.keyboardEnabled,
    this.chapters,
  });

  final int pageIndex;
  final int pageCount;
  final TextDirection direction;
  final ValueChanged<int>? onSelect;
  final bool keyboardEnabled;
  final ({Widget previous, Widget next})? chapters;

  @override
  State<ReaderPageNavigation> createState() => _ReaderPageNavigationState();
}

class _ReaderPageNavigationState extends State<ReaderPageNavigation> {
  int? _previewIndex;
  bool _showFocus = false;

  @override
  void didUpdateWidget(ReaderPageNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pageIndex != oldWidget.pageIndex) _previewIndex = null;
  }

  void _clearPreview() {
    if (_previewIndex != null) setState(() => _previewIndex = null);
  }

  void _updateFocusOutline(bool show) {
    if (_showFocus != show) setState(() => _showFocus = show);
  }

  void _select(int index) {
    _clearPreview();
    final target = index.clamp(0, widget.pageCount - 1);
    if (target != widget.pageIndex) widget.onSelect?.call(target);
  }

  Widget _slider(int index) {
    final enabled = widget.onSelect != null;
    final last = widget.pageCount - 1;
    final rtl = widget.direction == TextDirection.rtl;
    final canIncrease = enabled && index < last;
    final canDecrease = enabled && index > 0;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight,
        ): () =>
            _select(widget.pageIndex + 1),
        SingleActivator(
          rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft,
        ): () =>
            _select(widget.pageIndex - 1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _select(widget.pageIndex + 1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _select(widget.pageIndex - 1),
        const SingleActivator(LogicalKeyboardKey.home): () => _select(0),
        const SingleActivator(LogicalKeyboardKey.end): () => _select(last),
      },
      child: Semantics(
        container: true,
        slider: true,
        identifier: readerPageSliderIdentifier,
        enabled: enabled,
        label: '页码跳转',
        value: '${index + 1}',
        minValue: '1',
        maxValue: '${widget.pageCount}',
        increasedValue: canIncrease ? '${index + 2}' : null,
        decreasedValue: canDecrease ? '$index' : null,
        onIncrease: canIncrease ? () => _select(index + 1) : null,
        onDecrease: canDecrease ? () => _select(index - 1) : null,
        child: FocusableActionDetector(
          enabled: enabled && widget.keyboardEnabled,
          // A resize can restore DOM focus while Web still reports pointer mode.
          onFocusChange: kIsWeb ? _updateFocusOutline : null,
          onShowFocusHighlight: kIsWeb ? null : _updateFocusOutline,
          child: ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  kMinInteractiveDimensionCupertino / 2,
                ),
                border: _showFocus
                    ? Border.all(
                        color: AppColors.accent.resolveFrom(context),
                        width: 2,
                      )
                    : null,
              ),
              child: Listener(
                // A cancelled pointer can still end CupertinoSlider's drag.
                onPointerCancel: (_) => _clearPreview(),
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: enabled
                        ? (details) {
                            final width = constraints.maxWidth;
                            final inset = math.min(
                              kMinInteractiveDimensionCupertino / 2,
                              width / 4,
                            );
                            final fraction =
                                (details.localPosition.dx - inset) /
                                (width - inset * 2);
                            _select(
                              ((rtl ? 1 - fraction : fraction) * last).round(),
                            );
                          }
                        : null,
                    child: Directionality(
                      textDirection: widget.direction,
                      child: CupertinoSlider(
                        value: index.toDouble(),
                        max: last.toDouble(),
                        divisions: last,
                        onChangeStart: (_) => _previewIndex = widget.pageIndex,
                        onChanged: enabled
                            ? (value) {
                                if (_previewIndex != null) {
                                  setState(() => _previewIndex = value.round());
                                }
                              }
                            : null,
                        onChangeEnd: (_) {
                          if (_previewIndex case final target?) _select(target);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = _previewIndex ?? widget.pageIndex;
    final textStyle = DefaultTextStyle.of(context).style;
    final countStyle = textStyle.copyWith(
      fontFeatures: [
        ...?textStyle.fontFeatures,
        const FontFeature.tabularFigures(),
      ],
      fontWeight: MediaQuery.boldTextOf(context) ? FontWeight.bold : null,
    );
    final chapters = widget.chapters;
    const chapterGap = 4.0;
    const countGap = 8.0;
    const chapterWidth = kMinInteractiveDimensionCupertino;

    Widget count({required bool wrap}) => Text(
      '${widget.pageCount == 0 ? 0 : index + 1} / ${widget.pageCount}',
      style: countStyle,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      softWrap: wrap,
    );

    Widget rail(List<Widget> center) => Row(
      key: const ValueKey('page-navigation-row'),
      textDirection: widget.direction,
      children: [
        if (chapters != null) ...[
          SizedBox(width: chapterWidth, child: chapters.previous),
          const SizedBox(width: chapterGap),
        ],
        ...center,
        if (chapters != null) ...[
          const SizedBox(width: chapterGap),
          SizedBox(width: chapterWidth, child: chapters.next),
        ],
      ],
    );
    if (widget.pageCount <= 1) {
      return rail([Expanded(child: count(wrap: true))]);
    }

    // Reserve the maximum digit count so moving or previewing a page keeps
    // the track stationary, including when the current value gains a digit.
    final longestCount = '${widget.pageCount} / ${widget.pageCount}';
    Size measureCount(double width) {
      final painter = TextPainter(
        text: TextSpan(text: longestCount, style: countStyle),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout(maxWidth: width);
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final countWidth = measureCount(double.infinity).width.ceilToDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final chapterSpace = chapters == null
            ? 0
            : (chapterWidth + chapterGap) * 2;
        final availableTrack = constraints.maxWidth - chapterSpace;
        final stacked =
            availableTrack - countWidth - countGap <
            3 * kMinInteractiveDimensionCupertino;
        final wrap = countWidth > constraints.maxWidth;
        final label = ExcludeSemantics(child: count(wrap: wrap));
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stacked)
              if (wrap)
                SizedBox(
                  height: measureCount(constraints.maxWidth).height,
                  child: Center(child: label),
                )
              else
                label,
            rail([
              if (!stacked) ...[
                SizedBox(width: countWidth, child: label),
                const SizedBox(width: countGap),
              ],
              Expanded(
                key: const ValueKey(readerPageSliderIdentifier),
                child: _slider(index),
              ),
            ]),
          ],
        );
      },
    );
  }
}
