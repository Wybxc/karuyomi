import '../../theme/app_theme.dart';
import '../../widgets/app_routes.dart';
import '../../widgets/choice_field.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/source_runtime.dart';

import '../../diagnostics/reader_baseline.dart';
import 'reader_page_navigation.dart';
import 'reader_preferences.dart';
import 'resource_image.dart';
import 'resource_pool.dart';

typedef ResourceImageBuilder = Widget Function(
  BuildContext context,
  ImageResource resource,
  BoxFit fit,
);

/// Logical viewport state. An observed anchor requires an actually decoded,
/// visible Flutter image; scheduler residency alone never advances reading.
final class ReaderViewportState {
  const ReaderViewportState({
    required this.current,
    required this.observed,
    required this.atEnd,
    required this.windowReady,
    this.mode = ReadingMode.leftToRight,
    this.doublePage,
  });
  final ReadingPosition current;
  final ReadingPosition? observed;
  final bool atEnd;
  final bool windowReady;
  final ReadingMode mode;
  final bool? doublePage;
}

enum ReaderChapterEdge {
  previous(-1),
  next(1);

  const ReaderChapterEdge(this.delta);
  final int delta;
}

class const ReaderChapterTransition({
  super.key,
  required final ReaderChapterEdge edge,
  required final ({String name, String scanlator}) currentChapter,
  required final ({String name, String scanlator})? targetChapter,
  required final ReaderBackground background,
  required final int dimPercent,
  required final bool loading,
  required final String? error,
  required final VoidCallback? onContinue,
  required final VoidCallback? onRetry,
  required final VoidCallback? onReturn,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final previous = edge == ReaderChapterEdge.previous;
    final direction = previous ? '上一章' : '下一章';
    final foreground = _readerForegroundColor(context, background);
    final secondary = foreground.withValues(alpha: .75);
    final theme = CupertinoTheme.of(context).textTheme;
    final body = theme.textStyle.copyWith(color: foreground);
    final caption = theme.actionSmallTextStyle.copyWith(color: secondary);
    const actionTarget = Size.square(kMinInteractiveDimensionCupertino);

    Widget chapter(String label, ({String name, String scanlator}) entry) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: caption),
            const SizedBox(height: 4),
            Text(entry.name, style: body),
            if (entry.scanlator.trim().isNotEmpty)
              Text(entry.scanlator, style: caption),
          ],
        );

    final target = targetChapter;
    final neighbor = target == null
        ? Text(
            previous ? '前面没有章节' : '后面没有章节',
            style: caption,
            textAlign: TextAlign.center,
          )
        : chapter(direction, target);
    return _ReaderContent(
      background: background,
      dimPercent: dimPercent,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final scale = MediaQuery.textScalerOf(context).scale(17) / 17;
          final inset = (bounds.maxWidth * (scale > 1.5 ? .08 : .18)).clamp(
            12.0,
            64.0,
          );
          final chapterSpacing = (bounds.maxHeight * .07 / scale).clamp(
            24.0,
            56.0,
          );
          return Center(
            child: SingleChildScrollView(
              primary: false,
              padding: EdgeInsets.symmetric(horizontal: inset, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Semantics(
                  container: true,
                  label: '章节过渡',
                  explicitChildNodes: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (previous) neighbor else chapter('本章', currentChapter),
                      SizedBox(height: chapterSpacing),
                      if (previous) chapter('本章', currentChapter) else neighbor,
                      if (loading) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CupertinoActivityIndicator(color: secondary),
                              const SizedBox(height: 8),
                              Text(
                                '正在加载章节页面',
                                style: caption,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (error case final message?) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            message,
                            style: caption.copyWith(
                              color: AppColors.error.resolveFrom(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          CupertinoButton(
                            sizeStyle: CupertinoButtonSize.medium,
                            minimumSize: actionTarget,
                            autofocus: onReturn != null,
                            onPressed: onReturn,
                            child: const Text('返回本章'),
                          ),
                          if (onRetry != null)
                            CupertinoButton.filled(
                              sizeStyle: CupertinoButtonSize.medium,
                              minimumSize: actionTarget,
                              onPressed: onRetry,
                              child: const Text('重试'),
                            )
                          else if (onContinue != null)
                            CupertinoButton.filled(
                              sizeStyle: CupertinoButtonSize.medium,
                              minimumSize: actionTarget,
                              onPressed: onContinue,
                              child: Text('进入$direction'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// An online chapter view. Images are exclusively acquired through the Source's
/// PageProvider; this screen never downloads raw Source image URLs itself.
class const ReaderScreen({
  super.key,
  required final ChapterManifest manifest,
  required final PageProvider provider,
  required final String generation,
  final String title = '阅读',
  final String? subtitle,
  final Widget? chapterActions,
  final ReadingPosition? initialPosition,

  /// A confirmed resume can render at a clamped placement without replacing
  /// the saved preference merely because its images just finished laying out.
  final bool preserveInitialPlacement = false,
  final ReadingMode initialMode = ReadingMode.leftToRight,

  /// Defaults to automatic width-based layout. An in-reader selection lasts for
  /// this chapter unless this input changes; changing to null resumes automatic.
  final bool? doublePage,
  final ReaderFit fit = ReaderFit.contain,
  final bool cropBorders = false,
  final ReaderBackground background = ReaderBackground.black,

  /// Application content dimming only; never changes system screen brightness.
  final int dimPercent = 0,
  final ReaderInputPreset tapZones = ReaderInputPreset.standard,
  final ReaderInputPreset keyboard = ReaderInputPreset.standard,

  /// User selections only; applying parent settings and resizing do not save.
  final ValueChanged<ReadingMode>? onModeChanged,
  final ValueChanged<bool?>? onDoublePageChanged,

  /// Only disables settings edits; chapter navigation and zoom remain usable.
  final bool layoutSettingsEnabled = true,
  final ValueChanged<ReadingPosition>? onPositionChanged,
  final ResourceImageBuilder imageBuilder = buildResourceImage,
  final Future<void> Function(ImageResource)? imageEvictor,

  /// Runs after scheduler cancellation, widget pins and cache eviction finish.
  final Future<void> Function()? onClosed,

  /// Publishes the complete cleanup future as soon as this leaf unmounts.
  final ValueChanged<Future<void>>? onClosing,
  final ({Widget previous, Widget next})? chapterNavigation,
  final Widget? chapterControls,
  final Widget? readingSettings,
  final VoidCallback? onAttached,
  final VoidCallback? onExit,
  final ReaderChapterTransition? chapterTransition,
  final ValueChanged<ReaderChapterEdge>? onChapterEdge,
  final ValueChanged<ReaderViewportState>? onViewportChanged,

  /// Explicit navigation such as a persisted reading-epoch reset. It changes
  /// the logical viewport without replacing or reusing a closed provider.
  final ValueListenable<ReadingPosition?>? positionRequest,

  /// Access loss freezes production while retaining the displayed resources.
  final bool paused = false,
}) extends StatefulHookWidget {
  this : assert(dimPercent >= 0 && dimPercent <= 80);

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

typedef _ReaderAppearance = ({
  ReaderBackground background,
  int dimPercent,
  ReaderFit fit,
  bool cropBorders,
  Map<String, _ImageCrop> crops,
});

class _ReaderScreenState extends State<ReaderScreen> {
  late ValueNotifier<_ReaderAppearance> _appearance;
  ReaderBaselineRecorder? _baseline;
  int _navigationEpoch = 0;
  late final ReaderController _reader;
  late ImageScheduler _scheduler;
  late ReaderResourcePool _resourcePool;
  late ScrollController _scroll;
  late TransformationController _transform;
  late AnimationController _toolbarAnimation;
  final _horizontal = <String, ScrollController>{};
  final _pointers = <int>{};
  Offset? _dragStart;
  double _edgePull = 0;
  bool _toolbar = true;
  bool _restoring = false;
  late ReadingPosition? _preferredPlacement = widget.preserveInitialPlacement
      ? widget.initialPosition
      : null;
  double _viewportWidth = 0;
  double _viewportHeight = 0;
  double? _pageCenterY;
  Size? _windowSize;
  int _restoreEpoch = 0;
  ReadingPosition? _pendingRestorePosition;
  String _windowSignature = '';
  bool _zoomed = false;
  bool _dimensionsScheduled = false;
  bool _viewportScheduled = false;
  late bool? _doublePagePreference;
  final _decodedResources = <String>{};
  final _learnedDimensions = <String, ImageDimensions>{};
  final _crops = <String, _ImageCrop>{};
  bool _resetCropGeometry = false;

  void _initialize() {
    _baseline = ReaderBaselineScope.read(context);
    _baseline?.event('reader_attached', {
      'chapterKey': widget.manifest.chapterKey,
      'generation': widget.generation,
    });
    widget.onAttached?.call();
    _doublePagePreference = widget.doublePage;
    _reader = ReaderController(
      manifest: widget.manifest,
      initialPosition: widget.initialPosition,
      mode: widget.initialMode,
      doublePage: widget.doublePage ?? false,
    );
    if (widget.initialPosition == null && _reader.position != null) {
      _reader.goToPage(0, normalizedX: _leadingX, viewportX: _leadingX);
    }
    _attachScheduler();
  }

  void _readerChanged() {
    _syncWindow();
    if (mounted) setState(() {});
    final position = _reader.position;
    if (position != null) widget.onPositionChanged?.call(position);
    _scheduleViewport();
  }

  void _applyPositionRequest() {
    final requested = widget.positionRequest?.value;
    if (requested == null) return;
    if (requested.chapterKey != _reader.manifest.chapterKey) return;
    final resolved = resolvePosition(_reader.manifest, requested).position;
    if (resolved == null) return;
    _preferredPlacement = null;
    _navigation('position_request', {
      'targetPageKey': resolved.pageKey,
      'targetIndex': resolved.pageIndexHint,
    });
    _restoring = true;
    _transform.value = Matrix4.identity();
    _reader.goToPage(
      resolved.pageIndexHint,
      offset: resolved.normalizedOffset,
      normalizedX: resolved.normalizedX,
      viewportX: resolved.viewportX,
      viewportY: resolved.viewportY,
    );
    _scheduleRestore();
  }

  void _attachScheduler() {
    _windowSignature = '';
    _decodedResources.clear();
    _learnedDimensions.clear();
    _crops.clear();
    _resetCropGeometry = true;
    _resourcePool = ReaderResourcePool(
      widget.provider,
      evict: widget.imageEvictor,
      baseline: _baseline,
    );
    _scheduler = ImageScheduler(provider: _resourcePool);
    _scheduler.setPaused(widget.paused);
    _syncWindow();
    _publishAppearance();
  }

  void _imagesChanged(ImageSchedulerSnapshot snapshot) {
    final residentIds = snapshot.resources.values
        .map((image) => image.id)
        .toSet();
    _decodedResources.removeWhere((id) => !residentIds.contains(id));
    final cropCount = _crops.length;
    _crops.removeWhere(
      (id, crop) =>
          !residentIds.contains(id) ||
          snapshot.dimensions[id]?.width != crop.width ||
          snapshot.dimensions[id]?.height != crop.height,
    );
    if (cropCount != _crops.length) _publishAppearance();
    _scheduleDimensions();
    _scheduleViewport();
    if (mounted) setState(() {});
  }

  void _scheduleViewport() {
    if (_viewportScheduled ||
        (widget.onViewportChanged == null && _baseline?.recording != true)) {
      return;
    }
    _viewportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportScheduled = false;
      if (!mounted ||
          _restoring ||
          widget.chapterTransition != null ||
          _reader.position == null) {
        return;
      }
      final snapshot = _scheduler.snapshot;
      final manifest = _reader.manifest;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _recordViewport(const [], snapshot, blocked: true);
        widget.onViewportChanged?.call(
          ReaderViewportState(
            current: _reader.position!,
            observed: null,
            atEnd: false,
            windowReady: false,
            mode: _reader.mode,
            doublePage: _doublePagePreference,
          ),
        );
        return;
      }
      final images = _visibleImages;
      final visible = images.map((image) => image.index).toList();
      bool decoded(_VisibleImage image) => _hasDecodedGeometry(image.index);

      final shown = images.where(decoded).toList();
      final allVisible = images.isNotEmpty && images.every(decoded);
      final last = shown.isEmpty ? null : shown.last;
      final observed = last == null
          ? null
          : _positionInImage(
              last,
              Offset(
                _leadingX == 1 ? last.visible.left : last.visible.right,
                last.visible.bottom,
              ),
            );
      final terminal = shown
          .where((image) => image.index == manifest.pages.length - 1)
          .firstOrNull;
      final atEnd =
          terminal != null &&
          (Offset.zero & Size(_viewportWidth, _viewportHeight))
              .inflate(1)
              .contains(
                Offset(
                  _leadingX == 1 ? terminal.rect.left : terminal.rect.right,
                  terminal.rect.bottom,
                ),
              );
      _recordViewport(visible, snapshot);
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
          mode: _reader.mode,
          doublePage: _doublePagePreference,
        ),
      );
    });
    // A decoder or another post-frame callback may run after the last frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _recordViewport(
    List<int> visible,
    ImageSchedulerSnapshot snapshot, {
    bool blocked = false,
  }) {
    final baseline = _baseline;
    if (baseline?.recording != true) return;
    final position = _reader.position;
    baseline!.event('viewport', {
      'chapterKey': _reader.manifest.chapterKey,
      'generation': widget.generation,
      'frameNumber': ui.PlatformDispatcher.instance.frameData.frameNumber,
      'viewportWidth': _viewportWidth,
      'viewportHeight': _viewportHeight,
      'scrollOffset': _scroll.hasClients ? _scroll.offset : null,
      'mode': _reader.mode.name,
      'blockedByRouteOrTransform': blocked,
      'navigationEpoch': _navigationEpoch,
      'manifestVersion': _reader.manifest.version,
      'currentPageKey': position?.pageKey,
      'currentIndex': position?.pageIndexHint,
      'normalizedOffset': position?.normalizedOffset,
      'normalizedX': position?.normalizedX,
      'viewportX': position?.viewportX,
      'viewportY': position?.viewportY,
      'fit': widget.fit.name,
      'cropBorders': widget.cropBorders,
      'visible': [
        for (final index in visible)
          {
            'pageKey': _reader.manifest.pages[index].key,
            'index': index,
            'resourceId':
                snapshot.resources[_reader.manifest.pages[index].key]?.id,
            'resourceGeneration': snapshot
                .resources[_reader.manifest.pages[index].key]
                ?.generation,
            'decoded': _decodedResources.contains(
              snapshot.resources[_reader.manifest.pages[index].key]?.id,
            ),
          },
      ],
    });
  }

  void _navigation(String action, [Map<String, Object?> data = const {}]) {
    if (_baseline?.recording != true) return;
    final index = data['targetIndex'];
    _baseline!.event('navigation', {
      'action': action,
      'chapterKey': _reader.manifest.chapterKey,
      'generation': widget.generation,
      'fromPageKey': _reader.position?.pageKey,
      'manifestVersion': _reader.manifest.version,
      'navigationEpoch': ++_navigationEpoch,
      if (index is int && index >= 0 && index < _reader.manifest.pages.length)
        'targetPageKey': _reader.manifest.pages[index].key,
      ...data,
    });
  }

  void _scheduleDimensions() {
    if (_dimensionsScheduled) return;
    _dimensionsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dimensionsScheduled = false;
      if (!mounted) return;
      final snapshot = _scheduler.snapshot;
      final resources = snapshot.resources;
      var changed = false;
      final pages = _reader.manifest.pages.map((page) {
        final image = resources[page.key];
        final dimensions =
            _learnedDimensions[page.key] ??
            (image == null ? null : snapshot.dimensions[image.id]);
        final width = dimensions?.width.toDouble() ?? page.width;
        final height = dimensions?.height.toDouble() ?? page.height;
        final crop = image == null ? null : _acceptedCrop(image.id);
        // Keep already learned list geometry when a page leaves the resource
        // window. A new resource remains unobservable until its own ROI arrives.
        final ratio = !widget.cropBorders
            ? null
            : crop != null && width != null && height != null
            ? width / height * crop.bounds.width / crop.bounds.height
            : _resetCropGeometry
            ? null
            : page.contentAspectRatio;
        if (page.width == width &&
            page.height == height &&
            page.contentAspectRatio == ratio) {
          return page;
        }
        changed = true;
        return ReaderPage(
          key: page.key,
          width: width,
          height: height,
          contentAspectRatio: ratio,
        );
      }).toList();
      _resetCropGeometry = false;
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
    if (oldWidget.chapterTransition != null &&
        widget.chapterTransition == null) {
      _scheduleViewport();
    }
    if (oldWidget.background != widget.background ||
        oldWidget.dimPercent != widget.dimPercent ||
        oldWidget.fit != widget.fit ||
        oldWidget.cropBorders != widget.cropBorders) {
      _publishAppearance();
    }
    if (oldWidget.fit != widget.fit ||
        oldWidget.cropBorders != widget.cropBorders) {
      _restoring = true;
      _transform.value = Matrix4.identity();
      _scheduleDimensions();
      _scheduleRestore();
    }
    _scheduler.setPaused(widget.paused);
    if (oldWidget.provider != widget.provider) {
      final oldScheduler = _scheduler;
      unawaited(() async {
        await oldScheduler.dispose();
        await oldWidget.onClosed?.call();
      }());
      _attachScheduler();
    }
    if (oldWidget.manifest != widget.manifest) {
      if (oldWidget.manifest.chapterKey != widget.manifest.chapterKey ||
          oldWidget.manifest.version != widget.manifest.version) {
        _learnedDimensions.clear();
        _crops.clear();
        _resetCropGeometry = true;
        _publishAppearance();
      }
      _reader.updateManifest(widget.manifest);
      if (!_toolbar && _reader.position == null) {
        _toolbar = true;
        _toolbarAnimation.value = 1;
      }
      _scheduleDimensions();
      _scheduleRestore();
    }
    if (oldWidget.doublePage != widget.doublePage ||
        oldWidget.manifest.chapterKey != widget.manifest.chapterKey) {
      _doublePagePreference = widget.doublePage;
      _applyDoublePagePreference();
    }
    if (oldWidget.initialMode != widget.initialMode ||
        oldWidget.manifest.chapterKey != widget.manifest.chapterKey) {
      _applyMode(widget.initialMode);
    }
    if (oldWidget.generation != widget.generation) {
      _learnedDimensions.clear();
      _crops.clear();
      _resetCropGeometry = true;
      _publishAppearance();
      _scheduleDimensions();
      _scheduleRestore();
      _syncWindow();
    }
  }

  void _publishAppearance() {
    // An open zoom route is a sibling; never dirty it in the Reader's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _appearance.value = (
        background: widget.background,
        dimPercent: widget.dimPercent,
        fit: widget.fit,
        cropBorders: widget.cropBorders,
        crops: Map.unmodifiable({
          for (final id in _crops.keys)
            if (_acceptedCrop(id) case final _ImageCrop crop) id: crop,
        }),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  _ImageCrop? _acceptedCrop(String id) {
    final crop = _crops[id];
    final dimensions = _scheduler.snapshot.dimensions[id];
    return crop != null &&
            dimensions?.width == crop.width &&
            dimensions?.height == crop.height
        ? crop
        : null;
  }

  Rect _cropBounds(ReaderPage page) {
    if (!widget.cropBorders) return _fullImage;
    final resource = _scheduler.snapshot.resources[page.key];
    return resource == null
        ? _fullImage
        : _acceptedCrop(resource.id)?.bounds ?? _fullImage;
  }

  void _acceptCrop(
    String pageKey,
    ImageResource expected,
    ReaderImageCrop notification,
  ) {
    if (!widget.cropBorders ||
        notification.resourceId != expected.id ||
        expected.generation != widget.generation ||
        !_validCrop(notification.bounds)) {
      return;
    }
    final snapshot = _scheduler.snapshot;
    final current = snapshot.resources[pageKey];
    final dimensions = snapshot.dimensions[expected.id];
    if (current?.id != expected.id ||
        current?.generation != widget.generation ||
        !_decodedResources.contains(expected.id) ||
        dimensions?.width != notification.width ||
        dimensions?.height != notification.height) {
      return;
    }
    final crop = _ImageCrop(
      notification.bounds,
      notification.width,
      notification.height,
    );
    final previous = _crops[expected.id];
    if (previous?.bounds == crop.bounds &&
        previous?.width == crop.width &&
        previous?.height == crop.height) {
      return;
    }
    _crops[expected.id] = crop;
    _restoring = true;
    _scheduleDimensions();
    _scheduleRestore();
    _publishAppearance();
    setState(() {});
  }

  double get _leadingX => _reader.mode == ReadingMode.rightToLeft ? 1 : 0;
  double get _gap => _reader.mode == ReadingMode.webtoon ? 0 : 12;
  Size get _viewport => Size(_viewportWidth, _viewportHeight);
  Size _pageSize(ReaderPage page, {double? width}) => _fitImageSize(
    page.aspectRatio,
    Size(width ?? _viewportWidth, _viewportHeight),
    widget.fit,
  );
  double _pageHeight(ReaderPage page) => _pageSize(page).height;
  List<double> get _offsets {
    final offsets = <double>[0];
    for (final page in _reader.manifest.pages) {
      offsets.add(offsets.last + _pageHeight(page) + _gap);
    }
    return offsets;
  }

  _ReaderScene get _pagedScene => _spreadScene(
    _reader.spreads[_reader.spreadIndex].displayPages(_reader.mode),
    _viewport,
    widget.fit,
    centerY: _pageCenterY,
  );

  double _horizontalOffset(String key) {
    final controller = _horizontal[key];
    return controller != null && controller.hasClients ? controller.offset : 0;
  }

  List<_VisibleImage> get _visibleImages {
    if (_viewportWidth <= 0 || _viewportHeight <= 0) return const [];
    final viewport = Offset.zero & _viewport;
    final rects = <String, Rect>{};
    if (_reader.isContinuous) {
      if (!_scroll.hasClients) return const [];
      final offsets = _offsets;
      for (var index = 0; index < _reader.manifest.pages.length; index++) {
        final page = _reader.manifest.pages[index];
        final size = _pageSize(page);
        final rect = Rect.fromLTWH(
          math.max(0, (_viewportWidth - size.width) / 2) -
              _horizontalOffset(page.key),
          offsets[index] - _scroll.offset,
          size.width,
          size.height,
        );
        if (rect.overlaps(viewport)) rects[page.key] = rect;
      }
    } else {
      for (final entry in _pagedScene.images.entries) {
        rects[entry.key] = MatrixUtils.transformRect(
          _transform.value,
          entry.value,
        );
      }
    }
    return [
      for (var index = 0; index < _reader.manifest.pages.length; index++)
        if (rects[_reader.manifest.pages[index].key] case final Rect rect)
          if (rect.overlaps(viewport))
            _VisibleImage(index, rect, rect.intersect(viewport)),
    ];
  }

  bool _hasDecodedGeometry(int index) {
    final page = _reader.manifest.pages[index];
    final snapshot = _scheduler.snapshot;
    final resource = snapshot.resources[page.key];
    final dimensions = resource == null
        ? null
        : snapshot.dimensions[resource.id];
    return resource != null &&
        resource.generation == widget.generation &&
        _decodedResources.contains(resource.id) &&
        dimensions != null &&
        page.width == dimensions.width &&
        page.height == dimensions.height &&
        (!widget.cropBorders || _acceptedCrop(resource.id) != null);
  }

  ReadingPosition _positionInImage(_VisibleImage image, Offset point) {
    final crop = _cropBounds(_reader.manifest.pages[image.index]);
    return _reader.manifest.positionAt(
      image.index,
      offset:
          crop.top +
          ((point.dy - image.rect.top) / image.rect.height).clamp(0.0, 1.0) *
              crop.height,
      normalizedX:
          crop.left +
          ((point.dx - image.rect.left) / image.rect.width).clamp(0.0, 1.0) *
              crop.width,
      viewportX: (point.dx / _viewportWidth).clamp(0.0, 1.0),
      viewportY: (point.dy / _viewportHeight).clamp(0.0, 1.0),
    );
  }

  Offset _pointWithinCrop(ReadingPosition anchor) {
    final crop = _cropBounds(_reader.manifest.pages[anchor.pageIndexHint]);
    return Offset(
      ((anchor.normalizedX - crop.left) / crop.width).clamp(0.0, 1.0),
      ((anchor.normalizedOffset - crop.top) / crop.height).clamp(0.0, 1.0),
    );
  }

  void _setViewportPosition(ReadingPosition position) {
    final previous = _reader.position;
    if (previous != null && _sameAnchor(previous, position)) return;
    _preferredPlacement = null;
    _reader.updateViewportAnchor(
      position.pageIndexHint,
      offset: position.normalizedOffset,
      normalizedX: position.normalizedX,
      viewportX: position.viewportX,
      viewportY: position.viewportY,
    );
    // The controller publishes page changes; movement within a page is quiet.
    if (previous?.pageKey == position.pageKey) {
      widget.onPositionChanged?.call(position);
    }
  }

  void _confirmViewportAnchor(
    ReadingPosition anchor, {
    bool preservePlacement = false,
  }) {
    if (!_hasDecodedGeometry(anchor.pageIndexHint)) return;
    final image = _visibleImages
        .where((image) => image.index == anchor.pageIndexHint)
        .firstOrNull;
    if (image == null) return;
    final normalized = _pointWithinCrop(anchor);
    final crop = _cropBounds(_reader.manifest.pages[anchor.pageIndexHint]);
    final original = Offset(
      crop.left + crop.width * normalized.dx,
      crop.top + crop.height * normalized.dy,
    );
    final point = Offset(
      image.rect.left + image.rect.width * normalized.dx,
      image.rect.top + image.rect.height * normalized.dy,
    );
    if (!(Offset.zero & _viewport).inflate(1).contains(point)) {
      // A user may have panned before the first decoded frame. Only now can
      // that visible point be sampled in genuine original-image coordinates.
      _captureViewportAnchor();
      return;
    }
    final preferred = _preferredPlacement;
    final keepPreferred = preferred != null && _sameAnchor(anchor, preferred);
    if ((preservePlacement || keepPreferred) &&
        anchor.normalizedX >= crop.left &&
        anchor.normalizedX <= crop.right &&
        anchor.normalizedOffset >= crop.top &&
        anchor.normalizedOffset <= crop.bottom) {
      // Layout can clamp the same original point while resuming, turning
      // a page, or changing internal controls. Keep the chosen placement;
      // a gesture or explicit 2D jump will publish a new point.
      return;
    }
    _setViewportPosition(
      _reader.manifest.positionAt(
        anchor.pageIndexHint,
        offset: original.dy,
        normalizedX: original.dx,
        viewportX: (point.dx / _viewportWidth).clamp(0.0, 1.0),
        viewportY: (point.dy / _viewportHeight).clamp(0.0, 1.0),
      ),
    );
  }

  void _captureViewportAnchor() {
    if (_restoring) return;
    final images = _visibleImages;
    if (images.isEmpty) return;
    final leading = Offset(_viewportWidth * _leadingX, 0);
    Offset nearest(_VisibleImage image) => Offset(
      leading.dx.clamp(image.visible.left, image.visible.right),
      image.visible.top,
    );
    var selected = images.first;
    for (final image in images.skip(1)) {
      if ((nearest(image) - leading).distanceSquared <
          (nearest(selected) - leading).distanceSquared) {
        selected = image;
      }
    }
    if (_hasDecodedGeometry(selected.index)) {
      _setViewportPosition(_positionInImage(selected, nearest(selected)));
    } else if (_reader.position?.pageIndexHint != selected.index) {
      // Before decoding we can navigate to a page identity, but its guessed
      // aspect ratio cannot establish an original-image point.
      _setViewportPosition(
        _reader.manifest.positionAt(
          selected.index,
          normalizedX: _leadingX,
          viewportX: _leadingX,
        ),
      );
    }
  }

  double _restoreTop(ReadingPosition anchor) =>
      _offsets[anchor.pageIndexHint] +
      _pageHeight(_reader.manifest.pages[anchor.pageIndexHint]) *
          _pointWithinCrop(anchor).dy -
      _viewportHeight * anchor.viewportY;

  void _onHorizontalScroll() {
    if (!mounted || _restoring) return;
    _captureViewportAnchor();
    _scheduleViewport();
  }

  void _syncWindow() {
    var pages = _reader.imageWindow();
    if (_reader.isContinuous && _viewportWidth > 0 && _viewportHeight > 0) {
      final offsets = _offsets;
      final anchor = _pendingRestorePosition ?? _reader.position;
      final top = _restoring && anchor != null
          ? _restoreTop(anchor)
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
    if (_restoring ||
        widget.chapterTransition != null ||
        !_scroll.hasClients ||
        _viewportWidth <= 0) {
      return;
    }
    _captureViewportAnchor();
    final position = _reader.position;
    if (position != null) {
      _navigation('scroll', {
        'targetIndex': position.pageIndexHint,
        'offset': position.normalizedOffset,
        'normalizedX': position.normalizedX,
        'scrollOffset': _scroll.offset,
      });
    }
    _syncWindow();
    _scheduleViewport();
  }

  void _scheduleRestore({bool preservePlacement = false}) {
    _pendingRestorePosition = _reader.position;
    _restoring = true;
    final epoch = ++_restoreEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _restoreEpoch) return;
      final anchor = _pendingRestorePosition;
      if (anchor == null || _viewportWidth <= 0 || _viewportHeight <= 0) {
        _restoring = false;
        return;
      }
      if (_reader.isContinuous && _scroll.hasClients) {
        _scroll.jumpTo(
          _restoreTop(anchor).clamp(0.0, _scroll.position.maxScrollExtent),
        );
      } else if (!_reader.isContinuous) {
        final scene = _pagedScene;
        final rect = scene.images[anchor.pageKey];
        if (rect != null) {
          _transform.value = _anchoredTransform(
            scene.size,
            _viewport,
            Offset(
              rect.left + rect.width * _pointWithinCrop(anchor).dx,
              rect.top + rect.height * _pointWithinCrop(anchor).dy,
            ),
            Offset(
              _viewportWidth * anchor.viewportX,
              _viewportHeight * anchor.viewportY,
            ),
            _transform.value.getMaxScaleOnAxis(),
          );
        }
      }
      // A vertical jump may build the target page's horizontal ScrollPosition
      // in the next layout. Keep observations blocked until that position exists.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _restoreEpoch) return;
        if (_reader.isContinuous) {
          final page = _reader.manifest.pages[anchor.pageIndexHint];
          final size = _pageSize(page);
          final horizontal = _horizontal[page.key];
          if (horizontal != null && horizontal.hasClients) {
            final target =
                math.max(0, (_viewportWidth - size.width) / 2) +
                size.width * _pointWithinCrop(anchor).dx -
                _viewportWidth * anchor.viewportX;
            horizontal.jumpTo(
              target.clamp(0.0, horizontal.position.maxScrollExtent),
            );
          }
        }
        _pendingRestorePosition = null;
        _restoring = false;
        // Preserve the original image point, updating only where layout
        // constraints place it in the viewport. Placeholder ratios never save.
        _confirmViewportAnchor(anchor, preservePlacement: preservePlacement);
        _syncWindow();
        _scheduleViewport();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _selectMode(ReadingMode mode) {
    if (_reader.mode == mode) return;
    _preferredPlacement = null;
    _navigation('layout', {'mode': mode.name});
    _applyMode(mode);
    widget.onModeChanged?.call(mode);
  }

  void _applyMode(ReadingMode mode) {
    if (_reader.mode == mode) return;
    _restoring = true;
    _transform.value = Matrix4.identity();
    _reader.setLayout(mode: mode);
    _scheduleRestore();
  }

  void _selectDoublePage(bool? value) {
    if (_doublePagePreference == value) return;
    _preferredPlacement = null;
    _navigation('layout', {'doublePage': value});
    setState(() => _doublePagePreference = value);
    _restoring = true;
    _transform.value = Matrix4.identity();
    _applyDoublePagePreference();
    _scheduleRestore();
    widget.onDoublePageChanged?.call(value);
  }

  void _applyDoublePagePreference() {
    final doublePage = _doublePagePreference ?? _viewportWidth >= 900;
    if (_reader.doublePage == doublePage) return;
    _restoring = true;
    _reader.setLayout(doublePage: doublePage);
    _scheduleRestore();
  }

  void _goTo(int index) {
    if (_reader.manifest.pages.isEmpty) return;
    _restoring = true;
    _transform.value = Matrix4.identity();
    _navigation('jump', {'targetIndex': index});
    _selectPage(index);
    _scheduleRestore();
  }

  void _advance() {
    if (!_reader.canAdvance) return;
    _navigation('advance', {
      'targetPageKey': _reader.spreads[_reader.spreadIndex + 1].pages.first.key,
    });
    _restoring = true;
    final page = _reader.spreads[_reader.spreadIndex + 1].pages.first;
    _selectPage(
      _reader.manifest.pages.indexWhere((item) => item.key == page.key),
    );
    _transform.value = Matrix4.identity();
    _scheduleRestore();
  }

  void _back() {
    if (!_reader.canGoBack) return;
    _navigation('back', {
      'targetPageKey': _reader.spreads[_reader.spreadIndex - 1].pages.first.key,
    });
    _restoring = true;
    final page = _reader.spreads[_reader.spreadIndex - 1].pages.first;
    _selectPage(
      _reader.manifest.pages.indexWhere((item) => item.key == page.key),
    );
    _transform.value = Matrix4.identity();
    _scheduleRestore();
  }

  void _turn(bool forward) {
    final edge = forward ? ReaderChapterEdge.next : ReaderChapterEdge.previous;
    if (widget.chapterTransition case final transition?) {
      if (edge == transition.edge) {
        transition.onContinue?.call();
      } else {
        transition.onReturn?.call();
      }
      return;
    }
    if (_reader.isContinuous &&
        widget.onChapterEdge != null &&
        _scroll.hasClients &&
        _scroll.position.hasContentDimensions) {
      final offset = _scroll.position;
      final remaining = forward ? offset.extentAfter : offset.extentBefore;
      if (remaining <= 1) {
        _offerChapterEdge(edge);
        return;
      }
    }
    if (forward ? _reader.canAdvance : _reader.canGoBack) {
      forward ? _advance() : _back();
    } else if (!_reader.isContinuous) {
      _offerChapterEdge(edge);
    }
  }

  void _offerChapterEdge(ReaderChapterEdge edge) {
    if (!widget.paused &&
        !_zoomed &&
        _reader.position != null &&
        widget.chapterTransition == null) {
      widget.onChapterEdge?.call(edge);
    }
  }

  bool _onChapterOverscroll(ScrollNotification notification) {
    if (notification.depth != 0 || widget.onChapterEdge == null) return false;
    if (notification is ScrollStartNotification) {
      _edgePull = 0;
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      _edgePull += notification.overscroll;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final metrics = notification.metrics;
      _edgePull =
          metrics.pixels -
          metrics.pixels.clamp(
            metrics.minScrollExtent,
            metrics.maxScrollExtent,
          );
    } else if (notification is ScrollEndNotification &&
        _edgePull.abs() >= kMinInteractiveDimensionCupertino) {
      final edge = _edgePull > 0
          ? ReaderChapterEdge.next
          : ReaderChapterEdge.previous;
      final controller = _scroll;
      // Scroll notifications arrive after layout. Only the current attached
      // viewport can turn this completed drag into a chapter boundary.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _reader.isContinuous &&
            identical(controller, _scroll) &&
            controller.hasClients) {
          _offerChapterEdge(edge);
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    return false;
  }

  void _selectPage(int index) {
    _reader.goToPage(index, normalizedX: _leadingX, viewportX: _leadingX);
    // The page identity is already valid before its image arrives. Late
    // dimensions can change rendering without changing the saved placement.
    _preferredPlacement = _reader.position;
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (_zoomed != zoomed && mounted) setState(() => _zoomed = zoomed);
    _captureViewportAnchor();
    _scheduleViewport();
  }

  void _zoom(double factor) {
    _preferredPlacement = null;
    final scale = _transform.value.getMaxScaleOnAxis();
    final next = (scale * factor).clamp(1.0, 5.0);
    final center = Offset(_viewportWidth / 2, _viewportHeight / 2);
    _transform.value = _anchoredTransform(
      _pagedScene.size,
      _viewport,
      _transform.toScene(center),
      center,
      next,
    );
  }

  void _afterImageNotification(VoidCallback action) {
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.postFrameCallbacks) {
      action();
      return;
    }
    final scheduler = _scheduler;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(scheduler, _scheduler)) action();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _image(ReaderPage page, {BoxFit fit = BoxFit.contain}) {
    final snapshot = _scheduler.snapshot;
    final resource = snapshot.resources[page.key];
    final number = _reader.manifest.pages.indexOf(page) + 1;
    if (resource != null) {
      return Semantics(
        label: '第 $number 页',
        image: true,
        child: NotificationListener<ReaderImageDecoded>(
          onNotification: (notification) {
            if (notification.resourceId == resource.id) {
              _afterImageNotification(() {
                if (_scheduler.snapshot.resources[page.key]?.id !=
                    resource.id) {
                  return;
                }
                _learnedDimensions[page.key] = ImageDimensions(
                  width: notification.width,
                  height: notification.height,
                );
                final firstFrame = !_decodedResources.contains(resource.id);
                if (_scheduler.recordDecoded(
                  resource.id,
                  notification.width,
                  notification.height,
                )) {
                  _decodedResources.add(resource.id);
                  if (firstFrame &&
                      !_restoring &&
                      _reader.position?.pageKey == page.key &&
                      page.width == notification.width &&
                      page.height == notification.height) {
                    // A matching late frame does not change the manifest. Its
                    // geometry is already restored, so confirm once without
                    // delaying observation or interrupting gestures.
                    _confirmViewportAnchor(_reader.position!);
                  }
                } else {
                  _decodedResources.remove(resource.id);
                }
                _scheduleViewport();
              });
            }
            return true;
          },
          child: NotificationListener<ReaderImageFailed>(
            onNotification: (notification) {
              if (notification.resourceId == resource.id) {
                _afterImageNotification(() {
                  _decodedResources.remove(resource.id);
                  _scheduler.recordDecodeError(resource.id, notification.error);
                  _scheduleViewport();
                });
              }
              return true;
            },
            child: ReaderImageCropScope(
              enabled: widget.cropBorders,
              child: NotificationListener<ReaderImageCrop>(
                onNotification: (notification) {
                  _afterImageNotification(
                    () => _acceptCrop(page.key, resource, notification),
                  );
                  return true;
                },
                child: _CroppedImage(
                  bounds: _cropBounds(page),
                  child: PinnedReaderImage(
                    key: ValueKey('display-${resource.id}'),
                    pool: _resourcePool,
                    image: resource,
                    builder: (context) =>
                        widget.imageBuilder(context, resource, fit),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (snapshot.cleanupError != null) {
      return const Center(child: Text('图片资源清理失败，请重新打开章节。'));
    }
    if (snapshot.errors[page.key] case final error?) {
      final detail = switch (error) {
        RuntimeException(code: RuntimeErrorCode.unsupportedCapability) =>
          '当前平台尚未支持图片阅读',
        RuntimeException(code: RuntimeErrorCode.accessRequired) =>
          '访问验证已失效，请返回重新登录',
        RuntimeException(code: RuntimeErrorCode.runtimeLost) =>
          '漫画源已中断，请返回重新连接',
        ImageBudgetExceeded(:final message) => message,
        _ => null,
      };
      return Center(
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('第 $number 页未能加载', textAlign: TextAlign.center),
              if (detail != null) Text(detail, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              CupertinoButton.filled(
                onPressed: widget.paused
                    ? null
                    : () => _scheduler.retry(page.key),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    return snapshot.loading.contains(page.key)
        ? Center(
            child: Semantics(
              container: true,
              label: '正在加载第 $number 页',
              child: CupertinoActivityIndicator(
                color: _readerForegroundColor(context, widget.background),
              ),
            ),
          )
        : const SizedBox.shrink();
  }

  void _openZoom(ReaderPage page) {
    final resource = _scheduler.snapshot.resources[page.key];
    if (resource == null) return;
    _navigation('open_zoom', {'targetPageKey': page.key});
    final pool = _resourcePool;
    final scheduler = _scheduler;
    final pin = pool.pin(resource.id);
    unawaited(
      showAppDialog<void>(
        context: context,
        builder: (dialogContext) => NotificationListener<ReaderImageDecoded>(
          onNotification: (notification) {
            if (notification.resourceId == resource.id) {
              _afterImageNotification(() {
                if (!identical(scheduler, _scheduler)) return;
                final accepted = scheduler.recordDecoded(
                  resource.id,
                  notification.width,
                  notification.height,
                );
                if (!accepted && dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              });
            }
            return true;
          },
          child: NotificationListener<ReaderImageFailed>(
            onNotification: (notification) {
              if (notification.resourceId == resource.id) {
                _afterImageNotification(() {
                  if (!identical(scheduler, _scheduler)) return;
                  _decodedResources.remove(resource.id);
                  scheduler.recordDecodeError(resource.id, notification.error);
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                });
              }
              return true;
            },
            child: NotificationListener<ReaderImageCrop>(
              onNotification: (notification) {
                _afterImageNotification(() {
                  if (!identical(scheduler, _scheduler)) return;
                  _acceptCrop(page.key, resource, notification);
                });
                return true;
              },
              child: _ZoomImageDialog(
                resource: resource,
                pool: pool,
                imageBuilder: widget.imageBuilder,
                appearance: _appearance,
                aspectRatio: page.originalAspectRatio,
              ),
            ),
          ),
        ),
      ).whenComplete(() async {
        await pin.close();
        if (mounted) _scheduleViewport();
      }),
    );
  }

  void _toggleToolbar() {
    if (_reader.position == null) return;
    setState(() => _toolbar = !_toolbar);
    if (MediaQuery.disableAnimationsOf(context)) {
      _toolbarAnimation.value = _toolbar ? 1 : 0;
    } else if (_toolbar) {
      _toolbarAnimation.forward();
    } else {
      _toolbarAnimation.reverse();
    }
  }

  void _onCanvasTap(TapUpDetails details) {
    // Disposing a page's double-tap recognizer can release a pending single tap.
    if (!mounted ||
        WidgetsBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
      return;
    }
    final fraction = details.localPosition.dx / _viewportWidth;
    if (fraction > 1 / 3 && fraction < 2 / 3) {
      _toggleToolbar();
    } else if (!_reader.isContinuous &&
        !_zoomed &&
        widget.tapZones != ReaderInputPreset.disabled) {
      final forward = _reader.mode == ReadingMode.rightToLeft
          ? fraction < 1 / 3
          : fraction > 2 / 3;
      final advance = widget.tapZones == ReaderInputPreset.reversed
          ? !forward
          : forward;
      _turn(advance);
    }
  }

  Widget _continuous() => NotificationListener<ScrollNotification>(
    onNotification: _onChapterOverscroll,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTapUp: _onCanvasTap,
      child: ListView.builder(
        key: const ValueKey('continuous-reader'),
        controller: _scroll,
        physics: widget.onChapterEdge == null
            ? null
            : const AlwaysScrollableScrollPhysics(),
        scrollCacheExtent: const ScrollCacheExtent.viewport(1),
        itemCount: _reader.manifest.pages.length,
        itemExtentBuilder: (index, dimensions) =>
            _pageHeight(_reader.manifest.pages[index]) + _gap,
        itemBuilder: (context, index) {
          final page = _reader.manifest.pages[index];
          final size = _pageSize(page);
          return Padding(
            padding: EdgeInsets.only(bottom: _gap),
            child: _ContinuousImage(
              key: ValueKey('continuous-image-${page.key}'),
              pageKey: page.key,
              viewportWidth: _viewportWidth,
              imageSize: size,
              onAttached: (controller) => _horizontal[page.key] = controller,
              onDetached: (controller) {
                if (identical(_horizontal[page.key], controller)) {
                  _horizontal.remove(page.key);
                }
              },
              onMoved: _onHorizontalScroll,
              onDoubleTap: () => _openZoom(page),
              child: _image(page),
            ),
          );
        },
      ),
    ),
  );

  Widget _paged() {
    final spread = _reader.spreads[_reader.spreadIndex];
    final scene = _pagedScene;
    final pannable =
        _zoomed ||
        scene.size.width > _viewportWidth + 1 ||
        scene.size.height > _viewportHeight + 1;
    return Listener(
      onPointerDown: (event) {
        _pointers.add(event.pointer);
        _dragStart = _pointers.length == 1 && !pannable ? event.position : null;
      },
      onPointerUp: (event) {
        final start = _dragStart;
        _pointers.remove(event.pointer);
        _dragStart = null;
        if (start == null || pannable) return;
        final delta = event.position - start;
        if (delta.dx.abs() < 60 || delta.dx.abs() < delta.dy.abs()) return;
        final forward = _reader.mode == ReadingMode.rightToLeft
            ? delta.dx > 0
            : delta.dx < 0;
        _turn(forward);
      },
      onPointerCancel: (event) {
        _pointers.remove(event.pointer);
        _dragStart = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => _zoom(_zoomed ? 0.2 : 2),
        onTapUp: _onCanvasTap,
        child: InteractiveViewer(
          key: ValueKey('spread-${spread.pages.first.key}'),
          transformationController: _transform,
          alignment: Alignment.topLeft,
          constrained: false,
          minScale: 1,
          maxScale: 5,
          panEnabled: pannable,
          child: SizedBox(
            width: scene.size.width,
            height: scene.size.height,
            child: Stack(
              children: [
                for (final page in spread.displayPages(_reader.mode))
                  Positioned.fromRect(
                    rect: scene.images[page.key]!,
                    child: SizedBox(
                      key: ValueKey('image-rect-${page.key}'),
                      child: _image(page),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _keyboardTurn(bool forward) {
    if (widget.keyboard == ReaderInputPreset.disabled) return;
    final advance = widget.keyboard == ReaderInputPreset.reversed
        ? !forward
        : forward;
    _turn(advance);
  }

  void _keyboardGoTo(int index) {
    if (widget.keyboard != ReaderInputPreset.disabled &&
        widget.chapterTransition == null) {
      _goTo(index);
    }
  }

  Widget _title() {
    final title = Text(
      widget.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final subtitle = widget.subtitle;
    if (subtitle == null || subtitle.isEmpty) return title;
    return Semantics(
      label: '${widget.title} · $subtitle',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) => FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                title,
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CupertinoTheme.of(context).textTheme.textStyle
                      .copyWith(
                        color: AppColors.secondaryLabel.resolveFrom(context),
                        fontSize: 13,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageIndicator() {
    final count = '${_reader.pageIndex + 1} / ${_reader.manifest.pages.length}';
    return Semantics(
      key: const ValueKey('reader-page-indicator'),
      container: true,
      label: '显示阅读工具',
      value: count,
      child: CupertinoButton(
        onPressed: _toggleToolbar,
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: CupertinoColors.black.withValues(alpha: .8),
              shape: const StadiumBorder(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                count,
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [ui.FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _readingCanvas(double centerY) {
    final needsPositionNotice = _reader.requiresPositionNotice;
    return DefaultTextStyle.merge(
      style: TextStyle(
        color: _readerForegroundColor(context, widget.background),
      ),
      child: Column(
        children: [
          if (needsPositionNotice) const Text('页面清单发生变化，已定位到最接近的页码。'),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final window = MediaQuery.sizeOf(context);
                final sameWindow = _windowSize == window;
                if (_windowSize != null && !sameWindow) {
                  _preferredPlacement = null;
                }
                _windowSize = window;
                final pageCenterY = needsPositionNotice ? null : centerY;
                if (_viewportWidth != constraints.maxWidth ||
                    _viewportHeight != constraints.maxHeight ||
                    _pageCenterY != pageCenterY) {
                  final chromeOnly =
                      sameWindow && _viewportWidth == constraints.maxWidth;
                  _viewportWidth = constraints.maxWidth;
                  _viewportHeight = constraints.maxHeight;
                  _pageCenterY = pageCenterY;
                  _scheduleRestore(preservePlacement: chromeOnly);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _applyDoublePagePreference();
                    _scheduleRestore(preservePlacement: chromeOnly);
                  });
                }
                if (_reader.manifest.pages.isEmpty) {
                  return const Center(child: Text('这一章没有页面'));
                }
                final transition = widget.chapterTransition;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ExcludeSemantics(
                      excluding: transition != null,
                      child: ExcludeFocus(
                        excluding: transition != null,
                        child: IgnorePointer(
                          ignoring: transition != null,
                          child: _ReaderContent(
                            background: widget.background,
                            dimPercent: widget.dimPercent,
                            child: _reader.isContinuous
                                ? _continuous()
                                : _paged(),
                          ),
                        ),
                      ),
                    ),
                    if (widget.onChapterEdge != null)
                      _chapterTransitionLayer(transition),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chapterTransitionLayer(ReaderChapterTransition? transition) {
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.reduceMotionOf(context);
    return IgnorePointer(
      ignoring: transition == null,
      child: ExcludeFocus(
        excluding: transition == null,
        child: ExcludeSemantics(
          excluding: transition == null,
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: transition == null
                ? const SizedBox.expand()
                : GestureDetector(
                    key: ValueKey(transition.edge),
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTapUp: _onCanvasTap,
                    onHorizontalDragEnd: !_reader.isContinuous
                        ? (details) {
                            final velocity = details.primaryVelocity;
                            if (velocity != null && velocity != 0) {
                              _turn(
                                _reader.mode == ReadingMode.rightToLeft
                                    ? velocity > 0
                                    : velocity < 0,
                              );
                            }
                          }
                        : null,
                    onVerticalDragEnd: _reader.isContinuous
                        ? (details) {
                            final velocity = details.primaryVelocity;
                            if (velocity != null && velocity != 0) {
                              _turn(velocity < 0);
                            }
                          }
                        : null,
                    child: transition,
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scroll = useScrollController();
    _transform = useTransformationController();
    _toolbarAnimation = useAnimationController(
      duration: const Duration(milliseconds: 200),
      initialValue: 1,
    );
    useEffect(() {
      final animation = _toolbarAnimation;
      void update(AnimationStatus status) {
        if (mounted &&
            (status == AnimationStatus.completed ||
                status == AnimationStatus.dismissed)) {
          setState(() {});
        }
      }

      animation.addStatusListener(update);
      return () => animation.removeStatusListener(update);
    }, [_toolbarAnimation]);
    _appearance = useValueNotifier<_ReaderAppearance>((
      background: widget.background,
      dimPercent: widget.dimPercent,
      fit: widget.fit,
      cropBorders: widget.cropBorders,
      crops: const {},
    ));
    useEffect(() {
      _initialize();
      return null;
    }, const []);
    useOnStreamChange(_reader.changes, onData: (_) => _readerChanged());
    useOnStreamChange(_scheduler.changes, onData: _imagesChanged);
    useOnListenableChange(_scroll, _onScroll);
    useOnListenableChange(_transform, _onTransform);
    useOnListenableChange(widget.positionRequest, _applyPositionRequest);
    // Keep the canvas constraints steady while painting the exit transition.
    final toolbarMounted = _toolbar || !_toolbarAnimation.isDismissed;
    final toolbarInteractive = _toolbar && _toolbarAnimation.isCompleted;
    final toolbarProgress = _toolbarAnimation.drive(
      CurveTween(curve: Curves.easeInOutCubic),
    );
    final chapterTransition = widget.chapterTransition;
    final navigationBar = toolbarMounted
        ? _ReaderNavigationBar(
            progress: toolbarProgress,
            interactive: toolbarInteractive,
            bar: CupertinoNavigationBar(
              automaticBackgroundVisibility: false,
              automaticallyImplyLeading: chapterTransition == null,
              backgroundColor: AppColors.toolbar.resolveFrom(context),
              leading:
                  widget.onExit == null ||
                      (chapterTransition != null &&
                          chapterTransition.onReturn == null)
                  ? null
                  : CupertinoNavigationBarBackButton(onPressed: widget.onExit),
              middle: _title(),
              trailing: chapterTransition == null
                  ? widget.chapterActions
                  : null,
            ),
          )
        : null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _keyboardTurn(_reader.mode != ReadingMode.rightToLeft),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _keyboardTurn(_reader.mode == ReadingMode.rightToLeft),
        const SingleActivator(LogicalKeyboardKey.pageDown): () =>
            _keyboardTurn(true),
        const SingleActivator(LogicalKeyboardKey.space): () =>
            _keyboardTurn(true),
        const SingleActivator(LogicalKeyboardKey.pageUp): () =>
            _keyboardTurn(false),
        const SingleActivator(LogicalKeyboardKey.home): () => _keyboardGoTo(0),
        const SingleActivator(LogicalKeyboardKey.end): () =>
            _keyboardGoTo(_reader.manifest.pages.length - 1),
        if (chapterTransition case final transition?)
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              transition.onReturn?.call(),
        if (widget.keyboard != ReaderInputPreset.disabled)
          const SingleActivator(LogicalKeyboardKey.keyT, includeRepeats: false):
              _toggleToolbar,
      },
      child: Focus(
        autofocus: true,
        child: CupertinoPageScaffold(
          backgroundColor: _readerBackgroundColor(context, widget.background),
          navigationBar: navigationBar,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, bounds) {
                // The scaffold already consumed the navigation bar's height.
                // Express the full safe area's center in the canvas's coordinates.
                final barHeight = navigationBar?.preferredSize.height ?? 0;
                final centerY = (bounds.maxHeight - barHeight) / 2;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Column(
                      children: [
                        Expanded(child: _readingCanvas(centerY)),
                        if (toolbarMounted)
                          _ReaderToolbarTransition(
                            progress: toolbarProgress,
                            interactive:
                                toolbarInteractive && chapterTransition == null,
                            slideFrom: const Offset(0, 1),
                            child: Opacity(
                              opacity: chapterTransition == null ? 1 : .5,
                              child: _controls(),
                            ),
                          ),
                      ],
                    ),
                    if (!toolbarMounted && _reader.position != null)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: _pageIndicator(),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final available = math.max(
      0.0,
      MediaQuery.sizeOf(context).height -
          MediaQuery.paddingOf(context).vertical -
          kMinInteractiveDimensionCupertino,
    );
    // Keep space for the page even when the full set of controls cannot fit.
    final readingHeight = math.min(
      3 * kMinInteractiveDimensionCupertino,
      available / 2,
    );
    return ColoredBox(
      color: AppColors.toolbar.resolveFrom(context),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: available - readingHeight),
          child: _scrollableControls(),
        ),
      ),
    );
  }

  Widget _pageStep({
    required bool enabled,
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) => Semantics(
    container: true,
    enabled: enabled,
    child: CupertinoButton(
      onPressed: enabled ? onPressed : null,
      padding: const EdgeInsets.all(8),
      child: Icon(icon, semanticLabel: label),
    ),
  );

  Widget _pageTools(TextDirection direction) {
    final rtl = direction == TextDirection.rtl;
    return Row(
      textDirection: direction,
      children: [
        _pageStep(
          enabled: _reader.canGoBack,
          onPressed: _back,
          icon: rtl ? CupertinoIcons.forward_end : CupertinoIcons.backward_end,
          label: '上一页',
        ),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceField<ReadingMode>(
                label: '阅读模式',
                value: _reader.mode,
                icon: switch (_reader.mode) {
                  ReadingMode.leftToRight => CupertinoIcons.arrow_right,
                  ReadingMode.rightToLeft => CupertinoIcons.arrow_left,
                  ReadingMode.continuous => CupertinoIcons.arrow_down,
                  ReadingMode.webtoon => CupertinoIcons.rectangle_grid_1x2,
                },
                options: const {
                  ReadingMode.leftToRight: '从左到右',
                  ReadingMode.rightToLeft: '从右到左',
                  ReadingMode.continuous: '竖向连续',
                  ReadingMode.webtoon: '条漫',
                },
                onChanged: widget.layoutSettingsEnabled
                    ? (mode) {
                        if (mode != null) _selectMode(mode);
                      }
                    : null,
              ),
              if (!_reader.isContinuous)
                ChoiceField<bool>(
                  key: const ValueKey('reader-page-layout'),
                  label: '分页布局',
                  value: _doublePagePreference,
                  icon: switch (_doublePagePreference) {
                    null => CupertinoIcons.rectangle,
                    false => CupertinoIcons.doc,
                    true => CupertinoIcons.book,
                  },
                  options: const {null: '自动', false: '单页', true: '双页'},
                  onChanged: widget.layoutSettingsEnabled
                      ? _selectDoublePage
                      : null,
                ),
              if (_reader.isContinuous)
                CupertinoButton(
                  onPressed: _reader.position == null
                      ? null
                      : () => _openZoom(
                          _reader.manifest.pages[_reader.pageIndex],
                        ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    CupertinoIcons.zoom_in,
                    semanticLabel: '放大当前图片',
                  ),
                )
              else ...[
                for (final (factor, icon, label) in [
                  (0.5, CupertinoIcons.zoom_out, '缩小'),
                  (2.0, CupertinoIcons.zoom_in, '放大'),
                ])
                  CupertinoButton(
                    onPressed: () => _zoom(factor),
                    padding: const EdgeInsets.all(8),
                    child: Icon(icon, semanticLabel: label),
                  ),
                CupertinoButton(
                  onPressed: () {
                    _preferredPlacement = null;
                    _restoring = true;
                    _transform.value = Matrix4.identity();
                    _scheduleRestore();
                  },
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    CupertinoIcons.arrow_up_left_arrow_down_right,
                    semanticLabel: '重置缩放',
                  ),
                ),
              ],
              if (widget.readingSettings case final Widget settings) settings,
            ],
          ),
        ),
        _pageStep(
          enabled: _reader.canAdvance,
          onPressed: _advance,
          icon: rtl ? CupertinoIcons.backward_end : CupertinoIcons.forward_end,
          label: '下一页',
        ),
      ],
    );
  }

  Widget _scrollableControls() {
    final direction = _reader.mode == ReadingMode.rightToLeft
        ? TextDirection.rtl
        : TextDirection.ltr;
    return SingleChildScrollView(
      primary: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ReaderPageNavigation(
              key: ValueKey((
                widget.provider,
                widget.generation,
                widget.manifest,
                widget.paused,
                _reader.mode,
              )),
              pageIndex: _reader.pageIndex,
              pageCount: _reader.manifest.pages.length,
              direction: direction,
              onSelect: widget.paused ? null : _goTo,
              keyboardEnabled: widget.keyboard != ReaderInputPreset.disabled,
              chapters: widget.chapterNavigation,
            ),
          ),
          _pageTools(direction),
          if (widget.chapterControls case final Widget controls)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: controls,
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    final position = _reader.position;
    if (position != null) widget.onPositionChanged?.call(position);
    final scheduler = _scheduler;
    final onClosed = widget.onClosed;
    final baseline = _baseline;
    final exitCapture = baseline?.recording == true ? baseline!.session : null;
    final exitIdentity = {
      'chapterKey': _reader.manifest.chapterKey,
      'generation': widget.generation,
      'manifestVersion': _reader.manifest.version,
    };
    baseline?.event('reader_exit_requested', exitIdentity);
    final cleanup = () async {
      try {
        await scheduler.dispose();
        await onClosed?.call();
        if (exitCapture != null && exitCapture == baseline?.session) {
          baseline?.event('reader_exit_ack', exitIdentity);
        }
      } catch (error) {
        if (exitCapture != null && exitCapture == baseline?.session) {
          baseline?.event('reader_exit_error', {
            ...exitIdentity,
            'errorType': error.runtimeType.toString(),
          });
        }
        rethrow;
      }
    }();
    widget.onClosing?.call(cleanup);
    unawaited(cleanup);
    unawaited(_reader.dispose());
    super.dispose();
  }
}

class _ReaderToolbarTransition extends StatelessWidget {
  const _ReaderToolbarTransition({
    required this.progress,
    required this.interactive,
    required this.slideFrom,
    required this.child,
  });

  final Animation<double> progress;
  final bool interactive;
  final Offset slideFrom;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    excluding: !interactive,
    child: ExcludeFocus(
      excluding: !interactive,
      child: IgnorePointer(
        ignoring: !interactive,
        child: ClipRect(
          clipBehavior: interactive ? Clip.none : Clip.hardEdge,
          child: FadeTransition(
            opacity: progress,
            child: SlideTransition(
              position: MediaQuery.reduceMotionOf(context)
                  ? const AlwaysStoppedAnimation(Offset.zero)
                  : progress.drive(
                      Tween<Offset>(begin: slideFrom, end: Offset.zero),
                    ),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReaderNavigationBar extends _ReaderToolbarTransition
    implements ObstructingPreferredSizeWidget {
  const _ReaderNavigationBar({
    required this.bar,
    required super.progress,
    required super.interactive,
  }) : super(slideFrom: const Offset(0, -1), child: bar);

  final CupertinoNavigationBar bar;

  @override
  Size get preferredSize => bar.preferredSize;

  @override
  bool shouldFullyObstruct(BuildContext context) =>
      bar.shouldFullyObstruct(context);
}

/// Each lazily built page owns its horizontal position and disposes it when
/// leaving the list; the Reader only borrows live controllers for restoration.
class const _ContinuousImage({
  super.key,
  required final String pageKey,
  required final double viewportWidth,
  required final Size imageSize,
  required final ValueChanged<ScrollController> onAttached,
  required final ValueChanged<ScrollController> onDetached,
  required final VoidCallback onMoved,
  required final VoidCallback onDoubleTap,
  required final Widget child,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final controller = useScrollController();
    useOnListenableChange(controller, onMoved);
    useEffect(() {
      onAttached(controller);
      return () => onDetached(controller);
    }, [controller]);
    return SingleChildScrollView(
      key: ValueKey('horizontal-$pageKey'),
      controller: controller,
      scrollDirection: Axis.horizontal,
      child: GestureDetector(
        onDoubleTap: onDoubleTap,
        child: SizedBox(
          width: math.max(viewportWidth, imageSize.width),
          height: imageSize.height,
          child: Center(
            child: SizedBox(
              key: ValueKey('image-rect-$pageKey'),
              width: imageSize.width,
              height: imageSize.height,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

const _fullImage = Rect.fromLTRB(0, 0, 1, 1);

final class _ImageCrop {
  const _ImageCrop(this.bounds, this.width, this.height);
  final Rect bounds;
  final int width;
  final int height;
}

bool _validCrop(Rect bounds) =>
    [
      bounds.left,
      bounds.top,
      bounds.right,
      bounds.bottom,
    ].every((value) => value.isFinite && value >= 0 && value <= 1) &&
    bounds.width > 0 &&
    bounds.height > 0;

/// Repositions the same complete image under a clip. Its provider, encoded
/// bytes, decoded frame and resource ownership are unchanged by trimming.
class const _CroppedImage({
  required final Rect bounds,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ClipRect(
      child: SizedBox.expand(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -constraints.maxWidth * bounds.left / bounds.width,
              top: -constraints.maxHeight * bounds.top / bounds.height,
              width: constraints.maxWidth / bounds.width,
              height: constraints.maxHeight / bounds.height,
              child: child,
            ),
          ],
        ),
      ),
    ),
  );
}

final class _VisibleImage {
  const _VisibleImage(this.index, this.rect, this.visible);
  final int index;
  final Rect rect;
  final Rect visible;
}

final class _ReaderScene {
  const _ReaderScene(this.size, this.images);
  final Size size;
  final Map<String, Rect> images;
}

Size _fitImageSize(double aspectRatio, Size cell, ReaderFit fit) {
  final height = switch (fit) {
    ReaderFit.contain => math.min(cell.height, cell.width / aspectRatio),
    ReaderFit.width => cell.width / aspectRatio,
    ReaderFit.height => cell.height,
  };
  return Size(height * aspectRatio, height);
}

_ReaderScene _spreadScene(
  List<ReaderPage> pages,
  Size viewport,
  ReaderFit fit, {
  double? centerY,
}) {
  final cellWidth = viewport.width / pages.length;
  final sizes = [
    for (final page in pages)
      _fitImageSize(page.aspectRatio, Size(cellWidth, viewport.height), fit),
  ];
  final contentWidth = fit == ReaderFit.height
      ? sizes.fold(0.0, (width, size) => width + size.width)
      : viewport.width;
  final tallest = sizes.fold(
    0.0,
    (height, size) => math.max(height, size.height),
  );
  final scene = Size(
    math.max(viewport.width, contentWidth),
    math.max(viewport.height, tallest),
  );
  final containedCenter = fit == ReaderFit.contain
      ? (centerY ?? viewport.height / 2).clamp(
          tallest / 2,
          viewport.height - tallest / 2,
        )
      : null;
  final images = <String, Rect>{};
  var left = (scene.width - contentWidth) / 2;
  for (var index = 0; index < pages.length; index++) {
    final size = sizes[index];
    final width = fit == ReaderFit.height ? size.width : cellWidth;
    images[pages[index].key] = Rect.fromLTWH(
      left + (width - size.width) / 2,
      containedCenter == null
          ? math.max(0, (viewport.height - size.height) / 2)
          : containedCenter - size.height / 2,
      size.width,
      size.height,
    );
    left += width;
  }
  return _ReaderScene(scene, images);
}

Matrix4 _anchoredTransform(
  Size scene,
  Size viewport,
  Offset imagePoint,
  Offset viewportPoint,
  double scale,
) {
  final x = (viewportPoint.dx - imagePoint.dx * scale)
      .clamp(math.min(0.0, viewport.width - scene.width * scale), 0.0)
      .toDouble();
  final y = (viewportPoint.dy - imagePoint.dy * scale)
      .clamp(math.min(0.0, viewport.height - scene.height * scale), 0.0)
      .toDouble();
  return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(x, y, 0);
}

bool _sameAnchor(ReadingPosition first, ReadingPosition second) =>
    first.chapterKey == second.chapterKey &&
    first.pageKey == second.pageKey &&
    first.manifestVersion == second.manifestVersion &&
    (first.normalizedOffset - second.normalizedOffset).abs() < 0.000001 &&
    (first.normalizedX - second.normalizedX).abs() < 0.000001 &&
    (first.viewportX - second.viewportX).abs() < 0.000001 &&
    (first.viewportY - second.viewportY).abs() < 0.000001;

Color _readerBackgroundColor(
  BuildContext context,
  ReaderBackground background,
) => switch (background) {
  ReaderBackground.black => CupertinoColors.black,
  ReaderBackground.white => CupertinoColors.white,
  ReaderBackground.theme => CupertinoTheme.of(context).scaffoldBackgroundColor,
};

Color _readerForegroundColor(
  BuildContext context,
  ReaderBackground background,
) => switch (background) {
  ReaderBackground.black => CupertinoColors.white,
  ReaderBackground.white => CupertinoColors.black,
  ReaderBackground.theme => AppColors.label.resolveFrom(context),
};

/// Applies appearance only to reading content, preserving input and controls.
class const _ReaderContent({
  required final ReaderBackground background,
  required final int dimPercent,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: _readerBackgroundColor(context, background),
    child: DefaultTextStyle.merge(
      style: TextStyle(color: _readerForegroundColor(context, background)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (dimPercent > 0)
            IgnorePointer(
              child: ColoredBox(
                key: const ValueKey('reader-content-dimming'),
                color: CupertinoColors.black.withValues(
                  alpha: dimPercent / 100,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class const _ZoomImageDialog({
  required final ImageResource resource,
  required final ReaderResourcePool pool,
  required final ResourceImageBuilder imageBuilder,
  required final ValueListenable<_ReaderAppearance> appearance,
  required final double aspectRatio,
}) extends StatefulHookWidget {
  @override
  State<_ZoomImageDialog> createState() => _ZoomImageDialogState();
}

class _ZoomImageDialogState extends State<_ZoomImageDialog> {
  late TransformationController _transform;
  Size? _viewport;
  _ReaderScene? _scene;
  ReaderFit? _fit;
  Rect _crop = _fullImage;
  late double _aspectRatio = widget.aspectRatio;
  int _layoutEpoch = 0;

  void _zoom(double factor) {
    final scene = _scene;
    final viewport = _viewport;
    if (scene == null || viewport == null) return;
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      5.0,
    );
    final center = viewport.center(Offset.zero);
    _transform.value = _anchoredTransform(
      scene.size,
      viewport,
      _transform.toScene(center),
      center,
      scale,
    );
  }

  Widget _content(_ReaderAppearance appearance, BoxConstraints constraints) {
    final fit = appearance.fit;
    final crop = appearance.cropBorders
        ? appearance.crops[widget.resource.id]?.bounds ?? _fullImage
        : _fullImage;
    final viewport = constraints.biggest;
    final scene = _spreadScene(
      [
        ReaderPage(
          key: widget.resource.id,
          width: _aspectRatio,
          height: 1,
          contentAspectRatio: _aspectRatio * crop.width / crop.height,
        ),
      ],
      viewport,
      fit,
    );
    if (_viewport != viewport ||
        _fit != fit ||
        _crop != crop ||
        _scene?.images[widget.resource.id] !=
            scene.images[widget.resource.id]) {
      final oldViewport = _viewport;
      final oldRect = _scene?.images[widget.resource.id];
      var normalized = Offset.zero;
      var viewportPoint = Offset.zero;
      if (oldRect != null && oldViewport != null) {
        final rect = MatrixUtils.transformRect(_transform.value, oldRect);
        final point = Offset(
          0.0.clamp(rect.left, rect.right),
          0.0.clamp(rect.top, rect.bottom),
        );
        normalized = Offset(
          _crop.left +
              ((point.dx - rect.left) / rect.width).clamp(0.0, 1.0) *
                  _crop.width,
          _crop.top +
              ((point.dy - rect.top) / rect.height).clamp(0.0, 1.0) *
                  _crop.height,
        );
        viewportPoint = Offset(
          (point.dx / oldViewport.width).clamp(0.0, 1.0),
          (point.dy / oldViewport.height).clamp(0.0, 1.0),
        );
      }
      final scale = _fit != null && _fit != fit
          ? 1.0
          : _transform.value.getMaxScaleOnAxis();
      _viewport = viewport;
      _scene = scene;
      _fit = fit;
      _crop = crop;
      final epoch = ++_layoutEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _layoutEpoch) return;
        final rect = scene.images[widget.resource.id]!;
        _transform.value = _anchoredTransform(
          scene.size,
          viewport,
          Offset(
            rect.left +
                rect.width *
                    ((normalized.dx - crop.left) / crop.width).clamp(0.0, 1.0),
            rect.top +
                rect.height *
                    ((normalized.dy - crop.top) / crop.height).clamp(0.0, 1.0),
          ),
          Offset(
            viewport.width * viewportPoint.dx,
            viewport.height * viewportPoint.dy,
          ),
          scale,
        );
      });
    }
    final rect = scene.images[widget.resource.id]!;
    return InteractiveViewer(
      transformationController: _transform,
      alignment: Alignment.topLeft,
      constrained: false,
      minScale: 1,
      maxScale: 5,
      child: SizedBox(
        width: scene.size.width,
        height: scene.size.height,
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: ReaderImageCropScope(
                enabled: appearance.cropBorders,
                child: _CroppedImage(
                  bounds: crop,
                  child: NotificationListener<ReaderImageDecoded>(
                    onNotification: (notification) {
                      final ratio = notification.width / notification.height;
                      if (notification.resourceId == widget.resource.id &&
                          ratio != _aspectRatio) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _aspectRatio = ratio);
                        });
                        WidgetsBinding.instance.ensureVisualUpdate();
                      }
                      return false;
                    },
                    child: PinnedReaderImage(
                      pool: widget.pool,
                      image: widget.resource,
                      builder: (context) => widget.imageBuilder(
                        context,
                        widget.resource,
                        BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _transform = useTransformationController();
    final appearance = useValueListenable(widget.appearance);
    return CupertinoPageScaffold(
      key: const ValueKey('reader-image-viewer'),
      backgroundColor: _readerBackgroundColor(context, appearance.background),
      navigationBar: CupertinoNavigationBar(
        automaticBackgroundVisibility: false,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.xmark, semanticLabel: '关闭图片'),
        ),
        middle: const Text('查看图片'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoButton(
              onPressed: () => _zoom(0.5),
              padding: const EdgeInsets.all(8),
              child: const Icon(CupertinoIcons.zoom_out, semanticLabel: '缩小'),
            ),
            CupertinoButton(
              onPressed: () => _zoom(2),
              padding: const EdgeInsets.all(8),
              child: const Icon(CupertinoIcons.zoom_in, semanticLabel: '放大'),
            ),
            CupertinoButton(
              onPressed: () => _zoom(0.2),
              padding: const EdgeInsets.all(8),
              child: const Icon(
                CupertinoIcons.arrow_up_left_arrow_down_right,
                semanticLabel: '重置缩放',
              ),
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: _ReaderContent(
          background: appearance.background,
          dimPercent: appearance.dimPercent,
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _content(appearance, constraints),
          ),
        ),
      ),
    );
  }
}
