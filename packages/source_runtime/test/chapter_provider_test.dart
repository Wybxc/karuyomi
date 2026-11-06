import 'dart:async';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:test/test.dart';

import 'support/fake_runtime_transport.dart';

final class ImageRuntime implements SourceRuntime {
  final acquisitions = <ImageAcquireRequest>[];
  final cancellations = <ImageCancelRequest>[];
  final releases = <ImageReleaseRequest>[];
  final sessions = <PageSessionRef>[];
  final result = Completer<ImageResource>();
  final cancelAck = Completer<void>();
  final releaseAck = Completer<void>();
  @override
  Future<ImageResource> acquireImage(ImageAcquireRequest request) {
    acquisitions.add(request);
    return result.future;
  }

  @override
  Future<void> cancelImage(ImageCancelRequest request) {
    cancellations.add(request);
    return cancelAck.future;
  }

  @override
  Future<void> releaseImage(ImageReleaseRequest request) {
    releases.add(request);
    return releaseAck.future;
  }

  @override
  Future<void> closePageSession(PageSessionRef session) async {
    sessions.add(session);
  }

  @override
  Future<void> cancel(String requestId) =>
      throw StateError('Must not recycle the Source Worker');
  @override
  Stream<RuntimeEvent> get events => const Stream.empty();
  @override
  Future<RuntimeSession> open(BuildDescriptor build) =>
      throw UnimplementedError();
  @override
  Future<SourceResult> invoke(SourceRequest request) =>
      throw UnimplementedError();
  @override
  Future<wire.PreparedBuild> prepareBuild({
    required String preparationId,
    required wire.CatalogReference catalog,
    required wire.ExtensionBuildDescriptor build,
  }) => throw UnimplementedError();
  @override
  Future<void> cancelPreparation(String preparationId) =>
      throw UnimplementedError();
  @override
  Future<wire.ExtensionCacheState> extensionCache() =>
      throw UnimplementedError();
  @override
  Future<void> forgetExtensionArtifact(String sha256) =>
      throw UnimplementedError();
  @override
  Future<void> closeBuild({
    required String buildId,
    required String generation,
  }) => throw UnimplementedError();
  @override
  Future<void> dispose() async {}
}

ChapterPageProvider provider(ImageRuntime runtime) => ChapterPageProvider(
  runtime: runtime,
  sourceId: '42',
  pageSessionId: 'opaque-session',
  generation: 'g',
  chapterKey: 'stable-chapter',
  pageKeys: {'stable-page': 'p-0'},
);
PageRef page({
  String id = 'r-1',
  String generation = 'g',
  String key = 'stable-page',
}) => PageRef(
  requestId: id,
  chapterKey: 'stable-chapter',
  pageKey: key,
  generation: generation,
);
ImageResource image() => ImageResource(
  id: 'resource',
  generation: 'g',
  location: Uri.parse('blob:https://reader.example/id'),
  byteLength: 100,
);

void main() {
  test(
    'failed image release and page-session ACK retry the same owners before build cleanup',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final pages = ChapterPageProvider(
        runtime: runtime,
        sourceId: sourceId,
        pageSessionId: 'pages-1',
        generation: 'generation-1',
        chapterKey: 'chapter',
        pageKeys: {'page': 'p-0'},
      );
      await pages.acquire(
        PageRef(
          requestId: 'image-1',
          chapterKey: 'chapter',
          pageKey: 'page',
          generation: 'generation-1',
        ),
      );
      var releaseAttempts = 0;
      var closeAttempts = 0;
      transport.handler = (call) async {
        if (call.hasReleaseImage() && ++releaseAttempts == 1) {
          return wire.ControlResponse(
            requestId: call.requestId,
            released: wire.Released(released: false),
          );
        }
        if (call.hasClosePageSession() && ++closeAttempts == 1) {
          return wire.ControlResponse(
            requestId: call.requestId,
            closed: wire.Closed(closed: false),
          );
        }
        return transport.respond(call);
      };
      await expectLater(
        pages.close(),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(pages.isClosed, false);
      expect(closeAttempts, 0);
      await expectLater(
        pages.close(),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(pages.isClosed, false);
      expect(releaseAttempts, 2);
      await pages.close();
      expect(pages.isClosed, true);
      expect(closeAttempts, 2);
      await pages.close();
      expect(closeAttempts, 2);
      final releases = transport.calls
          .where((call) => call.hasReleaseImage())
          .toList();
      expect(releases[0].releaseImage, releases[1].releaseImage);
      final closes = transport.calls
          .where((call) => call.hasClosePageSession())
          .toList();
      expect(closes[0].closePageSession, closes[1].closePageSession);
      await runtime.dispose();
    },
  );
  test(
    'chapter binding maps logical keys and release/close are idempotent',
    () async {
      final runtime = ImageRuntime();
      final pages = provider(runtime);
      final future = pages.acquire(page());
      expect(runtime.acquisitions.single.pageKey, 'p-0');
      expect(runtime.acquisitions.single.pageSessionId, 'opaque-session');
      runtime.result.complete(image());
      await future;
      final release = pages.release('resource');
      final duplicate = pages.release('resource');
      expect(runtime.releases, hasLength(1));
      expect(identical(release, duplicate), true);
      var closed = false;
      final closing = pages.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, false);
      expect(runtime.sessions, isEmpty);
      runtime.releaseAck.complete();
      await closing;
      await pages.close();
      expect(runtime.sessions, hasLength(1));
      await expectLater(
        pages.acquire(page(id: 'late')),
        throwsA(isA<RuntimeException>()),
      );
    },
  );

  test(
    'cancel waits for platform ACK and releases a late successful acquisition',
    () async {
      final runtime = ImageRuntime();
      final pages = provider(runtime);
      final acquisition = pages.acquire(page());
      final assertion = expectLater(
        acquisition,
        throwsA(
          isA<RuntimeException>().having(
            (e) => e.code,
            'code',
            RuntimeErrorCode.cancelled,
          ),
        ),
      );
      var cancelled = false;
      final cancellation = pages.cancel('r-1').then((_) => cancelled = true);
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, false);
      final closing = pages.close();
      expect(runtime.cancellations, hasLength(1));
      expect(runtime.sessions, isEmpty);
      runtime.result.complete(image());
      await Future<void>.delayed(Duration.zero);
      expect(runtime.releases.single.generation, 'g');
      runtime.cancelAck.complete();
      await cancellation;
      expect(runtime.sessions, isEmpty);
      runtime.releaseAck.complete();
      await assertion;
      await closing;
      expect(runtime.sessions.single.pageSessionId, 'opaque-session');
    },
  );

  test(
    'foreign generation and unknown logical keys never request image bytes',
    () async {
      final runtime = ImageRuntime();
      final pages = provider(runtime);
      await expectLater(
        pages.acquire(page(generation: 'old')),
        throwsA(isA<RuntimeException>()),
      );
      await expectLater(
        pages.acquire(page(key: 'unknown')),
        throwsA(isA<RuntimeException>()),
      );
      expect(runtime.acquisitions, isEmpty);
      await pages.close();
    },
  );
}
