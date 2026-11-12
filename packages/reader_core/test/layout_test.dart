import 'package:reader_core/reader_core.dart';
import 'package:test/test.dart';

ReaderPage portrait(String key) =>
    ReaderPage(key: key, width: 600, height: 900);
ChapterManifest chapter(List<ReaderPage> pages, {String version = '1'}) =>
    ChapterManifest(chapterKey: 'chapter', version: version, pages: pages);

void main() {
  test('learned content geometry controls spreads while original decode budgets remain intact', () {
    final cropped = ReaderPage(
      key: 'cropped',
      width: 1200,
      height: 600,
      contentAspectRatio: .8,
    );
    final manifest = chapter([portrait('cover'), cropped, portrait('next')]);
    expect(
      groupPages(
        manifest,
        doublePage: true,
      ).map((spread) => spread.pages.map((page) => page.key).toList()),
      [
        ['cover'],
        ['cropped', 'next'],
      ],
    );
    expect(cropped.originalAspectRatio, 2);
    expect(cropped.estimatedDecodedBytes, 1200 * 600 * 4);
    for (final ratio in [0.0, -1.0, double.infinity, double.nan]) {
      expect(
        () => ReaderPage(key: 'invalid', contentAspectRatio: ratio),
        throwsArgumentError,
      );
    }
  });

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
        initialPosition: manifest.positionAt(
          4,
          offset: 0.6,
          normalizedX: .7,
          viewportX: .3,
          viewportY: .8,
        ),
      );
      controller.setLayout(mode: ReadingMode.rightToLeft, doublePage: true);
      expect(controller.position!.pageKey, '4');
      expect(controller.position!.normalizedOffset, 0.6);
      expect(controller.position!.normalizedX, .7);
      expect(controller.position!.viewportX, .3);
      expect(controller.position!.viewportY, .8);
      expect(
        controller.spreads[controller.spreadIndex].pages.map((p) => p.key),
        ['3', '4'],
      );
      controller.advance();
      expect(controller.position!.pageKey, '5');
      expect(controller.position!.normalizedX, 0);
      expect(controller.position!.viewportX, 0);
      expect(controller.position!.viewportY, 0);
      controller.back();
      expect(controller.position!.pageKey, '3');
      controller.setLayout(mode: ReadingMode.webtoon);
      expect(controller.spreads.every((s) => s.pages.length == 1), isTrue);
      expect(controller.position!.pageKey, '3');
      controller.updateViewportAnchor(
        3,
        offset: .2,
        normalizedX: .6,
        viewportX: .4,
        viewportY: .5,
      );
      controller.setLayout(mode: ReadingMode.continuous);
      expect(controller.position!.normalizedX, .6);
      expect(controller.position!.viewportX, .4);
      expect(controller.position!.viewportY, .5);
      controller.goToPage(3);
      expect(controller.position!.normalizedOffset, 0);
      expect(controller.position!.normalizedX, 0);
      expect(controller.position!.viewportX, 0);
      expect(controller.position!.viewportY, 0);
      await controller.dispose();
    },
  );

  test('manifest revision reorders by identity and explicitly reports missing pages', () {
    final old = chapter([portrait('a'), portrait('b'), portrait('c')]);
    final reordered = chapter([
      portrait('c'),
      portrait('a'),
      portrait('b'),
    ], version: '2');
    final exact = resolvePosition(
      reordered,
      old.positionAt(
        1,
        offset: 0.4,
        normalizedX: .8,
        viewportX: .6,
        viewportY: .2,
      ),
    );
    expect(exact.kind, PositionResolutionKind.exactPage);
    expect(exact.position!.pageIndexHint, 2);
    expect(exact.position!.normalizedOffset, 0.4);
    expect(exact.position!.normalizedX, .8);
    expect(exact.position!.viewportX, .6);
    expect(exact.position!.viewportY, .2);
    expect(exact.position!.manifestVersion, '2');
    final removed = resolvePosition(
      chapter([portrait('a')]),
      old.positionAt(2),
    );
    expect(removed.requiresNotice, isTrue);
    expect(removed.position!.pageKey, 'a');
  });

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
