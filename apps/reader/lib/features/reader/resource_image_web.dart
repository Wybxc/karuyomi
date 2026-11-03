import 'package:flutter/widgets.dart';
import 'package:reader_core/reader_core.dart';

ImageProvider<Object> resourceImageProvider(ImageResource resource) {
  if (resource.location.scheme != 'blob') {
    throw UnsupportedError('Web images require a managed Blob URL');
  }
  return NetworkImage(resource.location.toString());
}
