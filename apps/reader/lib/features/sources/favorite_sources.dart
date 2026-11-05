import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/settings_repository.dart';
import '../../data/business_state_validation.dart';
import '../browse/catalog_controller.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_widgets.dart';

bool _sameSource(wire.FavoriteSource a, wire.FavoriteSource b) =>
    a.packageName == b.packageName && a.sourceId == b.sourceId;

/// Favorite sources are confirmed global settings; this view owns no separate
/// store or retry queue. Reopening it recovers the shared session's exact draft.
class FavoriteSourcesPanel extends StatefulWidget {
  const FavoriteSourcesPanel({super.key, required this.catalog});
  final CatalogController catalog;

  @override
  State<FavoriteSourcesPanel> createState() => _FavoriteSourcesPanelState();
}

class _FavoriteSourcesPanelState extends State<FavoriteSourcesPanel>
    with WidgetsBindingObserver {
  SettingsRepository? _repository;
  SettingsController? _settings;
  bool _opening = false;
  bool _changeScheduled = false;
  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.catalog.addListener(_catalogChanged);
    _bind();
  }

  @override
  void didUpdateWidget(FavoriteSourcesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.catalog, widget.catalog)) {
      oldWidget.catalog.removeListener(_catalogChanged);
      widget.catalog.addListener(_catalogChanged);
    }
    _bind();
  }

  void _bind() {
    final catalog = widget.catalog;
    final repository = catalog.settings;
    if (identical(_repository, repository)) return;
    _settings?.removeListener(_changed);
    _settings?.dispose();
    _repository = repository;
    _settings = null;
    if (repository == null) return;
    final controller = SettingsController(
      repository: repository,
      isCurrent: () =>
          mounted &&
          !_disposing &&
          identical(widget.catalog, catalog) &&
          identical(_repository, repository) &&
          identical(catalog.settings, repository) &&
          catalog.status == ServiceStatus.ready,
    );
    _settings = controller;
    controller.addListener(_changed);
    unawaited(controller.refresh());
  }

  void _catalogChanged() {
    if (!mounted || _disposing) return;
    _bind();
    _settings?.checkCurrent();
    _changed();
  }

  void _changed() {
    if (!mounted || _disposing) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_changeScheduled) {
        _changeScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _changeScheduled = false;
          _changed();
        });
      }
      return;
    }
    setState(() {});
  }

  bool get _currentRoute {
    final route = ModalRoute.of(context);
    return mounted &&
        !_disposing &&
        route?.isCurrent == true &&
        route?.isActive == true;
  }

  bool get _available =>
      _currentRoute &&
      !_opening &&
      !widget.catalog.busy &&
      widget.catalog.status == ServiceStatus.ready;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _available) {
      unawaited(_settings?.refresh());
    }
  }

  Future<void> _toggle(wire.FavoriteSource favorite) async {
    final controller = _settings;
    final confirmed = controller?.snapshot;
    if (!_available || controller?.canEdit != true || confirmed == null) return;
    final values = confirmed.global.deepCopy();
    final exists = values.favoriteSources.any(
      (item) => _sameSource(item, favorite),
    );
    if (exists) {
      values.favoriteSources.removeWhere((item) => _sameSource(item, favorite));
    } else {
      if (values.favoriteSources.length >= businessFavoriteSourceLimit) return;
      values.favoriteSources.add(favorite.deepCopy());
    }
    // All global fields and the original CAS travel together. A pending
    // command is only retried through SettingsStatus, never through this edit.
    await controller!.saveGlobal(values, confirmed.globalRevision);
  }

  Future<void> _open(wire.FavoriteSource favorite) async {
    final catalog = widget.catalog;
    final repository = _repository;
    if (!_available || repository == null || _settings?.busy == true) return;
    final identityKey = repository.identity.key;
    bool current() =>
        mounted &&
        !_disposing &&
        _currentRoute &&
        identical(widget.catalog, catalog) &&
        identical(_repository, repository) &&
        identical(catalog.settings, repository) &&
        repository.identity.key == identityKey &&
        catalog.status == ServiceStatus.ready;
    setState(() => _opening = true);
    try {
      await catalog.openFavoriteSource(
        favorite.deepCopy()..freeze(),
        identityKey: identityKey,
        shouldContinue: current,
      );
    } finally {
      if (mounted && !_disposing) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _settings;
    if (controller == null) return const SizedBox.shrink();
    final confirmed = controller.snapshot;
    final pending = controller.pending?.global;
    final favorites =
        confirmed?.global.favoriteSources ?? <wire.FavoriteSource>[];
    final atLimit = favorites.length >= businessFavoriteSourceLimit;
    final canEdit = _available && controller.canEdit;
    final canOpen = _available && !controller.busy;
    final catalog = widget.catalog;
    final packageName = catalog.activeBuild?.packageName;
    final statusVisible =
        confirmed == null || controller.error != null || pending != null;
    final status = AbsorbPointer(
      absorbing: !_available,
      child: SettingsStatus(controller: controller),
    );
    return Column(
      children: [
        if (statusVisible) status,
        ExpansionTile(
          key: ValueKey((
            'favorite-sources-panel',
            _repository,
            confirmed == null,
          )),
          tilePadding: EdgeInsets.zero,
          title: const Text('收藏的漫画源'),
          subtitle: Text(
            confirmed == null
                ? controller.busy
                      ? '正在读取服务端收藏'
                      : '尚未读取服务端收藏'
                : '${favorites.length} 个已确认收藏${atLimit ? ' · 已达上限' : ''}${pending == null ? '' : ' · 有未确认原操作'}',
          ),
          initiallyExpanded: favorites.isNotEmpty || pending != null,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('这里只显示服务器已确认的收藏。收藏独立于当前扩展版本；不可用的来源可取消收藏。'),
                if (!statusVisible) status,
                if (pending != null)
                  _PendingGlobalSettings(
                    values: pending,
                    revision: controller.pending!.basedOnRevision,
                  ),
                if (confirmed == null && !controller.busy)
                  const Text('读取设置后可管理收藏源。'),
                if (confirmed != null && favorites.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('还没有收藏的漫画源。打开扩展后可收藏其中的来源。'),
                  ),
                for (final favorite in favorites)
                  Card(
                    key: ValueKey((
                      'favorite-source',
                      favorite.packageName,
                      favorite.sourceId,
                    )),
                    child: ListTile(
                      title: Text(favorite.sourceName),
                      subtitle: Text(
                        '${favorite.sourceLang} · ${favorite.packageName}',
                      ),
                      onTap: canOpen ? () => unawaited(_open(favorite)) : null,
                      leading: IconButton(
                        key: ValueKey((
                          'favorite-source-open',
                          favorite.packageName,
                          favorite.sourceId,
                        )),
                        tooltip: '打开收藏源：${favorite.sourceName}',
                        onPressed: canOpen
                            ? () => unawaited(_open(favorite))
                            : null,
                        icon: const Icon(Icons.play_arrow),
                      ),
                      trailing: IconButton(
                        key: ValueKey((
                          'favorite-source-remove',
                          favorite.packageName,
                          favorite.sourceId,
                        )),
                        tooltip: '取消收藏源：${favorite.sourceName}',
                        onPressed: canEdit
                            ? () => unawaited(_toggle(favorite))
                            : null,
                        icon: const Icon(Icons.star),
                      ),
                    ),
                  ),
                if (packageName != null && catalog.session != null) ...[
                  const SizedBox(height: 12),
                  const Text('收藏当前扩展中的漫画源'),
                  if (atLimit)
                    const Text(
                      '已达到 $businessFavoriteSourceLimit 个收藏源上限；可取消收藏或打开已收藏来源。',
                      key: ValueKey('source-favorite-limit'),
                    ),
                  for (final source in catalog.session!.sources)
                    Builder(
                      builder: (context) {
                        final favorite = wire.FavoriteSource(
                          packageName: packageName,
                          sourceId: source.id,
                          sourceName: source.name,
                          sourceLang: source.lang,
                        );
                        final saved = favorites.any(
                          (item) => _sameSource(item, favorite),
                        );
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(source.name),
                          subtitle: Text('${source.lang} · $packageName'),
                          trailing: IconButton(
                            key: ValueKey((
                              'source-favorite-toggle',
                              packageName,
                              source.id,
                            )),
                            tooltip: saved
                                ? '取消收藏源：${source.name}'
                                : '收藏源：${source.name}',
                            onPressed: canEdit && (saved || !atLimit)
                                ? () => unawaited(_toggle(favorite))
                                : null,
                            icon: Icon(saved ? Icons.star : Icons.star_border),
                          ),
                        );
                      },
                    ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    widget.catalog.removeListener(_catalogChanged);
    _settings?.removeListener(_changed);
    _settings?.dispose();
    super.dispose();
  }
}

class _PendingGlobalSettings extends StatelessWidget {
  const _PendingGlobalSettings({required this.values, required this.revision});
  final wire.GlobalSettingsValues values;
  final int revision;

  @override
  Widget build(BuildContext context) {
    final reader = values.reader;
    return ExpansionTile(
      key: const ValueKey('favorite-source-pending-global'),
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      title: const Text('未确认的原全局设置内容'),
      subtitle: Text('原操作基于版本 $revision；重试会保留全部原内容。'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            [
              '应用主题：${switch (values.theme) {
                wire.AppTheme.APP_THEME_DARK => '深色',
                wire.AppTheme.APP_THEME_LIGHT => '浅色',
                _ => '跟随系统',
              }}',
              '阅读模式：${switch (reader.mode) {
                wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT => '从右到左',
                wire.ReaderMode.READER_MODE_CONTINUOUS => '竖向连续',
                wire.ReaderMode.READER_MODE_WEBTOON => '条漫',
                _ => '从左到右',
              }}',
              '页组：${switch (reader.pageLayout) {
                wire.ReaderPageLayout.READER_PAGE_LAYOUT_SINGLE => '单页',
                wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE => '双页',
                _ => '自动',
              }}；图像适配：${switch (reader.fit) {
                wire.ReaderFit.READER_FIT_WIDTH => '适宽',
                wire.ReaderFit.READER_FIT_HEIGHT => '适高',
                _ => '完整显示',
              }}；裁白：${reader.cropBorders ? '开启' : '关闭'}',
              '阅读背景：${switch (reader.background) {
                wire.ReaderBackground.READER_BACKGROUND_WHITE => '白色',
                wire.ReaderBackground.READER_BACKGROUND_THEME => '跟随应用主题',
                _ => '黑色',
              }}；应用内调暗：${reader.dimPercent}%',
              '分页点击区：${_input(reader.tapZones)}；阅读快捷键：${_input(reader.keyboard)}',
              if (values.favoriteSources.isEmpty) '收藏源：空列表',
              for (final source in values.favoriteSources)
                '收藏源：${source.sourceName} · ${source.sourceLang} · ${source.packageName} · ${source.sourceId}',
            ].join('\n'),
          ),
        ),
      ],
    );
  }

  String _input(wire.ReaderInputPreset value) => switch (value) {
    wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED => '反向',
    wire.ReaderInputPreset.READER_INPUT_PRESET_DISABLED => '关闭',
    _ => '标准',
  };
}
