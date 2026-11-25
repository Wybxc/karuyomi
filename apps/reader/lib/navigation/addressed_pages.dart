import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/settings_repository.dart';
import '../features/browse/catalog_controller.dart';
import '../features/browse/manga_details_page.dart';
import '../features/browse/source_browse_page.dart';
import '../features/extensions/extensions_controller.dart';
import '../features/extensions/extensions_page.dart';
import '../features/reader/chapter_reader_route.dart';
import '../features/reader/reader_recovery.dart';
import '../features/reader/source_input_dialog.dart';
import '../features/search/cross_source_search_page.dart';
import '../features/sources/source_error_details.dart';
import '../widgets/adaptive_detail_layout.dart';
import '../widgets/app_empty_state.dart';
import 'app_location.dart';
import 'app_navigation.dart';

class const AddressStatusPage({
  super.key,
  required final String title,
  required final String message,
  required final VoidCallback onBack,
  final bool loading = false,
  final ({String label, VoidCallback onPressed})? action,
  final String? diagnostics,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(
      leading: CupertinoNavigationBarBackButton(onPressed: onBack),
      middle: Text(title),
    ),
    child: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppEmptyState(
                leading: loading
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.link),
                title: message,
                message: '',
                action: action,
                announce: true,
              ),
              if (diagnostics case final value?)
                SourceErrorDetailsButton(details: value),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The requested location stays visible while its account becomes available.
/// After mounting, Source and Reader pages handle Access recovery themselves.
class const AddressedService({
  super.key,
  required final CatalogController? catalog,
  required final String title,
  required final VoidCallback onConnect,
  required final VoidCallback onAuthenticate,
  required final VoidCallback onBack,
  required final Widget Function(CatalogController) builder,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final admitted = useRef<CatalogController?>(null);
    final controller = useListenable(catalog);
    if (controller != null &&
        (identical(admitted.value, controller) ||
            controller.status == ServiceStatus.ready)) {
      admitted.value = controller;
      return builder(controller);
    }
    admitted.value = null;
    final status = controller?.status;
    final login = status == ServiceStatus.loginRequired;
    final waiting =
        status == ServiceStatus.connecting ||
        status == ServiceStatus.disconnected;
    return AddressStatusPage(
      title: title,
      onBack: onBack,
      loading: waiting,
      message: switch (status) {
        ServiceStatus.loginRequired => '登录后打开此链接',
        ServiceStatus.denied => '当前账号无法访问',
        ServiceStatus.failed => controller?.error ?? '服务连接未完成',
        ServiceStatus.connecting || ServiceStatus.disconnected => '正在连接服务',
        _ => '连接服务后打开此链接',
      },
      action: waiting
          ? null
          : (
              label: login ? '登录' : '连接服务',
              onPressed: login ? onAuthenticate : onConnect,
            ),
    );
  }
}

class const AddressedSourcePage({
  super.key,
  required final CatalogController catalog,
  required final SourceLocation target,
  required final VoidCallback onBack,
  required final VoidCallback onCloseDetail,
  required final VoidCallback onAuthenticate,
  required final ReaderAuthentication onAuthenticateReader,
  final CatalogBuild? selectedBuild,
  final String? catalogKey,
  final AdaptiveDetailSelection? detail,
  final bool loadListing = true,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final retry = useState(0);
    final start = useRef(loadListing || selectedBuild != null);
    start.value |= loadListing;
    final future = useMemoized(
      () => selectedBuild != null || !start.value
          ? null
          : catalog
                .resolveInstalledBuild(
                  target.packageName,
                  shouldContinue: () =>
                      context.mounted &&
                      ModalRoute.of(context)?.isActive == true,
                )
                .then((build) {
                  if (catalogKey != null &&
                      catalogLocationKey(build.catalog) != catalogKey) {
                    throw const FormatException('当前账号选择的扩展来源与链接不匹配。');
                  }
                  return build;
                }),
      [catalog, target, catalogKey, selectedBuild, start.value, retry.value],
    );
    final resolved = useFuture(future);
    final build = selectedBuild ?? resolved.data;
    final source = build?.sources
        .where((source) => source.id == target.sourceId)
        .firstOrNull;
    if (build != null && source != null) {
      return AdaptiveDetailLayout(
        handleSystemBack: false,
        owner: catalog.library,
        detail: detail,
        onCloseDetail: onCloseDetail,
        child: SourceBrowsePage(
          key: ValueKey((catalog, build.catalogUrl, build.id, source.id)),
          catalog: catalog,
          build: build,
          source: source,
          onAuthenticate: onAuthenticate,
          onAuthenticateReader: onAuthenticateReader,
        ),
      );
    }
    final failure = resolved.error;
    final waiting = failure == null && build == null;
    return AddressStatusPage(
      title: '漫画源',
      onBack: onBack,
      loading: waiting,
      message: failure is FormatException
          ? failure.message
          : build != null
          ? '当前扩展中找不到这个漫画源。'
          : waiting
          ? '正在打开漫画源'
          : '未能打开漫画源',
      action: waiting ? null : (label: '重试', onPressed: () => retry.value++),
      diagnostics: failure == null
          ? null
          : sourceErrorDetails(failure, operation: '打开漫画源链接'),
    );
  }
}

class const AddressedSearchPage({
  super.key,
  required final CatalogController catalog,
  required final VoidCallback onBack,
  required final VoidCallback onCloseDetail,
  required final VoidCallback onManageExtensions,
  required final ReaderAuthentication onAuthenticateReader,
  final AdaptiveDetailSelection? detail,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final result = useMemoized(() {
      try {
        return (service: catalog.createSourceSearch(), error: null);
      } on StateError catch (error) {
        return (service: null, error: error.message.toString());
      }
    }, [catalog, catalog.library?.client]);
    final service = result.service;
    if (service == null) {
      return AddressStatusPage(
        title: '跨源搜索',
        message: result.error!,
        onBack: onBack,
      );
    }
    return AdaptiveDetailLayout(
      owner: service,
      handleSystemBack: false,
      detail: detail,
      onCloseDetail: onCloseDetail,
      child: CrossSourceSearchPage(
        key: ObjectKey(service),
        service: service,
        coverCatalog: catalog,
        onManageExtensions: onManageExtensions,
        buildDetails: (details) => MangaDetailsPage(
          controller: catalog,
          manga: details.manga,
          chapters: details.chapters,
          source: details.source,
          onAuthenticateReader: onAuthenticateReader,
        ),
      ),
    );
  }
}

class const AddressedExtensionPage({
  super.key,
  required final CatalogController catalog,
  required final SettingsRepository repository,
  required final AppLocation location,
  required final VoidCallback onBack,
}) extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = useMemoized(
      () => ExtensionsController(
        catalog: catalog,
        repository: repository,
        container: ProviderScope.containerOf(context, listen: false),
        isCurrent: () =>
            context.mounted && ModalRoute.of(context)?.isActive == true,
      ),
      [catalog, repository],
    );
    useListenable(manager);
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && manager.available) {
          unawaited(manager.refresh(reportCatalogCheck: false));
        }
      });
      return manager.dispose;
    }, [manager]);
    if (location.panel == AppPanel.storage) {
      return ExtensionStoragePage(controller: manager);
    }
    if (location.panel == AppPanel.repositories) {
      return ExtensionRepositoriesPage(controller: manager);
    }
    final target = location.extension!;
    final build = catalog.builds
        .where(
          (build) =>
              build.packageName == target.packageName &&
              catalogLocationKey(build.catalog) == target.catalogKey,
        )
        .firstOrNull;
    final installed = catalog.installedExtension(target.packageName);
    final installedFromTarget =
        installed != null &&
        catalogLocationKey(
              wire.CatalogReference(
                catalogUrl: installed.catalogUrl,
                repoId: installed.repoId,
              ),
            ) ==
            target.catalogKey;
    if (build == null && !installedFromTarget) {
      return AddressStatusPage(
        title: '扩展详情',
        message: '当前目录中找不到这个扩展',
        onBack: onBack,
      );
    }
    return ExtensionDetailsPage(
      controller: manager,
      packageName: target.packageName,
      candidate: build,
      onOpenSource: (item, source) async {
        if (item.exact case final selected?) {
          AppNavigation.maybeOf(context)?.openSource(selected, source);
        }
      },
    );
  }
}

class const AddressedReaderPage({
  super.key,
  required final CatalogController catalog,
  required final AppLocation location,
  required final VoidCallback onBack,
  required final VoidCallback onAuthenticate,
  required final ReaderAuthentication onAuthenticateReader,
  required final ValueChanged<String> onChapterChanged,
}) extends StatefulWidget {
  @override
  State<AddressedReaderPage> createState() => _AddressedReaderPageState();
}

class _AddressedReaderPageState extends State<AddressedReaderPage> {
  RecoveredReader? _reader;
  String? _failure;
  String? _diagnostics;
  bool _loading = false;

  bool get _active => mounted && ModalRoute.of(context)?.isActive == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    if (!_active || _loading) return;
    setState(() {
      _loading = true;
      _failure = null;
      _diagnostics = null;
    });
    final catalog = widget.catalog;
    final location = widget.location;
    final subject = catalog.subject;
    bool current() =>
        _active &&
        identical(catalog, widget.catalog) &&
        catalog.subject == subject;
    try {
      final result = await catalog.openMangaLocation(
        location.mangaKey!,
        packageName: location.source?.packageName,
        sourceId: location.source?.sourceId,
        shouldContinue: current,
      );
      if (!current()) return;
      if (result == null) {
        throw StateError(catalog.error ?? '未能打开作品');
      }
      final reader = await openReaderChapter(
        catalog,
        result.details,
        packageName: result.packageName,
        chapterKey: location.chapterKey!,
        isCurrent: current,
        onInput: (prompt, ended) => current()
            ? showSourceInputDialog(
                context,
                sourceName: result.details.source.sourceName,
                prompt: prompt,
                operationEnded: ended,
              )
            : Future<String?>.value(),
      );
      if (!current()) {
        if (reader != null) await catalog.closeChapter(reader.opened);
        return;
      }
      if (reader == null) throw StateError(catalog.error ?? '未能打开章节');
      setState(() => _reader = reader);
    } catch (error) {
      if (current()) {
        setState(() {
          _failure = switch (error) {
            FormatException(:final message) => message,
            StateError(:final message) => message.toString(),
            _ => '未能打开章节',
          };
          _diagnostics =
              catalog.errorDetails ??
              sourceErrorDetails(error, operation: '打开章节链接');
        });
      }
    } finally {
      if (_active) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_reader case final reader?) {
      return ChapterReaderRoute(
        catalog: widget.catalog,
        manga: reader.manga,
        source: reader.source,
        sequence: reader.sequence,
        initialChapter: reader.chapter,
        initialOpened: reader.opened,
        onAuthenticate: widget.onAuthenticateReader,
        onChapterChanged: widget.onChapterChanged,
      );
    }
    final login = widget.catalog.status == ServiceStatus.loginRequired;
    return AddressStatusPage(
      title: '阅读',
      onBack: widget.onBack,
      loading: _failure == null,
      message: _failure ?? '正在打开章节',
      diagnostics: _diagnostics,
      action: _failure == null
          ? null
          : (
              label: login ? '登录' : '重试',
              onPressed: login
                  ? widget.onAuthenticate
                  : () => unawaited(_load()),
            ),
    );
  }

  @override
  void dispose() {
    if (_reader case final reader?) {
      unawaited(widget.catalog.closeChapter(reader.opened));
    }
    super.dispose();
  }
}
