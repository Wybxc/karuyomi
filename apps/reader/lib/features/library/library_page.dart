import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/library_repository.dart';
import '../browse/catalog_controller.dart';
import '../browse/catalog_page.dart';
import '../reader/reader_recovery.dart';
import 'category_dialogs.dart';

enum _LibrarySort { added, title }

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.controller,
    required this.onBrowse,
    required this.onConnect,
    required this.onAuthenticate,
    this.onAuthenticateReader,
  });

  final CatalogController? controller;
  final VoidCallback onBrowse;
  final VoidCallback onConnect;
  final VoidCallback onAuthenticate;
  final ReaderAuthentication? onAuthenticateReader;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> with WidgetsBindingObserver {
  final _search = TextEditingController();
  LibraryRepository? _repository;
  Stream<LibraryView>? _views;
  final _editLifecycle = ValueNotifier(0);
  String? _categoryFilter;
  bool _editing = false;
  bool _disposing = false;
  _LibrarySort _sort = _LibrarySort.added;
  int _retry = 0;
  ServiceStatus? _lastStatus;
  bool _opening = false;
  String? _refreshError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.addListener(_catalogChanged);
    _bindRepository();
  }

  @override
  void didUpdateWidget(LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_catalogChanged);
      widget.controller?.addListener(_catalogChanged);
    }
    _bindRepository();
  }

  void _catalogChanged() {
    if (!mounted) return;
    final status = widget.controller?.status;
    final reconnected = status == ServiceStatus.ready && _lastStatus != status;
    _lastStatus = status;
    setState(_bindRepository);
    if (reconnected) unawaited(_refresh());
  }

  void _bindRepository() {
    final next = widget.controller?.library;
    _editLifecycle.value++;
    if (identical(_repository, next)) {
      return;
    }
    _repository = next;
    _refreshError = null;
    _views = next?.watchView();
    _categoryFilter = null;
    _search.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.refresh();
      if (mounted && identical(repository, _repository)) {
        setState(() => _refreshError = null);
      }
    } catch (_) {
      if (mounted && identical(repository, _repository)) {
        setState(() => _refreshError = '未能刷新服务端书架，当前显示上次确认的结果。');
      }
    }
  }

  void _retryStorage() => setState(() {
    _retry++;
    _views = _repository?.watchView();
  });

  Future<void> _open(LibraryEntry entry) async {
    final controller = widget.controller;
    final repository = _repository;
    if (_opening || controller == null || repository == null) return;
    final route = ModalRoute.of(context);
    final identityKey = repository.identity.key;
    bool isCurrent() =>
        mounted &&
        identical(widget.controller, controller) &&
        identical(_repository, repository) &&
        _repository?.identity.key == identityKey &&
        route?.isCurrent == true &&
        route?.isActive == true;
    setState(() => _opening = true);
    try {
      final details = await controller.openLibraryEntry(
        entry,
        identityKey: identityKey,
        shouldContinue: isCurrent,
      );
      if (!mounted || details == null || !isCurrent()) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MangaDetailsPage(
            controller: controller,
            manga: details.manga,
            chapters: details.chapters,
            source: details.source,
            onAuthenticateReader: widget.onAuthenticateReader,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _editCategories(LibraryView view, {LibraryEntry? entry}) async {
    final controller = widget.controller;
    final repository = _repository;
    if (_editing ||
        _opening ||
        controller == null ||
        repository == null ||
        controller.status != ServiceStatus.ready ||
        controller.busy) {
      return;
    }
    final route = ModalRoute.of(context);
    final identityKey = repository.identity.key;
    bool isCurrent() =>
        mounted &&
        !_disposing &&
        identical(widget.controller, controller) &&
        identical(_repository, repository) &&
        repository.identity.key == identityKey &&
        controller.status == ServiceStatus.ready &&
        route?.isActive == true;
    setState(() => _editing = true);
    try {
      if (entry == null) {
        await showLibraryCategoryManager(
          context: context,
          controller: controller,
          repository: repository,
          view: view,
          lifecycle: _editLifecycle,
          isCurrent: isCurrent,
        );
      } else {
        await showLibraryCategoryPicker(
          context: context,
          controller: controller,
          repository: repository,
          view: view,
          entry: entry,
          lifecycle: _editLifecycle,
          isCurrent: isCurrent,
        );
      }
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_opening || widget.controller?.busy == true) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          if (widget.controller?.error case final error?) _notice(error),
          if (_refreshError case final error?) _notice(error),
          if (widget.controller case final controller?)
            if (controller.status != ServiceStatus.ready)
              _connection(controller),
          if (_repository != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => unawaited(_refresh()),
                icon: const Icon(Icons.sync),
                label: const Text('刷新服务端书架'),
              ),
            ),
          StreamBuilder<LibraryView>(
            key: ValueKey((_repository, _repository?.identity.key, _retry)),
            stream: _views,
            builder: (context, snapshot) {
              if (snapshot.hasError && !snapshot.hasData) {
                return Column(
                  children: [
                    _notice('未能读取服务端书架，请重试。'),
                    TextButton(
                      onPressed: _retryStorage,
                      child: const Text('重试读取书架'),
                    ),
                  ],
                );
              }
              if (_views != null && !snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('正在读取书架')),
                );
              }
              final view = snapshot.data;
              if (view == null) {
                return _repository == null && widget.controller != null
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('连接并确认身份后显示服务端书架。'),
                      )
                    : _empty();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (snapshot.hasError) _notice('未能读取服务端书架，当前显示上次确认的结果。'),
                  _categoryControls(view),
                  if (view.entries.isEmpty) _empty() else _library(view),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _connection(CatalogController controller) {
    final needsLogin = controller.accessPaused;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (controller.status) {
            ServiceStatus.connecting => '正在连接服务',
            ServiceStatus.loginRequired => '登录后继续阅读',
            ServiceStatus.denied => '当前账号无法访问',
            _ => '连接服务后打开书架漫画',
          }),
          TextButton.icon(
            onPressed: controller.busy
                ? null
                : needsLogin
                ? widget.onAuthenticate
                : widget.onConnect,
            icon: Icon(needsLogin ? Icons.login : Icons.refresh),
            label: Text(needsLogin ? '登录' : '连接服务'),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 64),
    child: Column(
      children: [
        Icon(
          Icons.auto_stories_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text('书架还是空的', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text('从浏览打开漫画详情，收藏喜欢的漫画。'),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: widget.onBrowse,
          icon: const Icon(Icons.explore_outlined),
          label: const Text('去浏览'),
        ),
      ],
    ),
  );

  String? _filterFor(LibraryView view) {
    final selected = _categoryFilter;
    if (selected != null &&
        selected.isNotEmpty &&
        !view.categories.any((category) => category.id == selected)) {
      return null;
    }
    return selected;
  }

  Widget _categoryControls(LibraryView view) {
    final repository = _repository;
    final pending =
        repository != null && hasPendingLibraryCategoryEdit(repository);
    final available =
        !_editing &&
        !_opening &&
        widget.controller?.status == ServiceStatus.ready &&
        widget.controller?.busy == false;
    final selected = _filterFor(view);
    Widget chip(String? value, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: label,
        child: ChoiceChip(
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          selected: selected == value,
          onSelected: (_) => setState(() => _categoryFilter = value),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending) ...[
          _notice('有一项分类修改尚未处理。请继续原修改，当前列表仅显示服务端已确认的结果。'),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: available
                  ? () => unawaited(_editCategories(view))
                  : null,
              icon: const Icon(Icons.pending_actions),
              label: const Text('处理未确认修改'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: available && !pending
                ? () => unawaited(_editCategories(view))
                : null,
            icon: const Icon(Icons.folder_outlined),
            label: const Text('管理分类'),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip(null, '全部'),
              chip('', '未分类'),
              for (final category in view.categories)
                chip(category.id, category.name),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _library(LibraryView view) {
    final entries = view.entries;
    final query = _search.text.trim().toLowerCase();
    final filter = _filterFor(view);
    final visible = entries.where((entry) {
      if (filter == '' && entry.categoryIds.isNotEmpty) return false;
      if (filter != null &&
          filter.isNotEmpty &&
          !entry.categoryIds.contains(filter)) {
        return false;
      }
      final text = [
        entry.title,
        entry.snapshot.author,
        entry.sourceName,
      ].join('\n').toLowerCase();
      return text.contains(query);
    }).toList();
    visible.sort((a, b) {
      final result = switch (_sort) {
        _LibrarySort.added => b.addedAt.compareTo(a.addedAt),
        _LibrarySort.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
      };
      return result == 0 ? a.mangaKey.compareTo(b.mangaKey) : result;
    });
    final controller = widget.controller;
    final canOpen =
        !_opening &&
        controller?.busy == false &&
        controller?.status == ServiceStatus.ready;
    final repository = _repository;
    final canCategorize =
        canOpen &&
        !_editing &&
        repository != null &&
        !hasPendingLibraryCategoryEdit(repository);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: '搜索书架',
            hintText: '漫画、作者或漫画源',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<_LibrarySort>(
          initialValue: _sort,
          decoration: const InputDecoration(
            labelText: '排序',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: _LibrarySort.added, child: Text('最近收藏')),
            DropdownMenuItem(value: _LibrarySort.title, child: Text('标题')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _sort = value);
          },
        ),
        const SizedBox(height: 16),
        Text('收藏 ${entries.length} 部 · 当前显示 ${visible.length} 部'),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text('没有找到收藏', textAlign: TextAlign.center),
          ),
        for (final entry in visible)
          Card(
            key: ValueKey(entry.mangaKey),
            child: ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(entry.title),
              subtitle: Text(
                [
                  if (entry.snapshot.author.isNotEmpty) entry.snapshot.author,
                  '${entry.sourceName} · ${entry.sourceLang}',
                  '分类：${entry.categoryIds.isEmpty ? '未分类' : view.categories.where((category) => entry.categoryIds.contains(category.id)).map((category) => category.name).join('、')}',
                ].join('\n'),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '设置分类：${entry.title}',
                    onPressed: canCategorize
                        ? () => unawaited(_editCategories(view, entry: entry))
                        : null,
                    icon: const Icon(Icons.folder_outlined),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: canOpen ? () => unawaited(_open(entry)) : null,
            ),
          ),
      ],
    );
  }

  Widget _notice(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _disposing = true;
    _editLifecycle.value++;
    _editLifecycle.dispose();
    widget.controller?.removeListener(_catalogChanged);
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }
}
