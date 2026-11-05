import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/business_state_client.dart';
import '../../data/settings_repository.dart';

/// A single global or manga editor; pending commands belong to the shared
/// identity-bound repository, independently of this widget's lifetime.
final class SettingsController extends ChangeNotifier {
  SettingsController({
    required this.repository,
    required this.isCurrent,
    this.mangaKey,
  }) {
    _subscription = repository.watchConfirmed().listen(_confirmed);
  }

  final SettingsRepository repository;
  final bool Function() isCurrent;
  final String? mangaKey;
  late final StreamSubscription<SettingsSnapshot> _subscription;
  SettingsSnapshot? _snapshot;
  bool _busy = false;
  bool _retired = false;
  bool _disposed = false;
  String? _error;
  int _wantedGlobalRevision = -1;

  SettingsSnapshot? get snapshot => _snapshot;
  bool get busy => _busy;
  String? get error => _error;
  SettingsDraft? get pending => mangaKey == null
      ? repository.pendingGlobal()
      : repository.pendingManga(mangaKey!);
  bool get available => !_disposed && !_retired && isCurrent();
  bool get canEdit =>
      available && !_busy && _snapshot != null && pending == null;
  bool get canRefresh => available && !_busy;
  bool get canRetry => available && !_busy && pending?.retryable == true;

  void checkCurrent() {
    if (_disposed || _retired || isCurrent()) return;
    _retired = true;
    _error = '身份或服务已改变，请重新打开设置。';
    notifyListeners();
  }

  void _confirmed(SettingsSnapshot value) {
    if (!available) return;
    if (value.globalRevision > _wantedGlobalRevision) {
      _wantedGlobalRevision = value.globalRevision;
    }
    if (mangaKey == null) {
      if (_snapshot != null &&
          value.globalRevision <= _snapshot!.globalRevision) {
        return;
      }
      _snapshot = value;
      notifyListeners();
    } else if (value.mangaKey == mangaKey) {
      _snapshot = value;
      notifyListeners();
    } else {
      _refreshInheritance();
    }
  }

  void _refreshInheritance() {
    if (mangaKey != null &&
        canRefresh &&
        pending == null &&
        _error == null &&
        _wantedGlobalRevision > (_snapshot?.globalRevision ?? -1)) {
      unawaited(refresh());
    }
  }

  Future<bool> refresh() async {
    checkCurrent();
    if (!canRefresh) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final value = mangaKey == null
          ? await repository.loadGlobal()
          : await repository.loadManga(mangaKey!);
      if (!available) return false;
      _snapshot = value;
      return true;
    } catch (_) {
      if (available) _error = '未能读取服务端设置；当前阅读仍可继续。';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        checkCurrent();
        notifyListeners();
        _refreshInheritance();
      }
    }
  }

  Future<bool> saveGlobal(wire.GlobalSettingsValues values, int revision) =>
      _save(
        () => repository.setGlobal(values: values, basedOnRevision: revision),
      );

  Future<bool> saveOverrides(
    wire.ReaderSettingsOverride values,
    int revision,
  ) => _save(
    () => repository.setManga(
      mangaKey: mangaKey!,
      overrides: values,
      basedOnRevision: revision,
    ),
  );

  Future<bool> retry() async {
    checkCurrent();
    final draft = pending;
    if (!canRetry || draft == null) return false;
    return _save(
      () => mangaKey == null
          ? repository.setGlobal(
              values: draft.global!,
              basedOnRevision: draft.basedOnRevision,
            )
          : repository.setManga(
              mangaKey: mangaKey!,
              overrides: draft.overrides!,
              basedOnRevision: draft.basedOnRevision,
            ),
      retrying: true,
    );
  }

  Future<bool> _save(
    Future<SettingsSnapshot> Function() send, {
    bool retrying = false,
  }) async {
    checkCurrent();
    if (!(retrying ? canRetry : canEdit)) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final value = await send();
      if (!available) return false;
      _snapshot = value;
      return true;
    } catch (failure) {
      if (available) {
        _error = failure is BusinessStateException && failure.conflict
            ? '设置已在其他设备修改，请重新读取后确认。'
            : '设置修改尚未确认，请明确重试原操作。';
      }
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        checkCurrent();
        notifyListeners();
        _refreshInheritance();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
