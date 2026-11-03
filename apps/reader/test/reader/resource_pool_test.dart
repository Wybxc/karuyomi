import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/reader/resource_pool.dart';
import 'package:reader_core/reader_core.dart';

final class PoolFixture implements PageProvider {
  final releases = <String>[];
  @override
  Future<ImageResource> acquire(PageRef page) async => ImageResource(
    id: 'image',
    generation: 'g',
    location: Uri.parse('blob:https://reader.example/id'),
    mimeType: 'image/png',
    byteLength: 20,
    width: 10,
    height: 20,
  );
  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<void> release(String resourceId) async {
    releases.add(resourceId);
  }
}

void main() {
  testWidgets(
    'scheduler release waits for widget and overlay pins, then cache eviction',
    (tester) async {
      final fixture = PoolFixture();
      final events = <String>[];
      final eviction = Completer<void>();
      final pool = ReaderResourcePool(
        fixture,
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
    },
  );
}
