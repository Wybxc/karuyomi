import '../../theme/app_theme.dart';
import '../../widgets/app_routes.dart';
import '../../widgets/choice_field.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../browse/catalog_controller.dart';
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
  late ScrollController _resultsScroll;
  late ExpansibleController _scope;
  int _sourcePage = 0;
  bool _allowPop = false;
  bool _leaving = false;
  bool? _closeDestination;
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
    if (leftForeground &&
        _closeDestination == null &&
        controller.retirement == null) {
      unawaited(controller.stop());
    }
  }

  Future<void> _leave({bool openExtensions = false}) async {
    if (_leaving ||
        controller.transitioning ||
        controller.retirement?.releasing == true) {
      return;
    }
    _leaving = true;
    final destination = _closeDestination ??= openExtensions;
    final closed = await controller.close();
    _leaving = false;
    if (!mounted) return;
    if (!closed) {
      if (controller.cleanupNotice != null) _showSearchFeedback();
      return;
    }
    setState(() => _allowPop = true);
    Navigator.of(context).pop(controller.retirement == null && destination);
  }

  void _retryCleanup() {
    if (controller.retirement != null) {
      unawaited(_leave());
    } else if (_closeDestination case final openExtensions?) {
      unawaited(_leave(openExtensions: openExtensions));
    } else {
      unawaited(_stopAll());
    }
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

  Future<void> _start(String query) async {
    final previousGroups = controller.groups;
    await controller.start(query);
    if (!mounted) return;
    if (controller.retirement == null &&
        !identical(previousGroups, controller.groups)) {
      FocusScope.of(context).unfocus();
      _scope.collapse();
    } else {
      _showSearchFeedback();
    }
  }

  Future<void> _stopAll() async {
    final stopped = await controller.stop();
    if (mounted && !stopped && controller.cleanupNotice != null) {
      _showSearchFeedback();
    }
  }

  void _showSearchFeedback() {
    if (_resultsScroll.hasClients) _resultsScroll.jumpTo(0);
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
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoFormSection.insetGrouped(
            margin: const EdgeInsets.only(bottom: 8),
            header: Row(
              children: [
                Expanded(
                  child: Text(
                    '选择漫画源（已选 ${controller.selected.length} / 32）',
                    key: const ValueKey('cross-search-selection-count'),
                  ),
                ),
                Flexible(
                  child: CupertinoButton(
                    key: const ValueKey('cross-search-refresh'),
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    onPressed: controller.canSelect
                        ? () => unawaited(controller.loadTargets())
                        : null,
                    child: const Text('刷新可选漫画源', textAlign: TextAlign.end),
                  ),
                ),
              ],
            ),
            footer: const Text('仅列出已安装、启用且来源仍有效的漫画源；最多选择32个。'),
            children: [
              ChoiceField<String>(
                inline: false,
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
              CupertinoTextFormFieldRow(
                autofillHints: null,
                key: const ValueKey('cross-search-source-filter'),
                controller: _sourceFilter,
                onChanged: (_) => setState(() => _sourcePage = 0),
                placeholder: '查找漫画源名称或扩展包',
              ),
            ],
          ),
          CupertinoFormSection.insetGrouped(
            margin: const EdgeInsets.only(bottom: 8),
            footer: visible.isEmpty
                ? null
                : Wrap(
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
            children: [
              if (controller.loadingTargets)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CupertinoActivityIndicator(),
                )
              else if (controller.targets.isEmpty) ...[
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('没有可选漫画源。请先安装并启用扩展。'),
                ),
                if (controller.available)
                  CupertinoButton(
                    onPressed: controller.canSelect
                        ? () => unawaited(_leave(openExtensions: true))
                        : null,
                    child: const Text('打开扩展管理'),
                  ),
              ] else if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('没有符合筛选条件的漫画源。'),
                ),
              for (final target in visible.sublist(start, end))
                MergeSemantics(
                  child: CupertinoListTile(
                    onTap: controller.canSelect
                        ? () => controller.select(
                            target,
                            !controller.selected.contains(target.key),
                          )
                        : null,
                    title: Builder(
                      builder: (context) => DefaultTextStyle(
                        style: DefaultTextStyle.of(context).style,
                        child: Text(target.source.name),
                      ),
                    ),
                    subtitle: Builder(
                      builder: (context) => DefaultTextStyle(
                        style: DefaultTextStyle.of(context).style,
                        child: Text(
                          '${sourceLanguage(target.source.lang)} · ${extensionName(target.build.packageName, target.build.sources)}',
                        ),
                      ),
                    ),
                    trailing: CupertinoCheckbox(
                      key: ValueKey(('cross-search-source', target.key)),
                      value: controller.selected.contains(target.key),
                      onChanged: controller.canSelect
                          ? (selected) =>
                                controller.select(target, selected == true)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultStrip(SourceSearchGroup group) {
    const cardWidth = 96.0;
    const inset = 4.0;
    const coverAspectRatio = 2 / 3;
    const titleLines = 3;
    final titleStyle = CupertinoTheme.of(context).textTheme.actionTextStyle
        .copyWith(
          fontSize: 12,
          height: 1.5,
          color: AppColors.label.resolveFrom(context),
        );
    final caption = TextPainter(
      text: TextSpan(style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    final titleHeight = titleLines * caption.preferredLineHeight;
    caption.dispose();
    const coverHeight = (cardWidth - 2 * inset) / coverAspectRatio;

    return SizedBox(
      height: coverHeight + 3 * inset + titleHeight,
      child: ListView.separated(
        key: ValueKey(('cross-search-results', group.target.key)),
        scrollDirection: Axis.horizontal,
        itemCount: group.mangas.length,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) => SizedBox(
          width: cardWidth,
          child: Semantics(
            enabled: controller.canSearch,
            child: CupertinoButton(
              key: ValueKey(('cross-search-result', group.target.key, index)),
              padding: const EdgeInsets.all(inset),
              alignment: Alignment.topLeft,
              onPressed: controller.canSearch
                  ? () => unawaited(_open(group, group.mangas[index]))
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: coverAspectRatio,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.groupedSurface.resolveFrom(context),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        CupertinoIcons.book,
                        color: AppColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: inset),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: inset),
                      child: Text(
                        group.mangas[index].title,
                        maxLines: titleLines,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    final loading =
        !controller.transitioning &&
        (group.status == SourceSearchStatus.loading ||
            group.status == SourceSearchStatus.cancelling);
    final hasAction =
        group.active ||
        group.hasNextPage ||
        group.status == SourceSearchStatus.error ||
        group.status == SourceSearchStatus.cancelled;
    final canCancel = controller.canCancel(group);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.target.source.name,
                        style: CupertinoTheme.of(context).textTheme.textStyle
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${sourceLanguage(group.target.source.lang)}'
                        ' · $status · $count 项',
                        key: ValueKey((
                          'cross-search-status',
                          group.target.key,
                        )),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (loading) ...[
                  const SizedBox(width: 12),
                  const CupertinoActivityIndicator(),
                ],
              ],
            ),
          ),
          if (group.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_circle_fill,
                    color: AppColors.error.resolveFrom(context),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.error!,
                    key: ValueKey(('cross-search-error', group.target.key)),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.error.resolveFrom(context),
                    ),
                  ),
                  if (group.errorDetails case final details?)
                    MergeSemantics(
                      child: CupertinoButton(
                        key: ValueKey((
                          'cross-search-error-details',
                          group.target.key,
                        )),
                        onPressed: () => showAppDialog<void>(
                          context: context,
                          builder: (context) => CupertinoAlertDialog(
                            title: Text('${group.target.source.name} · 错误详情'),
                            content: Text(details),
                            actions: [
                              CupertinoButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('错误详情'),
                      ),
                    ),
                ],
              ),
            ),
          if (group.limitReason != null && group.limitReason != group.error)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(group.limitReason!),
            ),
          if (group.mangas.isNotEmpty) _resultStrip(group),
          if (group.status == SourceSearchStatus.complete &&
              group.mangas.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '此漫画源没有找到漫画。',
                style: TextStyle(
                  color: AppColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
          if (hasAction)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  if (group.status == SourceSearchStatus.queued ||
                      group.status == SourceSearchStatus.loading)
                    Semantics(
                      enabled: canCancel,
                      child: CupertinoButton(
                        key: ValueKey((
                          'cross-search-cancel',
                          group.target.key,
                        )),
                        onPressed: canCancel
                            ? () => unawaited(controller.cancel(group))
                            : null,
                        child: const Text('停止此源'),
                      ),
                    ),
                  if (group.status == SourceSearchStatus.cancellationFailed &&
                      controller.cleanupError == null)
                    Semantics(
                      enabled: canCancel,
                      child: CupertinoButton(
                        key: ValueKey((
                          'cross-search-cancel-retry',
                          group.target.key,
                        )),
                        onPressed: canCancel
                            ? () => unawaited(controller.cancel(group))
                            : null,
                        child: const Text('重试停止'),
                      ),
                    ),
                  if (group.hasNextPage ||
                      group.status == SourceSearchStatus.error ||
                      group.status == SourceSearchStatus.cancelled)
                    MergeSemantics(
                      child: CupertinoButton(
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
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _searchControls() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Row(
      children: [
        Expanded(
          child: CupertinoTextField(
            autofillHints: null,
            key: const ValueKey('cross-search-query'),
            controller: _query,
            enabled: controller.available && !controller.opening,
            maxLength: crossSourceQueryLimit,
            textInputAction: TextInputAction.search,
            onSubmitted: controller.canStart
                ? (value) => unawaited(_start(value))
                : null,
            placeholder: '搜索漫画',
            placeholderStyle: TextStyle(
              color: AppColors.secondaryLabel.resolveFrom(context),
            ),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                CupertinoIcons.search,
                color: AppColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            clearButtonMode: OverlayVisibilityMode.editing,
            decoration: BoxDecoration(
              color: AppColors.groupedSurface.resolveFrom(context),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          label: '搜索所选漫画源',
          enabled: controller.canStart,
          child: CupertinoButton.filled(
            key: const ValueKey('cross-search-submit'),
            foregroundColor: controller.canStart
                ? null
                : CupertinoColors.tertiaryLabel.resolveFrom(context),
            onPressed: controller.canStart
                ? () => unawaited(_start(_query.text))
                : null,
            child: const ExcludeSemantics(child: Text('搜索')),
          ),
        ),
      ],
    ),
  );

  Widget _searchLayout(Widget results, {Widget? retired}) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 1000),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.openingTarget case final target?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Semantics(
              key: const ValueKey('cross-search-opening'),
              container: true,
              explicitChildNodes: true,
              child: CupertinoFormSection.insetGrouped(
                margin: EdgeInsets.zero,
                header: Semantics(
                  liveRegion: true,
                  child: const Text('正在打开作品详情'),
                ),
                children: [
                  CupertinoListTile(
                    title: Text(target.title, maxLines: 2),
                    subtitle: Text(target.sourceName, maxLines: 2),
                    trailing: const CupertinoActivityIndicator(),
                  ),
                ],
              ),
            ),
          ),
        if (retired == null) _searchControls(),
        Expanded(child: retired ?? results),
      ],
    ),
  );

  Widget _retiredSearch(
    SourceSearchRetirement retirement, {
    required bool releasing,
    required String? releaseError,
  }) => ListView(
    key: const PageStorageKey('cross-search-retired'),
    padding: const EdgeInsets.symmetric(vertical: 16),
    children: [
      CupertinoFormSection.insetGrouped(
        header: const Text('搜索已停用'),
        children: [
          CupertinoFormRow(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                retirement.reason,
                key: const ValueKey('cross-search-unavailable'),
              ),
            ),
          ),
          if (releasing)
            CupertinoFormRow(
              child: Semantics(
                container: true,
                liveRegion: true,
                child: const Row(
                  children: [
                    CupertinoActivityIndicator(),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Text('正在释放搜索资源'), Text('确认释放后可以返回。')],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (releaseError != null) ...[
            CupertinoFormRow(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    releaseError,
                    key: const ValueKey('cross-search-cleanup-error'),
                    style: TextStyle(
                      color: AppColors.error.resolveFrom(context),
                    ),
                  ),
                ),
              ),
            ),
            Semantics(
              container: true,
              child: CupertinoButton(
                key: const ValueKey('cross-search-cleanup-retry'),
                onPressed: _retryCleanup,
                child: const Text('重试释放搜索资源'),
              ),
            ),
          ] else
            const CupertinoFormRow(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('搜索资源已释放，可以返回。'),
              ),
            ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    _query = useTextEditingController();
    _sourceFilter = useTextEditingController();
    _resultsScroll = useScrollController(keepScrollOffset: false);
    _scope = useMemoized(ExpansibleController.new);
    useEffect(() {
      _scope.expand();
      return _scope.dispose;
    }, [_scope]);
    useListenable(controller);
    useOnAppLifecycleStateChange((_, state) => _lifecycleChanged(state));
    final retirement = controller.retirement;
    final releasing = controller.transitioning || retirement?.releasing == true;
    final releaseError = controller.cleanupError ?? retirement?.releaseError;
    final canGoBack =
        !releasing &&
        (retirement != null ? releaseError == null : _closeDestination != true);
    final canStopAll =
        !controller.transitioning &&
        !controller.opening &&
        controller.cleanupError == null &&
        _closeDestination == null;
    return PopScope<bool>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && canGoBack) unawaited(_leave());
      },
      child: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          leading: Semantics(
            enabled: canGoBack,
            child: CupertinoNavigationBarBackButton(
              color: canGoBack
                  ? null
                  : CupertinoColors.tertiaryLabel.resolveFrom(context),
              onPressed: () {
                if (canGoBack) unawaited(_leave());
              },
            ),
          ),
          middle: const Text('跨源搜索'),
          trailing: retirement == null && controller.hasActive
              ? Semantics(
                  enabled: canStopAll,
                  child: CupertinoButton(
                    key: const ValueKey('cross-search-stop'),
                    padding: EdgeInsets.zero,
                    onPressed: canStopAll ? () => unawaited(_stopAll()) : null,
                    child: const Text('停止全部'),
                  ),
                )
              : null,
        ),
        child: SafeArea(
          child: Center(
            child: _searchLayout(
              ListView(
                // Start each submitted search at the top with fresh scroll semantics.
                key: ObjectKey(controller.groups),
                controller: _resultsScroll,
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (controller.retired && _closeDestination == null)
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
                              style: TextStyle(
                                color: AppColors.error.resolveFrom(context),
                              ),
                            ),
                          ),
                        if (controller.cleanupNotice case final notice?)
                          CupertinoFormSection.insetGrouped(
                            margin: EdgeInsets.zero,
                            header: Semantics(
                              liveRegion: true,
                              child: const Text('搜索资源尚未释放'),
                            ),
                            footer: Text(switch (_closeDestination) {
                              true => '资源释放后打开扩展管理。',
                              false => '资源释放后返回。',
                              null => '确认释放后才能继续搜索或离开。',
                            }),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  notice,
                                  key: const ValueKey(
                                    'cross-search-cleanup-error',
                                  ),
                                  style: TextStyle(
                                    color: AppColors.error.resolveFrom(context),
                                  ),
                                ),
                              ),
                              CupertinoButton(
                                key: const ValueKey(
                                  'cross-search-cleanup-retry',
                                ),
                                onPressed: controller.transitioning
                                    ? null
                                    : _retryCleanup,
                                child: const Text('重试释放搜索资源'),
                              ),
                            ],
                          ),
                        Expansible(
                          controller: _scope,
                          animationStyle:
                              MediaQuery.reduceMotionOf(context) ||
                                  MediaQuery.disableAnimationsOf(context)
                              ? AnimationStyle.noAnimation
                              : null,
                          headerBuilder: (context, animation) => Semantics(
                            container: true,
                            expanded: _scope.isExpanded,
                            child: CupertinoButton(
                              key: const ValueKey('cross-search-scope-toggle'),
                              padding: EdgeInsets.zero,
                              onPressed: () => _scope.isExpanded
                                  ? _scope.collapse()
                                  : _scope.expand(),
                              child: CupertinoListTile(
                                title: Builder(
                                  builder: (context) => DefaultTextStyle(
                                    style: DefaultTextStyle.of(context).style,
                                    child: Text(
                                      '搜索范围 · 已选 ${controller.selected.length} 个漫画源',
                                    ),
                                  ),
                                ),
                                trailing: RotationTransition(
                                  turns: animation.drive(
                                    Tween(begin: 0.0, end: 0.25),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.chevron_right,
                                    size: 16,
                                    color: AppColors.accent.resolveFrom(
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          bodyBuilder: (context, animation) => _sourceChoices(),
                        ),
                        if (controller.transitioning &&
                            !controller.opening) ...[
                          const SizedBox(height: 12),
                          const CupertinoActivityIndicator(),
                          const Text('正在释放搜索资源'),
                        ],
                        if (controller.groups.isNotEmpty)
                          Text(
                            '“${controller.query}” · ${controller.groups.where((group) => !group.active).length} / ${controller.groups.length} 源完成 · ${controller.resultCount} 项',
                            key: const ValueKey('cross-search-results-heading'),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.secondaryLabel.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final group in controller.groups) _results(group),
                ],
              ),
              retired: retirement == null
                  ? null
                  : _retiredSearch(
                      retirement,
                      releasing: releasing,
                      releaseError: releaseError,
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
