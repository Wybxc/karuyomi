import 'dart:async';

import 'package:flutter/material.dart';

import '../browse/catalog_controller.dart';
import '../browse/manga_list_tile.dart';
import '../extensions/extension_listing.dart';
import 'cross_source_search_controller.dart';

typedef OpenSourceSearchDetails =
    Future<void> Function(
      ({MangaEntry manga, List<ChapterEntry> chapters, CatalogSourceRef source})
      details,
    );

class CrossSourceSearchPage extends StatefulWidget {
  const CrossSourceSearchPage({
    super.key,
    required this.service,
    required this.onOpen,
  });
  final CatalogSourceSearch service;
  final OpenSourceSearchDetails onOpen;

  @override
  State<CrossSourceSearchPage> createState() => _CrossSourceSearchPageState();
}

class _CrossSourceSearchPageState extends State<CrossSourceSearchPage>
    with WidgetsBindingObserver {
  late final CrossSourceSearchController controller;
  final _query = TextEditingController();
  final _sourceFilter = TextEditingController();
  int _sourcePage = 0;
  bool _allowPop = false;
  bool _leaving = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = CrossSourceSearchController(
      service: widget.service,
      isCurrent: () =>
          mounted && _foreground && ModalRoute.of(context)?.isCurrent == true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(controller.loadTargets());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    final leftForeground = _foreground && !foreground;
    _foreground = foreground;
    if (leftForeground) unawaited(controller.stop());
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final closed = await controller.close();
    _leaving = false;
    if (!mounted || !closed) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  Future<void> _open(SourceSearchGroup group, MangaEntry manga) async {
    final details = await controller.open(group, manga);
    if (!mounted ||
        !_foreground ||
        ModalRoute.of(context)?.isCurrent != true ||
        details == null) {
      return;
    }
    await widget.onOpen(details);
  }

  Widget _sourceChoices() {
    final filter = _sourceFilter.text.trim().toLowerCase();
    final visible = controller.visibleTargets
        .where(
          (target) =>
              filter.isEmpty ||
              target.source.name.toLowerCase().contains(filter) ||
              target.build.packageName.toLowerCase().contains(filter),
        )
        .toList(growable: false);
    final pages = (visible.length / 50).ceil();
    final page = pages == 0 ? 0 : _sourcePage.clamp(0, pages - 1);
    final start = page * 50;
    final end = (start + 50).clamp(0, visible.length);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '选择漫画源（已选 ${controller.selected.length} / 32）',
              style: Theme.of(context).textTheme.titleMedium,
              key: const ValueKey('cross-search-selection-count'),
            ),
            const Text('仅列出已安装、启用且来源仍有效的漫画源；最多选择32个。'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey(('cross-search-language', controller.language)),
              initialValue: controller.language,
              decoration: const InputDecoration(labelText: '语言'),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('全部语言'),
                ),
                for (final language in controller.languages)
                  DropdownMenuItem(
                    value: language,
                    child: Text(language.isEmpty ? '未标注语言' : language),
                  ),
              ],
              onChanged: controller.canChange
                  ? (value) {
                      controller.selectLanguage(value);
                      setState(() => _sourcePage = 0);
                    }
                  : null,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('cross-search-source-filter'),
              controller: _sourceFilter,
              decoration: const InputDecoration(labelText: '查找漫画源名称或扩展包'),
              onChanged: (_) => setState(() => _sourcePage = 0),
            ),
            if (controller.loadingTargets)
              const LinearProgressIndicator()
            else if (controller.targets.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('没有可选漫画源，请先在扩展管理中安装并启用扩展。'),
              )
            else if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('没有符合筛选条件的漫画源。'),
              ),
            for (final target in visible.sublist(start, end))
              CheckboxListTile(
                key: ValueKey(('cross-search-source', target.key)),
                value: controller.selected.contains(target.key),
                title: Text(target.source.name),
                subtitle: Text(
                  '${sourceLanguage(target.source.lang)} · ${extensionName(target.build.packageName, target.build.sources)}',
                ),
                onChanged: controller.canSelect
                    ? (selected) => controller.select(target, selected == true)
                    : null,
              ),
            if (visible.isNotEmpty)
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('显示 ${start + 1}–$end / ${visible.length}'),
                  if (pages > 1) ...[
                    TextButton(
                      onPressed: page > 0
                          ? () => setState(() => _sourcePage = page - 1)
                          : null,
                      child: const Text('上一组漫画源'),
                    ),
                    TextButton(
                      onPressed: page + 1 < pages
                          ? () => setState(() => _sourcePage = page + 1)
                          : null,
                      child: const Text('下一组漫画源'),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _results(SourceSearchGroup group) {
    final status = switch (group.status) {
      SourceSearchStatus.queued => '等待执行',
      SourceSearchStatus.loading => '正在搜索',
      SourceSearchStatus.complete => '已返回',
      SourceSearchStatus.error => '搜索未完成',
      SourceSearchStatus.cancelling => '正在停止',
      SourceSearchStatus.cancelled => '已停止',
      SourceSearchStatus.cancellationFailed => '停止尚未确认',
    };
    final count = group.mangas.length;
    return Card(
      key: ValueKey(('cross-search-group', group.target.key)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              group.target.source.name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${sourceLanguage(group.target.source.lang)}'
              ' · $status · $count 项',
              key: ValueKey(('cross-search-status', group.target.key)),
            ),
            if (group.status == SourceSearchStatus.loading ||
                group.status == SourceSearchStatus.cancelling)
              const LinearProgressIndicator(),
            if (group.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  group.error!,
                  key: ValueKey(('cross-search-error', group.target.key)),
                ),
              ),
            if (group.limitReason != null && group.limitReason != group.error)
              Text(group.limitReason!),
            for (var index = 0; index < group.mangas.length; index++)
              MangaListTile(
                key: ValueKey(('cross-search-result', group.target.key, index)),
                manga: group.mangas[index],
                onTap: controller.canChange && controller.cleanupError == null
                    ? () => unawaited(_open(group, group.mangas[index]))
                    : null,
              ),
            if (group.status == SourceSearchStatus.complete &&
                group.mangas.isEmpty)
              const Text('此漫画源没有找到漫画。'),
            Wrap(
              spacing: 8,
              children: [
                if (group.status == SourceSearchStatus.queued ||
                    group.status == SourceSearchStatus.loading)
                  TextButton(
                    key: ValueKey(('cross-search-cancel', group.target.key)),
                    onPressed: controller.canChange
                        ? () => unawaited(controller.cancel(group))
                        : null,
                    child: const Text('停止此源'),
                  ),
                if (group.status == SourceSearchStatus.cancellationFailed)
                  TextButton(
                    key: ValueKey((
                      'cross-search-cancel-retry',
                      group.target.key,
                    )),
                    onPressed: controller.canChange
                        ? () => unawaited(controller.cancel(group))
                        : null,
                    child: const Text('重试停止'),
                  ),
                if (group.hasNextPage ||
                    group.status == SourceSearchStatus.error ||
                    group.status == SourceSearchStatus.cancelled)
                  TextButton(
                    key: ValueKey(('cross-search-more', group.target.key)),
                    onPressed: controller.canContinue(group)
                        ? () => controller.next(group)
                        : null,
                    child: Text(
                      group.status == SourceSearchStatus.error ||
                              group.status == SourceSearchStatus.cancelled
                          ? '重试此源'
                          : '此源下一页',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _leave),
          title: const Text('跨源搜索'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!controller.available)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      controller.unavailableReason!,
                      key: const ValueKey('cross-search-unavailable'),
                    ),
                  ),
                if (controller.error != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      controller.error!,
                      key: const ValueKey('cross-search-error'),
                    ),
                  ),
                if (controller.cleanupError != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            controller.cleanupError!,
                            key: const ValueKey('cross-search-cleanup-error'),
                          ),
                          TextButton(
                            key: const ValueKey('cross-search-cleanup-retry'),
                            onPressed: controller.transitioning
                                ? null
                                : () => unawaited(controller.stop()),
                            child: const Text('重试释放搜索资源'),
                          ),
                        ],
                      ),
                    ),
                  ),
                _sourceChoices(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('cross-search-refresh'),
                    onPressed: controller.canSelect
                        ? () => unawaited(controller.loadTargets())
                        : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('刷新可选漫画源'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('cross-search-query'),
                  controller: _query,
                  enabled: controller.available && !controller.opening,
                  maxLength: crossSourceQueryLimit,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: '搜索漫画',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) => unawaited(controller.start(value)),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('cross-search-submit'),
                      onPressed: controller.canChange
                          ? () => unawaited(controller.start(_query.text))
                          : null,
                      icon: const Icon(Icons.search),
                      label: const Text('搜索所选漫画源'),
                    ),
                    if (controller.hasActive)
                      OutlinedButton(
                        key: const ValueKey('cross-search-stop'),
                        onPressed: controller.transitioning
                            ? null
                            : () => unawaited(controller.stop()),
                        child: const Text('停止全部'),
                      ),
                  ],
                ),
                if (controller.transitioning || controller.opening) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  Text(controller.opening ? '正在打开作品详情' : '正在释放搜索资源'),
                ],
                if (controller.groups.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '“${controller.query}” · ${controller.groups.where((group) => !group.active).length} / ${controller.groups.length} 源完成 · ${controller.resultCount} 项',
                    key: const ValueKey('cross-search-results-heading'),
                  ),
                  const Text('结果按漫画源分别显示；下一页和重试均需手动操作。'),
                ],
                for (final group in controller.groups) _results(group),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    _query.dispose();
    _sourceFilter.dispose();
    super.dispose();
  }
}
