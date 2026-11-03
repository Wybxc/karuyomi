import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:reader_core/reader_core.dart';

ChapterManifest manifest(String version, List<String> keys) => ChapterManifest(
  chapterKey: 'chapter',
  version: version,
  pages: keys.map((key) => ReaderPage(key: key)),
);

void main() {
  test(
    'navigation, restoration and preload do not advance observed progress',
    () {
      final pages = manifest('v1', ['one', 'two', 'three']);
      final initial = ChapterProgress(current: pages.positionAt(0));
      final moved = initial.advance(
        manifest: pages,
        current: pages.positionAt(2),
      );
      expect(moved.current.pageIndexHint, 2);
      expect(moved.furthest, isNull);
      expect(moved.completed, false);
    },
  );

  test('backtracking retains furthest page and normalized offset', () {
    final pages = manifest('v1', ['one', 'two', 'three']);
    final read = ChapterProgress(current: pages.positionAt(0)).advance(
      manifest: pages,
      current: pages.positionAt(1, offset: .8),
      observed: pages.positionAt(1, offset: .8),
    );
    final back = read.advance(
      manifest: pages,
      current: pages.positionAt(0),
      observed: pages.positionAt(1, offset: .2),
    );
    expect(back.current.pageKey, 'one');
    expect(back.furthest!.pageKey, 'two');
    expect(back.furthest!.normalizedOffset, .8);
  });

  test(
    'manifest reordering compares mapped stable pages, never old indexes',
    () {
      final before = manifest('v1', ['one', 'two', 'three']);
      final after = manifest('v2', ['three', 'new', 'one', 'two']);
      final previous = ChapterProgress(
        current: before.positionAt(2),
        furthest: before.positionAt(2, offset: .9),
      );
      final moved = previous.advance(
        manifest: after,
        current: after.positionAt(2),
        observed: after.positionAt(2),
      );
      expect(moved.furthest!.pageKey, 'one');
      expect(moved.furthest!.manifestVersion, 'v2');
      expect(moved.furthest!.pageIndexHint, 2);
      expect(moved.furthestUnresolved(after), false);
    },
  );

  test('missing furthest page stays unresolved without index comparison', () {
    final before = manifest('v1', ['one', 'gone']);
    final after = manifest('v2', ['new', 'one', 'last']);
    final previous = ChapterProgress(
      current: before.positionAt(1),
      furthest: before.positionAt(1, offset: .4),
    );
    final moved = previous.advance(
      manifest: after,
      current: after.positionAt(2),
      observed: after.positionAt(2),
    );
    expect(moved.furthest!.pageKey, 'gone');
    expect(moved.furthest!.manifestVersion, 'v1');
    expect(moved.furthestUnresolved(after), true);
  });

  test('only explicit observed final page completes this manifest version', () {
    final pages = manifest('v1', ['one', 'two']);
    final initial = ChapterProgress(current: pages.positionAt(0));
    expect(
      () => initial.advance(
        manifest: pages,
        current: pages.positionAt(1),
        complete: true,
      ),
      throwsArgumentError,
    );
    expect(
      () => initial.advance(
        manifest: pages,
        current: pages.positionAt(0),
        observed: pages.positionAt(0),
        complete: true,
      ),
      throwsArgumentError,
    );
    final completed = initial.advance(
      manifest: pages,
      current: pages.positionAt(1),
      observed: pages.positionAt(1),
      complete: true,
    );
    expect(completed.completed, true);
    expect(
      completed
          .advance(manifest: pages, current: pages.positionAt(0))
          .completed,
      true,
    );
    final changed = manifest('v2', ['one', 'two', 'new']);
    expect(
      completed
          .advance(manifest: changed, current: changed.positionAt(0))
          .completed,
      false,
    );
  });

  test('identity scopes deployment origin and authenticated subject', () {
    final identity = ProgressIdentity(
      origin: Uri.parse('https://reader.example/path?query=1'),
      subject: 'subject-one',
    );
    expect(identity.origin.toString(), 'https://reader.example');
    expect(
      identity.key,
      ProgressIdentity(
        origin: Uri.parse('https://reader.example'),
        subject: 'subject-one',
      ).key,
    );
    for (final other in [
      ProgressIdentity(
        origin: Uri.parse('https://reader.example:8443'),
        subject: 'subject-one',
      ),
      ProgressIdentity(
        origin: Uri.parse('https://reader.example'),
        subject: 'subject-two',
      ),
      ProgressIdentity(
        origin: Uri.parse('http://reader.example'),
        subject: 'subject-one',
      ),
    ]) {
      expect(other.key, isNot(identity.key));
    }
    expect(
      () => ProgressIdentity(origin: Uri.parse('file:///tmp/db'), subject: 'x'),
      throwsArgumentError,
    );
  });
}
