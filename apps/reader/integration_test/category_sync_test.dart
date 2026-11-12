import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:karuyomi/data/library_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/runtime/platform_runtime_native.dart';

import 'native_app.dart';

const _origin = String.fromEnvironment('APP_ORIGIN');
const _phase = String.fromEnvironment('CATEGORY_PHASE');
const _testCaBase64 = String.fromEnvironment('CATEGORY_TEST_CA_BASE64');
const _first = '分类同步·甲';
const _second = '分类同步·乙';
const _createdName = '跨端分类';
const _sharedName = '共享分类';
const _weekday = '工作日';
const _weekend = '周末';
const _operationBudget = Duration(seconds: 120);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Native category sync: $_phase', (tester) async {
    _validateConfiguration();
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
      await _waitFor(tester, 'Native 连接并显示两部预置收藏', () {
        if (catalog.accessPaused || catalog.status == ServiceStatus.failed) {
          fail('Native 连接未完成：${catalog.error ?? catalog.status.name}');
        }
        return catalog.status == ServiceStatus.ready &&
            catalog.library != null &&
            _tile(_first).evaluate().length == 1 &&
            _tile(_second).evaluate().length == 1;
      });
      final repository = catalog.library!;
      final before = await _readConfirmed(repository);
      final after = await _runPhase(tester, repository, before);
      final category = after.categories.singleOrNull;
      expect(catalog.session, isNull, reason: '分类验收不能启动 Source');
      expect(identical(catalog.library, repository), isTrue);
      expect(tester.takeException(), isNull);
      result = {
        'phase': _phase,
        'platform': Platform.operatingSystem,
        'origin': platform.origin.origin,
        'androidLoopbackTestCa': _testCaBase64.isNotEmpty,
        'subject': repository.identity.subject,
        'categoryRevision': after.categoryRevision,
        'categoryId': category?.id,
        'categoryName': category?.name,
        'categories': [
          for (final category in after.categories)
            {'id': category.id, 'name': category.name},
        ],
        'entries': [
          for (final title in [_first, _second])
            {
              'title': title,
              'revision': _entry(after, title).revision,
              'categoryIds': _entry(after, title).categoryIds,
            },
        ],
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
    binding.reportData = {'CATEGORY_SYNC_RESULT': result};
    debugPrint('CATEGORY_SYNC_RESULT ${jsonEncode(result)}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<LibraryView> _runPhase(
  WidgetTester tester,
  LibraryRepository repository,
  LibraryView before,
) async {
  switch (_phase) {
    case 'create':
      _expectState(before);
      await _expectShelf(tester);
      await _tap(tester, find.text('管理分类'));
      await _tap(tester, find.text('新建分类'));
      await _nameAndSave(tester, _createdName);
      await _waitForManager(tester, _createdName);
      await _closeManager(tester);
      final created = await _readConfirmed(repository);
      _expectState(created, categoryName: _createdName);
      await _assign(tester, _first, _createdName);
      final after = await _readConfirmed(repository);
      _expectState(after, categoryName: _createdName, firstAssigned: true);
      expect(after.categories.single.id, created.categories.single.id);
      await _expectShelf(
        tester,
        categoryName: _createdName,
        firstAssigned: true,
      );
      return after;
    case 'update':
      _expectState(before, categoryName: _createdName, firstAssigned: true);
      await _expectShelf(
        tester,
        categoryName: _createdName,
        firstAssigned: true,
      );
      await _tap(tester, find.text('管理分类'));
      await _tap(tester, find.byTooltip('重命名分类 $_createdName'));
      await _nameAndSave(tester, _sharedName);
      await _waitForManager(tester, _sharedName);
      await _closeManager(tester);
      final renamed = await _readConfirmed(repository);
      _expectState(renamed, categoryName: _sharedName, firstAssigned: true);
      expect(renamed.categories.single.id, before.categories.single.id);
      await _assign(tester, _second, _sharedName);
      final after = await _readConfirmed(repository);
      _expectState(
        after,
        categoryName: _sharedName,
        firstAssigned: true,
        secondAssigned: true,
      );
      expect(after.categories.single.id, before.categories.single.id);
      await _expectShelf(
        tester,
        categoryName: _sharedName,
        firstAssigned: true,
        secondAssigned: true,
      );
      return after;
    case 'verify':
    case 'delete':
      _expectState(
        before,
        categoryName: _sharedName,
        firstAssigned: true,
        secondAssigned: true,
      );
      await _expectShelf(
        tester,
        categoryName: _sharedName,
        firstAssigned: true,
        secondAssigned: true,
      );
      if (_phase == 'verify') return before;
      await _tap(tester, find.text('管理分类'));
      await _tap(tester, find.byTooltip('删除分类 $_sharedName'));
      await _tap(tester, find.text('删除'));
      await _waitFor(
        tester,
        '删除获得确认并返回空分类目录',
        () => find.text('还没有分类。').evaluate().length == 1,
      );
      await _closeManager(tester);
      final after = await _readConfirmed(repository);
      _expectState(after);
      await _expectShelf(tester);
      return after;
    case 'verify-deleted':
      _expectState(before);
      await _expectShelf(tester);
      await _tap(tester, find.widgetWithText(ChoiceChip, '未分类'));
      await _expectShelf(tester);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '未分类'))
            .selected,
        isTrue,
      );
      return before;
    case 'reorder':
      _expectOrderedState(before, [_weekday, _weekend]);
      await _expectOrderedShelf(tester, [_weekday, _weekend]);
      await _tap(tester, find.text('管理分类'));
      await _tap(tester, find.byTooltip('上移分类 $_weekend'));
      await _waitForManager(tester, _weekday);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.tooltip == '上移分类 $_weekend' &&
              widget.onPressed == null,
        ),
        findsOneWidget,
      );
      await _closeManager(tester);
      final after = await _readConfirmed(repository);
      _expectOrderedState(after, [_weekend, _weekday]);
      expect(after.categoryRevision, before.categoryRevision + 1);
      expect(
        after.categories.map((category) => category.id),
        before.categories.reversed.map((category) => category.id),
      );
      for (final title in [_first, _second]) {
        expect(_entry(after, title).revision, _entry(before, title).revision);
      }
      await _expectOrderedShelf(tester, [_weekend, _weekday]);
      return after;
    case 'delete-reordered':
      _expectOrderedState(before, [_weekend, _weekday]);
      await _expectOrderedShelf(tester, [_weekend, _weekday]);
      await _tap(tester, find.text('管理分类'));
      await _tap(tester, find.byTooltip('删除分类 $_weekend'));
      await _tap(tester, find.text('删除'));
      await _waitForManager(tester, _weekday);
      expect(find.byTooltip('删除分类 $_weekend'), findsNothing);
      await _closeManager(tester);
      final after = await _readConfirmed(repository);
      _expectOrderedState(after, [_weekday]);
      expect(after.categoryRevision, before.categoryRevision + 1);
      expect(after.categories.single.id, before.categories.last.id);
      expect(_entry(after, _first).revision, _entry(before, _first).revision);
      expect(
        _entry(after, _second).revision,
        _entry(before, _second).revision + 1,
      );
      await _expectOrderedShelf(tester, [_weekday]);
      return after;
    case 'verify-reordered-deleted':
      _expectOrderedState(before, [_weekday]);
      await _expectOrderedShelf(tester, [_weekday]);
      return before;
    default:
      throw StateError('Unknown CATEGORY_PHASE: $_phase');
  }
}

void _expectOrderedState(LibraryView view, List<String> names) {
  expect(view.categories.map((category) => category.name), names);
  expect(
    view.entries.map((entry) => entry.title),
    unorderedEquals([_first, _second]),
  );
  for (final (title, name) in [(_first, _weekday), (_second, _weekend)]) {
    expect(
      _entry(view, title).categoryIds,
      view.categories
          .where((category) => category.name == name)
          .map((category) => category.id),
    );
  }
}

Future<void> _expectOrderedShelf(
  WidgetTester tester,
  List<String> names,
) async {
  final secondName = names.contains(_weekend) ? _weekend : '未分类';
  final labels = ['全部', '未分类', ...names];
  Finder chip(String name) => find.widgetWithText(ChoiceChip, name);
  await _waitFor(tester, '书架显示目录顺序和两部收藏的分类', () {
    final actualLabels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ChoiceChip),
            matching: find.byType(Text),
          ),
        )
        .map((label) => label.data)
        .toList();
    if (actualLabels.join('/') != labels.join('/')) {
      return false;
    }
    for (final (title, name) in [(_first, _weekday), (_second, secondName)]) {
      if (!_tileShowsCategory(title, name)) return false;
    }
    return true;
  });
  for (final (name, visible, hidden) in [
    (_weekday, _first, _second),
    (secondName, _second, _first),
  ]) {
    await _tap(tester, chip(name));
    expect(tester.widget<ChoiceChip>(chip(name)).selected, isTrue);
    expect(_tile(visible), findsOneWidget);
    expect(_tile(hidden), findsNothing);
  }
  await _tap(tester, chip('全部'));
  expect(_tile(_first), findsOneWidget);
  expect(_tile(_second), findsOneWidget);
}

// watchView performs the repository's normal API refresh; no test state is injected.
Future<LibraryView> _readConfirmed(LibraryRepository repository) =>
    repository.watchView().first.timeout(_operationBudget);

void _expectState(
  LibraryView view, {
  String? categoryName,
  bool firstAssigned = false,
  bool secondAssigned = false,
}) {
  expect(
    view.entries.map((entry) => entry.title),
    unorderedEquals([_first, _second]),
  );
  if (categoryName == null) {
    expect(view.categories, isEmpty);
  } else {
    expect(view.categories, hasLength(1));
    expect(view.categories.single.name, categoryName);
  }
  final categoryIds = view.categories.map((category) => category.id).toList();
  expect(
    _entry(view, _first).categoryIds,
    firstAssigned ? categoryIds : isEmpty,
  );
  expect(
    _entry(view, _second).categoryIds,
    secondAssigned ? categoryIds : isEmpty,
  );
}

LibraryEntry _entry(LibraryView view, String title) =>
    view.entries.singleWhere((entry) => entry.title == title);

Finder _tile(String title) => find.widgetWithText(ListTile, title);

bool _tileShowsCategory(String title, String? categoryName) {
  final tile = _tile(title);
  if (tile.evaluate().length != 1) return false;
  return find
          .descendant(
            of: tile,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.data?.split('\n').last == '分类：$categoryName',
            ),
          )
          .evaluate()
          .length ==
      1;
}

Future<void> _expectShelf(
  WidgetTester tester, {
  String? categoryName,
  bool firstAssigned = false,
  bool secondAssigned = false,
}) => _waitFor(tester, '书架显示服务端确认的分类与收藏', () {
  if (find.byType(AlertDialog).evaluate().isNotEmpty) return false;
  for (final (title, assigned) in [
    (_first, firstAssigned),
    (_second, secondAssigned),
  ]) {
    final expected = assigned ? categoryName : '未分类';
    if (!_tileShowsCategory(title, expected)) return false;
  }
  return categoryName == null
      ? find.byType(ChoiceChip).evaluate().length == 2
      : find.widgetWithText(ChoiceChip, categoryName).evaluate().length == 1;
});

Future<void> _nameAndSave(WidgetTester tester, String name) async {
  final field = find.byType(TextFormField);
  await _waitFor(tester, '分类名称编辑框', () => field.evaluate().length == 1);
  await tester.enterText(field, name);
  await _tap(tester, find.text('保存'));
}

Future<void> _waitForManager(WidgetTester tester, String name) =>
    _waitFor(tester, '分类修改获得确认并返回管理窗口', () {
      final rename = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == '重命名分类 $name' &&
            widget.onPressed != null,
      );
      return find.byType(AlertDialog).evaluate().length == 1 &&
          rename.evaluate().length == 1;
    });

Future<void> _closeManager(WidgetTester tester) async {
  await _tap(tester, find.text('完成'));
  await _waitFor(
    tester,
    '关闭分类管理窗口',
    () => find.byType(AlertDialog).evaluate().isEmpty,
  );
}

Future<void> _assign(
  WidgetTester tester,
  String title,
  String categoryName,
) async {
  await _tap(tester, find.byTooltip('设置分类：$title'));
  final checkbox = find.widgetWithText(CheckboxListTile, categoryName);
  await _waitFor(tester, '漫画分类选择框', () => checkbox.evaluate().length == 1);
  expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
  await _tap(tester, checkbox);
  expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
  await _tap(tester, find.text('保存'));
  await _waitFor(
    tester,
    '漫画关联获得服务端确认',
    () => find.byType(AlertDialog).evaluate().isEmpty,
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

void _validateConfiguration() {
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
    fail('此正式分类同步验收仅适用于 Android 或 iOS 设备/模拟器');
  }
  if (_testCaBase64.isNotEmpty &&
      (!Platform.isAndroid || origin.host != '127.0.0.1')) {
    fail('CATEGORY_TEST_CA_BASE64 仅适用于 Android 的 HTTPS 127.0.0.1 验收');
  }
  if (!{
    'create',
    'update',
    'verify',
    'delete',
    'verify-deleted',
    'reorder',
    'delete-reordered',
    'verify-reordered-deleted',
  }.contains(_phase)) {
    fail(
      'CATEGORY_PHASE 须为 create/update/verify/delete/verify-deleted/'
      'reorder/delete-reordered/verify-reordered-deleted',
    );
  }
}
