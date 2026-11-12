import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/scheduler.dart';

import '../browse/catalog_controller.dart';
import 'chapter_read_batch.dart';
import 'chapter_read_controller.dart';

Future<Set<String>?> showChapterReadDialog({
  required BuildContext context,
  required CatalogController catalog,
  required ChapterReadController progress,
  required ChapterReadBatchDraft draft,
  required bool Function() isCurrent,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showDialog<Set<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ChapterReadDialog(
      catalog: catalog,
      progress: progress,
      draft: draft,
      isCurrent: isCurrent,
    ),
  );
}

class _ChapterReadDialog extends StatefulHookWidget {
  const _ChapterReadDialog({
    required this.catalog,
    required this.progress,
    required this.draft,
    required this.isCurrent,
  });
  final CatalogController catalog;
  final ChapterReadController progress;
  final ChapterReadBatchDraft draft;
  final bool Function() isCurrent;

  @override
  State<_ChapterReadDialog> createState() => _ChapterReadDialogState();
}

class _ChapterReadDialogState extends State<_ChapterReadDialog> {
  final _accepted = <String>{};
  bool _expired = false;
  bool _acceptedReload = false;
  ChapterReadBatchDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _expired = !widget.isCurrent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _changed();
    });
  }

  bool get _current {
    _checkSession();
    return mounted && !_expired;
  }

  void _checkSession() {
    if (!mounted || _expired || widget.isCurrent()) return;
    _expired = true;
    draft.pause();
    _changed();
  }

  void _changed() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _update();
      });
    } else {
      _update();
    }
  }

  void _update() {
    if (!_expired && widget.isCurrent()) {
      for (final item in draft.items) {
        final confirmation = item.confirmation;
        if (confirmation != null && _accepted.add(item.chapter.key)) {
          widget.progress.acceptConfirmed(item.chapter.key, confirmation);
        }
      }
      final snapshot = draft.reloaded;
      if (snapshot != null && !_acceptedReload) {
        _acceptedReload = true;
        widget.progress.acceptSnapshot(snapshot);
      }
    }
    setState(() {});
  }

  Future<void> _start() async {
    if (!_current) return;
    await draft.start(isCurrent: () => _current);
    if (mounted) _checkSession();
  }

  Future<void> _retry() async {
    if (!_current) return;
    await draft.retry(isCurrent: () => _current);
    if (mounted) _checkSession();
  }

  Future<void> _continue() async {
    if (!_current) return;
    await draft.continueRemaining(isCurrent: () => _current);
    if (mounted) _checkSession();
  }

  Future<void> _reload() async {
    if (!_current) return;
    await draft.reloadAndFinish(isCurrent: () => _current);
    if (mounted) _checkSession();
  }

  void _close() {
    if ((!_expired && draft.busy) ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    Navigator.pop(
      context,
      _current && draft.attempted ? draft.remainingKeys : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    useOnListenableChange(widget.catalog, _checkSession);
    useOnListenableChange(widget.progress, _checkSession);
    useOnListenableChange(draft, _changed);
    return PopScope<Set<String>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AlertDialog(
        title: Text(draft.read ? '标记为已读' : '标记为未读'),
        content: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(context).height * .55,
          child: ListView(
            children: [
              Text('确认清单：${draft.items.length} 章'),
              const Text('逐章保存，首项失败后暂停；不会加载页面或改变继续阅读的位置。'),
              if (_expired) const Text('身份或服务已变化，原窗口已停用。请关闭后重新打开。'),
              if (draft.attempted) ...[
                Text(
                  '已确认 ${draft.confirmedCount} / ${draft.items.length} 章 · 未开始 ${draft.notStartedCount} 章',
                ),
                if (draft.busy) const LinearProgressIndicator(),
                if (draft.busy && draft.pauseRequested)
                  const Text('已请求暂停，等待当前操作结束后可关闭。'),
                if (!_expired && draft.completed) const Text('全部标记已由服务端确认。'),
                if (!_expired && draft.finished && !draft.completed)
                  const Text('原批次已结束，剩余章节未再发送。请按最新状态重新确认。'),
                if (!draft.finished) const Text('当前会话保留原清单和未确认操作；关闭不会撤回已发请求。'),
              ],
              if (draft.error case final error?) Text(error),
              for (final item in draft.items)
                ListTile(
                  key: ValueKey(('chapter-read-item', item.chapter.key)),
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.chapter.name),
                  subtitle: Text(
                    [
                      '来源第 ${item.chapter.sourceIndex + 1} 项',
                      if (draft.attempted)
                        switch (item.status) {
                          ChapterReadItemStatus.notStarted => '未开始',
                          ChapterReadItemStatus.sending => '正在等待服务端确认',
                          ChapterReadItemStatus.confirmed => '已由服务端确认',
                          ChapterReadItemStatus.uncertain => '尚未确认，需重试原操作',
                          ChapterReadItemStatus.blocked => '未保存，需重新读取',
                        },
                      ?item.error,
                    ].join('\n'),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (!_expired && draft.busy)
            TextButton(
              onPressed: draft.pauseRequested ? null : draft.pause,
              child: const Text('暂停剩余操作'),
            ),
          TextButton(
            onPressed: !_expired && draft.busy ? null : _close,
            child: Text(
              !draft.attempted
                  ? '取消'
                  : draft.finished
                  ? '完成'
                  : '稍后处理',
            ),
          ),
          if (!draft.attempted)
            FilledButton(
              onPressed: _expired ? null : _start,
              child: const Text('确认并开始'),
            ),
          if (draft.canRetry)
            FilledButton(
              onPressed: _expired ? null : _retry,
              child: const Text('重试原未确认操作'),
            ),
          if (draft.canContinue) ...[
            FilledButton(
              onPressed: _expired ? null : _continue,
              child: const Text('继续剩余原清单'),
            ),
            TextButton(
              onPressed: _expired
                  ? null
                  : () {
                      if (_current) draft.finishRemaining();
                    },
              child: const Text('结束剩余操作'),
            ),
          ],
          if (draft.canReloadAndFinish)
            FilledButton(
              onPressed: _expired ? null : _reload,
              child: const Text('重新读取并结束原批次'),
            ),
        ],
      ),
    );
  }
}
