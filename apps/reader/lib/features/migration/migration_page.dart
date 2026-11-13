import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../widgets/app_appearance.dart';

import '../../widgets/choice_field.dart';
import '../../widgets/app_page_route.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../data/business_state_client.dart';
import '../../data/source_migration_matching.dart';
import '../../data/source_migration_repository.dart';
import '../browse/catalog_controller.dart';
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
    final accepted = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认迁移到目标作品'),
        content: Text(
          '将“${target.manga.title}”（${target.sourceName}）加入书架，保留原作品。\n'
          '按预览复制所选分类和章节标记；目标已有状态、封面和阅读位置保留。原页面位置不会复制。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回检查'),
          ),
          CupertinoDialogAction(
            key: const ValueKey('migration-confirm-send'),
            onPressed: () => Navigator.pop(context, true),
            isDefaultAction: true,
            child: const Text('确认迁移'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) await controller.confirm();
  }

  Future<void> _chooseChapter(MigrationChapterMatch match) async {
    final sequence = controller.targetSequence;
    if (!controller.canChange || sequence == null) return;
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
    if (mounted &&
        controller.canChange &&
        identical(sequence, controller.targetSequence) &&
        result != null) {
      controller.mapChapter(match.source.key, result.value);
    }
  }

  Widget _mappingRow(MigrationChapterMatch match) {
    final key = match.source.key;
    final targetKey = controller.mappedTargets[key];
    final target = controller.targetSequence?.entries
        .where((entry) => entry.key == targetKey)
        .firstOrNull;
    final state = controller.preview!;
    final read = state.sourceProgress[key]?.completed == true;
    final bookmark = state.sourceBookmarks.contains(key);
    return CupertinoListSection.insetGrouped(
      children: [
        MergeSemantics(
          child: CupertinoFormRow(
            prefix: Expanded(
              flex: 3,
              child: Text(
                '${match.source.sourceIndex + 1}. ${match.source.name}',
              ),
            ),
            helper: Text(
              '原标记：${read ? '已读 ' : ''}${bookmark ? '书签' : ''}${!read && !bookmark ? '无' : ''}\n'
              '目标：${target == null ? '未映射' : '${target.sourceIndex + 1}. ${target.name}'}\n${match.reason}',
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
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
        if (target != null &&
            (state.targetProgress.containsKey(target.key) ||
                state.targetBookmarks.contains(target.key)))
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('目标已有的已读/未读、位置和书签保留，仅补缺失标记。'),
          ),
        CupertinoButton(
          key: ValueKey(('migration-map-choose', key)),
          onPressed: controller.canChange
              ? () => unawaited(_chooseChapter(match))
              : null,
          child: const Text('选择目标章节'),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 1,
          child: ColoredBox(
            color: CupertinoColors.separator.resolveFrom(context),
          ),
        ),
        Text(
          '迁移预览',
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        Text(
          '原作品：${widget.seed.metadata.manga.title} · ${widget.seed.metadata.sourceName}',
        ),
        Text(
          '目标：${controller.targetMetadata!.manga.title} · ${controller.targetMetadata!.sourceName}',
          key: const ValueKey('migration-target-preview'),
        ),
        const Text('目标将加入书架，原作品保留；目标已有分类、章节状态、书签、封面与阅读位置保留。'),
        MergeSemantics(
          child: CupertinoFormRow(
            prefix: Expanded(flex: 3, child: const Text('合并原作品分类')),
            helper: Text(
              preview.source.categoryIds.isEmpty
                  ? '原作品没有分类'
                  : preview.categories.categories
                        .where(
                          (category) =>
                              preview.source.categoryIds.contains(category.id),
                        )
                        .map((category) => category.name)
                        .join('、'),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: CupertinoCheckbox(
              value: controller.copyCategories,
              onChanged: controller.canChange
                  ? (value) => controller.setCopyOptions(categories: value)
                  : null,
            ),
          ),
        ),
        if (controller.sourceSequence == null)
          const Text('原章节未读取：仅迁移收藏和所选分类；章节未映射，已读、书签与页面位置均不复制。')
        else ...[
          MergeSemantics(
            child: CupertinoFormRow(
              prefix: Expanded(flex: 3, child: const Text('补充缺失的目标已读状态')),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: CupertinoCheckbox(
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
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: CupertinoCheckbox(
                value: controller.copyBookmarks,
                onChanged: controller.canChange
                    ? (value) => controller.setCopyOptions(bookmarks: value)
                    : null,
              ),
            ),
          ),
          Text(
            '已选 $selected / $migrationChapterLimit 条映射；未选或未映射的原标记 ${controller.unmappedStoredMarks} 项不复制。',
            key: const ValueKey('migration-selection-count'),
          ),
          if (controller.tooMany)
            const Text(
              '已超出单次上限，请取消部分选中项后再确认；不会自动分批或部分提交。',
              key: ValueKey('migration-over-limit'),
            ),
          const Text('请逐项检查建议。重复、模糊或没有依据的章节不会自动映射；原页面锚点不跨漫画源复制。'),
          CupertinoButton(
            onPressed: controller.canChange ? controller.clearSelection : null,
            child: const Text('取消全部章节选择'),
          ),
          MergeSemantics(
            child: CupertinoFormRow(
              prefix: Expanded(flex: 3, child: const Text('只显示原作已读或有书签的章节')),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: CupertinoCheckbox(
                key: const ValueKey('migration-only-marked'),
                value: _showMarkedOnly,
                onChanged: (value) => setState(() {
                  _showMarkedOnly = value ?? false;
                  _mappingPage = 0;
                }),
              ),
            ),
          ),
          if (_showMarkedOnly && mappings.isEmpty)
            const Text('原作品没有已读或有书签的章节。'),
          for (final match in mappings.sublist(start, end)) _mappingRow(match),
          if (mappings.isNotEmpty)
            Row(
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
        ],
        CupertinoButton(
          key: const ValueKey('migration-refresh-preview'),
          onPressed:
              controller.available && !controller.busy && !controller.completed
              ? () => unawaited(controller.refreshPreview())
              : null,
          child: const Text('重新读取迁移预览（只读）'),
        ),
        CupertinoButton.filled(
          key: const ValueKey('migration-confirm'),
          onPressed: controller.canChange && !controller.tooMany
              ? () => unawaited(_confirm())
              : null,
          child: const Text('检查并确认迁移'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _search = useTextEditingController(text: widget.seed.metadata.manga.title);
    useListenable(controller);
    final pending = controller.pending;
    final selectedKey = controller.selectedSource?.key;
    return GlassScaffold(
      enableBackgroundSampling: false,
      extendBody: false,
      backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
      appBar: GlassAppBar.pinned(
        backgroundColor: AppAppearance.chromeColor(context),
        title: const Text('迁移到其他漫画源'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '原作品：${widget.seed.metadata.manga.title} · ${widget.seed.metadata.sourceName}',
            ),
            if (controller.busy) const CupertinoActivityIndicator(),
            if (controller.error case final value?)
              Text(value, key: const ValueKey('migration-error')),
            if (controller.notice case final value?)
              Text(value, key: const ValueKey('migration-notice')),
            if (pending != null) ...[
              const Text('原迁移操作尚未确认。新目标和新映射均不可提交；仅可明确重试原操作。'),
              Text(
                '原操作：${pending.request.mutationId} · 目标 ${pending.request.mangaKey}',
              ),
              Text(
                '原版本：源 ${pending.request.migrateFrom.expectedSourceRevision}，目标 ${pending.request.expectedRevision}，分类 ${pending.request.migrateFrom.expectedCatalogRevision}',
              ),
              if (pending.retryable)
                CupertinoButton.filled(
                  key: const ValueKey('migration-retry-original'),
                  onPressed: controller.available && !controller.busy
                      ? () => unawaited(controller.retry())
                      : null,
                  child: const Text('重试原迁移操作'),
                )
              else
                CupertinoButton(
                  key: const ValueKey('migration-discard-rejected'),
                  onPressed: controller.available && !controller.busy
                      ? () => unawaited(controller.discardRejected())
                      : null,
                  child: const Text('重新读取并结束已拒绝的原操作'),
                ),
            ],
            if (controller.completed)
              CupertinoButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              )
            else ...[
              const SizedBox(height: 16),
              Text(
                '1. 原作品章节',
                style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
              ),
              if (controller.sourceSequence != null)
                Text(
                  '已捕获 ${controller.sourceSequence!.entries.length} 章；切换目标源后仍保留本次章节快照。',
                )
              else
                const Text('先读取原源章节，或明确选择仅迁移收藏和分类。'),
              Wrap(
                spacing: 8,
                children: [
                  CupertinoButton(
                    key: const ValueKey('migration-load-source'),
                    onPressed:
                        controller.canChange &&
                            controller.selectedSource == null
                        ? () => unawaited(controller.readOriginalChapters())
                        : null,
                    child: const Text('读取原漫画源章节'),
                  ),
                  CupertinoButton(
                    key: const ValueKey('migration-categories-only'),
                    onPressed:
                        controller.canChange &&
                            controller.selectedSource == null
                        ? controller.chooseCategoriesOnly
                        : null,
                    child: const Text('仅迁移收藏和分类'),
                  ),
                ],
              ),
              if (controller.categoriesOnly) const Text('已选择仅迁移收藏和分类，章节标记不复制。'),
              const SizedBox(height: 16),
              Text(
                '2. 选择目标漫画源并查找作品',
                style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
              ),
              if (controller.sources.isEmpty)
                const Text('没有其他已安装且启用的可用漫画源。请先在扩展管理中准备目标。'),
              CupertinoButton(
                key: const ValueKey('migration-refresh-sources'),
                onPressed: controller.available && !controller.busy
                    ? () => unawaited(controller.refreshSources())
                    : null,
                child: const Text('重新读取可用漫画源（只读）'),
              ),
              ChoiceField<String>(
                key: const ValueKey('migration-source'),
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
                onChanged: controller.canChange && controller.sourceDecided
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
              CupertinoTextField(
                key: const ValueKey('migration-search'),
                controller: _search,
                enabled:
                    controller.canChange && controller.selectedSource != null,
                onSubmitted: (value) => unawaited(controller.search(value)),
                placeholder: '搜索目标作品',
              ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  CupertinoButton(
                    key: const ValueKey('migration-search-submit'),
                    onPressed:
                        controller.canChange &&
                            controller.selectedSource != null
                        ? () => unawaited(controller.search(_search.text))
                        : null,
                    child: const Text('搜索'),
                  ),
                  CupertinoButton(
                    key: const ValueKey('migration-popular'),
                    onPressed:
                        controller.canChange &&
                            controller.selectedSource != null
                        ? () => unawaited(controller.browsePopular())
                        : null,
                    child: const Text('浏览目标源热门作品'),
                  ),
                ],
              ),
              if (controller.emptyResultsMessage case final message?
                  when !controller.busy)
                Text(message),
              for (var index = 0; index < controller.results.length; index++)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: controller.canChange
                      ? () {
                          _mappingPage = 0;
                          unawaited(
                            controller.chooseManga(controller.results[index]),
                          );
                        }
                      : null,
                  child: CupertinoListTile(
                    key: ValueKey(('migration-result', index)),
                    title: Text(controller.results[index].title),
                    subtitle: Text(controller.results[index].url),
                    trailing: const Icon(CupertinoIcons.chevron_right),
                  ),
                ),
              if (controller.hasNextPage)
                CupertinoButton(
                  key: const ValueKey('migration-search-more'),
                  onPressed: controller.canChange
                      ? () => unawaited(controller.loadMore())
                      : null,
                  child: const Text('加载更多目标结果'),
                ),
              if (controller.preview != null) _preview(),
            ],
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
