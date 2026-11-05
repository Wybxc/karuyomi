import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

const _inputLimit = 16 * 1024 * 1024;
const _pixelLimit = 32 * 1000 * 1000;
const _outputLimit = 1024 * 1024;

Future<Uint8List?> selectCoverImage() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: '图片',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
        uniformTypeIdentifiers: ['public.image'],
      ),
    ],
  );
  if (file == null) return null;
  final length = await file.length();
  if (length <= 0 || length > _inputLimit) {
    throw const FormatException('请选择不超过 16 MiB 的图片。');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead(0, length)) {
    if (bytes.length + chunk.length > _inputLimit) {
      throw const FormatException('请选择不超过 16 MiB 的图片。');
    }
    bytes.add(chunk);
  }
  return compute(normalizeCoverImage, bytes.takeBytes());
}

/// Header validation precedes pixel allocation. Only the first image frame is
/// used; normalization changes the user-selected cover, never a Source image.
Uint8List normalizeCoverImage(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > _inputLimit) {
    throw const FormatException('请选择不超过 16 MiB 的图片。');
  }
  final decoder = img.findDecoderForData(bytes);
  final header = decoder?.startDecode(bytes);
  if (decoder == null || header == null) {
    throw const FormatException('无法识别图片，请选择 JPEG、PNG 或 WebP 图片。');
  }
  if (header.width <= 0 ||
      header.height <= 0 ||
      header.width * header.height > _pixelLimit) {
    throw const FormatException('图片像素超过 3200 万，请先缩小图片。');
  }
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) throw const FormatException('未能读取图片。');
  var image = img.bakeOrientation(decoded);
  if (math.max(image.width, image.height) > 1024) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 1024 : null,
      height: image.height > image.width ? 1024 : null,
      interpolation: img.Interpolation.average,
    );
  }
  final result = img.encodeJpg(image, quality: 85);
  if (result.length > _outputLimit) {
    throw const FormatException('处理后的封面仍超过 1 MiB，请选择更简单的图片。');
  }
  return result;
}
