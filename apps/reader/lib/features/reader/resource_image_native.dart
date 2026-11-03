import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:reader_core/reader_core.dart';

ImageProvider<Object> resourceImageProvider(ImageResource resource) =>
    resource.location.scheme == 'file'
    ? FileImage(File.fromUri(resource.location))
    : NetworkImage(resource.location.toString());
