import 'package:material_ui/material_ui.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/cover_repository.dart';

/// Private cover bytes are read through the verified business identity. No
/// Source thumbnail URL or unauthenticated image URL enters this widget.
class CustomCover extends StatefulWidget {
  const CustomCover({
    super.key,
    required this.repository,
    required this.cover,
    this.width = 48,
    this.height = 64,
  });
  final CoverRepository repository;
  final wire.CustomCover? cover;
  final double width;
  final double height;
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
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: failed
        ? IconButton(
            tooltip: '重试读取封面',
            onPressed: () => setState(() {
              _retry++;
              _bytes = widget.repository.read(widget.cover!);
            }),
            icon: const Icon(Icons.refresh),
          )
        : const Center(child: Icon(Icons.menu_book_outlined)),
  );
  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    height: widget.height,
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
            fit: BoxFit.cover,
            cacheHeight:
                (widget.height * MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(1, 1024)
                    .toInt(),
            gaplessPlayback: false,
            excludeFromSemantics: true,
            errorBuilder: (context, error, stack) => _placeholder(failed: true),
          );
        },
      ),
    ),
  );
}
