import 'package:flutter/foundation.dart';

import '../../data/business_state_client.dart';
import '../../data/business_state_validation.dart';
import '../../data/library_repository.dart';

enum LibraryBatchAction { removeFavorites, addCategories, removeCategories }

enum LibraryBatchItemStatus {
  notStarted,
  sending,
  confirmed,
  uncertain,
  blocked,
}

final class LibraryBatchItem {
  LibraryBatchItem._(this.entry, List<String> categoryIds)
    : categoryIds = List.unmodifiable(categoryIds);

  final LibraryEntry entry;
  final List<String> categoryIds;
  LibraryBatchItemStatus _status = LibraryBatchItemStatus.notStarted;
  String? _error;
  LibraryBatchItemStatus get status => _status;
  String? get error => _error;
}

// A session draft belongs to the authenticated business client. Recreating a
// repository wrapper must not lose the original command or its recovery entry.
final _batches = Expando<LibraryBatchDraft>('unfinished library batch');

LibraryBatchDraft? pendingLibraryBatch(LibraryRepository repository) =>
    _batches[repository.client];

/// Sequential writes against the exact shelf snapshot the user confirmed.
/// This is a session draft, not an atomic server transaction or durable outbox.
final class LibraryBatchDraft extends ChangeNotifier {
  LibraryBatchDraft({
    required this.repository,
    required this.view,
    required Set<String> mangaKeys,
    required this.action,
    Set<String> categoryIds = const {},
  }) : items = _freezeItems(view, mangaKeys, action, categoryIds);

  final LibraryRepository repository;
  final LibraryView view;
  final LibraryBatchAction action;
  final List<LibraryBatchItem> items;
  bool _attempted = false;
  bool _busy = false;
  bool _finished = false;
  bool _pauseRequested = false;
  String? _error;

  bool get attempted => _attempted;
  bool get busy => _busy;
  bool get completed => confirmedCount == items.length;
  bool get finished => _finished;
  bool get pauseRequested => _pauseRequested;
  String? get error => _error;
  int get confirmedCount => items
      .where((item) => item.status == LibraryBatchItemStatus.confirmed)
      .length;
  int get notStartedCount => items
      .where((item) => item.status == LibraryBatchItemStatus.notStarted)
      .length;
  LibraryBatchItem? get failedItem {
    for (final item in items) {
      if (item.status == LibraryBatchItemStatus.uncertain ||
          item.status == LibraryBatchItemStatus.blocked) {
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
      failedItem?.status == LibraryBatchItemStatus.uncertain;
  bool get canReloadAndFinish =>
      !busy &&
      !finished &&
      failedItem?.status == LibraryBatchItemStatus.blocked;
  Set<String> get remainingKeys => Set.unmodifiable(
    items
        .where((item) => item.status != LibraryBatchItemStatus.confirmed)
        .map((item) => item.entry.mangaKey),
  );

  Future<void> start({required bool Function() isCurrent}) async {
    if (attempted || busy || finished || !isCurrent()) return;
    final pending = pendingLibraryBatch(repository);
    if (pending != null && !identical(pending, this)) {
      _error = '请先处理当前会话中尚未结束的书架批次。';
      notifyListeners();
      return;
    }
    _batches[repository.client] = this;
    _attempted = true;
    await _runRemaining(isCurrent);
  }

  Future<void> continueRemaining({required bool Function() isCurrent}) async {
    if (!canContinue || !isCurrent()) return;
    await _runRemaining(isCurrent);
  }

  /// Retry only the uncertain original write. Starting the remaining writes
  /// requires a separate explicit action after this result is confirmed.
  Future<void> retry({required bool Function() isCurrent}) async {
    if (!canRetry || !isCurrent()) return;
    final item = failedItem!;
    _busy = true;
    _pauseRequested = false;
    _error = null;
    notifyListeners();
    try {
      if (isCurrent()) await _send(item);
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

  /// End only the unsent remainder after all attempted writes have settled.
  void finishRemaining() {
    if (!canContinue) return;
    _finish();
    notifyListeners();
  }

  /// A definite rejection ends this frozen batch after a read. Its old CAS
  /// revisions are never raised to turn it into a new write automatically.
  Future<bool> reloadAndFinish({required bool Function() isCurrent}) async {
    if (!canReloadAndFinish || !isCurrent()) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await repository.refresh();
      if (!isCurrent()) return false;
      _finish();
      return true;
    } catch (_) {
      _error = '未能重新读取服务端书架，请重试。';
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
        if (item.status != LibraryBatchItemStatus.notStarted) continue;
        if (!isCurrent() || pauseRequested) {
          _pauseRequested = true;
          break;
        }
        await _send(item);
        if (item.status != LibraryBatchItemStatus.confirmed) break;
      }
      if (completed) _finish();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _send(LibraryBatchItem item) async {
    item._status = LibraryBatchItemStatus.sending;
    item._error = null;
    notifyListeners();
    try {
      switch (action) {
        case LibraryBatchAction.removeFavorites:
          await repository.removeFavorite(
            mangaKey: item.entry.mangaKey,
            expectedMangaRevision: item.entry.revision,
          );
        case LibraryBatchAction.addCategories:
        case LibraryBatchAction.removeCategories:
          await repository.setCategories(
            mangaKey: item.entry.mangaKey,
            categoryIds: item.categoryIds,
            expectedCatalogRevision: view.categoryRevision,
            expectedMangaRevision: item.entry.revision,
          );
      }
      // A late ACK may settle the old draft, but the loop checks the caller's
      // lifetime before sending any subsequent entry.
      item._status = LibraryBatchItemStatus.confirmed;
    } on BusinessPendingMutationException {
      item._status = LibraryBatchItemStatus.blocked;
      item._error = '该漫画已有另一项未确认修改，请先处理原操作，再重新读取书架并确认新清单。';
    } on BusinessStateException catch (failure) {
      final blocked = failure.conflict || !failure.error.retryable;
      item._status = blocked
          ? LibraryBatchItemStatus.blocked
          : LibraryBatchItemStatus.uncertain;
      item._error = failure.conflict
          ? '该漫画或分类已变化，请重新读取书架并确认新的清单。'
          : blocked
          ? '服务端拒绝了该项修改，请重新读取书架后处理。'
          : '尚未确认该项修改，请原样重试；后续项目尚未发送。';
    } catch (_) {
      item._status = LibraryBatchItemStatus.uncertain;
      item._error = '尚未确认该项修改，请原样重试；后续项目尚未发送。';
    }
    _error = item.error;
    notifyListeners();
  }

  void _finish() {
    _finished = true;
    if (identical(pendingLibraryBatch(repository), this)) {
      _batches[repository.client] = null;
    }
  }
}

List<LibraryBatchItem> _freezeItems(
  LibraryView view,
  Set<String> mangaKeys,
  LibraryBatchAction action,
  Set<String> categoryIds,
) {
  if (mangaKeys.isEmpty) throw ArgumentError('Select at least one shelf entry');
  validateBusinessRevision(view.categoryRevision);
  final catalogIds = view.categories.map((category) => category.id).toSet();
  if (catalogIds.length != view.categories.length ||
      !catalogIds.containsAll(categoryIds) ||
      (action != LibraryBatchAction.removeFavorites && categoryIds.isEmpty) ||
      (action == LibraryBatchAction.removeFavorites &&
          categoryIds.isNotEmpty)) {
    throw ArgumentError('Batch categories must match the confirmed catalog');
  }
  final found = <String>{};
  final items = <LibraryBatchItem>[];
  for (final entry in view.entries) {
    if (!mangaKeys.contains(entry.mangaKey)) continue;
    if (!found.add(entry.mangaKey) ||
        !catalogIds.containsAll(entry.categoryIds)) {
      throw const FormatException('Shelf entries do not match their catalog');
    }
    final target = entry.categoryIds.toSet();
    switch (action) {
      case LibraryBatchAction.addCategories:
        target.addAll(categoryIds);
      case LibraryBatchAction.removeCategories:
        target.removeAll(categoryIds);
      case LibraryBatchAction.removeFavorites:
        break;
    }
    items.add(
      LibraryBatchItem._(
        entry,
        view.categories
            .where((category) => target.contains(category.id))
            .map((category) => category.id)
            .toList(),
      ),
    );
  }
  if (found.length != mangaKeys.length) {
    throw ArgumentError(
      'Selection contains entries outside the confirmed shelf',
    );
  }
  return List.unmodifiable(items);
}
