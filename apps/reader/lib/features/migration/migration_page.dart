import '../../theme/app_theme.dart';
import '../../widgets/choice_field.dart';
import '../../widgets/app_page_route.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../data/business_state_client.dart';
import '../../data/source_migration_matching.dart';
import '../../data/source_migration_repository.dart';
import '../browse/catalog_controller.dart';
import '../browse/manga_cover_tile.dart';
import 'migration_controller.dart';

class const MigrationPage({
  super.key,
  required final CatalogController catalog,
  required final BusinessStateClient client,
  required final MigrationSeed seed,
}) extends StatefulHookWidget {
  @override
  State<MigrationPage> createState() => _MigrationPageState();
}

class _MigrationPageState extends State<MigrationPage> {
  late final MigrationController controller;
  late TextEditingController _search;
  late FocusNode _confirmFocus;
  int _mappingPage = 0;
  bool _showMarkedOnly = false;

  @override
  void initState() {
    super.initState();
    controller = MigrationController(
      catalog: widget.catalog,
      client: widget.client,
      seed: widget.seed,
      isCurrent: () => mounted && ModalRoute.of(context)?.isActive == true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(controller.refreshSources());
    });
  }

  Future<void> _confirm() async {
    final target = controller.targetMetadata;
    if (!controller.canChange || target == null || controller.tooMany) return;
    _confirmFocus.requestFocus();
    final copyScope = controller.sourceSequence == null
        ? '仅迁移收藏和所选分类，章节标记不复制。'
        : '选中 ${controller.selectedChapters.length} 条章节映射；'
              '已读：${controller.copyRead ? '补充缺失标记' : '不复制'}；'
              '书签：${controller.copyBookmarks ? '补充缺失标记' : '不复制'}。';
    final accepted = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认迁移到目标作品'),
        content: Text(
          '原作品“${widget.seed.metadata.manga.title}”（${widget.seed.metadata.sourceName} · ${widget.seed.metadata.sourceLang}）保留。\n'
          '将目标“${target.manga.title}”（${target.sourceName} · ${target.sourceLang}）加入书架。\n'
          '分类：${controller.copyCategories ? '合并原作品分类' : '不复制'}。$copyScope\n'
          '目标已有状态、封面和阅读位置保留；原页面位置不复制。',
        ),
        actions: [
          CupertinoButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回检查'),
          ),
          CupertinoButton(
            key: const ValueKey('migration-confirm-send'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '确认迁移',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accepted == true) {
      await controller.confirm();
    } else if (controller.canChange) {
      _confirmFocus.requestFocus();
    }
  }

  Future<void> _chooseChapter(
    BuildContext context,
    MigrationChapterMatch match,
    FocusNode focus,
  ) async {
    final sequence = controller.targetSequence;
    if (!controller.canChange || sequence == null) return;
    focus.requestFocus();
    final options = <String?, String>{
      null: '不映射此章节',
      for (final chapter in sequence.entries)
        chapter.key:
            '${chapter.sourceIndex + 1}. ${chapter.name}${controller.targetUsed(chapter.key, match.source.key) ? '（已占用）' : ''}',
    };
    final result = await Navigator.of(context).push<({String? value})>(
      AppPageRoute(
        builder: (_) => ChoicePage<String>(
          label: '目标章节：${match.source.name}',
          value: controller.mappedTargets[match.source.key],
          options: options,
          disabledValues: {
            for (final chapter in sequence.entries)
              if (controller.targetUsed(chapter.key, match.source.key))
                chapter.key,
          },
        ),
      ),
    );
    if (context.mounted &&
        controller.canChange &&
        identical(sequence, controller.targetSequence)) {
      focus.requestFocus();
      if (result != null) {
        controller.mapChapter(match.source.key, result.value);
      }
    }
  }

  Future<void> _showOriginalDetails(MigrationDraft pending) =>
      showCupertinoDialog<void>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('原迁移操作详情'),
          content: Text(
            '操作：${pending.request.mutationId}\n'
            '目标：${pending.request.mangaKey}\n'
            '原作品版本：${pending.request.migrateFrom.expectedSourceRevision}\n'
            '目标版本：${pending.request.expectedRevision}\n'
            '分类版本：${pending.request.migrateFrom.expectedCatalogRevision}',
          ),
          actions: [
            CupertinoButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );

  Widget _mappingRow(MigrationChapterMatch match) {
    final key = match.source.key;
    final targetKey = controller.mappedTargets[key];
    final target = controller.targetSequence?.entries
        .where((entry) => entry.key == targetKey)
        .firstOrNull;
    final state = controller.preview!;
    final read = state.sourceProgress[key]?.completed == true;
    final bookmark = state.sourceBookmarks.contains(key);
    final targetHasState =
        target != null &&
        (state.targetProgress.containsKey(target.key) ||
            state.targetBookmarks.contains(target.key));
    return CupertinoFormSection.insetGrouped(
      key: ValueKey(('migration-map-row', key)),
      footer: Text(
        '原标记：${read ? '已读 ' : ''}${bookmark ? '书签' : ''}${!read && !bookmark ? '无' : ''}\n'
        '目标：${target == null ? '未映射' : '${target.sourceIndex + 1}. ${target.name}'}\n${match.reason}'
        '${targetHasState ? '\n目标已有的已读/未读、位置和书签保留，仅补缺失标记。' : ''}',
      ),
      children: [
        MergeSemantics(
          child: CupertinoFormRow(
            prefix: Expanded(
              flex: 3,
              child: Text(
                '${match.source.sourceIndex + 1}. ${match.source.name}',
              ),
            ),
            child: CupertinoCheckbox(
              key: ValueKey(('migration-map-selected', key)),
              value: controller.selectedChapters.contains(key),
              onChanged:
                  controller.canChange && controller.hasCopyableMarks(key)
                  ? (value) => controller.selectChapter(key, value ?? false)
                  : null,
            ),
          ),
        ),
        HookBuilder(
          builder: (context) {
            final focus = useFocusNode();
            return CupertinoButton(
              key: ValueKey(('migration-map-choose', key)),
              focusNode: focus,
              alignment: AlignmentDirectional.centerStart,
              onPressed: controller.canChange
                  ? () => unawaited(_chooseChapter(context, match, focus))
                  : null,
              child: const Text('选择目标章节'),
            );
          },
        ),
      ],
    );
  }

  Widget _preview() {
    final preview = controller.preview!;
    final mappings = _showMarkedOnly
        ? controller.matches.where((match) {
            final key = match.source.key;
            return preview.sourceProgress[key]?.completed == true ||
                preview.sourceBookmarks.contains(key);
          }).toList()
        : controller.matches;
    final lastPage = mappings.isEmpty ? 0 : (mappings.length - 1) ~/ 50;
    final page = _mappingPage.clamp(0, lastPage);
    final start = page * 50;
    final end = (start + 50).clamp(0, mappings.length);
    final selected = controller.selectedChapters.length;
    final canConfirm = controller.canChange && !controller.tooMany;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoFormSection.insetGrouped(
            header: const Text('迁移预览'),
            footer: const Text('目标将加入书架，原作品保留；目标已有分类、章节状态、书签、封面与阅读位置保留。'),
            children: [
              CupertinoFormRow(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '原作品：${widget.seed.metadata.manga.title} · ${widget.seed.metadata.sourceName} · ${widget.seed.metadata.sourceLang}',
                  ),
                ),
              ),
              CupertinoFormRow(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    '目标：${controller.targetMetadata!.manga.title} · ${controller.targetMetadata!.sourceName} · ${controller.targetMetadata!.sourceLang}',
                    key: const ValueKey('migration-target-preview'),
                  ),
                ),
              ),
            ],
          ),
          CupertinoFormSection.insetGrouped(
            header: const Text('复制内容'),
            footer: Text(
              controller.sourceSequence == null
                  ? '原章节未读取：仅迁移收藏和所选分类；章节未映射，已读、书签与页面位置均不复制。'
                  : '请逐项检查建议。重复、模糊或没有依据的章节不会自动映射；原页面锚点不跨漫画源复制。',
            ),
            children: [
              MergeSemantics(
                child: CupertinoFormRow(
                  prefix: Expanded(flex: 3, child: const Text('合并原作品分类')),
                  helper: Text(
                    preview.source.categoryIds.isEmpty
                        ? '原作品没有分类'
                        : preview.categories.categories
                              .where(
                                (category) => preview.source.categoryIds
                                    .contains(category.id),
                              )
                              .map((category) => category.name)
                              .join('、'),
                    style: TextStyle(
                      color: AppColors.secondaryLabel.resolveFrom(context),
                      fontSize: 13,
                    ),
                  ),
                  child: CupertinoSwitch(
                    value: controller.copyCategories,
                    onChanged: controller.canChange
                        ? (value) =>
                              controller.setCopyOptions(categories: value)
                        : null,
                  ),
                ),
              ),
              if (controller.sourceSequence != null) ...[
                MergeSemantics(
                  child: CupertinoFormRow(
                    prefix: Expanded(flex: 3, child: const Text('补充缺失的目标已读状态')),
                    child: CupertinoSwitch(
                      value: controller.copyRead,
                      onChanged: controller.canChange
                          ? (value) => controller.setCopyOptions(read: value)
                          : null,
                    ),
                  ),
                ),
                MergeSemantics(
                  child: CupertinoFormRow(
                    prefix: Expanded(flex: 3, child: const Text('补充缺失的目标书签')),
                    child: CupertinoSwitch(
                      value: controller.copyBookmarks,
                      onChanged: controller.canChange
                          ? (value) =>
                                controller.setCopyOptions(bookmarks: value)
                          : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (controller.sourceSequence != null) ...[
            CupertinoFormSection.insetGrouped(
              header: const Text('章节映射'),
              footer: const Text('未选或未映射的原标记不复制；一次确认全部提交，不自动分批。'),
              children: [
                CupertinoFormRow(
                  error: controller.tooMany
                      ? Text(
                          '已超出单次上限，请取消部分选中项后再确认；不会自动分批或部分提交。',
                          key: const ValueKey('migration-over-limit'),
                          style: TextStyle(
                            color: AppColors.error.resolveFrom(context),
                          ),
                        )
                      : null,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      '已选 $selected / $migrationChapterLimit 条映射；未选或未映射的原标记 ${controller.unmappedStoredMarks} 项不复制。',
                      key: const ValueKey('migration-selection-count'),
                    ),
                  ),
                ),
                CupertinoButton(
                  alignment: AlignmentDirectional.centerStart,
                  onPressed: controller.canChange
                      ? controller.clearSelection
                      : null,
                  child: const Text('取消全部章节选择'),
                ),
                MergeSemantics(
                  child: CupertinoFormRow(
                    prefix: Expanded(
                      flex: 3,
                      child: const Text('只显示原作已读或有书签的章节'),
                    ),
                    child: CupertinoSwitch(
                      key: const ValueKey('migration-only-marked'),
                      value: _showMarkedOnly,
                      onChanged: (value) => setState(() {
                        _showMarkedOnly = value;
                        _mappingPage = 0;
                      }),
                    ),
                  ),
                ),
                if (_showMarkedOnly && mappings.isEmpty)
                  const CupertinoFormRow(child: Text('原作品没有已读或有书签的章节。')),
                if (mappings.isNotEmpty)
                  CupertinoFormRow(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CupertinoButton(
                          onPressed: page > 0
                              ? () => setState(() => _mappingPage = page - 1)
                              : null,
                          child: const Text('上一页映射'),
                        ),
                        Text('${start + 1}–$end / ${mappings.length}'),
                        CupertinoButton(
                          onPressed: end < mappings.length
                              ? () => setState(() => _mappingPage = page + 1)
                              : null,
                          child: const Text('下一页映射'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            for (final match in mappings.sublist(start, end))
              _mappingRow(match),
          ],
          CupertinoFormSection.insetGrouped(
            footer: const Text('只有在下一步明确确认后，才会向服务端提交迁移。'),
            children: [
              CupertinoButton(
                key: const ValueKey('migration-refresh-preview'),
                alignment: AlignmentDirectional.centerStart,
                onPressed:
                    controller.available &&
                        !controller.busy &&
                        !controller.completed
                    ? () => unawaited(controller.refreshPreview())
                    : null,
                child: const Text('重新读取迁移预览（只读）'),
              ),
              Semantics(
                enabled: canConfirm,
                child: CupertinoButton.filled(
                  key: const ValueKey('migration-confirm'),
                  focusNode: _confirmFocus,
                  foregroundColor: canConfirm
                      ? null
                      : CupertinoColors.tertiaryLabel.resolveFrom(context),
                  onPressed: canConfirm ? () => unawaited(_confirm()) : null,
                  child: const Text('检查并确认迁移'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _readButton({
    required String id,
    required String label,
    required bool enabled,
    required VoidCallback read,
  }) => Semantics(
    container: true,
    enabled: enabled,
    child: CupertinoButton(
      key: ValueKey(id),
      alignment: AlignmentDirectional.centerStart,
      onPressed: enabled ? read : null,
      child: Text(label),
    ),
  );

  Widget _operationFeedback(BuildContext context) =>
      CupertinoFormSection.insetGrouped(
        header: Text(controller.operationLabel),
        children: [
          if (controller.targetReadContext case final target?)
            CupertinoFormRow(child: Text(target)),
          if (controller.busy)
            Semantics(
              container: true,
              liveRegion: true,
              child: CupertinoFormRow(
                prefix: Expanded(child: Text('正在${controller.operationLabel}')),
                child: const CupertinoActivityIndicator(),
              ),
            ),
          if (controller.error case final value?)
            CupertinoFormRow(
              child: Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  value,
                  key: const ValueKey('migration-error'),
                  style: TextStyle(color: AppColors.error.resolveFrom(context)),
                ),
              ),
            ),
          if (controller.targetRetryLabel case final retry?)
            _readButton(
              id: 'migration-retry-target',
              label: retry,
              enabled: controller.canChange,
              read: () => unawaited(controller.retryTargetRead()),
            ),
        ],
      );

  List<Widget> _candidateSlivers(BuildContext context) {
    final candidates = controller.results;
    final empty = controller.busy ? null : controller.emptyResultsMessage;
    if (candidates.isEmpty && empty == null) return const [];
    const spacing = 12.0;
    const minimumCoverWidth = 128.0;
    return [
      if (candidates.isEmpty)
        SliverToBoxAdapter(
          child: CupertinoFormSection.insetGrouped(
            header: const Text('候选作品'),
            children: [CupertinoFormRow(child: Text(empty!))],
          ),
        )
      else ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Semantics(
              header: true,
              child: Text(
                '候选作品',
                style: TextStyle(
                  color: AppColors.secondaryLabel.resolveFrom(context),
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: spacing),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) => SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    ((constraints.crossAxisExtent + spacing) /
                            (minimumCoverWidth + spacing))
                        .floor()
                        .clamp(1, 100),
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childAspectRatio: 2 / 3,
              ),
              itemCount: candidates.length,
              itemBuilder: (context, index) {
                final manga = candidates[index];
                return MangaCoverTile(
                  key: ValueKey(('migration-result', index)),
                  title: manga.title,
                  onPressed: controller.canChange
                      ? () {
                          _mappingPage = 0;
                          unawaited(controller.chooseManga(manga));
                        }
                      : null,
                );
              },
            ),
          ),
        ),
      ],
      if (controller.hasNextPage)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: spacing),
            child: _readButton(
              id: 'migration-search-more',
              label: '加载更多目标结果',
              enabled: controller.canChange,
              read: () => unawaited(controller.loadMore()),
            ),
          ),
        ),
    ];
  }

  Widget _contentWithTargetFeedback({
    required bool pinFeedback,
    required Widget child,
  }) => SafeArea(
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pinFeedback)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: SingleChildScrollView(
                primary: false,
                child: _operationFeedback(context),
              ),
            ),
          Expanded(child: child),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    _search = useTextEditingController(text: widget.seed.metadata.manga.title);
    _confirmFocus = useFocusNode();
    useListenable(controller);
    final available = controller.available;
    final pending = controller.pending;
    final selectedKey = controller.selectedSource?.key;
    final pinFeedback = available && controller.hasTargetReadFeedback;
    final target =
        pending?.request.migrateFrom.targetMetadata ??
        controller.targetMetadata;
    return CupertinoPageScaffold(
      backgroundColor: AppColors.background.resolveFrom(context),
      navigationBar: CupertinoNavigationBar(middle: const Text('迁移到其他漫画源')),
      child: _contentWithTargetFeedback(
        pinFeedback: pinFeedback,
        child: CustomScrollView(
          // The retired view has its own scroll position from the first frame.
          key: ValueKey(available),
          slivers: [
            SliverList.list(
              children: [
                if (!available)
                  CupertinoFormSection.insetGrouped(
                    header: const Text('迁移已停用'),
                    children: [
                      CupertinoFormRow(
                        child: Text(
                          controller.error ?? '身份或服务已改变，请关闭后重新开始迁移。',
                          key: const ValueKey('migration-error'),
                          style: TextStyle(
                            color: AppColors.error.resolveFrom(context),
                          ),
                        ),
                      ),
                      CupertinoButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('返回'),
                      ),
                    ],
                  )
                else ...[
                  if (!pinFeedback &&
                      (controller.busy || controller.error != null))
                    _operationFeedback(context),
                  CupertinoFormSection.insetGrouped(
                    header: const Text('原作品'),
                    footer: Text(
                      controller.completed
                          ? '原作品已保留；迁移结果见下方服务端确认。'
                          : pending != null
                          ? '原操作的复制范围已固定，原作品保留。'
                          : controller.sourceSequence != null
                          ? '已捕获 ${controller.sourceSequence!.entries.length} 章；切换目标源后仍保留本次章节快照。'
                          : controller.categoriesOnly
                          ? '已选择仅迁移收藏和分类，章节标记不复制。'
                          : '先读取原源章节，或明确选择仅迁移收藏和分类。',
                    ),
                    children: [
                      CupertinoFormRow(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            '${widget.seed.metadata.manga.title} · ${widget.seed.metadata.sourceName} · ${widget.seed.metadata.sourceLang}',
                          ),
                        ),
                      ),
                      if (!controller.completed &&
                          pending == null &&
                          controller.selectedSource == null) ...[
                        _readButton(
                          id: 'migration-load-source',
                          label: '读取原漫画源章节',
                          enabled: controller.canChange,
                          read: () =>
                              unawaited(controller.readOriginalChapters()),
                        ),
                        _readButton(
                          id: 'migration-categories-only',
                          label: '仅迁移收藏和分类',
                          enabled: controller.canChange,
                          read: controller.chooseCategoriesOnly,
                        ),
                      ],
                    ],
                  ),
                  if (pending != null)
                    CupertinoFormSection.insetGrouped(
                      header: Text(pending.retryable ? '原迁移尚未确认' : '原迁移已拒绝'),
                      footer: Text(
                        pending.retryable
                            ? '原操作的目标与复制范围已固定，新目标和新映射均不可提交。仅明确重试会重新发送原操作。'
                            : '服务端已明确拒绝原操作。请重新读取当前数据，再检查新的迁移预览。',
                      ),
                      children: [
                        CupertinoFormRow(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              '${target!.manga.title} · ${target.sourceName} · ${target.sourceLang}',
                            ),
                          ),
                        ),
                        CupertinoFormRow(
                          child: Text(
                            '合并分类：${pending.request.migrateFrom.copyCategories ? '是' : '否'}\n'
                            '补充已读 ${pending.request.migrateFrom.chapters.where((item) => item.copyRead).length} 章、'
                            '书签 ${pending.request.migrateFrom.chapters.where((item) => item.copyBookmark).length} 个',
                          ),
                        ),
                        if (pending.retryable)
                          CupertinoButton.filled(
                            key: const ValueKey('migration-retry-original'),
                            onPressed: !controller.busy
                                ? () => unawaited(controller.retry())
                                : null,
                            child: const Text('重试原迁移操作'),
                          )
                        else
                          CupertinoButton(
                            key: const ValueKey('migration-discard-rejected'),
                            alignment: AlignmentDirectional.centerStart,
                            onPressed: !controller.busy
                                ? () => unawaited(controller.discardRejected())
                                : null,
                            child: Text(
                              controller.targetMetadata == null
                                  ? '结束已拒绝的原操作并重新选择'
                                  : '重新读取并结束已拒绝的原操作',
                            ),
                          ),
                        CupertinoButton(
                          key: const ValueKey('migration-original-details'),
                          alignment: AlignmentDirectional.centerStart,
                          onPressed: () =>
                              unawaited(_showOriginalDetails(pending)),
                          child: const Text('查看原操作详情'),
                        ),
                        CupertinoButton(
                          key: const ValueKey('migration-refresh-sources'),
                          alignment: AlignmentDirectional.centerStart,
                          onPressed: !controller.busy
                              ? () => unawaited(controller.refreshSources())
                              : null,
                          child: const Text('重新读取迁移输入（只读）'),
                        ),
                      ],
                    )
                  else if (controller.completed)
                    CupertinoFormSection.insetGrouped(
                      header: const Text('服务端已确认'),
                      footer: Text(controller.notice!),
                      children: [
                        CupertinoFormRow(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              '${target!.manga.title} · ${target.sourceName} · ${target.sourceLang}',
                            ),
                          ),
                        ),
                        CupertinoButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('返回'),
                        ),
                      ],
                    )
                  else ...[
                    CupertinoFormSection.insetGrouped(
                      header: const Text('目标漫画源'),
                      children: [
                        if (controller.inputsReady &&
                            !controller.busy &&
                            controller.sources.isEmpty)
                          const CupertinoFormRow(
                            child: Text('没有其他已安装且启用的可用漫画源。请先在扩展管理中准备目标。'),
                          ),
                        ChoiceField<String>(
                          key: const ValueKey('migration-source'),
                          inline: false,
                          label: '目标漫画源',
                          value:
                              controller.sources.any(
                                (choice) => choice.key == selectedKey,
                              )
                              ? selectedKey
                              : null,
                          options: {
                            for (final choice in controller.sources)
                              choice.key:
                                  '${choice.source.name} · ${choice.source.lang} · ${choice.build.packageName}',
                          },
                          onChanged:
                              controller.canChange && controller.sourceDecided
                              ? (key) {
                                  if (key != null) {
                                    unawaited(
                                      controller.chooseSource(
                                        controller.sources.singleWhere(
                                          (choice) => choice.key == key,
                                        ),
                                      ),
                                    );
                                  }
                                }
                              : null,
                        ),
                        _readButton(
                          id: 'migration-refresh-sources',
                          label: '重新读取可用漫画源（只读）',
                          enabled: !controller.busy,
                          read: () => unawaited(controller.refreshSources()),
                        ),
                      ],
                    ),
                    if (controller.selectedSource != null)
                      CupertinoFormSection.insetGrouped(
                        header: const Text('查找目标作品'),
                        children: [
                          CupertinoFormRow(
                            child: CupertinoTextField(
                              autofillHints: null,
                              key: const ValueKey('migration-search'),
                              controller: _search,
                              enabled: controller.canChange,
                              onSubmitted: (value) =>
                                  unawaited(controller.search(value)),
                              placeholder: '搜索目标作品',
                              decoration: null,
                            ),
                          ),
                          _readButton(
                            id: 'migration-search-submit',
                            label: '搜索',
                            enabled: controller.canChange,
                            read: () =>
                                unawaited(controller.search(_search.text)),
                          ),
                          _readButton(
                            id: 'migration-popular',
                            label: '浏览目标源热门作品',
                            enabled: controller.canChange,
                            read: () => unawaited(controller.browsePopular()),
                          ),
                        ],
                      ),
                  ],
                ],
              ],
            ),
            if (available && pending == null && !controller.completed) ...[
              ..._candidateSlivers(context),
              if (controller.preview != null)
                SliverToBoxAdapter(child: _preview())
              else if (controller.targetMetadata case final metadata?
                  when controller.targetSequence != null)
                SliverToBoxAdapter(
                  child: CupertinoFormSection.insetGrouped(
                    header: const Text('迁移预览尚未取得'),
                    footer: const Text('尚未提交迁移。重新读取当前资料后，才能检查复制范围并确认。'),
                    children: [
                      CupertinoFormRow(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            '${metadata.manga.title} · ${metadata.sourceName} · ${metadata.sourceLang}',
                          ),
                        ),
                      ),
                      CupertinoButton(
                        key: const ValueKey('migration-refresh-preview'),
                        alignment: AlignmentDirectional.centerStart,
                        onPressed: controller.canChange
                            ? () => unawaited(controller.refreshPreview())
                            : null,
                        child: const Text('重新读取迁移预览（只读）'),
                      ),
                    ],
                  ),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
          ],
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
