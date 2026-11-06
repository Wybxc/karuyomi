import 'dart:async';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:test/test.dart';

import 'support/fake_runtime_transport.dart';

void main() {
  for (final (wireCode, code) in [
    (
      wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_REQUIRED,
      RuntimeErrorCode.accessRequired,
    ),
    (
      wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_DENIED,
      RuntimeErrorCode.accessDenied,
    ),
  ]) {
    for (final withSource in [false, true]) {
      test(
        'late API $code cannot pause a replacement Source (previous Source=$withSource)',
        () async {
          final transport = FakeTransport();
          final runtime = TransportSourceRuntime(transport);
          final events = <RuntimeEvent>[];
          final subscription = runtime.events.listen(events.add);
          if (withSource) await runtime.open(build());
          final entered = Completer<void>();
          final release = Completer<void>();
          transport.handler = (call) async {
            if (call.hasFetchApi()) {
              entered.complete();
              await release.future;
              return wire.ControlResponse(
                slotId: call.slotId,
                requestId: call.requestId,
                error: wire.RuntimeError(
                  code: wireCode,
                  message: 'Old private API Access decision',
                ),
              );
            }
            final response = transport.respond(call);
            if (call.hasOpen()) {
              response.session.generation = 'replacement-generation';
            }
            if (call.hasInvoke()) {
              response.source.generation = 'replacement-generation';
            }
            return response;
          };
          final old = expectLater(
            runtime.fetchApi(wire.ApiFetchRequest(path: '/api/settings')),
            throwsA(failure(code)),
          );
          await entered.future;
          await runtime.open(build(identity: 'replacement-owner'));
          events.clear();
          release.complete();
          await old;
          expect(events, isEmpty);
          expect(
            (await runtime.invoke(
              request(generation: 'replacement-generation'),
            )).generation,
            'replacement-generation',
          );
          await subscription.cancel();
          await runtime.dispose();
        },
      );
    }
  }

  for (final (wireCode, code) in [
    (
      wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_REQUIRED,
      RuntimeErrorCode.accessRequired,
    ),
    (
      wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_DENIED,
      RuntimeErrorCode.accessDenied,
    ),
  ]) {
    for (final withSource in [false, true]) {
      test(
        'private API $code pauses the client with Source=$withSource',
        () async {
          final transport = FakeTransport();
          final runtime = TransportSourceRuntime(transport);
          final events = <RuntimeEvent>[];
          final subscription = runtime.events.listen(events.add);
          if (withSource) await runtime.open(build());
          transport.handler = (call) async {
            if (call.hasFetchApi()) {
              return wire.ControlResponse(
                slotId: call.slotId,
                requestId: call.requestId,
                error: wire.RuntimeError(
                  code: wireCode,
                  message: 'Private API Access decision',
                ),
              );
            }
            return transport.respond(call);
          };
          await expectLater(
            runtime.fetchApi(wire.ApiFetchRequest(path: '/api/settings')),
            throwsA(failure(code)),
          );
          expect(events.single.code, code);
          expect(events.single.generation, withSource ? 'generation-1' : '');
          if (withSource) {
            await expectLater(
              runtime.invoke(request()),
              throwsA(failure(code)),
            );
          } else {
            expect(transport.calls.where((call) => call.hasOpen()), isEmpty);
          }
          transport.handler = (call) async {
            if (!call.hasFetchApi()) return transport.respond(call);
            return wire.ControlResponse(
              slotId: call.slotId,
              requestId: call.requestId,
              api: wire.ApiFetchResponse(status: 200, body: '{}'),
            );
          };
          expect(
            (await runtime.fetchApi(
              wire.ApiFetchRequest(path: '/api/bootstrap'),
            )).status,
            200,
          );
          expect(events, hasLength(1));
          await subscription.cancel();
          await runtime.dispose();
        },
      );
    }
  }

  for (final (wireCode, code) in [
    (
      wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_REQUIRED,
      RuntimeErrorCode.accessRequired,
    ),
    (
      wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_DENIED,
      RuntimeErrorCode.accessDenied,
    ),
  ]) {
    test(
      'Access pause retains the original $code and permits resource cleanup before explicit reopen',
      () async {
        final transport = FakeTransport();
        final runtime = TransportSourceRuntime(transport);
        final events = <RuntimeEvent>[];
        final subscription = runtime.events.listen(events.add);
        await runtime.open(build());
        final image = await runtime.acquireImage(imageRequest());
        var paused = true;
        var generation = 'generation-1';
        transport.handler = (call) async {
          if (paused && call.hasInvoke()) {
            return wire.ControlResponse(
              slotId: call.slotId,
              requestId: call.requestId,
              error: wire.RuntimeError(
                code: wireCode,
                message: 'Original Access decision',
                javaClass: 'AccessSessionExpired',
                retryable: true,
              ),
            );
          }
          final response = transport.respond(call);
          if (call.hasOpen()) response.session.generation = generation;
          if (call.hasInvoke()) response.source.generation = generation;
          return response;
        };
        RuntimeException? original;
        try {
          await runtime.invoke(request());
          fail('The Access decision must fail the Source call');
        } on RuntimeException catch (error) {
          original = error;
        }
        final controlsAtPause = transport.calls.length;
        await expectLater(runtime.invoke(request()), throwsA(same(original)));
        await expectLater(
          runtime.acquireImage(imageRequest(id: 'later')),
          throwsA(same(original)),
        );
        expect(transport.calls, hasLength(controlsAtPause));
        expect(
          original,
          failure(code)
              .having(
                (error) => error.message,
                'message',
                'Original Access decision',
              )
              .having(
                (error) => error.javaClass,
                'javaClass',
                'AccessSessionExpired',
              )
              .having((error) => error.retryable, 'retryable', true),
        );
        await Future<void>.delayed(Duration.zero);
        expect(events.single.code, code);
        expect(events.single.generation, 'generation-1');
        expect(
          transport.calls.where((call) => call.hasReleaseImage()),
          isEmpty,
        );
        await runtime.releaseImage(
          ImageReleaseRequest(
            resourceId: image.id,
            generation: image.generation,
          ),
        );
        await runtime.closePageSession(
          const PageSessionRef(
            pageSessionId: 'pages-1',
            generation: 'generation-1',
          ),
        );
        expect(
          transport.calls.last.closePageSession.generation,
          'generation-1',
        );

        paused = false;
        generation = 'generation-2';
        final reopened = await runtime.open(build());
        expect(reopened.generation, generation);
        expect(transport.calls.where((call) => call.hasOpen()), hasLength(2));
        expect(
          (await runtime.invoke(request(generation: generation))).generation,
          generation,
        );
        runtime.containerLost('ordinary process loss');
        await expectLater(
          runtime.invoke(request(generation: generation)),
          throwsA(failure(RuntimeErrorCode.runtimeLost)),
        );
        await subscription.cancel();
        await runtime.dispose();
      },
    );
  }

  for (final isImage in [false, true]) {
    test(
      'late ${isImage ? 'image' : 'Source'} completion cannot resume a paused generation',
      () async {
        final transport = FakeTransport();
        final runtime = TransportSourceRuntime(transport);
        await runtime.open(build());
        final entered = Completer<void>();
        final finish = Completer<void>();
        transport.handler = (call) async {
          if ((isImage && call.hasAcquireImage()) ||
              (!isImage &&
                  call.hasInvoke() &&
                  call.invoke.requestId == 'slow')) {
            entered.complete();
            await finish.future;
            return transport.respond(call);
          }
          if (call.hasInvoke()) {
            return wire.ControlResponse(
              slotId: call.slotId,
              requestId: call.requestId,
              error: wire.RuntimeError(
                code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_REQUIRED,
                message: 'Pause the entire generation',
              ),
            );
          }
          return transport.respond(call);
        };
        final slowRequest = request();
        slowRequest.call.requestId = 'slow';
        final late = expectLater(
          isImage
              ? runtime.acquireImage(imageRequest())
              : runtime.invoke(slowRequest),
          throwsA(failure(RuntimeErrorCode.accessRequired)),
        );
        await entered.future;
        await expectLater(
          runtime.invoke(request()),
          throwsA(failure(RuntimeErrorCode.accessRequired)),
        );
        finish.complete();
        await late;
        expect(
          transport.calls.where((call) => call.hasReleaseImage()),
          hasLength(isImage ? 1 : 0),
        );
        await runtime.dispose();
      },
    );
  }

  test(
    'concurrent open shares generated session and decimal Source identity',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      final first = runtime.open(build());
      final second = runtime.open(build());
      final session = await first;
      expect((await second).generation, session.generation);
      expect(session.sources.single.id, sourceId);
      expect(session.sources.single.hasSupportsLatest(), false);
      expect(transport.calls.where((call) => call.hasOpen()), hasLength(1));
      expect(
        transport.calls
            .singleWhere((call) => call.hasOpen())
            .open
            .expectedBundleSha256,
        'a' * 64,
      );
      final result = await runtime.invoke(request());
      expect(result.whichPayload(), wire.SourceResult_Payload.mangaPage);
      expect(result.mangaPage.hasNextPage, false);
      expect(transport.calls.last.invoke.popular.page, 2);
      expect(
        transport.calls.map((call) => call.requestId).toSet().length,
        transport.calls.length,
      );
      await runtime.dispose();
    },
  );

  test(
    'unconfirmed identity and noncanonical static paths never reach transport',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await expectLater(
        runtime.open(build(identity: '')),
        throwsA(failure(RuntimeErrorCode.accessRequired)),
      );
      for (final path in [
        '/runtime/build.json',
        '/extensions/builds/other/manifest.json',
        '/extensions/builds/build-1/manifest.json?old=1',
        'https://another.example/extensions/builds/build-1/manifest.json',
      ]) {
        await expectLater(
          runtime.open(build(path: path)),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
      }
      expect(transport.calls, isEmpty);
      await runtime.dispose();
    },
  );

  test('foreign generation and Source cannot invoke transport', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    await expectLater(
      runtime.invoke(request(generation: 'old')),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    await expectLater(
      runtime.invoke(request(id: 'other')),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    expect(transport.calls.where((call) => call.hasInvoke()), isEmpty);
    await runtime.dispose();
  });

  test(
    'container invalidation is observed before a replacement can be opened',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final events = <RuntimeEvent>[];
      Future<void>? invalidatedCall;
      final subscription = runtime.events.listen((event) {
        events.add(event);
        invalidatedCall = expectLater(
          runtime.invoke(request()),
          throwsA(failure(RuntimeErrorCode.runtimeLost)),
        );
      });
      runtime.containerLost('explicit rebuild');
      expect(events.single.message, 'explicit rebuild');
      expect(events.single.generation, isEmpty);
      await invalidatedCall;
      expect(transport.calls.where((call) => call.hasInvoke()), isEmpty);
      transport.handler = (call) async {
        final response = transport.respond(call);
        if (call.hasOpen()) response.session.generation = 'generation-2';
        if (call.hasInvoke()) response.source.generation = 'generation-2';
        return response;
      };
      expect((await runtime.open(build())).generation, 'generation-2');
      expect(
        (await runtime.invoke(request(generation: 'generation-2'))).generation,
        'generation-2',
      );
      expect(events, hasLength(1));
      await subscription.cancel();
      await runtime.dispose();
    },
  );

  for (final (wireCode, code) in [
    (
      wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST,
      RuntimeErrorCode.runtimeLost,
    ),
    (
      wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_REQUIRED,
      RuntimeErrorCode.accessRequired,
    ),
  ]) {
    test(
      'synchronous $code events observe the committed failure state',
      () async {
        final transport = FakeTransport();
        final runtime = TransportSourceRuntime(transport);
        await runtime.open(build());
        var invokeCount = 0;
        transport.handler = (call) async {
          if (call.hasInvoke() && ++invokeCount == 1) {
            return wire.ControlResponse(
              slotId: call.slotId,
              requestId: call.requestId,
              error: wire.RuntimeError(
                code: wireCode,
                message: 'invalidate current session',
              ),
            );
          }
          return transport.respond(call);
        };
        Future<void>? observerCall;
        final events = <RuntimeEvent>[];
        final subscription = runtime.events.listen((event) {
          events.add(event);
          observerCall = expectLater(
            runtime.invoke(request()),
            throwsA(failure(code)),
          );
        });
        await expectLater(runtime.invoke(request()), throwsA(failure(code)));
        expect(events.single.generation, 'generation-1');
        await observerCall;
        expect(invokeCount, 1);
        await subscription.cancel();
        await runtime.dispose();
      },
    );
  }

  test('container replacement discards late generated Source result', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    final ready = Completer<void>();
    transport.handler = (call) async {
      if (call.hasInvoke()) await ready.future;
      return transport.respond(call);
    };
    final assertion = expectLater(
      runtime.invoke(request()),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    runtime.containerLost('process recycled');
    ready.complete();
    await assertion;
    await runtime.dispose();
  });

  test(
    'expired hello cannot start a Source in replacement container',
    () async {
      final transport = FakeTransport();
      final ready = Completer<void>();
      transport.handler = (call) async {
        if (call.hasReady()) await ready.future;
        return transport.respond(call);
      };
      final runtime = TransportSourceRuntime(transport);
      final assertion = expectLater(
        runtime.open(build()),
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      runtime.containerLost('replaced during hello');
      ready.complete();
      await assertion;
      expect(transport.calls.where((call) => call.hasOpen()), isEmpty);
      await runtime.dispose();
    },
  );

  test('invalid generated session shape is a protocol error', () async {
    final transport = FakeTransport();
    transport.corrupt = (call, json) => call.hasOpen()
        ? {
            ...json,
            'session': {
              ...json['session'] as Map,
              'capabilities': [42],
            },
          }
        : json;
    final runtime = TransportSourceRuntime(transport);
    await expectLater(
      runtime.open(build()),
      throwsA(failure(RuntimeErrorCode.protocolError)),
    );
    await runtime.dispose();
  });

  for (final (wireCode, code) in [
    (
      wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_SOURCE_ERROR,
      RuntimeErrorCode.sourceError,
    ),
    (
      wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_STORAGE_BUSY,
      RuntimeErrorCode.storageBusy,
    ),
  ]) {
    test(
      'generated $code preserves category, Java class, message and retryability',
      () async {
        final transport = FakeTransport();
        final runtime = TransportSourceRuntime(transport);
        await runtime.open(build());
        transport.handler = (call) async => call.hasInvoke()
            ? wire.ControlResponse(
                slotId: call.slotId,
                requestId: call.requestId,
                error: wire.RuntimeError(
                  code: wireCode,
                  message: 'Explicit reference is required',
                  javaClass: 'java.lang.IllegalArgumentException',
                  retryable: true,
                ),
              )
            : transport.respond(call);
        await expectLater(
          runtime.invoke(request()),
          throwsA(
            failure(code)
                .having(
                  (error) => error.javaClass,
                  'javaClass',
                  'java.lang.IllegalArgumentException',
                )
                .having((error) => error.retryable, 'retryable', true),
          ),
        );
        await runtime.dispose();
      },
    );
  }

  test('image control uses opaque handles and matching cleanup ACKs', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    final image = await runtime.acquireImage(imageRequest());
    expect(image.byteLength, 1234);
    expect(image.location.scheme, 'blob');
    expect(transport.calls.last.acquireImage.pageSessionId, 'pages-1');
    expect(transport.calls.last.acquireImage.pageKey, 'p-0');
    expect(transport.calls.last.acquireImage.timeoutMs, 30000);
    await runtime.cancelImage(
      const ImageCancelRequest(
        requestId: 'image-1',
        generation: 'generation-1',
      ),
    );
    await runtime.releaseImage(
      const ImageReleaseRequest(
        resourceId: 'resource-1',
        generation: 'generation-1',
      ),
    );
    await runtime.closePageSession(
      const PageSessionRef(
        pageSessionId: 'pages-1',
        generation: 'generation-1',
      ),
    );
    expect(transport.calls.where((call) => call.hasCancel()), isEmpty);
    transport.handler = (call) async => call.hasReleaseImage()
        ? wire.ControlResponse(
            slotId: call.slotId,
            requestId: call.requestId,
            released: wire.Released(),
          )
        : transport.respond(call);
    await expectLater(
      runtime.releaseImage(
        const ImageReleaseRequest(
          resourceId: 'resource-1',
          generation: 'generation-1',
        ),
      ),
      throwsA(failure(RuntimeErrorCode.protocolError)),
    );
    await runtime.dispose();
  });

  test(
    'file images require the Native transport ownership table, including identity and generation',
    () async {
      final delegate = FakeTransport();
      final managed = ManagedTransport(delegate);
      final location = Uri.parse('file:///private/tmp/managed/image');
      delegate.handler = (request) async {
        final response = delegate.respond(request);
        if (request.hasAcquireImage()) response.image.url = location.toString();
        return response;
      };
      final runtime = TransportSourceRuntime(managed);
      await runtime.open(build());
      await expectLater(
        runtime.acquireImage(imageRequest()),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      managed.owned = location;
      final resource = await runtime.acquireImage(imageRequest());
      expect(resource.location, location);
      await runtime.releaseImage(
        const ImageReleaseRequest(
          resourceId: 'resource-1',
          generation: 'generation-1',
        ),
      );
      managed.owned = Uri.parse('file:///private/tmp/managed/other');
      await expectLater(
        runtime.acquireImage(imageRequest()),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      await runtime.dispose();
    },
  );

  test(
    'invalid managed locations and byte counts release rejected resource',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      for (final change in <void Function(wire.ImageResource)>[
        (image) => image.url = 'https://source.example/raw.png',
        (image) => image.url = 'data:image/png;base64,AAAA',
        (image) => image.byteLength = 0,
        (image) => image.byteLength = 64 * 1024 * 1024 + 1,
      ]) {
        transport.handler = (call) async {
          final response = transport.respond(call);
          if (call.hasAcquireImage()) change(response.image);
          return response;
        };
        await expectLater(
          runtime.acquireImage(imageRequest()),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
        expect(transport.calls.last.hasReleaseImage(), true);
      }
      await runtime.dispose();
    },
  );

  test(
    'late image after replacement is released under original generation',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final ready = Completer<void>();
      transport.handler = (call) async {
        if (call.hasAcquireImage()) await ready.future;
        return transport.respond(call);
      };
      final assertion = expectLater(
        runtime.acquireImage(imageRequest()),
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      runtime.containerLost('replaced');
      ready.complete();
      await assertion;
      expect(transport.calls.last.releaseImage.generation, 'generation-1');
      await runtime.dispose();
    },
  );

  test(
    'response control ID, result case and Source payload must match request',
    () async {
      for (final change in <void Function(wire.ControlResponse)>[
        (response) => response.requestId = 'foreign',
        (response) => response.completed = wire.Completed(completed: true),
        (response) => response.source.chapters = wire.ChapterList(),
      ]) {
        final transport = FakeTransport();
        final runtime = TransportSourceRuntime(transport);
        await runtime.open(build());
        transport.handler = (call) async {
          final response = transport.respond(call);
          if (call.hasInvoke()) change(response);
          return response;
        };
        await expectLater(
          runtime.invoke(request()),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
        await runtime.dispose();
      }
    },
  );

  test(
    'opaque memo numeric lexemes and false optional presence survive response',
    () async {
      const memo = '{"id":9223372036854775806,"nested":{"huge":1e1000}}';
      final transport = FakeTransport();
      transport.handler = (call) async {
        final response = transport.respond(call);
        if (call.hasOpen()) {
          response.session.sources.single.supportsLatest = false;
        }
        if (call.hasInvoke()) {
          response.source.mangaPage.mangas.add(
            wire.Manga(url: '/m', title: 'm', memoJson: memo),
          );
        }
        return response;
      };
      final runtime = TransportSourceRuntime(transport);
      final session = await runtime.open(build());
      expect(session.sources.single.hasSupportsLatest(), true);
      expect(session.sources.single.supportsLatest, false);
      expect(
        (await runtime.invoke(request())).mangaPage.mangas.single.memoJson,
        memo,
      );
      await runtime.dispose();
    },
  );

  test('image timeout is local; lost generation remains broadcast', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    final events = <RuntimeEvent>[];
    final subscription = runtime.events.listen(events.add);
    var code = wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_TIMEOUT;
    transport.handler = (call) async => call.hasAcquireImage()
        ? wire.ControlResponse(
            slotId: call.slotId,
            requestId: call.requestId,
            error: wire.RuntimeError(
              code: code,
              message: 'Image unwind outcome',
            ),
          )
        : transport.respond(call);
    await expectLater(
      runtime.acquireImage(imageRequest()),
      throwsA(failure(RuntimeErrorCode.timeout)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    code = wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST;
    await expectLater(
      runtime.acquireImage(imageRequest()),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events.single.code, RuntimeErrorCode.runtimeLost);
    await subscription.cancel();
    await runtime.dispose();
  });

  test('dispose is acknowledged once and rejects later work', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    await runtime.dispose();
    await runtime.dispose();
    expect(transport.calls.where((call) => call.hasDispose()), hasLength(1));
    await expectLater(
      runtime.invoke(request()),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
  });
  for (final lateError in [false, true]) {
    test(
      'late API completion cannot affect a reopened runtime (error=$lateError)',
      () async {
        final transport = FakeTransport();
        final runtime = TransportSourceRuntime(transport);
        final events = <RuntimeEvent>[];
        final subscription = runtime.events.listen(events.add);
        final entered = Completer<void>();
        final release = Completer<void>();
        transport.handler = (call) async {
          if (!call.hasFetchApi()) return transport.respond(call);
          entered.complete();
          await release.future;
          return wire.ControlResponse(
            slotId: call.slotId,
            requestId: call.requestId,
            error: lateError
                ? wire.RuntimeError(
                    code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST,
                    message: 'Old API failed',
                  )
                : null,
            api: lateError
                ? null
                : wire.ApiFetchResponse(status: 200, body: 'old identity'),
          );
        };
        final old = expectLater(
          runtime.fetchApi(wire.ApiFetchRequest(path: '/api/bootstrap')),
          throwsA(failure(RuntimeErrorCode.runtimeLost)),
        );
        await entered.future;
        runtime.containerLost('Old API container ended');
        await runtime.open(build());
        events.clear();
        release.complete();
        await old;
        expect((await runtime.invoke(request())).generation, 'generation-1');
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        await subscription.cancel();
        await runtime.dispose();
      },
    );
  }

  for (final cleanupFails in [false, true]) {
    test(
      'late image cleanup keeps original owner and reopened session (failure=$cleanupFails)',
      () async {
        final transport = FakeTransport();
        final runtime = TransportSourceRuntime(transport);
        final events = <RuntimeEvent>[];
        final subscription = runtime.events.listen(events.add);
        final entered = Completer<void>();
        final release = Completer<void>();
        var generation = 'generation-1';
        transport.handler = (call) async {
          final response = transport.respond(call);
          if (call.hasAcquireImage()) {
            entered.complete();
            await release.future;
            return response;
          }
          if (call.hasOpen()) {
            response.session.generation = generation;
            response.session.workerInstanceId = 'worker-$generation';
          }
          if (call.hasInvoke()) response.source.generation = generation;
          if (call.hasReleaseImage() && cleanupFails) {
            return wire.ControlResponse(
              slotId: call.slotId,
              requestId: call.requestId,
              error: wire.RuntimeError(
                code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST,
                message: 'Old image cleanup failed',
              ),
            );
          }
          return response;
        };
        await runtime.open(build());
        final old = expectLater(
          runtime.acquireImage(imageRequest()),
          throwsA(failure(RuntimeErrorCode.runtimeLost)),
        );
        await entered.future;
        runtime.containerLost('Old image container ended');
        generation = 'generation-2';
        await runtime.open(build());
        events.clear();
        release.complete();
        await old;
        final cleanup = transport.calls.singleWhere(
          (call) => call.hasReleaseImage(),
        );
        expect(cleanup.releaseImage.resourceId, 'resource-1');
        expect(cleanup.releaseImage.generation, 'generation-1');
        expect(
          (await runtime.invoke(request(generation: generation))).generation,
          generation,
        );
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        await subscription.cancel();
        await runtime.dispose();
      },
    );
  }
  for (final lateError in [false, true]) {
    test(
      'late control handshake cannot invalidate a newer open (error=$lateError)',
      () async {
        final transport = FakeTransport();
        final runtime = TransportSourceRuntime(transport);
        final events = <RuntimeEvent>[];
        final subscription = runtime.events.listen(events.add);
        final entered = Completer<void>();
        final release = Completer<void>();
        var readyCalls = 0;
        transport.handler = (call) async {
          if (call.hasReady() && ++readyCalls == 1) {
            entered.complete();
            await release.future;
            if (lateError) throw StateError('Old handshake transport failed');
          }
          return transport.respond(call);
        };
        final old = expectLater(
          runtime.open(build()),
          throwsA(failure(RuntimeErrorCode.runtimeLost)),
        );
        await entered.future;
        runtime.containerLost('Previous startup ended');
        await runtime.open(build());
        events.clear();
        release.complete();
        await old;
        expect((await runtime.invoke(request())).generation, 'generation-1');
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        await subscription.cancel();
        await runtime.dispose();
      },
    );
  }
}
