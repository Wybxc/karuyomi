part of 'catalog_controller.dart';

final class SourceSearchTarget {
  SourceSearchTarget({
    required this.build,
    required wire.CatalogSource source,
    required this.bundleSha256,
  }) : source = source.deepCopy()..freeze();
  final CatalogBuild build;
  final wire.CatalogSource source;
  final String bundleSha256;
  String get key => jsonEncode([
    build.catalogUrl,
    build.repoId,
    build.packageName,
    build.id,
    bundleSha256,
    source.id,
  ]);
}

final class SourceSearchPage {
  SourceSearchPage({
    required List<MangaEntry> mangas,
    required this.hasNextPage,
  }) : mangas = List.unmodifiable(mangas);
  final List<MangaEntry> mangas;
  final bool hasNextPage;
}

abstract interface class SourceSearchTask {
  Future<SourceSearchPage> get result;
  Future<void> cancel();
}

/// A page-scoped search: account authority stays with CatalogController/D1.
/// Closing an operation never closes a reader or borrows its execution slot.
abstract class CatalogSourceSearch extends ChangeNotifier {
  bool get available;
  String? get unavailableReason;
  Future<List<SourceSearchTarget>> loadTargets();
  SourceSearchTask search(
    SourceSearchTarget target,
    String query, {
    int page = 1,
    void Function()? onStarted,
  });
  Future<void> stop();
  Future<void> close();
  Future<
    ({MangaEntry manga, List<ChapterEntry> chapters, CatalogSourceRef source})?
  >
  openResult(
    SourceSearchTarget target,
    MangaEntry manga, {
    bool Function()? shouldContinue,
  });
}

extension CatalogCrossSourceSearch on CatalogController {
  CatalogSourceSearch createSourceSearch() {
    final client = _confirmedBusinessClient;
    final secondary =
        _searchRuntimeOverride ??
        (api is PlatformRuntime
            ? (api as PlatformRuntime).searchRuntime
            : null);
    if (client == null || secondary == null || identical(runtime, secondary)) {
      throw StateError('当前服务没有两个独立的搜索执行槽。');
    }
    final search = _CatalogSourceSearch(this, client, secondary);
    _searchScopes.add(search);
    return search;
  }
}

final class _SearchJob implements SourceSearchTask {
  _SearchJob(this.owner, this.target, this.query, this.page, this.onStarted);
  final _CatalogSourceSearch owner;
  final SourceSearchTarget target;
  final String query;
  final int page;
  final void Function()? onStarted;
  final _result = Completer<SourceSearchPage>();
  final cancelled = Completer<void>();
  final done = Completer<void>();
  _SearchPackage? package;
  String? requestId;
  bool opening = false;
  bool finished = false;
  Future<void>? cancelling;
  @override
  Future<SourceSearchPage> get result => _result.future;
  bool get isCancelled => cancelled.isCompleted;
  @override
  Future<void> cancel() {
    if (finished) return Future.value();
    if (!cancelled.isCompleted) cancelled.complete();
    return cancelling ??= _cancel().whenComplete(() {
      cancelling = null;
    });
  }

  Future<void> _cancel() async {
    final running = package;
    if (running?.active != this || running?.runtime == null) return;
    final closing = running!.closing;
    if (closing != null) {
      await closing;
      return;
    }
    final runtime = running.runtime!;
    final id = requestId;
    if (id != null && running.session != null) {
      try {
        await runtime.cancel(id);
      } catch (_) {
        // Active cancellation may report the retired generation as runtimeLost.
        // A reset ACK proves physical shutdown even when the cancel ACK is lost.
        await _reset(runtime, running);
      }
    } else if (opening) {
      await _reset(runtime, running);
    }
    // A pre-open authority request has no Worker. Its continuation checks the
    // cancellation flag before it can acquire or execute any extension code.
  }

  Future<void> _reset(SourceRuntime runtime, _SearchPackage running) async {
    try {
      await runtime.rebuildHost();
    } catch (failure) {
      // A rejected open is only a logical epoch change. Without a reset ACK,
      // startup may still own a physical Worker even before session exists.
      owner._dirty[runtime] = running.session;
      owner._cleanupError(failure);
      rethrow;
    }
  }

  void fail(Object error, [StackTrace? stack]) {
    if (!_result.isCompleted) _result.completeError(error, stack);
  }

  void finish() {
    finished = true;
    if (!done.isCompleted) done.complete();
  }
}

final class _SearchPackage {
  _SearchPackage(this.key);
  final String key;
  final jobs = <_SearchJob>[];
  _SearchJob? active;
  SourceRuntime? runtime;
  RuntimeSession? session;
  Future<void>? running;
  Future<void>? closing;
}

final class _CatalogSourceSearch extends CatalogSourceSearch {
  _CatalogSourceSearch(this.catalog, this.client, this.secondary) {
    catalog.addListener(_changed);
    _events = [
      catalog.runtime.events.listen(_runtimeEvent),
      secondary.events.listen(_runtimeEvent),
    ];
  }
  static int _sequence = 0;
  final int id = ++_sequence;
  final CatalogController catalog;
  final BusinessStateClient client;
  final SourceRuntime secondary;
  final _pool = Pool(2);
  final _free = <SourceRuntime>[];
  final _packages = <String, _SearchPackage>{};
  final _jobs = <_SearchJob>{};
  final _targets = <String, SourceSearchTarget>{};
  final _dirty = <SourceRuntime, RuntimeSession?>{};
  late final List<StreamSubscription<RuntimeEvent>> _events;
  Future<void>? _claiming;
  Future<void>? _stopping;
  Future<void>? _closing;
  bool _retired = false;
  bool _disposed = false;
  bool _closed = false;
  String? _reason;
  String? _cleanupFailure;
  int _requestSequence = 0;

  @override
  bool get available =>
      !_retired &&
      !_disposed &&
      !_closed &&
      !catalog._closed &&
      identical(catalog._confirmedBusinessClient, client) &&
      {ServiceStatus.ready, ServiceStatus.failed}.contains(catalog.status) &&
      _cleanupFailure == null;
  @override
  String? get unavailableReason => _cleanupFailure ?? _reason;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _check() {
    if (!available) throw StateError(unavailableReason ?? '身份或服务已改变，请重新开始搜索。');
  }

  void _runtimeEvent(RuntimeEvent event) {
    if ({
          RuntimeErrorCode.accessRequired,
          RuntimeErrorCode.accessDenied,
        }.contains(event.code) &&
        !catalog.accessPaused) {
      catalog._onRuntimeEvent(event);
    }
    if (event.containerWide ||
        {
          RuntimeErrorCode.accessRequired,
          RuntimeErrorCode.accessDenied,
        }.contains(event.code)) {
      _retire('运行容器或访问身份已改变，请关闭后重新开始搜索。');
    }
  }

  void _changed() {
    if (!catalog._closed &&
        identical(catalog._confirmedBusinessClient, client) &&
        {ServiceStatus.ready, ServiceStatus.failed}.contains(catalog.status)) {
      for (final job in _jobs.toList()) {
        if (!catalog._allowsBuild(
          job.target.build,
          sha256: job.target.bundleSha256,
        )) {
          unawaited(
            job.cancel().catchError((Object failure) {
              _cleanupError(failure);
            }),
          );
        }
      }
    } else {
      _retire('身份或服务已改变，请关闭后重新开始搜索。');
    }
  }

  void _retire(String reason) {
    if (_retired) return;
    _retired = true;
    _reason = reason;
    _notify();
    unawaited(
      stop().catchError((Object failure) {
        _cleanupError(failure);
      }),
    );
  }

  void _cleanupError(Object failure) {
    _cleanupFailure = '搜索资源尚未确认关闭，请重试清理。';
    if (!catalog._closed) {
      catalog.error = _cleanupFailure;
      catalog._notify();
    }
    _notify();
  }

  bool _current(_SearchJob job) =>
      available &&
      !job.isCancelled &&
      catalog._allowsBuild(job.target.build, sha256: job.target.bundleSha256);

  @override
  Future<List<SourceSearchTarget>> loadTargets() async {
    _check();
    if (_jobs.isNotEmpty) throw StateError('请先停止当前搜索再刷新漫画源。');
    await catalog.refreshInstallations();
    _check();
    await catalog.refreshCatalog(shouldContinue: () => available);
    _check();
    final result = <SourceSearchTarget>[];
    for (final build in catalog.builds) {
      final installed = catalog.installedExtension(build.packageName);
      if (installed == null ||
          !catalog._allowsBuild(build, sha256: installed.bundleSha256) ||
          !catalog.isNetworkRegistered(build, sha256: installed.bundleSha256)) {
        continue;
      }
      for (final source in build.sources) {
        result.add(
          SourceSearchTarget(
            build: build,
            source: source,
            bundleSha256: installed.bundleSha256,
          ),
        );
      }
    }
    _targets
      ..clear()
      ..addEntries(result.map((value) => MapEntry(value.key, value)));
    return List.unmodifiable(result);
  }

  Future<void> _claim() async {
    _check();
    final claiming = _claiming;
    if (claiming != null) return claiming;
    if (identical(catalog._searchOwner, this)) return;
    return _claiming ??= _claimSlots().whenComplete(() {
      _claiming = null;
    });
  }

  Future<void> _claimSlots() async {
    _check();
    if (catalog._searchOwner != null ||
        catalog.busy ||
        catalog._openedChapters.isNotEmpty ||
        catalog._progressClosing != null) {
      throw StateError('请先退出阅读并等待当前操作和资源关闭，再开始跨源搜索。');
    }
    catalog._searchOwner = this;
    catalog._notify();
    try {
      final current = catalog.session;
      if (current != null) {
        await catalog.runtime.closeBuild(
          buildId: current.buildId,
          generation: current.generation,
        );
        if (catalog.session?.generation == current.generation) {
          catalog._dropSession();
        }
      }
      _check();
      if (_free.isEmpty) _free.addAll([catalog.runtime, secondary]);
      catalog._notify();
    } catch (_) {
      if (catalog.session != null && identical(catalog._searchOwner, this)) {
        _dirty[catalog.runtime] = catalog.session;
        _cleanupError(StateError('前台运行槽尚未关闭。'));
      } else if (identical(catalog._searchOwner, this)) {
        catalog._searchOwner = null;
      }
      catalog._notify();
      rethrow;
    }
  }

  @override
  SourceSearchTask search(
    SourceSearchTarget target,
    String query, {
    int page = 1,
    void Function()? onStarted,
  }) {
    _check();
    final canonical = _targets[target.key];
    if (canonical == null ||
        query.trim().isEmpty ||
        query.length > 500 ||
        page < 1 ||
        page > 10000 ||
        _jobs.length >= 32) {
      throw const FormatException('请选择当前已确认漫画源，输入 1–500 字的搜索词；最多同时搜索 32 个源。');
    }
    if (_stopping != null) throw StateError('上一轮搜索资源正在关闭。');
    final job = _SearchJob(this, canonical, query, page, onStarted);
    // Callers attach to result synchronously; this observer handles cancellation
    // during teardown even when the owning widget has already been disposed.
    unawaited(
      job.result.then<void>(
        (_) {},
        onError: (Object failure, StackTrace stack) {},
      ),
    );
    _jobs.add(job);
    final key = jsonEncode([
      client.identity.key,
      target.build.catalogUrl,
      target.build.repoId,
      target.build.packageName,
    ]);
    final package = _packages.putIfAbsent(key, () => _SearchPackage(key));
    package.jobs.add(job);
    job.package = package;
    package.running ??= _runPackage(package);
    return job;
  }

  Future<void> _runPackage(_SearchPackage package) async {
    try {
      await _pool.withResource(() async {
        if (package.jobs.every((job) => job.isCancelled) || !available) {
          _cancelPending(package);
          return;
        }
        await _claim();
        if (package.jobs.every((job) => job.isCancelled) || !available) {
          _cancelPending(package);
          return;
        }
        final runtime = _free.removeAt(0);
        package.runtime = runtime;
        try {
          while (package.jobs.isNotEmpty) {
            final job = package.jobs.removeAt(0);
            package.active = job;
            try {
              if (!_current(job)) {
                throw const RuntimeException(
                  RuntimeErrorCode.cancelled,
                  '搜索已取消或安装选择已改变。',
                );
              }
              await _runJob(package, job);
            } catch (failure, stack) {
              job.fail(failure, stack);
              if (job.isCancelled ||
                  failure is RuntimeException &&
                      {
                        RuntimeErrorCode.runtimeLost,
                        RuntimeErrorCode.timeout,
                        RuntimeErrorCode.cancelled,
                      }.contains(failure.code)) {
                await _closePackage(package);
              }
            } finally {
              job.finish();
              _jobs.remove(job);
              package.active = null;
            }
          }
        } finally {
          await _closePackage(package);
          package.runtime = null;
          _free.add(runtime);
        }
      });
    } catch (failure, stack) {
      if (package.runtime != null) {
        _dirty[package.runtime!] = package.session;
        _cleanupError(failure);
      }
      for (final job in package.jobs) {
        job.fail(failure, stack);
        job.finish();
        _jobs.remove(job);
      }
      package.jobs.clear();
    } finally {
      package.running = null;
      if (package.jobs.isNotEmpty &&
          available &&
          package.jobs.any((job) => !job.isCancelled)) {
        package.running = _runPackage(package);
      } else {
        _cancelPending(package);
        _packages.remove(package.key);
        if (_packages.isEmpty && _dirty.isEmpty) _release();
      }
    }
  }

  void _cancelPending(_SearchPackage package) {
    for (final job in package.jobs) {
      job.fail(
        const RuntimeException(RuntimeErrorCode.cancelled, '搜索已取消或会话已失效。'),
      );
      job.finish();
      _jobs.remove(job);
    }
    package.jobs.clear();
  }

  Future<void> _runJob(_SearchPackage package, _SearchJob job) async {
    final target = job.target;
    job.onStarted?.call();
    await catalog.refreshInstallations();
    if (!_current(job)) {
      throw const RuntimeException(
        RuntimeErrorCode.cancelled,
        '搜索已取消或安装选择已改变。',
      );
    }
    final build = await catalog.resolveInstalledBuild(
      target.build.packageName,
      requested: target.build,
      shouldContinue: () => _current(job),
    );
    if (!_current(job)) {
      throw const RuntimeException(RuntimeErrorCode.cancelled, '搜索已取消。');
    }
    final selected = catalog.installedExtension(build.packageName);
    if (selected?.bundleSha256 != target.bundleSha256) {
      throw const FormatException('账户所选产物已改变，请重新选择漫画源。');
    }
    final preferences = catalog.sourcePreferences;
    if (preferences == null ||
        preferences.hasPendingPackage(
          build.packageName,
          catalog: build.catalog,
        ) ||
        catalog._preferenceRecoveries.keys.any(
          (key) =>
              key.$1 == build.catalogUrl &&
              key.$2 == build.repoId &&
              key.$3 == build.packageName,
        )) {
      throw const FormatException('这个扩展的设置尚未确认，请先在普通浏览中处理设置。');
    }
    final runtime = package.runtime!;
    var session = package.session;
    if (session == null) {
      final prepared = await catalog._createSourceDescriptor(
        build,
        preferences,
        shouldContinue: () => _current(job),
        cancelled: job.cancelled.future,
      );
      if (prepared == null || !_current(job)) {
        throw const RuntimeException(RuntimeErrorCode.cancelled, '搜索已取消。');
      }
      if (prepared.descriptor.sha256 != target.bundleSha256) {
        throw const FormatException('产物与账户选择不匹配。');
      }
      job.opening = true;
      catalog._runtimeNeedsRebuild = true;
      try {
        session = await runtime.open(prepared.descriptor);
        package.session = session;
      } finally {
        job.opening = false;
      }
    } else {
      await catalog.refreshNetworkPolicies(
        build.catalog,
        shouldContinue: () => _current(job),
      );
      if (!catalog.isNetworkRegistered(build, sha256: target.bundleSha256)) {
        throw const FormatException('此构建尚未登记漫画源网络权限。');
      }
    }
    if (!_current(job)) {
      throw const RuntimeException(RuntimeErrorCode.cancelled, '搜索已取消。');
    }
    if (!session.sources.any((source) => source.id == target.source.id)) {
      throw const FormatException('当前运行时不包含原漫画源。');
    }
    final requestId = 'search-$id-${++_requestSequence}';
    job.requestId = requestId;
    final result = await runtime.invoke(
      SourceRequest(
        packageId: build.packageName,
        call: wire.SourceCall(
          requestId: requestId,
          generation: session.generation,
          sourceId: target.source.id,
          timeoutMs: 30000,
          search: wire.SearchRequest(page: job.page, query: job.query),
        ),
      ),
    );
    job.requestId = null;
    await catalog.refreshInstallations();
    if (!_current(job)) {
      throw const RuntimeException(RuntimeErrorCode.cancelled, '搜索结果已失效。');
    }
    if (!result.hasMangaPage() || result.mangaPage.mangas.length > 200) {
      throw const FormatException('漫画源返回了无效或超过 200 项的结果页。');
    }
    job._result.complete(
      SourceSearchPage(
        mangas: result.mangaPage.mangas.map(MangaEntry.new).toList(),
        hasNextPage: result.mangaPage.hasNextPage,
      ),
    );
  }

  Future<void> _closePackage(_SearchPackage package) =>
      package.closing ??= _closePackageSlot(package).whenComplete(() {
        package.closing = null;
      });

  Future<void> _closePackageSlot(_SearchPackage package) async {
    // Cancel may already be resetting this generation. Serialize cleanup so a
    // second reset cannot invalidate the first physical shutdown ACK.
    try {
      await package.active?.cancelling;
    } catch (_) {
      // A failed cancellation reset is tracked in _dirty and retried below.
    }
    final runtime = package.runtime;
    final session = package.session;
    if (runtime == null) return;
    if (_dirty.containsKey(runtime)) {
      await runtime.rebuildHost();
      _dirty.remove(runtime);
      package.session = null;
      return;
    }
    if (session == null) return;
    try {
      await runtime.closeBuild(
        buildId: session.buildId,
        generation: session.generation,
      );
    } catch (_) {
      // Search exclusively owns this slot; a reset ACK is a safe physical
      // fallback for cleanup, never a replay of the Source operation.
      await runtime.rebuildHost();
    }
    package.session = null;
  }

  void _release() {
    if (identical(catalog._searchOwner, this)) {
      catalog._searchOwner = null;
      catalog._notify();
    }
    _free.clear();
  }

  @override
  Future<void> stop() => _stopping ??= _stop().whenComplete(() {
    _stopping = null;
  });
  Future<void> _stop() async {
    final jobs = _jobs.toList();
    await Future.wait(
      jobs.map((job) async {
        try {
          await job.cancel();
          return null;
        } catch (failure) {
          return failure;
        }
      }),
    );
    await Future.wait(
      _packages.values
          .map((package) => package.running)
          .whereType<Future<void>>()
          .toList(),
    );
    for (final runtime in _dirty.keys.toList()) {
      await runtime.rebuildHost();
      _dirty.remove(runtime);
      if (identical(runtime, catalog.runtime)) catalog._dropSession();
    }
    _cleanupFailure = null;
    _release();
    _notify();
  }

  @override
  Future<
    ({MangaEntry manga, List<ChapterEntry> chapters, CatalogSourceRef source})?
  >
  openResult(
    SourceSearchTarget target,
    MangaEntry manga, {
    bool Function()? shouldContinue,
  }) async {
    _check();
    await stop();
    _check();
    bool current() => available && shouldContinue?.call() != false;
    if (!current()) return null;
    final selected = await catalog.resolveInstalledBuild(
      target.build.packageName,
      requested: target.build,
      shouldContinue: current,
    );
    if (!current()) return null;
    if (catalog.installedExtension(selected.packageName)?.bundleSha256 !=
        target.bundleSha256) {
      throw const FormatException('账户所选产物已改变，请重新搜索。');
    }
    final opened = await catalog.openSelectedSource(
      packageName: selected.packageName,
      requested: target.build,
      sourceId: target.source.id,
      shouldContinue: current,
    );
    if (opened == null || !current()) return null;
    if (catalog.activeBuild?.catalog != target.build.catalog ||
        catalog.activeBuild?.id != target.build.id ||
        catalog._activeBundleSha256 != target.bundleSha256) {
      throw const FormatException('账户所选来源或构建已改变，请重新搜索。');
    }
    final result = await catalog.details(manga, shouldContinue: current);
    return current() ? result : null;
  }

  @override
  Future<void> close() => _closing ??= _close().whenComplete(() {
    _closing = null;
  });
  Future<void> _close() async {
    _retired = true;
    _reason ??= '搜索页面已关闭。';
    await stop();
    if (_closed) return;
    _closed = true;
    catalog.removeListener(_changed);
    catalog._searchScopes.remove(this);
    await Future.wait(_events.map((subscription) => subscription.cancel()));
    await _pool.close();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    catalog.removeListener(_changed);
    catalog._searchScopes.remove(this);
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}
