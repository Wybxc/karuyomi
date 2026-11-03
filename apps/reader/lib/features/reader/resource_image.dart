import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:reader_core/reader_core.dart';
import 'resource_image_web.dart'
    if (dart.library.io) 'resource_image_native.dart'
    as platform;

Widget buildResourceImage(
  BuildContext context,
  ImageResource resource,
  BoxFit fit,
) => _ResourceImage(key: ValueKey(resource.id), resource: resource, fit: fit);

class _ResourceImage extends StatefulWidget {
  const _ResourceImage({super.key, required this.resource, required this.fit});
  final ImageResource resource;
  final BoxFit fit;

  @override
  State<_ResourceImage> createState() => _ResourceImageState();
}

class _ResourceImageState extends State<_ResourceImage> {
  late ImageProvider<Object> _image;

  @override
  void initState() {
    super.initState();
    _image = platform.resourceImageProvider(widget.resource);
  }

  @override
  void didUpdateWidget(_ResourceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resource.location != widget.resource.location) {
      unawaited(_image.evict());
      _image = platform.resourceImageProvider(widget.resource);
    }
  }

  @override
  Widget build(BuildContext context) => Image(
    image: _image,
    fit: widget.fit,
    gaplessPlayback: false,
    excludeFromSemantics: true,
    errorBuilder: (context, error, stack) =>
        const Center(child: Text('无法显示这张图片')),
  );

  @override
  void dispose() {
    // Leaving the scheduler window must also remove the decoded Flutter cache
    // entry. Releasing an object URL or native file alone does not do that.
    unawaited(_image.evict());
    super.dispose();
  }
}
