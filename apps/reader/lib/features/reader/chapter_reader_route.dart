import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_core/reader_core.dart';

import '../../data/reading_progress.dart';
import '../browse/catalog_controller.dart';
import 'chapter_sequence.dart';
import 'chapter_preparation.dart';
import 'reader_screen.dart';
import 'reading_progress_controller.dart';

/// One navigation route owns the whole reading session, not one route per page
/// list. A new leaf can only acquire images after the previous leaf's ACKs.
class ChapterReaderRoute extends StatefulWidget {
  const ChapterReaderRoute({
    super.key,
    required this.catalog,
    required this.manga,
    required this.source,
    required this.sequence,
    required this.initialChapter,
    required this.initialOpened,
  });

  final CatalogController catalog;
  final MangaEntry manga;
  final CatalogSourceRef source;
  final ChapterSequence sequence;
  final SequenceChapter initialChapter;
  final OpenedChapter initialOpened;

  @override
  State<ChapterReaderRoute> createState() => _ChapterReaderRouteState();
}

class _ChapterReaderRouteState extends State<ChapterReaderRoute>
    with WidgetsBindingObserver {
  late OpenedChapter _opened = widget.initialOpened;
  late SequenceChapter _chapter = widget.initialChapter;
  ChapterOrder _order = ChapterOrder.source;
  Completer<void> _viewClosed = Completer<void>();
  bool _visible = true;
  bool _busy = false;
  bool _closing = false;
  bool _viewAttached = false;
  String? _error;
  Future<void>? _moving;
  late final _preparation = ChapterPreparation(_openChapter);
  ReaderViewportState? _viewport;
  bool _preparationScheduled = false;
  String? _preparationAttempt;
  ReadingProgressController? _progress;
  ReadingPosition? _initialPosition;
  final _positionRequest = ValueNotifier<ReadingPosition?>(null);
  bool _allowPop = false;
  bool _exitPending = false;

  @override
  void initState() {
    super.initState();
    widget.catalog.addListener(_schedulePreparation);
    WidgetsBinding.instance.addObserver(this);
    _progress = widget.catalog.createReadingProgress(widget.sequence.mangaKey);
    _progress?.addListener(_progressChanged);
    if (_progress != null && _opened.manifest.pages.isNotEmpty) {
      _visible = false;
      unawaited(_restoreInitial());
    }
  }

  Future<void> _restoreInitial() async {
    final position = await _progress!.restore(_opened.manifest);
    if (_closing || !mounted) return;
    setState(() {
      _initialPosition = position;
      _order = _progress!.reversedOrder
          ? ChapterOrder.reversed
          : ChapterOrder.source;
      _visible = true;
    });
  }

  void _progressChanged() {
    if (!_closing && mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_progress?.flush());
  }

  void _recordViewport({bool complete = false}) {
    final viewport = _viewport;
    if (viewport == null || _closing) return;
    _progress?.observe(
      manifest: _opened.manifest,
      current: viewport.current,
      observed: viewport.observed,
      reversedOrder: _order == ChapterOrder.reversed,
      complete: complete,
    );
  }

  Future<void> _finishChapter() async {
    final canComplete = _viewport?.atEnd == true && _viewport?.observed != null;
    if (_busy || !canComplete) return;
    _recordViewport(complete: true);
    await _progress?.flush();
  }

  Future<void> _resetChapter() async {
    final progress = _progress;
    if (_busy || progress == null) return;
    setState(() => _busy = true);
    final reset = await progress.reset(_opened.manifest);
    if (!_closing && mounted) {
      if (reset != null) {
        _viewport = null;
        _positionRequest.value = reset.current;
      }
      setState(() => _busy = false);
    }
  }

  Future<void> _exit() async {
    if (_exitPending || _closing) return;
    _exitPending = true;
    await _progress?.flush();
    if (_closing || !mounted) return;
    setState(() => _allowPop = true);
    // Update PopScope before requesting the second, now permitted pop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) Navigator.of(context).pop();
    });
  }

  void _schedulePreparation() {
    if (_preparationScheduled || _closing) return;
    _preparationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preparationScheduled = false;
      if (!mounted ||
          _closing ||
          _busy ||
          _preparation.busy ||
          _preparation.ready ||
          _preparation.blocked ||
          widget.catalog.busy ||
          !widget.catalog.isCurrentSource(widget.source) ||
          _viewport?.atEnd != true ||
          _viewport?.windowReady != true) {
        return;
      }
      final next = widget.sequence.adjacent(_chapter.sourceIndex, _order, 1);
      if (next == null) return;
      final attempt = '${_chapter.key}:${next.key}';
      if (_preparationAttempt == attempt) return;
      _preparationAttempt = attempt;
      unawaited(_prepareNext(next));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<OpenedChapter?> _openChapter(SequenceChapter chapter) =>
      widget.catalog.openChapter(
        widget.manga,
        ChapterEntry(chapter.snapshot),
        reference: widget.source,
        logicalChapterKey: chapter.key,
      );

  Future<void> _prepareNext(SequenceChapter target) async {
    if (_busy ||
        _closing ||
        _preparation.busy ||
        _preparation.ready ||
        _preparation.blocked) {
      return;
    }
    final pending = _preparation.prepare(target);
    setState(() => _error = null);
    try {
      await pending;
      if (!_closing && mounted) {
        setState(() {
          if (!_preparation.ready && widget.catalog.error != null) {
            _error = widget.catalog.error;
          }
        });
      }
    } catch (_) {
      if (!_closing && mounted) {
        setState(() => _error = '下一章准备未完成，可进入时重试');
      }
    }
  }

  void _changeOrder(ChapterOrder order) {
    final pending = _preparation.discard();
    setState(() {
      _order = order;
      _preparationAttempt = null;
    });
    _recordViewport();
    unawaited(() async {
      try {
        await pending;
      } catch (_) {
        if (!_closing && mounted) {
          setState(() => _error = '章节资源清理失败，请返回重新连接漫画源');
        }
      }
      if (!_closing && mounted) setState(() {});
      _schedulePreparation();
    }());
  }

  Future<void> _move(SequenceChapter target) {
    if (_busy || _closing || target.key == _chapter.key) return Future.value();
    setState(() {
      _busy = true;
      _error = null;
    });
    final operation = _changeChapter(target);
    _moving = operation;
    return operation;
  }

  Future<void> _changeChapter(SequenceChapter target) async {
    OpenedChapter? next;
    try {
      // Next is an explicit completion action only when the real viewport has
      // displayed the chapter end. A jump or a prepared session is not one.
      if (widget.sequence.adjacent(_chapter.sourceIndex, _order, 1)?.key ==
              target.key &&
          _viewport?.atEnd == true &&
          _viewport?.observed != null) {
        _recordViewport(complete: true);
      }
      await _progress?.flush();
      next = await _preparation.take(target);
      if (_closing || !mounted) return;
      next ??= await _openChapter(target);
      if (next == null) {
        if (!_closing && mounted) {
          setState(() => _error = widget.catalog.error ?? '章节未能打开，请重试');
        }
        return;
      }
      if (_closing || !mounted) return;
      setState(() => _visible = false);
      await _viewClosed.future;
      if (_closing || !mounted) return;
      await _progress?.flush();
      final position = await _progress?.restore(next.manifest);
      if (_closing || !mounted) return;
      if (!widget.catalog.isCurrentSource(widget.source)) {
        throw StateError('Source session expired during chapter transition');
      }
      setState(() {
        _opened = next!;
        _chapter = target;
        _viewClosed = Completer<void>();
        _viewAttached = false;
        _viewport = null;
        _initialPosition = position;
        _positionRequest.value = null;
        _preparationAttempt = null;
        _visible = true;
      });
      next = null; // The route owns it until onAttached mounts the new leaf.
    } catch (_) {
      if (!_closing && mounted) {
        setState(() => _error = '章节切换未完成，请返回重新连接漫画源');
      }
    } finally {
      if (next != null) {
        try {
          await next.provider.close();
        } catch (_) {
          if (!_closing && mounted) {
            setState(() => _error = '章节资源清理失败，请返回重新连接漫画源');
          }
        }
      }
      if (!_closing && mounted) setState(() => _busy = false);
    }
  }

  Widget _chapterControls() {
    final previous = widget.sequence.adjacent(_chapter.sourceIndex, _order, -1);
    final next = widget.sequence.adjacent(_chapter.sourceIndex, _order, 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_preparation.busy && !_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
        if (_progress case final progress?) _progressControls(progress),
        Row(
          children: [
            TextButton.icon(
              onPressed: _busy || previous == null
                  ? null
                  : () => unawaited(_move(previous)),
              icon: const Icon(Icons.navigate_before),
              label: const Text('上一章'),
            ),
            Expanded(
              child: DropdownButton<ChapterOrder>(
                value: _order,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: ChapterOrder.source,
                    child: Text('来源顺序'),
                  ),
                  DropdownMenuItem(
                    value: ChapterOrder.reversed,
                    child: Text('反向来源顺序'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (order) {
                        if (order != null) _changeOrder(order);
                      },
              ),
            ),
            TextButton.icon(
              onPressed: _busy || next == null
                  ? null
                  : () => unawaited(_move(next)),
              icon: const Icon(Icons.navigate_next),
              label: const Text('下一章'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _progressControls(ReadingProgressController progress) {
    if (_opened.manifest.pages.isEmpty) return const Text('本章没有页面，不记录进度');
    final saved = progress.chapter(_chapter.key);
    final unresolved = saved?.furthestUnresolved(_opened.manifest) ?? false;
    final far = saved?.furthest;
    final status =
        progress.error ??
        switch (progress.storageMode) {
          ProgressStorageMode.memoryOnly => '仅当前会话记录，关闭后不会保留',
          ProgressStorageMode.unsafePersistence => '本地存储不支持安全多窗口，请保持单窗口阅读',
          ProgressStorageMode.persistent =>
            progress.unsaved || progress.awaitingViewport
                ? '本地进度待保存'
                : '本地进度已保存',
          null => '正在连接本地进度存储',
        };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(status),
          if (unresolved) const Text('旧最远页已不在当前清单中；保留原记录，未按旧页码猜测'),
          if (!unresolved && far != null)
            Text(
              '最远：第 ${far.pageIndexHint + 1} 页${saved!.completed ? ' · 本章已读完' : ''}',
            ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: _busy || _opened.manifest.pages.isEmpty
                    ? null
                    : () => unawaited(_resetChapter()),
                child: const Text('重新阅读本章'),
              ),
              TextButton(
                onPressed:
                    _busy ||
                        _viewport?.atEnd != true ||
                        _viewport?.observed == null ||
                        saved?.completed == true
                    ? null
                    : () => unawaited(_finishChapter()),
                child: const Text('读完本章'),
              ),
              if (progress.error != null && progress.unsaved)
                TextButton(
                  onPressed: () => unawaited(progress.flush()),
                  child: const Text('重试保存'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _progress == null || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_exit());
      },
      child: _reader(),
    );
  }

  Widget _reader() {
    if (!_visible) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.manga.title)),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Text(_error!),
        ),
      );
    }
    final opened = _opened;
    final completion = _viewClosed;
    return ReaderScreen(
      key: ValueKey('${opened.generation}:${opened.provider.pageSessionId}'),
      manifest: opened.manifest,
      provider: opened.provider,
      generation: opened.generation,
      title: opened.title,
      initialPosition: _initialPosition,
      positionRequest: _positionRequest,
      chapterControls: _chapterControls(),
      onViewportChanged: (viewport) {
        if (_closing || !identical(opened, _opened)) return;
        final changed =
            _viewport?.atEnd != viewport.atEnd ||
            _viewport?.windowReady != viewport.windowReady;
        _viewport = viewport;
        _recordViewport();
        if (changed && !_closing && mounted) setState(() {});
        _schedulePreparation();
      },
      onAttached: () {
        if (identical(completion, _viewClosed)) _viewAttached = true;
      },
      onClosed: opened.provider.close,
      onClosing: (cleanup) {
        if (identical(completion, _viewClosed)) _viewAttached = false;
        if (!completion.isCompleted) completion.complete(cleanup);
      },
    );
  }

  @override
  void dispose() {
    _closing = true;
    WidgetsBinding.instance.removeObserver(this);
    _positionRequest.dispose();
    final progress = _progress;
    progress?.removeListener(_progressChanged);
    if (progress != null) {
      final released = widget.catalog.releaseReadingProgress(progress);
      unawaited(released);
    }
    widget.catalog.removeListener(_schedulePreparation);
    final preparationClosed = _preparation.close();
    if (!_viewAttached && !_viewClosed.isCompleted) {
      // setState may install a provider just before a pop removes this route,
      // before the next frame ever mounts its Reader leaf. The route retains
      // ownership until onAttached, so that provider still has a close owner.
      _viewClosed.complete(_opened.provider.close());
    }
    // Child disposal publishes cleanup synchronously; wait through a possible
    // late pages() result as well. Never recycle the runtime to cancel a hop.
    unawaited(() async {
      try {
        await Future.wait<void>([
          _viewClosed.future,
          ?_moving,
          preparationClosed,
        ]);
      } catch (_) {
        // The route has gone; Catalog/runtime errors remain available on return.
      }
    }());
    super.dispose();
  }
}
