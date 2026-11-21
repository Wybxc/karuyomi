import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/cover_repository.dart';
import '../../theme/app_theme.dart';

/// Private cover bytes are read through the verified business identity. No
/// Source thumbnail URL or unauthenticated image URL enters this widget.
class const CustomCover({
  super.key,
  required final CoverRepository repository,
  required final wire.CustomCover? cover,
  final BoxConstraints constraints = const BoxConstraints.tightFor(
    width: 48,
    height: 64,
  ),
  final BoxFit fit = BoxFit.cover,
}) extends StatefulWidget {
  @override
  State<CustomCover> createState() => _CustomCoverState();
}

class _CustomCoverState extends State<CustomCover> {
  late var _bytes = widget.cover == null
      ? null
      : widget.repository.read(widget.cover!);
  int _retry = 0;
  Object get _identity => (
    widget.repository.client,
    widget.cover?.assetId,
    widget.cover?.sha256,
    _retry,
  );
  @override
  void didUpdateWidget(CustomCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository.client, widget.repository.client) ||
        oldWidget.cover != widget.cover) {
      _bytes = widget.cover == null
          ? null
          : widget.repository.read(widget.cover!);
      _retry = 0;
    }
  }

  Widget _placeholder({bool failed = false}) => ColoredBox(
    color: AppColors.groupedSurface.resolveFrom(context),
    child: failed
        ? CupertinoButton(
            onPressed: () => setState(() {
              _retry++;
              _bytes = widget.repository.read(widget.cover!);
            }),
            padding: const EdgeInsets.all(8),
            child: const Icon(CupertinoIcons.refresh, semanticLabel: '重试读取封面'),
          )
        : const Center(heightFactor: 1, child: Icon(CupertinoIcons.book)),
  );
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: widget.constraints,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: FutureBuilder(
        key: ValueKey(_identity),
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _placeholder(failed: true);
          final bytes = snapshot.data;
          if (bytes == null) return _placeholder();
          return Image.memory(
            bytes,
            key: ValueKey(_identity),
            fit: widget.fit,
            cacheHeight: widget.constraints.hasBoundedHeight
                ? (widget.constraints.maxHeight *
                          MediaQuery.devicePixelRatioOf(context))
                      .ceil()
                      .clamp(1, 1024)
                      .toInt()
                : null,
            gaplessPlayback: false,
            excludeFromSemantics: true,
            errorBuilder: (context, error, stack) => _placeholder(failed: true),
          );
        },
      ),
    ),
  );
}
