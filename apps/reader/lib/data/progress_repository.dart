import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_client.dart';
import 'business_state_validation.dart';
import 'reading_progress.dart';

final class ProgressRepository {
  ProgressRepository(this.client);
  final BusinessStateClient client;
  ProgressIdentity get identity => client.identity;

  Future<ChapterProgress?> loadChapter({
    required String mangaKey,
    required String chapterKey,
  }) async {
    final result = await client.readManga(mangaKey, chapterKey: chapterKey);
    return result.hasProgress() ? decodeChapterProgress(result.progress) : null;
  }

  Future<MangaResume?> loadResume(String mangaKey) async {
    final result = await client.readManga(mangaKey);
    return result.manga.hasResume()
        ? MangaResume(
            chapterKey: result.manga.resume.chapterKey,
            reversedOrder: result.manga.resume.reversedOrder,
          )
        : null;
  }

  Future<ChapterProgress> save({
    required String mangaKey,
    required ChapterManifest manifest,
    required ChapterProgress progress,
    required bool reversedOrder,
  }) async {
    _validate(mangaKey, manifest, progress);
    final result = await client.mutate(
      wire.StateMutation(
        mangaKey: mangaKey,
        saveProgress: wire.SaveProgress(
          snapshot: _snapshot(manifest),
          progress: _progress(progress),
          reversedOrder: reversedOrder,
        ),
      ),
    );
    return _confirmedProgress(result, manifest.chapterKey);
  }

  Future<ChapterProgress> reset({
    required String mangaKey,
    required ChapterManifest manifest,
    required bool reversedOrder,
  }) async {
    if (mangaKey.isEmpty || manifest.pages.isEmpty) {
      throw ArgumentError(
        'Reset requires a nonempty chapter and manga identity',
      );
    }
    final result = await client.mutate(
      wire.StateMutation(
        mangaKey: mangaKey,
        resetProgress: wire.ResetProgress(
          snapshot: _snapshot(manifest),
          reversedOrder: reversedOrder,
        ),
      ),
    );
    return _confirmedProgress(result, manifest.chapterKey);
  }
}

ChapterProgress _confirmedProgress(
  wire.StateMutationResponse result,
  String chapterKey,
) {
  if (!result.hasProgress() || result.progress.chapterKey != chapterKey) {
    throw const FormatException('Progress response chapter mismatch');
  }
  return decodeChapterProgress(result.progress);
}

ChapterProgress decodeChapterProgress(wire.ChapterProgressState value) {
  validateBusinessProgress(value);
  return ChapterProgress(
    current: _decodeAnchor(value.current),
    furthest: value.hasFurthest() ? _decodeAnchor(value.furthest) : null,
    epoch: value.epoch,
    completed: value.completed,
  );
}

ReadingPosition _decodeAnchor(wire.ReadingAnchor value) {
  validateBusinessAnchor(value);
  return ReadingPosition(
    chapterKey: value.chapterKey,
    pageKey: value.pageKey,
    manifestVersion: value.manifestVersion,
    pageIndexHint: value.pageIndexHint,
    normalizedOffset: value.normalizedOffset,
  );
}

wire.ReadingAnchor _anchor(ReadingPosition value) => wire.ReadingAnchor(
  chapterKey: value.chapterKey,
  pageKey: value.pageKey,
  manifestVersion: value.manifestVersion,
  pageIndexHint: value.pageIndexHint,
  normalizedOffset: value.normalizedOffset,
);
wire.ChapterProgressState _progress(ChapterProgress value) {
  final result = wire.ChapterProgressState(
    chapterKey: value.current.chapterKey,
    current: _anchor(value.current),
    furthest: value.furthest == null ? null : _anchor(value.furthest!),
    epoch: value.epoch,
    completed: value.completed,
  );
  validateBusinessProgress(result);
  return result;
}

wire.ChapterSnapshot _snapshot(ChapterManifest value) {
  if (value.pages.length > 2048) {
    throw ArgumentError('Chapter exceeds progress snapshot budget');
  }
  return wire.ChapterSnapshot(
    chapterKey: value.chapterKey,
    manifestVersion: value.version,
    pageKeys: value.pages.map((page) => page.key),
  );
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
