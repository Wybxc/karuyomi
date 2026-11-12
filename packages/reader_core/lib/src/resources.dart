/// Reading state independent of Flutter, TeaVM and cloud storage.
library;

enum ReadingMode { leftToRight, rightToLeft, continuous, webtoon }

/// A logical anchor, preserved across rotation and layout changes.
final class ReadingPosition({
  required final String chapterKey,
  required final String pageKey,
  required final String manifestVersion,
  required final int pageIndexHint,

  /// Original source-image y coordinate.
  required final double normalizedOffset,

  /// Original source-image x coordinate; RTL does not reverse it.
  final double normalizedX = 0,

  /// Position of that source point within the reading viewport.
  final double viewportX = 0,
  final double viewportY = 0,
}) {
  this {
    if (chapterKey.isEmpty || pageKey.isEmpty || manifestVersion.isEmpty) {
      throw ArgumentError('Reading anchors require stable identifiers');
    }
    if (pageIndexHint < 0 ||
        [normalizedOffset, normalizedX, viewportX, viewportY].any(
          (coordinate) =>
              !coordinate.isFinite || coordinate < 0 || coordinate > 1,
        )) {
      throw ArgumentError('Invalid reading anchor');
    }
  }
}

/// The reading view must acquire processed images through this boundary.
abstract interface class PageProvider {
  Future<ImageResource> acquire(PageRef page);
  Future<void> cancel(String requestId);
  Future<void> release(String resourceId);
}

final class const PageRef({
  required final String requestId,
  required final String chapterKey,
  required final String pageKey,
  required final String generation,
});

/// Web adapters return a revocable object URL; native adapters a managed file.
/// Resource ownership remains with the provider until [PageProvider.release].
final class ImageResource({
  required final String id,
  required final String generation,
  required final Uri location,
  required final int byteLength,
}) {
  this {
    if (id.isEmpty || generation.isEmpty || byteLength <= 0) {
      throw ArgumentError(
        'Image resources require valid identity and encoded bytes',
      );
    }
  }
}

/// Dimensions learned from the client's actual decoded frame, never the Source.
final class ImageDimensions({
  required final int width,
  required final int height,
}) {
  this {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Decoded image dimensions must be positive');
    }
  }
  int get decodedBytes => width * height * 4;
}
