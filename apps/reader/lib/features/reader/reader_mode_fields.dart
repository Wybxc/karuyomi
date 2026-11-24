import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:reader_core/reader_core.dart';

import '../../widgets/choice_field.dart';

enum ReadingAdvance { paged, continuous }

enum ReadingSpacing { spaced, seamless }

ReadingMode _horizontalMode(ReadingAdvance advance, TextDirection direction) =>
    switch ((advance, direction)) {
      (ReadingAdvance.paged, TextDirection.ltr) => ReadingMode.leftToRight,
      (ReadingAdvance.paged, TextDirection.rtl) => ReadingMode.rightToLeft,
      (ReadingAdvance.continuous, TextDirection.ltr) =>
        ReadingMode.horizontalContinuousLeftToRight,
      (ReadingAdvance.continuous, TextDirection.rtl) =>
        ReadingMode.horizontalContinuousRightToLeft,
    };

List<Widget> readerModeFields({
  required String scope,
  required ReadingMode mode,
  required ValueChanged<ReadingMode>? onChanged,
  bool compact = false,
}) {
  final axis = mode.isVertical ? Axis.vertical : Axis.horizontal;
  final advance = mode.isContinuous
      ? ReadingAdvance.continuous
      : ReadingAdvance.paged;
  final direction = mode.isRightToLeft ? TextDirection.rtl : TextDirection.ltr;
  final spacing = mode == ReadingMode.webtoon
      ? ReadingSpacing.seamless
      : ReadingSpacing.spaced;

  Widget field<T extends Object>(
    String id,
    String label,
    T current,
    Map<T, String> options,
    ReadingMode Function(T) select,
  ) => ChoiceField<T>(
    key: ValueKey('$scope-$id'),
    label: label,
    value: current,
    options: options,
    inline: compact,
    showInlineLabel: false,
    onChanged: onChanged == null
        ? null
        : (value) {
            if (value != null && value != current) onChanged(select(value));
          },
  );

  return [
    field(
      'axis',
      '排布方向',
      axis,
      const {Axis.horizontal: '横向', Axis.vertical: '纵向'},
      (value) => value == Axis.vertical
          ? ReadingMode.continuous
          : ReadingMode.horizontalContinuousLeftToRight,
    ),
    if (!mode.isVertical) ...[
      field('advance', '推进方式', advance, const {
        ReadingAdvance.paged: '分页',
        ReadingAdvance.continuous: '连续滚动',
      }, (value) => _horizontalMode(value, direction)),
      field('direction', '横向页序', direction, const {
        TextDirection.ltr: '从左到右',
        TextDirection.rtl: '从右到左',
      }, (value) => _horizontalMode(advance, value)),
    ] else ...[
      if (!compact)
        const CupertinoListTile(title: Text('推进方式'), subtitle: Text('连续滚动')),
      field(
        'spacing',
        '图片间距',
        spacing,
        const {ReadingSpacing.spaced: '有间距', ReadingSpacing.seamless: '无间距'},
        (value) => value == ReadingSpacing.seamless
            ? ReadingMode.webtoon
            : ReadingMode.continuous,
      ),
    ],
  ];
}
