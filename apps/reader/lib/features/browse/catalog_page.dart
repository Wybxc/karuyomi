import 'dart:async';

import 'package:flutter/material.dart';
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

class CatalogPage extends StatefulWidget {
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
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  Future<void> _open(
    ExtensionListing extension,
    wire.CatalogSource source,
  ) async {
    final build = extension.exact;
    final catalog = widget.controller;
    if (build == null || catalog == null || catalog.busy) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SourceBrowsePage(
          catalog: catalog,
          build: build,
          source: source,
          onAuthenticateReader: widget.onAuthenticateReader,
          onAuthenticate: widget.onAuthenticate,
        ),
      ),
    );
  }

  Future<void> _preferences(SourcePreferencesTarget target) async {
    final catalog = widget.controller;
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

  Future<void> _search() async {
    final catalog = widget.controller;
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
                mounted &&
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
                        onAuthenticateReader: widget.onAuthenticateReader,
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
    final controller = widget.controller;
    return controller == null
        ? _content(null)
        : AnimatedBuilder(
            animation: controller,
            builder: (context, _) => _content(controller),
          );
  }

  Widget _content(CatalogController? catalog) {
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
                widget.configurationError ??
                    catalog?.error ??
                    '连接服务后，安装扩展并选择漫画源。',
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
                        ? widget.onAuthenticate
                        : widget.onConnect,
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
              controller: _tabs,
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
                controller: _tabs,
                children: [
                  SourceDirectory(
                    catalog: current,
                    onManage: () => _tabs.animateTo(1),
                    onOpen: _open,
                    onSearch: () => unawaited(_search()),
                    onPreferences: (target) => unawaited(_preferences(target)),
                  ),
                  ExtensionsPage(
                    key: ValueKey(current.settings),
                    catalog: current,
                    repository: current.settings!,
                    embedded: true,
                    onOpenSource: _open,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }
}
