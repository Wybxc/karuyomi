import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/library/library_page.dart';
import 'package:karuyomi/main.dart' as app;

Future<CatalogController> startNativeApp(WidgetTester tester) async {
  app.main();
  final elapsed = Stopwatch()..start();
  final shelf = find.byType(LibraryPage);
  while (elapsed.elapsed < const Duration(seconds: 5)) {
    await tester.pump(const Duration(milliseconds: 50));
    if (shelf.evaluate().length != 1) continue;
    final catalog = tester.widget<LibraryPage>(shelf).controller;
    if (catalog != null) return catalog;
  }
  fail('正式 App 未在本机服务地址恢复后创建 CatalogController');
}
