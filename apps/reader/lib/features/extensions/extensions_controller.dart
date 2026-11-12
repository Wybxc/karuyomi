import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';
import 'package:uuid/uuid.dart';

import '../../data/business_state_validation.dart';
import '../../data/settings_repository.dart';
import '../browse/catalog_controller.dart';
import '../settings/settings_controller.dart';

/// Account intent reuses the identity-bound global settings queue. Artifacts
/// remain disposable local copies; preparation never opens a Source.
enum ExtensionActivity { reading, preparing, saving, cleaning }

final class ExtensionsController extends ChangeNotifier {
  ExtensionsController({
    required this.catalog,
    required this.repository,
    required this.isCurrent,
  }) {
    if (!identical(catalog.settings, repository) || catalog.accessPaused) {
      _retire();
    }
    settings = SettingsController(
      repository: repository,
      isCurrent: () => available,
    );
    settings.addListener(_changed);
    catalog.addListener(_changed);
  }

  final _cancelled = Completer<void>();
  final CatalogController catalog;
  final SettingsRepository repository;
  final bool Function() isCurrent;
  late final SettingsController settings;
  wire.ExtensionCacheState? cache;
  String? error;
  String? message;
  String? _preparationId;
  ExtensionActivity? activity;
  RuntimeErrorCode? operationFailure;
  String? cleanupSha256;
  String? cleanupError;
  bool _busy = false;
  bool _disposed = false;
  bool _retired = false;

  bool get available =>
      !_disposed &&
      !_retired &&
      isCurrent() &&
      identical(catalog.settings, repository) &&
      {ServiceStatus.ready, ServiceStatus.failed}.contains(catalog.status);
  bool get busy => _busy || settings.busy;
  bool get canEdit => available && !busy && !catalog.busy && settings.canEdit;
  bool get preparing => _preparationId != null;
  List<wire.InstalledExtension> get installed =>
      settings.snapshot?.global.installedExtensions ?? const [];

  void _retire() {
    _retired = true;
    error = '身份或服务已改变，请关闭后重新打开扩展管理。';
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void _changed() {
    if (!identical(catalog.settings, repository) || catalog.accessPaused) {
      _retire();
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh({bool catalogToo = false}) async {
    if (!available || busy) return;
    await _run(() async {
      final refreshed = await settings.refresh();
      if (!available) return;
      if (refreshed) {
        await catalog.applyConfirmedInstallations(settings.snapshot!);
      }
      if (!available) return;
      if (catalogToo || catalog.repositories.length > 1) {
        await catalog.refreshCatalog(
          shouldContinue: () => available,
          cancelled: _cancelled.future,
        );
      }
      if (!available) return;
      cache = await catalog.runtime.extensionCache();
      if (available) message = catalogToo ? '已检查当前目录，账户构建选择未改变。' : null;
    });
  }

  Future<void> install(
    CatalogBuild build, {
    wire.InstalledExtension? replacing,
  }) async {
    final initial = settings.snapshot;
    if (!canEdit || initial == null) return;
    final values = initial.global.deepCopy();
    final previous = values.installedExtensions
        .where((value) => value.packageName == build.packageName)
        .firstOrNull;
    if (previous == null &&
        values.installedExtensions.length >= businessInstalledExtensionLimit) {
      error = '最多安装 $businessInstalledExtensionLimit 个扩展，请先卸载不再使用的扩展。';
      _changed();
      return;
    }
    if (!catalog.isRepositoryRegistered(build.catalog)) {
      error = '仓库尚未确认添加，不能安装。';
      _changed();
      return;
    }
    final crossRepository =
        previous != null &&
        (previous.catalogUrl != build.catalogUrl ||
            previous.repoId != build.repoId);
    if (crossRepository && replacing != previous) {
      error = '同包扩展来自另一个仓库，请明确确认替换；账户选择已变化时需重新确认。';
      _changed();
      return;
    }
    if (previous != null &&
        catalog.sourcePreferences!.hasPendingPackage(
          build.packageName,
          catalog: wire.CatalogReference(
            catalogUrl: previous.catalogUrl,
            repoId: previous.repoId,
          ),
        )) {
      error = '原仓库仍有未确认的漫画源设置，请先处理原请求。';
      _changed();
      return;
    }
    // This first snapshot and CAS stay fixed while the candidate downloads.
    final revision = initial.globalRevision;
    await _run(() async {
      final id = const Uuid().v4();
      _preparationId = id;
      activity = ExtensionActivity.preparing;
      _changed();
      wire.PreparedBuild prepared;
      try {
        prepared = await catalog.runtime.prepareBuild(
          preparationId: id,
          catalog: build.catalog,
          build: build.toProto(),
        );
      } catch (_) {
        if (_preparationId != id) return;
        rethrow;
      }
      if (!available || _preparationId != id) return;
      _preparationId = null;
      if (!settings.canEdit) {
        throw StateError('另一个全局设置操作尚未确认，请先处理原请求。');
      }
      values.installedExtensions.removeWhere(
        (value) => value.packageName == build.packageName,
      );
      values.installedExtensions.add(
        wire.InstalledExtension(
          catalogUrl: build.catalogUrl,
          repoId: build.repoId,
          packageName: build.packageName,
          buildId: prepared.build.buildId,
          bundleSha256: prepared.bundleSha256,
          enabled: previous?.enabled ?? true,
        ),
      );
      activity = ExtensionActivity.saving;
      _changed();
      final saved = await settings.saveGlobal(values, revision);
      if (!available) return;
      if (saved) await catalog.applyConfirmedInstallations(settings.snapshot!);
      if (!available) return;
      cache = await catalog.runtime.extensionCache();
      if (saved) {
        message = '账户扩展选择已确认，本机产物已准备。';
        if (previous != null &&
            previous.bundleSha256 != prepared.bundleSha256) {
          await _cleanup(previous.bundleSha256);
        }
      }
    });
  }

  Future<RepositoryPreview?> previewRepository(String url, String name) async {
    if (!canEdit || settings.snapshot == null) return null;
    RepositoryPreview? result;
    final baseline = settings.snapshot!;
    await _run(() async {
      final uri = Uri.parse(url.trim());
      if (uri.userInfo.isNotEmpty) {
        throw const FormatException('仓库地址不能包含用户名或密码。');
      }
      final canonical =
          (uri.path.isEmpty || uri.path == '/') &&
              !uri.hasQuery &&
              !uri.hasFragment
          ? '${uri.origin}/extensions/index.json'
          : url.trim();
      validateBusinessCatalogUrl(canonical);
      final document = await catalog.previewRepository(
        canonical,
        shouldContinue: () => available,
        cancelled: _cancelled.future,
      );
      if (!available) return;
      final repository = wire.ExtensionRepository(
        catalogUrl: document.catalog.catalogUrl,
        repoId: document.catalog.repoId,
        name: name.trim().isEmpty ? uri.host : name.trim(),
      );
      _validateNewRepository(repository, baseline.global.repositories);
      result = RepositoryPreview(
        repository: repository..freeze(),
        builds: document.builds,
        baseline: baseline,
      );
    });
    return result;
  }

  void _validateNewRepository(
    wire.ExtensionRepository repository,
    Iterable<wire.ExtensionRepository> existing,
  ) {
    if (repository.catalogUrl == catalog.catalogUrl ||
        repository.repoId == catalog.defaultCatalog.repoId) {
      throw const FormatException('默认仓库地址和身份保留，不能添加重复仓库。');
    }
    validateBusinessRepositories([...existing, repository]);
  }

  Future<void> addRepository(RepositoryPreview preview) async {
    if (!canEdit) return;
    final values = preview.baseline.global.deepCopy();
    await _run(() async {
      _validateNewRepository(preview.repository, values.repositories);
      values.repositories.add(preview.repository.deepCopy());
      activity = ExtensionActivity.saving;
      _changed();
      final saved = await settings.saveGlobal(
        values,
        preview.baseline.globalRevision,
      );
      if (!saved || !available) return;
      await catalog.applyConfirmedInstallations(settings.snapshot!);
      if (!available) return;
      await catalog.refreshCatalog(
        shouldContinue: () => available,
        cancelled: _cancelled.future,
      );
      if (available) message = '仓库已由账户确认，安装选择未改变。';
    });
  }

  Future<void> removeRepository(wire.ExtensionRepository repository) async {
    final initial = settings.snapshot;
    if (!canEdit ||
        initial == null ||
        repository.catalogUrl == catalog.catalogUrl ||
        repository.repoId == catalog.defaultCatalog.repoId) {
      return;
    }
    final values = initial.global.deepCopy();
    values.repositories.removeWhere(
      (value) =>
          value.catalogUrl == repository.catalogUrl &&
          value.repoId == repository.repoId,
    );
    await _run(() async {
      activity = ExtensionActivity.saving;
      _changed();
      final saved = await settings.saveGlobal(values, initial.globalRevision);
      if (!saved || !available) return;
      message = '仓库已移除；安装选择、书架和来源数据保留，对应运行槽将关闭。';
      await catalog.applyConfirmedInstallations(settings.snapshot!);
    });
  }

  Future<void> setEnabled(
    wire.InstalledExtension extension,
    bool enabled,
  ) async {
    final initial = settings.snapshot;
    if (!canEdit || initial == null) return;
    final values = initial.global.deepCopy();
    final match = values.installedExtensions
        .where((value) => value.packageName == extension.packageName)
        .firstOrNull;
    if (match == null) return;
    match.enabled = enabled;
    await _run(() async {
      activity = ExtensionActivity.saving;
      _changed();
      if (await settings.saveGlobal(values, initial.globalRevision) &&
          available) {
        await catalog.applyConfirmedInstallations(settings.snapshot!);
        message = enabled ? '账户已确认启用。' : '账户已确认停用。';
      }
    });
  }

  Future<void> uninstall(wire.InstalledExtension extension) async {
    final initial = settings.snapshot;
    if (!canEdit || initial == null) return;
    final values = initial.global.deepCopy();
    final removed = values.installedExtensions
        .where((value) => value.packageName == extension.packageName)
        .firstOrNull;
    if (removed == null) return;
    values.installedExtensions.removeWhere(
      (value) => value.packageName == extension.packageName,
    );
    await _run(() async {
      activity = ExtensionActivity.saving;
      _changed();
      if (!await settings.saveGlobal(values, initial.globalRevision) ||
          !available) {
        return;
      }
      message = '账户已确认卸载；书架、阅读进度和漫画源数据保留。';
      await catalog.applyConfirmedInstallations(settings.snapshot!);
      await _cleanup(removed.bundleSha256);
    });
  }

  Future<void> prepareInstalled(wire.InstalledExtension extension) async {
    if (!available || busy || catalog.busy) return;
    final build = catalog.builds
        .where(
          (build) =>
              build.id == extension.buildId &&
              build.packageName == extension.packageName &&
              build.repoId == extension.repoId &&
              build.catalogUrl == extension.catalogUrl,
        )
        .firstOrNull;
    if (build == null || !catalog.isRepositoryRegistered(build.catalog)) {
      error = '所选构建已下架或仓库尚未接入，请检查并手动更新。';
      _changed();
      return;
    }
    await _run(() async {
      final id = const Uuid().v4();
      _preparationId = id;
      activity = ExtensionActivity.preparing;
      _changed();
      wire.PreparedBuild prepared;
      try {
        prepared = await catalog.runtime.prepareBuild(
          preparationId: id,
          catalog: build.catalog,
          build: build.toProto(),
        );
      } catch (_) {
        if (_preparationId != id) return;
        rethrow;
      }
      if (!available || _preparationId != id) return;
      _preparationId = null;
      if (prepared.bundleSha256 != extension.bundleSha256) {
        throw const FormatException('产物与账户所选构建不匹配。');
      }
      cache = await catalog.runtime.extensionCache();
      if (available) message = '本机产物已准备，账户选择未改变。';
    });
  }

  Future<void> cancelPreparation() async {
    final id = _preparationId;
    if (id == null || !available) return;
    _preparationId = null;
    _changed();
    try {
      await catalog.runtime.cancelPreparation(id);
      if (available) message = '已取消准备；账户设置未更改。';
    } catch (_) {
      if (available) error = '取消尚未确认，请重新读取本机缓存。';
    }
    _changed();
  }

  Future<void> forget(String sha256) async {
    if (!available || busy || catalog.busy) return;
    await _run(() => _cleanup(sha256));
  }

  Future<void> _cleanup(String sha256) async {
    activity = ExtensionActivity.cleaning;
    cleanupSha256 = sha256;
    cleanupError = null;
    _changed();
    try {
      await catalog.retireUnavailableExtension();
      if (!available) return;
      await catalog.closeManagedBuild(sha256);
      if (!available) return;
      await catalog.runtime.forgetExtensionArtifact(sha256);
      if (!available) return;
      cache = await catalog.runtime.extensionCache();
      cleanupSha256 = null;
    } catch (_) {
      cleanupError = '账户已确认；本机副本清理未完成，请重试清理。';
      rethrow;
    }
  }

  Future<void> retryCleanup() async {
    if (!available || busy || catalog.busy) return;
    await _run(() async {
      final sha256 = cleanupSha256;
      if (sha256 != null) {
        await _cleanup(sha256);
      } else {
        await catalog.retireUnavailableExtension();
        if (available) cache = await catalog.runtime.extensionCache();
      }
    });
  }

  Future<void> rebuildForCleanup() async {
    if (!available || busy || !catalog.canRebuildUnavailableExtension) return;
    await _run(() async {
      await catalog.rebuildUnavailableExtension();
      if (!available) return;
      cache = await catalog.runtime.extensionCache();
      message = '运行时已重建；可重新清理本机副本。';
    });
  }

  Future<void> retry() async {
    if (!available || busy) return;
    await _run(() async {
      if (await settings.retry() && available) {
        await catalog.applyConfirmedInstallations(settings.snapshot!);
        cache = await catalog.runtime.extensionCache();
        message = '原设置操作已由服务端确认；请检查本机缓存状态。';
      }
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    _busy = true;
    activity = ExtensionActivity.reading;
    operationFailure = null;
    error = null;
    message = null;
    _changed();
    try {
      await operation();
    } catch (failure) {
      if (available) {
        operationFailure = failure is RuntimeException ? failure.code : null;
        error = switch (failure) {
          RuntimeException(code: RuntimeErrorCode.limitExceeded) =>
            '本机存储达到限额，请释放空间后重试。',
          RuntimeException(code: RuntimeErrorCode.storageBusy) =>
            '扩展仍在使用，请关闭相关阅读后重试。',
          RuntimeException(code: RuntimeErrorCode.unsupportedCapability) =>
            '当前应用不支持此扩展材料，请更新应用。',
          RuntimeException(code: RuntimeErrorCode.integrityError) =>
            '扩展下载校验失败，请检查更新后重试。',
          FormatException(:final message) => message,
          StateError(:final message) => message.toString(),
          _ => '操作未完成，请重试。',
        };
      }
    } finally {
      _preparationId = null;
      if (!_disposed) {
        _busy = false;
        activity = null;
        _changed();
      }
    }
  }

  @override
  void dispose() {
    if (!_cancelled.isCompleted) _cancelled.complete();
    final id = _preparationId;
    _preparationId = null;
    _disposed = true;
    if (id != null) {
      unawaited(
        catalog.runtime.cancelPreparation(id).catchError((Object _) {}),
      );
    }
    settings.removeListener(_changed);
    settings.dispose();
    catalog.removeListener(_changed);
    super.dispose();
  }
}

final class RepositoryPreview {
  const RepositoryPreview({
    required this.repository,
    required this.builds,
    required this.baseline,
  });
  final wire.ExtensionRepository repository;
  final List<CatalogBuild> builds;
  final SettingsSnapshot baseline;
}
