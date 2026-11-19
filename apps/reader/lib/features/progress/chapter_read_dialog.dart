import '../../widgets/edit_sheet.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_theme.dart';
import '../browse/catalog_controller.dart';
import 'chapter_read_batch.dart';
import 'chapter_read_controller.dart';

Future<Set<String>?> showChapterReadDialog({
  required BuildContext context,
  required CatalogController catalog,
  required ChapterReadController progress,
  required ChapterReadBatchDraft draft,
  required MangaEditContext target,
  required bool Function() isCurrent,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showCupertinoSheet<Set<String>>(
    context: context,
    enableDrag: false,
    scrollableBuilder: (context, _) => _ChapterReadDialog(
      catalog: catalog,
      progress: progress,
      draft: draft,
      target: target,
      isCurrent: isCurrent,
    ),
  );
}

class const _ChapterReadDialog({
  required final CatalogController catalog,
  required final ChapterReadController progress,
  required final ChapterReadBatchDraft draft,
  required final MangaEditContext target,
  required final bool Function() isCurrent,
}) extends StatefulHookWidget {
  @override
  State<_ChapterReadDialog> createState() => _ChapterReadDialogState();
}

class _ChapterReadDialogState extends State<_ChapterReadDialog> {
  final _accepted = <String>{};
  String? _expiration;
  bool _acceptedReload = false;
  bool get _expired => _expiration != null;
  ChapterReadBatchDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    if (!widget.isCurrent()) _expiration = _expiryMessage();
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
    _expiration = _expiryMessage();
    draft.pause();
    _changed();
  }

  String _expiryMessage() => switch (widget.catalog.status) {
    ServiceStatus.loginRequired => '访问验证已失效，原窗口已停用。',
    ServiceStatus.denied => '原连接已无权限，原窗口已停用。',
    _ => '身份、服务或漫画源已变化，原窗口已停用。',
  };

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

  Widget _entry(ChapterReadBatchItem item) {
    final theme = CupertinoTheme.of(context).textTheme.textStyle;
    final chapter = item.chapter;
    final scanlator = chapter.snapshot.scanlator;
    return CupertinoListTile(
      key: ValueKey(('chapter-read-item', chapter.key)),
      title: DefaultTextStyle(style: theme, child: Text(chapter.name)),
      subtitle: DefaultTextStyle(
        style: theme.copyWith(
          fontSize: 13,
          color: AppColors.secondaryLabel.resolveFrom(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '来源第 ${chapter.sourceIndex + 1} 项${scanlator.isEmpty ? '' : ' · $scanlator'}',
            ),
            if (draft.attempted)
              Text(
                switch (item.status) {
                  ChapterReadItemStatus.notStarted => '未开始',
                  ChapterReadItemStatus.sending =>
                    _expired ? '已发送，结果待核实' : '正在等待服务端确认',
                  ChapterReadItemStatus.confirmed => '已由服务端确认',
                  ChapterReadItemStatus.uncertain =>
                    _expired ? '尚未确认' : '尚未确认，需重试原操作',
                  ChapterReadItemStatus.blocked =>
                    _expired ? '未保存' : '未保存，需重新读取',
                },
                style: TextStyle(
                  color: switch (item.status) {
                    ChapterReadItemStatus.confirmed =>
                      AppColors.label.resolveFrom(context),
                    ChapterReadItemStatus.uncertain ||
                    ChapterReadItemStatus.blocked =>
                      AppColors.error.resolveFrom(context),
                    _ => null,
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summary() {
    final failure = draft.failedItem?.status;
    final errorColor = AppColors.error.resolveFrom(context);
    final noteColor = AppColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            container: true,
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_expiration case final reason?)
                  Text(reason, style: TextStyle(color: errorColor)),
                if (draft.attempted)
                  Text(
                    [
                      '已确认 ${draft.confirmedCount} / ${draft.items.length} 章',
                      if (failure == ChapterReadItemStatus.uncertain)
                        '尚未确认 1 章',
                      if (failure == ChapterReadItemStatus.blocked) '未保存 1 章',
                      '未开始 ${draft.notStartedCount} 章',
                    ].join(' · '),
                  ),
                if (!_expired && draft.busy)
                  Row(
                    children: [
                      const CupertinoActivityIndicator(),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          draft.pauseRequested
                              ? '已请求暂停，等待当前操作结束后可关闭。'
                              : failure == ChapterReadItemStatus.blocked
                              ? '正在重新读取章节状态'
                              : '正在等待服务端确认',
                        ),
                      ),
                    ],
                  ),
                if (!_expired && draft.completed) const Text('全部标记已由服务端确认。'),
                if (!_expired && draft.finished && !draft.completed)
                  const Text('原批次已结束，剩余章节未再发送。请按最新状态重新确认。'),
                if (draft.error case final error? when !_expired)
                  Text(error, style: TextStyle(color: errorColor)),
              ],
            ),
          ),
          if (_expired)
            Text('请关闭并重新连接服务，再打开原作品查看章节标记。', style: TextStyle(color: noteColor))
          else if (draft.attempted && !draft.finished)
            Semantics(
              container: true,
              child: Text(
                '当前会话保留原清单和未确认操作；关闭不会撤回已发请求。',
                style: TextStyle(color: noteColor),
              ),
            ),
          if (!_expired && draft.busy)
            Semantics(
              key: const ValueKey('chapter-read-pause'),
              container: true,
              enabled: !draft.pauseRequested,
              child: CupertinoButton(
                onPressed: draft.pauseRequested ? null : draft.pause,
                child: const Text('暂停剩余操作'),
              ),
            ),
          if (!_expired && draft.canContinue)
            Semantics(
              key: const ValueKey('chapter-read-end'),
              container: true,
              child: CupertinoButton(
                onPressed: () {
                  if (_current) draft.finishRemaining();
                },
                child: const Text('结束剩余操作'),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    useOnListenableChange(widget.catalog, _checkSession);
    useOnListenableChange(widget.progress, _checkSession);
    useOnListenableChange(draft, _changed);
    final canClose = _expired || !draft.busy;
    return PopScope<Set<String>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: EditSheet(
        key: const ValueKey('chapter-read-review'),
        title: Text(draft.read ? '标记为已读' : '标记为未读'),
        leading: draft.finished && !_expired
            ? null
            : Semantics(
                enabled: canClose,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: canClose ? _close : null,
                  child: Text(
                    _expired
                        ? '关闭'
                        : draft.attempted
                        ? '稍后'
                        : '取消',
                    semanticsLabel: !_expired && draft.attempted
                        ? '稍后处理'
                        : null,
                  ),
                ),
              ),
        trailing: _expired
            ? null
            : draft.finished
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _close,
                child: const Text('完成'),
              )
            : !draft.attempted
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _start,
                child: const Text('开始', semanticsLabel: '确认并开始'),
              )
            : draft.canRetry
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _retry,
                child: const Text('重试', semanticsLabel: '重试原未确认操作'),
              )
            : draft.canContinue
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _continue,
                child: const Text('继续', semanticsLabel: '继续剩余原清单'),
              )
            : draft.canReloadAndFinish
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _reload,
                child: const Text('重读', semanticsLabel: '重新读取并结束原批次'),
              )
            : null,
        content: ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            widget.target,
            if (_expired || draft.attempted || draft.error != null) _summary(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('确认清单：${draft.items.length} 章'),
                  if (!_expired && !draft.attempted)
                    Text(
                      '逐章保存，首项失败后暂停；不会加载页面或改变继续阅读的位置。',
                      style: TextStyle(
                        color: AppColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                ],
              ),
            ),
            for (final item in draft.items) _entry(item),
          ],
        ),
      ),
    );
  }
}
