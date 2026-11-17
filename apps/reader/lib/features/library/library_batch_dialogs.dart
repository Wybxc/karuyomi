import '../../widgets/edit_sheet.dart';
import '../../theme/app_theme.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/scheduler.dart';

import '../../data/library_repository.dart';
import '../browse/catalog_controller.dart';
import 'category_dialogs.dart';
import 'library_batch.dart';

Future<Set<String>?> showLibraryBatchDialog({
  required BuildContext context,
  required CatalogController controller,
  required LibraryRepository repository,
  required LibraryView view,
  required Set<String> mangaKeys,
  required LibraryBatchAction action,
  required Listenable lifecycle,
  required bool Function() isCurrent,
}) {
  if (hasPendingLibraryCategoryEdit(repository)) {
    return Future.value(null);
  }
  FocusManager.instance.primaryFocus?.unfocus();
  return showCupertinoSheet<Set<String>>(
    context: context,
    enableDrag: false,
    scrollableBuilder: (context, _) => _LibraryBatchDialog(
      controller: controller,
      repository: repository,
      view: view,
      mangaKeys: Set.unmodifiable(mangaKeys),
      action: action,
      lifecycle: lifecycle,
      isCurrent: isCurrent,
      pending: pendingLibraryBatch(repository),
    ),
  );
}

class const _LibraryBatchDialog({
  required final CatalogController controller,
  required final LibraryRepository repository,
  required final LibraryView view,
  required final Set<String> mangaKeys,
  required final LibraryBatchAction action,
  required final Listenable lifecycle,
  required final bool Function() isCurrent,
  required final LibraryBatchDraft? pending,
}) extends StatefulHookWidget {
  @override
  State<_LibraryBatchDialog> createState() => _LibraryBatchDialogState();
}

class _LibraryBatchDialogState extends State<_LibraryBatchDialog> {
  final _categoryIds = <String>{};
  late final _view = widget.pending?.view ?? widget.view;
  late final _action = widget.pending?.action ?? widget.action;
  late final _entries = List<LibraryEntry>.unmodifiable(
    widget.pending?.items.map((item) => item.entry) ??
        _view.entries.where(
          (entry) => widget.mangaKeys.contains(entry.mangaKey),
        ),
  );
  late LibraryBatchDraft? _draft = widget.pending;
  bool _expired = false;
  String? _error;

  String get _title => switch (_action) {
    LibraryBatchAction.removeFavorites => '批量移出书架',
    LibraryBatchAction.addCategories => '批量添加分类',
    LibraryBatchAction.removeCategories => '批量移出分类',
  };

  bool get _needsCategories => _action != LibraryBatchAction.removeFavorites;
  bool get _current {
    _checkSession();
    return mounted && !_expired;
  }

  void _selectCategory(String id, bool selected) {
    if (!_current || _draft != null) return;
    setState(() {
      if (selected) {
        _categoryIds.add(id);
      } else {
        _categoryIds.remove(id);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _expired = !widget.isCurrent();
  }

  void _checkSession() {
    if (!mounted || _expired || widget.isCurrent()) return;
    _expired = true;
    _draft?.pause();
    _draftChanged();
  }

  void _draftChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _start() async {
    if (!_current ||
        _draft != null ||
        _entries.isEmpty ||
        (_needsCategories && _categoryIds.isEmpty)) {
      return;
    }
    if (hasPendingLibraryCategoryEdit(widget.repository)) {
      setState(() => _error = '请先处理书架中的未确认分类修改。');
      return;
    }
    try {
      final draft = LibraryBatchDraft(
        repository: widget.repository,
        view: _view,
        mangaKeys: _entries.map((entry) => entry.mangaKey).toSet(),
        action: _action,
        categoryIds: Set.unmodifiable(_categoryIds),
      );
      setState(() {
        _draft = draft;
        _error = null;
      });
      await draft.start(isCurrent: () => _current);
      if (!mounted) return;
      _checkSession();
    } catch (_) {
      if (mounted && _current) {
        setState(() => _error = '未能开始批量操作，请重新读取书架后确认。');
      }
    }
  }

  Future<void> _retry() async {
    if (!_current || _draft?.canRetry != true) return;
    await _draft!.retry(isCurrent: () => _current);
    if (mounted) _checkSession();
  }

  Future<void> _continue() async {
    if (!_current || _draft?.canContinue != true) return;
    await _draft!.continueRemaining(isCurrent: () => _current);
    if (mounted) _checkSession();
  }

  Future<void> _reload() async {
    if (!_current || _draft?.canReloadAndFinish != true) return;
    await _draft!.reloadAndFinish(isCurrent: () => _current);
    if (mounted) _checkSession();
  }

  void _close() {
    final draft = _draft;
    if ((!_expired && draft?.busy == true) ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    Navigator.pop(context, _current ? draft?.remainingKeys : null);
  }

  List<String> _targetCategories(LibraryEntry entry) {
    final ids = entry.categoryIds.toSet();
    switch (_action) {
      case LibraryBatchAction.addCategories:
        ids.addAll(_categoryIds);
      case LibraryBatchAction.removeCategories:
        ids.removeAll(_categoryIds);
      case LibraryBatchAction.removeFavorites:
        return entry.categoryIds;
    }
    return _view.categories
        .where((category) => ids.contains(category.id))
        .map((category) => category.id)
        .toList();
  }

  String _categoryNames(List<String> ids) {
    if (ids.isEmpty) return '未分类';
    return _view.categories
        .where((category) => ids.contains(category.id))
        .map((category) => category.name)
        .join('、');
  }

  Widget _entry(LibraryEntry entry, {LibraryBatchItem? item}) {
    final target = item?.categoryIds ?? _targetCategories(entry);
    return CupertinoListTile(
      key: ValueKey(('batch-item', entry.mangaKey)),
      title: DefaultTextStyle(
        style: CupertinoTheme.of(context).textTheme.textStyle,
        child: Text(entry.title),
      ),
      subtitle: DefaultTextStyle(
        style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
          fontSize: 13,
          color: AppColors.secondaryLabel.resolveFrom(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${entry.sourceName} · ${entry.sourceLang}'),
            if (_needsCategories)
              Text(
                '${_categoryNames(entry.categoryIds)} → ${_categoryNames(target)}',
              ),
            if (item != null)
              Text(
                switch (item.status) {
                  LibraryBatchItemStatus.notStarted => '未开始',
                  LibraryBatchItemStatus.sending => '正在等待服务端确认',
                  LibraryBatchItemStatus.confirmed => '已由服务端确认',
                  LibraryBatchItemStatus.uncertain => '尚未确认，需重试原操作',
                  LibraryBatchItemStatus.blocked => '未保存，需重新读取',
                },
                style: TextStyle(
                  color: switch (item.status) {
                    LibraryBatchItemStatus.confirmed =>
                      AppColors.label.resolveFrom(context),
                    LibraryBatchItemStatus.uncertain ||
                    LibraryBatchItemStatus.blocked =>
                      AppColors.error.resolveFrom(context),
                    _ => AppColors.secondaryLabel.resolveFrom(context),
                  },
                ),
              ),
            if (item?.error case final error?)
              Text(
                error,
                style: TextStyle(color: AppColors.error.resolveFrom(context)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lifecycle = useMemoized(
      () => Listenable.merge([widget.controller, widget.lifecycle]),
      [widget.controller, widget.lifecycle],
    );
    useOnListenableChange(lifecycle, _checkSession);
    useOnListenableChange(_draft, _draftChanged);
    final draft = _draft;
    final locked = _expired || draft != null;
    final canStart =
        !locked &&
        _entries.isNotEmpty &&
        (!_needsCategories || _categoryIds.isNotEmpty);
    final actionColor = !_expired && !_needsCategories
        ? AppColors.error.resolveFrom(context)
        : null;
    return PopScope<Set<String>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: EditSheet(
        key: const ValueKey('library-batch-review'),
        title: Text(_title),
        leading: draft?.finished == true
            ? null
            : CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: !_expired && draft?.busy == true ? null : _close,
                child: Text(
                  draft == null || !draft.attempted ? '取消' : '稍后',
                  semanticsLabel: draft?.attempted == true ? '稍后处理' : null,
                ),
              ),
        trailing: draft?.finished == true
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _close,
                child: const Text('完成'),
              )
            : draft == null
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                foregroundColor: canStart ? actionColor : null,
                onPressed: canStart ? _start : null,
                child: const Text('开始', semanticsLabel: '确认并开始'),
              )
            : draft.canRetry
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                foregroundColor: actionColor,
                onPressed: _expired ? null : _retry,
                child: const Text('重试', semanticsLabel: '重试原未确认操作'),
              )
            : draft.canContinue
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                foregroundColor: actionColor,
                onPressed: _expired ? null : _continue,
                child: const Text('继续', semanticsLabel: '继续剩余原清单'),
              )
            : draft.canReloadAndFinish
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _expired ? null : _reload,
                child: const Text('重读', semanticsLabel: '重新读取并结束原批次'),
              )
            : null,
        content: ListView(
          children: [
            if (_needsCategories &&
                draft == null &&
                _view.categories.isNotEmpty)
              CupertinoFormSection.insetGrouped(
                header: const Text('选择分类'),
                footer: const Text('选择要添加或移出的分类；其它分类保持各漫画原有关联。'),
                children: [
                  for (final category in _view.categories)
                    MergeSemantics(
                      child: CupertinoListTile(
                        onTap: locked
                            ? null
                            : () => _selectCategory(
                                category.id,
                                !_categoryIds.contains(category.id),
                              ),
                        title: Builder(
                          builder: (context) => DefaultTextStyle(
                            style: DefaultTextStyle.of(context).style,
                            child: Text(category.name),
                          ),
                        ),
                        trailing: CupertinoCheckbox(
                          key: ValueKey(('batch-category', category.id)),
                          value: _categoryIds.contains(category.id),
                          onChanged: locked
                              ? null
                              : (selected) => _selectCategory(
                                  category.id,
                                  selected == true,
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            if (_expired || _error != null || draft != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_expired)
                      Text(
                        '身份或服务已变化，原窗口已停用。请关闭后重新打开。',
                        style: TextStyle(
                          color: AppColors.error.resolveFrom(context),
                        ),
                      ),
                    if (_error case final error?)
                      Text(
                        error,
                        style: TextStyle(
                          color: AppColors.error.resolveFrom(context),
                        ),
                      ),
                    if (draft != null) ...[
                      Text(
                        '已确认 ${draft.confirmedCount} / ${draft.items.length} 部 · 未开始 ${draft.notStartedCount} 部',
                      ),
                      if (draft.busy) const CupertinoActivityIndicator(),
                      if (draft.pauseRequested && draft.busy)
                        const Text('已请求暂停，等待当前操作结束后可关闭。'),
                      if (draft.error case final error?)
                        Text(
                          error,
                          style: TextStyle(
                            color: AppColors.error.resolveFrom(context),
                          ),
                        ),
                      if (!_expired && draft.completed)
                        const Text('全部修改已由服务端确认。'),
                      if (!_expired && draft.finished && !draft.completed)
                        const Text('原批次已结束，剩余漫画未再发送。请按最新书架重新确认。'),
                      if (draft.attempted && !draft.finished)
                        Text(
                          '当前会话保留原清单和未确认操作；关闭不会撤回已发请求。',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.secondaryLabel.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            if (_entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('确认清单：0 部漫画'),
              )
            else
              CupertinoFormSection.insetGrouped(
                header: Text('确认清单：${_entries.length} 部漫画'),
                footer: Text(
                  '逐部保存，以服务端确认结果为准；一项失败时暂停剩余操作。${_needsCategories ? '' : '\n移出书架后仍保留阅读进度、书签和分类。'}',
                ),
                children: [
                  if (draft != null)
                    for (final item in draft.items)
                      _entry(item.entry, item: item)
                  else
                    for (final entry in _entries) _entry(entry),
                ],
              ),
            if (!_expired && draft?.busy == true)
              CupertinoButton(
                onPressed: draft!.pauseRequested ? null : draft.pause,
                child: const Text('暂停剩余操作'),
              ),
            if (draft?.canContinue == true)
              CupertinoButton(
                onPressed: _expired
                    ? null
                    : () {
                        if (_current) draft!.finishRemaining();
                      },
                child: const Text('结束剩余操作'),
              ),
          ],
        ),
      ),
    );
  }
}
