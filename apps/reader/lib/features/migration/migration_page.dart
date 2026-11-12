import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../data/business_state_client.dart';
import '../../data/source_migration_matching.dart';
import '../../data/source_migration_repository.dart';
import '../browse/catalog_controller.dart';
import '../reader/chapter_sequence.dart';
import 'migration_controller.dart';

class MigrationPage extends StatefulHookWidget {
  const MigrationPage({
    super.key,
    required this.catalog,
    required this.client,
    required this.seed,
  });
  final CatalogController catalog;
  final BusinessStateClient client;
  final MigrationSeed seed;
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
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认迁移到目标作品'),
        content: Text(
          '将“${target.manga.title}”（${target.sourceName}）加入书架，保留原作品。\n'
          '按预览复制所选分类和章节标记；目标已有状态、封面和阅读位置保留。原页面位置不会复制。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回检查'),
          ),
          FilledButton(
            key: const ValueKey('migration-confirm-send'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认迁移'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) await controller.confirm();
  }

  Future<void> _chooseChapter(MigrationChapterMatch match) async {
    if (!controller.canChange) return;
    final targets =
        controller.targetSequence?.entries ?? const <SequenceChapter>[];
    var query = '';
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final visible = targets
              .where(
                (chapter) =>
                    query.isEmpty || chapter.name.toLowerCase().contains(query),
              )
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .8,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('原章节：${match.source.name}'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(labelText: '搜索目标章节'),
                      onChanged: (value) => setSheetState(
                        () => query = value.trim().toLowerCase(),
                      ),
                    ),
                  ),
                  ListTile(
                    title: const Text('不映射此章节'),
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final chapter = visible[index];
                        final used = controller.targetUsed(
                          chapter.key,
                          match.source.key,
                        );
                        return ListTile(
                          key: ValueKey((
                            'migration-target-chapter',
                            chapter.key,
                          )),
                          title: Text(
                            '${chapter.sourceIndex + 1}. ${chapter.name}',
                          ),
                          subtitle: used ? const Text('已由另一原章节占用') : null,
                          enabled: !used,
                          onTap: used
                              ? null
                              : () => Navigator.pop(context, chapter.key),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (chosen != null && mounted) {
      controller.mapChapter(match.source.key, chosen.isEmpty ? null : chosen);
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
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            key: ValueKey(('migration-map-selected', key)),
            value: controller.selectedChapters.contains(key),
            onChanged: controller.canChange && controller.hasCopyableMarks(key)
                ? (value) => controller.selectChapter(key, value ?? false)
                : null,
            title: Text(
              '${match.source.sourceIndex + 1}. ${match.source.name}',
            ),
            subtitle: Text(
              '原标记：${read ? '已读 ' : ''}${bookmark ? '书签' : ''}${!read && !bookmark ? '无' : ''}\n'
              '目标：${target == null ? '未映射' : '${target.sourceIndex + 1}. ${target.name}'}\n${match.reason}',
            ),
          ),
          if (target != null &&
              (state.targetProgress.containsKey(target.key) ||
                  state.targetBookmarks.contains(target.key)))
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('目标已有的已读/未读、位置和书签保留，仅补缺失标记。'),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: ValueKey(('migration-map-choose', key)),
              onPressed: controller.canChange
                  ? () => unawaited(_chooseChapter(match))
                  : null,
              child: const Text('手动选择目标章节'),
            ),
          ),
        ],
      ),
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
        const Divider(),
        Text('迁移预览', style: Theme.of(context).textTheme.titleLarge),
        Text(
          '原作品：${widget.seed.metadata.manga.title} · ${widget.seed.metadata.sourceName}',
        ),
        Text(
          '目标：${controller.targetMetadata!.manga.title} · ${controller.targetMetadata!.sourceName}',
          key: const ValueKey('migration-target-preview'),
        ),
        const Text('目标将加入书架，原作品保留；目标已有分类、章节状态、书签、封面与阅读位置保留。'),
        CheckboxListTile(
          title: const Text('合并原作品分类'),
          value: controller.copyCategories,
          subtitle: Text(
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
          onChanged: controller.canChange
              ? (value) => controller.setCopyOptions(categories: value)
              : null,
        ),
        if (controller.sourceSequence == null)
          const Text('原章节未读取：仅迁移收藏和所选分类；章节未映射，已读、书签与页面位置均不复制。')
        else ...[
          CheckboxListTile(
            title: const Text('补充缺失的目标已读状态'),
            value: controller.copyRead,
            onChanged: controller.canChange
                ? (value) => controller.setCopyOptions(read: value)
                : null,
          ),
          CheckboxListTile(
            title: const Text('补充缺失的目标书签'),
            value: controller.copyBookmarks,
            onChanged: controller.canChange
                ? (value) => controller.setCopyOptions(bookmarks: value)
                : null,
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
          TextButton(
            onPressed: controller.canChange ? controller.clearSelection : null,
            child: const Text('取消全部章节选择'),
          ),
          CheckboxListTile(
            key: const ValueKey('migration-only-marked'),
            title: const Text('只显示原作已读或有书签的章节'),
            value: _showMarkedOnly,
            onChanged: (value) => setState(() {
              _showMarkedOnly = value ?? false;
              _mappingPage = 0;
            }),
          ),
          if (_showMarkedOnly && mappings.isEmpty)
            const Text('原作品没有已读或有书签的章节。'),
          for (final match in mappings.sublist(start, end)) _mappingRow(match),
          if (mappings.isNotEmpty)
            Row(
              children: [
                TextButton(
                  onPressed: page > 0
                      ? () => setState(() => _mappingPage = page - 1)
                      : null,
                  child: const Text('上一页映射'),
                ),
                Text('${start + 1}–$end / ${mappings.length}'),
                TextButton(
                  onPressed: end < mappings.length
                      ? () => setState(() => _mappingPage = page + 1)
                      : null,
                  child: const Text('下一页映射'),
                ),
              ],
            ),
        ],
        TextButton(
          key: const ValueKey('migration-refresh-preview'),
          onPressed:
              controller.available && !controller.busy && !controller.completed
              ? () => unawaited(controller.refreshPreview())
              : null,
          child: const Text('重新读取迁移预览（只读）'),
        ),
        FilledButton(
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
    return Scaffold(
      appBar: AppBar(title: const Text('迁移到其他漫画源')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '原作品：${widget.seed.metadata.manga.title} · ${widget.seed.metadata.sourceName}',
          ),
          if (controller.busy) const LinearProgressIndicator(),
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
              FilledButton(
                key: const ValueKey('migration-retry-original'),
                onPressed: controller.available && !controller.busy
                    ? () => unawaited(controller.retry())
                    : null,
                child: const Text('重试原迁移操作'),
              )
            else
              TextButton(
                key: const ValueKey('migration-discard-rejected'),
                onPressed: controller.available && !controller.busy
                    ? () => unawaited(controller.discardRejected())
                    : null,
                child: const Text('重新读取并结束已拒绝的原操作'),
              ),
          ],
          if (controller.completed)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            )
          else ...[
            const SizedBox(height: 16),
            Text('1. 原作品章节', style: Theme.of(context).textTheme.titleMedium),
            if (controller.sourceSequence != null)
              Text(
                '已捕获 ${controller.sourceSequence!.entries.length} 章；切换目标源后仍保留本次章节快照。',
              )
            else
              const Text('先读取原源章节，或明确选择仅迁移收藏和分类。'),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('migration-load-source'),
                  onPressed:
                      controller.canChange && controller.selectedSource == null
                      ? () => unawaited(controller.readOriginalChapters())
                      : null,
                  child: const Text('读取原漫画源章节'),
                ),
                TextButton(
                  key: const ValueKey('migration-categories-only'),
                  onPressed:
                      controller.canChange && controller.selectedSource == null
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
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (controller.sources.isEmpty)
              const Text('没有其他已安装且启用的可用漫画源。请先在扩展管理中准备目标。'),
            TextButton(
              key: const ValueKey('migration-refresh-sources'),
              onPressed: controller.available && !controller.busy
                  ? () => unawaited(controller.refreshSources())
                  : null,
              child: const Text('重新读取可用漫画源（只读）'),
            ),
            DropdownButton<String>(
              key: const ValueKey('migration-source'),
              isExpanded: true,
              hint: const Text('选择已安装的目标漫画源'),
              value:
                  controller.sources.any((choice) => choice.key == selectedKey)
                  ? selectedKey
                  : null,
              items: [
                for (final choice in controller.sources)
                  DropdownMenuItem(
                    value: choice.key,
                    child: Text(
                      '${choice.source.name} · ${choice.source.lang} · ${choice.build.packageName}',
                    ),
                  ),
              ],
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
            TextField(
              key: const ValueKey('migration-search'),
              controller: _search,
              enabled:
                  controller.canChange && controller.selectedSource != null,
              decoration: const InputDecoration(labelText: '搜索目标作品'),
              onSubmitted: (value) => unawaited(controller.search(value)),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('migration-search-submit'),
                  onPressed:
                      controller.canChange && controller.selectedSource != null
                      ? () => unawaited(controller.search(_search.text))
                      : null,
                  child: const Text('搜索'),
                ),
                TextButton(
                  key: const ValueKey('migration-popular'),
                  onPressed:
                      controller.canChange && controller.selectedSource != null
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
              ListTile(
                key: ValueKey(('migration-result', index)),
                title: Text(controller.results[index].title),
                subtitle: Text(controller.results[index].url),
                trailing: const Icon(Icons.chevron_right),
                onTap: controller.canChange
                    ? () {
                        _mappingPage = 0;
                        unawaited(
                          controller.chooseManga(controller.results[index]),
                        );
                      }
                    : null,
              ),
            if (controller.hasNextPage)
              TextButton(
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
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
