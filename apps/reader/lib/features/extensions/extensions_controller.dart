import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:uuid/uuid.dart';

import '../../data/business_state_validation.dart';
import '../../data/settings_repository.dart';
import '../browse/catalog_controller.dart';
import '../settings/settings_controller.dart';

/// Account intent reuses the identity-bound global settings queue. Artifacts
/// remain disposable local copies; preparation never opens a Source.
final class ExtensionsController extends ChangeNotifier {
  ExtensionsController({required this.catalog, required this.isCurrent})
    : repository = catalog.settings! {
    settings = SettingsController(
      repository: repository,
      isCurrent: () => available,
    );
    settings.addListener(_changed);
    catalog.addListener(_changed);
  }

  final CatalogController catalog;
  final SettingsRepository repository;
  final bool Function() isCurrent;
  late final SettingsController settings;
  wire.ExtensionCacheState? cache;
  String? error;
  String? message;
  String? _preparationId;
  bool _busy = false;
  bool _disposed = false;

  bool get available =>
      !_disposed &&
      isCurrent() &&
      identical(catalog.settings, repository) &&
      catalog.status == ServiceStatus.ready;
  bool get busy => _busy || settings.busy;
  bool get canEdit => available && !busy && !catalog.busy && settings.canEdit;
  bool get preparing => _preparationId != null;
  List<wire.InstalledExtension> get installed =>
      settings.snapshot?.global.installedExtensions ?? const [];

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh({bool catalogToo = false}) async {
    if (!available || busy) return;
    await _run(() async {
      if (catalogToo) await catalog.refreshCatalog();
      if (!available) return;
      final refreshed = await settings.refresh();
      if (!available) return;
      if (refreshed) {
        await catalog.applyConfirmedInstallations(settings.snapshot!);
      }
      if (!available) return;
      cache = await catalog.runtime.extensionCache();
      if (available) message = catalogToo ? '已检查当前目录，账户构建选择未改变。' : null;
    });
  }

  Future<void> install(CatalogBuild build) async {
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
    // This first snapshot and CAS stay fixed while the candidate downloads.
    final revision = initial.globalRevision;
    await _run(() async {
      final id = const Uuid().v4();
      _preparationId = id;
      _changed();
      wire.PreparedBuild prepared;
      try {
        prepared = await catalog.runtime.prepareBuild(
          preparationId: id,
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
          catalogUrl: catalog.catalogUrl,
          repoId: build.repoId,
          packageName: build.packageName,
          buildId: prepared.build.buildId,
          bundleSha256: prepared.bundleSha256,
          enabled: previous?.enabled ?? true,
        ),
      );
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
              build.repoId == extension.repoId,
        )
        .firstOrNull;
    if (extension.catalogUrl != catalog.catalogUrl || build == null) {
      error = '所选构建已下架或仓库尚未接入，请检查并手动更新。';
      _changed();
      return;
    }
    await _run(() async {
      final id = const Uuid().v4();
      _preparationId = id;
      _changed();
      wire.PreparedBuild prepared;
      try {
        prepared = await catalog.runtime.prepareBuild(
          preparationId: id,
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
    await catalog.retireUnavailableExtension();
    if (!available) return;
    await catalog.closeManagedBuild(sha256);
    if (!available) return;
    await catalog.runtime.forgetExtensionArtifact(sha256);
    if (!available) return;
    cache = await catalog.runtime.extensionCache();
  }

  Future<void> retryCleanup() async {
    if (!available || busy || catalog.busy) return;
    await _run(() async {
      await catalog.retireUnavailableExtension();
      if (available) cache = await catalog.runtime.extensionCache();
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
    error = null;
    message = null;
    _changed();
    try {
      await operation();
    } catch (failure) {
      if (available) {
        error = failure is FormatException
            ? failure.message
            : '操作未完成；账户确认和本机清理状态请分别检查。${catalog.extensionCleanupError ?? ''}';
      }
    } finally {
      _preparationId = null;
      if (!_disposed) {
        _busy = false;
        _changed();
      }
    }
  }

  @override
  void dispose() {
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
