import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:uuid/uuid.dart';

import 'business_state_client.dart';
import 'business_state_validation.dart';
import 'reading_progress.dart';

final class CoverSnapshot {
  CoverSnapshot({required this.revision, wire.CustomCover? cover})
    : cover = cover == null ? null : (cover.deepCopy()..freeze());
  final int revision;
  final wire.CustomCover? cover;
}

/// The shared business session owns the immutable multipart/JSON command.
final class CoverDraft {
  const CoverDraft({
    required this.cover,
    required this.bytes,
    required this.basedOnRevision,
    required this.retryable,
  });
  final wire.CustomCover? cover;
  final Uint8List? bytes;
  final int basedOnRevision;
  final bool retryable;
}

final class CoverRepository {
  CoverRepository(this.client);
  final BusinessStateClient client;
  ProgressIdentity get identity => client.identity;

  CoverDraft? pending(String mangaKey) {
    final value = client.pendingCover(mangaKey);
    return value == null
        ? null
        : CoverDraft(
            cover: value.cover,
            bytes: value.bytes,
            basedOnRevision: value.basedOnRevision,
            retryable: value.retryable,
          );
  }

  Future<CoverSnapshot> load(String mangaKey) async =>
      _snapshot((await client.readManga(mangaKey)).manga);

  Future<CoverSnapshot> replace({
    required String mangaKey,
    required Uint8List bytes,
    required String contentType,
    required int basedOnRevision,
  }) async {
    if (pending(mangaKey) != null) {
      throw BusinessPendingMutationException(mangaKey, '请先处理该漫画未确认的原封面操作。');
    }
    if (bytes.isEmpty ||
        bytes.length > 1024 * 1024 ||
        (contentType != 'image/jpeg' && contentType != 'image/png')) {
      throw const FormatException('封面仅支持不超过 1 MiB 的 JPEG 或 PNG。');
    }
    final cover = wire.CustomCover(
      assetId: const Uuid().v4(),
      contentType: contentType,
      byteLength: bytes.length,
      sha256: sha256.convert(bytes).toString(),
    );
    validateBusinessCustomCover(cover);
    return _snapshot(
      (await client.mutate(
        wire.StateMutation(
          mangaKey: mangaKey,
          setCustomCover: wire.SetCustomCover(cover: cover),
        ),
        basedOnRevision: basedOnRevision,
        requireExactRevision: true,
        coverBytes: bytes,
      )).manga,
    );
  }

  Future<CoverSnapshot> clear({
    required String mangaKey,
    required int basedOnRevision,
  }) async {
    if (pending(mangaKey) != null) {
      throw BusinessPendingMutationException(mangaKey, '请先处理该漫画未确认的原封面操作。');
    }
    return _snapshot(
      (await client.mutate(
        wire.StateMutation(
          mangaKey: mangaKey,
          setCustomCover: wire.SetCustomCover(),
        ),
        basedOnRevision: basedOnRevision,
        requireExactRevision: true,
      )).manga,
    );
  }

  Future<CoverSnapshot> retry(String mangaKey) async =>
      _snapshot((await client.retryCover(mangaKey)).manga);

  Future<Uint8List> read(wire.CustomCover cover) => client.readCover(cover);
}

CoverSnapshot _snapshot(wire.MangaState manga) => CoverSnapshot(
  revision: manga.revision,
  cover: manga.hasCustomCover() ? manga.customCover : null,
);
