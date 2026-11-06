import '../features/reader/chapter_sequence.dart';

final class MigrationChapterMatch {
  MigrationChapterMatch({
    required this.source,
    required this.candidates,
    required this.suggested,
    required this.reason,
  });
  final SequenceChapter source;
  final List<SequenceChapter> candidates;
  final SequenceChapter? suggested;
  final String reason;
}

final _whitespace = RegExp(r'\s+');
String _name(String value) =>
    value.trim().toLowerCase().replaceAll(_whitespace, ' ');
double? _number(SequenceChapter value) =>
    value.snapshot.hasChapterNumber() &&
        value.snapshot.chapterNumber.isFinite &&
        value.snapshot.chapterNumber >= 0
    ? value.snapshot.chapterNumber
    : null;
typedef _ChapterSignature = (String, double?, String);
_ChapterSignature _signature(SequenceChapter value) =>
    (_name(value.name), _number(value), _name(value.snapshot.scanlator));

/// Full unique agreements are suggestions; weaker matches require a choice.
/// Source order, fractional chapter numbers and duplicate occurrences survive.
List<MigrationChapterMatch> suggestMigrationChapterMatches(
  ChapterSequence source,
  ChapterSequence target,
) {
  final signatures = <_ChapterSignature, List<SequenceChapter>>{};
  final names = <String, List<SequenceChapter>>{};
  final numbers = <double, List<SequenceChapter>>{};
  for (final chapter in target.entries) {
    final signature = _signature(chapter);
    if (chapter.stable && signature.$1.isNotEmpty && signature.$2 != null) {
      (signatures[signature] ??= []).add(chapter);
    }
    if (signature.$1.isNotEmpty) (names[signature.$1] ??= []).add(chapter);
    if (signature.$2 case final number?) (numbers[number] ??= []).add(chapter);
  }
  final proposed = <String, SequenceChapter>{};
  final claims = <String, int>{};
  for (final chapter in source.entries) {
    final matches = chapter.stable ? signatures[_signature(chapter)] : null;
    if (matches?.length == 1) {
      final match = matches!.single;
      proposed[chapter.key] = match;
      claims.update(match.key, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return List.unmodifiable([
    for (final chapter in source.entries)
      () {
        final proposal = proposed[chapter.key];
        final suggested = proposal != null && claims[proposal.key] == 1
            ? proposal
            : null;
        final signature = _signature(chapter);
        final candidates =
            <SequenceChapter>{
              ...?names[signature.$1],
              ...?numbers[signature.$2],
            }.toList()..sort(
              (left, right) => left.sourceIndex.compareTo(right.sourceIndex),
            );
        return MigrationChapterMatch(
          source: chapter,
          candidates: List.unmodifiable(candidates),
          suggested: suggested,
          reason: suggested != null
              ? (signature.$3.isEmpty
                    ? '标题和章节号唯一匹配（双方均未提供扫描组）'
                    : '标题、章节号和扫描组唯一匹配')
              : !chapter.stable
              ? '原章节URL重复，须手动确认具体条目'
              : candidates.isEmpty
              ? '没有建议，请手动选择或保留未映射'
              : '存在歧义，须手动确认',
        );
      }(),
  ]);
}
