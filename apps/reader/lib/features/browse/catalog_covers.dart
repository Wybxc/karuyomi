part of 'catalog_controller.dart';

Uri? sourceThumbnail(String value) {
  if (value.isEmpty || value.length > 4096) return null;
  final url = Uri.tryParse(value);
  return url != null &&
          (url.scheme == 'http' || url.scheme == 'https') &&
          url.host.isNotEmpty &&
          url.userInfo.isEmpty
      ? url
      : null;
}

extension CatalogCovers on CatalogController {
  Future<Uint8List?> readSourceCover({
    required CatalogSourceRef source,
    required Uri thumbnail,
    required String requestId,
    required bool Function() stillVisible,
  }) async {
    bool current() =>
        !closed &&
        !accessPaused &&
        stillVisible() &&
        isCurrentSource(source) &&
        session?.capabilities.contains('cover-image-resources') == true;
    if (!current()) return null;
    return (_coverPool ??= Pool(2)).withResource(() async {
      if (!current()) return null;
      _activeCovers.add(requestId);
      ImageResource? image;
      try {
        image = await runtime.acquireImage(
          ImageAcquireRequest(
            requestId: requestId,
            sourceId: source.sourceId,
            pageSessionId: '',
            pageKey: '',
            generation: source.generation,
            timeout: const Duration(seconds: 10),
            thumbnailUrl: thumbnail,
          ),
        );
        if (!current()) return null;
        if (image.generation != source.generation ||
            image.byteLength > wire.coverByteLimit ||
            !{'blob', 'file'}.contains(image.location.scheme)) {
          throw const FormatException('Invalid managed Source cover resource');
        }
        final file = XFile(
          image.location.scheme == 'file'
              ? image.location.toFilePath()
              : image.location.toString(),
        );
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in file.openRead()) {
          if (chunk.length > image.byteLength - bytes.length) {
            throw const FormatException(
              'Source cover exceeds its announced size',
            );
          }
          bytes.add(chunk);
        }
        if (bytes.length != image.byteLength) {
          throw const FormatException(
            'Source cover length does not match its resource',
          );
        }
        return current() ? bytes.takeBytes() : null;
      } finally {
        _activeCovers.remove(requestId);
        if (image != null) {
          await runtime.releaseImage(
            ImageReleaseRequest(
              resourceId: image.id,
              generation: image.generation,
            ),
          );
        }
      }
    });
  }

  Future<void> cancelSourceCover(
    String requestId,
    CatalogSourceRef source,
  ) async {
    if (!_activeCovers.contains(requestId) || !isCurrentSource(source)) return;
    try {
      await runtime.cancelImage(
        ImageCancelRequest(requestId: requestId, generation: source.generation),
      );
    } catch (_) {
      // A retiring Source closes pending acquisitions with its generation.
    }
  }
}
