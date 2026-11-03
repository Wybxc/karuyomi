import 'package:flutter/widgets.dart';
import 'package:reader_core/reader_core.dart';
import 'resource_image_web.dart'
    if (dart.library.io) 'resource_image_native.dart'
    as platform;

/// Emitted by Flutter's decoder after a frame, never by resource prefetch.
class ReaderImageDecoded extends Notification {
  const ReaderImageDecoded(this.resourceId);
  final String resourceId;
}

Widget buildResourceImage(
  BuildContext context,
  ImageResource resource,
  BoxFit fit,
) => Image(
  key: ValueKey(resource.id),
  image: platform.resourceImageProvider(resource),
  fit: fit,
  gaplessPlayback: false,
  excludeFromSemantics: true,
  frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
    if (frame != null) ReaderImageDecoded(resource.id).dispatch(context);
    return child;
  },
  errorBuilder: (context, error, stack) =>
      const Center(child: Text('无法显示这张图片')),
);

Future<void> evictResourceImage(ImageResource resource) async {
  await platform.resourceImageProvider(resource).evict();
}
