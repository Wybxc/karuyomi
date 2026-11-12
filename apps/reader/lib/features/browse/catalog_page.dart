import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../extensions/extension_listing.dart';
import '../extensions/extensions_page.dart';
import '../reader/reader_recovery.dart';
import '../search/cross_source_search_page.dart';
import '../sources/source_directory.dart';
import '../sources/source_preferences.dart';
import 'catalog_controller.dart';
import 'manga_details_page.dart';
import 'source_browse_page.dart';

class CatalogPage extends HookWidget {
  const CatalogPage({
    super.key,
    required this.controller,
    required this.onConnect,
    required this.onAuthenticate,
    this.configurationError,
    this.onAuthenticateReader,
  });
  final CatalogController? controller;
  final VoidCallback onConnect;
  final VoidCallback onAuthenticate;
  final String? configurationError;
  final ReaderAuthentication? onAuthenticateReader;
  Future<void> _open(
    BuildContext context,
    ExtensionListing extension,
    wire.CatalogSource source,
  ) async {
    final build = extension.exact;
    final catalog = controller;
    if (build == null || catalog == null || catalog.busy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SourceBrowsePage(
          catalog: catalog,
          build: build,
          source: source,
          onAuthenticateReader: onAuthenticateReader,
          onAuthenticate: onAuthenticate,
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .9,
        child: SourcePreferencesSheet(
          catalog: catalog,
          target: target,
          repository: repository,
        ),
      ),
    );
  }

  Future<void> _search(BuildContext context) async {
    final catalog = controller;
    final client = catalog?.library?.client;
    if (catalog == null || client == null || catalog.busy) return;
    final CatalogSourceSearch service;
    try {
      service = catalog.createSourceSearch();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError ? error.message.toString() : error.toString(),
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CrossSourceSearchPage(
          service: service,
          onOpen: (details) async {
            bool current() =>
                context.mounted &&
                !catalog.accessPaused &&
                identical(catalog.library?.client, client) &&
                catalog.isCurrentSource(details.source);
            if (!current()) return;
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => current()
                    ? MangaDetailsPage(
                        controller: catalog,
                        manga: details.manga,
                        chapters: details.chapters,
                        source: details.source,
                        onAuthenticateReader: onAuthenticateReader,
                      )
                    : Scaffold(
                        appBar: AppBar(title: const Text('作品已失效')),
                        body: const Center(child: Text('身份或漫画源已改变，请返回后重新搜索。')),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ticker = useSingleTickerProvider();
    final tabs = useMemoized(() => TabController(length: 2, vsync: ticker));
    useEffect(() => tabs.dispose, [tabs]);
    useListenable(controller);
    return _content(context, controller, tabs);
  }

  Widget _content(
    BuildContext context,
    CatalogController? catalog,
    TabController tabs,
  ) {
    final status = catalog?.status ?? ServiceStatus.disconnected;
    final ready =
        catalog?.settings != null &&
        {ServiceStatus.ready, ServiceStatus.failed}.contains(status);
    if (!ready) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.travel_explore_outlined, size: 56),
              const SizedBox(height: 20),
              Text(
                switch (status) {
                  ServiceStatus.loginRequired => '登录后继续浏览',
                  ServiceStatus.denied => '当前账号无法访问',
                  ServiceStatus.connecting => '正在连接服务',
                  ServiceStatus.failed => '服务连接未完成',
                  _ => '连接漫画服务',
                },
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                configurationError ?? catalog?.error ?? '连接服务后，安装扩展并选择漫画源。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (catalog?.busy == true)
                const LinearProgressIndicator()
              else
                Center(
                  child: FilledButton.icon(
                    onPressed:
                        status == ServiceStatus.loginRequired ||
                            status == ServiceStatus.denied
                        ? onAuthenticate
                        : onConnect,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      status == ServiceStatus.loginRequired ||
                              status == ServiceStatus.denied
                          ? '登录'
                          : '连接服务',
                    ),
                  ),
                ),
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
            TabBar(
              controller: tabs,
              tabs: [
                const Tab(text: '漫画源'),
                Tab(
                  key: const ValueKey('extensions-manage'),
                  text: updates == 0 ? '扩展' : '扩展 ($updates)',
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: tabs,
                children: [
                  SourceDirectory(
                    catalog: current,
                    onManage: () => tabs.animateTo(1),
                    onOpen: (extension, source) =>
                        _open(context, extension, source),
                    onSearch: () => unawaited(_search(context)),
                    onPreferences: (target) =>
                        unawaited(_preferences(context, target)),
                  ),
                  ExtensionsPage(
                    key: ValueKey(current.settings),
                    catalog: current,
                    repository: current.settings!,
                    embedded: true,
                    onOpenSource: (extension, source) =>
                        _open(context, extension, source),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
