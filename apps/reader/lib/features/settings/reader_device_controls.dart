import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/choice_field.dart';
import '../reader/reader_preferences.dart';
import 'reader_device_settings.dart';

const _backgrounds = <ReaderBackground, String>{
  ReaderBackground.black: '黑色',
  ReaderBackground.white: '白色',
  ReaderBackground.theme: '跟随应用主题',
};
const _inputs = <ReaderInputPreset, String>{
  ReaderInputPreset.standard: '标准',
  ReaderInputPreset.reversed: '反向',
  ReaderInputPreset.disabled: '关闭',
};

class const ReaderDeviceControls({
  super.key,
  final ReaderDeviceScope? scope,
  required final bool display,
  required final bool input,
}) extends HookConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = readerDeviceSettingsProvider(scope: scope);
    final local = ref.watch(provider).value;
    final defaults = ref.watch(effectiveReaderDevicePreferencesProvider());
    final preview = useState<int?>(null);
    final dragging = useRef(false);
    final manga = scope != null;
    final prefix = manga ? 'manga' : 'global';
    final editable = local != null && !local.saving;
    final prefs = local?.preferences;
    final dim = manga ? prefs?.dimPercent : defaults.dimPercent;
    final visibleDim = preview.value ?? dim;

    void change(
      ReaderDevicePreferences Function(ReaderDevicePreferences) edit,
    ) {
      final latest = ref.read(provider).value;
      if (latest != null && !latest.saving) {
        unawaited(ref.read(provider.notifier).save(edit(latest.preferences)));
      }
    }

    Widget choice<T extends Object>(
      String id,
      String label,
      T? value,
      Map<T, String> options,
      ReaderDevicePreferences Function(ReaderDevicePreferences, T?) apply,
    ) => ChoiceField<T>(
      key: ValueKey('$prefix-$id'),
      inline: false,
      label: label,
      value: value,
      options: {if (manga) null: '跟随本机默认', ...options},
      onChanged: editable
          ? (next) => change((values) => apply(values, next))
          : null,
    );

    Widget group(String title, List<Widget> fields, {String? help}) =>
        CupertinoFormSection.insetGrouped(
          margin: const EdgeInsets.symmetric(vertical: 8),
          header: Text(title),
          footer: help == null ? null : Text(help),
          children: fields,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (display) ...[
          group('本机阅读外观', [
            choice(
              'background',
              '阅读背景',
              manga ? prefs?.background : defaults.background,
              _backgrounds,
              (values, next) => values.withBackground(next),
            ),
            if (manga)
              MergeSemantics(
                child: CupertinoFormRow(
                  prefix: Expanded(flex: 3, child: const Text('调暗跟随本机默认')),
                  child: CupertinoSwitch(
                    key: ValueKey('$prefix-dim-inherit'),
                    value: dim == null,
                    onChanged: editable
                        ? (inherit) => change(
                            (values) => values.withDim(
                              inherit ? null : defaults.dimPercent,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    visibleDim == null
                        ? '应用内调暗：跟随本机默认（${defaults.dimPercent}%）'
                        : '应用内调暗：$visibleDim%',
                  ),
                  CupertinoSlider(
                    key: ValueKey('$prefix-dim'),
                    value: (visibleDim ?? defaults.dimPercent).toDouble(),
                    min: 0,
                    max: 80,
                    divisions: 80,
                    onChangeStart: (_) => dragging.value = true,
                    onChanged: editable && dim != null
                        ? (value) {
                            if (dragging.value) {
                              preview.value = value.round();
                            } else {
                              change((values) => values.withDim(value.round()));
                            }
                          }
                        : null,
                    onChangeEnd: (value) {
                      if (!dragging.value) return;
                      dragging.value = false;
                      preview.value = null;
                      change((values) => values.withDim(value.round()));
                    },
                  ),
                ],
              ),
            ),
          ], help: '仅调暗阅读内容。'),
        ],
        if (input) ...[
          group('本机翻页与快捷键', [
            choice(
              'tap-zones',
              '分页点击区',
              manga ? prefs?.tapZones : defaults.tapZones,
              _inputs,
              (values, next) => values.withTapZones(next),
            ),
            choice(
              'keyboard',
              '阅读快捷键',
              manga ? prefs?.keyboard : defaults.keyboard,
              _inputs,
              (values, next) => values.withKeyboard(next),
            ),
          ], help: '反向交换翻页方向。Home 和 End 跳到首末页，T 显示或隐藏工具栏。'),
        ],
        if (local == null || local.saving)
          Semantics(
            liveRegion: true,
            child: Text(local == null ? '正在读取本机阅读设置' : '正在保存本机阅读设置'),
          ),
        if (local?.failed case final failed?) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              '未能保存本机阅读设置。',
              style: TextStyle(color: AppColors.error.resolveFrom(context)),
            ),
          ),
          CupertinoButton(
            onPressed: () =>
                unawaited(ref.read(provider.notifier).save(failed)),
            child: const Text('重试保存本机阅读设置'),
          ),
        ],
      ],
    );
  }
}

extension on ReaderDevicePreferences {
  ReaderDevicePreferences withBackground(ReaderBackground? value) => (
    background: value,
    dimPercent: dimPercent,
    tapZones: tapZones,
    keyboard: keyboard,
  );

  ReaderDevicePreferences withDim(int? value) => (
    background: background,
    dimPercent: value,
    tapZones: tapZones,
    keyboard: keyboard,
  );

  ReaderDevicePreferences withTapZones(ReaderInputPreset? value) => (
    background: background,
    dimPercent: dimPercent,
    tapZones: value,
    keyboard: keyboard,
  );

  ReaderDevicePreferences withKeyboard(ReaderInputPreset? value) => (
    background: background,
    dimPercent: dimPercent,
    tapZones: tapZones,
    keyboard: value,
  );
}
