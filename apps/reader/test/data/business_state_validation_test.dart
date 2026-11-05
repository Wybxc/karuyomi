import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_validation.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

wire.LibraryMetadata metadata({String? memo, String url = '/manga/test'}) =>
    wire.LibraryMetadata(
      packageName: 'source.test',
      sourceId: '9007199254740993',
      sourceName: 'Test',
      sourceLang: 'en',
      manga: wire.Manga(url: url, title: 'Test', memoJson: memo),
    );

wire.MangaState manga(String digit) => wire.MangaState(
  mangaKey: sha256
      .convert(
        utf8.encode(
          jsonEncode(['source.test', '9007199254740993', '/manga/test/$digit']),
        ),
      )
      .toString(),
  revision: 1,
  metadata: metadata(url: '/manga/test/$digit'),
  favorite: true,
  addedAtSeconds: 2000000000,
);

wire.ReadingAnchor anchor({String chapterKey = 'chapter'}) =>
    wire.ReadingAnchor(
      chapterKey: chapterKey,
      pageKey: 'page',
      manifestVersion: 'manifest',
      normalizedOffset: 0.75,
      normalizedX: .2,
      viewportX: .6,
      viewportY: .8,
    );

wire.SettingsMutation favoriteSourceSettings(
  Iterable<wire.FavoriteSource> sources,
) => wire.SettingsMutation(
  schemaVersion: 1,
  setGlobal: wire.GlobalSettingsValues(
    theme: wire.AppTheme.APP_THEME_SYSTEM,
    reader: wire.ReaderSettings(
      mode: wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
      pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      background: wire.ReaderBackground.READER_BACKGROUND_BLACK,
      fit: wire.ReaderFit.READER_FIT_CONTAIN,
      tapZones: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
      keyboard: wire.ReaderInputPreset.READER_INPUT_PRESET_STANDARD,
    ),
    favoriteSources: sources,
  ),
);

void main() {
  test('business integers are exact uint32 values', () {
    for (final value in [0, 1, 0xffffffff]) {
      expect(() => validateBusinessRevision(value), returnsNormally);
    }
    for (final value in [-1, 0x100000000, 9007199254740993]) {
      expect(() => validateBusinessRevision(value), throwsFormatException);
    }
  });

  test(
    'metadata preserves opaque memo and bounds references, source IDs and bytes',
    () {
      const opaque = '{"large":9007199254740993,"decimal":123.4500}';
      final value = metadata(memo: opaque);
      validateBusinessMetadata(value);
      expect(value.manga.memoJson, opaque);
      final memo = jsonEncode({'payload': 'x' * (wire.sourceMemoLimit - 14)});
      expect(utf8.encode(memo).length, wire.sourceMemoLimit);
      expect(
        () => validateBusinessMetadata(metadata(memo: memo)),
        returnsNormally,
      );
      final invalid = <wire.LibraryMetadata>[
        metadata()..sourceId = '9223372036854775808',
        metadata()..sourceId = '-9223372036854775809',
        metadata()..sourceName = '',
        metadata()..sourceLang = '',
        metadata()..clearManga(),
        metadata()..manga.url = '',
        metadata()..manga.title = '',
        metadata()..manga.updateStrategy = 'UNKNOWN',
        metadata(memo: '[]'),
        metadata(memo: jsonEncode({'payload': 'x' * wire.sourceMemoLimit})),
        metadata()..manga.title = 'é' * (96 * 1024),
      ];
      for (final item in invalid) {
        expect(() => validateBusinessMetadata(item), throwsFormatException);
      }
    },
  );

  test(
    'progress accepts unresolved historical pages but rejects invalid anchors',
    () {
      final valid = wire.ChapterProgressState(
        chapterKey: 'chapter',
        current: anchor(),
        furthest: anchor()..manifestVersion = 'historical-manifest',
        epoch: 0xffffffff,
      );
      expect(
        () => validateBusinessProgress(valid, chapterKey: 'chapter'),
        returnsNormally,
      );
      expect(
        () => validateBusinessProgress(valid, chapterKey: 'other'),
        throwsFormatException,
      );
      for (final item in [
        valid.deepCopy()..clearCurrent(),
        valid.deepCopy()..current.chapterKey = 'other',
        valid.deepCopy()..furthest.chapterKey = 'other',
        valid.deepCopy()..current.normalizedOffset = double.nan,
        valid.deepCopy()..current.normalizedOffset = 1.01,
        valid.deepCopy()..current.normalizedX = -.1,
        valid.deepCopy()..current.normalizedX = double.infinity,
        valid.deepCopy()..current.viewportX = 1.1,
        valid.deepCopy()..current.viewportX = double.nan,
        valid.deepCopy()..current.viewportY = -.1,
        valid.deepCopy()..current.viewportY = double.negativeInfinity,
        valid.deepCopy()..current.pageIndexHint = 2048,
        valid.deepCopy()..current.pageKey = '',
      ]) {
        expect(() => validateBusinessProgress(item), throwsFormatException);
      }
    },
  );

  test(
    'manga responses require canonical identity and metadata for favorites',
    () {
      expect(() => validateBusinessManga(manga('a')), returnsNormally);
      expect(
        () => validateBusinessManga(wire.MangaState(mangaKey: 'a' * 64)),
        returnsNormally,
      );
      for (final item in [
        manga('a')..mangaKey = 'opaque',
        manga('a')..mangaKey = 'a' * 64,
        manga('a')..clearMetadata(),
        manga('a')..resume = wire.MangaResume(),
      ]) {
        expect(() => validateBusinessManga(item), throwsFormatException);
      }
    },
  );

  test(
    'library pages require one ordered bounded snapshot and explicit typed errors',
    () {
      final entries = [manga('a'), manga('b')]
        ..sort((a, b) => a.mangaKey.compareTo(b.mangaKey));
      final valid = wire.LibraryPageResponse(
        schemaVersion: 1,
        accountRevision: 2,
        categoryCatalog: wire.CategoryCatalog(),
        entries: entries,
        nextKey: entries.last.mangaKey,
      );
      expect(() => validateBusinessLibraryPage(valid), returnsNormally);
      for (final item in [
        valid.deepCopy()..schemaVersion = 2,
        valid.deepCopy()..clearCategoryCatalog(),
        valid.deepCopy()..categoryCatalog.revision = 3,
        valid.deepCopy()..entries.setAll(0, entries.reversed),
        valid.deepCopy()..entries.setAll(0, [entries.first, entries.first]),
        valid.deepCopy()..nextKey = 'c' * 64,
        valid.deepCopy()..entries.first.favorite = false,
        wire.LibraryPageResponse(
          schemaVersion: 1,
          entries: List.generate(9, (index) => manga('$index')),
        ),
        valid.deepCopy()
          ..error = wire.BusinessStateError(
            code: wire
                .BusinessStateErrorCode
                .BUSINESS_STATE_ERROR_CODE_UNAVAILABLE,
            message: 'Unavailable',
          ),
      ]) {
        expect(() => validateBusinessLibraryPage(item), throwsFormatException);
      }
      final failure = wire.LibraryPageResponse(
        schemaVersion: 1,
        error: wire.BusinessStateError(
          code: wire
              .BusinessStateErrorCode
              .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
          message: 'Library changed',
        ),
      );
      expect(() => validateBusinessLibraryPage(failure), returnsNormally);
      expect(
        () => validateBusinessError(
          wire.BusinessStateError(message: 'Unspecified error'),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'category catalogs enforce identities, UTF-8 names and association order',
    () {
      const first = '10000000-0000-4000-8000-000000000001';
      const second = '10000000-0000-4000-8000-000000000002';
      final catalog = wire.CategoryCatalog(
        revision: 2,
        categories: [
          wire.Category(id: first, name: '重复'),
          wire.Category(id: second, name: '重复'),
        ],
      );
      expect(() => validateBusinessCategoryCatalog(catalog), returnsNormally);
      expect(() => validateBusinessCategoryName('😀' * 64), returnsNormally);
      for (final name in ['', ' blank', 'blank ', 'a' * 101, '😀' * 65]) {
        expect(() => validateBusinessCategoryName(name), throwsFormatException);
      }
      for (final invalid in [
        catalog.deepCopy()..categories.last.id = first,
        catalog.deepCopy()
          ..categories.last.id = '10000000-0000-1000-8000-000000000002',
        catalog.deepCopy()..categories.last.name = ' invalid ',
        wire.CategoryCatalog(
          categories: List.generate(
            65,
            (i) => wire.Category(
              id: '10000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
              name: 'Category',
            ),
          ),
        ),
      ]) {
        expect(
          () => validateBusinessCategoryCatalog(invalid),
          throwsFormatException,
        );
      }
      final state = manga('a')..categoryIds.addAll([first, second]);
      expect(
        () => validateBusinessMangaCategories(state, catalog),
        returnsNormally,
      );
      state.categoryIds
        ..clear()
        ..addAll([second, first]);
      expect(
        () => validateBusinessMangaCategories(state, catalog),
        throwsFormatException,
      );
      state.categoryIds
        ..clear()
        ..add('10000000-0000-4000-8000-000000000003');
      expect(
        () => validateBusinessMangaCategories(state, catalog),
        throwsFormatException,
      );
    },
  );
  test(
    'favorite Sources retain signed identities and validate complete settings at both boundaries',
    () {
      final source = wire.FavoriteSource(
        packageName: 'source.test',
        sourceId: '9007199254740993',
        sourceName: 'Original 名称',
        sourceLang: 'zh-Hant',
      );
      final valid = [
        source,
        source.deepCopy()..packageName = 'source.other',
        source.deepCopy()..sourceId = '-9223372036854775808',
      ];
      wire.SettingsResponse response(Iterable<wire.FavoriteSource> sources) {
        final values = favoriteSourceSettings(sources).setGlobal;
        return wire.SettingsResponse(
          schemaVersion: 1,
          accountRevision: 1,
          global: wire.GlobalSettings(revision: 1, values: values),
          effectiveReader: values.reader.deepCopy(),
        );
      }

      final request = favoriteSourceSettings(valid);
      validateBusinessSettingsMutation(request);
      validateBusinessSettingsResponse(response(valid));
      expect(
        request.setGlobal.favoriteSources.map((item) => item.sourceId),
        valid.map((item) => item.sourceId),
      );
      final maximum = List.generate(
        128,
        (index) => source.deepCopy()..sourceId = '$index',
      );
      expect(
        () => validateBusinessSettingsMutation(favoriteSourceSettings(maximum)),
        returnsNormally,
      );
      for (final sources in [
        [
          source,
          source.deepCopy()
            ..sourceName = 'Duplicate identity with another label',
        ],
        [...maximum, source.deepCopy()..sourceId = '128'],
        ...[
          source.deepCopy()..packageName = '',
          source.deepCopy()..packageName = 'p' * 201,
          source.deepCopy()..sourceId = '',
          source.deepCopy()..sourceId = '9223372036854775808',
          source.deepCopy()..sourceId = '-9223372036854775809',
          source.deepCopy()..sourceId = '1.5',
          source.deepCopy()..sourceName = '',
          source.deepCopy()..sourceName = 'n' * 257,
          source.deepCopy()..sourceLang = '',
          source.deepCopy()..sourceLang = 'l' * 65,
        ].map((invalid) => [invalid]),
      ]) {
        expect(
          () =>
              validateBusinessSettingsMutation(favoriteSourceSettings(sources)),
          throwsFormatException,
        );
        expect(
          () => validateBusinessSettingsResponse(response(sources)),
          throwsFormatException,
        );
      }
      final oversized = maximum
          .map(
            (item) => item.deepCopy()
              ..packageName = '字' * 200
              ..sourceName = '字' * 256
              ..sourceLang = '字' * 64,
          )
          .toList();
      expect(
        () =>
            validateBusinessSettingsMutation(favoriteSourceSettings(oversized)),
        throwsFormatException,
      );
    },
  );
}
