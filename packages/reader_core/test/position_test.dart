import 'package:reader_core/reader_core.dart';
import 'package:test/test.dart';

void main() {
  ReadingPosition position({
    double offset = 0,
    double x = 0,
    double viewportX = 0,
    double viewportY = 0,
  }) => ReadingPosition(
    chapterKey: 'chapter-1',
    pageKey: 'page-4',
    manifestVersion: 'manifest-1',
    pageIndexHint: 3,
    normalizedOffset: offset,
    normalizedX: x,
    viewportX: viewportX,
    viewportY: viewportY,
  );

  test('anchor keeps original page identity and accepts source and viewport boundaries', () {
    expect(position().pageKey, 'page-4');
    final edge = position(offset: 1, x: 1, viewportX: 1, viewportY: 1);
    expect(edge.normalizedOffset, 1);
    expect(edge.normalizedX, 1);
    expect(edge.viewportX, 1);
    expect(edge.viewportY, 1);
  });

  test(
    'invalid and non-finite coordinates cannot enter persistent progress',
    () {
      for (final value in [
        -.1,
        1.1,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        for (final create in [
          () => position(offset: value),
          () => position(x: value),
          () => position(viewportX: value),
          () => position(viewportY: value),
        ]) {
          expect(create, throwsArgumentError);
        }
      }
    },
  );
}
