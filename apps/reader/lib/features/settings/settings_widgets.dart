import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

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
      if (controller.pending != null) const Text('设置尚未确认，本会话保留原操作。'),
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
          if (controller.pending != null)
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
          const Text('漫画可以单独覆盖阅读模式和页组；服务端确认后才保存。'),
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
