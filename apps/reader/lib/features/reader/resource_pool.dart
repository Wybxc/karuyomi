import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:reader_core/reader_core.dart';
import 'resource_image.dart';

final class _HeldImage {
  _HeldImage(this.image);
  final ImageResource image;
  int pins = 0;
  Completer<void>? release;
  bool releasing = false;
  bool evicting = false;
  Object? displayCleanupError;
}

/// Scheduler ownership and displayed widgets have independent lifetimes.
/// The Blob/file is released only after the last widget has left the frame and
/// the matching decoded Flutter cache entry has been evicted.
final class ReaderResourcePool implements PageProvider {
  ReaderResourcePool(
    this.provider, {
    Future<void> Function(ImageResource)? evict,
  }) : _evict = evict ?? evictResourceImage;
  final PageProvider provider;
  final Future<void> Function(ImageResource) _evict;
  final _images = <String, _HeldImage>{};

  @override
  Future<ImageResource> acquire(PageRef page) async {
    final image = await provider.acquire(page);
    if (_images.containsKey(image.id)) {
      throw StateError('The provider reused a live image resource ID');
    }
    _images[image.id] = _HeldImage(image);
    return image;
  }

  @override
  Future<void> cancel(String requestId) => provider.cancel(requestId);

  ReaderImagePin pin(String resourceId) {
    final image = _images[resourceId];
    if (image == null || image.releasing) {
      throw StateError('Cannot display a released image');
    }
    image.pins++;
    return ReaderImagePin._(() => _unpin(image));
  }

  Future<void> _unpin(_HeldImage image) async {
    // Widget.dispose runs while the element tree is being removed. Retain the
    // resource until the frame completes, including route/dialog transitions.
    await WidgetsBinding.instance.endOfFrame;
    image.pins--;
    if (image.pins == 0) {
      image.evicting = true;
      try {
        await _evict(image.image);
      } catch (error) {
        image.displayCleanupError = error;
      } finally {
        image.evicting = false;
      }
    }
    _tryRelease(image);
  }

  @override
  Future<void> release(String resourceId) {
    final image = _images[resourceId];
    if (image == null) return Future.value();
    final completion = image.release ??= Completer<void>();
    _tryRelease(image);
    return completion.future;
  }

  void _tryRelease(_HeldImage image) {
    if (image.release == null ||
        image.releasing ||
        image.evicting ||
        image.pins != 0) {
      return;
    }
    image.releasing = true;
    unawaited(() async {
      try {
        if (image.displayCleanupError case final Object error) throw error;
        await provider.release(image.image.id);
        _images.remove(image.image.id);
        image.release!.complete();
      } catch (error, stack) {
        image.release!.completeError(error, stack);
      }
    }());
  }
}

final class ReaderImagePin {
  ReaderImagePin._(this._close);
  final Future<void> Function() _close;
  Future<void>? _closing;
  Future<void> close() => _closing ??= _close();
}

/// Also wraps injected test renderers so display ownership has one policy.
class PinnedReaderImage extends StatefulWidget {
  const PinnedReaderImage({
    super.key,
    required this.pool,
    required this.image,
    required this.builder,
  });
  final ReaderResourcePool pool;
  final ImageResource image;
  final WidgetBuilder builder;
  @override
  State<PinnedReaderImage> createState() => _PinnedReaderImageState();
}

class _PinnedReaderImageState extends State<PinnedReaderImage> {
  late ReaderImagePin _pin;
  @override
  void initState() {
    super.initState();
    _pin = widget.pool.pin(widget.image.id);
  }

  @override
  void didUpdateWidget(PinnedReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pool != widget.pool ||
        oldWidget.image.id != widget.image.id) {
      unawaited(_pin.close());
      _pin = widget.pool.pin(widget.image.id);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
  @override
  void dispose() {
    unawaited(_pin.close());
    super.dispose();
  }
}
