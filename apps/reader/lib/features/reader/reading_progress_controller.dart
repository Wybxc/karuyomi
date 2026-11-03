import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reader_core/reader_core.dart';

import '../../data/progress_repository.dart';
import '../../data/reading_progress.dart';

final class _PendingProgress {
  const _PendingProgress(this.manifest, this.progress, this.reversedOrder);
  final ChapterManifest manifest;
  final ChapterProgress progress;
  final bool reversedOrder;
}

/// Product write scheduling only. Anchor projection, furthest merging and epoch
/// rules remain in ChapterProgress and the transactional Drift repository.
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
  final _states = <String, ChapterProgress>{};
  final _conflicted = <String>{};
  final _navigationPending = <String>{};
  final _resetting = <String>{};
  Timer? _delay;
  Timer? _deadline;
  Future<void>? _flushing;
  bool _closed = false;
  bool _orderLoaded = false;
  String? _currentChapter;
  bool reversedOrder = false;
  ProgressStorageMode? storageMode;
  String? error;

  bool get unsaved => _pending.isNotEmpty;
  bool get awaitingViewport => _navigationPending.isNotEmpty;
  ChapterProgress? chapter(String key) => _states[key];
  MangaResume? get draftResume => _currentChapter == null
      ? null
      : MangaResume(chapterKey: _currentChapter!, reversedOrder: reversedOrder);

  Future<ReadingPosition?> restore(ChapterManifest manifest) async {
    if (manifest.pages.isEmpty || _closed) return null;
    ChapterProgress? stored = _pending[manifest.chapterKey]?.progress;
    try {
      storageMode ??= await repository.database.storageMode;
      if (!_orderLoaded) {
        final resume = await repository.loadResume(mangaKey);
        if (resume != null) reversedOrder = resume.reversedOrder;
        _orderLoaded = true;
      }
      stored ??= await repository.loadChapter(
        mangaKey: mangaKey,
        chapterKey: manifest.chapterKey,
      );
      error = null;
      _conflicted.remove(manifest.chapterKey);
    } catch (_) {
      error = '未能读取本地进度，阅读仍可继续；保存失败时可重试。';
      stored ??= _states[manifest.chapterKey];
    }
    if (_closed) return null;
    final anchor = resolvePosition(manifest, stored?.current).position!;
    _states[manifest.chapterKey] = (stored ?? ChapterProgress(current: anchor))
        .advance(manifest: manifest, current: anchor);
    // Opening a chapter records navigation even when its saved anchor has not
    // changed. Merely preparing its pages() session never calls this method.
    _navigationPending.add(manifest.chapterKey);
    _notify();
    // Return the original anchor so ReaderScreen can show missing-page notice.
    return stored?.current;
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
    _cancelTimers();
    if (!unsaved && _flushing == null) return true;
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
    return !unsaved;
  }

  Future<void> _drain() async {
    while (_pending.isNotEmpty) {
      final entry = _pending.entries.first;
      final draft = entry.value;
      try {
        storageMode ??= await repository.database.storageMode;
        final saved = await repository.save(
          mangaKey: mangaKey,
          manifest: draft.manifest,
          progress: draft.progress,
          reversedOrder: draft.reversedOrder,
        );
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
      } catch (_) {
        error = '本地进度尚未保存，可重试；阅读仍可继续。';
        _notify();
        return; // Keep the exact dirty draft for a later explicit retry.
      }
    }
    _notify();
  }

  Future<ChapterProgress?> reset(ChapterManifest manifest) async {
    if (_closed || manifest.pages.isEmpty) return null;
    _resetting.add(manifest.chapterKey);
    await flush();
    try {
      final reset = await repository.reset(
        mangaKey: mangaKey,
        manifest: manifest,
        reversedOrder: reversedOrder,
      );
      _pending.remove(manifest.chapterKey);
      _conflicted.remove(manifest.chapterKey);
      _states[manifest.chapterKey] = reset;
      _currentChapter = manifest.chapterKey;
      error = null;
      _notify();
      return reset;
    } catch (_) {
      error = '重新阅读未能保存，请重试。';
      _notify();
      return null;
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
