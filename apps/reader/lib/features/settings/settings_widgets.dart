import '../../widgets/choice_field.dart';
import '../../widgets/edit_sheet.dart';
import '../../theme/app_theme.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../state/account_providers.dart';
import '../browse/catalog_controller.dart';
import '../reader/reader_preferences.dart';
import 'settings_controller.dart';

ReadingMode readerMode(wire.ReaderMode mode) => switch (mode) {
  wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT => ReadingMode.leftToRight,
  wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT => ReadingMode.rightToLeft,
  wire.ReaderMode.READER_MODE_CONTINUOUS => ReadingMode.continuous,
  wire.ReaderMode.READER_MODE_WEBTOON => ReadingMode.webtoon,
  _ => throw const FormatException('Unsupported reader settings mode'),
};
wire.ReaderMode wireReaderMode(ReadingMode mode) => switch (mode) {
  ReadingMode.leftToRight => wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
  ReadingMode.rightToLeft => wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
  ReadingMode.continuous => wire.ReaderMode.READER_MODE_CONTINUOUS,
  ReadingMode.webtoon => wire.ReaderMode.READER_MODE_WEBTOON,
};
bool? doublePage(wire.ReaderPageLayout layout) => switch (layout) {
  wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO => null,
  wire.ReaderPageLayout.READER_PAGE_LAYOUT_SINGLE => false,
  wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE => true,
  _ => throw const FormatException('Unsupported reader page layout'),
};
wire.ReaderPageLayout wirePageLayout(bool? value) => value == null
    ? wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO
    : value
    ? wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE
    : wire.ReaderPageLayout.READER_PAGE_LAYOUT_SINGLE;
ReaderFit readerFit(wire.ReaderFit value) => switch (value) {
  wire.ReaderFit.READER_FIT_CONTAIN => ReaderFit.contain,
  wire.ReaderFit.READER_FIT_WIDTH => ReaderFit.width,
  wire.ReaderFit.READER_FIT_HEIGHT => ReaderFit.height,
  _ => throw const FormatException('Unsupported reader fit'),
};
ReaderBackground readerBackground(wire.ReaderBackground value) =>
    switch (value) {
      wire.ReaderBackground.READER_BACKGROUND_BLACK => ReaderBackground.black,
      wire.ReaderBackground.READER_BACKGROUND_WHITE => ReaderBackground.white,
      wire.ReaderBackground.READER_BACKGROUND_THEME => ReaderBackground.theme,
      _ => throw const FormatException('Unsupported reader background'),
    };
ReaderInputPreset readerInputPreset(wire.ReaderInputPreset value) =>
    switch (value) {
      wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD =>
        ReaderInputPreset.standard,
      wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED =>
        ReaderInputPreset.reversed,
      wire.ReaderInputPreset.READER_INPUT_PRESET_DISABLED =>
        ReaderInputPreset.disabled,
      _ => throw const FormatException('Unsupported reader input preset'),
    };
Brightness? appBrightness(wire.AppTheme theme) => switch (theme) {
  wire.AppTheme.APP_THEME_SYSTEM => null,
  wire.AppTheme.APP_THEME_LIGHT => Brightness.light,
  wire.AppTheme.APP_THEME_DARK => Brightness.dark,
  _ => throw const FormatException('Unsupported application theme'),
};

const _modes = <wire.ReaderMode, String>{
  wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT: '从左到右',
  wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT: '从右到左',
  wire.ReaderMode.READER_MODE_CONTINUOUS: '竖向连续',
  wire.ReaderMode.READER_MODE_WEBTOON: '条漫',
};
const _layouts = <wire.ReaderPageLayout, String>{
  wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO: '自动',
  wire.ReaderPageLayout.READER_PAGE_LAYOUT_SINGLE: '单页',
  wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE: '双页',
};

const _fits = <wire.ReaderFit, String>{
  wire.ReaderFit.READER_FIT_CONTAIN: '完整显示',
  wire.ReaderFit.READER_FIT_WIDTH: '适宽',
  wire.ReaderFit.READER_FIT_HEIGHT: '适高',
};

const _backgrounds = <wire.ReaderBackground, String>{
  wire.ReaderBackground.READER_BACKGROUND_BLACK: '黑色',
  wire.ReaderBackground.READER_BACKGROUND_WHITE: '白色',
  wire.ReaderBackground.READER_BACKGROUND_THEME: '跟随应用主题',
};
const _inputPresets = <wire.ReaderInputPreset, String>{
  wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD: '标准',
  wire.ReaderInputPreset.READER_INPUT_PRESET_REVERSED: '反向',
  wire.ReaderInputPreset.READER_INPUT_PRESET_DISABLED: '关闭',
};

class const SettingsStatus({
  super.key,
  required final SettingsController controller,
  required final SettingsState state,
  final VoidCallback? onReloaded,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (state.busy) const CupertinoActivityIndicator(),
      if (state.error case final error?) Text(error),
      if (state.pending?.retryable == true) const Text('设置尚未确认，本会话保留原操作。'),
      Wrap(
        children: [
          CupertinoButton(
            onPressed: state.canRefresh
                ? () async {
                    if (await controller.refresh()) onReloaded?.call();
                  }
                : null,
            child: const Text('重新读取设置'),
          ),
          if (state.pending?.retryable == true)
            CupertinoButton(
              onPressed: state.canRetry
                  ? () async {
                      if (await controller.retry()) onReloaded?.call();
                    }
                  : null,
              child: const Text('重试原设置操作'),
            ),
        ],
      ),
    ],
  );
}

class const GlobalSettingsPanel({super.key, required super.catalog})
    extends _SettingsEditor {}

class MangaSettingsEditor extends _SettingsEditor {
  const MangaSettingsEditor({
    super.key,
    required super.catalog,
    required String mangaKey,
  }) : super(mangaKey: mangaKey);
}

/// One UI-only draft implements the same controls for global values and manga
/// overrides. Presence is preserved: null inherits, including explicit AUTO/0.
final class _FormDraft {
  _FormDraft(SettingsState state, this.owner, bool manga)
    : global = manga
          ? null
          : (state.pending?.global ?? state.snapshot!.global).deepCopy(),
      reader = manga
          ? (state.pending?.overrides ?? state.snapshot!.overrides!).deepCopy()
          : wire.ReaderSettingsOverride(),
      revision =
          state.pending?.basedOnRevision ??
          (manga
              ? state.snapshot!.mangaRevision!
              : state.snapshot!.globalRevision),
      dirty = state.pending != null {
    if (global case final values?) {
      final r = values.reader;
      reader
        ..mode = r.mode
        ..pageLayout = r.pageLayout
        ..fit = r.fit
        ..cropBorders = r.cropBorders
        ..background = r.background
        ..dimPercent = r.dimPercent
        ..tapZones = r.tapZones
        ..keyboard = r.keyboard;
    }
  }
  final Object owner;
  final wire.GlobalSettingsValues? global;
  final wire.ReaderSettingsOverride reader;
  final int revision;
  bool dirty;

  wire.GlobalSettingsValues globalValues() =>
      global!.deepCopy()
        ..reader = wire.ReaderSettings(
          mode: reader.mode,
          pageLayout: reader.pageLayout,
          fit: reader.fit,
          cropBorders: reader.cropBorders,
          background: reader.background,
          dimPercent: reader.dimPercent,
          tapZones: reader.tapZones,
          keyboard: reader.keyboard,
        );
}

class const _SettingsEditor({
  super.key,
  required final CatalogController catalog,
  final String? mangaKey,
}) extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = settingsControllerProvider(
      catalog,
      catalog.settings,
      mangaKey: mangaKey,
    );
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final owner = ref.watch(confirmedAccountProvider(catalog))?.settings;
    final edit = useRef<_FormDraft?>(null);
    final revision = useState(0);
    final manga = mangaKey != null;
    final scope = manga ? 'manga' : 'global';
    final confirmedRevision = manga
        ? state.snapshot?.mangaRevision
        : state.snapshot?.globalRevision;
    if (owner == null) {
      edit.value = null;
    } else if (state.snapshot != null &&
        (edit.value?.owner != owner ||
            (!edit.value!.dirty &&
                edit.value!.revision != confirmedRevision))) {
      edit.value = _FormDraft(state, owner, manga);
    }
    void reset() {
      if (!context.mounted) return;
      edit.value = null;
      revision.value++;
    }

    void change(VoidCallback apply) {
      apply();
      edit.value!.dirty = true;
      revision.value++;
    }

    Widget choice<T>(
      String id,
      String label,
      T? value,
      Map<T, String> values,
      void Function(T) set,
      VoidCallback clear, {
      bool inherit = true,
    }) => Padding(
      padding: EdgeInsets.zero,
      child: ChoiceField<T>(
        inline: false,
        key: ValueKey('$scope-$id'),
        label: label,
        value: value,
        options: {
          if (manga && inherit) null: '跟随全局',
          for (final item in values.entries) item.key: item.value,
        },
        onChanged: state.canEdit
            ? (value) => change(() {
                if (value == null) {
                  clear();
                } else {
                  set(value);
                }
              })
            : null,
      ),
    );
    final draft = edit.value;
    final r = draft?.reader;
    final dim = r?.hasDimPercent() == true ? r!.dimPercent : null;
    final inheritedDim = state.snapshot?.global.reader.dimPercent ?? 0;
    Widget group(String id, String title, List<Widget> fields) {
      final section = CupertinoListSection.insetGrouped(
        backgroundColor: AppColors.background.resolveFrom(context),
        separatorColor: AppColors.separator.resolveFrom(context),
        decoration: BoxDecoration(
          color: AppColors.groupedSurface.resolveFrom(context),
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
        header: manga ? Text(title) : null,
        hasLeading: false,
        children: fields,
      );
      return manga
          ? section
          : HookBuilder(
              key: ValueKey('settings-group-$id'),
              builder: (context) {
                final expansion = useMemoized(ExpansibleController.new);
                useEffect(() => expansion.dispose, [expansion]);
                return Expansible(
                  controller: expansion,
                  animationStyle:
                      MediaQuery.reduceMotionOf(context) ||
                          MediaQuery.disableAnimationsOf(context)
                      ? AnimationStyle.noAnimation
                      : null,
                  headerBuilder: (context, animation) => Semantics(
                    expanded: expansion.isExpanded,
                    child: CupertinoListTile(
                      title: Text(title),
                      onTap: () => expansion.isExpanded
                          ? expansion.collapse()
                          : expansion.expand(),
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
                  bodyBuilder: (context, animation) => section,
                );
              },
            );
    }

    final save = draft == null || r == null
        ? null
        : CupertinoButton.filled(
            onPressed: state.canEdit
                ? () async {
                    final saved = manga
                        ? await controller.saveOverrides(
                            r.deepCopy(),
                            draft.revision,
                          )
                        : await controller.saveGlobal(
                            draft.globalValues(),
                            draft.revision,
                          );
                    if (saved) reset();
                  }
                : null,
            child: Text(manga ? '保存本漫画设置' : '保存全局设置'),
          );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!manga)
          Text(
            '全局设置',
            style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
          ),
        Text(manga ? '选择“跟随全局”时，之后的全局修改会应用到此漫画。' : '漫画可以单独覆盖各项阅读偏好；服务端确认后才保存。'),
        const SizedBox(height: 16),
        if (draft != null && r != null) ...[
          if (draft.global case final global?)
            group('appearance', '外观与主题', [
              choice(
                'theme',
                '外观',
                global.theme,
                const {
                  wire.AppTheme.APP_THEME_SYSTEM: '跟随系统',
                  wire.AppTheme.APP_THEME_LIGHT: '浅色',
                  wire.AppTheme.APP_THEME_DARK: '深色',
                },
                (value) => global.theme = value,
                () {},
                inherit: false,
              ),
            ]),
          group('reading', '阅读显示', [
            choice(
              'mode',
              '阅读模式',
              r.hasMode() ? r.mode : null,
              _modes,
              (value) => r.mode = value,
              r.clearMode,
            ),
            choice(
              'layout',
              '页组',
              r.hasPageLayout() ? r.pageLayout : null,
              _layouts,
              (value) => r.pageLayout = value,
              r.clearPageLayout,
            ),
            choice(
              'fit',
              '图像适配',
              r.hasFit() ? r.fit : null,
              _fits,
              (value) => r.fit = value,
              r.clearFit,
            ),
            choice(
              'crop-borders',
              '裁白',
              r.hasCropBorders() ? r.cropBorders : null,
              const {false: '关闭', true: '开启'},
              (value) => r.cropBorders = value,
              r.clearCropBorders,
            ),
            choice(
              'background',
              '阅读背景',
              r.hasBackground() ? r.background : null,
              _backgrounds,
              (value) => r.background = value,
              r.clearBackground,
            ),
            if (manga)
              MergeSemantics(
                child: CupertinoFormRow(
                  prefix: Expanded(flex: 3, child: const Text('调暗跟随全局')),
                  padding: EdgeInsets.zero,
                  child: CupertinoSwitch(
                    key: ValueKey('$scope-dim-inherit'),
                    thumbColor: AppColors.onAccent.resolveFrom(context),
                    inactiveThumbColor: CupertinoColors.white,
                    onLabelColor: AppColors.onAccent.resolveFrom(context),
                    value: dim == null,
                    onChanged: state.canEdit
                        ? (inherit) => change(() {
                            if (inherit) {
                              r.clearDimPercent();
                            } else {
                              r.dimPercent = inheritedDim;
                            }
                          })
                        : null,
                  ),
                ),
              ),
            Text(dim == null ? '应用内调暗：跟随全局（$inheritedDim%）' : '应用内调暗：$dim%'),
            CupertinoSlider(
              key: ValueKey('$scope-dim'),
              value: (dim ?? inheritedDim).toDouble(),
              min: 0,
              max: 80,
              divisions: 80,
              onChanged: state.canEdit && dim != null
                  ? (value) => change(() => r.dimPercent = value.round())
                  : null,
            ),
            const Text('仅调暗阅读内容，不改变系统亮度。'),
          ]),
          group('input', '翻页与快捷键', [
            choice(
              'tap-zones',
              '分页点击区',
              r.hasTapZones() ? r.tapZones : null,
              _inputPresets,
              (value) => r.tapZones = value,
              r.clearTapZones,
            ),
            const Text('反向会交换左右翻页；关闭后仍可从中央显示工具栏，滑动翻页不变。'),
            const SizedBox(height: 16),
            choice(
              'keyboard',
              '阅读快捷键',
              r.hasKeyboard() ? r.keyboard : null,
              _inputPresets,
              (value) => r.keyboard = value,
              r.clearKeyboard,
            ),
            const Text('反向会交换方向键、上下翻页键和空格的翻页方向；Home/End 仍到首末页。'),
          ]),
        ],
        if (draft?.dirty == true && state.pending == null)
          const Text('修改尚未保存。')
        else if (state.snapshot != null &&
            !state.busy &&
            state.error == null &&
            state.pending == null)
          const Text('当前设置已获服务端确认。'),
        if (!manga && save != null) save,
        SettingsStatus(controller: controller, state: state, onReloaded: reset),
      ],
    );
    return manga
        ? PopScope(
            canPop: !state.busy,
            child: EditSheet(
              title: const Text('本漫画阅读设置'),
              content: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: content,
              ),
              actions: [
                CupertinoButton(
                  onPressed: state.busy ? null : () => Navigator.pop(context),
                  child: const Text('关闭设置'),
                ),
                ?save,
              ],
            ),
          )
        : content;
  }
}
