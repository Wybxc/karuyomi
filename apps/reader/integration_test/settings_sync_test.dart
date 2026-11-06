import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:karuyomi/data/business_state_validation.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:karuyomi/main.dart' as app;
import 'package:karuyomi/runtime/platform_runtime_native.dart';

const _origin = String.fromEnvironment('APP_ORIGIN');
const _subject = String.fromEnvironment('SETTINGS_SUBJECT');
const _phase = String.fromEnvironment('SETTINGS_PHASE');
const _expectedJson = String.fromEnvironment('SETTINGS_EXPECT_JSON');
const _preset = String.fromEnvironment('SETTINGS_PRESET');
const _operationBudget = Duration(seconds: 120);
const _presets = {
  'dark-rtl-double-width-crop',
  'light-webtoon-auto-height-no-crop',
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Native global settings sync: $_phase', (tester) async {
    final expected = _validateConfiguration();
    app.main();
    await tester.pump();
    final catalog = tester
        .widget<LibraryPage>(find.byType(LibraryPage))
        .controller;
    if (catalog == null) fail('正式 App 必须创建 CatalogController');
    final platform = catalog.api;
    if (platform is! NativePlatformRuntime) {
      fail('此验收必须使用正式 NativePlatformRuntime');
    }
    expect(platform.origin.origin, Uri.parse(_origin).origin);
    late final Map<String, Object?> result;

    try {
      await _waitFor(tester, 'Native 连接并取得同身份设置仓储', () {
        if (catalog.accessPaused || catalog.status == ServiceStatus.failed) {
          fail('Native 连接未完成：${catalog.error ?? catalog.status.name}');
        }
        return catalog.status == ServiceStatus.ready &&
            catalog.settings != null;
      });
      final repository = catalog.settings!;
      expect(repository.identity.subject, _subject);
      expect(repository.identity.origin.origin, platform.origin.origin);
      expect(catalog.session, isNull, reason: '设置验收不能启动 Source');

      await _tap(tester, find.byIcon(Icons.tune_outlined));
      await _waitFor(tester, '正式全局设置面板', () {
        final panels = find.byType(GlobalSettingsPanel);
        if (panels.evaluate().length != 1) {
          return false;
        }
        final editor = tester.widget<GlobalSettingsPanel>(panels).controller;
        return editor.available && !editor.busy && editor.snapshot != null;
      });
      final editor = tester
          .widget<GlobalSettingsPanel>(find.byType(GlobalSettingsPanel))
          .controller;
      expect(identical(editor.repository, repository), isTrue);
      final before = await repository.loadGlobal().timeout(_operationBudget);
      _expectSnapshot(before, expected);
      await _expectForm(tester, before.global);
      _expectTheme(tester, before.global.theme);
      expect(editor.pending, isNull);
      expect(editor.error, isNull);

      final after = _phase == 'write'
          ? await _write(tester, editor, repository, before)
          : await repository.loadGlobal().timeout(_operationBudget);
      if (_phase == 'verify') {
        _expectSnapshot(after, expected);
      }
      expect(identical(catalog.settings, repository), isTrue);
      expect(repository.identity.subject, _subject);
      expect(catalog.session, isNull, reason: '设置读写与确认不能启动 Source');
      expect(catalog.hasUnsavedReadingProgress, isFalse);
      expect(tester.takeException(), isNull);
      result = {
        'phase': _phase,
        'preset': _phase == 'write' ? _preset : null,
        'platform': Platform.operatingSystem,
        'origin': repository.identity.origin.origin,
        'subject': repository.identity.subject,
        'before': _report(before),
        'after': _report(after),
      };
    } finally {
      try {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await catalog.closeReadingProgress().timeout(_operationBudget);
      } finally {
        await platform.dispose().timeout(_operationBudget);
      }
    }
    binding.reportData = {'SETTINGS_SYNC_RESULT': result};
    debugPrint('SETTINGS_SYNC_RESULT ${jsonEncode(result)}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<SettingsSnapshot> _write(
  WidgetTester tester,
  SettingsController editor,
  SettingsRepository repository,
  SettingsSnapshot before,
) async {
  // Only these five visible preferences change. The form retains every other
  // confirmed reader field, favorite Source, installation and repository.
  final target = before.global.deepCopy();
  switch (_preset) {
    case 'dark-rtl-double-width-crop':
      target.theme = wire.AppTheme.APP_THEME_DARK;
      target.reader
        ..mode = wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT
        ..pageLayout = wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE
        ..fit = wire.ReaderFit.READER_FIT_WIDTH
        ..cropBorders = true;
      break;
    case 'light-webtoon-auto-height-no-crop':
      target.theme = wire.AppTheme.APP_THEME_LIGHT;
      target.reader
        ..mode = wire.ReaderMode.READER_MODE_WEBTOON
        ..pageLayout = wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO
        ..fit = wire.ReaderFit.READER_FIT_HEIGHT
        ..cropBorders = false;
      break;
    default:
      throw StateError('Unknown SETTINGS_PRESET: $_preset');
  }
  expect(
    (theme: target.theme, reader: _readerValues(target.reader)),
    isNot((
      theme: before.global.theme,
      reader: _readerValues(before.global.reader),
    )),
    reason: '写阶段须提交非默认差异，不能盲目重跑',
  );
  await _select<wire.AppTheme>(tester, target.theme);
  await _select<wire.ReaderMode>(tester, target.reader.mode);
  await _select<wire.ReaderPageLayout>(tester, target.reader.pageLayout);
  await _select<wire.ReaderFit>(tester, target.reader.fit);
  await _select<bool>(tester, target.reader.cropBorders);
  await _expectForm(tester, target);
  // A draft cannot apply the theme or become confirmed before the save ACK.
  _expectTheme(tester, before.global.theme);
  _expectGlobal(editor.snapshot!.global, before.global);
  expect(editor.pending, isNull);
  await _tap(tester, find.widgetWithText(FilledButton, '保存全局设置'));
  await _waitFor(tester, '全局设置获得服务端确认', () {
    if (editor.error != null) fail('全局设置写入失败：${editor.error}');
    return !editor.busy &&
        editor.pending == null &&
        editor.snapshot?.globalRevision == before.globalRevision + 1;
  });
  final after = await repository.loadGlobal().timeout(_operationBudget);
  expect(after.globalRevision, before.globalRevision + 1);
  expect(after.accountRevision, before.accountRevision + 1);
  _expectGlobal(after.global, target);
  expect(_readerValues(after.effectiveReader), _readerValues(target.reader));
  expect(after.mangaKey, isNull);
  expect(after.mangaRevision, isNull);
  expect(after.overrides, isNull);
  _expectGlobal(editor.snapshot!.global, target);
  expect(editor.error, isNull);
  await _expectForm(tester, target);
  _expectTheme(tester, target.theme);
  return after;
}

void _expectSnapshot(SettingsSnapshot actual, wire.SettingsResponse expected) {
  expect(actual.accountRevision, expected.accountRevision);
  expect(actual.globalRevision, expected.global.revision);
  _expectGlobal(actual.global, expected.global.values);
  expect(
    _readerValues(actual.effectiveReader),
    _readerValues(expected.effectiveReader),
  );
  expect(actual.mangaKey, isNull);
  expect(actual.mangaRevision, isNull);
  expect(actual.overrides, isNull);
}

// Plain proto3 scalar getters define the semantic value. GeneratedMessage's
// explicit-default presence must not change this assertion across TS and Dart.
void _expectGlobal(
  wire.GlobalSettingsValues actual,
  wire.GlobalSettingsValues expected,
) {
  expect(actual.theme, expected.theme);
  expect(actual.hasReader(), expected.hasReader());
  expect(_readerValues(actual.reader), _readerValues(expected.reader));
  expect(
    actual.favoriteSources.map(
      (value) => (
        packageName: value.packageName,
        sourceId: value.sourceId,
        sourceName: value.sourceName,
        sourceLang: value.sourceLang,
      ),
    ),
    orderedEquals(
      expected.favoriteSources.map(
        (value) => (
          packageName: value.packageName,
          sourceId: value.sourceId,
          sourceName: value.sourceName,
          sourceLang: value.sourceLang,
        ),
      ),
    ),
  );
  expect(
    actual.installedExtensions.map(
      (value) => (
        catalogUrl: value.catalogUrl,
        repoId: value.repoId,
        packageName: value.packageName,
        buildId: value.buildId,
        bundleSha256: value.bundleSha256,
        enabled: value.enabled,
      ),
    ),
    orderedEquals(
      expected.installedExtensions.map(
        (value) => (
          catalogUrl: value.catalogUrl,
          repoId: value.repoId,
          packageName: value.packageName,
          buildId: value.buildId,
          bundleSha256: value.bundleSha256,
          enabled: value.enabled,
        ),
      ),
    ),
  );
  expect(
    actual.repositories.map(
      (value) => (
        catalogUrl: value.catalogUrl,
        repoId: value.repoId,
        name: value.name,
      ),
    ),
    orderedEquals(
      expected.repositories.map(
        (value) => (
          catalogUrl: value.catalogUrl,
          repoId: value.repoId,
          name: value.name,
        ),
      ),
    ),
  );
}

({
  wire.ReaderMode mode,
  wire.ReaderPageLayout pageLayout,
  wire.ReaderBackground background,
  int dimPercent,
  wire.ReaderInputPreset tapZones,
  wire.ReaderInputPreset keyboard,
  wire.ReaderFit fit,
  bool cropBorders,
})
_readerValues(wire.ReaderSettings value) => (
  mode: value.mode,
  pageLayout: value.pageLayout,
  background: value.background,
  dimPercent: value.dimPercent,
  tapZones: value.tapZones,
  keyboard: value.keyboard,
  fit: value.fit,
  cropBorders: value.cropBorders,
);

Future<void> _expectForm(
  WidgetTester tester,
  wire.GlobalSettingsValues values,
) async {
  await _expectSelection(tester, 'global-theme', values.theme);
  await _expectSelection(tester, 'global-mode', values.reader.mode);
  await _expectSelection(tester, 'global-layout', values.reader.pageLayout);
  await _expectSelection(tester, 'global-fit', values.reader.fit);
  await _expectSelection(
    tester,
    'global-crop-borders',
    values.reader.cropBorders,
  );
}

Future<void> _expectSelection<T>(
  WidgetTester tester,
  String field,
  T value,
) async {
  final finder = find.byKey(ValueKey((field, value)));
  await _waitFor(tester, '设置字段 $field', () => finder.evaluate().length == 1);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  expect(finder.hitTestable(), findsOneWidget);
  expect(tester.widget<DropdownButtonFormField<T>>(finder).initialValue, value);
}

void _expectTheme(WidgetTester tester, wire.AppTheme theme) {
  final expected = switch (theme) {
    wire.AppTheme.APP_THEME_SYSTEM => ThemeMode.system,
    wire.AppTheme.APP_THEME_LIGHT => ThemeMode.light,
    wire.AppTheme.APP_THEME_DARK => ThemeMode.dark,
    _ => throw const FormatException('Unsupported expected application theme'),
  };
  expect(
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
    expected,
  );
}

Future<void> _select<T>(WidgetTester tester, T value) async {
  final field = find.byType(DropdownButtonFormField<T>);
  await _waitFor(tester, '设置选择框 $T', () => field.evaluate().length == 1);
  final input = tester.widget<DropdownButtonFormField<T>>(field);
  if (input.initialValue == value) {
    return;
  }
  expect(input.onChanged, isNotNull);
  final dropdown = find.descendant(
    of: field,
    matching: find.byType(DropdownButton<T>),
  );
  expect(dropdown, findsOneWidget);
  final items = tester.widget<DropdownButton<T>>(dropdown).items!;
  final child = items.singleWhere((item) => item.value == value).child;
  if (child is! Text || child.data == null) {
    fail('正式设置菜单应提供可见文本');
  }
  final label = child.data!;
  await _tap(tester, field);
  await _tap(tester, find.text(label).last);
  await _waitFor(
    tester,
    '设置选择已进入表单草稿',
    () =>
        tester.widget<DropdownButtonFormField<T>>(field).initialValue == value,
  );
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _waitFor(tester, '操作控件 $finder', () => finder.evaluate().length == 1);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  await _waitFor(
    tester,
    '操作控件可点击',
    () => finder.hitTestable().evaluate().length == 1,
  );
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _waitFor(
  WidgetTester tester,
  String operation,
  bool Function() ready,
) async {
  final elapsed = Stopwatch()..start();
  while (!ready()) {
    if (elapsed.elapsed >= _operationBudget) {
      fail('$operation 超过 ${_operationBudget.inSeconds} 秒预算');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

wire.SettingsResponse _validateConfiguration() {
  final origin = Uri.tryParse(_origin);
  if (origin == null ||
      origin.scheme != 'https' ||
      origin.host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      (origin.path.isNotEmpty && origin.path != '/')) {
    fail('APP_ORIGIN 必须是单一 HTTPS 服务源');
  }
  if (!Platform.isAndroid && !Platform.isIOS) {
    fail('此正式设置同步验收仅适用于 Android 或 iOS 设备/模拟器');
  }
  if (_subject.isEmpty || _subject.length > 1000) {
    fail('SETTINGS_SUBJECT 须为本次已确认身份');
  }
  if (!{'verify', 'write'}.contains(_phase) ||
      (_phase == 'verify' && _preset.isNotEmpty) ||
      (_phase == 'write' && !_presets.contains(_preset))) {
    fail('SETTINGS_PHASE 须为 verify/write；只有 write 可指定正式 preset');
  }
  final expected = wire.decodeProtoJson(
    wire.SettingsResponse(),
    jsonDecode(_expectedJson),
    maxBytes: wire.controlRequestLimit,
  );
  validateBusinessSettingsResponse(expected);
  expect(expected.hasError(), isFalse);
  expect(expected.hasManga(), isFalse);
  return expected;
}

Map<String, Object?> _report(SettingsSnapshot value) => {
  'accountRevision': value.accountRevision,
  'globalRevision': value.globalRevision,
  'global': wire.encodeProtoJson(value.global),
  'effectiveReader': wire.encodeProtoJson(value.effectiveReader),
};
