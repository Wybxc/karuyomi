import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
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

Widget buildResourceImage(
  BuildContext context,
  ImageResource resource,
  BoxFit fit,
) => ResourceImage(key: ValueKey(resource.id), resource: resource, fit: fit);

/// Observes the same cached provider/completer used by Image. The extra listener
/// owns only an ImageInfo handle; it never creates a codec or decodes bytes.
class ResourceImage extends StatefulWidget {
  const ResourceImage({
    super.key,
    required this.resource,
    required this.fit,
    this.imageProvider,
  });

  final ImageResource resource;
  final BoxFit fit;
  final ImageProvider<Object>? imageProvider;

  @override
  State<ResourceImage> createState() => _ResourceImageState();
}

class _ResourceImageState extends State<ResourceImage> {
  late ImageProvider<Object> _provider;
  ImageStream? _stream;
  ImageStreamCompleterHandle? _streamHandle;
  bool _listening = false;
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
  }

  void _resolve() {
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _stopListening();
    _streamHandle?.dispose();
    _streamHandle = null;
    _stream = stream;
    _epoch++;
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
    } finally {
      // Each ImageStream listener receives its own cloned handle.
      info.dispose();
    }
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
    });
    WidgetsBinding.instance.ensureVisualUpdate();
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
        _scheduleNotification();
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
    _stopListening();
    _streamHandle?.dispose();
    super.dispose();
  }
}

Future<void> evictResourceImage(ImageResource resource) async {
  await platform.resourceImageProvider(resource).evict();
}
