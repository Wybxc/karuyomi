import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:reader_core/reader_core.dart';

enum ProgressStorageMode { serverConfirmed }

/// Constructed only after bootstrap has confirmed the user's identity.
final class ProgressIdentity({
  required Uri origin,
  required final String subject,
}) {
  final Uri origin = _origin(origin);
  this {
    if (subject.isEmpty) {
      throw ArgumentError('Progress subject cannot be empty');
    }
  }

  static Uri _origin(Uri value) {
    if ((value.scheme != 'https' && value.scheme != 'http') ||
        value.host.isEmpty ||
        value.userInfo.isNotEmpty) {
      throw ArgumentError('Progress requires an HTTP deployment origin');
    }
    return Uri.parse(value.origin);
  }

  String get key => sha256
      .convert(utf8.encode(jsonEncode([origin.origin, subject])))
      .toString();
}

final class const MangaResume({
  required final String chapterKey,
  required final bool reversedOrder,
});

/// Current navigation and observed reading progress have different lifetimes.
/// Preloading or restoring a position never counts as observing a page.
final class ChapterProgress({
  required final ReadingPosition current,
  final ReadingPosition? furthest,
  final int epoch = 0,
  final bool completed = false,
}) {
  this {
    if (epoch < 0 ||
        (furthest != null && furthest!.chapterKey != current.chapterKey)) {
      throw ArgumentError('Invalid progress epoch or chapter identity');
    }
  }

  bool furthestUnresolved(ChapterManifest manifest) =>
      furthest != null && _project(manifest, furthest!) == null;

  ChapterProgress advance({
    required ChapterManifest manifest,
    required ReadingPosition current,
    ReadingPosition? observed,
    bool complete = false,
  }) {
    final resolvedCurrent = _requirePosition(manifest, current);
    final resolvedObserved = observed == null
        ? null
        : _requirePosition(manifest, observed);
    if (complete &&
        (resolvedObserved == null ||
            resolvedObserved.pageIndexHint != manifest.pages.length - 1)) {
      throw ArgumentError('Completion requires an actually observed last page');
    }
    return ChapterProgress(
      current: resolvedCurrent,
      furthest: _farther(manifest, furthest, resolvedObserved),
      epoch: epoch,
      completed: completed || complete,
    );
  }

  /// Merges same-epoch progress; persisted merges happen atomically on Worker.
  /// A missing old page stays unresolved instead of borrowing its old index.
  ChapterProgress merge({
    required ChapterManifest manifest,
    required ChapterProgress incoming,
  }) {
    if (epoch != incoming.epoch) {
      throw ArgumentError('Only progress in the same reading epoch can merge');
    }
    final resolvedCurrent = _requirePosition(manifest, incoming.current);
    return ChapterProgress(
      current: resolvedCurrent,
      furthest: _farther(manifest, furthest, incoming.furthest),
      epoch: epoch,
      completed: completed || incoming.completed,
    );
  }
}

ReadingPosition _requirePosition(
  ChapterManifest manifest,
  ReadingPosition position,
) =>
    _project(manifest, position) ??
    (throw ArgumentError('Progress must reference an existing chapter page'));

ReadingPosition? _project(ChapterManifest manifest, ReadingPosition position) {
  if (position.chapterKey != manifest.chapterKey) return null;
  final index = manifest.pages.indexWhere(
    (page) => page.key == position.pageKey,
  );
  return index < 0
      ? null
      : manifest.positionAt(
          index,
          offset: position.normalizedOffset,
          normalizedX: position.normalizedX,
          viewportX: position.viewportX,
          viewportY: position.viewportY,
        );
}

ReadingPosition? _farther(
  ChapterManifest manifest,
  ReadingPosition? previous,
  ReadingPosition? incoming,
) {
  final before = previous == null ? null : _project(manifest, previous);
  final next = incoming == null ? null : _project(manifest, incoming);
  if (previous != null && before == null) return previous;
  if (incoming != null && next == null) return previous ?? incoming;
  if (before == null) return next;
  if (next == null) return before;
  return next.pageIndexHint > before.pageIndexHint ||
          (next.pageIndexHint == before.pageIndexHint &&
              next.normalizedOffset > before.normalizedOffset)
      ? next
      : before;
}
