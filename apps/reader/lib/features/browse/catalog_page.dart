import '../../widgets/adaptive_detail_layout.dart';
import '../../widgets/app_routes.dart';
import '../../widgets/app_empty_state.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../extensions/extension_listing.dart';
import '../extensions/extensions_page.dart';
import '../reader/reader_recovery.dart';
import '../search/cross_source_search_page.dart';
import '../sources/source_directory.dart';
import '../sources/source_error_details.dart';
import '../sources/source_preferences.dart';
import 'catalog_controller.dart';
import 'manga_details_page.dart';
import 'source_browse_page.dart';

class const CatalogPage({
  super.key,
  required final CatalogController? controller,
  required final VoidCallback onConnect,
  required final VoidCallback onAuthenticate,
  final String? configurationError,
  final ReaderAuthentication? onAuthenticateReader,
}) extends HookWidget {
  Future<void> _open(
    BuildContext context,
    ExtensionListing extension,
    wire.CatalogSource source,
  ) async {
    final build = extension.exact;
    final catalog = controller;
    if (build == null || catalog == null || catalog.busy) return;
    await Navigator.of(context).push<void>(
      AppPageRoute(
        builder: (_) => AdaptiveDetailLayout(
          handleSystemBack: false,
          child: SourceBrowsePage(
            catalog: catalog,
            build: build,
            source: source,
            onAuthenticateReader: onAuthenticateReader,
            onAuthenticate: onAuthenticate,
          ),
        ),
      ),
    );
  }

  Future<void> _preferences(
    BuildContext context,
    SourcePreferencesTarget target,
  ) async {
    final catalog = controller;
    final repository = catalog?.sourcePreferences;
    if (catalog == null || repository == null || catalog.busy) return;
    await showAppSheet<void>(
      context: context,
      enableDrag: false,
      scrollableBuilder: (context, _) => SourcePreferencesSheet(
        catalog: catalog,
        target: target,
        repository: repository,
      ),
    );
  }

  Future<void> _search(
    BuildContext context,
    VoidCallback openExtensions,
  ) async {
    final catalog = controller;
    final client = catalog?.library?.client;
    if (catalog == null || client == null || catalog.busy) return;
    bool currentIdentity() =>
        context.mounted &&
        !catalog.accessPaused &&
        identical(catalog.library?.client, client);
    final CatalogSourceSearch service;
    try {
      service = catalog.createSourceSearch();
    } catch (error) {
      showAppDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('无法搜索'),
          content: Text(
            error is StateError ? error.message.toString() : error.toString(),
          ),
          actions: [
            CupertinoButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      return;
    }
    final manageExtensions = await Navigator.of(context).push<bool>(
      AppPageRoute(
        builder: (_) => CrossSourceSearchPage(
          service: service,
          coverCatalog: catalog,
          onOpen: (details) async {
            bool current() =>
                currentIdentity() && catalog.isCurrentSource(details.source);
            if (!current()) return;
            await Navigator.of(context).push<void>(
              AppPageRoute(
                builder: (_) => current()
                    ? MangaDetailsPage(
                        controller: catalog,
                        manga: details.manga,
                        chapters: details.chapters,
                        source: details.source,
                        onAuthenticateReader: onAuthenticateReader,
                      )
                    : CupertinoPageScaffold(
                        navigationBar: CupertinoNavigationBar(
                          middle: const Text('作品已失效'),
                        ),
                        child: SafeArea(
                          child: const Center(
                            child: Text('身份或漫画源已改变，请返回后重新搜索。'),
                          ),
                        ),
                      ),
              ),
            );
          },
        ),
      ),
    );
    if (manageExtensions == true && currentIdentity()) openExtensions();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = useState(0);
    useListenable(controller);
    return _content(context, controller, tabs);
  }

  Widget _content(
    BuildContext context,
    CatalogController? catalog,
    ValueNotifier<int> tabs,
  ) {
    final status = catalog?.status ?? ServiceStatus.disconnected;
    final ready =
        catalog?.settings != null &&
        {ServiceStatus.ready, ServiceStatus.failed}.contains(status);
    if (!ready) {
      final connecting = catalog?.busy == true;
      final needsLogin =
          status == ServiceStatus.loginRequired ||
          status == ServiceStatus.denied;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            shrinkWrap: true,
            children: [
              AppEmptyState(
                leading: connecting
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.globe),
                title: switch (status) {
                  ServiceStatus.loginRequired => '登录后继续浏览',
                  ServiceStatus.denied => '当前账号无法访问',
                  ServiceStatus.connecting => '正在连接服务',
                  ServiceStatus.failed => '服务连接未完成',
                  _ => '连接漫画服务',
                },
                message:
                    configurationError ??
                    catalog?.error ??
                    (catalog == null
                        ? '填写 HTTPS 服务地址后即可浏览漫画源。'
                        : '连接服务后，安装扩展并选择漫画源。'),
                announce: true,
                action: connecting
                    ? null
                    : (
                        label: needsLogin
                            ? '登录'
                            : catalog == null
                            ? '填写服务地址'
                            : '连接服务',
                        onPressed: needsLogin ? onAuthenticate : onConnect,
                      ),
              ),
              if (!connecting && catalog?.errorDetails != null)
                SourceErrorDetailsButton(details: catalog!.errorDetails!),
            ],
          ),
        ),
      );
    }
    final current = catalog!;
    final updates = extensionListings(
      current,
      current.installedExtensions,
    ).where((item) => item.needsUpdate).length;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: tabs.value,
                children: {
                  0: const Text('漫画源'),
                  1: Text(
                    updates == 0 ? '扩展' : '扩展 ($updates)',
                    key: const ValueKey('extensions-manage'),
                  ),
                },
                onValueChanged: (value) {
                  if (value != null) tabs.value = value;
                },
              ),
            ),
            Expanded(
              child: tabs.value == 0
                  ? SourceDirectory(
                      catalog: current,
                      onManage: () => tabs.value = 1,
                      onOpen: (extension, source) =>
                          _open(context, extension, source),
                      onSearch: () =>
                          unawaited(_search(context, () => tabs.value = 1)),
                      onPreferences: (target) =>
                          unawaited(_preferences(context, target)),
                    )
                  : ExtensionsPage(
                      key: ValueKey(current.settings),
                      catalog: current,
                      repository: current.settings!,
                      embedded: true,
                      onOpenSource: (extension, source) =>
                          _open(context, extension, source),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
