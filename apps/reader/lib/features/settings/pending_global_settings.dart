import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

class const PendingGlobalSettings({
  super.key,
  required final wire.GlobalSettingsValues values,
  required final int revision,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final reader = values.reader;
    return CupertinoListSection(
      key: const ValueKey('favorite-source-pending-global'),
      header: const Text('未确认的原全局设置内容'),
      footer: Text('原操作基于版本 $revision；重试会保留全部原内容。'),
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
