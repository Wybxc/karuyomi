import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

ChapterSequence sequence(
  List<wire.Chapter> chapters, {
  String manga = '/manga',
}) => ChapterSequence(
  packageName: 'source.package',
  sourceId: '9223372036854775806',
  mangaUrl: manga,
  chapters: chapters,
);

void main() {
  test(
    'Source sequence preserves absent/fractional numbers and duplicates',
    () {
      final chapters = [
        wire.Chapter(url: '/same', name: '重复', sourceOrder: 0),
        wire.Chapter(
          url: '/same',
          name: '重复',
          sourceOrder: 1,
          chapterNumber: 0.5,
          scanlator: 'another team',
          memoJson: '{"opaque":"exact"}',
        ),
        wire.Chapter(url: '/last', name: '零', chapterNumber: 0, sourceOrder: 2),
      ];
      final value = sequence(chapters);
      expect(value.entries, hasLength(3));
      expect(value.entries[0].snapshot.hasChapterNumber(), false);
      expect(value.entries[1].snapshot.chapterNumber, 0.5);
      expect(value.entries[2].snapshot.hasChapterNumber(), true);
      expect(value.entries[2].snapshot.chapterNumber, 0);
      expect(value.entries.map((entry) => entry.key).toSet(), hasLength(3));
      expect(value.entries.take(2).every((entry) => !entry.stable), true);
      expect(value.entries.last.stable, true);
      expect(value.adjacent(1, ChapterOrder.source, 1), same(value.entries[2]));
      expect(
        value.adjacent(1, ChapterOrder.reversed, 1),
        same(value.entries[0]),
      );
      expect(value.adjacent(0, ChapterOrder.reversed, 1), isNull);
      expect(value.entries[1].snapshot.memoJson, chapters[1].memoJson);
      chapters[1].name = 'Source caller changed';
      expect(value.entries[1].name, '重复');
    },
  );

  test('stable URLs survive insertion but ambiguous occurrences do not', () {
    final chapters = [
      wire.Chapter(url: '/same', name: '一'),
      wire.Chapter(url: '/same', name: '二'),
      wire.Chapter(url: '/unique', name: '三'),
    ];
    final before = sequence(chapters);
    final after = sequence([wire.Chapter(url: '/new', name: '新'), ...chapters]);
    expect(before.entries.last.key, after.entries.last.key);
    expect(before.entries.first.key, isNot(after.entries[1].key));
    expect(
      before.entries.last.key,
      isNot(sequence(chapters, manga: '/other-manga').entries.last.key),
    );
    expect(
      before.entries.first.key,
      isNot(sequence(chapters, manga: '/other-manga').entries.first.key),
    );
    final otherSource = ChapterSequence(
      packageName: 'another.package',
      sourceId: 'another-source',
      mangaUrl: '/manga',
      chapters: chapters,
    );
    expect(before.entries.first.key, isNot(otherSource.entries.first.key));
  });
}
