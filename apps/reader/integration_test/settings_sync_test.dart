import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:karuyomi/data/business_state_validation.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import '../test/settings/settings_probe.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:karuyomi/runtime/platform_runtime_native.dart';

import 'native_app.dart';

const _origin = String.fromEnvironment('APP_ORIGIN');
const _subject = String.fromEnvironment('SETTINGS_SUBJECT');
const _phase = String.fromEnvironment('SETTINGS_PHASE');
const _expectedJson = String.fromEnvironment('SETTINGS_EXPECT_JSON');
const _preset = String.fromEnvironment('SETTINGS_PRESET');
const _testCaBase64 = String.fromEnvironment('SETTINGS_TEST_CA_BASE64');
const _operationBudget = Duration(seconds: 120);
const _lifecycleBudget = Duration(minutes: 5);
const _ackSubject = 'acceptance-owner';
const _unconfirmed = '设置尚未确认，本会话保留原操作。';
const _retry = '重试原设置操作';
const _presets = {
  'dark-rtl-double-width-crop',
  'light-webtoon-auto-height-no-crop',
};

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Native global settings sync: $_phase', (tester) async {
    final expected = _validateConfiguration();
    if (_testCaBase64.isNotEmpty) {
      SecurityContext.defaultContext.setTrustedCertificatesBytes(
        base64Decode(_testCaBase64),
      );
    }
    final catalog = await startNativeApp(tester);
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
        final editor = globalSettings(tester);
        return editor.state.available &&
            !editor.state.busy &&
            editor.state.snapshot != null;
      });
      final editor = globalSettings(tester);
      expect(identical(editor.repository, repository), isTrue);
      final before = await repository.loadGlobal().timeout(_operationBudget);
      _expectSnapshot(before, expected);
      await _expectForm(tester, before.global);
      _expectTheme(tester, before.global.theme);
      expect(editor.state.pending, isNull);
      expect(editor.state.error, isNull);

      final after = switch (_phase) {
        'write' => await _write(tester, editor, repository, before),
        'resume' => await _resume(tester, editor, expected, before),
        'ack-loss' => await _ackLoss(tester, editor, repository, before),
        _ => await repository.loadGlobal().timeout(_operationBudget),
      };
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
        'preset': _preset.isEmpty ? null : _preset,
        if (_phase == 'ack-loss') 'pid': pid,
        if (_phase == 'resume')
          'lifecycle': {
            'pid': pid,
            'transitions': ['paused', 'resumed'],
          },
        'platform': Platform.operatingSystem,
        'androidLoopbackTestCa': _testCaBase64.isNotEmpty,
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

wire.GlobalSettingsValues _target(SettingsSnapshot before) {
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
    reason: '写入和前台恢复须从不同于预设的已确认值开始',
  );
  return target;
}

Future<SettingsSnapshot> _write(
  WidgetTester tester,
  SettingsProbe editor,
  SettingsRepository repository,
  SettingsSnapshot before,
) async {
  final target = _target(before);
  await _select<wire.AppTheme>(tester, target.theme);
  await _select<wire.ReaderMode>(tester, target.reader.mode);
  await _select<wire.ReaderPageLayout>(tester, target.reader.pageLayout);
  await _select<wire.ReaderFit>(tester, target.reader.fit);
  await _select<bool>(tester, target.reader.cropBorders);
  await _expectForm(tester, target);
  // A draft cannot apply the theme or become confirmed before the save ACK.
  _expectTheme(tester, before.global.theme);
  _expectGlobal(editor.state.snapshot!.global, before.global);
  expect(editor.state.pending, isNull);
  await _tap(tester, find.widgetWithText(FilledButton, '保存全局设置'));
  await _waitFor(tester, '全局设置获得服务端确认', () {
    if (editor.state.error != null) fail('全局设置写入失败：${editor.state.error}');
    return !editor.state.busy &&
        editor.state.pending == null &&
        editor.state.snapshot?.globalRevision == before.globalRevision + 1;
  });
  final after = await repository.loadGlobal().timeout(_operationBudget);
  _expectCommittedTarget(after, before, target);
  _expectGlobal(editor.state.snapshot!.global, target);
  expect(editor.state.error, isNull);
  await _expectForm(tester, target);
  _expectTheme(tester, target.theme);
  return after;
}

Future<SettingsSnapshot> _resume(
  WidgetTester tester,
  SettingsProbe editor,
  wire.SettingsResponse expected,
  SettingsSnapshot before,
) async {
  final target = _target(before);
  expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
  expect(editor.state.available, isTrue);
  expect(editor.state.busy, isFalse);
  _expectSnapshot(editor.state.snapshot!, expected);

  final resumed = Completer<void>();
  SettingsSnapshot? pausedSnapshot;
  SettingsSnapshot? resumedSnapshot;
  final listener = AppLifecycleListener(
    onPause: () {
      if (pausedSnapshot != null) return;
      pausedSnapshot = editor.state.snapshot;
      debugPrintSynchronously('SETTINGS_RESUME_PAUSED pid=$pid');
    },
    onResume: () {
      if (pausedSnapshot == null || resumed.isCompleted) return;
      resumedSnapshot = editor.state.snapshot;
      debugPrintSynchronously('SETTINGS_RESUME_RESUMED pid=$pid');
      resumed.complete();
    },
  );
  try {
    debugPrintSynchronously('SETTINGS_RESUME_READY pid=$pid');
    // Paused apps may not service a pump. Await the real system transition
    // without scheduling frames, reading the repository or touching the UI.
    await resumed.future.timeout(
      _lifecycleBudget,
      onTimeout: () => fail('未在预算内观察到系统暂停后恢复'),
    );
  } finally {
    listener.dispose();
  }

  _expectSnapshot(pausedSnapshot!, expected);
  _expectSnapshot(resumedSnapshot!, expected);
  await _waitFor(tester, '系统恢复触发正式设置重取', () {
    if (!editor.state.available || editor.state.error != null) {
      fail('恢复前台后原设置会话失效：${editor.state.error}');
    }
    final confirmed = editor.state.snapshot;
    return !editor.state.busy &&
        confirmed != null &&
        confirmed.globalRevision > before.globalRevision;
  });
  expect(globalSettings(tester).commands, same(editor.commands));
  final after = editor.state.snapshot!;
  _expectCommittedTarget(after, before, target);
  expect(editor.state.pending, isNull);
  await _expectForm(tester, target);
  _expectTheme(tester, target.theme);
  return after;
}

Future<SettingsSnapshot> _ackLoss(
  WidgetTester tester,
  SettingsProbe editor,
  SettingsRepository repository,
  SettingsSnapshot before,
) async {
  expect(before.accountRevision, 0, reason: '丢确认验收需要空 D1');
  expect(before.globalRevision, 0);
  expect(before.global.theme, wire.AppTheme.APP_THEME_SYSTEM);
  expect(before.global.installedExtensions, isEmpty);
  final target = before.global.deepCopy()..theme = wire.AppTheme.APP_THEME_DARK;
  final save = find.widgetWithText(FilledButton, '保存全局设置');
  final retry = find.widgetWithText(TextButton, _retry);
  await _select(tester, target.theme);
  _expectTheme(tester, before.global.theme);
  await _tap(tester, save);
  final unconfirmed = find.text(_unconfirmed);
  await _waitFor(tester, '正式保存保留未确认的设置操作', () {
    if (!editor.state.busy &&
        editor.state.pending == null &&
        editor.state.snapshot!.globalRevision > before.globalRevision) {
      fail('首次保存直接确认；须启动 settings-ack-loss 夹具');
    }
    return editor.state.canRetry &&
        unconfirmed.evaluate().length == 1 &&
        retry.evaluate().length == 1;
  });
  expect(find.text('设置修改尚未确认，请明确重试原操作。'), findsOneWidget);
  _expectPendingAck(tester, editor, before, target);
  expect(editor.state.snapshot!.globalRevision, before.globalRevision);
  _expectTheme(tester, before.global.theme);
  await _expectSelection(tester, 'global-theme', target.theme);

  // Read through a separate TLS connection so this checkpoint cannot publish a
  // confirmed value to the current editor or consume its pending operation.
  final committed = await _readAckSettings();
  expect(committed.accountRevision, before.accountRevision + 1);
  expect(committed.global.revision, before.globalRevision + 1);
  _expectGlobal(committed.global.values, target);
  expect(
    _readerValues(committed.effectiveReader),
    _readerValues(target.reader),
  );
  expect(editor.state.snapshot!.globalRevision, before.globalRevision);
  _expectTheme(tester, before.global.theme);
  _expectPendingAck(tester, editor, before, target);
  debugPrintSynchronously('SETTINGS_ACK_LOSS_COMMITTED_UNCONFIRMED pid=$pid');

  await _tap(tester, find.widgetWithText(TextButton, '重新读取设置'));
  await _waitFor(
    tester,
    '正式重读取到已提交值',
    () =>
        !editor.state.busy &&
        editor.state.snapshot!.globalRevision == committed.global.revision,
  );
  _expectSnapshot(editor.state.snapshot!, committed);
  expect(editor.state.error, isNull);
  _expectPendingAck(tester, editor, before, target);
  await _expectSelection(tester, 'global-theme', target.theme);
  _expectTheme(tester, target.theme);
  _expectSnapshot(editor.state.snapshot!, await _readAckSettings());
  debugPrintSynchronously('SETTINGS_ACK_LOSS_RELOADED_PENDING pid=$pid');

  await _tap(tester, retry);
  await _waitFor(tester, '显式重试确认原设置操作', () {
    if (!editor.state.busy && editor.state.error != null) {
      fail('重试原设置操作失败：${editor.state.error}');
    }
    return editor.state.canEdit &&
        editor.state.pending == null &&
        unconfirmed.evaluate().isEmpty &&
        retry.evaluate().isEmpty;
  });
  expect(globalSettings(tester).commands, same(editor.commands));
  expect(unconfirmed, findsNothing);
  expect(retry, findsNothing);
  _expectSnapshot(editor.state.snapshot!, committed);
  await _expectForm(tester, target);
  _expectTheme(tester, target.theme);
  final after = await repository.loadGlobal().timeout(_operationBudget);
  _expectSnapshot(after, committed);
  _expectSnapshot(after, await _readAckSettings());
  debugPrintSynchronously('SETTINGS_ACK_LOSS_RETRY_CONFIRMED pid=$pid');
  return after;
}

void _expectPendingAck(
  WidgetTester tester,
  SettingsProbe editor,
  SettingsSnapshot before,
  wire.GlobalSettingsValues target,
) {
  expect(editor.state.pending?.basedOnRevision, before.globalRevision);
  expect(editor.state.pending?.retryable, isTrue);
  _expectGlobal(editor.state.pending!.global!, target);
  expect(find.text(_unconfirmed), findsOneWidget);
  expect(
    tester
        .widget<TextButton>(find.widgetWithText(TextButton, _retry))
        .onPressed,
    isNotNull,
  );
  expect(
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '保存全局设置'))
        .onPressed,
    isNull,
  );
}

Future<wire.SettingsResponse> _readAckSettings() async {
  final client = http.Client();
  Future<wire.SettingsResponse> read() async {
    final origin = Uri.parse(_origin);
    final request = http.Request('GET', origin.resolve('/api/settings'))
      ..followRedirects = false
      ..headers.addAll({
        'Origin': origin.origin,
        'X-App-Request': '1',
        'X-App-Subject': _subject,
        'Accept': 'application/json',
      });
    final response = await client.send(request);
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], startsWith('application/json'));
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (chunk.length > wire.controlRequestLimit - bytes.length) {
        fail('验收设置响应超过读取预算');
      }
      bytes.add(chunk);
    }
    return _decodeGlobalSettings(utf8.decode(bytes.takeBytes()));
  }

  try {
    return await read().timeout(const Duration(seconds: 15));
  } finally {
    client.close();
  }
}

void _expectCommittedTarget(
  SettingsSnapshot after,
  SettingsSnapshot before,
  wire.GlobalSettingsValues target,
) {
  expect(after.globalRevision, before.globalRevision + 1);
  expect(after.accountRevision, before.accountRevision + 1);
  _expectGlobal(after.global, target);
  expect(_readerValues(after.effectiveReader), _readerValues(target.reader));
  expect(after.mangaKey, isNull);
  expect(after.mangaRevision, isNull);
  expect(after.overrides, isNull);
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
  if (_testCaBase64.isNotEmpty &&
      (!Platform.isAndroid || origin.host != '127.0.0.1')) {
    fail('SETTINGS_TEST_CA_BASE64 仅适用于 Android 的 HTTPS 127.0.0.1 验收');
  }
  if (_subject.isEmpty || _subject.length > 1000) {
    fail('SETTINGS_SUBJECT 须为本次已确认身份');
  }
  if (!{'verify', 'write', 'resume', 'ack-loss'}.contains(_phase) ||
      ({'verify', 'ack-loss'}.contains(_phase)
          ? _preset.isNotEmpty
          : !_presets.contains(_preset))) {
    fail(
      'SETTINGS_PHASE 须为 verify/write/resume/ack-loss；仅 write/resume 使用 preset',
    );
  }
  if (_phase == 'ack-loss' &&
      (origin.host != '127.0.0.1' ||
          !origin.hasPort ||
          origin.toString() != origin.origin ||
          _subject != _ackSubject)) {
    fail('丢确认验收仅允许本地 HTTPS 夹具及测试身份 $_ackSubject');
  }
  return _decodeGlobalSettings(_expectedJson);
}

wire.SettingsResponse _decodeGlobalSettings(String json) {
  final value = wire.decodeProtoJson(
    wire.SettingsResponse(),
    jsonDecode(json),
    maxBytes: wire.controlRequestLimit,
  );
  validateBusinessSettingsResponse(value);
  expect(value.hasError(), isFalse);
  expect(value.hasManga(), isFalse);
  return value;
}

Map<String, Object?> _report(SettingsSnapshot value) => {
  'accountRevision': value.accountRevision,
  'globalRevision': value.globalRevision,
  'global': wire.encodeProtoJson(value.global),
  'effectiveReader': wire.encodeProtoJson(value.effectiveReader),
};
