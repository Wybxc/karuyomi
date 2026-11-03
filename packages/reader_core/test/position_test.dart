import 'package:reader_core/reader_core.dart';
import 'package:test/test.dart';

void main() {
  ReadingPosition position(double offset) => ReadingPosition(
    chapterKey: 'chapter-1',
    pageKey: 'page-4',
    manifestVersion: 'manifest-1',
    pageIndexHint: 3,
    normalizedOffset: offset,
  );

  test('anchor keeps original page identity and accepts page boundaries', () {
    expect(position(0).pageKey, 'page-4');
    expect(position(1).normalizedOffset, 1);
  });

  test('invalid and non-finite offsets cannot enter persistent progress', () {
    for (final offset in [-0.1, 1.1, double.nan, double.infinity]) {
      expect(() => position(offset), throwsArgumentError);
    }
  });
}
