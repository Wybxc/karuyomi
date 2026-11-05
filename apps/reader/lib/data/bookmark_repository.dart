import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_client.dart';
import 'business_state_validation.dart';
import 'reading_progress.dart';

final class BookmarkSnapshot {
  const BookmarkSnapshot({
    required this.revision,
    required this.chapterKey,
    required this.bookmarked,
  });
  final int revision;
  final String chapterKey;
  final bool bookmarked;
}

final class MangaBookmarksSnapshot {
  MangaBookmarksSnapshot({
    required this.revision,
    required this.accountRevision,
    required Set<String> chapterKeys,
  }) : chapterKeys = Set.unmodifiable(chapterKeys);
  final int revision;
  final int accountRevision;
  final Set<String> chapterKeys;
}

/// A session command whose UUID, body and actual CAS remain with the client.
final class BookmarkDraft {
  const BookmarkDraft({
    required this.chapterKey,
    required this.bookmarked,
    required this.basedOnRevision,
    required this.retryable,
  });
  final String chapterKey;
  final bool bookmarked;
  final int basedOnRevision;
  final bool retryable;
}

final class BookmarkRepository {
  BookmarkRepository(this.client);
  final BusinessStateClient client;
  ProgressIdentity get identity => client.identity;

  BookmarkDraft? pending(String mangaKey) {
    final value = client.pendingBookmark(mangaKey);
    return value == null
        ? null
        : BookmarkDraft(
            chapterKey: value.chapterKey,
            bookmarked: value.bookmarked,
            basedOnRevision: value.basedOnRevision,
            retryable: value.retryable,
          );
  }

  Future<BookmarkSnapshot> loadChapter({
    required String mangaKey,
    required String chapterKey,
  }) async {
    validateBusinessChapterKey(chapterKey);
    final value = await client.readManga(mangaKey, chapterKey: chapterKey);
    return _snapshot(value.manga, value.bookmark);
  }

  Future<MangaBookmarksSnapshot> loadAll(String mangaKey) async {
    final value = await client.readBookmarks(mangaKey);
    return MangaBookmarksSnapshot(
      revision: value.manga.revision,
      accountRevision: value.accountRevision,
      chapterKeys: value.entries.map((entry) => entry.chapterKey).toSet(),
    );
  }

  Future<BookmarkSnapshot> set({
    required String mangaKey,
    required String chapterKey,
    required bool bookmarked,
    required int basedOnRevision,
  }) async {
    validateBusinessChapterKey(chapterKey);
    validateBusinessRevision(basedOnRevision);
    final value = await client.mutate(
      wire.StateMutation(
        mangaKey: mangaKey,
        setBookmark: wire.SetBookmark(
          chapterKey: chapterKey,
          bookmarked: bookmarked,
        ),
      ),
      basedOnRevision: basedOnRevision,
    );
    if (!value.hasBookmark()) {
      throw const FormatException('Missing confirmed chapter bookmark');
    }
    return _snapshot(value.manga, value.bookmark);
  }
}

BookmarkSnapshot _snapshot(
  wire.MangaState manga,
  wire.ChapterBookmark bookmark,
) {
  validateBusinessBookmark(bookmark);
  return BookmarkSnapshot(
    revision: manga.revision,
    chapterKey: bookmark.chapterKey,
    bookmarked: bookmark.bookmarked,
  );
}
