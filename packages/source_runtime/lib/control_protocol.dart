/// Generated control models and the standard ProtoJSON boundary codec.
library;

import 'dart:convert';
import 'package:protobuf/protobuf.dart';
import 'src/pb/karuyomi/v1/control.pb.dart';

export 'src/pb/karuyomi/v1/control.pb.dart';

const controlJsonLimit = 8 * 1024 * 1024;
const controlRequestLimit = 128 * 1024;
const sourceMemoLimit = 64 * 1024;
const controlJsonDepthLimit = 64;
const encodedImageByteLimit = 8 * 1024 * 1024;
const encodedImageRawWidthLimit = 4096;
const encodedPngRawHeightLimit = 100000;
const encodedJpegRawHeightLimit = 65500;

/// An encoded page is not a decoded surface; raw pixels do not spend a raster budget.
void checkEncodedImage(EncodedImage image) {
  final maxHeight = switch (image.mimeType) {
    'image/png' => encodedPngRawHeightLimit,
    'image/jpeg' => encodedJpegRawHeightLimit,
    _ => 0,
  };
  if (image.resourceId.isEmpty ||
      image.resourceId.length > 200 ||
      image.generation.isEmpty ||
      image.generation.length > 200 ||
      image.byteLength <= 0 ||
      image.byteLength > encodedImageByteLimit ||
      image.rawWidth <= 0 ||
      image.rawWidth > encodedImageRawWidthLimit ||
      image.rawHeight <= 0 ||
      image.rawHeight > maxHeight ||
      image.orientation < 1 ||
      image.orientation > 8) {
    throw const FormatException('Invalid encoded image descriptor');
  }
}

const imageTileByteLimit = 8 * 1024 * 1024;
const imageTileCacheByteLimit = 16 * 1024 * 1024;
const imageTileCountLimit = 64;
const imageTilePixelLimit = 32 * 1024 * 1024;
const imageWindowWaitLimitMs = 25000;

bool _validImageId(String value) => value.isNotEmpty && value.length <= 200;
bool _validDenominator(int value) => const [1, 2, 4].contains(value);
bool _uint32(int value) => value >= 0 && value <= 0xffffffff;
int _scaled(int value, int denominator) =>
    (value + denominator - 1) ~/ denominator;

/// A logical page retains one encoded Source output without rasterizing it.
void checkImagePage(ImagePage page) {
  if (!_validImageId(page.pageId) ||
      !_validImageId(page.generation) ||
      !page.hasEncoded()) {
    throw const FormatException('Invalid image page identity');
  }
  checkEncodedImage(page.encoded);
  if (page.encoded.generation != page.generation) {
    throw const FormatException('Image page generation mismatch');
  }
}

/// Small PNG surfaces are checked before a display adapter can borrow them.
/// A native file additionally needs proof from the transport ownership table.
void checkImageWindow(
  ImageWindowSnapshot snapshot, {
  bool Function(ImageResource resource)? isManagedFile,
}) {
  if (!_validImageId(snapshot.pageId) ||
      !_validImageId(snapshot.generation) ||
      !_validImageId(snapshot.windowId) ||
      !_uint32(snapshot.revision) ||
      !const [
        ImageWindowState.IMAGE_WINDOW_STATE_PENDING,
        ImageWindowState.IMAGE_WINDOW_STATE_COMPLETE,
        ImageWindowState.IMAGE_WINDOW_STATE_FAILED,
      ].contains(snapshot.state) ||
      (snapshot.state == ImageWindowState.IMAGE_WINDOW_STATE_FAILED) !=
          snapshot.hasError() ||
      (snapshot.tiles.isNotEmpty && !snapshot.hasHeader()) ||
      (snapshot.state == ImageWindowState.IMAGE_WINDOW_STATE_COMPLETE &&
          (!snapshot.hasHeader() ||
              snapshot.tiles.any((tile) => tile.provisional)))) {
    throw const FormatException('Invalid image window descriptor');
  }
  if (snapshot.hasError() &&
      snapshot.error.code == RuntimeErrorCode.RUNTIME_ERROR_CODE_UNSPECIFIED) {
    throw const FormatException('Invalid image window failure');
  }
  final header = snapshot.hasHeader() ? snapshot.header : null;
  if (header != null &&
      (!_validDenominator(header.denominator) ||
          header.sourceWidth <= 0 ||
          header.sourceWidth > encodedImageRawWidthLimit ||
          header.sourceHeight <= 0 ||
          header.sourceHeight > encodedPngRawHeightLimit ||
          header.width != _scaled(header.sourceWidth, header.denominator) ||
          header.height != _scaled(header.sourceHeight, header.denominator))) {
    throw const FormatException('Invalid decoded image header');
  }
  final ids = <String>{};
  final indices = <int>{};
  var pixels = 0;
  var bytes = 0;
  for (final tile in snapshot.tiles) {
    if (!_validImageId(tile.leaseId) ||
        !_validImageId(tile.sessionId) ||
        !ids.add(tile.leaseId) ||
        !_uint32(tile.index) ||
        !indices.add(tile.index) ||
        !tile.hasSourceRect() ||
        !tile.hasResource() ||
        !_validDenominator(tile.denominator)) {
      throw const FormatException('Invalid image tile identity');
    }
    final resource = tile.resource;
    final rect = tile.sourceRect;
    final location = resource.url.length <= 4096
        ? Uri.tryParse(resource.url)
        : null;
    final managed =
        location != null &&
        location.scheme == 'file' &&
        isManagedFile != null &&
        isManagedFile(resource);
    if (location == null ||
        (location.scheme != 'blob' && !managed) ||
        resource.resourceId != tile.leaseId ||
        resource.generation != snapshot.generation ||
        resource.mimeType != 'image/png' ||
        resource.byteLength <= 0 ||
        resource.byteLength > imageTileByteLimit ||
        resource.width <= 0 ||
        resource.width > encodedImageRawWidthLimit ||
        resource.height <= 0 ||
        resource.height > 256 ||
        rect.x != 0 ||
        rect.y < 0 ||
        rect.width <= 0 ||
        rect.width > encodedImageRawWidthLimit ||
        rect.height <= 0 ||
        rect.y + rect.height > encodedPngRawHeightLimit ||
        resource.width != _scaled(rect.width, tile.denominator) ||
        resource.height != _scaled(rect.height, tile.denominator) ||
        rect.y != tile.index * 256 * tile.denominator ||
        header == null ||
        tile.denominator != header.denominator ||
        rect.width != header.sourceWidth ||
        resource.width != header.width ||
        rect.y >= header.sourceHeight ||
        rect.height !=
            (resource.height * tile.denominator).clamp(
              0,
              header.sourceHeight - rect.y,
            ) ||
        resource.height != (header.height - tile.index * 256).clamp(0, 256)) {
      throw const FormatException('Invalid PNG tile resource or geometry');
    }
    pixels += resource.width * resource.height;
    bytes += resource.byteLength;
  }
  for (final id in snapshot.invalidatedLeaseIds) {
    if (!_validImageId(id) || !ids.add(id)) {
      throw const FormatException('Invalid image tile invalidation');
    }
  }
  if (ids.length > imageTileCountLimit ||
      pixels > imageTilePixelLimit ||
      bytes > imageTileCacheByteLimit) {
    throw const FormatException('Image window exceeds its lease budget');
  }
}

/// Checks transport budgets, without duplicating the generated field schema.
void _checkJsonNesting(Object? value) {
  final pending = <(Object?, int)>[(value, 0)];
  while (pending.isNotEmpty) {
    final (item, depth) = pending.removeLast();
    if (depth > controlJsonDepthLimit) {
      throw const FormatException('Control JSON nesting exceeds its budget');
    }
    if (item is Map) {
      for (final entry in item.entries) {
        if (entry.key is! String) {
          throw const FormatException(
            'Control JSON object keys must be strings',
          );
        }
        pending.add((entry.value, depth + 1));
      }
    } else if (item is List) {
      pending.addAll(item.map((child) => (child, depth + 1)));
    }
  }
}

void checkJsonBudget(Object? value, {int maxBytes = controlJsonLimit}) {
  _checkJsonNesting(value);
  try {
    if (utf8.encode(jsonEncode(value)).length > maxBytes) {
      throw const FormatException('Control JSON exceeds its byte budget');
    }
  } on JsonUnsupportedObjectError {
    throw const FormatException('Control payload is not valid JSON');
  }
}

T decodeProtoJson<T extends GeneratedMessage>(
  T message,
  Object? value, {
  int maxBytes = controlJsonLimit,
}) {
  if (value is! Map) {
    throw const FormatException('Expected a ProtoJSON object');
  }
  checkJsonBudget(value, maxBytes: maxBytes);
  _checkOneofFields(message, value);
  message.mergeFromProto3Json(value);
  return message;
}

// The Dart runtime accepts last-one-wins ProtoJSON oneofs. The control boundary
// requires one explicit command/result, matching Protobuf-ES. Reflect generated
// descriptors rather than maintaining another list of protocol fields.
void _checkOneofFields(GeneratedMessage message, Map<Object?, Object?> value) {
  final fields = <String, FieldInfo<Object?>>{};
  for (final field in message.info_.fieldInfo.values) {
    fields[field.name] = field;
    fields[field.protoName] = field;
  }
  final seenFields = <int>{};
  final seenOneofs = <int>{};
  for (final entry in value.entries) {
    final field = fields[entry.key];
    if (field == null || entry.value == null) continue;
    final oneof = message.info_.oneofs[field.tagNumber];
    if (!seenFields.add(field.tagNumber) ||
        (oneof != null && !seenOneofs.add(oneof))) {
      throw const FormatException('Conflicting ProtoJSON field or oneof');
    }
    final builder = field.subBuilder;
    if (builder != null) {
      if (field.isRepeated && entry.value is List) {
        for (final child in entry.value as List) {
          if (child is Map) _checkOneofFields(builder(), child);
        }
      } else if (entry.value is Map) {
        _checkOneofFields(builder(), entry.value as Map);
      }
    }
  }
}

Map<String, Object?> encodeProtoJson(
  GeneratedMessage message, {
  int maxBytes = controlRequestLimit,
}) {
  final value = message.toProto3Json();
  checkJsonBudget(value, maxBytes: maxBytes);
  return Map<String, Object?>.from(value as Map);
}

/// Validate opaque Source JSON without decoding and rewriting its numeric text.
void checkSourceMemo(String value) {
  if (utf8.encode(value).length > sourceMemoLimit) {
    throw const FormatException('Source memo exceeds its byte budget');
  }
  final decoded = jsonDecode(value);
  if (decoded is! Map) {
    throw const FormatException('Source memo must contain a JSON object');
  }
  _checkJsonNesting(decoded);
}
