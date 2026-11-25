import '../../widgets/choice_field.dart';
import '../../widgets/edit_sheet.dart';
import '../../widgets/app_routes.dart';
import '../../widgets/adaptive_layout.dart';
import '../../theme/app_theme.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../navigation/app_location.dart';

import '../../state/account_providers.dart';
import '../browse/catalog_controller.dart';
import '../reader/reader_mode_fields.dart';
import '../reader/reader_preferences.dart';
import 'reader_device_controls.dart';
import 'settings_controller.dart';

ReadingMode readerMode(wire.ReaderMode mode) => switch (mode) {
  wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT => ReadingMode.leftToRight,
  wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT => ReadingMode.rightToLeft,
  wire.ReaderMode.READER_MODE_CONTINUOUS => ReadingMode.continuous,
  wire.ReaderMode.READER_MODE_WEBTOON => ReadingMode.webtoon,
  wire.ReaderMode.READER_MODE_HORIZONTAL_CONTINUOUS_LEFT_TO_RIGHT =>
    ReadingMode.horizontalContinuousLeftToRight,
  wire.ReaderMode.READER_MODE_HORIZONTAL_CONTINUOUS_RIGHT_TO_LEFT =>
    ReadingMode.horizontalContinuousRightToLeft,
  _ => throw const FormatException('Unsupported reader settings mode'),
};
wire.ReaderMode wireReaderMode(ReadingMode mode) => switch (mode) {
  ReadingMode.leftToRight => wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
  ReadingMode.rightToLeft => wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
  ReadingMode.continuous => wire.ReaderMode.READER_MODE_CONTINUOUS,
  ReadingMode.webtoon => wire.ReaderMode.READER_MODE_WEBTOON,
  ReadingMode.horizontalContinuousLeftToRight =>
    wire.ReaderMode.READER_MODE_HORIZONTAL_CONTINUOUS_LEFT_TO_RIGHT,
  ReadingMode.horizontalContinuousRightToLeft =>
    wire.ReaderMode.READER_MODE_HORIZONTAL_CONTINUOUS_RIGHT_TO_LEFT,
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
final readerModeOptions = <wire.ReaderMode, String>{
  for (final entry in readingModeLabels.entries)
    wireReaderMode(entry.key): entry.value,
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

class const SettingsStatus({
  super.key,
  required final SettingsController controller,
  required final SettingsState state,
  final bool compact = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final unknown =
        state.failure == SettingsFailure.unknown &&
        state.pending?.retryable == true;
    final offersReload =
        state.pending?.acknowledged != true || state.pending?.retryable != true;
    final offersRetry =
        state.activity != SettingsActivity.saving &&
        state.pending?.retryable == true;
    final reload = offersReload && (!compact || state.canRefresh)
        ? Semantics(
            enabled: state.canRefresh,
            child: CupertinoButton(
              onPressed: state.canRefresh ? controller.refresh : null,
              child: const Text('重新读取设置'),
            ),
          )
        : null;
    final retry = offersRetry && (!compact || state.canRetry)
        ? Semantics(
            enabled: state.canRetry,
            child: CupertinoButton(
              onPressed: state.canRetry ? controller.retry : null,
              child: Text(
                state.pending?.acknowledged == true ? '重试读取最新设置' : '重试原设置操作',
              ),
            ),
          )
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.activity case final activity?)
          Semantics(
            key: ValueKey(('settings-activity', activity.name)),
            container: true,
            liveRegion: true,
            label: switch (activity) {
              SettingsActivity.reading => '正在读取设置',
              SettingsActivity.saving => '正在保存设置',
            },
            child: const CupertinoActivityIndicator(),
          ),
        if (state.error case final error? when !(compact && unknown))
          Semantics(
            liveRegion: compact,
            child: Text(
              error,
              style: TextStyle(
                fontSize: compact ? 13 : null,
                color: AppColors.error.resolveFrom(context),
              ),
            ),
          ),
        if (state.activity != SettingsActivity.saving &&
            (!compact || (!state.busy && (unknown || state.error == null))) &&
            state.pending?.retryable == true)
          Semantics(
            liveRegion: compact && unknown,
            child: Text(
              state.pending?.acknowledged == true
                  ? '原设置已确认，本会话保留原操作等待读取。'
                  : '设置尚未确认，本会话保留原操作。',
              style: TextStyle(
                fontSize: 13,
                color:
                    (compact && unknown
                            ? AppColors.error
                            : AppColors.secondaryLabel)
                        .resolveFrom(context),
              ),
            ),
          ),
        Wrap(children: compact ? [?retry, ?reload] : [?reload, ?retry]),
      ],
    );
  }
}

class const GlobalSettingsPanel({
  super.key,
  required super.catalog,
  super.connection,
  super.appearance,
  super.openConnectionOnMount,
  super.addressedSection,
  super.onSectionChanged,
}) extends _SettingsEditor {}

class const DeviceAppearanceSettings({
  super.key,
  required final AppAppearance value,
  required final ValueChanged<AppAppearance> onChanged,
  final bool restoring = false,
  final bool saving = false,
  final AppAppearance? failed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CupertinoFormSection.insetGrouped(
    margin: const EdgeInsets.symmetric(vertical: 8),
    header: const Text('本机设置'),
    children: [
      ChoiceField<AppAppearance>(
        key: const ValueKey('device-theme'),
        inline: false,
        label: '外观',
        value: value,
        options: const {
          AppAppearance.system: '跟随系统',
          AppAppearance.light: '浅色',
          AppAppearance.dark: '深色',
        },
        onChanged: restoring || saving
            ? null
            : (selection) {
                if (selection != null) onChanged(selection);
              },
      ),
      if (restoring || saving)
        Semantics(
          liveRegion: true,
          child: Text(restoring ? '正在读取本机外观' : '正在保存本机外观'),
        ),
      if (failed case final selection?) ...[
        Semantics(
          liveRegion: true,
          child: Text(
            '未能保存本机外观。',
            style: TextStyle(color: AppColors.error.resolveFrom(context)),
          ),
        ),
        CupertinoButton(
          onPressed: () => onChanged(selection),
          child: const Text('重试保存外观'),
        ),
      ],
    ],
  );
}

enum _ReadingModeSource { account, manga }

class MangaSettingsEditor extends _SettingsEditor {
  const MangaSettingsEditor({
    super.key,
    required CatalogController catalog,
    required String mangaKey,
    required MangaEditContext target,
  }) : super(catalog: catalog, mangaKey: mangaKey, mangaContext: target);

  @override
  CatalogController get catalog => super.catalog!;
}

/// The same controls edit global values and manga
/// overrides. Presence is preserved: null inherits, including explicit AUTO/0.
final class _FormDraft {
  _FormDraft(SettingsState state, bool manga)
    : global = manga
          ? null
          : (state.unsent?.setGlobal ??
                    state.submitting?.setGlobal ??
                    state.pending?.global ??
                    state.snapshot!.global)
                .deepCopy(),
      reader = manga
          ? (state.unsent?.setManga.overrides ??
                    state.submitting?.setManga.overrides ??
                    state.pending?.overrides ??
                    state.snapshot!.overrides!)
                .deepCopy()
          : wire.ReaderSettingsOverride() {
    if (global case final values?) {
      final r = values.reader;
      reader
        ..mode = r.mode
        ..pageLayout = r.pageLayout
        ..fit = r.fit
        ..cropBorders = r.cropBorders;
    }
  }
  final wire.GlobalSettingsValues? global;
  final wire.ReaderSettingsOverride reader;

  wire.GlobalSettingsValues globalValues() =>
      global!.deepCopy()
        ..reader = wire.ReaderSettings(
          mode: reader.mode,
          pageLayout: reader.pageLayout,
          fit: reader.fit,
          cropBorders: reader.cropBorders,
        );
}

class const _SettingsEditor({
  super.key,
  required final CatalogController? catalog,
  final String? mangaKey,
  final MangaEditContext? mangaContext,
  final Widget? connection,
  final Widget? appearance,
  final bool openConnectionOnMount = false,
  final SettingsSection? addressedSection,
  final ValueChanged<SettingsSection?>? onSectionChanged,
}) extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = catalog;
    final provider = service == null
        ? null
        : settingsControllerProvider(
            service,
            service.settings,
            mangaKey: mangaKey,
          );
    final state = provider == null
        ? const SettingsState()
        : ref.watch(provider);
    final controller = provider == null ? null : ref.read(provider.notifier);
    final owner = service == null
        ? null
        : ref.watch(confirmedAccountProvider(service))?.settings;
    final selected = useState<SettingsSection?>(
      openConnectionOnMount || service == null
          ? SettingsSection.connection
          : null,
    );
    final currentSection = onSectionChanged == null
        ? selected.value
        : addressedSection;
    void changeSection(SettingsSection? section) {
      final navigate = onSectionChanged;
      if (navigate == null) {
        selected.value = section;
      } else {
        navigate(section);
      }
    }

    final detailScroll = useScrollController();
    final navigator = useMemoized(GlobalKey<NavigatorState>.new);
    final wasWide = useRef<bool?>(null);
    final directoryFocus = useFocusScopeNode();
    final detailFocus = useFocusScopeNode();
    final manga = mangaKey != null;
    final scope = manga ? 'manga' : 'global';

    void change(void Function(wire.ReaderSettingsOverride) apply) {
      if (provider == null || controller == null || !context.mounted) return;
      final latest = ref.read(provider);
      if (!latest.canChange || latest.snapshot == null) return;
      final edit = _FormDraft(latest, manga);
      final before = edit.reader.deepCopy();
      apply(edit.reader);
      if (edit.reader == before) return;
      if (manga) {
        controller.queueOverrides(edit.reader);
      } else {
        controller.queueGlobal(edit.globalValues());
      }
    }

    Widget choice<T>(
      String id,
      String label,
      T? value,
      Map<T, String> values,
      void Function(wire.ReaderSettingsOverride, T) set,
      void Function(wire.ReaderSettingsOverride) clear,
    ) => ChoiceField<T>(
      inline: false,
      key: ValueKey('$scope-$id'),
      label: label,
      value: value,
      options: {
        if (manga) null: '跟随全局',
        for (final item in values.entries) item.key: item.value,
      },
      onChanged: state.canChange
          ? (value) => change((reader) {
              if (value == null) {
                clear(reader);
              } else {
                set(reader, value);
              }
            })
          : null,
    );
    final draft = owner == null || state.snapshot == null
        ? null
        : _FormDraft(state, manga);
    final r = draft?.reader;
    final effectiveMode = readerMode(
      r?.hasMode() == true
          ? r!.mode
          : state.snapshot?.global.reader.mode ??
                wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
    );
    final canClose =
        state.activity != SettingsActivity.saving || state.submitting != null;
    Widget group(String title, List<Widget> fields, {String? footer}) =>
        CupertinoFormSection.insetGrouped(
          margin: const EdgeInsets.symmetric(vertical: 8),
          header: manga ? Text(title) : null,
          footer: footer == null ? null : Text(footer),
          children: fields,
        );

    Widget feedback() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.unsent != null && state.error != null)
          const Text('部分修改尚未保存。'),
        if (controller != null)
          SettingsStatus(controller: controller, state: state),
      ],
    );
    Widget content(SettingsSection? section) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (owner != null) ?mangaContext,
        if (connection != null &&
            section?.isLocal != true &&
            section != SettingsSection.connection &&
            service?.status != ServiceStatus.ready) ...[
          if (service?.error case final error?)
            Text(
              error,
              style: TextStyle(color: AppColors.error.resolveFrom(context)),
            ),
          CupertinoButton(
            onPressed: () => changeSection(SettingsSection.connection),
            child: const Text('服务连接与登录'),
          ),
        ],
        if (section == SettingsSection.connection) ...[
          ?connection,
          if (service == null) const Text('连接并确认身份后可读取和保存同步设置。'),
        ],
        if (section == SettingsSection.appearance) ...[
          ?appearance,
          const ReaderDeviceControls(display: true, input: false),
        ],
        if (section == SettingsSection.input)
          const ReaderDeviceControls(display: false, input: true),
        if (section == SettingsSection.about)
          CupertinoListTile(
            leadingSize: 36,
            leading: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: Image.asset(
                'web/icons/karuyomi-192.png',
                width: 36,
                height: 36,
                excludeFromSemantics: true,
              ),
            ),
            title: const Text('Karuyomi'),
            subtitle: const Text('轻松翻开下一页'),
            trailing: const Text('0.1.0'),
          ),
        if (draft == null &&
            !state.available &&
            section?.isLocal != true &&
            section != SettingsSection.about &&
            section != SettingsSection.connection)
          const Text('连接并确认身份后可读取和保存同步设置。'),
        if (r != null) ...[
          if (manga || section == SettingsSection.reading) ...[
            group('账户阅读偏好', [
              if (manga)
                ChoiceField<_ReadingModeSource>(
                  key: const ValueKey('manga-mode-source'),
                  label: '阅读方式来源',
                  value: r.hasMode()
                      ? _ReadingModeSource.manga
                      : _ReadingModeSource.account,
                  options: const {
                    _ReadingModeSource.account: '跟随全局',
                    _ReadingModeSource.manga: '本漫画设置',
                  },
                  inline: false,
                  onChanged: state.canChange
                      ? (value) => change((reader) {
                          if (value == _ReadingModeSource.account) {
                            reader.clearMode();
                          } else {
                            reader.mode = wireReaderMode(effectiveMode);
                          }
                        })
                      : null,
                ),
              ...readerModeFields(
                scope: scope,
                mode: effectiveMode,
                onChanged: state.canChange
                    ? (mode) =>
                          change((reader) => reader.mode = wireReaderMode(mode))
                    : null,
              ),
              if (!effectiveMode.isContinuous)
                choice(
                  'layout',
                  '分页布局',
                  r.hasPageLayout() ? r.pageLayout : null,
                  _layouts,
                  (reader, value) => reader.pageLayout = value,
                  (reader) => reader.clearPageLayout(),
                ),
              choice(
                'fit',
                '图像适配',
                r.hasFit() ? r.fit : null,
                _fits,
                (reader, value) => reader.fit = value,
                (reader) => reader.clearFit(),
              ),
              choice(
                'crop-borders',
                '裁白',
                r.hasCropBorders() ? r.cropBorders : null,
                const {false: '关闭', true: '开启'},
                (reader, value) => reader.cropBorders = value,
                (reader) => reader.clearCropBorders(),
              ),
            ], footer: manga ? '选择“跟随全局”时，之后的账户默认值会应用到此漫画。' : null),
          ],
        ],
        if (manga)
          ReaderDeviceControls(
            scope: (
              origin: service?.deploymentOrigin?.origin ?? '',
              mangaKey: mangaKey!,
            ),
            display: true,
            input: true,
          ),
        if (!manga &&
            section?.isLocal != true &&
            (section == SettingsSection.reading ||
                state.unsent != null ||
                state.activity == SettingsActivity.saving ||
                state.pending != null ||
                state.error != null))
          feedback(),
      ],
    );
    return manga
        ? PopScope(
            canPop: canClose,
            child: EditSheet(
              title: const Text('本漫画阅读设置'),
              leading: Semantics(
                enabled: canClose,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: canClose ? () => Navigator.pop(context) : null,
                  child: const Text('关闭', semanticsLabel: '关闭设置'),
                ),
              ),
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
              final wide = fitsColumns(context, constraints, minimumWidth: 600);
              final section = currentSection ?? SettingsSection.appearance;
              final showDetail = wide || currentSection != null;
              bool isBackControl(FocusNode node) =>
                  node.context
                      ?.findAncestorWidgetOfExactType<
                        CupertinoNavigationBarBackButton
                      >() !=
                  null;

              final focus = FocusManager.instance.primaryFocus;
              final moveBackFocus =
                  wide &&
                  wasWide.value == false &&
                  focus != null &&
                  focus.context?.findAncestorStateOfType<NavigatorState>() ==
                      navigator.currentState &&
                  isBackControl(focus);
              if (!wide &&
                  wasWide.value == true &&
                  showDetail &&
                  directoryFocus.hasFocus) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted &&
                      wasWide.value == false &&
                      currentSection == section) {
                    detailFocus.traversalDescendants
                        .where(isBackControl)
                        .firstOrNull
                        ?.requestFocus();
                  }
                });
              }
              wasWide.value = wide;
              void select(SettingsSection value) {
                FocusScope.of(context).unfocus();
                changeSection(value);
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
                          for (final item in SettingsSection.values)
                            if (item != SettingsSection.connection ||
                                connection != null)
                              Semantics(
                                container: true,
                                selected: wide ? section == item : null,
                                child: CupertinoButton(
                                  key: ValueKey((
                                    'settings-navigation',
                                    item.id,
                                  )),
                                  autofocus: moveBackFocus && section == item,
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
                      if (!showDetail &&
                          state.unsent != null &&
                          state.error != null)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('部分修改尚未保存。'),
                        ),
                      if (!showDetail &&
                          controller != null &&
                          (state.pending != null || state.error != null))
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SettingsStatus(
                            controller: controller,
                            state: state,
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
                  child: PrimaryScrollController(
                    controller: detailScroll,
                    child: SingleChildScrollView(
                      key: ValueKey(('settings-content', section)),
                      primary: true,
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: content(section),
                        ),
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
                      child: FocusScope(node: directoryFocus, child: directory),
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
                          requestFocus: false,
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
                                child: FocusScope(
                                  node: detailFocus,
                                  child: detail,
                                ),
                              ),
                          ],
                          onDidRemovePage: (page) {
                            if (page.key ==
                                const ValueKey('settings-detail-page')) {
                              if (currentSection != null) changeSection(null);
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
