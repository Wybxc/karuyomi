import 'package:flutter/foundation.dart';

import '../../data/bookmark_repository.dart';
import '../../data/business_state_client.dart';

/// A page's confirmed bookmark view. The repository owns uncertain commands so
/// leaving this page does not turn a different action into an implicit retry.
final class ChapterBookmarksController extends ChangeNotifier {
  ChapterBookmarksController({
    required this.repository,
    required this.mangaKey,
    required this.isCurrent,
  });

  final BookmarkRepository repository;
  final String mangaKey;
  final bool Function() isCurrent;
  Set<String> _chapterKeys = const {};
  int _revision = 0;
  bool _loaded = false;
  bool _busy = false;
  bool _retired = false;
  bool _disposed = false;
  String? _error;

  Set<String> get chapterKeys => _chapterKeys;
  bool get loaded => _loaded;
  bool get busy => _busy;
  String? get error => _error;
  BookmarkDraft? get pending => repository.pending(mangaKey);
  bool get available => !_disposed && !_retired && isCurrent();
  bool get canEdit => available && _loaded && !_busy && pending == null;
  bool get canRefresh => available && !_busy;
  bool get canRetry => available && !_busy && pending?.retryable == true;
  bool contains(String chapterKey) => _chapterKeys.contains(chapterKey);

  void checkCurrent() {
    if (_disposed || _retired || isCurrent()) return;
    _retired = true;
    _error = '身份或服务已改变，请重新打开页面读取书签。';
    notifyListeners();
  }

  Future<void> refresh() async {
    checkCurrent();
    if (!canRefresh) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _read();
    } catch (_) {
      if (available) {
        _loaded = false;
        _error = '未能读取服务端书签，仍可继续阅读；请刷新重试。';
      }
    } finally {
      if (!_disposed) {
        _busy = false;
        checkCurrent();
        notifyListeners();
      }
    }
  }

  Future<void> setBookmarked(String chapterKey, bool bookmarked) async {
    checkCurrent();
    if (!canEdit) return;
    await _set(chapterKey, bookmarked, _revision);
  }

  Future<void> retry() async {
    checkCurrent();
    final draft = pending;
    if (!canRetry || draft == null) return;
    await _set(draft.chapterKey, draft.bookmarked, draft.basedOnRevision);
  }

  Future<void> _read() async {
    final value = await repository.loadAll(mangaKey);
    if (!available) return;
    _chapterKeys = Set.unmodifiable(value.chapterKeys);
    _revision = value.revision;
    _loaded = true;
  }

  Future<void> _set(String chapterKey, bool bookmarked, int revision) async {
    _busy = true;
    _error = null;
    notifyListeners();
    var acknowledged = false;
    try {
      final value = await repository.set(
        mangaKey: mangaKey,
        chapterKey: chapterKey,
        bookmarked: bookmarked,
        basedOnRevision: revision,
      );
      if (!available) return;
      acknowledged = true;
      final keys = {..._chapterKeys};
      if (value.bookmarked) {
        keys.add(value.chapterKey);
      } else {
        keys.remove(value.chapterKey);
      }
      _chapterKeys = Set.unmodifiable(keys);
      _revision = value.revision;
      // A retried ACK can refer to an older write; read the complete current
      // collection before letting this page edit another chapter.
      await _read();
    } catch (failure) {
      if (!available) return;
      if (acknowledged) {
        _loaded = false;
        _error = '书签已保存，但重新读取失败；请刷新后继续修改。';
      } else if (failure is BusinessStateException && failure.conflict) {
        _loaded = false;
        _error = '书签或作品已在其他设备修改，请刷新后确认当前状态。';
      } else {
        _error = '书签修改尚未确认，仍可继续阅读；请明确重试原操作。';
      }
    } finally {
      if (!_disposed) {
        _busy = false;
        checkCurrent();
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
