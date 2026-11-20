import '../../widgets/app_routes.dart';
import '../../widgets/choice_field.dart';
import '../../widgets/edit_sheet.dart';
import '../../theme/app_theme.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:proper_filesize/proper_filesize.dart' show FileSize;
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import '../../data/settings_repository.dart';
import '../../data/business_state_validation.dart';
import '../browse/catalog_controller.dart';
import '../browse/source_browse_page.dart';
import '../settings/settings_controller.dart';
import '../settings/pending_global_settings.dart';
import 'extension_listing.dart';
import 'extensions_controller.dart';
import 'pending_extension_changes.dart';

class const ExtensionsPage({
  super.key,
  required final CatalogController catalog,
  required final SettingsRepository repository,
  final bool embedded = false,
  final Future<void> Function(
    ExtensionListing extension,
    wire.CatalogSource source,
  )?
  onOpenSource,
}) extends StatefulHookConsumerWidget {
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
      if (mounted) {
        unawaited(
          _controller.refresh(catalogToo: true, reportCatalogCheck: false),
        );
      }
    });
  }

  Future<void> _details(ExtensionListing item) =>
      Navigator.of(context).push<void>(
        AppPageRoute(
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
      AppPageRoute(
        builder: (_) => ExtensionRepositoriesPage(controller: _controller),
      ),
    ),
  );
  void _storage() => unawaited(
    Navigator.of(context).push<void>(
      AppPageRoute(
        builder: (_) => ExtensionStoragePage(controller: _controller),
      ),
    ),
  );

  Widget _directoryStatus(String label, {bool failed = false}) => Semantics(
    liveRegion: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: (failed ? AppColors.error : AppColors.secondaryLabel)
                .resolveFrom(context),
          ),
        ),
        CupertinoButton(onPressed: _repositories, child: const Text('管理仓库')),
      ],
    ),
  );

  Widget _row(ExtensionListing item, bool sameName) {
    final installed = item.installed;
    final version = (installed == null ? item.candidate : item.exact)?.version;
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
    return Row(
      children: [
        Expanded(
          child: CupertinoButton(
            key: ValueKey((
              'extension-details',
              item.reference.catalogUrl,
              item.packageName,
            )),
            padding: EdgeInsets.zero,
            onPressed: () => unawaited(_details(item)),
            child: CupertinoListTile(
              key: installed != null
                  ? ValueKey(('extension-installed', item.packageName))
                  : ValueKey((
                      'extension-available',
                      item.reference.catalogUrl,
                      item.packageName,
                    )),
              leading: Icon(
                CupertinoIcons.cube_box,
                color: AppColors.accent.resolveFrom(context),
              ),
              title: Text(item.name, maxLines: 2),
              subtitle: Text(
                [
                  ?version,
                  item.languageSummary,
                  item.status(_controller.cache),
                  if (sameName) item.repositoryName,
                ].join(' · '),
                maxLines: 3,
              ),
            ),
          ),
        ),
        CupertinoButton(
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
      ],
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
    useListenable(_controller);
    final catalog = widget.catalog;
    final settings = _controller.settings;
    final all = extensionListings(catalog, _controller.installed);
    final languages = all.expand((item) => item.languages).toSet().toList()
      ..sort();
    if (_language != null && !languages.contains(_language)) {
      _language = null;
    }
    final query = _search.text.trim().toLowerCase();
    final visible = all
        .where((item) => item.matches(query, _language))
        .toList();
    final filtered = query.isNotEmpty || _language != null;
    final canCheck =
        _controller.available && !_controller.busy && !catalog.busy;
    final repositoryReadFailed = catalog.repositoryErrors.isNotEmpty;
    final readingEmptyDirectory =
        all.isEmpty &&
        _controller.activity == ExtensionActivity.reading &&
        settings.pending == null;
    Widget? directoryState;
    if (readingEmptyDirectory) {
      directoryState = Semantics(
        liveRegion: true,
        label: '正在读取扩展目录',
        child: const CupertinoActivityIndicator(),
      );
    } else if (visible.isEmpty && canCheck) {
      if (all.isEmpty && repositoryReadFailed) {
        directoryState = _directoryStatus('未能读取扩展目录', failed: true);
      } else if (all.isNotEmpty) {
        directoryState = const Text(
          '没有匹配的扩展，请清除筛选。',
          textAlign: TextAlign.center,
        );
      } else if (settings.snapshot != null &&
          settings.error == null &&
          _controller.error == null) {
        directoryState = _directoryStatus('当前目录没有扩展');
      }
    }
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
    final preparationFailure = _controller.preparationFailure;
    final list = CustomScrollView(
      key: const PageStorageKey('extensions-scroll'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: CupertinoTextField(
                        autofillHints: null,
                        key: const ValueKey('extensions-search'),
                        controller: _search,
                        placeholder: '查找扩展或漫画源名称',
                        placeholderStyle: TextStyle(
                          color: AppColors.secondaryLabel.resolveFrom(context),
                        ),
                        prefix: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(
                            CupertinoIcons.search,
                            color: AppColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                        clearButtonMode: OverlayVisibilityMode.editing,
                        decoration: BoxDecoration(
                          color: AppColors.groupedSurface.resolveFrom(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    CupertinoMenuAnchor(
                      key: const ValueKey('extensions-more'),
                      menuChildren: [
                        CupertinoMenuItem(
                          autofocus: true,
                          onPressed: _repositories,
                          child: Text('仓库管理'),
                        ),
                        CupertinoMenuItem(
                          onPressed: _storage,
                          child: Text('本机存储'),
                        ),
                      ],
                      builder: (context, menu, child) => CupertinoButton(
                        onPressed: () =>
                            menu.isOpen ? menu.close() : menu.open(),
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          CupertinoIcons.ellipsis,
                          semanticLabel: '扩展选项',
                        ),
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceField<String>(
                      key: const ValueKey('extensions-language'),
                      label: '语言',
                      value: _language,
                      options: {
                        null: '全部语言',
                        for (final language in languages)
                          language: sourceLanguage(language),
                      },
                      onChanged: (value) => setState(() => _language = value),
                    ),
                    CupertinoButton(
                      key: const ValueKey('extensions-check-updates'),
                      onPressed: canCheck
                          ? () =>
                                unawaited(_controller.refresh(catalogToo: true))
                          : null,
                      child: const Text('检查更新'),
                    ),
                    if (filtered)
                      CupertinoButton(
                        onPressed: () => setState(() {
                          _search.clear();
                          _language = null;
                        }),
                        child: const Text('清除筛选'),
                      ),
                  ],
                ),
                ExtensionOperationStatus(
                  controller: _controller,
                  showPreparation: false,
                  showProgress: !readingEmptyDirectory,
                ),
                if (settings.snapshot == null &&
                    canCheck &&
                    settings.error == null)
                  const Text('尚未读取账户扩展，请重试。'),
                if (all.isNotEmpty &&
                    settings.snapshot != null &&
                    settings.error == null &&
                    _controller.installed.isEmpty)
                  const Text('账户尚未安装扩展。'),
                if (repositoryReadFailed && all.isNotEmpty)
                  CupertinoListTile(
                    title: Text(
                      catalog.repositoryErrors.length <
                              catalog.repositories.length
                          ? '部分仓库未能读取'
                          : '未能读取扩展目录',
                      style: TextStyle(
                        color: AppColors.error.resolveFrom(context),
                      ),
                    ),
                    trailing: CupertinoButton(
                      onPressed: _repositories,
                      child: const Text('管理仓库'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (visible.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 16),
            sliver: SliverList.list(
              children: [
                for (final group in groups)
                  if (group.$2.isNotEmpty)
                    CupertinoListSection.insetGrouped(
                      header: Text('${group.$1} (${group.$2.length})'),
                      children: [
                        for (final item in group.$2)
                          _row(item, (nameCounts[item.name] ?? 0) > 1),
                      ],
                    ),
              ],
            ),
          ),
        if (directoryState != null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: directoryState),
            ),
          ),
      ],
    );
    final preparationStatus = switch (_controller.preparationBuild) {
      final build? => _ExtensionPreparationStatus(
        controller: _controller,
        target: build,
      ),
      null when preparationFailure != null =>
        _ExtensionPreparationFailureStatus(
          controller: _controller,
          failure: preparationFailure,
        ),
      null => null,
    };
    final content = LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (preparationStatus != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: preparationStatus,
              ),
            ),
          Expanded(child: list),
        ],
      ),
    );
    return widget.embedded
        ? content
        : CupertinoPageScaffold(
            navigationBar: CupertinoNavigationBar(middle: const Text('扩展')),
            child: SafeArea(child: content),
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
    final accepted = await showAppDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认替换扩展来源'),
        content: Text(
          '原仓库：${Uri.parse(previous.catalogUrl).host}\n新仓库：${Uri.parse(build.catalogUrl).host}\n书架、收藏源和阅读记录保留；源设置、Cookie 和登录不会继承到新仓库。',
        ),
        actions: [
          CupertinoButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoButton(
            key: const ValueKey('extension-replace-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '确认替换',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
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

class const ExtensionOperationStatus({
  super.key,
  required final ExtensionsController controller,
  final bool showStorageAction = true,
  final bool showProgress = true,
  final bool showPreparation = true,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final expansion = useMemoized(ExpansibleController.new);
    useEffect(() => expansion.dispose, [expansion]);
    final pending = controller.settings.pending;
    final repositoryTarget = controller.repositoryTarget;
    final failure = controller.settings.failure;
    final errorStyle = TextStyle(color: AppColors.error.resolveFrom(context));
    final preparation = controller.preparationBuild;
    final preparationFailure = controller.preparationFailure;
    final operationError = preparationFailure == null ? controller.error : null;
    final copy = controller.cleanupTarget;
    final cleaning =
        copy != null && controller.activity == ExtensionActivity.cleaning;
    final cleanupError =
        controller.cleanupError ?? controller.catalog.extensionCleanupError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showProgress &&
            controller.busy &&
            preparation == null &&
            !cleaning) ...[
          const CupertinoActivityIndicator(),
          Text(
            controller.settings.pending?.acknowledged == true &&
                    {
                      ExtensionActivity.reading,
                      ExtensionActivity.saving,
                    }.contains(controller.activity)
                ? '原账户操作已确认，正在读取最新设置'
                : switch (controller.activity) {
                    ExtensionActivity.previewing => '正在预览仓库',
                    ExtensionActivity.saving => '正在保存账户选择，等待确认',
                    _ => '正在读取账户、目录与本机副本',
                  },
          ),
        ],
        if (controller.busy && pending == null && repositoryTarget != null)
          CupertinoListSection.insetGrouped(
            margin: EdgeInsets.zero,
            header: const Text('当前仓库'),
            footer: controller.activity == ExtensionActivity.previewing
                ? const Text('只读预览不会更改账户或安装扩展。')
                : null,
            children: [
              CupertinoListTile(
                title: DefaultTextStyle(
                  style: CupertinoTheme.of(context).textTheme.textStyle,
                  child: Text(repositoryTarget.name),
                ),
                subtitle: DefaultTextStyle(
                  style: CupertinoTheme.of(context).textTheme.textStyle
                      .copyWith(
                        fontSize: 13,
                        color: AppColors.secondaryLabel.resolveFrom(context),
                      ),
                  child: Text(repositoryTarget.catalogUrl),
                ),
              ),
            ],
          ),
        if (showPreparation && preparation != null)
          _ExtensionPreparationStatus(
            controller: controller,
            target: preparation,
          ),
        if (showPreparation && preparationFailure != null)
          _ExtensionPreparationFailureStatus(
            controller: controller,
            failure: preparationFailure,
            showStorageAction: showStorageAction,
          ),
        if (controller.message case final message?)
          Text(message, key: const ValueKey('extensions-message')),
        if (operationError != null)
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              operationError,
              key: const ValueKey('extensions-error'),
              style: errorStyle,
            ),
          ),
        if (controller.settings.error case final error?)
          Text(error, style: errorStyle),
        if (showStorageAction &&
            preparationFailure == null &&
            controller.operationFailure == RuntimeErrorCode.limitExceeded)
          CupertinoButton(
            onPressed: () => Navigator.of(context).push<void>(
              AppPageRoute(
                builder: (_) => ExtensionStoragePage(controller: controller),
              ),
            ),
            child: const Text('管理本机存储'),
          ),
        if (pending != null) ...[
          if (!controller.busy)
            Text(switch (failure) {
              SettingsFailure.conflict => '账户已在其他设备修改，请读取最新状态后重新选择。',
              SettingsFailure.rejected => '操作未保存，请读取最新状态后处理。',
              SettingsFailure.confirmedRead => '原账户操作已确认，请重试读取最新状态。',
              _ =>
                pending.acknowledged
                    ? '原账户操作已确认，请读取最新状态。'
                    : pending.retryable
                    ? '结果待确认：请确认或重试原操作。'
                    : '原操作已被拒绝，请读取最新状态。',
            }),
          if (pending.global case final values?)
            PendingExtensionChanges(
              previous: pending.previousGlobal,
              submitted: values,
              extensionLabel: (extension) => extensionName(
                extension.packageName,
                controller.catalog.builds
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
          CupertinoButton(
            key: const ValueKey('extensions-retry-settings'),
            onPressed: controller.busy || !controller.settings.canRetry
                ? null
                : () => unawaited(controller.retry()),
            child: Text(pending.acknowledged ? '重试读取最新设置' : '重试原设置操作'),
          ),
          Expansible(
            key: const PageStorageKey('extensions-pending-values'),
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
                  title: Text(pending.acknowledged ? '查看已确认的原操作' : '查看未确认的原操作'),
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
            bodyBuilder: (context, animation) => switch (pending.global) {
              final values? => PendingGlobalSettings(
                values: values,
                revision: pending.basedOnRevision,
              ),
              null => const SizedBox.shrink(),
            },
          ),
        ],
        if (cleaning || cleanupError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ExtensionCleanupStatus(
              controller: controller,
              copy: copy,
              cleaning: cleaning,
              error: cleanupError,
            ),
          ),
        if (pending != null ||
            failure != null ||
            controller.settings.snapshot == null ||
            operationError != null)
          CupertinoButton(
            key: const ValueKey('extensions-refresh'),
            onPressed: !controller.available || controller.busy
                ? null
                : () => unawaited(controller.refresh()),
            child: const Text('重新读取账户和缓存'),
          ),
      ],
    );
  }
}

class const _ExtensionPreparationStatus({
  required final ExtensionsController controller,
  required final CatalogBuild target,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('extension-preparation-status'),
    container: true,
    explicitChildNodes: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            // A new phase starts at the heading even after reading the details.
            key: ValueKey(controller.preparing),
            primary: false,
            child: CupertinoFormSection.insetGrouped(
              margin: EdgeInsets.zero,
              header: Semantics(
                liveRegion: true,
                child: Text(controller.preparing ? '正在准备扩展' : '正在取消准备'),
              ),
              children: [
                CupertinoListTile(
                  title: DefaultTextStyle(
                    style: CupertinoTheme.of(context).textTheme.textStyle,
                    child: Text(
                      extensionName(target.packageName, target.sources),
                    ),
                  ),
                  subtitle: Text(target.version),
                  trailing: const CupertinoActivityIndicator(),
                ),
              ],
            ),
          ),
        ),
        if (controller.preparing)
          CupertinoButton(
            key: const ValueKey('extensions-cancel-prepare'),
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => unawaited(controller.cancelPreparation()),
            child: const Text('取消准备'),
          ),
      ],
    ),
  );
}

class const _ExtensionPreparationFailureStatus({
  required final ExtensionsController controller,
  required final ExtensionPreparationFailure failure,
  final bool showStorageAction = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final build = failure.build;
    final item = ExtensionListing(
      catalog: controller.catalog,
      candidate: build,
    );
    final currentBuild = controller.catalog.builds
        .where(
          (candidate) =>
              candidate.id == build.id &&
              candidate.packageName == build.packageName &&
              candidate.repoId == build.repoId &&
              candidate.catalogUrl == build.catalogUrl,
        )
        .firstOrNull;
    final localCopyOf = failure.localCopyOf;
    VoidCallback? retry;
    if (currentBuild != null &&
        item.registered &&
        !controller.busy &&
        !controller.catalog.busy) {
      if (localCopyOf == null && controller.canEdit) {
        retry = () =>
            unawaited(installExtension(context, controller, currentBuild));
      } else if (localCopyOf != null &&
          controller.installed.contains(localCopyOf)) {
        retry = () => unawaited(controller.prepareInstalled(localCopyOf));
      }
    }
    final storageFull =
        controller.operationFailure == RuntimeErrorCode.limitExceeded;
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            primary: false,
            child: CupertinoFormSection.insetGrouped(
              margin: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        container: true,
                        liveRegion: true,
                        label: '扩展准备失败',
                        child: Text(
                          failure.reason,
                          key: const ValueKey('extensions-error'),
                          style: textStyle.copyWith(
                            fontSize: 13,
                            color: AppColors.error.resolveFrom(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(item.name),
                      Text(
                        '${build.version} · ${item.repositoryName}',
                        style: textStyle.copyWith(
                          fontSize: 13,
                          color: AppColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!storageFull || showStorageAction)
          CupertinoButton(
            key: storageFull
                ? null
                : const ValueKey('extensions-retry-prepare'),
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            onPressed: storageFull
                ? () => Navigator.of(context).push<void>(
                    AppPageRoute(
                      builder: (_) =>
                          ExtensionStoragePage(controller: controller),
                    ),
                  )
                : retry,
            child: Text(storageFull ? '管理本机存储' : '重试准备'),
          ),
      ],
    );
  }
}

class const _ExtensionCleanupStatus({
  required final ExtensionsController controller,
  required final ExtensionLocalCopy? copy,
  required final bool cleaning,
  required final String? error,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final canRetry =
        controller.available && !controller.busy && !controller.catalog.busy;
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    return Semantics(
      key: const ValueKey('extension-cleanup-status'),
      container: true,
      explicitChildNodes: true,
      child: CupertinoFormSection.insetGrouped(
        margin: EdgeInsets.zero,
        header: Semantics(
          liveRegion: true,
          child: Text(cleaning ? '正在清理本机副本' : '清理未完成'),
        ),
        children: [
          if (error case final failure? when !cleaning) ...[
            CupertinoFormRow(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  failure,
                  style: TextStyle(color: AppColors.error.resolveFrom(context)),
                ),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                alignment: AlignmentDirectional.centerStart,
                onPressed: canRetry
                    ? () => unawaited(controller.retryCleanup())
                    : null,
                child: const Text('重试资源清理'),
              ),
            ),
            if (controller.catalog.canRebuildUnavailableExtension)
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  key: const ValueKey('extensions-rebuild-cleanup'),
                  alignment: AlignmentDirectional.centerStart,
                  onPressed: canRetry
                      ? () => unawaited(controller.rebuildForCleanup())
                      : null,
                  child: const Text('重建运行时并恢复清理'),
                ),
              ),
          ],
          if (copy case final target?)
            CupertinoListTile(
              title: DefaultTextStyle(
                style: textStyle,
                child: Text(target.name),
              ),
              subtitle: DefaultTextStyle(
                style: textStyle.copyWith(
                  fontSize: 13,
                  color: AppColors.secondaryLabel.resolveFrom(context),
                ),
                child: Text(target.sha256),
              ),
              trailing: cleaning ? const CupertinoActivityIndicator() : null,
            ),
        ],
      ),
    );
  }
}

class const ExtensionDetailsPage({
  super.key,
  required final ExtensionsController controller,
  required final String packageName,
  final CatalogBuild? candidate,
  final Future<void> Function(
    ExtensionListing extension,
    wire.CatalogSource source,
  )?
  onOpenSource,
}) extends HookWidget {
  Future<void> _confirmUninstall(
    BuildContext context,
    ExtensionListing item,
  ) async {
    final installed = item.installed;
    if (installed == null || !controller.canEdit) return;
    final name = item.name;
    final origin = [?item.exact?.version, item.repositoryName].join(' · ');
    final accepted = await showAppDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('卸载扩展？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('此扩展将从账户移除。'),
            const SizedBox(height: 8),
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(origin),
            const SizedBox(height: 8),
            const Text('书架、分类、阅读进度、收藏源及漫画源数据会保留。'),
          ],
        ),
        actions: [
          CupertinoButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoButton(
            key: const ValueKey('extension-uninstall-confirm'),
            foregroundColor: AppColors.error.resolveFrom(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认卸载'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      await controller.uninstall(installed);
    }
  }

  @override
  Widget build(BuildContext context) {
    useListenable(controller);
    final diagnostics = useMemoized(ExpansibleController.new);
    useEffect(() => diagnostics.dispose, [diagnostics]);
    final installed = controller.installed
        .where((value) => value.packageName == packageName)
        .firstOrNull;
    final item = ExtensionListing(
      catalog: controller.catalog,
      installed: installed,
      candidate: candidate,
    );
    const navigationBar = CupertinoNavigationBar(middle: Text('扩展详情'));
    if (installed == null && candidate == null) {
      return CupertinoPageScaffold(
        navigationBar: navigationBar,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ExtensionOperationStatus(controller: controller),
              const Text('账户已卸载此扩展，请返回扩展列表。'),
            ],
          ),
        ),
      );
    }
    final exact = item.exact;
    final version = (installed == null ? candidate : exact)?.version;
    final canOpenSource =
        installed != null && item.blockedReason == null && !controller.busy;
    final textTheme = CupertinoTheme.of(context).textTheme;
    return CupertinoPageScaffold(
      navigationBar: navigationBar,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ExtensionOperationStatus(controller: controller),
            ),
            Semantics(
              container: true,
              explicitChildNodes: true,
              child: CupertinoFormSection.insetGrouped(
                footer: installed == null
                    ? null
                    : const Text('卸载保留书架、阅读进度、收藏源及漫画源数据。'),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: CupertinoListTile(
                      leading: Icon(
                        CupertinoIcons.cube_box,
                        color: AppColors.accent.resolveFrom(context),
                      ),
                      title: DefaultTextStyle(
                        style: textTheme.navTitleTextStyle,
                        child: Semantics(header: true, child: Text(item.name)),
                      ),
                      subtitle: DefaultTextStyle(
                        style: textTheme.textStyle.copyWith(
                          fontSize: 12,
                          color: AppColors.secondaryLabel.resolveFrom(context),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(packageName),
                            Text(
                              [
                                ?version,
                                item.languageSummary,
                                item.status(controller.cache),
                              ].join(' · '),
                            ),
                            Text(item.repositoryName),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (installed != null &&
                      candidate != null &&
                      (candidate!.catalogUrl != installed.catalogUrl ||
                          candidate!.repoId != installed.repoId)) ...[
                    Text(
                      '另一个来源：${extensionName(candidate!.packageName, candidate!.sources)} · ${Uri.parse(candidate!.catalogUrl).host}',
                    ),
                    CupertinoButton.filled(
                      onPressed: controller.canEdit
                          ? () => unawaited(
                              installExtension(context, controller, candidate!),
                            )
                          : null,
                      child: const Text('替换来源'),
                    ),
                  ],
                  if (installed != null) ...[
                    MergeSemantics(
                      child: CupertinoFormRow(
                        prefix: Expanded(flex: 3, child: const Text('启用')),
                        child: CupertinoSwitch(
                          key: ValueKey(('extension-enabled', packageName)),
                          value: installed.enabled,
                          onChanged: controller.canEdit
                              ? (value) => unawaited(
                                  controller.setEnabled(installed, value),
                                )
                              : null,
                        ),
                      ),
                    ),
                    if (exact != null &&
                        controller.cache != null &&
                        !controller.cache!.artifacts.any(
                          (artifact) =>
                              artifact.sha256 == installed.bundleSha256,
                        ))
                      CupertinoButton(
                        key: ValueKey(('extension-prepare', packageName)),
                        onPressed: !controller.available || controller.busy
                            ? null
                            : () => unawaited(
                                controller.prepareInstalled(installed),
                              ),
                        child: const Text('下载本机副本'),
                      ),
                    if (item.needsUpdate)
                      CupertinoButton.filled(
                        key: ValueKey(('extension-update', packageName)),
                        onPressed: controller.canEdit
                            ? () => unawaited(
                                installExtension(
                                  context,
                                  controller,
                                  item.latest!,
                                ),
                              )
                            : null,
                        child: const Text('更新'),
                      ),
                    if (!item.registered)
                      CupertinoButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          AppPageRoute(
                            builder: (_) => ExtensionRepositoriesPage(
                              controller: controller,
                            ),
                          ),
                        ),
                        child: const Text('管理仓库'),
                      ),
                    CupertinoButton(
                      key: ValueKey(('extension-uninstall', packageName)),
                      onPressed: controller.canEdit
                          ? () => unawaited(_confirmUninstall(context, item))
                          : null,
                      child: Text(
                        '卸载扩展',
                        style: TextStyle(
                          color: controller.canEdit
                              ? AppColors.error.resolveFrom(context)
                              : AppColors.secondaryLabel.resolveFrom(context),
                        ),
                      ),
                    ),
                  ] else if (candidate != null)
                    CupertinoButton.filled(
                      onPressed: controller.canEdit
                          ? () => unawaited(
                              installExtension(context, controller, candidate!),
                            )
                          : null,
                      child: const Text('安装'),
                    ),
                ],
              ),
            ),
            CupertinoListSection.insetGrouped(
              hasLeading: false,
              header: Semantics(
                header: true,
                child: Text(
                  '包含的漫画源',
                  style: textTheme.textStyle.copyWith(
                    fontSize: 13,
                    color: AppColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
              children: [
                if (installed != null && exact == null)
                  const CupertinoListTile(
                    title: Text('所选构建的源资料不可用，请先处理扩展。', maxLines: 3),
                  )
                else
                  for (final source
                      in (exact ?? candidate)?.sources ??
                          <wire.CatalogSource>[])
                    Semantics(
                      container: true,
                      enabled: canOpenSource,
                      child: CupertinoButton(
                        key: ValueKey(('extension-source', source.id)),
                        padding: EdgeInsets.zero,
                        onPressed: !canOpenSource
                            ? null
                            : () {
                                final open = onOpenSource;
                                if (open != null) {
                                  unawaited(open(item, source));
                                } else {
                                  unawaited(
                                    Navigator.of(context).push<void>(
                                      AppPageRoute(
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
                        child: CupertinoListTile(
                          title: DefaultTextStyle(
                            style: textTheme.textStyle,
                            child: Text(source.name),
                          ),
                          subtitle: Text(
                            sourceLanguage(source.lang),
                            maxLines: 2,
                          ),
                          trailing: canOpenSource
                              ? const CupertinoListTileChevron()
                              : null,
                        ),
                      ),
                    ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              hasLeading: false,
              children: [
                Expansible(
                  key: const PageStorageKey('extension-details-diagnostics'),
                  controller: diagnostics,
                  animationStyle:
                      MediaQuery.reduceMotionOf(context) ||
                          MediaQuery.disableAnimationsOf(context)
                      ? AnimationStyle.noAnimation
                      : null,
                  headerBuilder: (context, animation) => Semantics(
                    container: true,
                    expanded: diagnostics.isExpanded,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => diagnostics.isExpanded
                          ? diagnostics.collapse()
                          : diagnostics.expand(),
                      child: CupertinoListTile(
                        title: const Text('诊断信息'),
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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableRegion(
                          selectionControls: cupertinoTextSelectionControls,
                          contextMenuBuilder: (context, state) =>
                              CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                                buttonItems: state.contextMenuButtonItems,
                                anchors: state.contextMenuAnchors,
                              ),
                          child: Text(
                            '包名：$packageName\n仓库：${item.reference.catalogUrl}\n身份：${item.reference.repoId}\n账户构建：${installed?.buildId ?? '未安装'}\n目录版本：${item.latest?.version ?? '不可用'}\n目录构建：${item.latest?.id ?? '不可用'}\n摘要：${installed?.bundleSha256 ?? '未下载'}',
                          ),
                        ),
                        if (controller.catalog.activeBuild?.packageName ==
                            packageName)
                          Text(
                            '当前运行：${controller.catalog.activeBuild!.id}',
                            key: const ValueKey('extensions-running'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class const ExtensionRepositoriesPage({
  super.key,
  required final ExtensionsController controller,
}) extends HookWidget {
  Future<({String url, String name})?> _promptRepository(
    BuildContext context,
    ({String url, String name}) draft,
    String? failure,
  ) => showAppSheet<({String url, String name})>(
    context: context,
    enableDrag: false,
    scrollableBuilder: (context, scrollController) => HookBuilder(
      builder: (context) {
        final address = useTextEditingController(text: draft.url);
        final name = useTextEditingController(text: draft.name);
        return EditSheet(
          title: const Text('预览额外仓库'),
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          trailing: CupertinoButton(
            key: const ValueKey('repository-preview-submit'),
            padding: EdgeInsets.zero,
            onPressed: () =>
                Navigator.pop(context, (url: address.text, name: name.text)),
            child: const Text(
              '只读预览',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          content: ListView(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              if (failure != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      failure,
                      style: TextStyle(
                        color: AppColors.error.resolveFrom(context),
                      ),
                    ),
                  ),
                ),
              CupertinoFormSection.insetGrouped(
                footer: const Text('仓库必须公开提供 HTTPS 静态目录及 CORS，应用凭据不会发送给仓库。'),
                children: [
                  CupertinoFormRow(
                    child: CupertinoTextField(
                      key: const ValueKey('repository-url'),
                      controller: address,
                      autofillHints: null,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      placeholder: 'HTTPS 仓库地址',
                    ),
                  ),
                  CupertinoFormRow(
                    child: CupertinoTextField(
                      key: const ValueKey('repository-name'),
                      controller: name,
                      autofillHints: null,
                      maxLength: 100,
                      placeholder: '名称（可选）',
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _addRepository(BuildContext context) async {
    var draft = (url: '', name: '');
    String? failure;
    RepositoryPreview? preview;
    do {
      final submitted = await _promptRepository(context, draft, failure);
      if (submitted == null || !context.mounted || !controller.canEdit) return;
      draft = submitted;
      preview = await controller.previewRepository(draft.url, draft.name);
      if (!context.mounted ||
          !controller.available ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      failure = controller.error;
      if (preview == null && failure == null) return;
    } while (preview == null);
    final candidate = preview;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('确认添加仓库'),
        content: SingleChildScrollView(
          child: Text(
            '${candidate.repository.name}\n${Uri.parse(candidate.repository.catalogUrl).host}\n${candidate.builds.length} 个扩展。添加仓库不会安装扩展。',
          ),
        ),
        actions: [
          CupertinoButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoButton(
            key: const ValueKey('repository-add-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '确认添加',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await controller.addRepository(candidate);
    }
  }

  Future<void> _removeRepository(
    BuildContext context,
    wire.ExtensionRepository repository,
  ) async {
    final affected = controller.installed
        .where(
          (item) =>
              item.catalogUrl == repository.catalogUrl &&
              item.repoId == repository.repoId,
        )
        .map(
          (item) => ExtensionListing(
            catalog: controller.catalog,
            installed: item,
          ).name,
        )
        .toList();
    final accepted = await showAppDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('移除仓库'),
        content: Text(
          '移除“${repository.name}”后，对应扩展暂时不可用；安装选择、书架和阅读记录保留。\n受影响扩展：${affected.isEmpty ? '无' : affected.join('、')}',
        ),
        actions: [
          CupertinoButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoButton(
            key: const ValueKey('repository-remove-confirm'),
            onPressed: () => Navigator.pop(context, true),
            foregroundColor: AppColors.error.resolveFrom(context),
            child: const Text('确认移除'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      await controller.removeRepository(repository);
    }
  }

  @override
  Widget build(BuildContext context) {
    useListenable(controller);
    final diagnostics = useMemoized(ExpansibleController.new);
    useEffect(() => diagnostics.dispose, [diagnostics]);
    final catalog = controller.catalog;
    final actionStyle = CupertinoTheme.of(context).textTheme.actionTextStyle;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: const Text('仓库管理')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ExtensionOperationStatus(controller: controller),
            ),
            CupertinoFormSection.insetGrouped(
              footer: const Text('仓库提供可安装的扩展目录；添加仓库不会自动安装扩展。'),
              children: [
                for (final repository in catalog.repositories)
                  CupertinoListTile(
                    title: Text(repository.name, maxLines: 2),
                    subtitle: Text(
                      '${Uri.parse(repository.catalogUrl).host} · ${catalog.repositoryErrors[catalogReferenceKey(wire.CatalogReference(catalogUrl: repository.catalogUrl, repoId: repository.repoId))] == null ? '可用' : '读取失败'}',
                      maxLines: 2,
                    ),
                    additionalInfo: repository.catalogUrl == catalog.catalogUrl
                        ? const Text('默认')
                        : null,
                    trailing: repository.catalogUrl == catalog.catalogUrl
                        ? null
                        : Semantics(
                            container: true,
                            child: CupertinoButton(
                              key: ValueKey((
                                'repository-remove',
                                repository.catalogUrl,
                              )),
                              onPressed: controller.canEdit
                                  ? () => unawaited(
                                      _removeRepository(context, repository),
                                    )
                                  : null,
                              padding: const EdgeInsets.all(8),
                              foregroundColor: AppColors.error.resolveFrom(
                                context,
                              ),
                              child: Icon(
                                CupertinoIcons.trash,
                                semanticLabel: '移除仓库：${repository.name}',
                              ),
                            ),
                          ),
                  ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              hasLeading: false,
              children: [
                CupertinoButton(
                  key: const ValueKey('repositories-add'),
                  onPressed:
                      controller.canEdit && catalog.repositories.length <= 16
                      ? () => unawaited(_addRepository(context))
                      : null,
                  padding: EdgeInsets.zero,
                  child: CupertinoListTile(
                    title: Text('添加仓库', style: actionStyle, maxLines: 2),
                  ),
                ),
                CupertinoButton(
                  onPressed: !controller.available || controller.busy
                      ? null
                      : () => unawaited(controller.refresh(catalogToo: true)),
                  padding: EdgeInsets.zero,
                  child: CupertinoListTile(
                    title: Text('重试读取仓库', style: actionStyle, maxLines: 2),
                  ),
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              hasLeading: false,
              children: [
                Expansible(
                  key: const PageStorageKey(
                    'extension-repositories-diagnostics',
                  ),
                  controller: diagnostics,
                  animationStyle:
                      MediaQuery.reduceMotionOf(context) ||
                          MediaQuery.disableAnimationsOf(context)
                      ? AnimationStyle.noAnimation
                      : null,
                  headerBuilder: (context, animation) => Semantics(
                    container: true,
                    expanded: diagnostics.isExpanded,
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => diagnostics.isExpanded
                          ? diagnostics.collapse()
                          : diagnostics.expand(),
                      child: CupertinoListTile(
                        title: const Text('诊断信息'),
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
                    padding: const EdgeInsets.all(16),
                    child: SelectableRegion(
                      selectionControls: cupertinoTextSelectionControls,
                      contextMenuBuilder: (context, state) =>
                          CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                            buttonItems: state.contextMenuButtonItems,
                            anchors: state.contextMenuAnchors,
                          ),
                      child: Text(
                        [
                          for (final repository in catalog.repositories)
                            '${repository.catalogUrl}\n${repository.repoId}\n${catalog.repositoryErrors[catalogReferenceKey(wire.CatalogReference(catalogUrl: repository.catalogUrl, repoId: repository.repoId))] ?? ''}',
                        ].join('\n\n'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class const ExtensionStoragePage({
  super.key,
  required final ExtensionsController controller,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    useListenable(controller);
    final scroll = useScrollController();
    final diagnostics = useMemoized(ExpansibleController.new);
    useEffect(() => diagnostics.dispose, [diagnostics]);
    final cleanupTarget = controller.cleanupTarget;
    useEffect(() {
      if (cleanupTarget != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && scroll.hasClients) {
            scroll.jumpTo(scroll.position.minScrollExtent);
          }
        });
      }
      return null;
    }, [cleanupTarget, controller.cleanupError]);
    final cache = controller.cache;
    final canRefresh = controller.available && !controller.busy;
    final canForget = canRefresh && !controller.catalog.busy;
    final checking =
        cache == null &&
        controller.available &&
        controller.activity == ExtensionActivity.reading &&
        controller.settings.pending?.acknowledged != true;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: const Text('本机存储')),
      child: SafeArea(
        child: CustomScrollView(
          controller: scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: ExtensionOperationStatus(
                  controller: controller,
                  showStorageAction: false,
                  showProgress: !checking,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 16),
              sliver: SliverList.list(
                children: [
                  CupertinoFormSection.insetGrouped(
                    footer: const Text('清理副本后仍是账户已安装状态，重新打开时会再次下载。书架与阅读记录保留。'),
                    children: [
                      CupertinoListTile(
                        title: Text(
                          checking
                              ? '正在检查本机副本'
                              : cache == null
                              ? '尚未读取本机副本'
                              : '扩展副本占用',
                        ),
                        subtitle: cache == null
                            ? null
                            : Text(
                                '${cache.artifacts.length} 个副本 · ${FileSize.fromBytes(cache.totalBytes)}',
                                key: const ValueKey('extensions-cache-usage'),
                              ),
                        trailing: checking
                            ? const CupertinoActivityIndicator()
                            : null,
                      ),
                      if (cache != null && cache.artifacts.isEmpty)
                        const CupertinoListTile(title: Text('本机没有扩展副本')),
                    ],
                  ),
                  if (cache != null) ...[
                    if (cache.artifacts.isNotEmpty)
                      CupertinoListSection.insetGrouped(
                        hasLeading: false,
                        children: [
                          for (final artifact in cache.artifacts)
                            CupertinoListTile(
                              title: DefaultTextStyle(
                                style: CupertinoTheme.of(context)
                                    .textTheme
                                    .textStyle,
                                child: Text(
                                  controller.artifactName(artifact.sha256),
                                ),
                              ),
                              subtitle: Text(
                                FileSize.fromBytes(artifact.byteLength)
                                    .toString(),
                              ),
                              trailing: Semantics(
                                container: true,
                                enabled: canForget,
                                child: CupertinoButton(
                                  key: ValueKey((
                                    'extension-forget',
                                    artifact.sha256,
                                  )),
                                  onPressed: canForget
                                      ? () => unawaited(
                                          controller.forget(artifact.sha256),
                                        )
                                      : null,
                                  child: Text(
                                    '清理副本',
                                    semanticsLabel:
                                        '清理副本：${controller.artifactName(artifact.sha256)}',
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    CupertinoListSection.insetGrouped(
                      hasLeading: false,
                      children: [
                        Expansible(
                          key: const PageStorageKey(
                            'extension-storage-diagnostics',
                          ),
                          controller: diagnostics,
                          animationStyle:
                              MediaQuery.reduceMotionOf(context) ||
                                  MediaQuery.disableAnimationsOf(context)
                              ? AnimationStyle.noAnimation
                              : null,
                          headerBuilder: (context, animation) => Semantics(
                            container: true,
                            expanded: diagnostics.isExpanded,
                            child: CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => diagnostics.isExpanded
                                  ? diagnostics.collapse()
                                  : diagnostics.expand(),
                              child: CupertinoListTile(
                                title: const Text('诊断信息'),
                                trailing: RotationTransition(
                                  turns: animation.drive(
                                    Tween(begin: 0.0, end: 0.25),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.chevron_right,
                                    size: 16,
                                    color: AppColors.accent.resolveFrom(
                                      context,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          bodyBuilder: (context, animation) => Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableRegion(
                              selectionControls: cupertinoTextSelectionControls,
                              contextMenuBuilder: (context, state) =>
                                  CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                                    buttonItems: state.contextMenuButtonItems,
                                    anchors: state.contextMenuAnchors,
                                  ),
                              child: Text(
                                [
                                  '${cache.artifacts.length} / ${cache.maxArtifacts} 个产物 · '
                                      '${FileSize.fromBytes(cache.totalBytes)} / '
                                      '${FileSize.fromBytes(cache.maxBytes)}',
                                  for (final artifact in cache.artifacts)
                                    '${controller.artifactName(artifact.sha256)} · ${artifact.sha256}',
                                ].join('\n'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  CupertinoListSection.insetGrouped(
                    hasLeading: false,
                    clipBehavior: Clip.none,
                    children: [
                      Semantics(
                        enabled: canRefresh,
                        child: SizedBox(
                          width: double.infinity,
                          child: CupertinoButton(
                            alignment: AlignmentDirectional.centerStart,
                            onPressed: canRefresh
                                ? () => unawaited(controller.refresh())
                                : null,
                            child: const Text('重新读取本机副本'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
