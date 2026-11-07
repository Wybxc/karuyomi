import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

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
ThemeMode appTheme(wire.AppTheme theme) => switch (theme) {
  wire.AppTheme.APP_THEME_SYSTEM => ThemeMode.system,
  wire.AppTheme.APP_THEME_LIGHT => ThemeMode.light,
  wire.AppTheme.APP_THEME_DARK => ThemeMode.dark,
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

/// The same four preferences are edited globally and per manga. Null values
/// mean inheritance only in the manga editor; zero dimming remains explicit.
class _ReaderAppearanceFields extends StatelessWidget {
  const _ReaderAppearanceFields({
    required this.scope,
    required this.enabled,
    required this.background,
    required this.dimPercent,
    required this.tapZones,
    required this.keyboard,
    required this.onBackground,
    required this.onDimPercent,
    required this.onTapZones,
    required this.onKeyboard,
    this.allowInheritance = false,
    this.inheritedDimPercent = 0,
  });
  final String scope;
  final bool enabled;
  final bool allowInheritance;
  final wire.ReaderBackground? background;
  final int? dimPercent;
  final wire.ReaderInputPreset? tapZones;
  final wire.ReaderInputPreset? keyboard;
  final int inheritedDimPercent;
  final ValueChanged<wire.ReaderBackground?> onBackground;
  final ValueChanged<int?> onDimPercent;
  final ValueChanged<wire.ReaderInputPreset?> onTapZones;
  final ValueChanged<wire.ReaderInputPreset?> onKeyboard;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      DropdownButtonFormField<wire.ReaderBackground>(
        key: ValueKey(('$scope-background', background)),
        initialValue: background,
        hint: const Text('跟随全局'),
        decoration: const InputDecoration(
          labelText: '阅读背景',
          border: OutlineInputBorder(),
        ),
        items: [
          if (allowInheritance)
            const DropdownMenuItem(value: null, child: Text('跟随全局')),
          for (final item in _backgrounds.entries)
            DropdownMenuItem(value: item.key, child: Text(item.value)),
        ],
        onChanged: enabled ? onBackground : null,
      ),
      const SizedBox(height: 16),
      if (allowInheritance)
        SwitchListTile(
          key: ValueKey('$scope-dim-inherit'),
          contentPadding: EdgeInsets.zero,
          title: const Text('调暗跟随全局'),
          value: dimPercent == null,
          onChanged: enabled
              ? (inherit) => onDimPercent(inherit ? null : inheritedDimPercent)
              : null,
        ),
      Text(
        dimPercent == null
            ? '应用内调暗：跟随全局（$inheritedDimPercent%）'
            : '应用内调暗：$dimPercent%',
      ),
      Slider(
        key: ValueKey('$scope-dim'),
        value: (dimPercent ?? inheritedDimPercent).toDouble(),
        min: 0,
        max: 80,
        divisions: 80,
        label: '${dimPercent ?? inheritedDimPercent}%',
        onChanged: enabled && dimPercent != null
            ? (value) => onDimPercent(value.round())
            : null,
      ),
      const Text('仅调暗阅读内容，不改变系统亮度。'),
      const SizedBox(height: 16),
      DropdownButtonFormField<wire.ReaderInputPreset>(
        key: ValueKey(('$scope-tap-zones', tapZones)),
        initialValue: tapZones,
        hint: const Text('跟随全局'),
        decoration: const InputDecoration(
          labelText: '分页点击区',
          border: OutlineInputBorder(),
        ),
        items: [
          if (allowInheritance)
            const DropdownMenuItem(value: null, child: Text('跟随全局')),
          for (final item in _inputPresets.entries)
            DropdownMenuItem(value: item.key, child: Text(item.value)),
        ],
        onChanged: enabled ? onTapZones : null,
      ),
      const SizedBox(height: 8),
      const Text('反向会交换左右翻页；关闭后仍可从中央显示工具栏，滑动翻页不变。'),
      const SizedBox(height: 16),
      DropdownButtonFormField<wire.ReaderInputPreset>(
        key: ValueKey(('$scope-keyboard', keyboard)),
        initialValue: keyboard,
        hint: const Text('跟随全局'),
        decoration: const InputDecoration(
          labelText: '阅读快捷键',
          border: OutlineInputBorder(),
        ),
        items: [
          if (allowInheritance)
            const DropdownMenuItem(value: null, child: Text('跟随全局')),
          for (final item in _inputPresets.entries)
            DropdownMenuItem(value: item.key, child: Text(item.value)),
        ],
        onChanged: enabled ? onKeyboard : null,
      ),
      const SizedBox(height: 8),
      const Text('反向会交换方向键、上下翻页键和空格的翻页方向；Home/End 仍到首末页。'),
    ],
  );
}

class SettingsStatus extends StatelessWidget {
  const SettingsStatus({super.key, required this.controller, this.onReloaded});
  final SettingsController controller;
  final VoidCallback? onReloaded;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (controller.busy) const LinearProgressIndicator(),
      if (controller.error case final error?) Text(error),
      if (controller.pending?.retryable == true) const Text('设置尚未确认，本会话保留原操作。'),
      Wrap(
        children: [
          TextButton.icon(
            onPressed: controller.canRefresh
                ? () => unawaited(() async {
                    if (await controller.refresh()) onReloaded?.call();
                  }())
                : null,
            icon: const Icon(Icons.sync),
            label: const Text('重新读取设置'),
          ),
          if (controller.pending?.retryable == true)
            TextButton(
              onPressed: controller.canRetry
                  ? () => unawaited(() async {
                      if (await controller.retry()) onReloaded?.call();
                    }())
                  : null,
              child: const Text('重试原设置操作'),
            ),
        ],
      ),
    ],
  );
}

class GlobalSettingsPanel extends StatefulWidget {
  const GlobalSettingsPanel({super.key, required this.controller});
  final SettingsController controller;
  @override
  State<GlobalSettingsPanel> createState() => _GlobalSettingsPanelState();
}

class _GlobalSettingsPanelState extends State<GlobalSettingsPanel> {
  wire.GlobalSettingsValues? _draft;
  int _revision = 0;
  bool _dirty = false;
  void _reset() {
    final snapshot = widget.controller.snapshot;
    final pending = widget.controller.pending;
    if (snapshot == null && pending?.global == null) return;
    _draft = (pending?.global ?? snapshot!.global).deepCopy();
    _revision = pending?.basedOnRevision ?? snapshot!.globalRevision;
    _dirty = pending != null;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (_draft == null ||
          (!_dirty && _revision != controller.snapshot?.globalRevision)) {
        _reset();
      }
      final draft = _draft;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('全局设置', style: Theme.of(context).textTheme.titleLarge),
          const Text('漫画可以单独覆盖各项阅读偏好；服务端确认后才保存。'),
          const SizedBox(height: 16),
          if (draft != null) ...[
            DropdownButtonFormField<wire.AppTheme>(
              key: ValueKey(('global-theme', draft.theme)),
              initialValue: draft.theme,
              decoration: const InputDecoration(
                labelText: '外观',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: wire.AppTheme.APP_THEME_SYSTEM,
                  child: Text('跟随系统'),
                ),
                DropdownMenuItem(
                  value: wire.AppTheme.APP_THEME_LIGHT,
                  child: Text('浅色'),
                ),
                DropdownMenuItem(
                  value: wire.AppTheme.APP_THEME_DARK,
                  child: Text('深色'),
                ),
              ],
              onChanged: controller.canEdit
                  ? (value) {
                      if (value != null) {
                        setState(() {
                          _dirty = true;
                          draft.theme = value;
                        });
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<wire.ReaderMode>(
              key: ValueKey(('global-mode', draft.reader.mode)),
              initialValue: draft.reader.mode,
              decoration: const InputDecoration(
                labelText: '默认阅读模式',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final item in _modes.entries)
                  DropdownMenuItem(value: item.key, child: Text(item.value)),
              ],
              onChanged: controller.canEdit
                  ? (value) {
                      if (value != null) {
                        setState(() {
                          _dirty = true;
                          draft.reader.mode = value;
                        });
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<wire.ReaderPageLayout>(
              key: ValueKey(('global-layout', draft.reader.pageLayout)),
              initialValue: draft.reader.pageLayout,
              decoration: const InputDecoration(
                labelText: '默认页组',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final item in _layouts.entries)
                  DropdownMenuItem(value: item.key, child: Text(item.value)),
              ],
              onChanged: controller.canEdit
                  ? (value) {
                      if (value != null) {
                        setState(() {
                          _dirty = true;
                          draft.reader.pageLayout = value;
                        });
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<wire.ReaderFit>(
              key: ValueKey(('global-fit', draft.reader.fit)),
              initialValue: draft.reader.fit,
              decoration: const InputDecoration(
                labelText: '图像适配',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final item in _fits.entries)
                  DropdownMenuItem(value: item.key, child: Text(item.value)),
              ],
              onChanged: controller.canEdit
                  ? (value) {
                      if (value != null) {
                        setState(() {
                          _dirty = true;
                          draft.reader.fit = value;
                        });
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<bool>(
              key: ValueKey(('global-crop-borders', draft.reader.cropBorders)),
              initialValue: draft.reader.cropBorders,
              decoration: const InputDecoration(
                labelText: '裁白',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: false, child: Text('关闭')),
                DropdownMenuItem(value: true, child: Text('开启')),
              ],
              onChanged: controller.canEdit
                  ? (value) {
                      if (value != null) {
                        setState(() {
                          _dirty = true;
                          draft.reader.cropBorders = value;
                        });
                      }
                    }
                  : null,
            ),
            _ReaderAppearanceFields(
              scope: 'global',
              enabled: controller.canEdit,
              background: draft.reader.background,
              dimPercent: draft.reader.dimPercent,
              tapZones: draft.reader.tapZones,
              keyboard: draft.reader.keyboard,
              onBackground: (value) {
                if (value != null) {
                  setState(() {
                    _dirty = true;
                    draft.reader.background = value;
                  });
                }
              },
              onDimPercent: (value) {
                if (value != null) {
                  setState(() {
                    _dirty = true;
                    draft.reader.dimPercent = value;
                  });
                }
              },
              onTapZones: (value) {
                if (value != null) {
                  setState(() {
                    _dirty = true;
                    draft.reader.tapZones = value;
                  });
                }
              },
              onKeyboard: (value) {
                if (value != null) {
                  setState(() {
                    _dirty = true;
                    draft.reader.keyboard = value;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: controller.canEdit
                  ? () => unawaited(() async {
                      if (await controller.saveGlobal(
                            draft.deepCopy(),
                            _revision,
                          ) &&
                          mounted) {
                        setState(_reset);
                      }
                    }())
                  : null,
              child: const Text('保存全局设置'),
            ),
          ],
          SettingsStatus(
            controller: controller,
            onReloaded: () {
              if (mounted) setState(_reset);
            },
          ),
        ],
      );
    },
  );
}

class MangaSettingsEditor extends StatefulWidget {
  const MangaSettingsEditor({super.key, required this.controller});
  final SettingsController controller;
  @override
  State<MangaSettingsEditor> createState() => _MangaSettingsEditorState();
}

class _MangaSettingsEditorState extends State<MangaSettingsEditor> {
  wire.ReaderSettingsOverride? _draft;
  int _revision = 0;
  bool _dirty = false;
  void _reset() {
    final snapshot = widget.controller.snapshot;
    final pending = widget.controller.pending;
    if (snapshot?.overrides == null && pending?.overrides == null) return;
    _draft = (pending?.overrides ?? snapshot!.overrides!).deepCopy();
    _revision = pending?.basedOnRevision ?? snapshot!.mangaRevision!;
    _dirty = pending != null;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (_draft == null ||
          (!_dirty && _revision != controller.snapshot?.mangaRevision)) {
        _reset();
      }
      final draft = _draft;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('本漫画阅读设置', style: Theme.of(context).textTheme.titleLarge),
              const Text('选择“跟随全局”时，之后的全局修改会应用到此漫画。'),
              const SizedBox(height: 16),
              if (draft != null) ...[
                DropdownButtonFormField<wire.ReaderMode>(
                  key: ValueKey((
                    'manga-mode',
                    draft.hasMode() ? draft.mode : null,
                  )),
                  initialValue: draft.hasMode() ? draft.mode : null,
                  hint: const Text('跟随全局'),
                  decoration: const InputDecoration(
                    labelText: '阅读模式',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('跟随全局')),
                    for (final item in _modes.entries)
                      DropdownMenuItem(
                        value: item.key,
                        child: Text(item.value),
                      ),
                  ],
                  onChanged: controller.canEdit
                      ? (value) => setState(() {
                          _dirty = true;
                          if (value == null) {
                            draft.clearMode();
                          } else {
                            draft.mode = value;
                          }
                        })
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<wire.ReaderPageLayout>(
                  key: ValueKey((
                    'manga-layout',
                    draft.hasPageLayout() ? draft.pageLayout : null,
                  )),
                  initialValue: draft.hasPageLayout() ? draft.pageLayout : null,
                  hint: const Text('跟随全局'),
                  decoration: const InputDecoration(
                    labelText: '页组',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('跟随全局')),
                    for (final item in _layouts.entries)
                      DropdownMenuItem(
                        value: item.key,
                        child: Text(item.value),
                      ),
                  ],
                  onChanged: controller.canEdit
                      ? (value) => setState(() {
                          _dirty = true;
                          if (value == null) {
                            draft.clearPageLayout();
                          } else {
                            draft.pageLayout = value;
                          }
                        })
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<wire.ReaderFit>(
                  key: ValueKey((
                    'manga-fit',
                    draft.hasFit() ? draft.fit : null,
                  )),
                  initialValue: draft.hasFit() ? draft.fit : null,
                  hint: const Text('跟随全局'),
                  decoration: const InputDecoration(
                    labelText: '图像适配',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('跟随全局')),
                    for (final item in _fits.entries)
                      DropdownMenuItem(
                        value: item.key,
                        child: Text(item.value),
                      ),
                  ],
                  onChanged: controller.canEdit
                      ? (value) => setState(() {
                          _dirty = true;
                          if (value == null) {
                            draft.clearFit();
                          } else {
                            draft.fit = value;
                          }
                        })
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<bool>(
                  key: ValueKey((
                    'manga-crop-borders',
                    draft.hasCropBorders() ? draft.cropBorders : null,
                  )),
                  initialValue: draft.hasCropBorders()
                      ? draft.cropBorders
                      : null,
                  hint: const Text('跟随全局'),
                  decoration: const InputDecoration(
                    labelText: '裁白',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('跟随全局')),
                    DropdownMenuItem(value: false, child: Text('关闭')),
                    DropdownMenuItem(value: true, child: Text('开启')),
                  ],
                  onChanged: controller.canEdit
                      ? (value) => setState(() {
                          _dirty = true;
                          if (value == null) {
                            draft.clearCropBorders();
                          } else {
                            draft.cropBorders = value;
                          }
                        })
                      : null,
                ),
                _ReaderAppearanceFields(
                  scope: 'manga',
                  enabled: controller.canEdit,
                  allowInheritance: true,
                  background: draft.hasBackground() ? draft.background : null,
                  dimPercent: draft.hasDimPercent() ? draft.dimPercent : null,
                  tapZones: draft.hasTapZones() ? draft.tapZones : null,
                  keyboard: draft.hasKeyboard() ? draft.keyboard : null,
                  inheritedDimPercent:
                      controller.snapshot?.global.reader.dimPercent ?? 0,
                  onBackground: (value) => setState(() {
                    _dirty = true;
                    if (value == null) {
                      draft.clearBackground();
                    } else {
                      draft.background = value;
                    }
                  }),
                  onDimPercent: (value) => setState(() {
                    _dirty = true;
                    if (value == null) {
                      draft.clearDimPercent();
                    } else {
                      draft.dimPercent = value;
                    }
                  }),
                  onTapZones: (value) => setState(() {
                    _dirty = true;
                    if (value == null) {
                      draft.clearTapZones();
                    } else {
                      draft.tapZones = value;
                    }
                  }),
                  onKeyboard: (value) => setState(() {
                    _dirty = true;
                    if (value == null) {
                      draft.clearKeyboard();
                    } else {
                      draft.keyboard = value;
                    }
                  }),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: controller.canEdit
                      ? () => unawaited(() async {
                          if (await controller.saveOverrides(
                                draft.deepCopy(),
                                _revision,
                              ) &&
                              mounted) {
                            setState(_reset);
                          }
                        }())
                      : null,
                  child: const Text('保存本漫画设置'),
                ),
              ],
              SettingsStatus(
                controller: controller,
                onReloaded: () {
                  if (mounted) setState(_reset);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}
