import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_client.dart';
import 'business_state_validation.dart';
import 'reading_progress.dart';

String _mangaKey(String packageName, String sourceId, String mangaUrl) => sha256
    .convert(utf8.encode(jsonEncode([packageName, sourceId, mangaUrl])))
    .toString();

/// A confirmed server favorite. Builds and generations are excluded from its
/// stable identity; the full Source snapshot retains its opaque memo text.
final class LibraryEntry {
  LibraryEntry({
    required this.packageName,
    required this.sourceId,
    required this.sourceName,
    required this.sourceLang,
    required wire.Manga manga,
    required this.addedAt,
    List<String> categoryIds = const [],
    this.revision = 0,
    wire.CustomCover? customCover,
    this.resume,
  }) : customCover = customCover == null
           ? null
           : (customCover.deepCopy()..freeze()),
       snapshot = manga.deepCopy()..freeze(),
       categoryIds = List.unmodifiable(categoryIds) {
    _validateMetadata(packageName, sourceId, sourceName, sourceLang, snapshot);
    validateBusinessCategoryIds(this.categoryIds);
    validateBusinessRevision(revision);
    if (resume != null) validateBusinessChapterKey(resume!.chapterKey);
    if (this.customCover != null) {
      validateBusinessCustomCover(this.customCover!);
    }
  }

  final String packageName;
  final String sourceId;
  final String sourceName;
  final String sourceLang;
  final wire.Manga snapshot;
  final DateTime addedAt;
  final List<String> categoryIds;
  final int revision;
  final wire.CustomCover? customCover;
  final MangaResume? resume;
  String get mangaKey => _mangaKey(packageName, sourceId, snapshot.url);
  String get title => snapshot.title;
  String get url => snapshot.url;
}

final class LibraryCategory {
  const LibraryCategory({required this.id, required this.name});
  final String id;
  final String name;
}

final class LibraryView {
  LibraryView({
    required List<LibraryEntry> entries,
    required List<LibraryCategory> categories,
    required this.categoryRevision,
  }) : entries = List.unmodifiable(entries),
       categories = List.unmodifiable(categories);
  final List<LibraryEntry> entries;
  final List<LibraryCategory> categories;
  final int categoryRevision;
}

final class LibraryRepository {
  LibraryRepository(this.client);
  final BusinessStateClient client;
  ProgressIdentity get identity => client.identity;

  Stream<LibraryView> watchView() => client.watchLibrarySnapshot().map(
    (view) => LibraryView(
      entries: view.entries.map(_entry).toList(),
      categories: view.categoryCatalog.categories
          .map(
            (category) => LibraryCategory(id: category.id, name: category.name),
          )
          .toList(),
      categoryRevision: view.categoryCatalog.revision,
    ),
  );

  Stream<List<LibraryEntry>> watchEntries() =>
      watchView().map((view) => view.entries);

  Stream<bool> watchFavorite(String mangaKey) => client
      .watchManga(mangaKey)
      .map((state) => state?.favorite ?? false)
      .distinct();

  Future<bool> contains(String mangaKey) async =>
      (await client.readManga(mangaKey)).manga.favorite;

  Future<void> refresh() => client.refreshLibrary();

  Future<void> createCategory({
    required String categoryId,
    required String name,
    required int expectedRevision,
  }) async {
    await client.mutateCategories(
      wire.CategoryMutation(
        expectedRevision: expectedRevision,
        createCategory: wire.CreateCategory(
          category: wire.Category(id: categoryId, name: name.trim()),
        ),
      ),
    );
  }

  Future<void> renameCategory({
    required String categoryId,
    required String name,
    required int expectedRevision,
  }) async {
    await client.mutateCategories(
      wire.CategoryMutation(
        expectedRevision: expectedRevision,
        renameCategory: wire.RenameCategory(
          categoryId: categoryId,
          name: name.trim(),
        ),
      ),
    );
  }

  Future<void> reorderCategories({
    required List<String> categoryIds,
    required int expectedRevision,
  }) async {
    await client.mutateCategories(
      wire.CategoryMutation(
        expectedRevision: expectedRevision,
        reorderCategories: wire.ReorderCategories(categoryIds: categoryIds),
      ),
    );
  }

  Future<void> deleteCategory({
    required String categoryId,
    required int expectedRevision,
  }) async {
    await client.mutateCategories(
      wire.CategoryMutation(
        expectedRevision: expectedRevision,
        deleteCategory: wire.DeleteCategory(categoryId: categoryId),
      ),
    );
  }

  Future<void> setCategories({
    required String mangaKey,
    required List<String> categoryIds,
    required int expectedCatalogRevision,
    required int expectedMangaRevision,
  }) async {
    validateBusinessCategoryIds(categoryIds);
    validateBusinessRevision(expectedCatalogRevision);
    validateBusinessRevision(expectedMangaRevision);
    await client.mutate(
      wire.StateMutation(
        mangaKey: mangaKey,
        setCategories: wire.SetCategories(
          categoryIds: categoryIds,
          expectedCatalogRevision: expectedCatalogRevision,
        ),
      ),
      basedOnRevision: expectedMangaRevision,
      requireExactRevision: true,
    );
  }

  /// Remove a confirmed shelf entry without replacing its Source metadata.
  Future<void> removeFavorite({
    required String mangaKey,
    required int expectedMangaRevision,
  }) async {
    validateBusinessRevision(expectedMangaRevision);
    await client.mutate(
      wire.StateMutation(
        mangaKey: mangaKey,
        setFavorite: wire.SetFavorite(favorite: false),
      ),
      basedOnRevision: expectedMangaRevision,
      requireExactRevision: true,
    );
  }

  Future<void> setFavorite({
    required String packageName,
    required String sourceId,
    required String sourceName,
    required String sourceLang,
    required wire.Manga manga,
    required bool favorite,
  }) async {
    final metadata = _metadata(
      packageName,
      sourceId,
      sourceName,
      sourceLang,
      manga,
    );
    await client.mutate(
      wire.StateMutation(
        mangaKey: _mangaKey(packageName, sourceId, manga.url),
        setFavorite: wire.SetFavorite(metadata: metadata, favorite: favorite),
      ),
    );
  }

  /// A detail refresh updates server metadata without implicitly favoriting it.
  Future<void> refreshMetadata({
    required String packageName,
    required String sourceId,
    required String sourceName,
    required String sourceLang,
    required wire.Manga manga,
  }) async {
    final metadata = _metadata(
      packageName,
      sourceId,
      sourceName,
      sourceLang,
      manga,
    );
    await client.mutate(
      wire.StateMutation(
        mangaKey: _mangaKey(packageName, sourceId, manga.url),
        updateMetadata: metadata,
      ),
      allowPendingReplay: false,
    );
  }
}

LibraryEntry _entry(wire.MangaState state) {
  final metadata = state.metadata;
  final entry = LibraryEntry(
    packageName: metadata.packageName,
    sourceId: metadata.sourceId,
    sourceName: metadata.sourceName,
    sourceLang: metadata.sourceLang,
    manga: metadata.manga,
    addedAt: DateTime.fromMillisecondsSinceEpoch(
      state.addedAtSeconds * 1000,
      isUtc: true,
    ),
    categoryIds: state.categoryIds,
    revision: state.revision,
    customCover: state.hasCustomCover() ? state.customCover : null,
    resume: state.hasResume()
        ? MangaResume(
            chapterKey: state.resume.chapterKey,
            reversedOrder: state.resume.reversedOrder,
          )
        : null,
  );
  if (entry.mangaKey != state.mangaKey) {
    throw const FormatException('Library metadata identity mismatch');
  }
  return entry;
}

wire.LibraryMetadata _metadata(
  String packageName,
  String sourceId,
  String sourceName,
  String sourceLang,
  wire.Manga manga,
) {
  _validateMetadata(packageName, sourceId, sourceName, sourceLang, manga);
  final result = wire.LibraryMetadata(
    packageName: packageName,
    sourceId: sourceId,
    sourceName: sourceName,
    sourceLang: sourceLang,
    manga: manga.deepCopy(),
  );
  validateBusinessMetadata(result);
  return result;
}

void _validateMetadata(
  String packageName,
  String sourceId,
  String sourceName,
  String sourceLang,
  wire.Manga manga,
) {
  if (packageName.isEmpty ||
      sourceId.isEmpty ||
      sourceName.isEmpty ||
      sourceLang.isEmpty ||
      manga.title.isEmpty ||
      manga.url.isEmpty) {
    throw const FormatException(
      'Library metadata requires a Source and manga identity',
    );
  }
  if (manga.memoJson.isNotEmpty) wire.checkSourceMemo(manga.memoJson);
}
