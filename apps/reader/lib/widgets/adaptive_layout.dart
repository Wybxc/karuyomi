import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The second column needs space for its content and for larger system text.
bool fitsColumns(
  BuildContext context,
  BoxConstraints constraints, {
  required double minimumWidth,
}) {
  final scale = MediaQuery.textScalerOf(context).scale(17) / 17;
  final textSpace = 112 * math.max(0, scale - 1);
  return constraints.maxHeight >= 440 &&
      constraints.maxWidth >= minimumWidth + textSpace;
}
