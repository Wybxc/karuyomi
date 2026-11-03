import 'package:flutter/widgets.dart';
import 'package:reader_core/reader_core.dart';
import 'resource_image_web.dart'
    if (dart.library.io) 'resource_image_native.dart'
    as platform;

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
  errorBuilder: (context, error, stack) =>
      const Center(child: Text('无法显示这张图片')),
);

Future<void> evictResourceImage(ImageResource resource) async {
  await platform.resourceImageProvider(resource).evict();
}
