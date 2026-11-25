import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/business_state_client.dart';
import '../../data/device_source_preferences.dart';
import '../../data/source_preferences_repository.dart';
import '../../data/source_preferences_validation.dart';
import '../browse/catalog_controller.dart';
import 'source_error_details.dart';

enum SourcePreferencesActivity { reading, editing, saving, readingConfirmed }

/// Edits invoke the original Source once. Only the resulting immutable business
/// command can be retried; an unknown runtime result always requires reopening.
final class SourcePreferencesController extends ChangeNotifier {
  SourcePreferencesController({
    required this.catalog,
    required this.target,
    required this.repository,
    required this.isCurrent,
  }) {
    if (!identical(catalog.sourcePreferences, repository) ||
        catalog.accessPaused) {
      _retire();
    }
    catalog.addListener(_catalogChanged);
  }
  final CatalogController catalog;
  final SourcePreferencesTarget target;
  final bool Function() isCurrent;
  final SourcePreferencesRepository repository;
  wire.PreferenceSnapshot? snapshot;
  wire.SourcePreferences? confirmed;
  String? error;
  String? errorDetails;
  String? message;
  String? _requestId;
  SourcePreferencesActivity? activity;
  bool get busy => activity != null;
  bool _disposed = false;
  bool _retired = false;
  bool needsRecovery = false;
  CatalogSourceRef? _reference;
  String? _worker;

  void _retire() {
    _retired = true;
    snapshot = null;
    confirmed = null;
    activity = null;
    needsRecovery = false;
    message = null;
    errorDetails = null;
    error = '身份或服务已改变，请关闭后重新打开漫画源设置。';
  }

  void _catalogChanged() {
    if (_disposed) return;
    if (!identical(catalog.sourcePreferences, repository) ||
        catalog.accessPaused) {
      _retire();
    }
    notifyListeners();
  }

  bool get available =>
      !_disposed &&
      !_retired &&
      !catalog.accessPaused &&
      isCurrent() &&
      identical(catalog.sourcePreferences, repository);
  SourcePreferencesDraft? get pending => repository.pending(
    target.build.packageName,
    target.source.id,
    catalog: target.build.catalog,
  );
  bool get canEdit =>
      available &&
      !busy &&
      !catalog.busy &&
      !needsRecovery &&
      pending == null &&
      snapshot != null &&
      catalog.isCurrentPreferencesTarget(target) &&
      !catalog.sourcePreferencesBlocked &&
      _reference != null &&
      catalog.isCurrentSource(_reference!) &&
      catalog.session?.workerInstanceId == _worker;

  bool _sameBaseline(wire.SourcePreferences a, wire.SourcePreferences b) =>
      a.revision == b.revision && samePreferenceEntries(a.entries, b.entries);

  Future<bool> load({bool reopen = false}) => _perform(
    pending?.acknowledged == true
        ? SourcePreferencesActivity.readingConfirmed
        : SourcePreferencesActivity.reading,
    () async {
      final latest = await repository.load(
        target.build.packageName,
        catalog: target.build.catalog,
      );
      if (!available) return false;
      final current = latest.source(target.source.id);
      if (pending case final draft?) {
        confirmed = current;
        needsRecovery = true;
        snapshot = null;
        message = draft.acknowledged
            ? '原保存已确认。请读取最新设置以重新打开漫画源。'
            : '原设置操作尚未确认，可重试原保存或读取服务端状态。';
        return true;
      }
      final loaded = catalog.loadedSourcePreferences?.source(target.source.id);
      if (reopen ||
          loaded == null ||
          !_sameBaseline(loaded, current) ||
          !catalog.isCurrentPreferencesTarget(target) ||
          catalog.sourcePreferencesBlocked) {
        if (!await catalog.reopenSourcePreferences(
              target,
              shouldContinue: () => available,
            ) ||
            !available) {
          if (available) {
            error = catalog.error ?? '未能打开漫画源设置，请重试。';
            errorDetails = catalog.errorDetails;
          }
          return false;
        }
      }
      confirmed = catalog.loadedSourcePreferences!.source(target.source.id);
      final value = await catalog.describeSourcePreferences(
        target,
        shouldContinue: () => available,
        onRequest: (id) => _requestId = id,
      );
      _requestId = null;
      if (!available) return false;
      if (value == null) {
        error = catalog.error ?? '未能读取漫画源设置，可明确重试；默认浏览仍可继续。';
        errorDetails = catalog.errorDetails;
        snapshot = null;
        return false;
      }
      snapshot = value;
      _reference = catalog.sourceReference;
      _worker = catalog.session!.workerInstanceId;
      needsRecovery = false;
      return true;
    },
  );

  Future<bool> change(List<int> path, wire.PreferenceValue value) {
    if (!canEdit) return Future.value(false);
    return _edit(
      wire.PreferenceEditRequest(
        snapshotId: snapshot!.snapshotId,
        path: path,
        change: value,
      ),
    );
  }

  Future<bool> click(List<int> path) {
    if (!canEdit) return Future.value(false);
    return _edit(
      wire.PreferenceEditRequest(
        snapshotId: snapshot!.snapshotId,
        path: path,
        click: wire.Empty(),
      ),
    );
  }

  Future<bool> _edit(wire.PreferenceEditRequest request) {
    if (!canEdit) return Future.value(false);
    final baseline = confirmed!;
    final before = snapshot!;
    return _perform(SourcePreferencesActivity.editing, () async {
      final result = await catalog.editSourcePreference(
        target,
        request,
        shouldContinue: () => available,
        onRequest: (id) => _requestId = id,
      );
      _requestId = null;
      if (!available) return false;
      needsRecovery = true;
      snapshot = null;
      if (result == null) {
        error = '设置操作的运行结果未知，请读取服务端状态后重新打开；不会自动重跑原操作。';
        errorDetails = catalog.errorDetails;
        return false;
      }
      final localChanged = !samePreferenceEntries(
        before.sessionValues,
        result.snapshot.sessionValues,
      );
      final accountChanged = !samePreferenceEntries(
        result.snapshot.syncValues,
        baseline.entries,
      );
      if (localChanged) {
        _setActivity(SourcePreferencesActivity.saving);
        try {
          await DeviceSourcePreferences(repository.identity).save(
            catalog: target.build.catalog,
            packageName: target.build.packageName,
            sourceId: target.source.id,
            entries: result.snapshot.sessionValues,
          );
        } on FormatException catch (failure) {
          if (available) {
            error = failure.message;
            errorDetails = sourceErrorDetails(failure, operation: '保存本机漫画源设置');
          }
          return false;
        }
        if (!available) return false;
      }
      if (catalog.allowsAccountPreferences(target.build) && accountChanged) {
        _setActivity(SourcePreferencesActivity.saving);
        await repository.save(
          catalog: target.build.catalog,
          packageName: target.build.packageName,
          sourceId: target.source.id,
          basedOnRevision: baseline.revision,
          entries: result.snapshot.syncValues,
          onAcknowledged: () =>
              _setActivity(SourcePreferencesActivity.readingConfirmed),
        );
        if (!available) return false;
      }
      if (!result.accepted && request.hasClick()) {
        message = result.clickHandled ? '操作已处理。' : '漫画源未处理此操作；实际设置已重新读取。';
      } else if (!result.accepted) {
        if (localChanged ||
            !samePreferenceEntries(
              before.syncValues,
              result.snapshot.syncValues,
            )) {
          message = '漫画源已更新设置；请核对实际值。';
        } else {
          error = '漫画源未接受输入；设置未更改。';
        }
      }
      return _reopenAndDescribe();
    });
  }

  Future<bool> retry() {
    if (!available || busy || pending?.retryable != true) {
      return Future.value(false);
    }
    return _perform(
      pending?.acknowledged == true
          ? SourcePreferencesActivity.readingConfirmed
          : SourcePreferencesActivity.saving,
      () async {
        await repository.retry(
          target.build.packageName,
          target.source.id,
          catalog: target.build.catalog,
          onAcknowledged: () =>
              _setActivity(SourcePreferencesActivity.readingConfirmed),
        );
        if (!available) return false;
        return _reopenAndDescribe();
      },
    );
  }

  Future<bool> recover() {
    if (!available || busy) return Future.value(false);
    return _perform(SourcePreferencesActivity.reading, () async {
      await repository.discard(
        target.build.packageName,
        target.source.id,
        catalog: target.build.catalog,
      );
      if (!available) return false;
      message = '已读取服务端当前状态；不会撤销可能已成功的原写入。';
      return _reopenAndDescribe();
    });
  }

  Future<bool> _reopenAndDescribe() async {
    if (!await catalog.reopenSourcePreferences(
          target,
          shouldContinue: () => available,
        ) ||
        !available) {
      if (available) {
        error = catalog.error ?? '设置已处理，但漫画源尚未重新打开，请重试读取。';
        errorDetails = catalog.errorDetails;
      }
      return false;
    }
    confirmed = catalog.loadedSourcePreferences!.source(target.source.id);
    final value = await catalog.describeSourcePreferences(
      target,
      shouldContinue: () => available,
      onRequest: (id) => _requestId = id,
    );
    _requestId = null;
    if (!available) return false;
    if (value == null) {
      error = catalog.error ?? '漫画源已重新打开，设置描述未能读取。';
      errorDetails = catalog.errorDetails;
      return false;
    }
    snapshot = value;
    _reference = catalog.sourceReference;
    _worker = catalog.session!.workerInstanceId;
    needsRecovery = false;
    return true;
  }

  void _setActivity(SourcePreferencesActivity phase) {
    if (!available || activity == phase) return;
    activity = phase;
    notifyListeners();
  }

  Future<bool> _perform(
    SourcePreferencesActivity phase,
    Future<bool> Function() action,
  ) async {
    if (!available || busy || catalog.busy) return false;
    activity = phase;
    error = null;
    errorDetails = null;
    message = null;
    notifyListeners();
    try {
      return await action();
    } catch (failure) {
      if (available) {
        final draft = pending;
        needsRecovery = catalog.sourcePreferencesBlocked || draft != null;
        error = failure is BusinessStateException && failure.conflict
            ? '设置已在另一端修改。请读取服务端状态并重新打开，再确认新编辑。'
            : draft?.acknowledged == true && draft?.retryable == true
            ? '原保存已确认，读取最新设置未完成。请重试读取。'
            : draft?.retryable == false
            ? '原保存请求已被拒绝。请读取服务端状态并重新打开。'
            : draft != null
            ? '设置尚未确认；重试只发送原保存请求，不会重跑漫画源操作。'
            : '设置处理未完成，请读取服务端状态后重新打开。';
      }
      return false;
    } finally {
      _requestId = null;
      if (!_disposed) {
        activity = null;
        notifyListeners();
      }
    }
  }

  void cancelActiveRequest() {
    final id = _requestId;
    _requestId = null;
    if (id != null) unawaited(catalog.cancelSourcePreferenceRequest(id));
  }

  @override
  void dispose() {
    _disposed = true;
    catalog.removeListener(_catalogChanged);
    final id = _requestId;
    _requestId = null;
    if (id != null) {
      unawaited(
        Future<void>.microtask(() => catalog.cancelSourcePreferenceRequest(id)),
      );
    }
    super.dispose();
  }
}
