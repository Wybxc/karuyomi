import 'dart:async';
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:uuid/uuid.dart';

import '../../theme/app_theme.dart';
import 'catalog_controller.dart';

class const SourceMangaCover({
  super.key,
  required final CatalogController catalog,
  final CatalogSourceRef? source,
  final SourceSearchTarget? target,
  required final Uri? thumbnail,
}) extends StatefulWidget {
  @override
  State<SourceMangaCover> createState() => _SourceMangaCoverState();
}

class _SourceMangaCoverState extends State<SourceMangaCover> {
  Future<Uint8List?>? _bytes;
  String? _request;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadIfVisible();
  }

  @override
  void didUpdateWidget(SourceMangaCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.source;
    final next = widget.source;
    if (!identical(oldWidget.catalog, widget.catalog) ||
        oldWidget.thumbnail != widget.thumbnail ||
        oldWidget.target?.key != widget.target?.key ||
        old?.generation != next?.generation ||
        old?.buildId != next?.buildId ||
        old?.sourceId != next?.sourceId) {
      _cancel(oldWidget);
      _bytes = null;
    }
    _loadIfVisible();
  }

  void _loadIfVisible() {
    final visible =
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.isCurrentOf(context) != false;
    if (!visible) {
      if (_request != null) {
        _cancel(widget);
        _bytes = null;
      }
      return;
    }
    final source = widget.source;
    final target = widget.target;
    final thumbnail = widget.thumbnail;
    if (_bytes != null ||
        (source == null && target == null) ||
        thumbnail == null) {
      return;
    }
    final request = _request = const Uuid().v4();
    _bytes = widget.catalog
        .readSourceCover(
          source: source,
          target: target,
          thumbnail: thumbnail,
          requestId: request,
          stillVisible: () => mounted && _request == request,
        )
        .whenComplete(() {
          if (_request == request) _request = null;
        });
  }

  void _cancel(SourceMangaCover cover) {
    final request = _request;
    _request = null;
    if (request != null) {
      unawaited(cover.catalog.cancelSourceCover(request));
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: AppColors.groupedSurface.resolveFrom(context),
      child: Center(
        child: Icon(
          CupertinoIcons.book,
          color: AppColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
    return FutureBuilder<Uint8List?>(
      key: ObjectKey(_bytes),
      future: _bytes,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) return placeholder;
        return Image.memory(
          data,
          key: const ValueKey('source-cover-image'),
          fit: BoxFit.cover,
          cacheWidth: 512,
          excludeFromSemantics: true,
          frameBuilder: (_, child, frame, _) =>
              frame == null ? placeholder : child,
          errorBuilder: (_, _, _) => placeholder,
        );
      },
    );
  }

  @override
  void dispose() {
    _cancel(widget);
    super.dispose();
  }
}
