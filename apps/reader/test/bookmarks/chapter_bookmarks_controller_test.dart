import '../../test_support/cupertino.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/bookmark_repository.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/bookmarks/bookmark_status.dart';
import 'package:karuyomi/features/bookmarks/chapter_bookmarks_controller.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';

import '../data/business_state_server.dart';

const _mangaKey =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _chapter = 'chapter-one';

ProgressIdentity get _identity => ProgressIdentity(
  origin: Uri.parse('https://reader.example.com'),
  subject: 'owner-subject',
);

/// Delays a real supplier response after the server has applied the mutation.
final class _ResponseGate implements ApiFetch {
  _ResponseGate(this.api);
  final ApiFetch api;
  Completer<void>? received;
  Completer<void>? release;
  bool _holdNextWrite = false;

  void holdNextWrite() {
    _holdNextWrite = true;
    received = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final hold = _holdNextWrite && method == 'POST';
    if (hold) _holdNextWrite = false;
    final reply = await api.fetchApi(
      path,
      method: method,
      headers: headers,
      body: body,
    );
    if (hold) {
      received!.complete();
      await release!.future;
    }
    return reply;
  }
}

void main() {
  late TestBusinessServer server;
  late _ResponseGate gate;
  late BusinessStateClient client;
  late BookmarkRepository repository;
  late ChapterBookmarksController controller;
  late bool current;
  late bool disposed;

  setUp(() {
    server = TestBusinessServer();
    gate = _ResponseGate(server);
    client = BusinessStateClient(api: gate, identity: _identity);
    repository = BookmarkRepository(client);
    current = true;
    disposed = false;
    controller = ChapterBookmarksController(
      repository: repository,
      mangaKey: _mangaKey,
      isCurrent: () => current,
    );
  });

  tearDown(() async {
    if (!disposed) controller.dispose();
    await client.dispose();
  });

  Iterable<TestBusinessRequest> getWrites() =>
      server.requests.where((request) => request.method == 'POST');

  test('a bookmark becomes confirmed only after its server ACK', () async {
    expect(controller.canEdit, false);
    await controller.refresh();
    expect(controller.loaded, true);
    expect(controller.contains(_chapter), false);
    gate.holdNextWrite();
    final write = controller.setBookmarked(_chapter, true);
    await gate.received!.future;
    expect(server.bookmarked(_mangaKey, _chapter), true);
    expect(controller.contains(_chapter), false);
    expect(controller.busy, true);
    expect(controller.canEdit, false);
    gate.release!.complete();
    await write;
    expect(controller.contains(_chapter), true);
    expect(controller.canEdit, true);
    expect(controller.pending, isNull);
    expect(controller.error, isNull);
  });

  for (final loseReply in [false, true]) {
    test(
      'an uncertain write requires the exact explicit retry (lost reply: $loseReply)',
      () async {
        await controller.refresh();
        if (loseReply) {
          server.loseNextResponse = true;
        } else {
          server.beforeRequest = (request) {
            if (request.method == 'POST') {
              throw StateError('Injected failure before sending');
            }
            return null;
          };
        }
        await controller.setBookmarked(_chapter, true);
        expect(controller.error, contains('尚未确认'));
        expect(controller.contains(_chapter), false);
        expect(controller.pending!.chapterKey, _chapter);
        expect(controller.pending!.bookmarked, true);
        expect(controller.pending!.retryable, true);
        expect(controller.canEdit, false);
        expect(controller.canRetry, true);
        final original = getWrites().single.body;
        server.beforeRequest = null;
        await controller.setBookmarked('chapter-two', true);
        await controller.refresh();
        expect(getWrites(), hasLength(1));
        expect(controller.pending, isNotNull);
        expect(controller.canEdit, false);
        await controller.retry();
        expect(getWrites().map((request) => request.body), [
          original,
          original,
        ]);
        expect(server.appliedMutations, 1);
        expect(controller.contains(_chapter), true);
        expect(controller.contains('chapter-two'), false);
        expect(controller.pending, isNull);
        expect(controller.canEdit, true);
      },
    );
  }

  test('a conflict requires a complete refresh before a new edit', () async {
    await controller.refresh();
    final remoteClient = BusinessStateClient(api: server, identity: _identity);
    addTearDown(remoteClient.dispose);
    final remote = BookmarkRepository(remoteClient);
    await remote.set(
      mangaKey: _mangaKey,
      chapterKey: 'remote-chapter',
      bookmarked: true,
      basedOnRevision: 0,
    );
    await controller.setBookmarked(_chapter, true);
    expect(controller.error, contains('其他设备修改'));
    expect(controller.loaded, false);
    expect(controller.contains(_chapter), false);
    expect(controller.canRetry, false);
    expect(controller.pending!.retryable, false);
    final writes = getWrites().length;
    await controller.retry();
    await controller.setBookmarked('chapter-two', true);
    expect(getWrites(), hasLength(writes));
    await controller.refresh();
    expect(controller.chapterKeys, {'remote-chapter'});
    expect(controller.pending, isNull);
    expect(controller.canEdit, true);
    await controller.setBookmarked(_chapter, true);
    expect(controller.chapterKeys, {'remote-chapter', _chapter});
    expect(server.appliedMutations, 2);
  });

  test('identity changes retire the page before a late ACK', () async {
    await controller.refresh();
    gate.holdNextWrite();
    final write = controller.setBookmarked(_chapter, true);
    await gate.received!.future;
    current = false;
    controller.checkCurrent();
    expect(controller.error, contains('身份或服务已改变'));
    expect(controller.available, false);
    gate.release!.complete();
    await write;
    expect(controller.contains(_chapter), false);
    expect(controller.error, contains('身份或服务已改变'));
    final writes = getWrites().length;
    current = true;
    await controller.refresh();
    await controller.setBookmarked('chapter-two', true);
    expect(controller.available, false);
    expect(getWrites(), hasLength(writes));
  });

  test('disposing a page drops a late ACK and does not notify it', () async {
    await controller.refresh();
    var notifications = 0;
    controller.addListener(() => notifications++);
    gate.holdNextWrite();
    final write = controller.setBookmarked(_chapter, true);
    await gate.received!.future;
    controller.dispose();
    disposed = true;
    final before = notifications;
    gate.release!.complete();
    await write;
    expect(controller.contains(_chapter), false);
    expect(notifications, before);
    expect(server.bookmarked(_mangaKey, _chapter), true);
  });

  test(
    'read failures disable edits until an explicit successful refresh',
    () async {
      server.failNextRequest = true;
      await controller.refresh();
      expect(controller.loaded, false);
      expect(controller.error, contains('仍可继续阅读'));
      expect(controller.canEdit, false);
      await controller.setBookmarked(_chapter, true);
      expect(getWrites(), isEmpty);
      await controller.refresh();
      expect(controller.loaded, true);
      expect(controller.canEdit, true);
      expect(controller.error, isNull);
    },
  );

  test(
    'an ACK followed by a failed refresh preserves its confirmed value',
    () async {
      await controller.refresh();
      var written = false;
      server.beforeRequest = (request) {
        if (request.method == 'POST') written = true;
        if (written && request.uri.path.endsWith('/bookmarks')) {
          throw StateError('Injected post-ACK read failure');
        }
        return null;
      };
      await controller.setBookmarked(_chapter, true);
      expect(server.bookmarked(_mangaKey, _chapter), true);
      expect(controller.contains(_chapter), true);
      expect(controller.pending, isNull);
      expect(controller.loaded, false);
      expect(controller.canEdit, false);
      expect(controller.error, contains('书签已保存，但重新读取失败'));
      server.beforeRequest = null;
      await controller.refresh();
      expect(controller.contains(_chapter), true);
      expect(controller.canEdit, true);
      expect(getWrites(), hasLength(1));
    },
  );

  Future<void> show(WidgetTester tester) => tester.pumpWidget(
    CupertinoApp(
      home: CupertinoPageScaffold(
        child: Column(
          children: [
            BookmarkStatus(controller: controller),
            ChapterBookmarkButton(
              controller: controller,
              chapterKey: _chapter,
              chapterName: '第一章',
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  testWidgets('the shared chapter button marks and removes a server bookmark', (
    tester,
  ) async {
    await show(tester);
    expect(
      tester
          .widget<CupertinoButton>(
            find.byKey(const ValueKey('chapter-bookmark-$_chapter')),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, find.text('刷新书签'));
    await tap(tester, iconLabel('标记章节书签 第一章'));
    expect(server.bookmarked(_mangaKey, _chapter), true);
    expect(iconLabel('移除章节书签 第一章'), findsOneWidget);
    await tap(tester, iconLabel('移除章节书签 第一章'));
    expect(server.bookmarked(_mangaKey, _chapter), false);
    expect(iconLabel('标记章节书签 第一章'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'the shared status exposes an explicit retry without resending on refresh',
    (tester) async {
      await show(tester);
      await tap(tester, find.text('刷新书签'));
      server.failWrites = true;
      await tap(tester, iconLabel('标记章节书签 第一章'));
      expect(find.text('本会话有尚未确认的书签操作；刷新不会自动重发。'), findsOneWidget);
      expect(find.text('重试原书签操作'), findsOneWidget);
      expect(
        tester
            .widget<CupertinoButton>(
              find.byKey(const ValueKey('chapter-bookmark-$_chapter')),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, find.text('刷新书签'));
      expect(getWrites(), hasLength(1));
      server.failWrites = false;
      await tap(tester, find.text('重试原书签操作'));
      expect(getWrites(), hasLength(2));
      expect(server.appliedMutations, 1);
      expect(find.text('重试原书签操作'), findsNothing);
      expect(iconLabel('移除章节书签 第一章'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
