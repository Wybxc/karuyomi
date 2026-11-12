import 'dart:async';

import 'package:flutter/material.dart';
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
  return showDialog<Set<String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _LibraryBatchDialog(
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

class _LibraryBatchDialog extends StatefulHookWidget {
  const _LibraryBatchDialog({
    required this.controller,
    required this.repository,
    required this.view,
    required this.mangaKeys,
    required this.action,
    required this.lifecycle,
    required this.isCurrent,
    required this.pending,
  });
  final CatalogController controller;
  final LibraryRepository repository;
  final LibraryView view;
  final Set<String> mangaKeys;
  final LibraryBatchAction action;
  final Listenable lifecycle;
  final bool Function() isCurrent;
  final LibraryBatchDraft? pending;

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
    return ListTile(
      key: ValueKey(('batch-item', entry.mangaKey)),
      contentPadding: EdgeInsets.zero,
      title: Text(entry.title),
      subtitle: Text(
        [
          '${entry.sourceName} · ${entry.sourceLang}',
          if (_needsCategories)
            '${_categoryNames(entry.categoryIds)} → ${_categoryNames(target)}',
          if (item != null)
            switch (item.status) {
              LibraryBatchItemStatus.notStarted => '未开始',
              LibraryBatchItemStatus.sending => '正在等待服务端确认',
              LibraryBatchItemStatus.confirmed => '已由服务端确认',
              LibraryBatchItemStatus.uncertain => '尚未确认，需重试原操作',
              LibraryBatchItemStatus.blocked => '未保存，需重新读取',
            },
          ?item?.error,
        ].join('\n'),
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
    return PopScope<Set<String>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AlertDialog(
        title: Text(_title),
        content: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(context).height * .55,
          child: ListView(
            children: [
              Text('确认清单：${_entries.length} 部漫画'),
              const SizedBox(height: 8),
              const Text('逐部保存，以服务端确认结果为准；一项失败时暂停剩余操作。'),
              if (!_needsCategories) const Text('移出书架后仍保留阅读进度、书签和分类。'),
              if (_needsCategories && draft == null) ...[
                const SizedBox(height: 12),
                const Text('选择要添加或移出的分类；其它分类保持各漫画原有关联。'),
                for (final category in _view.categories)
                  CheckboxListTile(
                    key: ValueKey(('batch-category', category.id)),
                    contentPadding: EdgeInsets.zero,
                    title: Text(category.name),
                    value: _categoryIds.contains(category.id),
                    onChanged: locked
                        ? null
                        : (selected) => setState(() {
                            if (selected == true) {
                              _categoryIds.add(category.id);
                            } else {
                              _categoryIds.remove(category.id);
                            }
                          }),
                  ),
              ],
              if (_expired) const Text('身份或服务已变化，原窗口已停用。请关闭后重新打开。'),
              if (_error case final error?) Text(error),
              if (draft != null) ...[
                const SizedBox(height: 12),
                Text(
                  '已确认 ${draft.confirmedCount} / ${draft.items.length} 部 · 未开始 ${draft.notStartedCount} 部',
                ),
                if (draft.busy) const LinearProgressIndicator(),
                if (draft.pauseRequested && draft.busy)
                  const Text('已请求暂停，等待当前操作结束后可关闭。'),
                if (draft.error case final error?) Text(error),
                if (!_expired && draft.completed) const Text('全部修改已由服务端确认。'),
                if (!_expired && draft.finished && !draft.completed)
                  const Text('原批次已结束，剩余漫画未再发送。请按最新书架重新确认。'),
                if (draft.attempted && !draft.finished)
                  const Text('当前会话保留原清单和未确认操作；关闭不会撤回已发请求。'),
                for (final item in draft.items) _entry(item.entry, item: item),
              ] else ...[
                for (final entry in _entries) _entry(entry),
              ],
            ],
          ),
        ),
        actions: [
          if (!_expired && draft?.busy == true)
            TextButton(
              onPressed: draft!.pauseRequested ? null : draft.pause,
              child: const Text('暂停剩余操作'),
            ),
          TextButton(
            onPressed: !_expired && draft?.busy == true ? null : _close,
            child: Text(
              draft == null || !draft.attempted
                  ? '取消'
                  : draft.finished
                  ? '完成'
                  : '稍后处理',
            ),
          ),
          if (draft == null)
            FilledButton(
              onPressed:
                  locked ||
                      _entries.isEmpty ||
                      (_needsCategories && _categoryIds.isEmpty)
                  ? null
                  : _start,
              child: const Text('确认并开始'),
            )
          else ...[
            if (draft.canRetry)
              FilledButton(
                onPressed: _expired ? null : _retry,
                child: const Text('重试原未确认操作'),
              ),
            if (draft.canContinue)
              FilledButton(
                onPressed: _expired ? null : _continue,
                child: const Text('继续剩余原清单'),
              ),
            if (draft.canContinue)
              TextButton(
                onPressed: _expired
                    ? null
                    : () {
                        if (_current) draft.finishRemaining();
                      },
                child: const Text('结束剩余操作'),
              ),
            if (draft.canReloadAndFinish)
              FilledButton(
                onPressed: _expired ? null : _reload,
                child: const Text('重新读取并结束原批次'),
              ),
          ],
        ],
      ),
    );
  }
}
