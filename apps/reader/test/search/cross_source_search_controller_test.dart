import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/search/cross_source_search_controller.dart';

import 'fakes.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeSourceSearch service;
  late CrossSourceSearchController controller;
  bool current = true;

  setUp(() {
    current = true;
    service = FakeSourceSearch();
    controller = CrossSourceSearchController(
      service: service,
      isCurrent: () => current,
    );
  });

  tearDown(() async {
    controller.dispose();
    await _settle();
  });

  Future<void> selectAll() async {
    await controller.loadTargets();
    for (final target in controller.targets) {
      controller.select(target, true);
    }
  }

  test('loading choices is read-only and selection is explicit', () async {
    await controller.loadTargets();
    expect(controller.targets, hasLength(2));
    expect(controller.selected, isEmpty);
    expect(service.tasks, isEmpty);
    await controller.start('作品');
    expect(service.tasks, isEmpty);
    expect(controller.error, contains('请选择'));
    controller.selectLanguage('zh');
    expect(controller.visibleTargets.single.source.id, '2');
  });

  test('one slow or failed Source does not hide another result', () async {
    service.autoStart = false;
    await selectAll();
    await controller.start('作品');
    expect(controller.groups.map((group) => group.status), [
      SourceSearchStatus.queued,
      SourceSearchStatus.queued,
    ]);
    service.tasks.first.start();
    expect(controller.groups.first.status, SourceSearchStatus.loading);
    final manga = searchManga('先完成');
    service.tasks.first.complete([manga]);
    await _settle();
    expect(controller.groups.first.mangas, [manga]);
    expect(controller.groups.last.status, SourceSearchStatus.queued);
    service.tasks.last.fail('该源暂时不可用');
    await _settle();
    expect(controller.groups.last.error, '该源暂时不可用');
    expect(controller.groups.first.mangas, [manga]);
  });

  test(
    'pagination and explicit retry retain the frozen source query',
    () async {
      await controller.loadTargets();
      controller.select(controller.targets.first, true);
      await controller.start('  原查询  ');
      service.tasks.single.complete([searchManga('第一页')], more: true);
      await _settle();
      final group = controller.groups.single;
      expect(service.tasks, hasLength(1));
      controller.next(group);
      expect(service.tasks.last.page, 2);
      expect(service.tasks.last.query, '原查询');
      service.tasks.last.fail('第二页失败');
      await _settle();
      expect(group.mangas.single.title, '第一页');
      controller.next(group);
      expect(service.tasks.last.page, 2);
      service.tasks.last.complete([searchManga('第二页')]);
      await _settle();
      expect(group.mangas.map((manga) => manga.title), ['第一页', '第二页']);
      expect(group.page, 2);
      expect(group.hasNextPage, false);
    },
  );

  test(
    'a new query waits for old cleanup and ignores late old results',
    () async {
      await controller.loadTargets();
      controller.select(controller.targets.first, true);
      await controller.start('旧查询');
      final old = service.tasks.single;
      final gate = Completer<void>();
      service.beforeStop = () => gate.future;
      final starting = controller.start('新查询');
      await _settle();
      expect(service.tasks, hasLength(1));
      expect(controller.transitioning, true);
      old.complete([searchManga('迟到的旧结果')]);
      await _settle();
      expect(controller.resultCount, 0);
      gate.complete();
      await starting;
      expect(service.tasks, hasLength(2));
      expect(service.tasks.last.query, '新查询');
      expect(controller.groups.single.mangas, isEmpty);
    },
  );

  test(
    'failed cancellation retains a retryable stop before new work',
    () async {
      await controller.loadTargets();
      controller.select(controller.targets.first, true);
      await controller.start('作品');
      final task = service.tasks.single;
      var attempts = 0;
      task.beforeCancel = () async {
        if (++attempts == 1) throw const FormatException('ACK丢失');
      };
      final group = controller.groups.single;
      await controller.cancel(group);
      expect(group.status, SourceSearchStatus.cancellationFailed);
      expect(group.error, contains('ACK丢失'));
      expect(task.completion.isCompleted, false);
      await controller.cancel(group);
      expect(group.status, SourceSearchStatus.cancelled);
      controller.next(group);
      expect(service.tasks, hasLength(2));
      expect(service.tasks.last.page, 1);
    },
  );

  test(
    'a late individual cancel failure cannot overwrite confirmed global stop',
    () async {
      await controller.loadTargets();
      controller.select(controller.targets.first, true);
      await controller.start('作品');
      final task = service.tasks.single;
      final gate = Completer<void>();
      var attempts = 0;
      task.beforeCancel = () async {
        if (++attempts == 1) await gate.future;
      };
      final group = controller.groups.single;
      final cancelling = controller.cancel(group);
      await _settle();
      expect(await controller.stop(), true);
      gate.completeError(const FormatException('旧停止请求失败'));
      await cancelling;
      expect(group.status, SourceSearchStatus.cancelled);
      expect(group.error, isNull);
      expect(group.errorDetails, isNull);
      expect(controller.cleanupError, isNull);
    },
  );

  test(
    'confirmed global stop clears the previous cancellation failure',
    () async {
      await controller.loadTargets();
      controller.select(controller.targets.first, true);
      await controller.start('作品');
      var attempts = 0;
      service.tasks.single.beforeCancel = () async {
        if (++attempts == 1) throw const FormatException('停止确认丢失');
      };
      final group = controller.groups.single;
      await controller.cancel(group);
      expect(group.errorDetails, contains('停止确认丢失'));
      expect(await controller.stop(), true);
      expect(group.status, SourceSearchStatus.cancelled);
      expect(group.error, isNull);
      expect(group.errorDetails, isNull);
      expect(controller.canContinue(group), true);
    },
  );

  test('selection and query bounds never silently truncate input', () async {
    service.targets = List.generate(33, (index) => searchTarget(index + 1));
    await selectAll();
    expect(controller.selected, hasLength(32));
    expect(controller.error, contains('最多选择32'));
    await controller.start('a' * 501);
    expect(service.tasks, isEmpty);
    expect(controller.error, contains('500'));
  });

  test('a page exceeding the per-Source budget is rejected whole', () async {
    await controller.loadTargets();
    controller.select(controller.targets.first, true);
    await controller.start('作品');
    service.tasks.single.complete(
      List.generate(201, (index) => searchManga('作品$index')),
    );
    await _settle();
    final group = controller.groups.single;
    expect(group.mangas, isEmpty);
    expect(group.limitReason, contains('200'));
    expect(controller.canContinue(group), false);
    expect(group.page, 0);
  });

  test(
    'the total budget preserves accepted results and rejects the next page',
    () async {
      service.targets = List.generate(6, (index) => searchTarget(index + 1));
      await selectAll();
      await controller.start('作品');
      for (var source = 0; source < 5; source++) {
        service.tasks[source].complete(
          List.generate(200, (index) => searchManga('作品$source-$index')),
        );
        await _settle();
      }
      expect(controller.resultCount, 1000);
      service.tasks.last.complete([searchManga('超预算')]);
      await _settle();
      expect(controller.resultCount, 1000);
      expect(controller.groups.last.mangas, isEmpty);
      expect(controller.groups.last.limitReason, contains('1000'));
    },
  );

  test(
    'identity retirement is permanent and late results never appear',
    () async {
      await selectAll();
      await controller.start('作品');
      service.changeAvailability(false);
      service.tasks.first.complete([searchManga('迟到')]);
      await _settle();
      service.changeAvailability(true);
      expect(controller.available, false);
      expect(controller.resultCount, 0);
      final count = service.tasks.length;
      await controller.start('另一个查询');
      expect(service.tasks, hasLength(count));
    },
  );

  test(
    'opening retains exact target and suppresses navigation after route loss',
    () async {
      await controller.loadTargets();
      controller.select(controller.targets.first, true);
      await controller.start('作品');
      final manga = searchManga('结果');
      service.tasks.single.complete([manga]);
      await _settle();
      final group = controller.groups.single;
      final gate = Completer<void>();
      service.beforeOpen = () => gate.future;
      final opening = controller.open(group, manga);
      await _settle();
      expect(service.openedTarget, same(group.target));
      expect(service.openedManga, same(manga));
      current = false;
      gate.complete();
      expect(await opening, isNull);
      expect(service.openCurrent!(), false);
    },
  );

  test(
    'failed close keeps cleanup visible and a second close can succeed',
    () async {
      var attempts = 0;
      service.beforeClose = () async {
        if (++attempts == 1) throw const FormatException('关闭ACK丢失');
      };
      expect(await controller.close(), false);
      expect(controller.cleanupError, contains('关闭ACK丢失'));
      expect(controller.available, false);
      expect(await controller.close(), true);
      expect(controller.cleanupError, isNull);
      expect(service.closes, 2);
    },
  );
}
