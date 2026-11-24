import '../../theme/app_theme.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'settings_widgets.dart' show readerModeOptions;

class const PendingGlobalSettings({
  super.key,
  required final wire.GlobalSettingsValues values,
  required final int revision,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final reader = values.reader;
    return CupertinoListSection(
      backgroundColor: AppColors.background.resolveFrom(context),
      separatorColor: AppColors.separator.resolveFrom(context),
      decoration: BoxDecoration(
        color: AppColors.groupedSurface.resolveFrom(context),
      ),
      key: const ValueKey('favorite-source-pending-global'),
      header: const Text('原全局设置内容'),
      footer: Text('原操作基于版本 $revision；重试会保留全部原内容。'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            [
              '阅读模式：${readerModeOptions[reader.mode]}',
              '分页布局：${switch (reader.pageLayout) {
                wire.ReaderPageLayout.READER_PAGE_LAYOUT_SINGLE => '单页',
                wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE => '双页',
                _ => '自动',
              }}；图像适配：${switch (reader.fit) {
                wire.ReaderFit.READER_FIT_WIDTH => '适宽',
                wire.ReaderFit.READER_FIT_HEIGHT => '适高',
                _ => '完整显示',
              }}；裁白：${reader.cropBorders ? '开启' : '关闭'}',
              if (values.favoriteSources.isEmpty) '收藏源：空列表',
              for (final source in values.favoriteSources)
                '收藏源：${source.sourceName} · ${source.sourceLang} · ${source.packageName} · ${source.sourceId}',
              if (values.installedExtensions.isEmpty) '扩展安装选择：空列表',
              for (final extension in values.installedExtensions)
                '扩展安装选择：${extension.packageName}（${extension.enabled ? '启用' : '停用'}）\n仓库：${extension.repoId} · ${extension.catalogUrl}\n构建：${extension.buildId}\n产物标识：${extension.bundleSha256}',
              if (values.repositories.isEmpty) '额外仓库：空列表',
              for (final repository in values.repositories)
                '额外仓库：${repository.name}\n${repository.repoId} · ${repository.catalogUrl}',
            ].join('\n'),
          ),
        ),
      ],
    );
  }
}
