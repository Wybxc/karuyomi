import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../../diagnostics/reader_baseline.dart';

import 'package:reader_core/reader_core.dart';

import 'resource_image_web.dart'
    if (dart.library.io) 'resource_image_native.dart'
    as platform;

/// Actual client-decoded dimensions, emitted only after Image displays a frame.
class ReaderImageDecoded extends Notification {
  const ReaderImageDecoded(
    this.resourceId, {
    required this.width,
    required this.height,
  });
  final String resourceId;
  final int width;
  final int height;
}

class ReaderImageFailed extends Notification {
  const ReaderImageFailed(this.resourceId, this.error);
  final String resourceId;
  final Object error;
}

/// Only UI image widgets inspect borders. Transport and Source stay opaque.
class ReaderImageCropScope extends InheritedWidget {
  const ReaderImageCropScope({
    super.key,
    required this.enabled,
    required super.child,
  });
  final bool enabled;
  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ReaderImageCropScope>()
          ?.enabled ??
      false;
  @override
  bool updateShouldNotify(ReaderImageCropScope oldWidget) =>
      enabled != oldWidget.enabled;
}

class ReaderImageCrop extends Notification {
  const ReaderImageCrop(
    this.resourceId, {
    required this.bounds,
    required this.width,
    required this.height,
  });
  final String resourceId;
  final ui.Rect bounds;
  final int width;
  final int height;
}

/// Keeps the scheduler's existing resource ownership until pixel work ends.
class ReaderImageCropWork extends Notification {
  const ReaderImageCropWork(this.resourceId, this.finished);
  final String resourceId;
  final Future<void> finished;
}

const _fullBounds = ui.Rect.fromLTWH(0, 0, 1, 1);
const _cropSampleSide = 1024;

Widget buildResourceImage(
  BuildContext context,
  ImageResource resource,
  BoxFit fit,
) => ResourceImage(
  key: ValueKey(resource.id),
  resource: resource,
  fit: fit,
  cropBorders: ReaderImageCropScope.enabledOf(context),
);

/// Observes the same cached provider/completer used by Image. The extra listener
/// owns only an ImageInfo handle; it never creates a codec or decodes bytes.
class ResourceImage extends StatefulWidget {
  const ResourceImage({
    super.key,
    required this.resource,
    required this.fit,
    this.imageProvider,
    this.cropBorders = false,
  });

  final ImageResource resource;
  final BoxFit fit;
  final ImageProvider<Object>? imageProvider;
  final bool cropBorders;

  @override
  State<ResourceImage> createState() => _ResourceImageState();
}

class _ResourceImageState extends State<ResourceImage> {
  late ImageProvider<Object> _provider;
  ImageStream? _stream;
  ImageStreamCompleterHandle? _streamHandle;
  bool _listening = false;
  ui.Image? _cropFrame;
  ui.Rect? _cropBounds;
  bool _cropAttempted = false;
  bool _cropInFlight = false;
  bool _cropScheduled = false;
  bool _cropNotified = false;
  bool _animated = false;
  int _cropEpoch = 0;
  bool _paused = false;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onImage,
    onError: _onError,
    reportErrors: false,
  );
  ImageDimensions? _dimensions;
  ImageDimensions? _notifiedDimensions;
  Object? _error;
  bool _hasFrame = false;
  bool _scheduled = false;
  bool _errorNotified = false;
  int _epoch = 0;
  ReaderBaselineRecorder? _baseline;
  ({int session, int epoch, int frame})? _lastBaselineFrame;
  ({int session, int epoch})? _baselineErrorIdentity;

  @override
  void initState() {
    super.initState();
    _provider =
        widget.imageProvider ?? platform.resourceImageProvider(widget.resource);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _baseline = ReaderBaselineScope.read(context);
    _paused =
        !TickerMode.valuesOf(context).enabled ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _resolve();
    if (_paused && _hasFrame) {
      _stopListening(keepAlive: true);
    } else {
      _listen();
    }
  }

  @override
  void didUpdateWidget(ResourceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource != widget.resource ||
        oldWidget.imageProvider != widget.imageProvider) {
      _provider =
          widget.imageProvider ??
          platform.resourceImageProvider(widget.resource);
      _stopListening();
      _streamHandle?.dispose();
      _streamHandle = null;
      _stream = null;
      _resolve();
    }
    if (oldWidget.cropBorders != widget.cropBorders) {
      _cropEpoch++;
      _cropFrame?.dispose();
      _cropFrame = null;
      _cropScheduled = false;
      _cropNotified = false;
      _cropAttempted = _cropBounds != null;
      if (widget.cropBorders) {
        if (_cropBounds == null) {
          // Reattach to the same cached completer; this never creates a codec.
          _stopListening();
          _listen();
        }
        // Reattaching retrieves the cached frame synchronously. Sampling uses
        // its clone; the metadata listener must not resume paused animation.
        if (_paused && _hasFrame) _stopListening(keepAlive: true);
        _scheduleCrop();
      } else if (_paused && _hasFrame) {
        _stopListening(keepAlive: true);
      }
    }
  }

  void _resolve() {
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _stopListening();
    _streamHandle?.dispose();
    _streamHandle = null;
    _stream = stream;
    _epoch++;
    _cropEpoch++;
    _cropFrame?.dispose();
    _cropFrame = null;
    _cropBounds = null;
    _cropAttempted = false;
    _cropScheduled = false;
    _cropNotified = false;
    _animated = false;
    _dimensions = null;
    _notifiedDimensions = null;
    _hasFrame = false;
    _error = null;
    _errorNotified = false;
    _scheduled = false;
    _listen();
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    _stream!.addListener(_listener);
    _streamHandle?.dispose();
    _streamHandle = null;
  }

  void _stopListening({bool keepAlive = false}) {
    if (!_listening) return;
    if (keepAlive && _streamHandle == null) {
      _streamHandle = _stream?.completer?.keepAlive();
    }
    _stream?.removeListener(_listener);
    _listening = false;
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    try {
      _baseline?.event('image_info', {
        'resourceId': widget.resource.id,
        'generation': widget.resource.generation,
        'width': info.image.width,
        'height': info.image.height,
        'synchronousCall': synchronousCall,
      });
      _dimensions = ImageDimensions(
        width: info.image.width,
        height: info.image.height,
      );
      if (widget.cropBorders &&
          !_cropAttempted &&
          _cropFrame == null &&
          !_animated) {
        _cropFrame = info.image.clone();
      }
    } finally {
      // Each ImageStream listener receives its own cloned handle.
      info.dispose();
    }
    if (_hasFrame) _scheduleCrop();
    // frameBuilder is the presentation signal. A cached/prefetched ImageInfo
    // alone must never advance reading progress.
  }

  void _onError(Object error, StackTrace? stack) {
    final baseline = _baseline;
    if (baseline != null &&
        baseline.recording &&
        _baselineErrorIdentity != (session: baseline.session, epoch: _epoch)) {
      _baselineErrorIdentity = (session: baseline.session, epoch: _epoch);
      baseline.event('image_error', {
        'resourceId': widget.resource.id,
        'generation': widget.resource.generation,
        'errorType': error.runtimeType.toString(),
      });
    }
    _error = error;
    _cropEpoch++;
    _cropFrame?.dispose();
    _cropFrame = null;
    _cropBounds = null;
    _cropAttempted = false;
    _cropNotified = false;
    _dimensions = null;
    _hasFrame = false;
    _scheduleNotification();
  }

  void _scheduleNotification() {
    if (_scheduled || (_error != null && _errorNotified)) return;
    if (_error == null &&
        _notifiedDimensions != null &&
        _notifiedDimensions?.width == _dimensions?.width &&
        _notifiedDimensions?.height == _dimensions?.height) {
      return;
    }
    _scheduled = true;
    final epoch = _epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _epoch) return;
      _scheduled = false;
      if (_error case final Object error) {
        if (!_errorNotified) {
          _errorNotified = true;
          ReaderImageFailed(widget.resource.id, error).dispatch(context);
        }
        return;
      }
      final dimensions = _dimensions;
      if (!_hasFrame || dimensions == null) return;
      if (_notifiedDimensions?.width == dimensions.width &&
          _notifiedDimensions?.height == dimensions.height) {
        return;
      }
      _notifiedDimensions = dimensions;
      _baseline?.event('image_post_frame', {
        'resourceId': widget.resource.id,
        'generation': widget.resource.generation,
        'width': dimensions.width,
        'height': dimensions.height,
        'frameNumber': ui.PlatformDispatcher.instance.frameData.frameNumber,
      });
      if (_paused) _stopListening(keepAlive: true);
      ReaderImageDecoded(
        widget.resource.id,
        width: dimensions.width,
        height: dimensions.height,
      ).dispatch(context);
      _scheduleCrop();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _scheduleCrop() {
    if (!widget.cropBorders ||
        !_hasFrame ||
        _error != null ||
        _cropScheduled ||
        _cropNotified ||
        _cropInFlight) {
      return;
    }
    if (_cropBounds == null && (_cropAttempted || _cropFrame == null)) return;
    _cropScheduled = true;
    final epoch = _cropEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _cropEpoch) return;
      _cropScheduled = false;
      if (!widget.cropBorders || !_hasFrame || _error != null) return;
      if (_cropBounds != null) {
        _publishCrop();
        return;
      }
      final frame = _cropFrame;
      if (frame == null || _cropAttempted) return;
      _cropFrame = null;
      _cropAttempted = true;
      _cropInFlight = true;
      final work = _detectCrop(frame, epoch).whenComplete(() {
        _cropInFlight = false;
        if (mounted && widget.cropBorders) {
          // Rapid off/on changes wait for the previous bounded readback rather
          // than allocating another sample while it is still in flight.
          _cropAttempted = _cropBounds != null;
          _scheduleCrop();
        }
      });
      ReaderImageCropWork(widget.resource.id, work).dispatch(context);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _publishCrop() {
    final bounds = _cropBounds;
    final dimensions = _dimensions;
    if (!mounted ||
        !widget.cropBorders ||
        !_hasFrame ||
        _cropNotified ||
        bounds == null ||
        dimensions == null) {
      return;
    }
    _cropNotified = true;
    if (_paused) _stopListening(keepAlive: true);
    ReaderImageCrop(
      widget.resource.id,
      bounds: bounds,
      width: dimensions.width,
      height: dimensions.height,
    ).dispatch(context);
  }

  Future<void> _detectCrop(ui.Image frame, int epoch) async {
    final resource = widget.resource;
    final baseline = _baseline;
    ui.Image? sample;
    var bounds = _fullBounds;
    try {
      try {
        // A bounded readback of the existing UI frame, without another decoder.
        final scale = math.min(
          1.0,
          _cropSampleSide / math.max(frame.width, frame.height),
        );
        final width = math.max(1, (frame.width * scale).round());
        final height = math.max(1, (frame.height * scale).round());
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          frame,
          ui.Rect.fromLTWH(
            0,
            0,
            frame.width.toDouble(),
            frame.height.toDouble(),
          ),
          ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.medium,
        );
        final picture = recorder.endRecording();
        try {
          sample = picture.toImageSync(width, height);
        } finally {
          picture.dispose();
        }
      } finally {
        frame.dispose();
      }
      final bytes = await sample
          .toByteData(format: ui.ImageByteFormat.rawRgba)
          .timeout(const Duration(seconds: 3));
      if (bytes == null) throw StateError('UI pixels are unavailable');
      if (!mounted || epoch != _cropEpoch || !widget.cropBorders) return;
      final bitmap = img.Image.fromBytes(
        width: sample.width,
        height: sample.height,
        bytes: bytes.buffer,
        bytesOffset: bytes.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );
      bool white(img.Pixel pixel) =>
          pixel.a >= 250 && pixel.r >= 240 && pixel.g >= 240 && pixel.b >= 240;
      final top = bitmap.getPixel(0, 0);
      final bottom = bitmap.getPixel(bitmap.width - 1, bitmap.height - 1);
      final mode = white(top)
          ? img.TrimMode.topLeftColor
          : white(bottom)
          ? img.TrimMode.bottomRightColor
          : null;
      if (mode != null) {
        // The library handles border finding and JPEG fuzz; project code only
        // selects white margins and maps its bounded pixel result to the source.
        final crop = img.findTrim(bitmap, mode: mode, fuzzy: 0.04, padding: 2);
        bounds = ui.Rect.fromLTWH(
          crop[0] / bitmap.width,
          crop[1] / bitmap.height,
          crop[2] / bitmap.width,
          crop[3] / bitmap.height,
        );
      }
    } catch (error) {
      baseline?.event('image_crop_unavailable', {
        'resourceId': resource.id,
        'generation': resource.generation,
        'errorType': error.runtimeType.toString(),
      });
    } finally {
      sample?.dispose();
    }
    if (!mounted ||
        epoch != _cropEpoch ||
        !widget.cropBorders ||
        _error != null) {
      return;
    }
    _cropBounds = bounds;
    _publishCrop();
  }

  @override
  Widget build(BuildContext context) => Image(
    image: _provider,
    fit: widget.fit,
    gaplessPlayback: false,
    excludeFromSemantics: true,
    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
      if (frame != null && _error == null) {
        final baseline = _baseline;
        if (baseline != null && baseline.recording) {
          final identity = (
            session: baseline.session,
            epoch: _epoch,
            frame: frame,
          );
          if (_lastBaselineFrame != identity) {
            _lastBaselineFrame = identity;
            baseline.event('image_frame', {
              'resourceId': widget.resource.id,
              'generation': widget.resource.generation,
              'imageFrame': frame,
              'synchronouslyLoaded': wasSynchronouslyLoaded,
              'frameNumber':
                  ui.PlatformDispatcher.instance.frameData.frameNumber,
            });
          }
        }
        _hasFrame = true;
        if (frame > 0 && !_animated) {
          // Animated content can change outside its first frame's rectangle.
          _animated = true;
          _cropEpoch++;
          _cropFrame?.dispose();
          _cropFrame = null;
          _cropScheduled = false;
          _cropAttempted = true;
          _cropNotified = false;
          _cropBounds = _fullBounds;
        }
        _scheduleNotification();
        _scheduleCrop();
      }
      return child;
    },
    errorBuilder: (context, error, stack) {
      _onError(error, stack);
      return const Center(child: Text('无法显示这张图片'));
    },
  );

  @override
  void dispose() {
    _cropEpoch++;
    _cropFrame?.dispose();
    _cropFrame = null;
    _stopListening();
    _streamHandle?.dispose();
    super.dispose();
  }
}

Future<void> evictResourceImage(ImageResource resource) async {
  await platform.resourceImageProvider(resource).evict();
}
