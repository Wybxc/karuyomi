import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reader_core/reader_core.dart';

import '../../data/business_state_client.dart';
import '../../data/progress_repository.dart';
import '../../data/reading_progress.dart';

final class _PendingProgress {
  const _PendingProgress(this.manifest, this.progress, this.reversedOrder);
  final ChapterManifest manifest;
  final ChapterProgress progress;
  final bool reversedOrder;
}

final class _PendingReset {
  const _PendingReset(this.manifest, this.reversedOrder);
  final ChapterManifest manifest;
  final bool reversedOrder;
}

/// Product write scheduling only. Anchor projection, furthest merging and epoch
/// rules remain in ChapterProgress and the authoritative Worker transaction.
final class ReadingProgressController extends ChangeNotifier {
  ReadingProgressController({
    required this.repository,
    required this.mangaKey,
    this.debounce = const Duration(milliseconds: 600),
    this.maxWait = const Duration(seconds: 2),
  });

  final ProgressRepository repository;
  final String mangaKey;
  final Duration debounce;
  final Duration maxWait;
  final _pending = <String, _PendingProgress>{};
  final _pendingResets = <String, _PendingReset>{};
  final _states = <String, ChapterProgress>{};
  final _confirmed = <String, ProgressSnapshot>{};
  final _conflicted = <String>{};
  final _navigationPending = <String>{};
  final _resetting = <String>{};
  Timer? _delay;
  Timer? _deadline;
  Future<void>? _flushing;
  bool _closed = false;
  bool _orderLoaded = false;
  int _viewSequence = 0;
  int _refreshSequence = 0;
  String? _currentChapter;
  bool reversedOrder = false;
  ProgressStorageMode? storageMode;
  String? error;

  bool get unsaved => _pending.isNotEmpty || _pendingResets.isNotEmpty;
  bool get awaitingViewport => _navigationPending.isNotEmpty;
  ChapterProgress? chapter(String key) => _states[key];
  bool needsReopen(String chapterKey) => _conflicted.contains(chapterKey);
  MangaResume? get draftResume => _currentChapter == null
      ? null
      : MangaResume(chapterKey: _currentChapter!, reversedOrder: reversedOrder);

  Future<ReadingPosition?> restore(ChapterManifest manifest) async {
    if (manifest.pages.isEmpty || _closed) return null;
    final view = ++_viewSequence;
    ++_refreshSequence;
    final reopening = needsReopen(manifest.chapterKey);
    ProgressSnapshot? loaded;
    ChapterProgress? stored = reopening
        ? null
        : _pending[manifest.chapterKey]?.progress;
    try {
      storageMode = ProgressStorageMode.serverConfirmed;
      if (stored == null) {
        final state = await repository.loadChapterState(
          mangaKey: mangaKey,
          chapterKey: manifest.chapterKey,
        );
        if (_closed || view != _viewSequence) return null;
        _remember(manifest.chapterKey, state);
        loaded = state;
        stored = state.progress;
        if (!_orderLoaded || reopening) {
          reversedOrder = state.resume?.reversedOrder ?? false;
        }
        _orderLoaded = true;
      }
      if (reopening) {
        _pending.remove(manifest.chapterKey);
        _pendingResets.remove(manifest.chapterKey);
      }
      error = null;
      _conflicted.remove(manifest.chapterKey);
    } catch (_) {
      if (_closed || view != _viewSequence) return null;
      error = '未能读取服务器进度，阅读仍可继续；未确认的修改仅保留在当前会话。';
      stored ??= _states[manifest.chapterKey];
    }
    if (_closed || view != _viewSequence) return null;
    final anchor = resolvePosition(manifest, stored?.current).position!;
    _states[manifest.chapterKey] =
        (stored ??
                ChapterProgress(
                  current: anchor,
                  epoch: loaded?.epoch ?? 0,
                  completed: loaded?.completed ?? false,
                ))
            .advance(manifest: manifest, current: anchor);
    // Opening a chapter records navigation even when its saved anchor has not
    // changed. Merely preparing its pages() session never calls this method.
    _navigationPending.add(manifest.chapterKey);
    _notify();
    // Return the original anchor so ReaderScreen can show missing-page notice.
    return stored?.current;
  }

  /// Foreground refresh never moves the current viewport. Unconfirmed writes
  /// keep their original CAS view; an observed server change requires reopening.
  Future<void> refreshFromServer(ChapterManifest manifest) async {
    if (_closed ||
        manifest.pages.isEmpty ||
        needsReopen(manifest.chapterKey) ||
        _resetting.isNotEmpty) {
      return;
    }
    final refresh = ++_refreshSequence;
    final view = _viewSequence;
    bool current() =>
        !_closed && refresh == _refreshSequence && view == _viewSequence;
    _cancelTimers();
    if (unsaved || _flushing != null) {
      if (!await flush() || !current()) return;
    }
    if (!current()) return;
    final before = _confirmed[manifest.chapterKey];
    try {
      final latest = await repository.inspectChapter(
        mangaKey: mangaKey,
        chapterKey: manifest.chapterKey,
      );
      if (!current()) return;
      final progressChanged =
          before == null ||
          before.epoch != latest.epoch ||
          before.completed != latest.completed ||
          !_sameNullableProgress(before.progress, latest.progress) ||
          !_sameResume(before.resume, latest.resume);
      final remoteRevisionChanged =
          before != null &&
          latest.revision != before.revision &&
          !repository.client.hasOnlyLocalChangesSince(
            mangaKey,
            basedOnRevision: before.revision,
            revision: latest.revision,
          );
      if (progressChanged || remoteRevisionChanged) {
        _conflicted.add(manifest.chapterKey);
        error = before?.epoch != latest.epoch
            ? '本章进度已在其他设备重置，当前阅读位置保持不变。请重新打开本章后继续保存。'
            : progressChanged
            ? '阅读进度已在其他设备更新，当前阅读位置保持不变。请重新打开本章后继续保存。'
            : '此作品已在其他设备更新，当前阅读位置保持不变。请重新打开本章后继续保存。';
      } else if (_conflicted.isEmpty) {
        _remember(manifest.chapterKey, latest);
        error = null;
      }
      _notify();
    } catch (_) {
      if (!current()) return;
      error = '未能刷新服务器进度，当前阅读位置保持不变，可重试。';
      _notify();
    }
  }

  void _remember(String chapterKey, ProgressSnapshot snapshot) {
    if (snapshot.revision >= (_confirmed[chapterKey]?.revision ?? 0)) {
      _confirmed[chapterKey] = snapshot;
    }
  }

  void observe({
    required ChapterManifest manifest,
    required ReadingPosition current,
    ReadingPosition? observed,
    required bool reversedOrder,
    bool complete = false,
  }) {
    if (_closed ||
        _conflicted.contains(manifest.chapterKey) ||
        _resetting.contains(manifest.chapterKey) ||
        _pendingResets.containsKey(manifest.chapterKey) ||
        manifest.pages.isEmpty) {
      return;
    }
    final before =
        _states[manifest.chapterKey] ?? ChapterProgress(current: current);
    final after = before.advance(
      manifest: manifest,
      current: current,
      observed: observed,
      complete: complete,
    );
    final orderChanged = this.reversedOrder != reversedOrder;
    this.reversedOrder = reversedOrder;
    _currentChapter = manifest.chapterKey;
    final navigation = _navigationPending.remove(manifest.chapterKey);
    if (_sameProgress(before, after) &&
        !orderChanged &&
        !navigation &&
        _states.containsKey(manifest.chapterKey)) {
      return;
    }
    final wasUnsaved = unsaved;
    ++_viewSequence;
    _states[manifest.chapterKey] = after;
    _pending[manifest.chapterKey] = _PendingProgress(
      manifest,
      after,
      reversedOrder,
    );
    _delay?.cancel();
    _delay = Timer(debounce, () => unawaited(flush()));
    _deadline ??= Timer(maxWait, () => unawaited(flush()));
    if (!wasUnsaved || before.completed != after.completed) _notify();
  }

  Future<bool> flush() async {
    if (_closed) return !unsaved && _conflicted.isEmpty;
    _cancelTimers();
    if (!unsaved && _flushing == null) return _conflicted.isEmpty;
    if (_flushing != null) {
      await _flushing;
      // A new viewport can arrive in the completion microtask of the previous
      // drain, after this caller has cancelled its timer. Do not strand it.
      if (unsaved && error == null) return flush();
    } else {
      final pending = _drain();
      _flushing = pending;
      try {
        await pending;
      } finally {
        _flushing = null;
      }
    }
    if (!unsaved) _cancelTimers();
    return !unsaved && _conflicted.isEmpty;
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty && !_closed) {
      final entry = _pending.entries.first;
      final draft = entry.value;
      try {
        storageMode = ProgressStorageMode.serverConfirmed;
        final confirmed = await repository.saveState(
          mangaKey: mangaKey,
          manifest: draft.manifest,
          progress: draft.progress,
          reversedOrder: draft.reversedOrder,
          basedOnRevision: _confirmed[entry.key]?.revision,
        );
        if (_closed) return;
        final saved = confirmed.progress!;
        _remember(entry.key, confirmed);
        if (saved.epoch != draft.progress.epoch) {
          _pending.remove(entry.key);
          _states[entry.key] = saved;
          _conflicted.add(entry.key);
          error = '本章进度已在其他窗口重置，请重新打开本章。';
        } else {
          if (identical(_pending[entry.key], draft)) {
            _pending.remove(entry.key);
            _states[entry.key] = saved;
          }
          if (_conflicted.isEmpty) error = null;
        }
      } on BusinessStateException catch (failure) {
        if (_closed) return;
        if (failure.conflict) {
          _pending.remove(entry.key);
          _conflicted.add(entry.key);
          if (failure.progress?.hasCurrent() == true) {
            _states[entry.key] = decodeChapterProgress(failure.progress!);
          }
          error = failure.staleEpoch
              ? '本章进度已在其他窗口重置，请重新打开本章。'
              : '此作品已在其他设备更新，请重新打开本章后继续保存。';
          _notify();
          return;
        }
        error = '进度尚未获服务器确认，可重试；草稿仅保留在当前会话。';
        _notify();
        return;
      } catch (_) {
        if (_closed) return;
        error = '进度尚未保存到服务器，可重试；草稿仅保留在当前会话。';
        _notify();
        return; // Keep the exact dirty draft for a later explicit retry.
      }
    }
    while (_pendingResets.isNotEmpty && !_closed) {
      final entry = _pendingResets.entries.first;
      try {
        final confirmed = await repository.resetState(
          mangaKey: mangaKey,
          manifest: entry.value.manifest,
          reversedOrder: entry.value.reversedOrder,
          basedOnRevision: _confirmed[entry.key]?.revision,
        );
        if (_closed) return;
        final saved = confirmed.progress!;
        _remember(entry.key, confirmed);
        _pendingResets.remove(entry.key);
        _conflicted.remove(entry.key);
        _states[entry.key] = saved;
        _currentChapter = entry.key;
        storageMode = ProgressStorageMode.serverConfirmed;
        error = null;
      } on BusinessStateException catch (failure) {
        if (_closed) return;
        if (failure.conflict) {
          _pendingResets.remove(entry.key);
          _conflicted.add(entry.key);
          error = '此作品已在其他设备更新，请重新打开本章后再重新阅读。';
        } else {
          error = '重新阅读尚未获服务器确认，请重试；草稿仅保留在当前会话。';
        }
        _notify();
        return;
      } catch (_) {
        if (_closed) return;
        error = '重新阅读尚未保存到服务器，请重试；草稿仅保留在当前会话。';
        _notify();
        return;
      }
    }
    _notify();
  }

  Future<ChapterProgress?> reset(ChapterManifest manifest) async {
    if (_closed ||
        manifest.pages.isEmpty ||
        _resetting.contains(manifest.chapterKey)) {
      return null;
    }
    _resetting.add(manifest.chapterKey);
    ++_viewSequence;
    ++_refreshSequence;
    try {
      if (!_pendingResets.containsKey(manifest.chapterKey)) {
        if (!await flush() || _closed) return null;
        _pendingResets[manifest.chapterKey] = _PendingReset(
          manifest,
          reversedOrder,
        );
      }
      _notify();
      return await flush() &&
              !_closed &&
              !_conflicted.contains(manifest.chapterKey)
          ? _states[manifest.chapterKey]
          : null;
    } finally {
      _resetting.remove(manifest.chapterKey);
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _delay?.cancel();
    _delay = null;
    _deadline?.cancel();
    _deadline = null;
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }
}

bool _sameAnchor(ReadingPosition? a, ReadingPosition? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        a.chapterKey == b.chapterKey &&
        a.pageKey == b.pageKey &&
        a.manifestVersion == b.manifestVersion &&
        a.pageIndexHint == b.pageIndexHint &&
        a.normalizedOffset == b.normalizedOffset);
bool _sameProgress(ChapterProgress a, ChapterProgress b) =>
    a.epoch == b.epoch &&
    a.completed == b.completed &&
    _sameAnchor(a.current, b.current) &&
    _sameAnchor(a.furthest, b.furthest);

bool _sameNullableProgress(ChapterProgress? a, ChapterProgress? b) =>
    identical(a, b) || (a != null && b != null && _sameProgress(a, b));

bool _sameResume(MangaResume? a, MangaResume? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        a.chapterKey == b.chapterKey &&
        a.reversedOrder == b.reversedOrder);
