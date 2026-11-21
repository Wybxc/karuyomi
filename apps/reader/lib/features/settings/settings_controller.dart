import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/business_state_client.dart';
import '../../data/settings_repository.dart';
import '../../state/account_providers.dart';
import '../browse/catalog_controller.dart';

part 'settings_controller.g.dart';

enum SettingsFailure { conflict, rejected, unknown, confirmedRead }

enum SettingsActivity { reading, saving }

final class const SettingsState({
  final SettingsSnapshot? snapshot,
  final SettingsDraft? pending,
  final wire.SettingsMutation? submitting,
  final wire.SettingsMutation? unsent,
  final bool available = false,
  final SettingsActivity? activity,
  final String? error,
  final SettingsFailure? failure,
}) {
  bool get busy => activity != null;
  bool get _canStart =>
      available && !busy && snapshot != null && pending == null;
  bool get canEdit => _canStart && submitting == null && unsent == null;
  bool get canChange =>
      canEdit || (available && submitting != null && failure == null);
  bool get canRefresh => available && !busy && submitting == null;
  bool get canRetry => available && !busy && pending?.retryable == true;
}

/// One editor per verified catalog identity and global/manga scope. Submitted
/// UUID/CAS drafts remain in BusinessStateClient when this provider is disposed.
@riverpod
class SettingsController extends _$SettingsController {
  Object _generation = Object();
  int _wantedGlobalRevision = -1;
  wire.SettingsMutation? _submitting;
  wire.SettingsMutation? _unsent;
  void Function()? _releaseAutosave;

  @override
  SettingsState build(
    CatalogController catalog,
    SettingsRepository? repository, {
    String? mangaKey,
  }) {
    final account = ref.watch(confirmedAccountProvider(catalog));
    final generation = _generation = Object();
    _submitting = null;
    _unsent = null;
    _releaseAutosave = null;
    final initial = mangaKey == null ? catalog.installationSettings : null;
    final pending = _pending();
    final failure = _rejection(pending);
    _wantedGlobalRevision = initial?.globalRevision ?? -1;
    if (repository == null || !identical(account?.settings, repository)) {
      return SettingsState(pending: _pending());
    }
    final subscription = repository.watchConfirmed().listen((value) {
      if (!_current(generation)) return;
      _wantedGlobalRevision = value.globalRevision > _wantedGlobalRevision
          ? value.globalRevision
          : _wantedGlobalRevision;
      if (mangaKey == null) {
        if (value.globalRevision <= (state.snapshot?.globalRevision ?? -1)) {
          return;
        }
      } else if (value.mangaKey != mangaKey) {
        _refreshInheritance();
        return;
      }
      state = _next(
        snapshot: value,
        activity: state.activity,
        error: state.error,
        failure: state.failure,
      );
    });
    ref.onDispose(() => unawaited(subscription.cancel()));
    if (initial == null) {
      scheduleMicrotask(() {
        if (_current(generation)) unawaited(refresh());
      });
    }
    return SettingsState(
      snapshot: initial,
      pending: _pending(),
      available: true,
      failure: failure,
      error: failure == null ? null : _failureMessage(failure),
    );
  }

  bool _current(Object generation) =>
      ref.mounted &&
      !catalog.closed &&
      {ServiceStatus.ready, ServiceStatus.failed}.contains(catalog.status) &&
      identical(generation, _generation) &&
      repository != null &&
      !catalog.accessPaused &&
      catalog.subject == repository!.identity.subject &&
      identical(catalog.settings, repository);

  SettingsDraft? _pending() => mangaKey == null
      ? repository?.pendingGlobal()
      : repository?.pendingManga(mangaKey!);

  SettingsFailure? _rejection(SettingsDraft? pending) =>
      pending?.retryable == false
      ? pending?.rejectionCode ==
                wire
                    .BusinessStateErrorCode
                    .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT
            ? SettingsFailure.conflict
            : SettingsFailure.rejected
      : null;

  String _failureMessage(SettingsFailure failure) => switch (failure) {
    SettingsFailure.conflict => '设置已在其他设备修改，请重新读取后确认。',
    SettingsFailure.rejected => '设置修改已被服务端拒绝，请重新读取后确认。',
    SettingsFailure.unknown => '设置修改尚未确认，请明确重试原操作。',
    SettingsFailure.confirmedRead => '原设置已确认，读取最新状态未完成，请重试读取。',
  };

  SettingsState _next({
    SettingsSnapshot? snapshot,
    SettingsActivity? activity,
    String? error,
    SettingsFailure? failure,
  }) => SettingsState(
    snapshot: snapshot ?? state.snapshot,
    pending: _pending(),
    submitting: _submitting,
    unsent: _unsent,
    available: _current(_generation),
    activity: activity,
    error: error,
    failure: failure,
  );

  void _refreshInheritance() {
    if (mangaKey != null &&
        state.canRefresh &&
        _submitting == null &&
        _unsent == null &&
        state.pending == null &&
        state.error == null &&
        _wantedGlobalRevision > (state.snapshot?.globalRevision ?? -1)) {
      unawaited(refresh());
    }
  }

  Future<bool> refresh() async {
    if (!_current(_generation) || !state.canRefresh) return false;
    state = _next(activity: SettingsActivity.reading);
    final generation = _generation;
    try {
      final snapshot = mangaKey == null
          ? await repository!.loadGlobal()
          : await repository!.loadManga(mangaKey!);
      if (!_current(generation)) return false;
      if (_pending() == null && _submitting == null) {
        _unsent = null;
        _releaseAutosave?.call();
        _releaseAutosave = null;
      }
      state = _next(snapshot: snapshot);
      return true;
    } catch (_) {
      if (_current(generation)) {
        final pending = _pending();
        final failure =
            pending?.acknowledged == true && pending?.retryable == true
            ? SettingsFailure.confirmedRead
            : _rejection(pending);
        state = _next(
          failure: failure,
          error: failure == null
              ? '未能读取服务端设置；当前阅读仍可继续。'
              : failure == SettingsFailure.confirmedRead
              ? _failureMessage(failure)
              : '未能读取最新设置。${_failureMessage(failure)}',
        );
      }
      return false;
    } finally {
      if (_current(generation)) _refreshInheritance();
    }
  }

  void queueGlobal(wire.GlobalSettingsValues values) =>
      _queue(wire.SettingsMutation(setGlobal: values.deepCopy()));

  void queueOverrides(wire.ReaderSettingsOverride overrides) => _queue(
    wire.SettingsMutation(
      setManga: wire.SetMangaReaderSettings(
        mangaKey: mangaKey!,
        overrides: overrides.deepCopy(),
      ),
    ),
  );

  int? get _scopeRevision => mangaKey == null
      ? state.snapshot?.globalRevision
      : state.snapshot?.mangaRevision;

  void _queue(wire.SettingsMutation edit) {
    if (!_current(_generation) || !state.canChange) return;
    final submitting = _submitting;
    if (submitting == null) {
      edit.expectedRevision = _scopeRevision!;
      _unsent = edit..freeze();
      _releaseAutosave ??= ref.keepAlive().close;
      unawaited(_drainAutosave());
      return;
    }
    edit.expectedRevision = submitting.expectedRevision + 1;
    // If the final selection returns to the in-flight values, that ACK
    // satisfies the editor without another revision.
    final sameValues = edit.hasSetGlobal()
        ? edit.setGlobal == submitting.setGlobal
        : edit.setManga.overrides == submitting.setManga.overrides;
    _unsent = sameValues ? null : (edit..freeze());
    state = _next(activity: state.activity);
  }

  Future<void> _drainAutosave() async {
    final generation = _generation;
    while (_current(generation) && state._canStart && _unsent != null) {
      final edit = _unsent!;
      if (edit.expectedRevision != _scopeRevision) {
        state = _next(
          failure: SettingsFailure.conflict,
          error: _failureMessage(SettingsFailure.conflict),
        );
        break;
      }

      _submitting = edit;
      _unsent = null;
      final saved = await _save(
        (onAcknowledged) => edit.hasSetGlobal()
            ? repository!.setGlobal(
                values: edit.setGlobal,
                basedOnRevision: edit.expectedRevision,
                onAcknowledged: onAcknowledged,
              )
            : repository!.setManga(
                mangaKey: edit.setManga.mangaKey,
                overrides: edit.setManga.overrides,
                basedOnRevision: edit.expectedRevision,
                onAcknowledged: onAcknowledged,
              ),
        automatic: true,
      );
      if (!_current(generation)) return;
      _submitting = null;
      state = _next(error: state.error, failure: state.failure);
      if (!saved) break;
    }
    if (!_current(generation)) return;
    if (_unsent == null) {
      _releaseAutosave?.call();
      _releaseAutosave = null;
    }
    _refreshInheritance();
  }

  Future<bool> saveGlobal(wire.GlobalSettingsValues values, int revision) =>
      _save(
        (onAcknowledged) => repository!.setGlobal(
          values: values,
          basedOnRevision: revision,
          onAcknowledged: onAcknowledged,
        ),
      );

  Future<bool> saveOverrides(
    wire.ReaderSettingsOverride values,
    int revision,
  ) => _save(
    (onAcknowledged) => repository!.setManga(
      mangaKey: mangaKey!,
      overrides: values,
      basedOnRevision: revision,
      onAcknowledged: onAcknowledged,
    ),
  );

  Future<bool> retry() async {
    final generation = _generation;
    if (!_current(generation)) return false;
    final pending = state.pending;
    if (!state.canRetry || pending == null) return false;
    final saved = await _save(
      (onAcknowledged) => mangaKey == null
          ? repository!.setGlobal(
              values: pending.global!,
              basedOnRevision: pending.basedOnRevision,
              onAcknowledged: onAcknowledged,
            )
          : repository!.setManga(
              mangaKey: mangaKey!,
              overrides: pending.overrides!,
              basedOnRevision: pending.basedOnRevision,
              onAcknowledged: onAcknowledged,
            ),
      retrying: true,
    );
    if (saved && _current(generation) && _unsent != null) {
      unawaited(_drainAutosave());
    }
    return saved;
  }

  Future<bool> _save(
    Future<SettingsSnapshot> Function(void Function() onAcknowledged) send, {
    bool retrying = false,
    bool automatic = false,
  }) async {
    if (!_current(_generation) ||
        !(retrying
            ? state.canRetry
            : (automatic ? state._canStart : state.canEdit))) {
      return false;
    }
    final generation = _generation;
    state = _next(
      activity: retrying && state.pending?.acknowledged == true
          ? SettingsActivity.reading
          : SettingsActivity.saving,
    );
    try {
      final snapshot = await send(() {
        if (_current(generation)) {
          state = _next(activity: SettingsActivity.reading);
        }
      });
      if (!_current(generation)) return false;
      state = _next(snapshot: snapshot);
      return true;
    } catch (error) {
      if (_current(generation)) {
        final pending = _pending();
        final failure =
            pending?.acknowledged == true && pending?.retryable == true
            ? SettingsFailure.confirmedRead
            : switch (error) {
                BusinessStateException(conflict: true) =>
                  SettingsFailure.conflict,
                BusinessStateException(:final error) when !error.retryable =>
                  SettingsFailure.rejected,
                _ => SettingsFailure.unknown,
              };
        state = _next(failure: failure, error: _failureMessage(failure));
      }
      return false;
    } finally {
      if (_current(generation)) _refreshInheritance();
    }
  }
}
