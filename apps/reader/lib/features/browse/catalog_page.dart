import 'package:flutter/material.dart';

import 'catalog_controller.dart';
import '../reader/reader_screen.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({
    super.key,
    required this.controller,
    required this.onConnect,
    required this.onAuthenticate,
    this.configurationError,
  });
  final CatalogController? controller;
  final VoidCallback onConnect;
  final VoidCallback onAuthenticate;
  final String? configurationError;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _search = TextEditingController();

  Future<void> _details(MangaEntry entry) async {
    final controller = widget.controller!;
    final details = await controller.details(entry);
    if (!mounted || details == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MangaDetailsPage(
          controller: controller,
          manga: details.manga,
          chapters: details.chapters,
          source: details.source,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (controller == null) return _content(context, null);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _content(context, controller),
    );
  }

  Widget _content(BuildContext context, CatalogController? controller) {
    final status = controller?.status ?? ServiceStatus.disconnected;
    final busy = controller?.busy ?? false;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (busy) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(controller!.activity ?? '正在加载'),
              const SizedBox(height: 16),
            ],
            if (controller?.error != null) ...[
              _Notice(text: controller!.error!, icon: Icons.error_outline),
              const SizedBox(height: 16),
            ],
            if (status != ServiceStatus.ready) ...[
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
                widget.configurationError ?? '连接你的服务，加载已安装的漫画源。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Center(
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : status == ServiceStatus.loginRequired ||
                            status == ServiceStatus.denied
                      ? widget.onAuthenticate
                      : widget.onConnect,
                  icon: Icon(
                    status == ServiceStatus.loginRequired ||
                            status == ServiceStatus.denied
                        ? Icons.login
                        : Icons.refresh,
                  ),
                  label: Text(
                    status == ServiceStatus.loginRequired ||
                            status == ServiceStatus.denied
                        ? '登录'
                        : '连接服务',
                  ),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      controller!.email ?? '已连接',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : widget.onConnect,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新连接'),
                  ),
                ],
              ),
              if (controller.builds.isEmpty)
                const _Notice(
                  text: '尚未安装漫画源。安装后重新连接即可浏览。',
                  icon: Icons.extension_outlined,
                ),
              if (controller.builds.isNotEmpty) ...[
                Text('漫画源', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final build in controller.builds)
                      ChoiceChip(
                        label: Text('${build.packageName} · ${build.version}'),
                        selected: controller.activeBuild?.id == build.id,
                        onSelected: busy
                            ? null
                            : (_) => controller.openBuild(build),
                      ),
                  ],
                ),
              ],
              if (controller.session != null) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final source in controller.session!.sources)
                      FilterChip(
                        label: Text('${source.name} · ${source.lang}'),
                        selected: controller.activeSource?.id == source.id,
                        onSelected: busy
                            ? null
                            : (_) => controller.selectSource(source),
                      ),
                  ],
                ),
              ],
              if (controller.activeSource != null) ...[
                const SizedBox(height: 24),
                TextField(
                  controller: _search,
                  enabled: !busy,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (query) => controller.loadMangas(search: query),
                  decoration: InputDecoration(
                    labelText: '搜索漫画',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: '搜索',
                      onPressed: busy
                          ? null
                          : () => controller.loadMangas(search: _search.text),
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in [('popular', '热门'), ('latest', '最新')])
                      if (item.$1 != 'latest' ||
                          controller.activeSource?.hasSupportsLatest() !=
                              true ||
                          controller.activeSource?.supportsLatest != false)
                        ChoiceChip(
                          label: Text(item.$2),
                          selected: controller.listing == item.$1,
                          onSelected: busy
                              ? null
                              : (_) {
                                  _search.clear();
                                  controller.loadMangas(
                                    search: '',
                                    operation: item.$1,
                                  );
                                },
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!busy && controller.mangas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('没有找到漫画', textAlign: TextAlign.center),
                  ),
                for (final manga in controller.mangas)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(manga.title),
                      subtitle: manga.author == null
                          ? null
                          : Text(manga.author!),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy ? null : () => _details(manga),
                    ),
                  ),
                if (controller.hasNextPage)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => controller.loadMangas(more: true),
                      child: const Text('加载更多'),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

class MangaDetailsPage extends StatelessWidget {
  const MangaDetailsPage({
    super.key,
    required this.controller,
    required this.manga,
    required this.chapters,
    required this.source,
  });
  final CatalogController controller;
  final MangaEntry manga;
  final List<ChapterEntry> chapters;
  final CatalogSourceRef source;

  Future<void> _openChapter(BuildContext context, ChapterEntry chapter) async {
    final route = ModalRoute.of(context);
    final opened = await controller.openChapter(
      manga,
      chapter,
      reference: source,
    );
    if (opened == null) return;
    if (!context.mounted ||
        route?.isCurrent != true ||
        route?.isActive != true) {
      await controller.closeChapter(opened);
      return;
    }
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            manifest: opened.manifest,
            provider: opened.provider,
            generation: opened.generation,
            title: opened.title,
            onClosed: () => controller.closeChapter(opened),
          ),
        ),
      );
    } catch (_) {
      await controller.closeChapter(opened);
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(manga.title)),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => !controller.isCurrentSource(source)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(controller.error ?? '漫画源会话已变化，请返回浏览重新打开详情。'),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      manga.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    if (manga.author?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 12),
                      Text('作者：${manga.author}'),
                    ],
                    if (manga.artist?.isNotEmpty ?? false)
                      Text('画师：${manga.artist}'),
                    if (manga.genres.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final genre in manga.genres)
                            Chip(label: Text(genre)),
                        ],
                      ),
                    ],
                    if (manga.description?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 16),
                      SelectableText(manga.description!),
                    ],
                    const SizedBox(height: 32),
                    Text(
                      '章节（${chapters.length}）',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (controller.busy) const LinearProgressIndicator(),
                    if (controller.error != null)
                      _Notice(
                        text: controller.error!,
                        icon: Icons.error_outline,
                      ),
                    if (chapters.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('这个漫画源没有返回章节'),
                      ),
                    for (final chapter in chapters)
                      ListTile(
                        enabled: !controller.busy,
                        leading: const Icon(Icons.article_outlined),
                        title: Text(chapter.name),
                        onTap: () => _openChapter(context, chapter),
                      ),
                  ],
                ),
              ),
            ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}
