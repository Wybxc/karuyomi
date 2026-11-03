import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:reader_core/reader_core.dart';

import 'reader_database.dart';
import 'reading_progress.dart';

final class ProgressRepository {
  ProgressRepository(this.database, this.identity);
  final ReaderDatabase database;
  final ProgressIdentity identity;

  Future<ChapterProgress?> loadChapter({
    required String mangaKey,
    required String chapterKey,
  }) async {
    final row =
        await (database.select(database.chapterProgressRows)..where(
              (row) =>
                  row.identityKey.equals(identity.key) &
                  row.mangaKey.equals(mangaKey) &
                  row.chapterKey.equals(chapterKey),
            ))
            .getSingleOrNull();
    return row == null ? null : _progress(row);
  }

  Future<MangaResume?> loadResume(String mangaKey) async {
    final row =
        await (database.select(database.mangaResumeRows)..where(
              (row) =>
                  row.identityKey.equals(identity.key) &
                  row.mangaKey.equals(mangaKey),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : MangaResume(
            chapterKey: row.chapterKey,
            reversedOrder: row.reversedOrder,
          );
  }

  Future<ChapterProgress> save({
    required String mangaKey,
    required ChapterManifest manifest,
    required ChapterProgress progress,
    required bool reversedOrder,
  }) => database.transaction(() async {
    _validate(mangaKey, manifest, progress);
    final stored = await loadChapter(
      mangaKey: mangaKey,
      chapterKey: manifest.chapterKey,
    );
    if (stored != null && progress.epoch < stored.epoch) return stored;
    if (progress.epoch != (stored?.epoch ?? 0)) {
      throw StateError('Only reset may advance the persisted reading epoch');
    }
    final merged = (stored ?? ChapterProgress(current: progress.current)).merge(
      manifest: manifest,
      incoming: progress,
    );
    await _write(mangaKey, manifest.chapterKey, merged, reversedOrder);
    return merged;
  });

  Future<ChapterProgress> reset({
    required String mangaKey,
    required ChapterManifest manifest,
    required bool reversedOrder,
  }) => database.transaction(() async {
    if (mangaKey.isEmpty || manifest.pages.isEmpty) {
      throw ArgumentError(
        'Reset requires a nonempty chapter and manga identity',
      );
    }
    final stored = await loadChapter(
      mangaKey: mangaKey,
      chapterKey: manifest.chapterKey,
    );
    final reset = ChapterProgress(
      current: manifest.positionAt(0),
      epoch: (stored?.epoch ?? 0) + 1,
    );
    await _write(mangaKey, manifest.chapterKey, reset, reversedOrder);
    return reset;
  });

  Future<void> _write(
    String mangaKey,
    String chapterKey,
    ChapterProgress progress,
    bool reversedOrder,
  ) async {
    await database
        .into(database.chapterProgressRows)
        .insertOnConflictUpdate(
          ChapterProgressRowsCompanion.insert(
            identityKey: identity.key,
            mangaKey: mangaKey,
            chapterKey: chapterKey,
            currentJson: _encode(progress.current),
            furthestJson: Value(
              progress.furthest == null ? null : _encode(progress.furthest!),
            ),
            epoch: progress.epoch,
            completed: progress.completed,
          ),
        );
    await database
        .into(database.mangaResumeRows)
        .insertOnConflictUpdate(
          MangaResumeRowsCompanion.insert(
            identityKey: identity.key,
            mangaKey: mangaKey,
            chapterKey: chapterKey,
            reversedOrder: reversedOrder,
          ),
        );
  }
}

void _validate(
  String mangaKey,
  ChapterManifest manifest,
  ChapterProgress progress,
) {
  if (mangaKey.isEmpty ||
      manifest.pages.isEmpty ||
      progress.current.chapterKey != manifest.chapterKey ||
      progress.current.manifestVersion != manifest.version ||
      !manifest.pages.any((page) => page.key == progress.current.pageKey)) {
    throw ArgumentError('Progress must belong to the current nonempty chapter');
  }
}

ChapterProgress _progress(ChapterProgressRow row) => ChapterProgress(
  current: _decode(row.currentJson),
  furthest: row.furthestJson == null ? null : _decode(row.furthestJson!),
  epoch: row.epoch,
  completed: row.completed,
);

String _encode(ReadingPosition value) => jsonEncode({
  'chapterKey': value.chapterKey,
  'pageKey': value.pageKey,
  'manifestVersion': value.manifestVersion,
  'pageIndexHint': value.pageIndexHint,
  'normalizedOffset': value.normalizedOffset,
});

ReadingPosition _decode(String value) => switch (jsonDecode(value)) {
  {
    'chapterKey': String chapterKey,
    'pageKey': String pageKey,
    'manifestVersion': String version,
    'pageIndexHint': int index,
    'normalizedOffset': num offset,
  } =>
    ReadingPosition(
      chapterKey: chapterKey,
      pageKey: pageKey,
      manifestVersion: version,
      pageIndexHint: index,
      normalizedOffset: offset.toDouble(),
    ),
  _ => throw const FormatException('Invalid persisted reading position'),
};
