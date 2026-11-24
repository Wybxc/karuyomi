import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../../widgets/adaptive_detail_layout.dart';
import '../../widgets/app_empty_state.dart';
import '../reader/reader_recovery.dart';
import '../sources/source_error_details.dart';
import 'catalog_controller.dart';
import 'manga_details_page.dart';

typedef LoadMangaDetails = Future<MangaDetails?> Function(
  bool Function() isCurrent,
);

Future<void> openMangaDetails(
  BuildContext context, {
  required String title,
  required CatalogController catalog,
  required LoadMangaDetails load,
  ReaderAuthentication? onAuthenticateReader,
}) => openAdaptiveDetail(
  context,
  (_, close) => MangaDetailsDestination(
    title: title,
    load: load,
    failure: () => (message: catalog.error, diagnostics: catalog.errorDetails),
    onClose: close,
    buildDetails: (details) => MangaDetailsPage(
      controller: catalog,
      manga: details.manga,
      chapters: details.chapters,
      source: details.source,
      onClose: close,
      onAuthenticateReader: onAuthenticateReader,
    ),
  ),
);

class const MangaDetailsDestination({
  super.key,
  required final String title,
  required final LoadMangaDetails load,
  required final Widget Function(MangaDetails details) buildDetails,
  required final ({String? message, String? diagnostics}) Function() failure,
  final VoidCallback? onClose,
}) extends StatefulWidget {
  @override
  State<MangaDetailsDestination> createState() =>
      _MangaDetailsDestinationState();
}

class _MangaDetailsDestinationState extends State<MangaDetailsDestination> {
  ModalRoute<dynamic>? _route;
  bool _closing = false;
  bool _loading = false;
  MangaDetails? _details;
  String? _error;
  String? _diagnostics;

  bool _isActive() => mounted && !_closing && _route?.isActive == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  Future<void> _load() async {
    if (!_isActive() || _loading) return;
    setState(() => _loading = true);
    var focused = true;
    bool canContinue() {
      focused = focused && _isActive() && _route?.isCurrent == true;
      return focused;
    }

    MangaDetails? details;
    ({String? message, String? diagnostics})? failure;
    try {
      if (canContinue()) {
        details = await widget.load(canContinue);
        if (details == null && canContinue()) failure = widget.failure();
      }
    } catch (error) {
      if (canContinue()) {
        failure = (
          message: error is FormatException ? error.message : null,
          diagnostics: error is FormatException
              ? null
              : sourceErrorDetails(error, operation: '加载作品详情'),
        );
      }
    }
    if (!_isActive()) return;
    if (!canContinue()) {
      details = null;
      failure = (message: '加载已停止，请重试。', diagnostics: null);
    }
    setState(() {
      _details = details;
      _error = details == null ? failure?.message ?? '请重试。' : null;
      _diagnostics = failure?.diagnostics;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_details case final details?) return widget.buildDetails(details);
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _closing = true;
      },
      child: CupertinoPageScaffold(
        key: const ValueKey('manga-details-destination'),
        navigationBar: CupertinoNavigationBar(
          middle: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: CupertinoNavigationBarBackButton(
            onPressed: () {
              _closing = true;
              final close = widget.onClose;
              if (close == null) {
                Navigator.of(context).pop();
              } else {
                close();
              }
            },
          ),
        ),
        child: SafeArea(
          child: Center(
            child: _loading || _error == null
                ? Semantics(
                    label: '正在加载作品详情',
                    liveRegion: true,
                    child: const CupertinoActivityIndicator(
                      key: ValueKey('manga-details-loading'),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppEmptyState(
                          leading: const Icon(CupertinoIcons.book),
                          title: '未能打开作品详情',
                          message: _error!,
                          action: (
                            label: '重试',
                            onPressed: () => unawaited(_load()),
                          ),
                          announce: true,
                        ),
                        if (_diagnostics case final details?)
                          SourceErrorDetailsButton(details: details),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
