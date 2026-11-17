import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../theme/app_theme.dart';

class const PendingExtensionChanges({
  super.key,
  required final wire.GlobalSettingsValues? previous,
  required final wire.GlobalSettingsValues submitted,
  final String Function(wire.InstalledExtension)? extensionLabel,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final before = previous;
    if (before == null) return const SizedBox.shrink();
    final changes = <({String title, String detail})>[];
    String name(wire.InstalledExtension value) =>
        extensionLabel?.call(value) ?? value.packageName.split('.').last;
    String identity(wire.InstalledExtension value) =>
        '${value.packageName}\n${value.repoId} · ${value.catalogUrl}';
    bool sameRepository(
      wire.ExtensionRepository a,
      wire.ExtensionRepository b,
    ) => a.catalogUrl == b.catalogUrl && a.repoId == b.repoId;
    for (final old in before.installedExtensions) {
      if (!submitted.installedExtensions.any(
        (value) => value.packageName == old.packageName,
      )) {
        changes.add((title: '卸载扩展：${name(old)}', detail: identity(old)));
      }
    }
    for (final value in submitted.installedExtensions) {
      final old = before.installedExtensions
          .where((item) => item.packageName == value.packageName)
          .firstOrNull;
      if (old == null) {
        changes.add((title: '安装扩展：${name(value)}', detail: identity(value)));
        continue;
      }
      if (old.catalogUrl != value.catalogUrl || old.repoId != value.repoId) {
        changes.add((
          title: '更换扩展仓库：${name(value)}',
          detail:
              '${value.packageName}\n${old.repoId} · ${old.catalogUrl}\n→ ${value.repoId} · ${value.catalogUrl}',
        ));
      } else if (old.buildId != value.buildId ||
          old.bundleSha256 != value.bundleSha256) {
        changes.add((
          title: '更新扩展：${name(value)}',
          detail:
              '${identity(value)}\n原构建：${old.buildId}\n新构建：${value.buildId}',
        ));
      }
      if (old.enabled != value.enabled) {
        changes.add((
          title: '${value.enabled ? '启用' : '停用'}扩展：${name(value)}',
          detail: identity(value),
        ));
      }
    }
    for (final old in before.repositories) {
      if (!submitted.repositories.any((value) => sameRepository(old, value))) {
        changes.add((
          title: '移除仓库：${old.name}',
          detail: '${old.repoId} · ${old.catalogUrl}',
        ));
      }
    }
    for (final value in submitted.repositories) {
      final old = before.repositories
          .where((item) => sameRepository(item, value))
          .firstOrNull;
      if (old == null) {
        changes.add((
          title: '添加仓库：${value.name}',
          detail: '${value.repoId} · ${value.catalogUrl}',
        ));
      } else if (old.name != value.name) {
        changes.add((
          title: '重命名仓库：${old.name} → ${value.name}',
          detail: '${value.repoId} · ${value.catalogUrl}',
        ));
      }
    }
    if (changes.isEmpty) return const SizedBox.shrink();
    return CupertinoListSection.insetGrouped(
      margin: EdgeInsets.zero,
      header: const Text('保留的原操作'),
      children: [
        for (final change in changes)
          CupertinoListTile(
            title: DefaultTextStyle(
              style: CupertinoTheme.of(context).textTheme.textStyle,
              child: Text(change.title),
            ),
            subtitle: DefaultTextStyle(
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                fontSize: 13,
                color: AppColors.secondaryLabel.resolveFrom(context),
              ),
              child: Text(change.detail),
            ),
          ),
      ],
    );
  }
}
