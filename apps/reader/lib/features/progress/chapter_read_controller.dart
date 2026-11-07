import 'package:flutter/foundation.dart';

import '../../data/progress_repository.dart';

/// A complete, confirmed view. Missing rows mean unread only after loadAll.
final class ChapterReadController extends ChangeNotifier {
  ChapterReadController({
    required this.repository,
    required this.mangaKey,
    required this.isCurrent,
  });

  final ProgressRepository repository;
  final String mangaKey;
  final bool Function() isCurrent;
  Map<String, bool> _completed = const {};
  int _revision = 0;
  bool _loaded = false;
  Future<void>? _refreshing;
  bool _retired = false;
  bool _disposed = false;
  String? _error;

  int get revision => _revision;
  bool get loaded => _loaded;
  bool get busy => _refreshing != null;
  String? get error => _error;
  bool get available => !_disposed && !_retired && isCurrent();
  bool get canRefresh => available && !busy;
  bool? completed(String chapterKey) =>
      _loaded ? (_completed[chapterKey] ?? false) : null;

  void checkCurrent() {
    if (_disposed || _retired || isCurrent()) return;
    _retired = true;
    _error = '身份或服务已变化，请重新打开详情读取章节状态。';
    notifyListeners();
  }

  Future<void> refresh() {
    checkCurrent();
    if (!available) return Future<void>.value();
    if (_refreshing case final active?) return active;
    _error = null;
    final current = _loadSnapshot().whenComplete(() {
      _refreshing = null;
      if (!_disposed) {
        checkCurrent();
        notifyListeners();
      }
    });
    _refreshing = current;
    notifyListeners();
    return current;
  }

  /// A read already in flight may predate a just-confirmed local write.
  Future<void> refreshAfterCurrent() async {
    if (_refreshing case final active?) await active;
    await refresh();
  }

  Future<void> _loadSnapshot() async {
    try {
      final snapshot = await repository.loadAll(mangaKey);
      acceptSnapshot(snapshot);
    } catch (_) {
      if (available) {
        _loaded = false;
        _error = '未能读取服务端章节状态，仍可继续阅读；请刷新重试。';
      }
    }
  }

  void acceptSnapshot(MangaProgressSnapshot snapshot) {
    if (!available || (_loaded && snapshot.revision < _revision)) return;
    _completed = Map.unmodifiable({
      for (final entry in snapshot.chapters.entries)
        entry.key: entry.value.completed,
    });
    _revision = snapshot.revision;
    _loaded = true;
    _error = null;
    notifyListeners();
  }

  void acceptConfirmed(String chapterKey, ProgressSnapshot snapshot) {
    if (!available || !_loaded || snapshot.revision < _revision) return;
    _completed = Map.unmodifiable({
      ..._completed,
      chapterKey: snapshot.completed,
    });
    _revision = snapshot.revision;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
