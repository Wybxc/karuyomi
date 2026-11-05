import 'dart:async';
import 'layout.dart';
import 'resources.dart';

final class ReaderController {
  ReaderController({
    required ChapterManifest manifest,
    ReadingPosition? initialPosition,
    ReadingMode mode = ReadingMode.leftToRight,
    bool doublePage = false,
    bool coverAlone = true,
  }) : _manifest = manifest,
       // Keep public constructor names; all mutable state uses setLayout.
       // ignore: prefer_initializing_formals
       _mode = mode,
       // ignore: prefer_initializing_formals
       _doublePage = doublePage,
       // ignore: prefer_initializing_formals
       _coverAlone = coverAlone,
       _resolution = resolvePosition(manifest, initialPosition);

  ChapterManifest _manifest;
  ReadingMode _mode;
  bool _doublePage;
  final bool _coverAlone;
  PositionResolution _resolution;
  final _changes = StreamController<void>.broadcast(sync: true);
  bool _disposed = false;

  ChapterManifest get manifest => _manifest;
  ReadingMode get mode => _mode;
  bool get doublePage => _doublePage;
  ReadingPosition? get position => _resolution.position;
  PositionResolutionKind get resolutionKind => _resolution.kind;
  bool get requiresPositionNotice => _resolution.requiresNotice;
  bool get isContinuous =>
      _mode == ReadingMode.continuous || _mode == ReadingMode.webtoon;
  Stream<void> get changes => _changes.stream;
  List<PageSpread> get spreads => groupPages(
    _manifest,
    doublePage: _doublePage && !isContinuous,
    coverAlone: _coverAlone,
  );

  int get pageIndex => position?.pageIndexHint ?? 0;
  int get spreadIndex {
    final key = position?.pageKey;
    final index = spreads.indexWhere(
      (spread) => spread.pages.any((page) => page.key == key),
    );
    return index < 0 ? 0 : index;
  }

  bool get canAdvance =>
      _manifest.pages.isNotEmpty && spreadIndex < spreads.length - 1;
  bool get canGoBack => _manifest.pages.isNotEmpty && spreadIndex > 0;

  void setLayout({ReadingMode? mode, bool? doublePage}) {
    _mode = mode ?? _mode;
    _doublePage = doublePage ?? _doublePage;
    _notify();
  }

  void updateManifest(ChapterManifest manifest) {
    _resolution = resolvePosition(manifest, position);
    _manifest = manifest;
    _notify();
  }

  void goToPage(
    int index, {
    double offset = 0,
    double normalizedX = 0,
    double viewportX = 0,
    double viewportY = 0,
  }) {
    if (_manifest.pages.isEmpty) return;
    if (index < 0 || index >= _manifest.pages.length) {
      throw RangeError.index(index, _manifest.pages);
    }
    _resolution = PositionResolution(
      _manifest.positionAt(
        index,
        offset: offset,
        normalizedX: normalizedX,
        viewportX: viewportX,
        viewportY: viewportY,
      ),
      PositionResolutionKind.exactPage,
    );
    _notify();
  }

  void advance() => _moveSpread(1);
  void back() => _moveSpread(-1);

  /// Scroll frames update the logical offset without rebuilding the whole view;
  /// page changes still notify controls and the image window.
  void updateViewportAnchor(
    int index, {
    required double offset,
    double normalizedX = 0,
    double viewportX = 0,
    double viewportY = 0,
  }) {
    if (_manifest.pages.isEmpty) return;
    final previousKey = position?.pageKey;
    _resolution = PositionResolution(
      _manifest.positionAt(
        index,
        offset: offset,
        normalizedX: normalizedX,
        viewportX: viewportX,
        viewportY: viewportY,
      ),
      PositionResolutionKind.exactPage,
    );
    if (previousKey != position?.pageKey) _notify();
  }

  void _moveSpread(int delta) {
    if (_manifest.pages.isEmpty) return;
    final index = (spreadIndex + delta).clamp(0, spreads.length - 1);
    final key = spreads[index].pages.first.key;
    goToPage(_manifest.pages.indexWhere((page) => page.key == key));
  }

  /// Visible pages first, then the next spread, then the preceding spread.
  /// This bounded list is independent of physical LTR/RTL presentation.
  List<ReaderPage> imageWindow({int adjacentSpreads = 1}) {
    if (adjacentSpreads < 0) throw ArgumentError.value(adjacentSpreads);
    if (_manifest.pages.isEmpty) return const [];
    final groups = spreads;
    final current = spreadIndex;
    final result = [...groups[current].pages];
    for (var distance = 1; distance <= adjacentSpreads; distance++) {
      if (current + distance < groups.length) {
        result.addAll(groups[current + distance].pages);
      }
      if (current - distance >= 0) {
        result.addAll(groups[current - distance].pages);
      }
    }
    return result;
  }

  void _notify() {
    if (_disposed) throw StateError('Reader controller is disposed');
    _changes.add(null);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _changes.close();
  }
}
