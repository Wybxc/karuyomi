import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/source_migration_matching.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

ChapterSequence _sequence(String source, List<wire.Chapter> chapters) =>
    ChapterSequence(
      packageName: 'test.extension',
      sourceId: source,
      mangaUrl: '/manga',
      chapters: chapters,
    );
wire.Chapter _chapter(
  String url, {
  String name = 'Chapter',
  double? number = 1,
  String scanlator = '',
}) => wire.Chapter(
  url: url,
  name: name,
  chapterNumber: number,
  scanlator: scanlator,
);

void main() {
  test(
    'unique normalized agreement retains zero, fractional numbers and Source order',
    () {
      final source = _sequence('1', [
        _chapter('/zero', name: '  Prelude  ', number: 0),
        _chapter(
          '/half',
          name: 'Chapter  1.5',
          number: 1.5,
          scanlator: ' Team ',
        ),
      ]);
      final target = _sequence('2', [
        _chapter('/half', name: 'chapter 1.5', number: 1.5, scanlator: 'team'),
        _chapter('/zero', name: 'prelude', number: 0),
      ]);
      final result = suggestMigrationChapterMatches(source, target);
      expect(result.map((entry) => entry.source), source.entries);
      expect(result.map((entry) => entry.suggested!.key), [
        target.entries[1].key,
        target.entries[0].key,
      ]);
      expect(result.first.reason, isNot(contains('扫描组唯一匹配')));
      expect(result.last.reason, contains('扫描组'));
    },
  );
  for (final missingNumber in [null, -1.0]) {
    test(
      'missing or invalid number $missingNumber is only a manual candidate',
      () {
        final source = _sequence('1', [
          _chapter('/one', number: missingNumber),
        ]);
        final target = _sequence('2', [
          _chapter('/two', number: missingNumber),
        ]);
        final match = suggestMigrationChapterMatches(source, target).single;
        expect(match.suggested, isNull);
        expect(match.candidates, target.entries);
      },
    );
  }
  test(
    'same chapter number with different title or scanlator requires a manual choice',
    () {
      final source = _sequence('1', [_chapter('/one', scanlator: 'A')]);
      final target = _sequence('2', [
        _chapter('/two', scanlator: 'B'),
        _chapter('/three', name: 'Different', scanlator: 'A'),
      ]);
      final match = suggestMigrationChapterMatches(source, target).single;
      expect(match.suggested, isNull);
      expect(match.candidates, target.entries);
    },
  );
  test('multiple original chapters cannot automatically claim one target', () {
    final source = _sequence('1', [_chapter('/one'), _chapter('/two')]);
    final target = _sequence('2', [_chapter('/target')]);
    final matches = suggestMigrationChapterMatches(source, target);
    expect(matches.every((entry) => entry.suggested == null), true);
    expect(
      matches.every(
        (entry) => entry.candidates.single.key == target.entries.single.key,
      ),
      true,
    );
  });
  test(
    'duplicate target signatures are ambiguous and retain their opaque identities',
    () {
      final source = _sequence('1', [_chapter('/original')]);
      final target = _sequence('2', [_chapter('/one'), _chapter('/two')]);
      final match = suggestMigrationChapterMatches(source, target).single;
      expect(match.suggested, isNull);
      expect(
        match.candidates.map((chapter) => chapter.key).toSet(),
        hasLength(2),
      );
    },
  );
  test(
    'repeated URL occurrences never become automatic migration suggestions',
    () {
      final source = _sequence('1', [
        _chapter('/duplicate'),
        _chapter('/duplicate', number: 2),
      ]);
      final target = _sequence('2', [
        _chapter('/one'),
        _chapter('/two', number: 2),
      ]);
      final matches = suggestMigrationChapterMatches(source, target);
      expect(source.entries.map((entry) => entry.key).toSet(), hasLength(2));
      expect(matches.every((entry) => entry.suggested == null), true);
      expect(matches.every((entry) => entry.reason.contains('URL重复')), true);
    },
  );
  test(
    'empty titles and unavailable numbers cannot match by absent metadata',
    () {
      final source = _sequence('1', [_chapter('/one', name: '', number: null)]);
      final target = _sequence('2', [_chapter('/two', name: '', number: null)]);
      final match = suggestMigrationChapterMatches(source, target).single;
      expect(match.suggested, isNull);
      expect(match.candidates, isEmpty);
    },
  );
}
