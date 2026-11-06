import 'dart:async';

import 'package:flutter/material.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/catalog_controller.dart';
import '../settings/settings_widgets.dart';
import 'extensions_controller.dart';

class ExtensionsPage extends StatefulWidget {
  const ExtensionsPage({super.key, required this.catalog});
  final CatalogController catalog;

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
      isCurrent: () => mounted && ModalRoute.of(context)?.isActive == true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_controller.refresh());
    }
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
            const Text('扩展从当前服务的静态目录获取。'),
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
                    (value) => value.packageName == build.packageName,
                  ) &&
                  _matches(build.packageName, build.sources))
                Card(
                  key: ValueKey(('extension-available', build.packageName)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${build.packageName} · ${build.version}'),
                        for (final source in build.sources)
                          Text(
                            '${source.name} · ${source.lang.isEmpty ? '未标注语言' : source.lang}',
                          ),
                        FilledButton.tonal(
                          key: ValueKey((
                            'extension-install',
                            build.packageName,
                          )),
                          onPressed:
                              controller.canEdit && installed.length < 128
                              ? () => unawaited(controller.install(build))
                              : null,
                          child: const Text('准备并安装'),
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
        .where((build) => build.packageName == extension.packageName)
        .firstOrNull;
    final supported = extension.catalogUrl == widget.catalog.catalogUrl;
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
            Text(
              cached.contains(extension.bundleSha256) ? '本机产物已准备' : '本机尚未准备',
            ),
            if (!isCurrent) Text(supported ? '所选构建已下架，请手动更新。' : '这个仓库尚未接入。'),
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
                        ? () => unawaited(controller.install(latest))
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
