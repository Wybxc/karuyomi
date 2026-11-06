import 'dart:async';

import 'package:flutter/material.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/settings_repository.dart';
import '../../data/business_state_validation.dart';
import '../browse/catalog_controller.dart';
import '../settings/settings_widgets.dart';
import 'extensions_controller.dart';

class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({
    super.key,
    required this.catalog,
    required this.repository,
  });
  final CatalogController catalog;
  final SettingsRepository repository;

  @override
  State<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends State<ExtensionsPage>
    with WidgetsBindingObserver {
  late final ExtensionsController _controller;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ExtensionsController(
      catalog: widget.catalog,
      repository: widget.repository,
      isCurrent: () => mounted && ModalRoute.of(context)?.isActive == true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.refresh(catalogToo: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_controller.refresh());
    }
  }

  Future<void> _addRepository() async {
    var address = '';
    var label = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('预览额外仓库'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('仓库必须公开提供 HTTPS 静态目录及 CORS，应用凭据不会发送给仓库。'),
              TextField(
                key: const ValueKey('repository-url'),
                onChanged: (value) => address = value,
                decoration: const InputDecoration(
                  labelText: '仓库地址或 /extensions/index.json URL',
                ),
              ),
              TextField(
                key: const ValueKey('repository-name'),
                onChanged: (value) => label = value,
                maxLength: 100,
                decoration: const InputDecoration(labelText: '名称（可选）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('repository-preview-submit'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('只读预览'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted || !_controller.canEdit) return;
    final preview = await _controller.previewRepository(address, label);
    if (!mounted || !_controller.available || preview == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认添加仓库'),
        content: SingleChildScrollView(
          child: Text(
            '${preview.repository.name}\n${preview.repository.catalogUrl}\n身份：${preview.repository.repoId}\n当前 ${preview.builds.length} 个扩展。添加仓库不会安装或运行代码，网络登记另行显示。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('repository-add-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认添加'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _controller.addRepository(preview);
  }

  Future<void> _removeRepository(wire.ExtensionRepository repository) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除仓库'),
        content: Text(
          '移除“${repository.name}”后关闭其运行槽；安装选择、书架、进度与来源数据保留。重新添加同一仓库后可继续准备和使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('repository-remove-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认移除'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await _controller.removeRepository(repository);
    }
  }

  Future<void> _install(CatalogBuild build) async {
    final previous = _controller.installed
        .where((value) => value.packageName == build.packageName)
        .firstOrNull;
    final replacing =
        previous != null &&
        (previous.catalogUrl != build.catalogUrl ||
            previous.repoId != build.repoId);
    if (replacing) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认替换扩展来源'),
          content: Text(
            '${build.packageName} 当前来自 ${previous.catalogUrl}。\n将改用 ${build.catalogUrl}（${build.repoId}）；原书架、收藏源和阅读记录保留，设置、Cookie及登录会话按仓库隔离，不继承到新仓库。准备完成并由服务端确认后关闭原运行槽。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('extension-replace-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('准备并确认替换'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    await _controller.install(
      build,
      replacing: replacing ? (previous.deepCopy()..freeze()) : null,
    );
  }

  bool _matches(String packageName, Iterable<wire.CatalogSource> sources) =>
      _query.isEmpty ||
      packageName.toLowerCase().contains(_query) ||
      sources.any((source) => source.name.toLowerCase().contains(_query));

  String _bytes(int value) =>
      '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final controller = _controller;
      final catalog = widget.catalog;
      final pending = controller.settings.pending;
      final cache = controller.cache;
      final cached = {
        for (final item in cache?.artifacts ?? <wire.CachedExtensionArtifact>[])
          item.sha256,
      };
      final installed = controller.installed;
      final current = catalog.activeBuild;
      return Scaffold(
        appBar: AppBar(title: const Text('扩展管理')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('账户扩展在同一身份的设备间同步；本机下载可随时重新准备。'),
            Text(
              catalog.catalogUrl,
              key: const ValueKey('extensions-catalog-url'),
            ),
            const Text('扩展从已确认仓库的公开静态目录获取。代码准备与漫画源网络登记分别检查。'),
            Text('仓库 ${catalog.repositories.length - 1} / 16（另含固定默认仓库）'),
            for (final repository in catalog.repositories)
              Card(
                child: ListTile(
                  title: Text(repository.name),
                  subtitle: Text(
                    '${repository.catalogUrl}\n身份：${repository.repoId}\n${catalog.repositoryErrors[catalogReferenceKey(wire.CatalogReference(catalogUrl: repository.catalogUrl, repoId: repository.repoId))] ?? ''}${catalog.networkPolicyErrors[catalogReferenceKey(wire.CatalogReference(catalogUrl: repository.catalogUrl, repoId: repository.repoId))] ?? ''}',
                  ),
                  trailing: repository.catalogUrl == catalog.catalogUrl
                      ? const Text('默认')
                      : IconButton(
                          key: ValueKey((
                            'repository-remove',
                            repository.catalogUrl,
                          )),
                          tooltip: '移除仓库',
                          onPressed: controller.canEdit
                              ? () => unawaited(_removeRepository(repository))
                              : null,
                          icon: const Icon(Icons.delete_outline),
                        ),
                ),
              ),
            TextButton.icon(
              key: const ValueKey('repositories-add'),
              onPressed: controller.canEdit && catalog.repositories.length <= 16
                  ? () => unawaited(_addRepository())
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('预览并添加仓库'),
            ),
            if (controller.busy) const LinearProgressIndicator(),
            if (controller.message case final value?)
              Text(value, key: const ValueKey('extensions-message')),
            if (controller.error case final value?)
              Text(value, key: const ValueKey('extensions-error')),
            if (controller.settings.error case final value?) Text(value),
            if (catalog.extensionCleanupError case final value?) ...[
              Text(value),
              TextButton(
                onPressed: controller.busy
                    ? null
                    : () => unawaited(controller.retryCleanup()),
                child: const Text('重试资源清理'),
              ),
              if (catalog.canRebuildUnavailableExtension)
                TextButton(
                  key: const ValueKey('extensions-rebuild-cleanup'),
                  onPressed: controller.busy
                      ? null
                      : () => unawaited(controller.rebuildForCleanup()),
                  child: const Text('重建运行时并恢复清理'),
                ),
            ],
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: const ValueKey('extensions-refresh'),
                  onPressed: !controller.available || controller.busy
                      ? null
                      : () => unawaited(controller.refresh()),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新读取账户和缓存'),
                ),
                TextButton.icon(
                  key: const ValueKey('extensions-check-updates'),
                  onPressed:
                      !controller.available || controller.busy || catalog.busy
                      ? null
                      : () => unawaited(controller.refresh(catalogToo: true)),
                  icon: const Icon(Icons.sync),
                  label: const Text('检查更新'),
                ),
                if (controller.preparing)
                  TextButton(
                    key: const ValueKey('extensions-cancel-prepare'),
                    onPressed: () => unawaited(controller.cancelPreparation()),
                    child: const Text('取消准备'),
                  ),
              ],
            ),
            if (pending != null) ...[
              const Text('全局设置尚未确认；请处理原操作后再修改扩展。'),
              Text('原操作基于全局版本 ${pending.basedOnRevision}'),
              TextButton(
                key: const ValueKey('extensions-retry-settings'),
                onPressed: controller.busy || !controller.settings.canRetry
                    ? null
                    : () => unawaited(controller.retry()),
                child: const Text('重试原设置操作'),
              ),
              ExpansionTile(
                key: const ValueKey('extensions-pending-values'),
                title: const Text('查看未确认的原设置内容'),
                children: [
                  GlobalSettingsPanel(controller: controller.settings),
                  for (final favorite
                      in pending.global?.favoriteSources ??
                          <wire.FavoriteSource>[])
                    Text('收藏源：${favorite.sourceName} · ${favorite.sourceLang}'),
                  for (final repository
                      in pending.global?.repositories ??
                          <wire.ExtensionRepository>[])
                    Text(
                      '仓库：${repository.name} · ${repository.catalogUrl} · ${repository.repoId}',
                    ),
                  for (final extension
                      in pending.global?.installedExtensions ??
                          <wire.InstalledExtension>[])
                    Text(
                      '扩展：${extension.packageName} · ${extension.buildId} · ${extension.enabled ? '启用' : '停用'}',
                    ),
                ],
              ),
            ],
            if (current != null)
              Text(
                '当前运行：${current.packageName} · ${current.id}',
                key: const ValueKey('extensions-running'),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('extensions-search'),
              decoration: const InputDecoration(
                labelText: '搜索扩展或漫画源名称',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            const SizedBox(height: 16),
            Text(
              '账户已安装 ${installed.length} / 128',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (controller.settings.snapshot != null && installed.isEmpty)
              const Text('账户尚未安装扩展。'),
            for (final extension in installed)
              if (_matches(extension.packageName, const []))
                _installed(extension, cached),
            const SizedBox(height: 16),
            Text('当前目录可用扩展', style: Theme.of(context).textTheme.titleMedium),
            for (final build in catalog.builds)
              if (!installed.any(
                    (value) =>
                        value.packageName == build.packageName &&
                        value.catalogUrl == build.catalogUrl &&
                        value.repoId == build.repoId,
                  ) &&
                  _matches(build.packageName, build.sources))
                Card(
                  key: ValueKey((
                    'extension-available',
                    build.catalogUrl,
                    build.packageName,
                  )),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${build.packageName} · ${build.version}'),
                        Text('${build.catalogUrl} · ${build.repoId}'),
                        Text(
                          catalog.isNetworkRegistered(build)
                              ? '网络已登记，打开时校验精确构建'
                              : '代码可准备；网络待登记或尚未读取',
                        ),
                        for (final source in build.sources)
                          Text(
                            '${source.name} · ${source.lang.isEmpty ? '未标注语言' : source.lang}',
                          ),
                        FilledButton.tonal(
                          key: ValueKey((
                            'extension-install',
                            build.catalogUrl,
                            build.packageName,
                          )),
                          onPressed:
                              controller.canEdit &&
                                  (installed.length < 128 ||
                                      installed.any(
                                        (value) =>
                                            value.packageName ==
                                            build.packageName,
                                      ))
                              ? () => unawaited(_install(build))
                              : null,
                          child: Text(
                            installed.any(
                                  (value) =>
                                      value.packageName == build.packageName,
                                )
                                ? '准备并替换来源'
                                : '准备并安装',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            if (catalog.builds.isEmpty) const Text('当前目录没有可用构建。'),
            const SizedBox(height: 16),
            Text('本机扩展缓存', style: Theme.of(context).textTheme.titleMedium),
            if (cache != null) ...[
              Text(
                '${cache.artifacts.length} / ${cache.maxArtifacts} 个产物 · ${_bytes(cache.totalBytes)} / ${_bytes(cache.maxBytes)}',
                key: const ValueKey('extensions-cache-usage'),
              ),
              for (final artifact in cache.artifacts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(artifact.sha256.substring(0, 12)),
                  subtitle: Text(_bytes(artifact.byteLength)),
                  trailing: TextButton(
                    key: ValueKey(('extension-forget', artifact.sha256)),
                    onPressed:
                        !controller.available || controller.busy || catalog.busy
                        ? null
                        : () => unawaited(controller.forget(artifact.sha256)),
                    child: const Text('清理副本'),
                  ),
                ),
            ] else
              const Text('尚未读取本机缓存。'),
            const Text('清理扩展副本不删除书架、进度、收藏源或漫画源数据。'),
          ],
        ),
      );
    },
  );

  Widget _installed(wire.InstalledExtension extension, Set<String> cached) {
    final controller = _controller;
    final latest = widget.catalog.builds
        .where(
          (build) =>
              build.packageName == extension.packageName &&
              build.catalogUrl == extension.catalogUrl &&
              build.repoId == extension.repoId,
        )
        .firstOrNull;
    final supported = widget.catalog.isRepositoryRegistered(
      wire.CatalogReference(
        catalogUrl: extension.catalogUrl,
        repoId: extension.repoId,
      ),
    );
    final isCurrent =
        supported &&
        latest?.repoId == extension.repoId &&
        latest?.id == extension.buildId;
    return Card(
      key: ValueKey(('extension-installed', extension.packageName)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(extension.packageName),
            Text('账户选择：${extension.buildId}'),
            Text('${extension.catalogUrl} · ${extension.repoId}'),
            if (latest != null)
              Text(
                widget.catalog.isNetworkRegistered(
                      latest,
                      sha256: extension.bundleSha256,
                    )
                    ? '网络已登记'
                    : '代码与账户选择保留；网络待登记或尚未读取',
              ),
            Text(
              cached.contains(extension.bundleSha256) ? '本机产物已准备' : '本机尚未准备',
            ),
            if (!isCurrent)
              Text(supported ? '所选构建已下架，请手动更新。' : '这个仓库已移除，请重新预览并添加。'),
            if (latest != null) Text('当前目录：${latest.version} · ${latest.id}'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              key: ValueKey(('extension-enabled', extension.packageName)),
              title: const Text('启用'),
              value: extension.enabled,
              onChanged: controller.canEdit
                  ? (value) =>
                        unawaited(controller.setEnabled(extension, value))
                  : null,
            ),
            Wrap(
              spacing: 8,
              children: [
                if (isCurrent && !cached.contains(extension.bundleSha256))
                  TextButton(
                    key: ValueKey(('extension-prepare', extension.packageName)),
                    onPressed: !controller.available || controller.busy
                        ? null
                        : () =>
                              unawaited(controller.prepareInstalled(extension)),
                    child: const Text('准备本机副本'),
                  ),
                if (supported && latest != null && !isCurrent)
                  FilledButton.tonal(
                    key: ValueKey(('extension-update', extension.packageName)),
                    onPressed: controller.canEdit
                        ? () => unawaited(_install(latest))
                        : null,
                    child: const Text('准备并确认更新'),
                  ),
                TextButton(
                  key: ValueKey(('extension-uninstall', extension.packageName)),
                  onPressed: controller.canEdit
                      ? () => unawaited(controller.uninstall(extension))
                      : null,
                  child: const Text('卸载并清理本机副本'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }
}
