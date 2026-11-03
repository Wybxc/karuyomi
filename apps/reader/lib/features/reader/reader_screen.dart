import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/source_runtime.dart';
import 'resource_image.dart';
import 'resource_pool.dart';

typedef ResourceImageBuilder =
    Widget Function(BuildContext context, ImageResource resource, BoxFit fit);

/// Logical viewport state. An observed anchor requires an actually decoded,
/// visible Flutter image; scheduler residency alone never advances reading.
final class ReaderViewportState {
  const ReaderViewportState({
    required this.current,
    required this.observed,
    required this.atEnd,
    required this.windowReady,
  });
  final ReadingPosition current;
  final ReadingPosition? observed;
  final bool atEnd;
  final bool windowReady;
}

/// An online chapter view. Images are exclusively acquired through the Source's
/// PageProvider; this screen never downloads raw Source image URLs itself.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.manifest,
    required this.provider,
    required this.generation,
    this.title = '阅读',
    this.initialPosition,
    this.initialMode = ReadingMode.leftToRight,
    this.doublePage,
    this.onPositionChanged,
    this.imageBuilder = buildResourceImage,
    this.imageEvictor,
    this.onClosed,
    this.onClosing,
    this.chapterControls,
    this.onAttached,
    this.onViewportChanged,
    this.positionRequest,
  });

  final ChapterManifest manifest;
  final PageProvider provider;
  final String generation;
  final String title;
  final ReadingPosition? initialPosition;
  final ReadingMode initialMode;
  final bool? doublePage;
  final ValueChanged<ReadingPosition>? onPositionChanged;
  final ResourceImageBuilder imageBuilder;
  final Future<void> Function(ImageResource)? imageEvictor;

  /// Runs after scheduler cancellation, widget pins and cache eviction finish.
  final Future<void> Function()? onClosed;

  /// Publishes the complete cleanup future as soon as this leaf unmounts.
  final ValueChanged<Future<void>>? onClosing;
  final Widget? chapterControls;
  final VoidCallback? onAttached;
  final ValueChanged<ReaderViewportState>? onViewportChanged;

  /// Explicit navigation such as a persisted reading-epoch reset. It changes
  /// the logical viewport without replacing or reusing a closed provider.
  final ValueListenable<ReadingPosition?>? positionRequest;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final ReaderController _reader;
  late ImageScheduler _scheduler;
  late ReaderResourcePool _resourcePool;
  StreamSubscription<void>? _readerSubscription;
  StreamSubscription<ImageSchedulerSnapshot>? _imagesSubscription;
  final _scroll = ScrollController();
  final _transform = TransformationController();
  final _pointers = <int>{};
  Offset? _dragStart;
  bool _toolbar = true;
  bool _restoring = false;
  double _viewportWidth = 0;
  double _viewportHeight = 0;
  bool _restoreScheduled = false;
  ReadingPosition? _pendingRestorePosition;
  String _windowSignature = '';
  bool _zoomed = false;
  bool _dimensionsScheduled = false;
  bool _viewportScheduled = false;
  final _decodedResources = <String>{};

  @override
  void initState() {
    super.initState();
    widget.onAttached?.call();
    _reader = ReaderController(
      manifest: widget.manifest,
      initialPosition: widget.initialPosition,
      mode: widget.initialMode,
      doublePage: widget.doublePage ?? false,
    );
    _readerSubscription = _reader.changes.listen((_) {
      _syncWindow();
      if (mounted) setState(() {});
      final position = _reader.position;
      if (position != null) widget.onPositionChanged?.call(position);
      _scheduleViewport();
    });
    _attachScheduler();
    _scroll.addListener(_onScroll);
    _transform.addListener(_onTransform);
    widget.positionRequest?.addListener(_applyPositionRequest);
  }

  void _applyPositionRequest() {
    final requested = widget.positionRequest?.value;
    if (requested == null) return;
    if (requested.chapterKey != _reader.manifest.chapterKey) return;
    final resolved = resolvePosition(_reader.manifest, requested).position;
    if (resolved == null) return;
    _restoring = true;
    _transform.value = Matrix4.identity();
    _reader.goToPage(resolved.pageIndexHint, offset: resolved.normalizedOffset);
    _scheduleRestore();
  }

  void _attachScheduler() {
    _windowSignature = '';
    _resourcePool = ReaderResourcePool(
      widget.provider,
      evict: widget.imageEvictor,
    );
    _scheduler = ImageScheduler(provider: _resourcePool);
    _imagesSubscription = _scheduler.changes.listen((_) {
      _scheduleDimensions();
      _scheduleViewport();
      if (mounted) setState(() {});
    });
    _syncWindow();
  }

  void _scheduleViewport() {
    if (_viewportScheduled || widget.onViewportChanged == null) return;
    _viewportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportScheduled = false;
      if (!mounted || _restoring || _reader.position == null) return;
      final snapshot = _scheduler.snapshot;
      final manifest = _reader.manifest;
      if ((!_reader.isContinuous && !_transform.value.isIdentity()) ||
          ModalRoute.of(context)?.isCurrent == false) {
        widget.onViewportChanged?.call(
          ReaderViewportState(
            current: _reader.position!,
            observed: null,
            atEnd: false,
            windowReady: false,
          ),
        );
        return;
      }
      final visible = <int>[];
      var bottomOffset = 1.0;
      var atEnd = false;
      if (_reader.isContinuous) {
        if (!_scroll.hasClients || _viewportHeight <= 0) return;
        final top = _scroll.offset;
        final bottom = top + _viewportHeight;
        final offsets = _offsets;
        for (var index = 0; index < manifest.pages.length; index++) {
          if (offsets[index + 1] > top && offsets[index] < bottom) {
            visible.add(index);
          }
        }
        if (visible.isNotEmpty) {
          final last = visible.last;
          bottomOffset =
              ((bottom - offsets[last]) / _pageHeight(manifest.pages[last]))
                  .clamp(0.0, 1.0);
        }
        atEnd = _scroll.position.extentAfter <= 1;
      } else {
        visible.addAll(
          _reader.spreads[_reader.spreadIndex].pages.map(
            (page) => manifest.pages.indexWhere((item) => item.key == page.key),
          ),
        );
        atEnd = !_reader.canAdvance;
      }
      bool decoded(int index) {
        final image = snapshot.resources[manifest.pages[index].key];
        return image != null && _decodedResources.contains(image.id);
      }

      final shown = visible.where(decoded).toList();
      final allVisible = visible.isNotEmpty && visible.every(decoded);
      final observed = shown.isEmpty
          ? null
          : manifest.positionAt(
              shown.last,
              offset: shown.last == visible.last ? bottomOffset : 1,
            );
      widget.onViewportChanged?.call(
        ReaderViewportState(
          current: _reader.position!,
          observed: observed,
          atEnd: atEnd && allVisible,
          windowReady:
              allVisible &&
              _scheduler.isIdle &&
              snapshot.errors.isEmpty &&
              snapshot.cleanupError == null,
        ),
      );
    });
    // A decoder or another post-frame callback may run after the last frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _scheduleDimensions() {
    if (_dimensionsScheduled) return;
    _dimensionsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dimensionsScheduled = false;
      if (!mounted) return;
      final resources = _scheduler.snapshot.resources;
      var changed = false;
      final pages = _reader.manifest.pages.map((page) {
        final image = resources[page.key];
        if (image == null ||
            (page.width == image.width && page.height == image.height)) {
          return page;
        }
        changed = true;
        return ReaderPage(
          key: page.key,
          width: image.width.toDouble(),
          height: image.height.toDouble(),
        );
      }).toList();
      if (!changed) return;
      // Dimensions are learned layout data, not a change to page identity.
      _restoring = true;
      _pendingRestorePosition = _reader.position;
      _reader.updateManifest(
        ChapterManifest(
          chapterKey: _reader.manifest.chapterKey,
          version: _reader.manifest.version,
          pages: pages,
        ),
      );
      _scheduleRestore();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(ReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionRequest != widget.positionRequest) {
      oldWidget.positionRequest?.removeListener(_applyPositionRequest);
      widget.positionRequest?.addListener(_applyPositionRequest);
    }
    if (oldWidget.provider != widget.provider) {
      unawaited(_imagesSubscription?.cancel());
      final oldScheduler = _scheduler;
      unawaited(() async {
        await oldScheduler.dispose();
        await oldWidget.onClosed?.call();
      }());
      _attachScheduler();
    }
    if (oldWidget.manifest != widget.manifest) {
      _reader.updateManifest(widget.manifest);
      _scheduleRestore();
    }
    if (oldWidget.generation != widget.generation) _syncWindow();
  }

  double get _gap => _reader.mode == ReadingMode.webtoon ? 0 : 12;
  double _pageHeight(ReaderPage page) => _viewportWidth / page.aspectRatio;
  List<double> get _offsets {
    final offsets = <double>[0];
    for (final page in _reader.manifest.pages) {
      offsets.add(offsets.last + _pageHeight(page) + _gap);
    }
    return offsets;
  }

  void _syncWindow() {
    var pages = _reader.imageWindow();
    if (_reader.isContinuous && _viewportWidth > 0 && _viewportHeight > 0) {
      final offsets = _offsets;
      final anchor = _pendingRestorePosition ?? _reader.position;
      final top = _restoring && anchor != null
          ? offsets[anchor.pageIndexHint] +
                _pageHeight(_reader.manifest.pages[anchor.pageIndexHint]) *
                    anchor.normalizedOffset
          : _scroll.hasClients
          ? _scroll.offset
          : 0.0;
      final visible = <ReaderPage>[];
      final forward = <ReaderPage>[];
      final backward = <ReaderPage>[];
      for (var i = 0; i < _reader.manifest.pages.length; i++) {
        final start = offsets[i];
        final end = offsets[i + 1];
        if (end > top && start < top + _viewportHeight) {
          visible.add(_reader.manifest.pages[i]);
        } else if (start >= top + _viewportHeight &&
            start < top + _viewportHeight * 2) {
          forward.add(_reader.manifest.pages[i]);
        } else if (end <= top && end > top - _viewportHeight) {
          backward.add(_reader.manifest.pages[i]);
        }
      }
      pages = [...visible, ...forward, ...backward.reversed];
    }
    final signature = jsonEncode([
      _reader.manifest.chapterKey,
      widget.generation,
      pages.map((page) => [page.key, page.width, page.height]).toList(),
    ]);
    if (_windowSignature == signature) return;
    _windowSignature = signature;
    _scheduler.setWindow(
      chapterKey: _reader.manifest.chapterKey,
      generation: widget.generation,
      pages: pages,
    );
  }

  void _onScroll() {
    if (_restoring || !_scroll.hasClients || _viewportWidth <= 0) return;
    final offsets = _offsets;
    final top = _scroll.offset.clamp(0.0, _scroll.position.maxScrollExtent);
    var index = 0;
    while (index + 1 < offsets.length - 1 && offsets[index + 1] <= top) {
      index++;
    }
    if (_reader.manifest.pages.isEmpty) return;
    final height = _pageHeight(_reader.manifest.pages[index]);
    final offset = ((top - offsets[index]) / height).clamp(0.0, 1.0);
    _reader.updateViewportAnchor(index, offset: offset);
    _syncWindow();
    final position = _reader.position;
    if (position != null) widget.onPositionChanged?.call(position);
    _scheduleViewport();
  }

  void _scheduleRestore() {
    _pendingRestorePosition = _reader.position;
    _restoring = true;
    if (_restoreScheduled) return;
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScheduled = false;
      if (!mounted) return;
      final anchor = _pendingRestorePosition;
      _pendingRestorePosition = null;
      if (_reader.isContinuous && _scroll.hasClients && anchor != null) {
        final offsets = _offsets;
        final index = anchor.pageIndexHint;
        final target =
            offsets[index] +
            _pageHeight(_reader.manifest.pages[index]) *
                anchor.normalizedOffset;
        _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
      }
      _restoring = false;
      _syncWindow();
      _scheduleViewport();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _layout({ReadingMode? mode, bool? doublePage}) {
    _transform.value = Matrix4.identity();
    _reader.setLayout(mode: mode, doublePage: doublePage);
    _scheduleRestore();
  }

  void _goTo(int index) {
    if (_reader.manifest.pages.isEmpty) return;
    _transform.value = Matrix4.identity();
    _reader.goToPage(index);
    _scheduleRestore();
  }

  void _advance() {
    if (!_reader.canAdvance) return;
    _reader.advance();
    _transform.value = Matrix4.identity();
    _scheduleRestore();
  }

  void _back() {
    if (!_reader.canGoBack) return;
    _reader.back();
    _transform.value = Matrix4.identity();
    _scheduleRestore();
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (_zoomed != zoomed && mounted) setState(() => _zoomed = zoomed);
    _scheduleViewport();
  }

  void _zoom(double factor) {
    final scale = _transform.value.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, 5.0);
    _transform.value = Matrix4.diagonal3Values(next, next, 1);
  }

  Widget _image(ReaderPage page, {BoxFit fit = BoxFit.contain}) {
    final snapshot = _scheduler.snapshot;
    final resource = snapshot.resources[page.key];
    if (resource != null) {
      return Semantics(
        label: '第 ${_reader.manifest.pages.indexOf(page) + 1} 页',
        image: true,
        child: NotificationListener<ReaderImageDecoded>(
          onNotification: (notification) {
            if (notification.resourceId == resource.id &&
                _decodedResources.add(resource.id)) {
              _scheduleViewport();
            }
            return true;
          },
          child: PinnedReaderImage(
            key: ValueKey('display-${resource.id}'),
            pool: _resourcePool,
            image: resource,
            builder: (context) => widget.imageBuilder(context, resource, fit),
          ),
        ),
      );
    }
    if (snapshot.cleanupError != null) {
      return const Center(child: Text('图片资源清理失败，请重新打开章节。'));
    }
    if (snapshot.errors.containsKey(page.key)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(switch (snapshot.errors[page.key]) {
              RuntimeException(code: RuntimeErrorCode.unsupportedCapability) =>
                '当前平台尚未支持图片阅读',
              RuntimeException(code: RuntimeErrorCode.accessRequired) =>
                '访问验证已失效，请返回重新登录',
              RuntimeException(code: RuntimeErrorCode.runtimeLost) =>
                '漫画源已中断，请返回重新连接',
              ImageBudgetExceeded(:final message) => message,
              _ => '图片未能加载',
            }),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => _scheduler.retry(page.key),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return snapshot.loading.contains(page.key)
        ? const Center(child: CircularProgressIndicator())
        : const SizedBox.shrink();
  }

  void _openZoom(ReaderPage page) {
    final resource = _scheduler.snapshot.resources[page.key];
    if (resource == null) return;
    final pool = _resourcePool;
    final pin = pool.pin(resource.id);
    unawaited(
      showDialog<void>(
        context: context,
        useSafeArea: true,
        builder: (context) => _ZoomImageDialog(
          resource: resource,
          pool: pool,
          imageBuilder: widget.imageBuilder,
        ),
      ).whenComplete(pin.close),
    );
  }

  Widget _continuous() => ListView.builder(
    key: const ValueKey('continuous-reader'),
    controller: _scroll,
    scrollCacheExtent: const ScrollCacheExtent.viewport(1),
    itemCount: _reader.manifest.pages.length,
    itemExtentBuilder: (index, dimensions) =>
        _pageHeight(_reader.manifest.pages[index]) + _gap,
    itemBuilder: (context, index) {
      final page = _reader.manifest.pages[index];
      return Padding(
        padding: EdgeInsets.only(bottom: _gap),
        child: GestureDetector(
          onDoubleTap: () => _openZoom(page),
          child: SizedBox(width: _viewportWidth, child: _image(page)),
        ),
      );
    },
  );

  Widget _paged() {
    final spread = _reader.spreads[_reader.spreadIndex];
    return Listener(
      onPointerDown: (event) {
        _pointers.add(event.pointer);
        if (_pointers.length == 1 &&
            _transform.value.getMaxScaleOnAxis() == 1) {
          _dragStart = event.position;
        } else {
          _dragStart = null;
        }
      },
      onPointerUp: (event) {
        final start = _dragStart;
        _pointers.remove(event.pointer);
        _dragStart = null;
        if (start == null || _transform.value.getMaxScaleOnAxis() > 1.01) {
          return;
        }
        final delta = event.position - start;
        if (delta.dx.abs() < 60 || delta.dx.abs() < delta.dy.abs()) return;
        final forward = _reader.mode == ReadingMode.rightToLeft
            ? delta.dx > 0
            : delta.dx < 0;
        forward ? _advance() : _back();
      },
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        _dragStart = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () =>
            _zoom(_transform.value.getMaxScaleOnAxis() > 1 ? 0.2 : 2),
        onTapUp: (details) {
          if (_transform.value.getMaxScaleOnAxis() > 1.01) return;
          final fraction = details.localPosition.dx / _viewportWidth;
          if (fraction > 1 / 3 && fraction < 2 / 3) {
            setState(() => _toolbar = !_toolbar);
          } else {
            final forward = _reader.mode == ReadingMode.rightToLeft
                ? fraction < 1 / 3
                : fraction > 2 / 3;
            forward ? _advance() : _back();
          }
        },
        child: InteractiveViewer(
          key: ValueKey('spread-${spread.pages.first.key}'),
          transformationController: _transform,
          minScale: 1,
          maxScale: 5,
          panEnabled: _transform.value.getMaxScaleOnAxis() > 1.01,
          child: Row(
            textDirection: TextDirection.ltr,
            children: [
              for (final page in spread.displayPages(_reader.mode))
                Expanded(child: _image(page)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
          _reader.mode == ReadingMode.rightToLeft ? _back() : _advance(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
          _reader.mode == ReadingMode.rightToLeft ? _advance() : _back(),
      const SingleActivator(LogicalKeyboardKey.pageDown): _advance,
      const SingleActivator(LogicalKeyboardKey.space): _advance,
      const SingleActivator(LogicalKeyboardKey.pageUp): _back,
      const SingleActivator(LogicalKeyboardKey.home): () => _goTo(0),
      const SingleActivator(LogicalKeyboardKey.end): () =>
          _goTo(_reader.manifest.pages.length - 1),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _toolbar ? AppBar(title: Text(widget.title)) : null,
        body: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: SafeArea(
            child: Column(
              children: [
                if (_reader.requiresPositionNotice)
                  const MaterialBanner(
                    content: Text('页面清单发生变化，已定位到最接近的页码。'),
                    actions: [SizedBox.shrink()],
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (_viewportWidth != constraints.maxWidth ||
                          _viewportHeight != constraints.maxHeight) {
                        _viewportWidth = constraints.maxWidth;
                        _viewportHeight = constraints.maxHeight;
                        _scheduleRestore();
                        final doublePage =
                            widget.doublePage ?? constraints.maxWidth >= 900;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          if (_reader.doublePage != doublePage) {
                            _reader.setLayout(doublePage: doublePage);
                          }
                          _scheduleRestore();
                        });
                      }
                      if (_reader.manifest.pages.isEmpty) {
                        return const Center(
                          child: Text(
                            '这一章没有页面',
                            style: TextStyle(color: Colors.white),
                          ),
                        );
                      }
                      return _reader.isContinuous ? _continuous() : _paged();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _toolbar ? _controls() : null,
      ),
    ),
  );

  Widget _controls() => Material(
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '上一页',
                  onPressed: _reader.canGoBack ? _back : null,
                  icon: const Icon(Icons.skip_previous),
                ),
                Expanded(
                  child: Text(
                    _reader.position == null
                        ? '0 / 0'
                        : '${_reader.pageIndex + 1} / ${_reader.manifest.pages.length}',
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  tooltip: '下一页',
                  onPressed: _reader.canAdvance ? _advance : null,
                  icon: const Icon(Icons.skip_next),
                ),
                if (_reader.isContinuous)
                  IconButton(
                    tooltip: '放大当前图片',
                    onPressed: _reader.position == null
                        ? null
                        : () => _openZoom(
                            _reader.manifest.pages[_reader.pageIndex],
                          ),
                    icon: const Icon(Icons.zoom_in),
                  ),
                if (!_reader.isContinuous) ...[
                  IconButton(
                    tooltip: '缩小',
                    onPressed: () => _zoom(0.5),
                    icon: const Icon(Icons.zoom_out),
                  ),
                  IconButton(
                    tooltip: '放大',
                    onPressed: () => _zoom(2),
                    icon: const Icon(Icons.zoom_in),
                  ),
                  IconButton(
                    tooltip: '重置缩放',
                    onPressed: () => _transform.value = Matrix4.identity(),
                    icon: const Icon(Icons.fit_screen),
                  ),
                ],
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<ReadingMode>(
                    value: _reader.mode,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                        value: ReadingMode.leftToRight,
                        child: Text('从左到右'),
                      ),
                      DropdownMenuItem(
                        value: ReadingMode.rightToLeft,
                        child: Text('从右到左'),
                      ),
                      DropdownMenuItem(
                        value: ReadingMode.continuous,
                        child: Text('竖向连续'),
                      ),
                      DropdownMenuItem(
                        value: ReadingMode.webtoon,
                        child: Text('条漫'),
                      ),
                    ],
                    onChanged: (mode) {
                      if (mode != null) _layout(mode: mode);
                    },
                  ),
                ),
                if (!_reader.isContinuous)
                  FilterChip(
                    label: const Text('双页'),
                    selected: _reader.doublePage,
                    onSelected: (value) => _layout(doublePage: value),
                  ),
              ],
            ),
            if (widget.chapterControls case final Widget controls) controls,
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    widget.positionRequest?.removeListener(_applyPositionRequest);
    final position = _reader.position;
    if (position != null) widget.onPositionChanged?.call(position);
    unawaited(_readerSubscription?.cancel());
    unawaited(_imagesSubscription?.cancel());
    final scheduler = _scheduler;
    final onClosed = widget.onClosed;
    final cleanup = () async {
      await scheduler.dispose();
      await onClosed?.call();
    }();
    widget.onClosing?.call(cleanup);
    unawaited(cleanup);
    unawaited(_reader.dispose());
    _scroll.dispose();
    _transform.dispose();
    super.dispose();
  }
}

class _ZoomImageDialog extends StatefulWidget {
  const _ZoomImageDialog({
    required this.resource,
    required this.pool,
    required this.imageBuilder,
  });
  final ImageResource resource;
  final ReaderResourcePool pool;
  final ResourceImageBuilder imageBuilder;

  @override
  State<_ZoomImageDialog> createState() => _ZoomImageDialogState();
}

class _ZoomImageDialogState extends State<_ZoomImageDialog> {
  final _transform = TransformationController();

  void _zoom(double factor) {
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      5.0,
    );
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: const Text('查看图片'),
        actions: [
          IconButton(
            tooltip: '缩小',
            onPressed: () => _zoom(0.5),
            icon: const Icon(Icons.zoom_out),
          ),
          IconButton(
            tooltip: '放大',
            onPressed: () => _zoom(2),
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            tooltip: '重置缩放',
            onPressed: () => _transform.value = Matrix4.identity(),
            icon: const Icon(Icons.fit_screen),
          ),
        ],
      ),
      body: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: PinnedReaderImage(
            pool: widget.pool,
            image: widget.resource,
            builder: (context) =>
                widget.imageBuilder(context, widget.resource, BoxFit.contain),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }
}
