import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

enum ChapterOrder { source, reversed }

String _key(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

/// An occurrence is retained even when another entry has the same URL or name.
final class SequenceChapter {
  SequenceChapter._(this.key, this.sourceIndex, this.snapshot, this.stable);
  final String key;
  final int sourceIndex;
  final wire.Chapter snapshot;
  final bool stable;
  String get name => snapshot.name;
}

/// The Source's list is never sorted by a possibly absent/fractional number.
final class ChapterSequence {
  ChapterSequence({
    required String packageName,
    required String sourceId,
    required String mangaUrl,
    required Iterable<wire.Chapter> chapters,
  }) : mangaKey = _key([packageName, sourceId, mangaUrl]) {
    final snapshots = chapters
        .map((chapter) => chapter.deepCopy()..freeze())
        .toList();
    version = _key(snapshots.map(wire.encodeProtoJson).toList());
    final counts = <String, int>{};
    for (final chapter in snapshots) {
      counts.update(chapter.url, (count) => count + 1, ifAbsent: () => 1);
    }
    entries = List.unmodifiable([
      for (var index = 0; index < snapshots.length; index++)
        SequenceChapter._(
          counts[snapshots[index].url] == 1
              ? _key([packageName, sourceId, mangaUrl, snapshots[index].url])
              : 'snapshot-${_key([mangaKey, version, index])}',
          index,
          snapshots[index],
          counts[snapshots[index].url] == 1,
        ),
    ]);
  }

  final String mangaKey;
  late final String version;
  late final List<SequenceChapter> entries;

  SequenceChapter? adjacent(int sourceIndex, ChapterOrder order, int delta) {
    final index = sourceIndex + (order == ChapterOrder.source ? delta : -delta);
    return index >= 0 && index < entries.length ? entries[index] : null;
  }

  List<SequenceChapter> ordered(ChapterOrder order) =>
      order == ChapterOrder.source ? entries : entries.reversed.toList();
}
