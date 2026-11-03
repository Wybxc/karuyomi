import 'package:reader_core/reader_core.dart';
import 'package:test/test.dart';

ReaderPage portrait(String key) =>
    ReaderPage(key: key, width: 600, height: 900);
ChapterManifest chapter(List<ReaderPage> pages, {String version = '1'}) =>
    ChapterManifest(chapterKey: 'chapter', version: version, pages: pages);

void main() {
  test(
    'cover and landscape are alone; portrait spreads preserve source order',
    () {
      final manifest = chapter([
        portrait('cover'),
        portrait('1'),
        portrait('2'),
        portrait('3'),
        ReaderPage(key: 'wide', width: 1200, height: 600),
        portrait('4'),
        portrait('5'),
        portrait('6'),
      ]);
      final groups = groupPages(manifest, doublePage: true);
      expect(groups.map((g) => g.pages.map((p) => p.key).toList()), [
        ['cover'],
        ['1', '2'],
        ['3'],
        ['wide'],
        ['4', '5'],
        ['6'],
      ]);
      expect(
        groups[1].displayPages(ReadingMode.rightToLeft).map((p) => p.key),
        ['2', '1'],
      );
      expect(manifest.pages.map((p) => p.key), [
        'cover',
        '1',
        '2',
        '3',
        'wide',
        '4',
        '5',
        '6',
      ]);
    },
  );

  test(
    'layout switches retain the exact current page and normalized anchor',
    () async {
      final manifest = chapter(List.generate(8, (i) => portrait('$i')));
      final controller = ReaderController(
        manifest: manifest,
        initialPosition: manifest.positionAt(4, offset: 0.6),
      );
      controller.setLayout(mode: ReadingMode.rightToLeft, doublePage: true);
      expect(controller.position!.pageKey, '4');
      expect(controller.position!.normalizedOffset, 0.6);
      expect(
        controller.spreads[controller.spreadIndex].pages.map((p) => p.key),
        ['3', '4'],
      );
      controller.advance();
      expect(controller.position!.pageKey, '5');
      controller.back();
      expect(controller.position!.pageKey, '3');
      controller.setLayout(mode: ReadingMode.webtoon);
      expect(controller.spreads.every((s) => s.pages.length == 1), isTrue);
      expect(controller.position!.pageKey, '3');
      await controller.dispose();
    },
  );

  test(
    'manifest revision reorders by identity and explicitly reports missing pages',
    () {
      final old = chapter([portrait('a'), portrait('b'), portrait('c')]);
      final reordered = chapter([
        portrait('c'),
        portrait('a'),
        portrait('b'),
      ], version: '2');
      final exact = resolvePosition(reordered, old.positionAt(1, offset: 0.4));
      expect(exact.kind, PositionResolutionKind.exactPage);
      expect(exact.position!.pageIndexHint, 2);
      expect(exact.position!.normalizedOffset, 0.4);
      expect(exact.position!.manifestVersion, '2');
      final removed = resolvePosition(
        chapter([portrait('a')]),
        old.positionAt(2),
      );
      expect(removed.requiresNotice, isTrue);
      expect(removed.position!.pageKey, 'a');
    },
  );

  test(
    'empty chapter has no position and duplicate page keys are rejected',
    () async {
      final controller = ReaderController(manifest: chapter([]));
      expect(controller.position, isNull);
      expect(controller.imageWindow(), isEmpty);
      controller.advance();
      expect(controller.canAdvance, isFalse);
      expect(
        () => chapter([portrait('same'), portrait('same')]),
        throwsArgumentError,
      );
      await controller.dispose();
    },
  );
}
