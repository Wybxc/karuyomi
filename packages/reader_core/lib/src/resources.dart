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
  }) {
    if (chapterKey.isEmpty || pageKey.isEmpty || manifestVersion.isEmpty) {
      throw ArgumentError('Reading anchors require stable identifiers');
    }
    if (pageIndexHint < 0 ||
        !normalizedOffset.isFinite ||
        normalizedOffset < 0 ||
        normalizedOffset > 1) {
      throw ArgumentError('Invalid reading anchor');
    }
  }

  final String chapterKey;
  final String pageKey;
  final String manifestVersion;
  final int pageIndexHint;
  final double normalizedOffset;
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
    required this.mimeType,
    required this.byteLength,
    required this.width,
    required this.height,
  }) {
    if (id.isEmpty ||
        generation.isEmpty ||
        byteLength <= 0 ||
        width <= 0 ||
        height <= 0) {
      throw ArgumentError(
        'Image resources require valid identity, bytes and dimensions',
      );
    }
  }

  final String id;
  final String generation;
  final Uri location;
  final String mimeType;
  final int byteLength;
  final int width;
  final int height;
}
