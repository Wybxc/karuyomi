import 'package:flutter/widgets.dart';
import 'package:reader_core/reader_core.dart';

ImageProvider<Object> resourceImageProvider(ImageResource resource) =>
    NetworkImage(resource.location.toString());
