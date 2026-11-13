import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../widgets/app_appearance.dart';

import '../../widgets/choice_field.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../browse/catalog_controller.dart';
import '../browse/manga_list_tile.dart';
import '../extensions/extension_listing.dart';
import 'cross_source_search_controller.dart';

typedef OpenSourceSearchDetails = Future<void> Function(
  ({MangaEntry manga, List<ChapterEntry> chapters, CatalogSourceRef source})
  details,
);

class const CrossSourceSearchPage({
  super.key,
  required final CatalogSourceSearch service,
  required final OpenSourceSearchDetails onOpen,
}) extends StatefulHookWidget {
  @override
  State<CrossSourceSearchPage> createState() => _CrossSourceSearchPageState();
}

class _CrossSourceSearchPageState extends State<CrossSourceSearchPage> {
  late final CrossSourceSearchController controller;
  late TextEditingController _query;
  late TextEditingController _sourceFilter;
  int _sourcePage = 0;
  bool _allowPop = false;
  bool _leaving = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    controller = CrossSourceSearchController(
      service: widget.service,
      isCurrent: () =>
          mounted && _foreground && ModalRoute.of(context)?.isCurrent == true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(controller.loadTargets());
    });
  }

  void _lifecycleChanged(AppLifecycleState state) {
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
    return CupertinoListSection.insetGrouped(
      children: [
        Text(
          '选择漫画源（已选 ${controller.selected.length} / 32）',
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          key: const ValueKey('cross-search-selection-count'),
        ),
        const Text('仅列出已安装、启用且来源仍有效的漫画源；最多选择32个。'),
        const SizedBox(height: 12),
        ChoiceField<String>(
          key: const ValueKey('cross-search-language'),
          label: '语言',
          value: controller.language,
          options: {
            null: '全部语言',
            for (final language in controller.languages)
              language: language.isEmpty ? '未标注语言' : language,
          },
          onChanged: controller.canChange
              ? (value) {
                  controller.selectLanguage(value);
                  setState(() => _sourcePage = 0);
                }
              : null,
        ),
        const SizedBox(height: 12),
        CupertinoTextField(
          key: const ValueKey('cross-search-source-filter'),
          controller: _sourceFilter,
          onChanged: (_) => setState(() => _sourcePage = 0),
          placeholder: '查找漫画源名称或扩展包',
        ),
        if (controller.loadingTargets)
          const CupertinoActivityIndicator()
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
          MergeSemantics(
            child: CupertinoFormRow(
              prefix: Expanded(flex: 3, child: Text(target.source.name)),
              helper: Text(
                '${sourceLanguage(target.source.lang)} · ${extensionName(target.build.packageName, target.build.sources)}',
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: CupertinoCheckbox(
                key: ValueKey(('cross-search-source', target.key)),
                value: controller.selected.contains(target.key),
                onChanged: controller.canSelect
                    ? (selected) => controller.select(target, selected == true)
                    : null,
              ),
            ),
          ),
        if (visible.isNotEmpty)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('显示 ${start + 1}–$end / ${visible.length}'),
              if (pages > 1) ...[
                CupertinoButton(
                  onPressed: page > 0
                      ? () => setState(() => _sourcePage = page - 1)
                      : null,
                  child: const Text('上一组漫画源'),
                ),
                CupertinoButton(
                  onPressed: page + 1 < pages
                      ? () => setState(() => _sourcePage = page + 1)
                      : null,
                  child: const Text('下一组漫画源'),
                ),
              ],
            ],
          ),
      ],
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
    return CupertinoListSection.insetGrouped(
      children: [
        Text(
          group.target.source.name,
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        Text(
          '${sourceLanguage(group.target.source.lang)}'
          ' · $status · $count 项',
          key: ValueKey(('cross-search-status', group.target.key)),
        ),
        if (group.status == SourceSearchStatus.loading ||
            group.status == SourceSearchStatus.cancelling)
          const CupertinoActivityIndicator(),
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
        if (group.status == SourceSearchStatus.complete && group.mangas.isEmpty)
          const Text('此漫画源没有找到漫画。'),
        Wrap(
          spacing: 8,
          children: [
            if (group.status == SourceSearchStatus.queued ||
                group.status == SourceSearchStatus.loading)
              CupertinoButton(
                key: ValueKey(('cross-search-cancel', group.target.key)),
                onPressed: controller.canChange
                    ? () => unawaited(controller.cancel(group))
                    : null,
                child: const Text('停止此源'),
              ),
            if (group.status == SourceSearchStatus.cancellationFailed)
              CupertinoButton(
                key: ValueKey(('cross-search-cancel-retry', group.target.key)),
                onPressed: controller.canChange
                    ? () => unawaited(controller.cancel(group))
                    : null,
                child: const Text('重试停止'),
              ),
            if (group.hasNextPage ||
                group.status == SourceSearchStatus.error ||
                group.status == SourceSearchStatus.cancelled)
              CupertinoButton(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    _query = useTextEditingController();
    _sourceFilter = useTextEditingController();
    useListenable(controller);
    useOnAppLifecycleStateChange((_, state) => _lifecycleChanged(state));
    return PopScope<void>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: GlassScaffold(
        enableBackgroundSampling: false,
        extendBody: false,
        backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
        appBar: GlassAppBar.pinned(
          backgroundColor: AppAppearance.chromeColor(context),
          onBack: _leave,
          title: const Text('跨源搜索'),
        ),
        body: SafeArea(
          top: false,
          child: Center(
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
                    CupertinoListSection.insetGrouped(
                      children: [
                        Text(
                          controller.cleanupError!,
                          key: const ValueKey('cross-search-cleanup-error'),
                        ),
                        CupertinoButton(
                          key: const ValueKey('cross-search-cleanup-retry'),
                          onPressed: controller.transitioning
                              ? null
                              : () => unawaited(controller.stop()),
                          child: const Text('重试释放搜索资源'),
                        ),
                      ],
                    ),
                  _sourceChoices(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CupertinoButton(
                      key: const ValueKey('cross-search-refresh'),
                      onPressed: controller.canSelect
                          ? () => unawaited(controller.loadTargets())
                          : null,
                      child: const Text('刷新可选漫画源'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    key: const ValueKey('cross-search-query'),
                    controller: _query,
                    enabled: controller.available && !controller.opening,
                    maxLength: crossSourceQueryLimit,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) => unawaited(controller.start(value)),
                    placeholder: '搜索漫画',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      CupertinoButton.filled(
                        key: const ValueKey('cross-search-submit'),
                        onPressed: controller.canChange
                            ? () => unawaited(controller.start(_query.text))
                            : null,
                        child: const Text('搜索所选漫画源'),
                      ),
                      if (controller.hasActive)
                        CupertinoButton(
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
                    const CupertinoActivityIndicator(),
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
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
