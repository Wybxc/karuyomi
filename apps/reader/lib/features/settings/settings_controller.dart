import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/business_state_client.dart';
import '../../data/settings_repository.dart';
import '../../state/account_providers.dart';
import '../browse/catalog_controller.dart';

part 'settings_controller.g.dart';

enum SettingsFailure { conflict, rejected, unknown }

final class SettingsState {
  const SettingsState({
    this.snapshot,
    this.pending,
    this.available = false,
    this.busy = false,
    this.error,
    this.failure,
  });
  final SettingsSnapshot? snapshot;
  final SettingsDraft? pending;
  final bool available;
  final bool busy;
  final String? error;
  final SettingsFailure? failure;
  bool get canEdit => available && !busy && snapshot != null && pending == null;
  bool get canRefresh => available && !busy;
  bool get canRetry => available && !busy && pending?.retryable == true;
}

/// One editor per verified catalog identity and global/manga scope. Submitted
/// UUID/CAS drafts remain in BusinessStateClient when this provider is disposed.
@riverpod
class SettingsController extends _$SettingsController {
  Object _generation = Object();
  int _wantedGlobalRevision = -1;

  @override
  SettingsState build(
    CatalogController catalog,
    SettingsRepository? repository, {
    String? mangaKey,
  }) {
    final account = ref.watch(confirmedAccountProvider(catalog));
    final generation = _generation = Object();
    final initial = mangaKey == null ? catalog.installationSettings : null;
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
        busy: state.busy,
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

  SettingsState _next({
    SettingsSnapshot? snapshot,
    bool busy = false,
    String? error,
    SettingsFailure? failure,
  }) => SettingsState(
    snapshot: snapshot ?? state.snapshot,
    pending: _pending(),
    available: _current(_generation),
    busy: busy,
    error: error,
    failure: failure,
  );

  void _refreshInheritance() {
    if (mangaKey != null &&
        state.canRefresh &&
        state.pending == null &&
        state.error == null &&
        _wantedGlobalRevision > (state.snapshot?.globalRevision ?? -1)) {
      unawaited(refresh());
    }
  }

  Future<bool> refresh() async {
    if (!_current(_generation) || !state.canRefresh) return false;
    state = _next(busy: true);
    final generation = _generation;
    try {
      final snapshot = mangaKey == null
          ? await repository!.loadGlobal()
          : await repository!.loadManga(mangaKey!);
      if (!_current(generation)) return false;
      state = _next(snapshot: snapshot);
      return true;
    } catch (_) {
      if (_current(generation)) state = _next(error: '未能读取服务端设置；当前阅读仍可继续。');
      return false;
    } finally {
      if (_current(generation)) _refreshInheritance();
    }
  }

  Future<bool> saveGlobal(wire.GlobalSettingsValues values, int revision) =>
      _save(
        () => repository!.setGlobal(values: values, basedOnRevision: revision),
      );

  Future<bool> saveOverrides(
    wire.ReaderSettingsOverride values,
    int revision,
  ) => _save(
    () => repository!.setManga(
      mangaKey: mangaKey!,
      overrides: values,
      basedOnRevision: revision,
    ),
  );

  Future<bool> retry() async {
    if (!_current(_generation)) return false;
    final pending = state.pending;
    if (!state.canRetry || pending == null) return false;
    return _save(
      () => mangaKey == null
          ? repository!.setGlobal(
              values: pending.global!,
              basedOnRevision: pending.basedOnRevision,
            )
          : repository!.setManga(
              mangaKey: mangaKey!,
              overrides: pending.overrides!,
              basedOnRevision: pending.basedOnRevision,
            ),
      retrying: true,
    );
  }

  Future<bool> _save(
    Future<SettingsSnapshot> Function() send, {
    bool retrying = false,
  }) async {
    if (!_current(_generation) ||
        !(retrying ? state.canRetry : state.canEdit)) {
      return false;
    }
    final generation = _generation;
    state = _next(busy: true);
    try {
      final snapshot = await send();
      if (!_current(generation)) return false;
      state = _next(snapshot: snapshot);
      return true;
    } catch (error) {
      if (_current(generation)) {
        final failure = switch (error) {
          BusinessStateException(conflict: true) => SettingsFailure.conflict,
          BusinessStateException(:final error) when !error.retryable =>
            SettingsFailure.rejected,
          _ => SettingsFailure.unknown,
        };
        state = _next(
          failure: failure,
          error: switch (failure) {
            SettingsFailure.conflict => '设置已在其他设备修改，请重新读取后确认。',
            SettingsFailure.rejected => '设置修改已被服务端拒绝，请重新读取后确认。',
            SettingsFailure.unknown => '设置修改尚未确认，请明确重试原操作。',
          },
        );
      }
      return false;
    } finally {
      if (_current(generation)) _refreshInheritance();
    }
  }
}
