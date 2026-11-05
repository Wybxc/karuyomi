import 'dart:async';
import 'package:reader_core/reader_core.dart';
import 'package:test/test.dart';

final class ControlledProvider implements PageProvider {
  final requests = <PageRef>[];
  final pending = <String, Completer<ImageResource>>{};
  final cancelled = <String>[];
  final released = <String>[];
  var concurrent = 0;
  var peak = 0;
  Completer<void>? releaseGate;

  @override
  Future<ImageResource> acquire(PageRef page) {
    requests.add(page);
    concurrent++;
    if (concurrent > peak) peak = concurrent;
    final future = Completer<ImageResource>();
    pending[page.requestId] = future;
    return future.future.whenComplete(() => concurrent--);
  }

  void complete(PageRef ref, {int bytes = 10, String? generation}) {
    pending[ref.requestId]!.complete(
      ImageResource(
        id: ref.requestId,
        generation: generation ?? ref.generation,
        location: Uri.parse('https://processed.invalid/${ref.pageKey}'),
        byteLength: bytes,
      ),
    );
  }

  @override
  Future<void> cancel(String requestId) async => cancelled.add(requestId);
  @override
  Future<void> release(String resourceId) async {
    released.add(resourceId);
    await releaseGate?.future;
  }
}

List<ReaderPage> pages(int count, {String prefix = 'p'}) => List.generate(
  count,
  (index) => ReaderPage(key: '$prefix$index', width: 10, height: 20),
);

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'Access pause retains owned images and cancels production until disposal',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(provider: provider, maxConcurrent: 1);
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: 'g',
        pages: pages(3),
      );
      final displayed = provider.requests.single;
      provider.complete(displayed, bytes: 40);
      await tick();
      final inFlight = provider.requests.last;
      expect(inFlight.pageKey, 'p1');

      scheduler.setPaused(true);
      scheduler.setWindow(chapterKey: 'chapter', generation: 'g', pages: []);
      scheduler.retry('p2');
      expect(provider.cancelled, [inFlight.requestId]);
      expect(provider.released, isEmpty);
      expect(scheduler.snapshot.resources['p0']?.id, displayed.requestId);
      expect(scheduler.snapshot.residentBytes, 40);

      provider.complete(inFlight);
      await scheduler.settled;
      expect(provider.requests, hasLength(2));
      expect(provider.released, [inFlight.requestId]);
      expect(scheduler.snapshot.resources['p0']?.id, displayed.requestId);

      provider.releaseGate = Completer<void>();
      final closing = scheduler.dispose();
      expect(scheduler.snapshot.residentBytes, 40);
      provider.releaseGate!.complete();
      await closing;
      expect(provider.released, [inFlight.requestId, displayed.requestId]);
      expect(scheduler.snapshot.residentBytes, 0);
    },
  );

  test(
    'idle includes pending release ACKs, not only visible loading',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(provider: provider);
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: '1',
        pages: pages(1),
      );
      expect(scheduler.isIdle, false);
      provider.complete(provider.requests.single);
      await scheduler.settled;
      expect(scheduler.isIdle, true);
      provider.releaseGate = Completer<void>();
      scheduler.setWindow(chapterKey: 'chapter', generation: '1', pages: []);
      expect(scheduler.snapshot.loading, isEmpty);
      expect(scheduler.isIdle, false);
      provider.releaseGate!.complete();
      await scheduler.settled;
      expect(scheduler.isIdle, true);
      await scheduler.dispose();
    },
  );

  test(
    'priority, concurrent and resident-page limits hold across a long chapter',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(provider: provider, maxResidentPages: 3);
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: '1',
        pages: pages(100),
      );
      expect(provider.requests.map((r) => r.pageKey), ['p0', 'p1']);
      provider.complete(provider.requests.first);
      await tick();
      expect(provider.requests.map((r) => r.pageKey), ['p0', 'p1', 'p2']);
      provider.complete(provider.requests[1]);
      provider.complete(provider.requests[2]);
      await scheduler.settled;
      expect(provider.peak, 2);
      expect(scheduler.snapshot.resources.keys, ['p0', 'p1', 'p2']);
      expect(scheduler.snapshot.residentBytes, 30);
      await scheduler.dispose();
      expect(provider.released.length, 3);
    },
  );

  test(
    'switching generation cancels old requests and releases late results',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(provider: provider);
      scheduler.setWindow(chapterKey: 'a', generation: 'old', pages: pages(2));
      final old = provider.requests.toList();
      scheduler.setWindow(
        chapterKey: 'b',
        generation: 'new',
        pages: pages(1, prefix: 'new'),
      );
      expect(provider.cancelled, old.map((r) => r.requestId));
      for (final ref in old) {
        provider.complete(ref);
      }
      await tick();
      expect(provider.released, containsAll(old.map((r) => r.requestId)));
      expect(scheduler.snapshot.resources, isEmpty);
      expect(provider.requests.last.generation, 'new');
      provider.complete(provider.requests.last);
      await scheduler.settled;
      expect(scheduler.snapshot.resources.keys, ['new0']);
      await scheduler.dispose();
    },
  );

  test(
    'prefetch cannot displace the visible image at the byte budget',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(
        provider: provider,
        maxResidentBytes: 100,
      );
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: '1',
        pages: pages(2),
      );
      provider.complete(provider.requests[1], bytes: 80);
      await tick();
      provider.complete(provider.requests[0], bytes: 80);
      await scheduler.settled;
      expect(scheduler.snapshot.resources.keys, ['p0']);
      expect(scheduler.snapshot.residentBytes, 80);
      expect(provider.released, contains(provider.requests[1].requestId));
      expect(scheduler.snapshot.errors['p1'], isA<ImageBudgetExceeded>());
      await scheduler.dispose();
    },
  );

  test(
    'oversized images are released and invalid generation cannot display',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(
        provider: provider,
        maxResidentBytes: 100,
      );
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: '1',
        pages: pages(2),
      );
      provider.complete(provider.requests[0], bytes: 101);
      provider.complete(provider.requests[1], generation: 'stale');
      await scheduler.settled;
      expect(scheduler.snapshot.resources, isEmpty);
      expect(scheduler.snapshot.errors['p0'], isA<ImageBudgetExceeded>());
      expect(scheduler.snapshot.errors['p1'], isA<StateError>());
      expect(provider.released.length, 2);
      await scheduler.dispose();
    },
  );

  test(
    'late completion after timeout or disposal still releases the image',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(
        provider: provider,
        requestTimeout: const Duration(milliseconds: 5),
      );
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: '1',
        pages: pages(1),
      );
      final ref = provider.requests.single;
      await scheduler.settled;
      expect(scheduler.snapshot.errors['p0'], isA<TimeoutException>());
      expect(provider.cancelled, [ref.requestId]);
      await scheduler.dispose();
      provider.complete(ref);
      await tick();
      expect(provider.released, [ref.requestId]);
    },
  );

  test(
    'known giant decoded image is rejected before the provider runs',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(
        provider: provider,
        maxEstimatedDecodedBytes: 100,
      );
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: '1',
        pages: pages(1),
      );
      expect(provider.requests, isEmpty);
      expect(scheduler.snapshot.errors['p0'], isA<ImageBudgetExceeded>());
      scheduler.retry('p0');
      expect(provider.requests, isEmpty);
      await scheduler.dispose();
    },
  );

  test(
    'new production waits for old resource release acknowledgement',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(provider: provider);
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: '1',
        pages: pages(1),
      );
      provider.complete(provider.requests.single);
      await scheduler.settled;
      provider.releaseGate = Completer<void>();
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: '1',
        pages: pages(1, prefix: 'next'),
      );
      await tick();
      expect(provider.requests.length, 1);
      provider.releaseGate!.complete();
      await tick();
      expect(provider.requests.last.pageKey, 'next0');
      provider.complete(provider.requests.last);
      await scheduler.settled;
      await scheduler.dispose();
    },
  );

  test(
    'newly learned giant dimensions are rejected before presentation',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(
        provider: provider,
        maxEstimatedDecodedBytes: 1000,
        unknownPageDecodedEstimate: 100,
      );
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: 'g',
        pages: [ReaderPage(key: 'unknown')],
      );
      provider.complete(provider.requests.single);
      await scheduler.settled;
      expect(
        scheduler.recordDecoded(provider.requests.single.requestId, 100, 100),
        false,
      );
      await scheduler.settled;
      expect(scheduler.snapshot.resources, isEmpty);
      expect(scheduler.snapshot.errors['unknown'], isA<ImageBudgetExceeded>());
      expect(provider.released, [provider.requests.single.requestId]);
      await scheduler.dispose();
    },
  );

  test(
    'client dimensions replace unknown estimates and survive release until ACK',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(
        provider: provider,
        unknownPageDecodedEstimate: 100,
      );
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: 'g',
        pages: [ReaderPage(key: 'p')],
      );
      provider.complete(provider.requests.single, bytes: 12);
      await scheduler.settled;
      final id = provider.requests.single.requestId;
      expect(scheduler.snapshot.estimatedDecodedBytes, 100);
      expect(scheduler.snapshot.dimensions, isEmpty);
      expect(scheduler.recordDecoded(id, 4, 5), true);
      expect(scheduler.snapshot.estimatedDecodedBytes, 80);
      expect(scheduler.snapshot.dimensions[id]?.width, 4);
      expect(
        () => scheduler.snapshot.dimensions.clear(),
        throwsUnsupportedError,
      );
      provider.releaseGate = Completer<void>();
      scheduler.setWindow(chapterKey: 'chapter', generation: 'g', pages: []);
      expect(scheduler.snapshot.resources, isEmpty);
      expect(scheduler.snapshot.residentBytes, 12);
      expect(scheduler.snapshot.estimatedDecodedBytes, 80);
      expect(scheduler.snapshot.dimensions[id]?.height, 5);
      expect(scheduler.recordDecoded(id, 1, 1), false);
      provider.releaseGate!.complete();
      await scheduler.settled;
      expect(scheduler.snapshot.residentBytes, 0);
      expect(scheduler.snapshot.estimatedDecodedBytes, 0);
      expect(scheduler.snapshot.dimensions, isEmpty);
      await scheduler.dispose();
    },
  );

  test(
    'client decode failures invalidate display and retain costs through release ACK',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(
        provider: provider,
        unknownPageDecodedEstimate: 100,
      );
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: 'g',
        pages: [ReaderPage(key: 'p')],
      );
      provider.complete(provider.requests.single);
      await scheduler.settled;
      final id = provider.requests.single.requestId;
      expect(scheduler.recordDecoded(id, 10, 20), true);
      provider.releaseGate = Completer<void>();
      final error = StateError('bad client frame');
      scheduler.recordDecodeError(id, error);
      expect(scheduler.snapshot.resources, isEmpty);
      expect(scheduler.snapshot.errors['p'], same(error));
      expect(scheduler.snapshot.estimatedDecodedBytes, 800);
      expect(scheduler.recordDecoded(id, 1, 1), false);
      scheduler.recordDecodeError('foreign', StateError('unrelated'));
      expect(provider.released, [id]);
      provider.releaseGate!.complete();
      await scheduler.settled;
      expect(scheduler.snapshot.estimatedDecodedBytes, 0);
      await scheduler.dispose();
    },
  );

  test(
    'over-budget actual frame is rejected and its full cost stays until release ACK',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(
        provider: provider,
        unknownPageDecodedEstimate: 100,
        maxEstimatedDecodedBytes: 1000,
      );
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: 'g',
        pages: [ReaderPage(key: 'p')],
      );
      provider.complete(provider.requests.single);
      await scheduler.settled;
      provider.releaseGate = Completer<void>();
      final id = provider.requests.single.requestId;
      expect(scheduler.recordDecoded(id, 100, 100), false);
      expect(scheduler.snapshot.resources, isEmpty);
      expect(scheduler.snapshot.errors['p'], isA<ImageBudgetExceeded>());
      expect(scheduler.snapshot.estimatedDecodedBytes, 40000);
      expect(scheduler.snapshot.residentBytes, 10);
      provider.releaseGate!.complete();
      await scheduler.settled;
      expect(scheduler.snapshot.estimatedDecodedBytes, 0);
      await scheduler.dispose();
    },
  );

  test(
    'dispose releases an acquired image waiting for a prefetch eviction ACK exactly once',
    () async {
      final provider = ControlledProvider();
      final scheduler = ImageScheduler(
        provider: provider,
        maxResidentBytes: 100,
      );
      scheduler.setWindow(
        chapterKey: 'chapter',
        generation: 'g',
        pages: pages(2),
      );
      provider.complete(provider.requests[1], bytes: 80);
      await tick();
      provider.releaseGate = Completer<void>();
      provider.complete(provider.requests[0], bytes: 80);
      await tick();
      expect(provider.released, [provider.requests[1].requestId]);
      expect(scheduler.snapshot.residentBytes, 160);
      final disposal = scheduler.dispose();
      expect(
        provider.released,
        containsAll(provider.requests.map((request) => request.requestId)),
      );
      provider.releaseGate!.complete();
      await disposal;
      await tick();
      expect(provider.released, hasLength(2));
      expect(scheduler.snapshot.residentBytes, 0);
    },
  );

  test(
    'new reader schedulers do not reuse image request IDs in one runtime generation',
    () async {
      final provider = ControlledProvider();
      final first = ImageScheduler(provider: provider);
      first.setWindow(chapterKey: 'chapter', generation: 'g', pages: pages(1));
      final a = provider.requests.single;
      provider.complete(a);
      await first.settled;
      await first.dispose();
      final second = ImageScheduler(provider: provider);
      second.setWindow(chapterKey: 'chapter', generation: 'g', pages: pages(1));
      final b = provider.requests.last;
      expect(b.requestId, isNot(a.requestId));
      provider.complete(b);
      await second.settled;
      await second.dispose();
    },
  );
}
