import 'package:flutter/foundation.dart';

import '../../data/business_state_client.dart';
import '../../data/business_state_validation.dart';
import '../../data/progress_repository.dart';
import '../reader/chapter_sequence.dart';

enum ChapterReadItemStatus {
  notStarted,
  sending,
  confirmed,
  uncertain,
  blocked,
}

final class ChapterReadBatchItem {
  ChapterReadBatchItem._(this.chapter);
  final SequenceChapter chapter;
  ChapterReadItemStatus _status = ChapterReadItemStatus.notStarted;
  String? _error;
  int? _expectedRevision;
  ProgressSnapshot? _confirmation;
  ChapterReadItemStatus get status => _status;
  String? get error => _error;
  ProgressSnapshot? get confirmation => _confirmation;
}

final _batches = Expando<Map<String, ChapterReadBatchDraft>>(
  'unfinished chapter read batches',
);

ChapterReadBatchDraft? pendingChapterReadBatch(
  ProgressRepository repository,
  String mangaKey,
) => _batches[repository.client]?[mangaKey];

/// One manga's exact revision chain, with no page loading or resume writes.
final class ChapterReadBatchDraft extends ChangeNotifier {
  ChapterReadBatchDraft({
    required this.repository,
    required this.mangaKey,
    required this.read,
    required int revision,
    required List<SequenceChapter> chapters,
  }) : items = List.unmodifiable(chapters.map(ChapterReadBatchItem._)),
       _nextRevision = revision {
    validateBusinessRevision(revision);
    if (mangaKey.isEmpty ||
        chapters.isEmpty ||
        chapters.map((chapter) => chapter.key).toSet().length !=
            chapters.length) {
      throw ArgumentError('A read batch requires distinct chapter occurrences');
    }
  }

  final ProgressRepository repository;
  final String mangaKey;
  final bool read;
  final List<ChapterReadBatchItem> items;
  int _nextRevision;
  bool _attempted = false;
  bool _busy = false;
  bool _finished = false;
  bool _pauseRequested = false;
  String? _error;
  MangaProgressSnapshot? _reloaded;

  bool get attempted => _attempted;
  bool get busy => _busy;
  bool get finished => _finished;
  bool get completed => confirmedCount == items.length;
  bool get pauseRequested => _pauseRequested;
  String? get error => _error;
  MangaProgressSnapshot? get reloaded => _reloaded;
  int get confirmedCount => items
      .where((item) => item.status == ChapterReadItemStatus.confirmed)
      .length;
  int get notStartedCount => items
      .where((item) => item.status == ChapterReadItemStatus.notStarted)
      .length;
  ChapterReadBatchItem? get failedItem {
    for (final item in items) {
      if (item.status == ChapterReadItemStatus.uncertain ||
          item.status == ChapterReadItemStatus.blocked) {
        return item;
      }
    }
    return null;
  }

  bool get canContinue =>
      attempted &&
      !busy &&
      !finished &&
      failedItem == null &&
      notStartedCount > 0;
  bool get canRetry =>
      !busy &&
      !finished &&
      failedItem?.status == ChapterReadItemStatus.uncertain;
  bool get canReloadAndFinish =>
      !busy && !finished && failedItem?.status == ChapterReadItemStatus.blocked;
  Set<String> get remainingKeys => Set.unmodifiable(
    items
        .where((item) => item.status != ChapterReadItemStatus.confirmed)
        .map((item) => item.chapter.key),
  );

  Future<void> start({required bool Function() isCurrent}) async {
    if (attempted || busy || finished || !isCurrent()) return;
    final pending = pendingChapterReadBatch(repository, mangaKey);
    if (pending != null && !identical(pending, this)) {
      _error = '请先处理此作品尚未结束的章节标记。';
      notifyListeners();
      return;
    }
    final sessions = _batches[repository.client] ??= {};
    sessions[mangaKey] = this;
    _attempted = true;
    await _runRemaining(isCurrent);
  }

  Future<void> continueRemaining({required bool Function() isCurrent}) async {
    if (!canContinue || !isCurrent()) return;
    await _runRemaining(isCurrent);
  }

  Future<void> retry({required bool Function() isCurrent}) async {
    if (!canRetry || !isCurrent()) return;
    _busy = true;
    _pauseRequested = false;
    _error = null;
    notifyListeners();
    try {
      if (isCurrent()) await _send(failedItem!);
      if (completed) _finish();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void pause() {
    if (!busy || pauseRequested) return;
    _pauseRequested = true;
    notifyListeners();
  }

  void finishRemaining() {
    if (!canContinue) return;
    _finish();
    notifyListeners();
  }

  Future<bool> reloadAndFinish({required bool Function() isCurrent}) async {
    if (!canReloadAndFinish || !isCurrent()) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final snapshot = await repository.loadAll(mangaKey);
      if (!isCurrent()) return false;
      _reloaded = snapshot;
      _finish();
      return true;
    } catch (_) {
      _error = '未能重新读取服务端章节状态，请重试。';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _runRemaining(bool Function() isCurrent) async {
    _busy = true;
    _pauseRequested = false;
    _error = null;
    notifyListeners();
    try {
      for (final item in items) {
        if (item.status != ChapterReadItemStatus.notStarted) continue;
        if (!isCurrent() || pauseRequested) {
          _pauseRequested = true;
          break;
        }
        await _send(item);
        if (item.status != ChapterReadItemStatus.confirmed) break;
      }
      if (completed) _finish();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _send(ChapterReadBatchItem item) async {
    item._status = ChapterReadItemStatus.sending;
    item._error = null;
    item._expectedRevision ??= _nextRevision;
    notifyListeners();
    try {
      final snapshot = await repository.setChapterRead(
        mangaKey: mangaKey,
        chapterKey: item.chapter.key,
        read: read,
        basedOnRevision: item._expectedRevision!,
      );
      if (snapshot.revision != item._expectedRevision! + 1 ||
          snapshot.completed != read) {
        throw const FormatException(
          'Chapter marking did not confirm its exact revision',
        );
      }
      item._confirmation = snapshot;
      item._status = ChapterReadItemStatus.confirmed;
      _nextRevision = snapshot.revision;
    } on BusinessPendingMutationException {
      item._status = ChapterReadItemStatus.blocked;
      item._error = '此作品已有另一项未确认修改，请先处理原操作，再重新读取并确认章节清单。';
    } on BusinessStateException catch (failure) {
      final blocked = failure.conflict || !failure.error.retryable;
      item._status = blocked
          ? ChapterReadItemStatus.blocked
          : ChapterReadItemStatus.uncertain;
      item._error = failure.conflict
          ? '作品已在其他操作或设备更新，请重新读取章节状态后确认新清单。'
          : blocked
          ? '服务端拒绝了该项标记，请重新读取章节状态后处理。'
          : '尚未确认该项标记，请原样重试；后续章节尚未发送。';
    } catch (_) {
      item._status = ChapterReadItemStatus.uncertain;
      item._error = '尚未确认该项标记，请原样重试；后续章节尚未发送。';
    }
    _error = item.error;
    notifyListeners();
  }

  void _finish() {
    _finished = true;
    final sessions = _batches[repository.client];
    if (identical(sessions?[mangaKey], this)) sessions!.remove(mangaKey);
  }
}
