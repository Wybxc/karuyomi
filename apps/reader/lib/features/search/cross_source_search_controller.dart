import 'dart:async';

import 'package:flutter/foundation.dart';

import '../browse/catalog_controller.dart';

const crossSourceSelectionLimit = 32;
const crossSourceQueryLimit = 500;
const crossSourceResultLimit = 1000;
const crossSourcePerSourceLimit = 200;

enum SourceSearchStatus {
  queued,
  loading,
  complete,
  error,
  cancelling,
  cancelled,
  cancellationFailed,
}

final class SourceSearchGroup {
  SourceSearchGroup({required this.target, required this.query});
  final SourceSearchTarget target;
  final String query;
  List<MangaEntry> mangas = const [];
  int page = 0;
  bool hasNextPage = false;
  SourceSearchStatus status = SourceSearchStatus.queued;
  String? error;
  String? limitReason;
  SourceSearchTask? _task;
  int _request = 0;

  bool get active => {
    SourceSearchStatus.queued,
    SourceSearchStatus.loading,
    SourceSearchStatus.cancelling,
    SourceSearchStatus.cancellationFailed,
  }.contains(status);
}

final class CrossSourceSearchController extends ChangeNotifier {
  CrossSourceSearchController({
    required this.service,
    bool Function()? isCurrent,
  }) : isCurrent = isCurrent ?? (() => true) {
    service.addListener(_serviceChanged);
    if (!service.available) _retired = true;
  }

  final CatalogSourceSearch service;
  final bool Function() isCurrent;
  List<SourceSearchTarget> targets = const [];
  List<SourceSearchGroup> groups = const [];
  final _selected = <String>{};
  Set<String> get selected => Set.unmodifiable(_selected);
  String? language;
  String query = '';
  String? error;
  String? cleanupError;
  bool loadingTargets = false;
  bool transitioning = false;
  bool opening = false;
  bool _retired = false;
  bool _disposed = false;
  bool _closed = false;
  int _epoch = 0;

  bool get available =>
      !_disposed && !_retired && !_closed && service.available;
  String? get unavailableReason =>
      available ? null : service.unavailableReason ?? '身份或服务已改变，请关闭后重新开始搜索。';
  bool get hasActive => groups.any((group) => group.active);
  int get resultCount =>
      groups.fold(0, (count, group) => count + group.mangas.length);
  bool get canChange =>
      available && !loadingTargets && !transitioning && !opening;
  bool get canSelect => canChange && !hasActive && cleanupError == null;
  List<String> get languages =>
      targets.map((target) => target.source.lang).toSet().toList()..sort();
  List<SourceSearchTarget> get visibleTargets => List.unmodifiable(
    targets.where(
      (target) => language == null || target.source.lang == language,
    ),
  );

  bool _current(int epoch) => available && isCurrent() && epoch == _epoch;

  void _serviceChanged() {
    if (_disposed) return;
    if (!service.available) {
      _retired = true;
      ++_epoch;
    }
    notifyListeners();
  }

  Future<void> loadTargets() async {
    if (!canSelect || !isCurrent()) return;
    loadingTargets = true;
    error = null;
    final epoch = _epoch;
    notifyListeners();
    try {
      final loaded = await service.loadTargets();
      if (!_current(epoch)) return;
      targets = List.unmodifiable(loaded);
      _selected.removeWhere(
        (key) => !targets.any((target) => target.key == key),
      );
      if (!languages.contains(language)) language = null;
    } catch (failure) {
      if (_current(epoch)) error = _message(failure);
    } finally {
      if (!_disposed) {
        loadingTargets = false;
        notifyListeners();
      }
    }
  }

  void select(SourceSearchTarget target, bool value) {
    if (!canSelect || !targets.any((item) => item.key == target.key)) return;
    if (value && !_selected.contains(target.key)) {
      if (_selected.length >= crossSourceSelectionLimit) {
        error = '最多选择32个漫画源，请先取消部分选择。';
        notifyListeners();
        return;
      }
      _selected.add(target.key);
    } else if (!value) {
      _selected.remove(target.key);
    }
    error = null;
    notifyListeners();
  }

  void selectLanguage(String? value) {
    if (!canChange || (value != null && !languages.contains(value))) return;
    language = value;
    notifyListeners();
  }

  Future<void> start(String value) async {
    if (!canChange || !isCurrent()) return;
    final text = value.trim();
    if (text.isEmpty || text.length > crossSourceQueryLimit) {
      error = '请输入1至500字的搜索词。';
      notifyListeners();
      return;
    }
    final choices = targets
        .where((target) => _selected.contains(target.key))
        .toList(growable: false);
    if (choices.isEmpty || choices.length > crossSourceSelectionLimit) {
      error = '请选择1至32个漫画源。';
      notifyListeners();
      return;
    }
    if (!await stop() || !available || !isCurrent()) return;
    query = text;
    groups = List.unmodifiable([
      for (final target in choices)
        SourceSearchGroup(target: target, query: text),
    ]);
    error = null;
    final epoch = _epoch;
    for (final group in groups) {
      _search(group, epoch);
    }
    notifyListeners();
  }

  void _search(SourceSearchGroup group, int epoch) {
    final request = ++group._request;
    group.status = SourceSearchStatus.queued;
    group.error = null;
    try {
      final task = service.search(
        group.target,
        group.query,
        page: group.page + 1,
        onStarted: () {
          if (!_current(epoch) || request != group._request) return;
          group.status = SourceSearchStatus.loading;
          notifyListeners();
        },
      );
      group._task = task;
      unawaited(_receive(group, task, epoch, request));
    } catch (failure) {
      if (!_current(epoch) || request != group._request) return;
      group.status = SourceSearchStatus.error;
      group.error = _message(failure);
    }
  }

  Future<void> _receive(
    SourceSearchGroup group,
    SourceSearchTask task,
    int epoch,
    int request,
  ) async {
    try {
      final found = await task.result;
      if (!_current(epoch) || request != group._request) return;
      group._task = null;
      if (group.mangas.length + found.mangas.length >
              crossSourcePerSourceLimit ||
          resultCount + found.mangas.length > crossSourceResultLimit) {
        group.limitReason = '本页超过每源200项或总计1000项的上限，请缩小搜索范围后重新搜索。';
        group.error = group.limitReason;
        group.status = SourceSearchStatus.error;
        return;
      }
      group.mangas = List.unmodifiable([...group.mangas, ...found.mangas]);
      ++group.page;
      group.hasNextPage = found.hasNextPage;
      group.status = SourceSearchStatus.complete;
      if (found.hasNextPage &&
          (group.mangas.length >= crossSourcePerSourceLimit ||
              resultCount >= crossSourceResultLimit)) {
        group.limitReason = '已达每源200项或总计1000项的上限；请缩小范围后重新搜索以查看更多。';
      }
    } catch (failure) {
      if (!_current(epoch) || request != group._request) return;
      group._task = null;
      group.status = SourceSearchStatus.error;
      group.error = _message(failure);
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  bool canContinue(SourceSearchGroup group) =>
      canChange &&
      cleanupError == null &&
      !group.active &&
      group.limitReason == null &&
      (group.status == SourceSearchStatus.error ||
          group.status == SourceSearchStatus.cancelled ||
          (group.status == SourceSearchStatus.complete && group.hasNextPage));

  void next(SourceSearchGroup group) {
    if (!canContinue(group) || !groups.contains(group) || !isCurrent()) return;
    _search(group, _epoch);
    notifyListeners();
  }

  Future<void> cancel(SourceSearchGroup group) async {
    final task = group._task;
    if (!available ||
        transitioning ||
        task == null ||
        !groups.contains(group) ||
        group.status == SourceSearchStatus.cancelling) {
      return;
    }
    final request = ++group._request;
    final epoch = _epoch;
    group.status = SourceSearchStatus.cancelling;
    group.error = null;
    notifyListeners();
    try {
      await task.cancel();
      if (_disposed || epoch != _epoch || request != group._request) return;
      group._task = null;
      group.status = SourceSearchStatus.cancelled;
    } catch (failure) {
      if (_disposed || epoch != _epoch || request != group._request) return;
      group.status = SourceSearchStatus.cancellationFailed;
      group.error = '停止尚未确认：${_message(failure)}';
    } finally {
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> stop() async {
    if (_disposed || transitioning) return false;
    transitioning = true;
    ++_epoch;
    error = null;
    notifyListeners();
    try {
      await service.stop();
      if (_disposed) return false;
      for (final group in groups) {
        ++group._request;
        group._task = null;
        if (group.active) group.status = SourceSearchStatus.cancelled;
      }
      cleanupError = null;
      return true;
    } catch (failure) {
      if (!_disposed) cleanupError = '搜索资源尚未释放：${_message(failure)}';
      return false;
    } finally {
      if (!_disposed) {
        transitioning = false;
        notifyListeners();
      }
    }
  }

  Future<
    ({MangaEntry manga, List<ChapterEntry> chapters, CatalogSourceRef source})?
  >
  open(SourceSearchGroup group, MangaEntry manga) async {
    if (!canChange ||
        !groups.contains(group) ||
        !group.mangas.contains(manga) ||
        !isCurrent()) {
      return null;
    }
    if (!await stop() || !available || !isCurrent()) return null;
    opening = true;
    error = null;
    final epoch = _epoch;
    notifyListeners();
    try {
      final details = await service.openResult(
        group.target,
        manga,
        shouldContinue: () => _current(epoch),
      );
      if (!_current(epoch)) return null;
      if (details == null) error = '作品详情未能打开，请重试。';
      return details;
    } catch (failure) {
      if (_current(epoch)) error = _message(failure);
      return null;
    } finally {
      if (!_disposed) {
        opening = false;
        notifyListeners();
      }
    }
  }

  Future<bool> close() async {
    if (_closed) return true;
    if (_disposed || transitioning) return false;
    transitioning = true;
    ++_epoch;
    notifyListeners();
    try {
      await service.close();
      if (_disposed) return false;
      _closed = true;
      cleanupError = null;
      for (final group in groups) {
        group._task = null;
        if (group.active) group.status = SourceSearchStatus.cancelled;
      }
      return true;
    } catch (failure) {
      if (!_disposed) cleanupError = '搜索资源尚未释放：${_message(failure)}';
      return false;
    } finally {
      if (!_disposed) {
        transitioning = false;
        notifyListeners();
      }
    }
  }

  static String _message(Object error) =>
      error is FormatException ? error.message.toString() : error.toString();

  Future<void> _disposeService() async {
    try {
      if (!_closed) await service.close();
    } catch (_) {
      // Normal route exit keeps the page mounted until cleanup is confirmed.
      // A forced widget disposal still retires the service permanently.
    } finally {
      service.dispose();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    service.removeListener(_serviceChanged);
    unawaited(_disposeService());
    super.dispose();
  }
}
