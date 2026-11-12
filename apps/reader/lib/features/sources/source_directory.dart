import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/business_state_validation.dart';
import '../../data/settings_repository.dart';
import '../browse/catalog_controller.dart';
import '../extensions/extension_listing.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_widgets.dart';
import '../settings/pending_global_settings.dart';

class SourceDirectory extends StatefulWidget {
  const SourceDirectory({
    super.key,
    required this.catalog,
    required this.onManage,
    required this.onOpen,
    required this.onSearch,
    required this.onPreferences,
  });
  final CatalogController catalog;
  final VoidCallback onManage;
  final Future<void> Function(
    ExtensionListing extension,
    wire.CatalogSource source,
  )
  onOpen;
  final VoidCallback onSearch;
  final ValueChanged<SourcePreferencesTarget> onPreferences;

  @override
  State<SourceDirectory> createState() => _SourceDirectoryState();
}

class _SourceDirectoryState extends State<SourceDirectory>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  SettingsController? _settings;
  SettingsRepository? _repository;
  final _search = TextEditingController();
  String? _language;
  bool _scheduled = false;
  bool _disposing = false;
  (String, String)? _saving;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.catalog.addListener(_changed);
    _bind();
  }

  void _bind() {
    final repository = widget.catalog.settings;
    if (identical(repository, _repository)) return;
    _settings?.removeListener(_changed);
    _settings?.dispose();
    _repository = repository;
    _settings = null;
    _language = null;
    _search.clear();
    if (repository == null) return;
    final settings = SettingsController(
      repository: repository,
      isCurrent: () =>
          mounted &&
          !_disposing &&
          identical(widget.catalog.settings, repository) &&
          !widget.catalog.accessPaused,
    );
    _settings = settings;
    settings.addListener(_changed);
    unawaited(settings.refresh());
  }

  void _changed() {
    if (!mounted || _disposing) return;
    _bind();
    _settings?.checkCurrent();
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_scheduled) return;
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted && !_disposing) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(SourceDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.catalog, widget.catalog)) {
      oldWidget.catalog.removeListener(_changed);
      widget.catalog.addListener(_changed);
    }
    _bind();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_settings?.refresh());
    }
  }

  bool _same(
    wire.FavoriteSource favorite,
    String packageName,
    String sourceId,
  ) => favorite.packageName == packageName && favorite.sourceId == sourceId;
  Future<void> _toggle(String packageName, wire.CatalogSource source) async {
    final settings = _settings;
    final confirmed = settings?.snapshot;
    if (confirmed == null || settings?.canEdit != true || widget.catalog.busy) {
      return;
    }
    final values = confirmed.global.deepCopy();
    final exists = values.favoriteSources.any(
      (item) => _same(item, packageName, source.id),
    );
    if (exists) {
      values.favoriteSources.removeWhere(
        (item) => _same(item, packageName, source.id),
      );
    } else {
      if (values.favoriteSources.length >= businessFavoriteSourceLimit) return;
      values.favoriteSources.add(
        wire.FavoriteSource(
          packageName: packageName,
          sourceId: source.id,
          sourceName: source.name,
          sourceLang: source.lang,
        ),
      );
    }
    setState(() => _saving = (packageName, source.id));
    await settings!.saveGlobal(values, confirmed.globalRevision);
    if (mounted) setState(() => _saving = null);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final catalog = widget.catalog;
    final settings = _settings;
    final favorites =
        settings?.snapshot?.global.favoriteSources ?? <wire.FavoriteSource>[];
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
          : a.source.name.toLowerCase().compareTo(b.source.name.toLowerCase());
    });
    final languages = rows.map((row) => row.source.lang).toSet().toList()
      ..sort();
    if (_language != null && !languages.contains(_language)) _language = null;
    final query = _search.text.trim().toLowerCase();
    final visible = rows
        .where(
          (row) =>
              (_language == null || row.source.lang == _language) &&
              (query.isEmpty || row.source.name.toLowerCase().contains(query)),
        )
        .toList();
    final pendingExtensions = unresolved
        .where((item) => item.matches(query, _language))
        .toList();
    final hasFilter = query.isNotEmpty || _language != null;
    final canEdit = settings?.canEdit == true && !catalog.busy;
    return ListView(
      key: const PageStorageKey('source-directory-scroll'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('source-directory-search'),
                controller: _search,
                decoration: const InputDecoration(
                  hintText: '查找漫画源名称',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              key: const ValueKey('cross-source-search-open'),
              tooltip: '跨源搜索',
              onPressed: catalog.busy || catalog.library == null
                  ? null
                  : widget.onSearch,
              icon: const Icon(Icons.manage_search),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('语言：'),
            DropdownButton<String>(
              key: const ValueKey('source-language-filter'),
              value: _language,
              hint: const Text('全部语言'),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('全部语言'),
                ),
                for (final language in languages)
                  DropdownMenuItem(
                    value: language,
                    child: Text(sourceLanguage(language)),
                  ),
              ],
              onChanged: (value) => setState(() => _language = value),
            ),
            if (hasFilter)
              TextButton(
                key: const ValueKey('source-language-clear'),
                onPressed: () => setState(() {
                  _language = null;
                  _search.clear();
                }),
                child: const Text('清除筛选'),
              ),
          ],
        ),
        if (settings != null &&
            (settings.snapshot == null ||
                settings.error != null ||
                settings.pending != null)) ...[
          SettingsStatus(controller: settings),
          if (settings.pending?.global case final values?)
            PendingGlobalSettings(
              values: values,
              revision: settings.pending!.basedOnRevision,
            ),
        ],
        for (final target in catalog.sourcePreferenceRecoveries)
          ListTile(
            title: Text('${target.source.name}的设置需要处理'),
            subtitle: const Text('原保存请求尚未确认'),
            trailing: TextButton(
              onPressed: catalog.busy
                  ? null
                  : () => widget.onPreferences(target),
              child: const Text('处理设置'),
            ),
          ),
        if (catalog.hasUnsavedReadingProgress)
          ListTile(
            title: const Text('部分阅读进度尚未保存'),
            trailing: TextButton(
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
                const Icon(Icons.travel_explore, size: 48),
                const SizedBox(height: 16),
                Text(
                  hasFilter ? '没有匹配的漫画源' : '尚无漫画源',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(hasFilter ? '请修改名称或语言条件。' : '安装扩展后即可选择其中的漫画源。'),
                TextButton(
                  onPressed: hasFilter
                      ? () => setState(() {
                          _language = null;
                          _search.clear();
                        })
                      : widget.onManage,
                  child: Text(hasFilter ? '清除筛选' : '前往扩展'),
                ),
              ],
            ),
          ),
        for (final row in visible)
          ListTile(
            key: ValueKey((
              'source-directory-row',
              row.packageName,
              row.source.id,
            )),
            leading: const Icon(Icons.language),
            title: Text(row.source.name),
            subtitle: Text(
              [
                sourceLanguage(row.source.lang),
                if (row.blocked != null) row.blocked!,
                if ((nameCounts[row.source.name] ?? 0) > 1)
                  row.extension?.name ?? row.packageName.split('.').last,
              ].join(' · '),
            ),
            onTap: catalog.busy
                ? null
                : row.blocked != null || row.extension == null
                ? widget.onManage
                : () => unawaited(widget.onOpen(row.extension!, row.source)),
            trailing: GestureDetector(
              excludeFromSemantics: true,
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: _saving == (row.packageName, row.source.id)
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      key: ValueKey((
                        'source-favorite-toggle',
                        row.packageName,
                        row.source.id,
                      )),
                      tooltip: saved(row.packageName, row.source.id)
                          ? '取消收藏源：${row.source.name}'
                          : '收藏源：${row.source.name}',
                      onPressed:
                          canEdit &&
                              (saved(row.packageName, row.source.id) ||
                                  favorites.length <
                                      businessFavoriteSourceLimit)
                          ? () =>
                                unawaited(_toggle(row.packageName, row.source))
                          : null,
                      icon: Icon(
                        saved(row.packageName, row.source.id)
                            ? Icons.star
                            : Icons.star_border,
                      ),
                    ),
            ),
          ),
        for (final extension in pendingExtensions)
          ListTile(
            key: ValueKey(('source-extension-blocked', extension.packageName)),
            leading: const Icon(Icons.extension_off_outlined),
            title: Text('${extension.name}（扩展待处理）'),
            subtitle: Text(extension.blockedReason ?? '所选构建的漫画源资料不可用'),
            trailing: TextButton(
              onPressed: widget.onManage,
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

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.catalog.removeListener(_changed);
    _settings?.removeListener(_changed);
    _settings?.dispose();
    _search.dispose();
    super.dispose();
  }
}
