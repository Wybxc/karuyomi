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
        mimeType: 'image/png',
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
}
