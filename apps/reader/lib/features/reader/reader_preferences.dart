import 'package:reader_core/reader_core.dart';

const readingModeLabels = {
  ReadingMode.leftToRight: '横向分页 · 从左到右',
  ReadingMode.rightToLeft: '横向分页 · 从右到左',
  ReadingMode.horizontalContinuousLeftToRight: '横向连续 · 从左到右',
  ReadingMode.horizontalContinuousRightToLeft: '横向连续 · 从右到左',
  ReadingMode.continuous: '纵向连续',
  ReadingMode.webtoon: '条漫（无间距）',
};

/// Reading content appearance; independent of the transport protocol.
enum ReaderBackground { black, white, theme }

/// Relative page navigation only. Absolute first/last keyboard actions retain
/// their meaning when reversed; disabling presets leaves explicit UI usable.
enum ReaderInputPreset { standard, reversed, disabled }

/// Base image sizing, shared by paged, continuous and enlarged reading.
enum ReaderFit { contain, width, height }
