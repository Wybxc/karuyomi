import 'dart:async';

import 'package:flutter/material.dart';

import '../browse/catalog_controller.dart';
import 'chapter_sequence.dart';
import 'reader_screen.dart';

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

class _ChapterReaderRouteState extends State<ChapterReaderRoute> {
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
      next = await widget.catalog.openChapter(
        widget.manga,
        ChapterEntry(target.snapshot),
        reference: widget.source,
        logicalChapterKey: target.key,
      );
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
      if (!widget.catalog.isCurrentSource(widget.source)) {
        throw StateError('Source session expired during chapter transition');
      }
      setState(() {
        _opened = next!;
        _chapter = target;
        _viewClosed = Completer<void>();
        _viewAttached = false;
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
        if (_error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
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
                        if (order != null) setState(() => _order = order);
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

  @override
  Widget build(BuildContext context) {
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
      chapterControls: _chapterControls(),
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
        await _viewClosed.future;
        await _moving;
      } catch (_) {
        // The route has gone; Catalog/runtime errors remain available on return.
      }
    }());
    super.dispose();
  }
}
