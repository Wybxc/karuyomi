import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/manga_cover_tile.dart';
import 'package:karuyomi/theme/app_theme.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('cover opens and resumes independently at text scale $scale', (
      tester,
    ) async {
      var opened = 0;
      var resumed = 0;
      var selected = false;
      await tester.pumpWidget(
        CupertinoApp(
          theme: readerAppTheme(Brightness.dark),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: CupertinoPageScaffold(
              child: Center(
                child: SizedBox(
                  width: 160,
                  child: MangaCoverTile(
                    title: '一个很长的漫画标题，用来检查放大文字和独立续读操作',
                    onPressed: () => opened++,
                    onLongPress: () => selected = true,
                    onContinue: () => resumed++,
                    continueLabel: '继续阅读',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final resume = find.byIcon(CupertinoIcons.play_fill);
      final resumeButton = find.ancestor(
        of: resume,
        matching: find.byType(CupertinoButton),
      );
      final target = tester.getSize(resumeButton);
      expect(target.width, greaterThanOrEqualTo(44));
      expect(target.height, greaterThanOrEqualTo(44));
      await tester.tap(resume);
      expect(resumed, 1);
      expect(opened, 0);
      await tester.tap(find.byIcon(CupertinoIcons.book));
      expect(opened, 1);
      await tester.longPress(find.byIcon(CupertinoIcons.book));
      expect(selected, true);
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
