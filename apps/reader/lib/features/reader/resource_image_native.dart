import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:reader_core/reader_core.dart';

ImageProvider<Object> resourceImageProvider(ImageResource resource) {
  if (resource.location.scheme != 'file') {
    throw UnsupportedError('Native images require a managed local file');
  }
  return FileImage(File.fromUri(resource.location));
}
