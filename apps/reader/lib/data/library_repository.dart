import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'reader_database.dart';
import 'reading_progress.dart';

String _mangaKey(String packageName, String sourceId, String mangaUrl) => sha256
    .convert(utf8.encode(jsonEncode([packageName, sourceId, mangaUrl])))
    .toString();

/// Local metadata and an explicit favorite, scoped to a confirmed identity.
/// Builds and runtime generations are deliberately excluded from manga identity.
final class LibraryEntry {
  LibraryEntry({
    required this.packageName,
    required this.sourceId,
    required this.sourceName,
    required this.sourceLang,
    required wire.Manga manga,
    required this.addedAt,
  }) : snapshot = manga.deepCopy()..freeze() {
    _validateMetadata(packageName, sourceId, sourceName, sourceLang, snapshot);
  }

  final String packageName;
  final String sourceId;
  final String sourceName;
  final String sourceLang;
  final wire.Manga snapshot;
  final DateTime addedAt;
  String get mangaKey => _mangaKey(packageName, sourceId, snapshot.url);
  String get title => snapshot.title;
  String get url => snapshot.url;
}

/// P1 local favorites only. D1 business state and the P2 outbox are separate
/// work; these rows must not be presented as already synchronized cloud state.
final class LibraryRepository {
  LibraryRepository(this.database, this.identity, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final ReaderDatabase database;
  final ProgressIdentity identity;
  final DateTime Function() _now;

  Stream<List<LibraryEntry>> watchEntries() {
    final favorites = database.libraryFavoriteRows;
    final manga = database.libraryMangaRows;
    final query =
        database.select(favorites).join([
            innerJoin(
              manga,
              manga.identityKey.equalsExp(favorites.identityKey) &
                  manga.mangaKey.equalsExp(favorites.mangaKey),
            ),
          ])
          ..where(favorites.identityKey.equals(identity.key))
          ..orderBy([
            OrderingTerm.desc(favorites.addedAt),
            OrderingTerm.asc(favorites.mangaKey),
          ]);
    return query.watch().map(
      (rows) => List.unmodifiable(
        rows.map((row) {
          final metadata = row.readTable(manga);
          return LibraryEntry(
            packageName: metadata.packageName,
            sourceId: metadata.sourceId,
            sourceName: metadata.sourceName,
            sourceLang: metadata.sourceLang,
            manga: wire.decodeProtoJson(
              wire.Manga(),
              jsonDecode(metadata.mangaJson),
            ),
            addedAt: row.readTable(favorites).addedAt,
          );
        }),
      ),
    );
  }

  Stream<bool> watchFavorite(String mangaKey) =>
      _favorite(mangaKey).watchSingleOrNull().map((row) => row != null);

  Future<bool> contains(String mangaKey) async =>
      await _favorite(mangaKey).getSingleOrNull() != null;

  SimpleSelectStatement<$LibraryFavoriteRowsTable, LibraryFavoriteRow>
  _favorite(String mangaKey) => database.select(database.libraryFavoriteRows)
    ..where(
      (row) =>
          row.identityKey.equals(identity.key) & row.mangaKey.equals(mangaKey),
    );

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
    await database.transaction(() async {
      if (favorite) {
        await database
            .into(database.libraryMangaRows)
            .insertOnConflictUpdate(metadata);
        // Updating metadata or repeating an add must not reorder the shelf.
        await database
            .into(database.libraryFavoriteRows)
            .insert(
              LibraryFavoriteRowsCompanion.insert(
                identityKey: identity.key,
                mangaKey: metadata.mangaKey.value,
                addedAt: _now().toUtc(),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      } else {
        await (database.delete(database.libraryFavoriteRows)..where(
              (row) =>
                  row.identityKey.equals(identity.key) &
                  row.mangaKey.equals(metadata.mangaKey.value),
            ))
            .go();
      }
    });
  }

  /// Refreshing a detail never implicitly favorites it or creates shelf rows.
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
    await (database.update(database.libraryMangaRows)..where(
          (row) =>
              row.identityKey.equals(identity.key) &
              row.mangaKey.equals(metadata.mangaKey.value),
        ))
        .write(metadata);
  }

  LibraryMangaRowsCompanion _metadata(
    String packageName,
    String sourceId,
    String sourceName,
    String sourceLang,
    wire.Manga manga,
  ) {
    _validateMetadata(packageName, sourceId, sourceName, sourceLang, manga);
    return LibraryMangaRowsCompanion.insert(
      identityKey: identity.key,
      mangaKey: _mangaKey(packageName, sourceId, manga.url),
      packageName: packageName,
      sourceId: sourceId,
      sourceName: sourceName,
      sourceLang: sourceLang,
      mangaJson: jsonEncode(wire.encodeProtoJson(manga)),
    );
  }
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
}
