import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:karuyomi/runtime/cover_transport.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_server.dart';

final class TestCoverUpload {
  TestCoverUpload({
    required this.mangaKey,
    required this.mutation,
    required this.subject,
    required Uint8List bytes,
    required this.contentType,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final String mangaKey;
  final String mutation;
  final String subject;
  final Uint8List bytes;
  final String contentType;
  wire.StateMutation get command =>
      wire.decodeProtoJson(wire.StateMutation(), jsonDecode(mutation));
}

/// Data/component supplier only; real multipart, R2 and codec limits are tested
/// separately against the formal transport and Worker API.
final class TestCoverTransport implements CoverTransport {
  TestCoverTransport(this.server, {String? subject})
    : subject = subject ?? server.defaultSubject;
  final TestBusinessServer server;
  final String subject;
  final uploads = <TestCoverUpload>[];
  FutureOr<void> Function(TestCoverUpload upload)? beforeUpload;
  FutureOr<void> Function()? beforeRead;
  bool closed = false;

  @override
  Future<ApiReply> uploadCover({
    required String mangaKey,
    required String mutation,
    required String subject,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (closed) throw StateError('Cover transport has ended');
    if (subject != this.subject) {
      throw const CoverTransportException(403, 'Cover subject changed');
    }
    final upload = TestCoverUpload(
      mangaKey: mangaKey,
      mutation: mutation,
      subject: subject,
      bytes: bytes,
      contentType: contentType,
    );
    final cover = upload.command.setCustomCover.cover;
    if (!upload.command.hasSetCustomCover() ||
        !upload.command.setCustomCover.hasCover() ||
        cover.byteLength != bytes.length ||
        cover.contentType != contentType ||
        cover.sha256 != crypto.sha256.convert(bytes).toString()) {
      throw const FormatException('Cover payload differs from its descriptor');
    }
    uploads.add(upload);
    await beforeUpload?.call(upload);
    return server.handle(
      TestBusinessRequest(
        path: '/api/covers/$mangaKey',
        method: 'POST',
        headers: {'X-App-Subject': subject},
        body: mutation,
      ),
      subject: this.subject,
    );
  }

  @override
  Future<Uint8List> readCover({
    required String assetId,
    required String subject,
    required String sha256,
    required int byteLength,
  }) async {
    if (closed) throw StateError('Cover transport has ended');
    await beforeRead?.call();
    if (subject != this.subject) {
      throw const CoverTransportException(403, 'Cover subject changed');
    }
    final upload = uploads
        .where(
          (upload) =>
              upload.subject == subject &&
              upload.command.setCustomCover.cover.assetId == assetId &&
              server
                      .manga(upload.mangaKey, subject: subject)
                      ?.customCover
                      .assetId ==
                  assetId,
        )
        .lastOrNull;
    if (upload == null) {
      throw const CoverTransportException(404, 'Cover missing');
    }
    if (upload.bytes.length != byteLength ||
        crypto.sha256.convert(upload.bytes).toString() != sha256) {
      throw const FormatException('Cover transfer integrity mismatch');
    }
    return Uint8List.fromList(upload.bytes);
  }

  @override
  void close() => closed = true;
}
