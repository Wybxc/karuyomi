import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import '../../data/settings_repository.dart';
import '../../data/business_state_validation.dart';
import '../browse/catalog_controller.dart';
import '../browse/source_browse_page.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_widgets.dart';
import '../settings/pending_global_settings.dart';
import 'extension_listing.dart';
import 'extensions_controller.dart';

class ExtensionsPage extends StatefulHookConsumerWidget {
  const ExtensionsPage({
    super.key,
    required this.catalog,
    required this.repository,
    this.embedded = false,
    this.onOpenSource,
  });
  final CatalogController catalog;
  final SettingsRepository repository;
  final bool embedded;
  final Future<void> Function(
    ExtensionListing extension,
    wire.CatalogSource source,
  )?
  onOpenSource;
  @override
  ConsumerState<ExtensionsPage> createState() => _ExtensionsPageState();
}

class _ExtensionsPageState extends ConsumerState<ExtensionsPage> {
  late final ExtensionsController _controller;
  late TextEditingController _search;
  String? _language;
  @override
  void initState() {
    super.initState();
    _controller = ExtensionsController(
      catalog: widget.catalog,
      container: ProviderScope.containerOf(context, listen: false),
      repository: widget.repository,
      isCurrent: () => mounted && ModalRoute.of(context)?.isActive == true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.refresh(catalogToo: true));
    });
  }

  Future<void> _details(ExtensionListing item) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ExtensionDetailsPage(
            controller: _controller,
            packageName: item.packageName,
            candidate: item.candidate,
            onOpenSource: widget.onOpenSource,
          ),
        ),
      );
  void _repositories() => unawaited(
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ExtensionRepositoriesPage(controller: _controller),
      ),
    ),
  );
  void _storage() => unawaited(
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ExtensionStoragePage(controller: _controller),
      ),
    ),
  );
  Widget _row(ExtensionListing item, bool sameName) {
    final installed = item.installed;
    final canEdit = _controller.canEdit;
    final String label;
    final VoidCallback? action;
    if (installed == null) {
      label =
          _controller.installed.any(
            (value) => value.packageName == item.packageName,
          )
          ? '替换来源'
          : '安装';
      action = canEdit
          ? () => unawaited(
              installExtension(context, _controller, item.candidate!),
            )
          : null;
    } else if (!item.registered) {
      label = '管理仓库';
      action = _repositories;
    } else if (item.needsUpdate) {
      label = '更新';
      action = canEdit
          ? () =>
                unawaited(installExtension(context, _controller, item.latest!))
          : null;
    } else if (!installed.enabled) {
      label = '启用';
      action = canEdit
          ? () => unawaited(_controller.setEnabled(installed, true))
          : null;
    } else {
      label = '管理';
      action = () => unawaited(_details(item));
    }
    return ListTile(
      key: installed != null
          ? ValueKey(('extension-installed', item.packageName))
          : ValueKey((
              'extension-available',
              item.reference.catalogUrl,
              item.packageName,
            )),
      leading: const Icon(Icons.extension_outlined),
      title: Text(item.name),
      subtitle: Text(
        '${item.languageLabel} · ${item.status(_controller.cache)}${sameName ? ' · ${item.repositoryName}' : ''}',
      ),
      onTap: () => unawaited(_details(item)),
      trailing: TextButton(
        key: installed == null
            ? ValueKey((
                'extension-install',
                item.reference.catalogUrl,
                item.packageName,
              ))
            : ValueKey(('extension-primary', item.packageName)),
        onPressed: action,
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    useAutomaticKeepAlive();
    _search = useTextEditingController();
    useListenable(_search);
    useOnAppLifecycleStateChange((_, state) {
      if (state == AppLifecycleState.resumed &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_controller.refresh());
      }
    });
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final all = extensionListings(widget.catalog, _controller.installed);
        final languages = all.expand((item) => item.languages).toSet().toList()
          ..sort();
        if (_language != null && !languages.contains(_language)) {
          _language = null;
        }
        final query = _search.text.trim().toLowerCase();
        final visible = all
            .where((item) => item.matches(query, _language))
            .toList();
        final nameCounts = <String, int>{};
        for (final item in all) {
          nameCounts.update(item.name, (count) => count + 1, ifAbsent: () => 1);
        }
        final groups = <(String, List<ExtensionListing>)>[
          ('需要处理', visible.where((item) => item.needsAttention).toList()),
          (
            '已安装',
            visible
                .where((item) => item.installed != null && !item.needsAttention)
                .toList(),
          ),
          ('可安装', visible.where((item) => item.installed == null).toList()),
        ];
        final content = ListView(
          key: const PageStorageKey('extensions-scroll'),
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('extensions-search'),
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: '查找扩展或漫画源名称',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  key: const ValueKey('extensions-more'),
                  tooltip: '扩展选项',
                  onSelected: (value) {
                    if (value == 'repositories') {
                      _repositories();
                    } else {
                      _storage();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'repositories', child: Text('仓库管理')),
                    PopupMenuItem(value: 'storage', child: Text('本机存储')),
                  ],
                ),
              ],
            ),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  key: const ValueKey('extensions-language'),
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
                TextButton.icon(
                  key: const ValueKey('extensions-check-updates'),
                  onPressed:
                      !_controller.available ||
                          _controller.busy ||
                          widget.catalog.busy
                      ? null
                      : () => unawaited(_controller.refresh(catalogToo: true)),
                  icon: const Icon(Icons.sync),
                  label: const Text('检查更新'),
                ),
                if (query.isNotEmpty || _language != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _search.clear();
                      _language = null;
                    }),
                    child: const Text('清除筛选'),
                  ),
              ],
            ),
            ExtensionOperationStatus(controller: _controller),
            if (_controller.settings.snapshot == null && !_controller.busy)
              const Text('尚未读取账户扩展，请重试。'),
            if (_controller.settings.snapshot != null &&
                _controller.installed.isEmpty)
              const Text('账户尚未安装扩展。'),
            if (widget.catalog.repositoryErrors.isNotEmpty)
              ListTile(
                title: const Text('部分仓库未能读取'),
                subtitle: const Text('已有目录仍可查看'),
                trailing: TextButton(
                  onPressed: _repositories,
                  child: const Text('管理仓库'),
                ),
              ),
            for (final group in groups)
              if (group.$2.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    '${group.$1} (${group.$2.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final item in group.$2)
                  _row(item, (nameCounts[item.name] ?? 0) > 1),
              ],
            if (visible.isEmpty && !_controller.busy)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  query.isNotEmpty || _language != null
                      ? '没有匹配的扩展，请清除筛选。'
                      : '当前目录没有扩展，请检查更新或管理仓库。',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        );
        return widget.embedded
            ? content
            : Scaffold(
                appBar: AppBar(title: const Text('扩展')),
                body: content,
              );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

Future<void> installExtension(
  BuildContext context,
  ExtensionsController controller,
  CatalogBuild build,
) async {
  final previous = controller.installed
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
          '原仓库：${Uri.parse(previous.catalogUrl).host}\n新仓库：${Uri.parse(build.catalogUrl).host}\n书架、收藏源和阅读记录保留；源设置、Cookie 和登录不会继承到新仓库。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('extension-replace-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认替换'),
          ),
        ],
      ),
    );
    if (accepted != true || !context.mounted) return;
  }
  await controller.install(
    build,
    replacing: replacing ? (previous.deepCopy()..freeze()) : null,
  );
}

class ExtensionOperationStatus extends StatelessWidget {
  const ExtensionOperationStatus({
    super.key,
    required this.controller,
    this.showStorageAction = true,
  });
  final ExtensionsController controller;
  final bool showStorageAction;
  @override
  Widget build(BuildContext context) {
    final pending = controller.settings.pending;
    final failure = controller.settings.failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (controller.busy) ...[
          const LinearProgressIndicator(),
          Text(switch (controller.activity) {
            ExtensionActivity.preparing => '正在准备扩展',
            ExtensionActivity.saving => '正在保存账户选择，等待确认',
            ExtensionActivity.cleaning => '账户已确认，正在清理本机副本',
            _ => '正在读取账户、目录与本机副本',
          }),
        ],
        if (controller.preparing)
          TextButton(
            key: const ValueKey('extensions-cancel-prepare'),
            onPressed: () => unawaited(controller.cancelPreparation()),
            child: const Text('取消准备'),
          ),
        if (controller.message case final message?)
          Text(message, key: const ValueKey('extensions-message')),
        if (controller.error case final error?)
          Text(error, key: const ValueKey('extensions-error')),
        if (controller.settings.error case final error?) Text(error),
        if (showStorageAction &&
            controller.operationFailure == RuntimeErrorCode.limitExceeded)
          TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ExtensionStoragePage(controller: controller),
              ),
            ),
            child: const Text('管理本机存储'),
          ),
        if (pending != null) ...[
          Text(switch (failure) {
            SettingsFailure.conflict => '账户已在其他设备修改，请读取最新状态后重新选择。',
            SettingsFailure.rejected => '操作未保存，请读取最新状态后处理。',
            _ => pending.retryable ? '结果待确认：请确认或重试原操作。' : '原操作尚未确认，请读取最新状态。',
          }),
          TextButton(
            key: const ValueKey('extensions-retry-settings'),
            onPressed: controller.busy || !controller.settings.canRetry
                ? null
                : () => unawaited(controller.retry()),
            child: const Text('重试原设置操作'),
          ),
          ExpansionTile(
            key: const ValueKey('extensions-pending-values'),
            title: const Text('查看未确认的原操作'),
            children: [
              if (pending.global case final values?)
                PendingGlobalSettings(
                  values: values,
                  revision: pending.basedOnRevision,
                ),
              GlobalSettingsPanel(catalog: controller.catalog),
            ],
          ),
        ],
        if (controller.cleanupError != null ||
            controller.catalog.extensionCleanupError != null) ...[
          Text(
            controller.cleanupError ??
                controller.catalog.extensionCleanupError!,
          ),
          TextButton(
            onPressed: controller.busy
                ? null
                : () => unawaited(controller.retryCleanup()),
            child: const Text('重试资源清理'),
          ),
          if (controller.catalog.canRebuildUnavailableExtension)
            TextButton(
              key: const ValueKey('extensions-rebuild-cleanup'),
              onPressed: controller.busy
                  ? null
                  : () => unawaited(controller.rebuildForCleanup()),
              child: const Text('重建运行时并恢复清理'),
            ),
        ],
        if (pending != null ||
            failure != null ||
            controller.settings.snapshot == null ||
            controller.error != null)
          TextButton.icon(
            key: const ValueKey('extensions-refresh'),
            onPressed: !controller.available || controller.busy
                ? null
                : () => unawaited(controller.refresh()),
            icon: const Icon(Icons.refresh),
            label: const Text('重新读取账户和缓存'),
          ),
      ],
    );
  }
}

class ExtensionDetailsPage extends StatelessWidget {
  const ExtensionDetailsPage({
    super.key,
    required this.controller,
    required this.packageName,
    this.candidate,
    this.onOpenSource,
  });
  final ExtensionsController controller;
  final String packageName;
  final CatalogBuild? candidate;
  final Future<void> Function(
    ExtensionListing extension,
    wire.CatalogSource source,
  )?
  onOpenSource;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final installed = controller.installed
          .where((value) => value.packageName == packageName)
          .firstOrNull;
      final item = ExtensionListing(
        catalog: controller.catalog,
        installed: installed,
        candidate: candidate,
      );
      if (installed == null && candidate == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('扩展')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ExtensionOperationStatus(controller: controller),
              const Text('账户已卸载此扩展，请返回扩展列表。'),
            ],
          ),
        );
      }
      final exact = item.exact;
      return Scaffold(
        appBar: AppBar(title: Text(item.name)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ExtensionOperationStatus(controller: controller),
            Text('${item.languageLabel} · ${item.status(controller.cache)}'),
            const SizedBox(height: 16),
            if (installed != null &&
                candidate != null &&
                (candidate!.catalogUrl != installed.catalogUrl ||
                    candidate!.repoId != installed.repoId)) ...[
              Text(
                '另一个来源：${extensionName(candidate!.packageName, candidate!.sources)} · ${Uri.parse(candidate!.catalogUrl).host}',
              ),
              FilledButton.tonal(
                onPressed: controller.canEdit
                    ? () => unawaited(
                        installExtension(context, controller, candidate!),
                      )
                    : null,
                child: const Text('替换来源'),
              ),
            ],
            if (installed != null) ...[
              SwitchListTile(
                key: ValueKey(('extension-enabled', packageName)),
                title: const Text('启用'),
                value: installed.enabled,
                onChanged: controller.canEdit
                    ? (value) =>
                          unawaited(controller.setEnabled(installed, value))
                    : null,
              ),
              if (exact != null &&
                  controller.cache != null &&
                  !controller.cache!.artifacts.any(
                    (artifact) => artifact.sha256 == installed.bundleSha256,
                  ))
                TextButton(
                  key: ValueKey(('extension-prepare', packageName)),
                  onPressed: !controller.available || controller.busy
                      ? null
                      : () => unawaited(controller.prepareInstalled(installed)),
                  child: const Text('下载本机副本'),
                ),
              if (item.needsUpdate)
                FilledButton.tonal(
                  key: ValueKey(('extension-update', packageName)),
                  onPressed: controller.canEdit
                      ? () => unawaited(
                          installExtension(context, controller, item.latest!),
                        )
                      : null,
                  child: const Text('更新'),
                ),
              if (!item.registered)
                TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          ExtensionRepositoriesPage(controller: controller),
                    ),
                  ),
                  child: const Text('管理仓库'),
                ),
              TextButton(
                key: ValueKey(('extension-uninstall', packageName)),
                onPressed: controller.canEdit
                    ? () => unawaited(controller.uninstall(installed))
                    : null,
                child: const Text('卸载扩展'),
              ),
              const Text('卸载保留书架、阅读进度、收藏源及漫画源数据。'),
            ] else if (candidate != null)
              FilledButton(
                onPressed: controller.canEdit
                    ? () => unawaited(
                        installExtension(context, controller, candidate!),
                      )
                    : null,
                child: const Text('安装'),
              ),
            const SizedBox(height: 24),
            Text('包含的漫画源', style: Theme.of(context).textTheme.titleMedium),
            if (installed != null && exact == null)
              const Text('所选构建的源资料不可用，请先处理扩展。')
            else
              for (final source
                  in (exact ?? candidate)?.sources ?? <wire.CatalogSource>[])
                ListTile(
                  title: Text(source.name),
                  subtitle: Text(sourceLanguage(source.lang)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap:
                      installed == null ||
                          item.blockedReason != null ||
                          controller.busy
                      ? null
                      : () {
                          final open = onOpenSource;
                          if (open != null) {
                            unawaited(open(item, source));
                          } else {
                            unawaited(
                              Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => SourceBrowsePage(
                                    catalog: controller.catalog,
                                    build: exact!,
                                    source: source,
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                ),
            const SizedBox(height: 24),
            ExpansionTile(
              title: const Text('诊断信息'),
              children: [
                SelectableText(
                  '包名：$packageName\n仓库：${item.reference.catalogUrl}\n身份：${item.reference.repoId}\n账户构建：${installed?.buildId ?? '未安装'}\n目录版本：${item.latest?.version ?? '不可用'}\n目录构建：${item.latest?.id ?? '不可用'}\n摘要：${installed?.bundleSha256 ?? '未下载'}',
                ),
                if (controller.catalog.activeBuild?.packageName == packageName)
                  Text(
                    '当前运行：${controller.catalog.activeBuild!.id}',
                    key: const ValueKey('extensions-running'),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class ExtensionRepositoriesPage extends StatefulWidget {
  const ExtensionRepositoriesPage({super.key, required this.controller});
  final ExtensionsController controller;
  @override
  State<ExtensionRepositoriesPage> createState() =>
      _ExtensionRepositoriesPageState();
}

class _ExtensionRepositoriesPageState extends State<ExtensionRepositoriesPage> {
  ExtensionsController get _controller => widget.controller;
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
            '${preview.repository.name}\n${Uri.parse(preview.repository.catalogUrl).host}\n${preview.builds.length} 个扩展。添加仓库不会安装扩展。',
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
          '移除“${repository.name}”后，对应扩展暂时不可用；安装选择、书架和阅读记录保留。\n受影响扩展：${_controller.installed.where((item) => item.catalogUrl == repository.catalogUrl && item.repoId == repository.repoId).map((item) => ExtensionListing(catalog: _controller.catalog, installed: item).name).join('、')}',
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final catalog = _controller.catalog;
      return Scaffold(
        appBar: AppBar(title: const Text('仓库管理')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ExtensionOperationStatus(controller: _controller),
            for (final repository in catalog.repositories)
              ListTile(
                title: Text(repository.name),
                subtitle: Text(
                  '${Uri.parse(repository.catalogUrl).host} · ${catalog.repositoryErrors[catalogReferenceKey(wire.CatalogReference(catalogUrl: repository.catalogUrl, repoId: repository.repoId))] == null ? '可用' : '读取失败'}',
                ),
                trailing: repository.catalogUrl == catalog.catalogUrl
                    ? const Text('默认')
                    : IconButton(
                        key: ValueKey((
                          'repository-remove',
                          repository.catalogUrl,
                        )),
                        tooltip: '移除仓库',
                        onPressed: _controller.canEdit
                            ? () => unawaited(_removeRepository(repository))
                            : null,
                        icon: const Icon(Icons.delete_outline),
                      ),
              ),
            TextButton.icon(
              key: const ValueKey('repositories-add'),
              onPressed:
                  _controller.canEdit && catalog.repositories.length <= 16
                  ? () => unawaited(_addRepository())
                  : null,
              icon: const Icon(Icons.add),
              label: const Text('添加仓库'),
            ),
            TextButton.icon(
              onPressed: !_controller.available || _controller.busy
                  ? null
                  : () => unawaited(_controller.refresh(catalogToo: true)),
              icon: const Icon(Icons.refresh),
              label: const Text('重试读取仓库'),
            ),
            ExpansionTile(
              title: const Text('诊断信息'),
              children: [
                for (final repository in catalog.repositories)
                  ListTile(
                    title: SelectableText(repository.catalogUrl),
                    subtitle: Text(
                      '${repository.repoId}\n${catalog.repositoryErrors[catalogReferenceKey(wire.CatalogReference(catalogUrl: repository.catalogUrl, repoId: repository.repoId))] ?? ''}',
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

String _bytes(int value) => '${(value / (1024 * 1024)).toStringAsFixed(1)} MiB';

class ExtensionStoragePage extends StatelessWidget {
  const ExtensionStoragePage({super.key, required this.controller});
  final ExtensionsController controller;
  String _name(String sha256) {
    final installed = controller.installed
        .where((item) => item.bundleSha256 == sha256)
        .firstOrNull;
    return installed == null
        ? '未使用的扩展副本'
        : ExtensionListing(
            catalog: controller.catalog,
            installed: installed,
          ).name;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final cache = controller.cache;
      return Scaffold(
        appBar: AppBar(title: const Text('本机存储')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ExtensionOperationStatus(
              controller: controller,
              showStorageAction: false,
            ),
            const Text('清理副本后仍是账户已安装状态，重新打开时会再次下载。书架与阅读记录保留。'),
            const SizedBox(height: 16),
            if (cache == null)
              const Text('正在检查本机副本')
            else ...[
              Text(
                '${cache.artifacts.length} 个副本 · ${_bytes(cache.totalBytes)}',
                key: const ValueKey('extensions-cache-usage'),
              ),
              if (cache.artifacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('本机没有扩展副本'),
                ),
              for (final artifact in cache.artifacts)
                ListTile(
                  title: Text(_name(artifact.sha256)),
                  subtitle: Text(_bytes(artifact.byteLength)),
                  trailing: TextButton(
                    key: ValueKey(('extension-forget', artifact.sha256)),
                    onPressed:
                        !controller.available ||
                            controller.busy ||
                            controller.catalog.busy
                        ? null
                        : () => unawaited(controller.forget(artifact.sha256)),
                    child: const Text('清理副本'),
                  ),
                ),
              ExpansionTile(
                title: const Text('诊断信息'),
                children: [
                  Text(
                    '${cache.artifacts.length} / ${cache.maxArtifacts} 个产物 · ${_bytes(cache.totalBytes)} / ${_bytes(cache.maxBytes)}',
                  ),
                  for (final artifact in cache.artifacts)
                    SelectableText(
                      '${_name(artifact.sha256)} · ${artifact.sha256}',
                    ),
                ],
              ),
            ],
            TextButton.icon(
              onPressed: !controller.available || controller.busy
                  ? null
                  : () => unawaited(controller.refresh()),
              icon: const Icon(Icons.refresh),
              label: const Text('重新读取本机副本'),
            ),
          ],
        ),
      );
    },
  );
}
