import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:karuyomi/features/reader/resource_image.dart';
import 'package:karuyomi/features/reader/resource_pool.dart';
import 'package:karuyomi/diagnostics/reader_baseline.dart';
import 'package:reader_core/reader_core.dart';

final class PoolFixture implements PageProvider {
  final releases = <String>[];
  Completer<void>? releaseGate;
  @override
  Future<ImageResource> acquire(PageRef page) async => ImageResource(
    id: 'image',
    generation: 'g',
    location: Uri.parse('blob:https://reader.example/id'),
    byteLength: 20,
  );
  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<void> release(String resourceId) async {
    releases.add(resourceId);
    await releaseGate?.future;
  }
}

void main() {
  testWidgets(
    'crop pixel work keeps a pool pin after the displaying widget leaves',
    (tester) async {
      final fixture = PoolFixture();
      final pool = ReaderResourcePool(fixture, evict: (_) async {});
      final encoded = await pool.acquire(
        const PageRef(
          requestId: 'crop',
          chapterKey: 'c',
          pageKey: 'p',
          generation: 'g',
        ),
      );
      final work = Completer<void>();
      BuildContext? imageContext;
      await tester.pumpWidget(
        PinnedReaderImage(
          pool: pool,
          image: encoded,
          builder: (context) {
            imageContext = context;
            return const SizedBox.shrink();
          },
        ),
      );
      ReaderImageCropWork(encoded.id, work.future).dispatch(imageContext!);
      var released = false;
      final release = pool.release(encoded.id).then((_) => released = true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(released, false);
      expect(fixture.releases, isEmpty);
      work.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      await release;
      expect(fixture.releases, ['image']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'release ACK remains owned but does not leak into a new capture',
    (tester) async {
      final baseline = ReaderBaselineRecorder(
        flushDuration: const Duration(milliseconds: 10),
      )..start();
      addTearDown(baseline.dispose);
      final fixture = PoolFixture()..releaseGate = Completer<void>();
      final pool = ReaderResourcePool(fixture, baseline: baseline);
      await pool.acquire(
        const PageRef(
          requestId: 'r',
          chapterKey: 'c',
          pageKey: 'p',
          generation: 'g',
        ),
      );
      final release = pool.release('image');
      final stopped = baseline.stop();
      await tester.pump(const Duration(milliseconds: 10));
      await stopped;
      expect(
        (baseline.export()['events'] as List).map((e) => e['type']),
        contains('release_sent'),
      );
      baseline.start();
      fixture.releaseGate!.complete();
      await release;
      final next = baseline.stop();
      await tester.pump(const Duration(milliseconds: 10));
      await next;
      expect(
        (baseline.export()['events'] as List).map((e) => e['type']),
        isNot(contains('release_ack')),
      );
      expect(fixture.releases, ['image']);
    },
  );

  testWidgets(
    'scheduler release waits for widget and overlay pins, then cache eviction',
    (tester) async {
      final baseline = ReaderBaselineRecorder(
        flushDuration: const Duration(milliseconds: 10),
      )..start();
      addTearDown(baseline.dispose);
      final fixture = PoolFixture();
      final events = <String>[];
      final eviction = Completer<void>();
      final pool = ReaderResourcePool(
        fixture,
        baseline: baseline,
        evict: (image) async {
          events.add('evict');
          await eviction.future;
        },
      );
      await pool.acquire(
        const PageRef(
          requestId: 'r',
          chapterKey: 'c',
          pageKey: 'p',
          generation: 'g',
        ),
      );
      final widget = pool.pin('image');
      final overlay = pool.pin('image');
      final release = pool.release('image');
      final unpin = widget.close();
      await tester.pump();
      await unpin;
      expect(fixture.releases, isEmpty);
      expect(events, isEmpty);
      final removeOverlay = overlay.close();
      await tester.pump();
      expect(events, ['evict']);
      expect(fixture.releases, isEmpty);
      eviction.complete();
      await removeOverlay;
      await release;
      expect(fixture.releases, ['image']);
      await pool.release('image');
      expect(fixture.releases, hasLength(1));
      final stopped = baseline.stop();
      await tester.pump(const Duration(milliseconds: 10));
      await stopped;
      final captured = (baseline.export()['events'] as List)
          .cast<Map<String, Object?>>();
      expect(
        captured
            .map((e) => e['type'])
            .where((name) => (name as String).startsWith('release_')),
        ['release_requested', 'release_sent', 'release_ack'],
      );
    },
  );
}
