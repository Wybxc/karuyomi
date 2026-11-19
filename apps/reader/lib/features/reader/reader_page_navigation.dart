import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

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
          onShowFocusHighlight: (show) => setState(() => _showFocus = show),
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
    final count = Text(
      '${widget.pageCount == 0 ? 0 : index + 1} / ${widget.pageCount}',
      textAlign: TextAlign.center,
    );
    final chapters = widget.chapters;
    final hasSlider = widget.pageCount > 1;
    final rtl = widget.direction == TextDirection.rtl;
    return Column(
      children: [
        if (hasSlider) ExcludeSemantics(child: count),
        Row(
          textDirection: widget.direction,
          children: [
            if (chapters != null)
              Expanded(
                child: Align(
                  alignment: rtl ? Alignment.centerRight : Alignment.centerLeft,
                  child: chapters.previous,
                ),
              ),
            Expanded(flex: 2, child: hasSlider ? _slider(index) : count),
            if (chapters != null)
              Expanded(
                child: Align(
                  alignment: rtl ? Alignment.centerLeft : Alignment.centerRight,
                  child: chapters.next,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
