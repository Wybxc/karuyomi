import '../../widgets/choice_field.dart';
import '../../widgets/edit_sheet.dart';
import '../../widgets/app_page_route.dart';
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
      if (state.activity case final activity?)
        Row(
          children: [
            const CupertinoActivityIndicator(),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                switch (activity) {
                  SettingsActivity.reading => '正在读取服务端设置',
                  SettingsActivity.saving => '正在等待服务端确认设置修改',
                },
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
          ],
        ),
      if (state.error case final error?)
        Text(
          error,
          style: TextStyle(color: AppColors.error.resolveFrom(context)),
        ),
      if (state.pending?.retryable == true)
        Text(
          '设置尚未确认，本会话保留原操作。',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.secondaryLabel.resolveFrom(context),
          ),
        ),
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

class const GlobalSettingsPanel({
  super.key,
  required super.catalog,
  super.connection,
}) extends _SettingsEditor {}

enum _SettingsSection {
  appearance('appearance', '外观与主题', '跟随系统、浅色与深色', CupertinoIcons.paintbrush),
  reading('reading', '阅读显示', '阅读模式、图像与背景', CupertinoIcons.book),
  input('input', '翻页与快捷键', '点击区与键盘操作', CupertinoIcons.keyboard),
  connection('connection', '服务连接', '服务地址与登录', CupertinoIcons.cloud),
  about('about', '关于', 'Karuyomi', CupertinoIcons.info);

  const _SettingsSection(this.id, this.title, this.subtitle, this.icon);
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}

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
  final Widget? connection,
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
    final selected = useState<_SettingsSection?>(null);
    final detailScroll = useScrollController();
    final navigator = useMemoized(GlobalKey<NavigatorState>.new);
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
      if (!manga) selected.value ??= _SettingsSection.appearance;
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
    Widget group(String title, List<Widget> fields, {String? footer}) =>
        CupertinoFormSection.insetGrouped(
          margin: const EdgeInsets.symmetric(vertical: 8),
          header: manga ? Text(title) : null,
          footer: footer == null ? null : Text(footer),
          children: fields,
        );

    final save = draft == null || r == null
        ? null
        : CupertinoButton(
            padding: manga ? EdgeInsets.zero : null,
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
            child: Text(
              manga ? '保存' : '保存全局设置',
              semanticsLabel: manga ? '保存本漫画设置' : null,
            ),
          );
    Widget feedback() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (draft?.dirty == true &&
            state.pending == null &&
            state.activity != SettingsActivity.saving)
          const Text('修改尚未保存。')
        else if (state.snapshot != null &&
            !state.busy &&
            state.error == null &&
            state.pending == null)
          const Text('当前设置已获服务端确认。'),
        if (!manga && save != null)
          CupertinoButton.filled(onPressed: save.onPressed, child: save.child),
        SettingsStatus(controller: controller, state: state, onReloaded: reset),
      ],
    );
    Widget content(_SettingsSection? section) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (connection != null &&
            section != _SettingsSection.connection &&
            catalog.status != ServiceStatus.ready) ...[
          if (catalog.error case final error?)
            Text(
              error,
              style: TextStyle(color: AppColors.error.resolveFrom(context)),
            ),
          CupertinoButton(
            onPressed: () => selected.value = _SettingsSection.connection,
            child: const Text('服务连接与登录'),
          ),
        ],
        if (section == _SettingsSection.connection) ?connection,
        if (section == _SettingsSection.about)
          const CupertinoListTile(
            title: Text('Karuyomi'),
            subtitle: Text('轻松翻开下一页'),
            trailing: Text('0.1.0'),
          ),
        if (draft == null &&
            !state.available &&
            section != _SettingsSection.about &&
            section != _SettingsSection.connection)
          const Text('连接并确认身份后可读取和保存同步设置。'),
        if (draft != null && r != null) ...[
          if (draft.global case final global?
              when section == _SettingsSection.appearance)
            group('外观与主题', [
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
          if (manga || section == _SettingsSection.reading) ...[
            group('阅读显示', [
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
            ], footer: manga ? '选择“跟随全局”时，之后的全局修改会应用到此漫画。' : null),
            group('应用内调暗', [
              if (manga)
                MergeSemantics(
                  child: CupertinoFormRow(
                    prefix: Expanded(flex: 3, child: const Text('调暗跟随全局')),
                    child: CupertinoSwitch(
                      key: ValueKey('$scope-dim-inherit'),
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
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      dim == null
                          ? '应用内调暗：跟随全局（$inheritedDim%）'
                          : '应用内调暗：$dim%',
                    ),
                    CupertinoSlider(
                      key: ValueKey('$scope-dim'),
                      value: (dim ?? inheritedDim).toDouble(),
                      min: 0,
                      max: 80,
                      divisions: 80,
                      onChanged: state.canEdit && dim != null
                          ? (value) =>
                                change(() => r.dimPercent = value.round())
                          : null,
                    ),
                  ],
                ),
              ),
            ], footer: '仅调暗阅读内容，不改变系统亮度。'),
          ],
          if (manga || section == _SettingsSection.input) ...[
            group('分页点击区', [
              choice(
                'tap-zones',
                '分页点击区',
                r.hasTapZones() ? r.tapZones : null,
                _inputPresets,
                (value) => r.tapZones = value,
                r.clearTapZones,
              ),
            ], footer: '反向会交换左右翻页；关闭后仍可从中央显示工具栏，滑动翻页不变。'),
            group('阅读快捷键', [
              choice(
                'keyboard',
                '阅读快捷键',
                r.hasKeyboard() ? r.keyboard : null,
                _inputPresets,
                (value) => r.keyboard = value,
                r.clearKeyboard,
              ),
            ], footer: '反向会交换方向键、上下翻页键和空格的翻页方向；Home/End 仍到首末页。'),
          ],
        ],
        if (!manga &&
            ({
                  _SettingsSection.appearance,
                  _SettingsSection.reading,
                  _SettingsSection.input,
                }.contains(section) ||
                draft?.dirty == true ||
                state.pending != null ||
                state.error != null))
          feedback(),
      ],
    );
    return manga
        ? PopScope(
            canPop: state.activity != SettingsActivity.saving,
            child: EditSheet(
              title: const Text('本漫画阅读设置'),
              leading: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: state.activity == SettingsActivity.saving
                    ? null
                    : () => Navigator.pop(context),
                child: const Text('关闭', semanticsLabel: '关闭设置'),
              ),
              trailing: save,
              content: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: feedback(),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: detailScroll,
                      padding: const EdgeInsets.all(24),
                      child: content(null),
                    ),
                  ),
                ],
              ),
            ),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final wide =
                  constraints.maxWidth >= 600 &&
                  MediaQuery.sizeOf(context).shortestSide >= 600;
              final section = selected.value ?? _SettingsSection.appearance;
              final showDetail = wide || selected.value != null;
              void select(_SettingsSection value) {
                FocusScope.of(context).unfocus();
                selected.value = value;
                if (detailScroll.hasClients) detailScroll.jumpTo(0);
              }

              final directory = CupertinoPageScaffold(
                navigationBar: const CupertinoNavigationBar(middle: Text('设置')),
                child: SafeArea(
                  child: ListView(
                    primary: false,
                    children: [
                      if (owner == null && !showDetail)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('连接并确认身份后可读取和保存同步设置。'),
                        ),
                      CupertinoListSection.insetGrouped(
                        children: [
                          for (final item in _SettingsSection.values)
                            if (item != _SettingsSection.connection ||
                                connection != null)
                              Semantics(
                                container: true,
                                selected: wide ? section == item : null,
                                child: CupertinoButton(
                                  key: ValueKey((
                                    'settings-navigation',
                                    item.id,
                                  )),
                                  padding: EdgeInsets.zero,
                                  onPressed: () => select(item),
                                  child: CupertinoListTile(
                                    key: ValueKey(
                                      'settings-section-${item.id}',
                                    ),
                                    backgroundColor: wide && section == item
                                        ? AppColors.selection.resolveFrom(
                                            context,
                                          )
                                        : null,
                                    leading: Icon(
                                      item.icon,
                                      size: 24,
                                      color: AppColors.accent.resolveFrom(
                                        context,
                                      ),
                                    ),
                                    title: Text(
                                      item.title,
                                      maxLines: 2,
                                      softWrap: true,
                                    ),
                                    subtitle: Text(
                                      item.subtitle,
                                      maxLines: 3,
                                      softWrap: true,
                                    ),
                                    trailing: wide
                                        ? null
                                        : const CupertinoListTileChevron(),
                                  ),
                                ),
                              ),
                        ],
                      ),
                      if (!showDetail && draft?.dirty == true)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('修改尚未保存。'),
                        ),
                      if (!showDetail &&
                          (state.pending != null || state.error != null))
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SettingsStatus(
                            controller: controller,
                            state: state,
                            onReloaded: reset,
                          ),
                        ),
                    ],
                  ),
                ),
              );
              final detail = CupertinoPageScaffold(
                navigationBar: CupertinoNavigationBar(
                  automaticallyImplyLeading: !wide,
                  middle: Text(section.title),
                ),
                child: SafeArea(
                  child: SingleChildScrollView(
                    key: ValueKey(('settings-content', section)),
                    controller: detailScroll,
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: content(section),
                      ),
                    ),
                  ),
                ),
              );
              return Row(
                children: [
                  if (wide)
                    SizedBox(
                      key: const ValueKey('settings-directory'),
                      width: (constraints.maxWidth / 2).clamp(240, 384),
                      child: directory,
                    ),
                  Expanded(
                    key: const ValueKey('settings-detail'),
                    child: Semantics(
                      container: true,
                      child: NavigatorPopHandler<void>(
                        enabled: !wide,
                        onPopWithResult: (_) => navigator.currentState!.pop(),
                        child: Navigator(
                          key: navigator,
                          pages: [
                            if (!wide)
                              AppPage<void>(
                                key: const ValueKey('settings-directory-page'),
                                title: '设置',
                                child: directory,
                              ),
                            if (showDetail)
                              AppPage<void>(
                                key: const ValueKey('settings-detail-page'),
                                title: section.title,
                                child: detail,
                              ),
                          ],
                          onDidRemovePage: (page) {
                            if (page.key ==
                                const ValueKey('settings-detail-page')) {
                              selected.value = null;
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
  }
}
