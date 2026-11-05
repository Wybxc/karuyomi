import 'resources.dart';

final class ReaderPage {
  ReaderPage({
    required this.key,
    this.width,
    this.height,
    this.contentAspectRatio,
  }) {
    if (key.isEmpty) throw ArgumentError('Page key cannot be empty');
    if ((width == null) != (height == null) ||
        (width != null && (!width!.isFinite || width! <= 0)) ||
        (height != null && (!height!.isFinite || height! <= 0))) {
      throw ArgumentError('Page dimensions must be finite positive pairs');
    }
    if (contentAspectRatio != null &&
        (!contentAspectRatio!.isFinite || contentAspectRatio! <= 0)) {
      throw ArgumentError('Content aspect ratio must be finite and positive');
    }
  }

  final String key;
  final double? width;
  final double? height;

  /// Learned display geometry only; source dimensions and decode budgets remain
  /// those of the complete original image.
  final double? contentAspectRatio;
  double get originalAspectRatio => width == null ? 2 / 3 : width! / height!;
  double get aspectRatio => contentAspectRatio ?? originalAspectRatio;
  bool get isLandscape => aspectRatio > 1;

  /// Diagnostic estimate only; this is not measured process or GPU memory.
  int? get estimatedDecodedBytes =>
      width == null ? null : (width! * height! * 4).ceil();
}

final class ChapterManifest {
  ChapterManifest({
    required this.chapterKey,
    required this.version,
    required Iterable<ReaderPage> pages,
  }) : pages = List.unmodifiable(pages) {
    if (chapterKey.isEmpty || version.isEmpty) {
      throw ArgumentError('Chapter and manifest version must be explicit');
    }
    if (this.pages.map((page) => page.key).toSet().length !=
        this.pages.length) {
      throw ArgumentError('Page keys must be unique within a chapter');
    }
  }

  final String chapterKey;
  final String version;
  final List<ReaderPage> pages;

  ReadingPosition positionAt(
    int index, {
    double offset = 0,
    double normalizedX = 0,
    double viewportX = 0,
    double viewportY = 0,
  }) => ReadingPosition(
    chapterKey: chapterKey,
    pageKey: pages[index].key,
    manifestVersion: version,
    pageIndexHint: index,
    normalizedOffset: offset,
    normalizedX: normalizedX,
    viewportX: viewportX,
    viewportY: viewportY,
  );
}

final class PageSpread {
  PageSpread(Iterable<ReaderPage> pages) : pages = List.unmodifiable(pages);
  final List<ReaderPage> pages;

  /// RTL changes the spread's presentation order, never the source page order.
  List<ReaderPage> displayPages(ReadingMode mode) =>
      mode == ReadingMode.rightToLeft ? pages.reversed.toList() : pages;
}

List<PageSpread> groupPages(
  ChapterManifest manifest, {
  required bool doublePage,
  bool coverAlone = true,
}) {
  final spreads = <PageSpread>[];
  ReaderPage? pending;
  for (var index = 0; index < manifest.pages.length; index++) {
    final page = manifest.pages[index];
    final alone = !doublePage || page.isLandscape || (coverAlone && index == 0);
    if (alone) {
      if (pending != null) spreads.add(PageSpread([pending]));
      pending = null;
      spreads.add(PageSpread([page]));
    } else if (pending == null) {
      pending = page;
    } else {
      spreads.add(PageSpread([pending, page]));
      pending = null;
    }
  }
  if (pending != null) spreads.add(PageSpread([pending]));
  return List.unmodifiable(spreads);
}

enum PositionResolutionKind { exactPage, missingPage, differentChapter, empty }

final class PositionResolution {
  const PositionResolution(this.position, this.kind);
  final ReadingPosition? position;
  final PositionResolutionKind kind;
  bool get requiresNotice =>
      kind == PositionResolutionKind.missingPage ||
      kind == PositionResolutionKind.differentChapter;
}

/// Stable page identity takes precedence over hints, including after reordering.
/// Missing identities are explicitly reported, never silently treated as exact.
PositionResolution resolvePosition(
  ChapterManifest manifest,
  ReadingPosition? previous,
) {
  if (manifest.pages.isEmpty) {
    return const PositionResolution(null, PositionResolutionKind.empty);
  }
  if (previous == null) {
    return PositionResolution(
      manifest.positionAt(0),
      PositionResolutionKind.exactPage,
    );
  }
  if (previous.chapterKey != manifest.chapterKey) {
    return PositionResolution(
      manifest.positionAt(0),
      PositionResolutionKind.differentChapter,
    );
  }
  final index = manifest.pages.indexWhere(
    (page) => page.key == previous.pageKey,
  );
  if (index >= 0) {
    return PositionResolution(
      manifest.positionAt(
        index,
        offset: previous.normalizedOffset,
        normalizedX: previous.normalizedX,
        viewportX: previous.viewportX,
        viewportY: previous.viewportY,
      ),
      PositionResolutionKind.exactPage,
    );
  }
  return PositionResolution(
    manifest.positionAt(
      previous.pageIndexHint.clamp(0, manifest.pages.length - 1),
    ),
    PositionResolutionKind.missingPage,
  );
}
