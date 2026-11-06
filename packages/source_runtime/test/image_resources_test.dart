import 'dart:async';

import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';
import 'package:test/test.dart';

import 'support/fake_runtime_transport.dart';

ImageReleaseRequest release(String id) =>
    ImageReleaseRequest(resourceId: id, generation: 'generation-1');

void uniqueResource(FakeTransport transport, {int bytes = 1}) {
  transport.handler = (call) async {
    final response = transport.respond(call);
    if (call.hasAcquireImage()) {
      response.image
        ..resourceId = call.acquireImage.requestId
        ..byteLength = bytes;
    }
    return response;
  };
}

void main() {
  test(
    'Source image control carries opaque ownership and bytes only',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      uniqueResource(transport, bytes: wire.imageByteLimit);
      final image = await runtime.acquireImage(imageRequest());
      expect(image.byteLength, wire.imageByteLimit);
      expect(image.location.scheme, 'blob');
      final encoded = wire.encodeProtoJson(
        wire.ImageResource(
          resourceId: image.id,
          generation: image.generation,
          byteLength: image.byteLength,
          url: image.location.toString(),
        ),
      );
      expect(encoded.keys.toSet(), {
        'resourceId',
        'generation',
        'byteLength',
        'url',
      });
      expect(wire.encodeProtoJson(wire.ImageMeta()), isEmpty);
      for (final metadata in ['mimeType', 'width', 'height', 'orientation']) {
        expect(
          () => wire.decodeProtoJson(wire.ImageResource(), {
            ...encoded,
            metadata: 1,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => wire.decodeProtoJson(wire.ControlRequest(), {
          'acquireEncodedImage': <String, Object?>{},
        }),
        throwsFormatException,
      );
      await runtime.dispose();
    },
  );

  test(
    'cancel ACK cannot publish a late image and its cleanup preserves the Source',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final entered = Completer<void>();
      final ready = Completer<void>();
      transport.handler = (call) async {
        final response = transport.respond(call);
        if (call.hasAcquireImage()) {
          entered.complete();
          await ready.future;
        }
        return response;
      };
      final assertion = expectLater(
        runtime.acquireImage(imageRequest()),
        throwsA(failure(RuntimeErrorCode.cancelled)),
      );
      await entered.future;
      await runtime.cancelImage(
        const ImageCancelRequest(
          requestId: 'image-1',
          generation: 'generation-1',
        ),
      );
      ready.complete();
      await assertion;
      expect(transport.calls.last.releaseImage.resourceId, 'resource-1');
      expect(transport.calls.last.releaseImage.generation, 'generation-1');
      expect(transport.calls.where((call) => call.hasCancel()), isEmpty);
      expect((await runtime.invoke(request())).generation, 'generation-1');
      await runtime.dispose();
    },
  );

  test(
    'a rejected envelope releases only the new resource under the request generation',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      transport.handler = (call) async {
        final response = transport.respond(call);
        if (call.hasAcquireImage()) {
          response.requestId = 'foreign';
          response.image.generation = 'foreign';
        }
        return response;
      };
      await expectLater(
        runtime.acquireImage(imageRequest()),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(transport.calls.last.releaseImage.resourceId, 'resource-1');
      expect(transport.calls.last.releaseImage.generation, 'generation-1');
      await runtime.dispose();
    },
  );

  test(
    'a reused resource identity cannot revoke an accepted UI owner',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final first = await runtime.acquireImage(imageRequest());
      await expectLater(
        runtime.acquireImage(imageRequest(id: 'image-2')),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(transport.calls.where((call) => call.hasReleaseImage()), isEmpty);
      await runtime.releaseImage(release(first.id));
      expect(
        transport.calls.where((call) => call.hasReleaseImage()),
        hasLength(1),
      );
      await runtime.dispose();
    },
  );

  test(
    'resident body bytes remain charged until the matching release ACK',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      uniqueResource(transport, bytes: wire.imageByteLimit);
      final first = await runtime.acquireImage(imageRequest());
      final releaseStarted = Completer<void>();
      final releaseAck = Completer<void>();
      transport.handler = (call) async {
        final response = transport.respond(call);
        if (call.hasAcquireImage()) {
          response.image
            ..resourceId = call.acquireImage.requestId
            ..byteLength = 1;
        }
        if (call.hasReleaseImage() &&
            call.releaseImage.resourceId == first.id) {
          releaseStarted.complete();
          await releaseAck.future;
        }
        return response;
      };
      final retiring = runtime.releaseImage(release(first.id));
      await releaseStarted.future;
      await expectLater(
        runtime.acquireImage(imageRequest(id: 'too-early')),
        throwsA(failure(RuntimeErrorCode.limitExceeded)),
      );
      expect(transport.calls.last.releaseImage.resourceId, 'too-early');
      releaseAck.complete();
      await retiring;
      expect(
        (await runtime.acquireImage(imageRequest(id: 'after-ack'))).byteLength,
        1,
      );
      await runtime.dispose();
    },
  );

  test(
    'six owned resources include retirement and release calls share one ACK',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      uniqueResource(transport);
      for (var i = 0; i < wire.imageResourceLimit; i++) {
        await runtime.acquireImage(imageRequest(id: 'resource-$i'));
      }
      final releaseStarted = Completer<void>();
      final releaseAck = Completer<void>();
      transport.handler = (call) async {
        final response = transport.respond(call);
        if (call.hasAcquireImage()) {
          response.image
            ..resourceId = call.acquireImage.requestId
            ..byteLength = 1;
        }
        if (call.hasReleaseImage()) {
          releaseStarted.complete();
          await releaseAck.future;
        }
        return response;
      };
      final first = runtime.releaseImage(release('resource-0'));
      final second = runtime.releaseImage(release('resource-0'));
      await releaseStarted.future;
      await expectLater(
        runtime.acquireImage(imageRequest(id: 'seventh')),
        throwsA(failure(RuntimeErrorCode.limitExceeded)),
      );
      expect(
        transport.calls.where((call) => call.hasAcquireImage()),
        hasLength(6),
      );
      expect(
        transport.calls.where((call) => call.hasReleaseImage()),
        hasLength(1),
      );
      releaseAck.complete();
      await Future.wait([first, second]);
      expect(
        (await runtime.acquireImage(imageRequest(id: 'after-ack'))).id,
        'after-ack',
      );
      await runtime.dispose();
    },
  );

  test(
    'pending Source acquisitions occupy the same six-resource window',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final allEntered = Completer<void>();
      final ready = Completer<void>();
      var count = 0;
      transport.handler = (call) async {
        final response = transport.respond(call);
        if (call.hasAcquireImage()) {
          response.image
            ..resourceId = call.acquireImage.requestId
            ..byteLength = 1;
          if (++count == wire.imageResourceLimit) allEntered.complete();
          await ready.future;
        }
        return response;
      };
      final pending = [
        for (var i = 0; i < wire.imageResourceLimit; i++)
          runtime.acquireImage(imageRequest(id: 'pending-$i')),
      ];
      await allEntered.future;
      await expectLater(
        runtime.acquireImage(imageRequest(id: 'seventh')),
        throwsA(failure(RuntimeErrorCode.limitExceeded)),
      );
      await expectLater(
        runtime.acquireImage(imageRequest(id: 'pending-0')),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(count, wire.imageResourceLimit);
      ready.complete();
      expect(await Future.wait(pending), hasLength(wire.imageResourceLimit));
      await runtime.dispose();
    },
  );

  test(
    'a refused cleanup ACK retains the resource charge while explicit retries reuse its identity',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      uniqueResource(transport);
      for (var i = 0; i < wire.imageResourceLimit; i++) {
        await runtime.acquireImage(imageRequest(id: 'resource-$i'));
      }
      transport.handler = (call) async => call.hasReleaseImage()
          ? wire.ControlResponse(
              slotId: call.slotId,
              requestId: call.requestId,
              released: wire.Released(),
            )
          : transport.respond(call);
      await expectLater(
        runtime.releaseImage(release('resource-0')),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      await expectLater(
        runtime.releaseImage(release('resource-0')),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(
        transport.calls.where((call) => call.hasReleaseImage()),
        hasLength(2),
      );
      await expectLater(
        runtime.acquireImage(imageRequest(id: 'seventh')),
        throwsA(failure(RuntimeErrorCode.limitExceeded)),
      );
      transport.handler = (call) async {
        final response = transport.respond(call);
        if (call.hasAcquireImage()) {
          response.image.resourceId = call.acquireImage.requestId;
        }
        return response;
      };
      await runtime.releaseImage(release('resource-0'));
      expect(
        (await runtime.acquireImage(imageRequest(id: 'replacement'))).id,
        'replacement',
      );
      await runtime.dispose();
    },
  );
}
