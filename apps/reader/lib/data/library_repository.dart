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

final class LibraryRepository {
  LibraryRepository(this.client);
  final BusinessStateClient client;
  ProgressIdentity get identity => client.identity;

  Stream<List<LibraryEntry>> watchEntries() => client.watchLibrary().map(
    (values) => List.unmodifiable(values.map(_entry)),
  );

  Stream<bool> watchFavorite(String mangaKey) => client
      .watchManga(mangaKey)
      .map((state) => state?.favorite ?? false)
      .distinct();

  Future<bool> contains(String mangaKey) async =>
      (await client.readManga(mangaKey)).manga.favorite;

  Future<void> refresh() => client.refreshLibrary();

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
