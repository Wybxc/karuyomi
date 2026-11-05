import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/catalog_controller.dart';
import 'chapter_sequence.dart';

/// Local, one-shot navigation state for an explicitly requested Access login.
/// Original DTO snapshots are retained; URLs are never used to bypass Source.
final class ReaderRecoveryContext {
  const ReaderRecoveryContext({
    required this.origin,
    required this.subject,
    required this.packageName,
    required this.sourceId,
    required this.manga,
    required this.chapterKey,
    required this.position,
    required this.order,
    required this.mode,
    this.doublePage,
  });

  final String origin;
  final String subject;
  final String packageName;
  final String sourceId;
  final wire.Manga manga;
  final String chapterKey;
  final ReadingPosition? position;
  final ChapterOrder order;
  final ReadingMode mode;
  final bool? doublePage;

  Map<String, Object?> toJson() => {
    'origin': origin,
    'subject': subject,
    'packageName': packageName,
    'sourceId': sourceId,
    'manga': wire.encodeProtoJson(manga),
    'chapterKey': chapterKey,
    'order': order.name,
    'mode': mode.name,
    if (doublePage != null) 'doublePage': doublePage,
    if (position case final anchor?)
      'position': {
        'chapterKey': anchor.chapterKey,
        'pageKey': anchor.pageKey,
        'manifestVersion': anchor.manifestVersion,
        'pageIndexHint': anchor.pageIndexHint,
        'normalizedOffset': anchor.normalizedOffset,
        'normalizedX': anchor.normalizedX,
        'viewportX': anchor.viewportX,
        'viewportY': anchor.viewportY,
      },
  };

  factory ReaderRecoveryContext.fromJson(Object? value) {
    wire.checkJsonBudget(value, maxBytes: wire.controlRequestLimit);
    if (value
        case {
          'origin': final String origin,
          'subject': final String subject,
          'packageName': final String packageName,
          'sourceId': final String sourceId,
          'manga': final Object manga,
          'chapterKey': final String chapterKey,
          'order': final String order,
          'mode': final String mode,
        }
        when origin.isNotEmpty &&
            subject.isNotEmpty &&
            packageName.isNotEmpty &&
            sourceId.isNotEmpty &&
            chapterKey.isNotEmpty &&
            ChapterOrder.values.any((item) => item.name == order) &&
            ReadingMode.values.any((item) => item.name == mode)) {
      final doublePage = value['doublePage'];
      if (doublePage != null && doublePage is! bool) {
        throw const FormatException('阅读恢复布局无效');
      }
      ReadingPosition? position;
      if (value['position'] case final Object anchor) {
        if (anchor case {
          'chapterKey': final String anchorChapter,
          'pageKey': final String pageKey,
          'manifestVersion': final String version,
          'pageIndexHint': final int index,
          'normalizedOffset': final num offset,
          'normalizedX': final num normalizedX,
          'viewportX': final num viewportX,
          'viewportY': final num viewportY,
        } when anchorChapter == chapterKey) {
          position = ReadingPosition(
            chapterKey: anchorChapter,
            pageKey: pageKey,
            manifestVersion: version,
            pageIndexHint: index,
            normalizedOffset: offset.toDouble(),
            normalizedX: normalizedX.toDouble(),
            viewportX: viewportX.toDouble(),
            viewportY: viewportY.toDouble(),
          );
        } else {
          throw const FormatException('阅读恢复位置无效');
        }
      }
      return ReaderRecoveryContext(
        origin: origin,
        subject: subject,
        packageName: packageName,
        sourceId: sourceId,
        manga: wire.decodeProtoJson(wire.Manga(), manga)..freeze(),
        chapterKey: chapterKey,
        position: position,
        order: ChapterOrder.values.byName(order),
        mode: ReadingMode.values.byName(mode),
        doublePage: doublePage is bool ? doublePage : null,
      );
    }
    throw const FormatException('阅读恢复状态无效');
  }
}

typedef ReaderAuthentication = Future<bool> Function(ReaderRecoveryContext);

final class RecoveredReader {
  const RecoveredReader({
    required this.manga,
    required this.sequence,
    required this.chapter,
    required this.source,
    required this.opened,
    required this.position,
  });

  final MangaEntry manga;
  final ChapterSequence sequence;
  final SequenceChapter chapter;
  final CatalogSourceRef source;
  final OpenedChapter opened;
  final ReadingPosition? position;
}

/// Runs only after an explicit user action and a fresh bootstrap. It starts new
/// Source operations for this chapter, never replays failed calls or old POSTs.
Future<RecoveredReader?> recoverReader(
  CatalogController catalog,
  ReaderRecoveryContext context, {
  bool Function()? isCurrent,
}) async {
  if (catalog.status != ServiceStatus.ready ||
      catalog.subject != context.subject ||
      catalog.deploymentOrigin?.origin != context.origin) {
    throw StateError('登录身份或服务已改变，已停止恢复原阅读');
  }
  bool current() =>
      isCurrent?.call() != false &&
      catalog.status == ServiceStatus.ready &&
      catalog.subject == context.subject &&
      catalog.deploymentOrigin?.origin == context.origin;
  if (!current()) return null;
  final builds = catalog.builds.where(
    (build) => build.packageName == context.packageName,
  );
  if (builds.isEmpty) throw StateError('原漫画源已不可用，请返回浏览选择');
  await catalog.openBuild(builds.single);
  if (!current()) return null;
  final sources = catalog.session?.sources.where(
    (source) => source.id == context.sourceId,
  );
  if (sources == null || sources.isEmpty) return null;
  await catalog.selectSource(sources.single, loadListing: false);
  if (!current()) return null;
  final details = await catalog.details(
    MangaEntry(context.manga),
    shouldContinue: current,
  );
  if (details == null || !current()) return null;
  final sequence = ChapterSequence(
    packageName: context.packageName,
    sourceId: context.sourceId,
    mangaUrl: details.manga.url,
    chapters: details.chapters.map((chapter) => chapter.snapshot),
  );
  final chapters = sequence.entries.where(
    (chapter) => chapter.key == context.chapterKey,
  );
  if (chapters.isEmpty) {
    throw StateError('章节清单已改变，无法确定原章节；请返回重新选择');
  }
  final chapter = chapters.single;
  final opened = await catalog.openChapter(
    details.manga,
    ChapterEntry(chapter.snapshot),
    reference: details.source,
    logicalChapterKey: chapter.key,
  );
  if (opened == null) return null;
  if (!current() || !catalog.isCurrentSource(details.source)) {
    await opened.provider.close();
    return null;
  }
  return RecoveredReader(
    manga: details.manga,
    sequence: sequence,
    chapter: chapter,
    source: details.source,
    opened: opened,
    // ReaderController resolves this original anchor and retains its explicit
    // missing-page notice if the Source has changed its page list.
    position: context.position,
  );
}
