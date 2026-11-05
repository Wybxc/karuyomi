/// Reading state independent of Flutter, TeaVM and cloud storage.
library;

enum ReadingMode { leftToRight, rightToLeft, continuous, webtoon }

/// A logical anchor, preserved across rotation and layout changes.
final class ReadingPosition {
  ReadingPosition({
    required this.chapterKey,
    required this.pageKey,
    required this.manifestVersion,
    required this.pageIndexHint,
    required this.normalizedOffset,
    this.normalizedX = 0,
    this.viewportX = 0,
    this.viewportY = 0,
  }) {
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

  final String chapterKey;
  final String pageKey;
  final String manifestVersion;
  final int pageIndexHint;

  /// Original source-image y coordinate.
  final double normalizedOffset;

  /// Original source-image x coordinate; RTL does not reverse it.
  final double normalizedX;

  /// Position of that source point within the reading viewport.
  final double viewportX;
  final double viewportY;
}

/// The reading view must acquire processed images through this boundary.
abstract interface class PageProvider {
  Future<ImageResource> acquire(PageRef page);
  Future<void> cancel(String requestId);
  Future<void> release(String resourceId);
}

final class PageRef {
  const PageRef({
    required this.requestId,
    required this.chapterKey,
    required this.pageKey,
    required this.generation,
  });

  final String requestId;
  final String chapterKey;
  final String pageKey;
  final String generation;
}

/// Web adapters return a revocable object URL; native adapters a managed file.
/// Resource ownership remains with the provider until [PageProvider.release].
final class ImageResource {
  ImageResource({
    required this.id,
    required this.generation,
    required this.location,
    required this.byteLength,
  }) {
    if (id.isEmpty || generation.isEmpty || byteLength <= 0) {
      throw ArgumentError(
        'Image resources require valid identity and encoded bytes',
      );
    }
  }

  final String id;
  final String generation;
  final Uri location;
  final int byteLength;
}

/// Dimensions learned from the client's actual decoded frame, never the Source.
final class ImageDimensions {
  ImageDimensions({required this.width, required this.height}) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Decoded image dimensions must be positive');
    }
  }

  final int width;
  final int height;
  int get decodedBytes => width * height * 4;
}
