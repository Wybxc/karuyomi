import '../../widgets/choice_field.dart';
import '../../theme/app_theme.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/business_state_validation.dart';
import '../../state/account_providers.dart';
import '../browse/catalog_controller.dart';
import '../extensions/extension_listing.dart';
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
    return ListView(
      key: const PageStorageKey('source-directory-scroll'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
        if ((settings.snapshot == null ||
            settings.error != null ||
            settings.pending != null)) ...[
          SettingsStatus(controller: commands, state: settings),
          if (settings.pending?.global case final values?)
            PendingGlobalSettings(
              values: values,
              revision: settings.pending!.basedOnRevision,
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
        else if (visible.isEmpty && pendingExtensions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Icon(CupertinoIcons.globe, size: 48),
                const SizedBox(height: 16),
                Text(
                  hasFilter ? '没有匹配的漫画源' : '尚无漫画源',
                  style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                ),
                const SizedBox(height: 8),
                Text(hasFilter ? '请修改名称或语言条件。' : '安装扩展后即可选择其中的漫画源。'),
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
          ),
        for (final (index, row) in visible.indexed) ...[
          if (index == 0 ||
              group(row.packageName, row.source) !=
                  group(
                    visible[index - 1].packageName,
                    visible[index - 1].source,
                  ))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Text(
                group(row.packageName, row.source),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
          CupertinoButton(
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
              leading: const Icon(CupertinoIcons.globe),
              title: Text(row.source.name),
              subtitle: Text(
                [
                  sourceLanguage(row.source.lang),
                  if (row.blocked != null) row.blocked!,
                  if ((nameCounts[row.source.name] ?? 0) > 1)
                    row.extension?.name ?? row.packageName.split('.').last,
                ].join(' · '),
                maxLines: 3,
                style: TextStyle(
                  color: AppColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              trailing: GestureDetector(
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: saving.value == (row.packageName, row.source.id)
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CupertinoActivityIndicator(),
                      )
                    : CupertinoButton(
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
            ),
          ),
        ],
        for (final extension in pendingExtensions)
          CupertinoListTile(
            key: ValueKey(('source-extension-blocked', extension.packageName)),
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
        if (favorites.length >= businessFavoriteSourceLimit)
          const Text(
            '已达到收藏源上限；可取消收藏后再添加。',
            key: ValueKey('source-favorite-limit'),
          ),
      ],
    );
  }
}
