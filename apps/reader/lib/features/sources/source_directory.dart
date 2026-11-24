import '../../widgets/choice_field.dart';
import '../../theme/app_theme.dart';

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/business_state_validation.dart';
import '../../state/account_providers.dart';
import '../browse/catalog_controller.dart';
import '../extensions/extension_listing.dart';
import '../extensions/pending_extension_changes.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_widgets.dart';
import '../settings/pending_global_settings.dart';

class const SourceDirectory({
  super.key,
  required final CatalogController catalog,
  required final VoidCallback onManage,
  required final Future<void> Function(
    ExtensionListing extension,
    wire.CatalogSource source,
  )
  onOpen,
  required final VoidCallback onSearch,
  required final ValueChanged<SourcePreferencesTarget> onPreferences,
}) extends HookConsumerWidget {
  bool _same(
    wire.FavoriteSource favorite,
    String packageName,
    String sourceId,
  ) => favorite.packageName == packageName && favorite.sourceId == sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useAutomaticKeepAlive();
    useListenable(catalog);
    final account = ref.watch(confirmedAccountProvider(catalog));
    final search = useTextEditingController(keys: [account?.settings]);
    useListenable(search);
    final language = useState<String?>(null);
    final saving = useState<(String, String)?>(null);
    final expansion = useMemoized(ExpansibleController.new);
    useEffect(() => expansion.dispose, [expansion]);
    final provider = settingsControllerProvider(catalog, catalog.settings);
    final settings = ref.watch(provider);
    final commands = ref.read(provider.notifier);
    useOnAppLifecycleStateChange((previous, state) {
      if (state == AppLifecycleState.resumed &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(commands.refresh());
      }
    });
    useEffect(() {
      scheduleMicrotask(() {
        if (context.mounted) unawaited(commands.refresh());
      });
      return null;
    }, [commands]);
    useEffect(() {
      language.value = null;
      return null;
    }, [account?.settings]);
    Future<void> toggle(String packageName, wire.CatalogSource source) async {
      final confirmed = settings.snapshot;
      if (confirmed == null || !settings.canEdit || catalog.busy) return;
      final values = confirmed.global.deepCopy();
      final exists = values.favoriteSources.any(
        (item) => _same(item, packageName, source.id),
      );
      if (exists) {
        values.favoriteSources.removeWhere(
          (item) => _same(item, packageName, source.id),
        );
      } else {
        if (values.favoriteSources.length >= businessFavoriteSourceLimit) {
          return;
        }
        values.favoriteSources.add(
          wire.FavoriteSource(
            packageName: packageName,
            sourceId: source.id,
            sourceName: source.name,
            sourceLang: source.lang,
          ),
        );
      }
      saving.value = (packageName, source.id);
      await commands.saveGlobal(values, confirmed.globalRevision);
      if (context.mounted) saving.value = null;
    }

    final favorites =
        settings.snapshot?.global.favoriteSources ?? <wire.FavoriteSource>[];
    final extensions = extensionListings(
      catalog,
      catalog.installedExtensions,
    ).where((item) => item.installed != null).toList();
    final originalFavorites = settings.pending?.previousGlobal?.favoriteSources;
    final submittedFavorites = settings.pending?.global?.favoriteSources;
    final sourceChanges = <({bool removing, wire.FavoriteSource source})>[
      if (originalFavorites != null && submittedFavorites != null) ...[
        for (final source in originalFavorites)
          if (!submittedFavorites.any(
            (item) => _same(item, source.packageName, source.sourceId),
          ))
            (removing: true, source: source),
        for (final source in submittedFavorites)
          if (!originalFavorites.any(
            (item) => _same(item, source.packageName, source.sourceId),
          ))
            (removing: false, source: source),
      ],
    ];
    final rows =
        <
          ({
            ExtensionListing? extension,
            String packageName,
            wire.CatalogSource source,
            String? blocked,
          })
        >[];
    final unresolved = <ExtensionListing>[];
    for (final extension in extensions) {
      final exact = extension.exact;
      if (exact == null) {
        unresolved.add(extension);
        continue;
      }
      for (final source in exact.sources) {
        rows.add((
          extension: extension,
          packageName: extension.packageName,
          source: source,
          blocked: extension.blockedReason,
        ));
      }
    }
    for (final favorite in favorites) {
      if (rows.any((row) => _same(favorite, row.packageName, row.source.id))) {
        continue;
      }
      final extension = extensions
          .where((item) => item.packageName == favorite.packageName)
          .firstOrNull;
      rows.add((
        extension: extension,
        packageName: favorite.packageName,
        source: wire.CatalogSource(
          id: favorite.sourceId,
          name: favorite.sourceName,
          lang: favorite.sourceLang,
        ),
        blocked:
            extension?.blockedReason ??
            (extension == null ? '扩展尚未安装' : '所选构建中未找到原漫画源'),
      ));
    }
    final nameCounts = <String, int>{};
    for (final row in rows) {
      nameCounts.update(
        row.source.name,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    bool saved(String packageName, String sourceId) =>
        favorites.any((item) => _same(item, packageName, sourceId));
    rows.sort((a, b) {
      final first = saved(a.packageName, a.source.id),
          second = saved(b.packageName, b.source.id);
      return first != second
          ? (first ? -1 : 1)
          : a.source.lang != b.source.lang
          ? a.source.lang.compareTo(b.source.lang)
          : a.source.name.toLowerCase().compareTo(b.source.name.toLowerCase());
    });
    final languages = rows.map((row) => row.source.lang).toSet().toList()
      ..sort();
    if (language.value != null && !languages.contains(language.value)) {
      language.value = null;
    }
    final query = search.text.trim().toLowerCase();
    final visible = rows
        .where(
          (row) =>
              (language.value == null || row.source.lang == language.value) &&
              (query.isEmpty || row.source.name.toLowerCase().contains(query)),
        )
        .toList();
    final pendingExtensions = unresolved
        .where((item) => item.matches(query, language.value))
        .toList();
    final hasFilter = query.isNotEmpty || language.value != null;
    final canEdit = settings.canEdit == true && !catalog.busy;
    String group(String packageName, wire.CatalogSource source) =>
        saved(packageName, source.id) ? '收藏的漫画源' : sourceLanguage(source.lang);
    final groups = visible.groupListsBy(
      (row) => group(row.packageName, row.source),
    );
    final empty =
        catalog.installationSettings != null &&
        visible.isEmpty &&
        pendingExtensions.isEmpty;
    Widget emptyFeedback() => Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.globe, size: 48),
          const SizedBox(height: 16),
          Text(
            hasFilter ? '没有匹配的漫画源' : '尚无漫画源',
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            hasFilter ? '请修改名称或语言条件。' : '安装扩展后即可选择其中的漫画源。',
            textAlign: TextAlign.center,
          ),
          CupertinoButton(
            onPressed: hasFilter
                ? () {
                    language.value = null;
                    search.clear();
                  }
                : onManage,
            child: Text(hasFilter ? '清除筛选' : '前往扩展'),
          ),
        ],
      ),
    );
    final rowsAndControls = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: CupertinoTextField(
                    autofillHints: null,
                    key: const ValueKey('source-directory-search'),
                    controller: search,
                    placeholder: '查找漫画源名称',
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
                CupertinoButton(
                  key: const ValueKey('cross-source-search-open'),
                  onPressed: catalog.busy || catalog.library == null
                      ? null
                      : onSearch,
                  padding: const EdgeInsets.all(8),
                  child: const Icon(
                    CupertinoIcons.doc_text_search,
                    semanticLabel: '跨源搜索',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ChoiceField<String>(
                    key: const ValueKey('source-language-filter'),
                    label: '语言',
                    value: language.value,
                    options: {
                      null: '全部语言',
                      for (final language in languages)
                        language: sourceLanguage(language),
                    },
                    onChanged: (value) => language.value = value,
                  ),
                ),
                if (hasFilter)
                  CupertinoButton(
                    key: const ValueKey('source-language-clear'),
                    onPressed: () {
                      language.value = null;
                      search.clear();
                    },
                    child: const Text('清除筛选'),
                  ),
              ],
            ),
          ],
        ),
      ),
      if ((settings.busy ||
          settings.snapshot == null ||
          settings.error != null ||
          settings.pending != null)) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SettingsStatus(controller: commands, state: settings),
        ),
        if (settings.pending?.global case final values?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PendingExtensionChanges(
              previous: settings.pending?.previousGlobal,
              submitted: values,
              extensionLabel: (extension) => extensionName(
                extension.packageName,
                catalog.builds
                        .where(
                          (build) =>
                              build.packageName == extension.packageName &&
                              build.id == extension.buildId &&
                              build.repoId == extension.repoId &&
                              build.catalogUrl == extension.catalogUrl,
                        )
                        .firstOrNull
                        ?.sources ??
                    const [],
              ),
            ),
          ),
        if (sourceChanges.isNotEmpty)
          CupertinoListSection.insetGrouped(
            header: Text(
              settings.pending?.acknowledged == true
                  ? '已确认的原收藏操作'
                  : '未确认的原收藏操作',
            ),
            children: [
              for (final change in sourceChanges)
                CupertinoListTile(
                  title: DefaultTextStyle(
                    style: CupertinoTheme.of(context).textTheme.textStyle,
                    child: Text(
                      '${change.removing ? '取消收藏源' : '收藏源'}：${change.source.sourceName}',
                    ),
                  ),
                  subtitle: DefaultTextStyle(
                    style: CupertinoTheme.of(context).textTheme.textStyle
                        .copyWith(
                          fontSize: 13,
                          color: AppColors.secondaryLabel.resolveFrom(context),
                        ),
                    child: Text(
                      '${sourceLanguage(change.source.sourceLang)} · ${extensions.firstWhereOrNull((item) => item.packageName == change.source.packageName)?.name ?? change.source.packageName}',
                    ),
                  ),
                ),
            ],
          ),
        if (settings.pending?.global case final values?)
          Expansible(
            key: const PageStorageKey('source-pending-global-values'),
            controller: expansion,
            animationStyle:
                MediaQuery.reduceMotionOf(context) ||
                    MediaQuery.disableAnimationsOf(context)
                ? AnimationStyle.noAnimation
                : null,
            headerBuilder: (context, animation) => Semantics(
              container: true,
              expanded: expansion.isExpanded,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => expansion.isExpanded
                    ? expansion.collapse()
                    : expansion.expand(),
                child: CupertinoListTile(
                  title: Text(
                    settings.pending?.acknowledged == true
                        ? '查看已确认的原全局设置'
                        : '查看未确认的原全局设置',
                  ),
                  trailing: RotationTransition(
                    turns: animation.drive(Tween(begin: 0.0, end: 0.25)),
                    child: Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: AppColors.accent.resolveFrom(context),
                    ),
                  ),
                ),
              ),
            ),
            bodyBuilder: (context, animation) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PendingGlobalSettings(
                values: values,
                revision: settings.pending!.basedOnRevision,
              ),
            ),
          ),
      ],
      for (final target in catalog.sourcePreferenceRecoveries)
        CupertinoListTile(
          title: Text('${target.source.name}的设置需要处理'),
          subtitle: const Text('原保存请求尚未确认'),
          trailing: CupertinoButton(
            onPressed: catalog.busy ? null : () => onPreferences(target),
            child: const Text('处理设置'),
          ),
        ),
      if (catalog.hasUnsavedReadingProgress)
        CupertinoListTile(
          title: const Text('部分阅读进度尚未保存'),
          trailing: CupertinoButton(
            onPressed: () =>
                unawaited(catalog.flushReadingProgress(explicitRetry: true)),
            child: const Text('重试保存'),
          ),
        ),
      if (catalog.installationSettings == null)
        const Center(
          child: Padding(padding: EdgeInsets.all(24), child: Text('正在读取漫画源')),
        )
      else if (empty && hasFilter)
        emptyFeedback(),
      for (final group in groups.entries)
        CupertinoListSection.insetGrouped(
          header: Text(group.key),
          children: [
            for (final row in group.value)
              Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: catalog.busy
                          ? null
                          : row.blocked != null || row.extension == null
                          ? onManage
                          : () => unawaited(onOpen(row.extension!, row.source)),
                      child: CupertinoListTile(
                        key: ValueKey((
                          'source-directory-row',
                          row.packageName,
                          row.source.id,
                        )),
                        leading: Icon(
                          CupertinoIcons.globe,
                          color: AppColors.accent.resolveFrom(context),
                        ),
                        title: Text(row.source.name, maxLines: 2),
                        subtitle: Text(
                          [
                            sourceLanguage(row.source.lang),
                            if (row.blocked != null) row.blocked!,
                            if ((nameCounts[row.source.name] ?? 0) > 1)
                              row.extension?.name ??
                                  row.packageName.split('.').last,
                          ].join(' · '),
                          maxLines: 3,
                        ),
                      ),
                    ),
                  ),
                  if (row.extension?.exact case final build?
                      when row.extension?.installed?.enabled == true &&
                          row.extension?.repositoryError == null &&
                          build.sources.any(
                            (source) => source.id == row.source.id,
                          ))
                    CupertinoButton(
                      key: ValueKey((
                        'configure-source',
                        row.packageName,
                        row.source.id,
                      )),
                      padding: const EdgeInsets.all(8),
                      onPressed: catalog.busy
                          ? null
                          : () => onPreferences(
                              SourcePreferencesTarget(
                                build: build,
                                source: wire.SourceInfo(
                                  id: row.source.id,
                                  name: row.source.name,
                                  lang: row.source.lang,
                                ),
                              ),
                            ),
                      child: const Icon(
                        CupertinoIcons.gear_alt,
                        semanticLabel: '配置漫画源',
                      ),
                    ),
                  if (saving.value == (row.packageName, row.source.id))
                    const CupertinoButton(
                      onPressed: null,
                      padding: EdgeInsets.all(8),
                      child: CupertinoActivityIndicator(),
                    )
                  else
                    Semantics(
                      toggled: saved(row.packageName, row.source.id),
                      child: CupertinoButton(
                        key: ValueKey((
                          'source-favorite-toggle',
                          row.packageName,
                          row.source.id,
                        )),
                        onPressed:
                            canEdit &&
                                (saved(row.packageName, row.source.id) ||
                                    favorites.length <
                                        businessFavoriteSourceLimit)
                            ? () =>
                                  unawaited(toggle(row.packageName, row.source))
                            : null,
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          saved(row.packageName, row.source.id)
                              ? CupertinoIcons.star_fill
                              : CupertinoIcons.star,
                          semanticLabel: saved(row.packageName, row.source.id)
                              ? '取消收藏源：${row.source.name}'
                              : '收藏源：${row.source.name}',
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      if (pendingExtensions.isNotEmpty)
        CupertinoListSection.insetGrouped(
          header: const Text('需要处理的扩展'),
          children: [
            for (final extension in pendingExtensions)
              CupertinoListTile(
                key: ValueKey((
                  'source-extension-blocked',
                  extension.packageName,
                )),
                leading: const Icon(CupertinoIcons.cube),
                title: Text('${extension.name}（扩展待处理）'),
                subtitle: Text(
                  extension.blockedReason ?? '所选构建的漫画源资料不可用',
                  maxLines: 3,
                  style: TextStyle(
                    color: AppColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                trailing: CupertinoButton(
                  onPressed: onManage,
                  child: const Text('管理扩展'),
                ),
              ),
          ],
        ),
      if (favorites.length >= businessFavoriteSourceLimit)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '已达到收藏源上限；可取消收藏后再添加。',
            key: const ValueKey('source-favorite-limit'),
            style: TextStyle(
              color: AppColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ),
    ];
    final centerEmpty = empty && !hasFilter;
    return CustomScrollView(
      key: const PageStorageKey('source-directory-scroll'),
      semanticChildCount: rowsAndControls.length + (centerEmpty ? 1 : 0),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: 8, bottom: centerEmpty ? 0 : 8),
          sliver: SliverList.list(children: rowsAndControls),
        ),
        if (centerEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: IndexedSemantics(
              index: rowsAndControls.length,
              child: Center(child: emptyFeedback()),
            ),
          ),
      ],
    );
  }
}
