import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_client.dart';
import 'business_state_validation.dart';

const migrationChapterLimit = businessMigrationChapterLimit;
typedef MigrationDraft = BusinessMigrationDraft;

final class MigrationPreview {
  MigrationPreview({
    required wire.MangaState source,
    required wire.MangaState target,
    required wire.CategoryCatalog categories,
    required wire.LibraryMetadata targetMetadata,
    required Map<String, wire.ChapterProgressState> sourceProgress,
    required Map<String, wire.ChapterProgressState> targetProgress,
    required Set<String> sourceBookmarks,
    required Set<String> targetBookmarks,
  }) : source = source.deepCopy()..freeze(),
       target = target.deepCopy()..freeze(),
       categories = categories.deepCopy()..freeze(),
       targetMetadata = targetMetadata.deepCopy()..freeze(),
       sourceProgress = Map.unmodifiable({
         for (final entry in sourceProgress.entries)
           entry.key: entry.value.deepCopy()..freeze(),
       }),
       targetProgress = Map.unmodifiable({
         for (final entry in targetProgress.entries)
           entry.key: entry.value.deepCopy()..freeze(),
       }),
       sourceBookmarks = Set.unmodifiable(sourceBookmarks),
       targetBookmarks = Set.unmodifiable(targetBookmarks);
  final wire.MangaState source;
  final wire.MangaState target;
  final wire.CategoryCatalog categories;
  final wire.LibraryMetadata targetMetadata;
  final Map<String, wire.ChapterProgressState> sourceProgress;
  final Map<String, wire.ChapterProgressState> targetProgress;
  final Set<String> sourceBookmarks;
  final Set<String> targetBookmarks;
  String get sourceKey => source.mangaKey;
  String get targetKey => target.mangaKey;
}

/// Read-only preview followed by one explicitly confirmed atomic operation.
final class MigrationRepository {
  MigrationRepository(this.client);
  final BusinessStateClient client;

  MigrationDraft? pending(String sourceKey) =>
      client.pendingMigration(sourceKey);

  Future<MigrationPreview> preview({
    required String sourceKey,
    required wire.LibraryMetadata targetMetadata,
    bool Function()? shouldContinue,
  }) async {
    void checkCurrent() {
      if (shouldContinue?.call() == false) throw StateError('迁移页面已关闭。');
    }

    checkCurrent();
    validateBusinessMetadata(targetMetadata);
    final targetKey = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              targetMetadata.packageName,
              targetMetadata.sourceId,
              targetMetadata.manga.url,
            ]),
          ),
        )
        .toString();
    client.checkMigrationAvailable(sourceKey, targetKey);
    // Each paged read is complete at one account revision. Equal manga CAS
    // values below prove the source's two lists came from the same state.
    final sourceProgress = await client.readChapterProgress(
      sourceKey,
      shouldContinue: shouldContinue,
      updateSession: false,
    );
    checkCurrent();
    final sourceBookmarks = await client.readBookmarks(
      sourceKey,
      shouldContinue: shouldContinue,
      updateSession: false,
    );
    checkCurrent();
    final source = await client.readManga(
      sourceKey,
      shouldContinue: shouldContinue,
      updateSession: false,
    );
    checkCurrent();
    final targetProgress = await client.readChapterProgress(
      targetKey,
      shouldContinue: shouldContinue,
      updateSession: false,
    );
    checkCurrent();
    final targetBookmarks = await client.readBookmarks(
      targetKey,
      shouldContinue: shouldContinue,
      updateSession: false,
    );
    checkCurrent();
    final target = await client.readManga(
      targetKey,
      shouldContinue: shouldContinue,
      updateSession: false,
    );
    checkCurrent();
    client.checkMigrationAvailable(sourceKey, targetKey);
    if (!source.manga.hasMetadata()) {
      throw const FormatException('请先将原作品加入书架，再开始迁移。');
    }
    if (sourceProgress.manga.revision != source.manga.revision ||
        sourceBookmarks.manga.revision != source.manga.revision ||
        targetProgress.manga.revision != target.manga.revision ||
        targetBookmarks.manga.revision != target.manga.revision ||
        source.categoryCatalog.revision != target.categoryCatalog.revision) {
      throw const FormatException('迁移资料读取期间发生变化，请重新预览。');
    }
    return MigrationPreview(
      source: source.manga,
      target: target.manga,
      categories: source.categoryCatalog,
      targetMetadata: targetMetadata,
      sourceProgress: {
        for (final entry in sourceProgress.entries) entry.chapterKey: entry,
      },
      targetProgress: {
        for (final entry in targetProgress.entries) entry.chapterKey: entry,
      },
      sourceBookmarks: sourceBookmarks.entries
          .map((entry) => entry.chapterKey)
          .toSet(),
      targetBookmarks: targetBookmarks.entries
          .map((entry) => entry.chapterKey)
          .toSet(),
    );
  }

  Future<wire.StateMutationResponse> commit(
    MigrationPreview preview, {
    required Iterable<wire.ChapterMigration> chapters,
    bool copyCategories = true,
    bool Function()? shouldContinue,
  }) {
    final selected = chapters
        .map((entry) => entry.deepCopy()..freeze())
        .toList();
    if (selected.length > migrationChapterLimit) {
      throw const FormatException('每次最多明确选择256组章节映射，请减少所选项。');
    }
    // Recheck selected facts against the displayed immutable preview, never
    // turn missing/failed state reads into an assumed unread chapter.
    for (final entry in selected) {
      if ((entry.copyRead &&
              (preview.sourceProgress[entry.sourceChapterKey]?.completed !=
                      true ||
                  preview.targetProgress.containsKey(
                    entry.targetChapterKey,
                  ))) ||
          (entry.copyBookmark &&
              (!preview.sourceBookmarks.contains(entry.sourceChapterKey) ||
                  preview.targetBookmarks.contains(entry.targetChapterKey)))) {
        throw const FormatException('所选标记与迁移预览不一致，请重新确认。');
      }
    }
    return client.migrateFrom(
      targetKey: preview.targetKey,
      targetRevision: preview.target.revision,
      shouldContinue: shouldContinue,
      operation: wire.MigrateFrom(
        sourceMangaKey: preview.sourceKey,
        expectedSourceRevision: preview.source.revision,
        expectedCatalogRevision: preview.categories.revision,
        targetMetadata: preview.targetMetadata,
        copyCategories: copyCategories,
        chapters: selected,
      ),
    );
  }

  Future<wire.StateMutationResponse> retry(
    String sourceKey, {
    bool Function()? shouldContinue,
  }) => client.retryMigration(sourceKey, shouldContinue: shouldContinue);
  void discardRejected(String sourceKey) =>
      client.discardRejectedMigration(sourceKey);
}
