import '../../widgets/edit_sheet.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/scheduler.dart';
import 'package:uuid/uuid.dart';

import '../../data/business_state_client.dart';
import '../../data/business_state_validation.dart';
import '../../data/library_repository.dart';
import '../browse/catalog_controller.dart';
import 'library_batch.dart';

const _changed = '分类或漫画已在其他设备修改，请重新读取后重开编辑。';
const _expired = '身份或服务已变化，请关闭后重新打开。';

// Keep an uncertain command with its repository for this session, including
// when a dialog or shelf route closes. A new command must not silently retry it.
final _pendingEdits = Expando<_CategoryDraft>('unconfirmed category edit');

bool hasPendingLibraryCategoryEdit(LibraryRepository repository) =>
    _pendingEdits[repository.client] != null;

Future<void> showLibraryCategoryManager({
  required BuildContext context,
  required CatalogController controller,
  required LibraryRepository repository,
  required LibraryView view,
  required Listenable lifecycle,
  required bool Function() isCurrent,
}) {
  if (pendingLibraryBatch(repository) != null) return Future.value();
  final pending = _pendingEdits[repository.client];
  if (pending?.entry != null) {
    return _showCommand(context, controller, lifecycle, isCurrent, pending!);
  }
  return showCupertinoSheet<void>(
    context: context,
    enableDrag: false,
    scrollableBuilder: (context, _) => _CategoryManager(
      controller: controller,
      repository: repository,
      view: pending?.view ?? view,
      lifecycle: lifecycle,
      isCurrent: isCurrent,
    ),
  );
}

Future<void> showLibraryCategoryPicker({
  required BuildContext context,
  required CatalogController controller,
  required LibraryRepository repository,
  required LibraryView view,
  required LibraryEntry entry,
  required Listenable lifecycle,
  required bool Function() isCurrent,
}) {
  if (pendingLibraryBatch(repository) != null) return Future.value();
  if (hasPendingLibraryCategoryEdit(repository)) {
    return showLibraryCategoryManager(
      context: context,
      controller: controller,
      repository: repository,
      view: view,
      lifecycle: lifecycle,
      isCurrent: isCurrent,
    );
  }
  final draft = _CategoryDraft(
    repository: repository,
    view: view,
    entry: entry,
    title: '设置分类',
    description: entry.title,
    categories: view.categories,
    selection: entry.categoryIds.toSet(),
    submit: (_, selection) => repository.setCategories(
      mangaKey: entry.mangaKey,
      categoryIds: view.categories
          .where((category) => selection.contains(category.id))
          .map((category) => category.id)
          .toList(),
      expectedCatalogRevision: view.categoryRevision,
      expectedMangaRevision: entry.revision,
    ),
  );
  return _showCommand(context, controller, lifecycle, isCurrent, draft);
}

Future<void> _showCommand(
  BuildContext context,
  CatalogController controller,
  Listenable lifecycle,
  bool Function() isCurrent,
  _CategoryDraft draft,
) => showCupertinoSheet<void>(
  context: context,
  enableDrag: false,
  scrollableBuilder: (context, _) => _CategoryCommand(
    controller: controller,
    lifecycle: lifecycle,
    isCurrent: isCurrent,
    draft: draft,
  ),
);

typedef _Submit = Future<void> Function(String name, Set<String> selection);

final class _CategoryDraft extends ChangeNotifier {
  _CategoryDraft({
    required this.repository,
    required this.view,
    required this.title,
    required this.submit,
    this.entry,
    this.name,
    this.description,
    this.categories,
    Set<String> selection = const {},
    this.submitLabel = '保存',
    this.reorder = false,
  }) : selection = Set.unmodifiable(selection);

  final LibraryRepository repository;
  final LibraryView view;
  final LibraryEntry? entry;
  final String title;
  final String? description;
  final List<LibraryCategory>? categories;
  final String submitLabel;
  final bool reorder;
  final _Submit submit;
  String? name;
  Set<String> selection;
  bool attempted = false;
  bool busy = false;
  bool confirmed = false;
  bool blocked = false;
  bool completed = false;
  bool reloaded = false;
  String? error;
  LibraryView? confirmedView;

  String get retryLabel => confirmed ? '重试读取' : '重试保存';

  void _finish() {
    completed = true;
    if (identical(_pendingEdits[repository.client], this)) {
      _pendingEdits[repository.client] = null;
    }
  }

  Future<void> save() async {
    if (busy || blocked || completed) return;
    if (pendingLibraryBatch(repository) != null) {
      error = '请先处理书架中的未完成批量操作。';
      notifyListeners();
      return;
    }
    final pending = _pendingEdits[repository.client];
    if (pending != null && !identical(pending, this)) return;
    _pendingEdits[repository.client] = this;
    busy = true;
    attempted = true;
    error = null;
    notifyListeners();
    try {
      // An ACK followed by a failed shelf read must only retry the read.
      if (!confirmed) {
        await submit(name ?? '', selection);
        confirmed = true;
      }
      if (entry == null) {
        confirmedView = await repository.watchView().first;
      }
      _finish();
    } on BusinessPendingMutationException {
      blocked = true;
      error = '该漫画已有另一项未确认修改，请先处理原操作，再重新读取后重开分类编辑。';
    } on BusinessStateException catch (failure) {
      if (confirmed) {
        error = '修改已确认，但未能读取最新书架。请重试读取。';
      } else {
        blocked = failure.conflict || !failure.error.retryable;
        error = failure.conflict
            ? _changed
            : blocked
            ? '修改未保存，请重新读取后重开编辑。'
            : '尚未确认保存，请原样重试。';
      }
    } catch (_) {
      error = confirmed ? '修改已确认，但未能读取最新书架。请重试读取。' : '尚未确认保存，请原样重试。';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    if (!blocked || busy || completed) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await repository.refresh();
      reloaded = true;
      _finish();
    } catch (_) {
      error = '未能重新读取服务端分类，请重试。';
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

/// Once a service or identity is lost, an open editor never becomes writable
/// again. Explicit reopening can resume the same frozen, unconfirmed command.
abstract class _CategorySession<W extends StatefulHookWidget> extends State<W> {
  CatalogController get controller;
  Listenable get lifecycle;
  bool Function() get isCurrent;
  bool expired = false;

  @override
  void initState() {
    super.initState();
    expired = !isCurrent();
  }

  void useSession() {
    final changes = useMemoized(
      () => Listenable.merge([controller, lifecycle]),
      [controller, lifecycle],
    );
    useOnListenableChange(changes, _checkSession);
  }

  void _checkSession() {
    if (mounted && !expired && !isCurrent()) {
      expired = true;
      // A service replacement can notify from LibraryPage.didUpdateWidget;
      // its dialog belongs to another route and cannot rebuild during that build.
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      } else {
        setState(() {});
      }
    }
  }

  bool get current {
    _checkSession();
    return mounted && !expired;
  }

  bool get canCloseCurrentRoute =>
      current && ModalRoute.of(context)?.isCurrent == true;

  Widget status(_CategoryDraft? draft) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (draft?.busy == true) const CupertinoActivityIndicator(),
      if (expired || draft?.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            expired ? _expired : draft!.error!,
            style: TextStyle(
              color: CupertinoColors.systemRed.resolveFrom(context),
            ),
          ),
        ),
      if (!expired && draft?.completed == true)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(draft!.reloaded ? '已重新读取，请关闭后重新打开编辑。' : '分类修改已由服务端确认。'),
        ),
      if (!expired && draft?.attempted == true && !draft!.completed)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('原修改暂存在当前会话，关闭窗口不会撤回请求。请继续处理这次修改。'),
        ),
    ],
  );
}

class const _CategoryManager({
  required final CatalogController controller,
  required final LibraryRepository repository,
  required final LibraryView view,
  required final Listenable lifecycle,
  required final bool Function() isCurrent,
}) extends StatefulHookWidget {
  @override
  State<_CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends _CategorySession<_CategoryManager> {
  late LibraryView _view = widget.view;
  late _CategoryDraft? _draft = _pendingEdits[widget.repository.client];
  bool _childOpen = false;
  @override
  CatalogController get controller => widget.controller;
  @override
  Listenable get lifecycle => widget.lifecycle;
  @override
  bool Function() get isCurrent => widget.isCurrent;
  bool get editable => !expired && !_childOpen && _draft == null;

  void _draftChanged() {
    if (!mounted) return;
    setState(() {
      final draft = _draft;
      // A resumed command may finish in the retired dialog that started it.
      // Accept its confirmed result without navigating from that old session.
      if (!expired &&
          isCurrent() &&
          !_childOpen &&
          draft?.completed == true &&
          !draft!.reloaded) {
        _view = draft.confirmedView ?? _view;
        _draft = null;
      }
    });
  }

  Future<void> _execute(_CategoryDraft draft) async {
    if (!current || _childOpen || draft.busy) return;
    setState(() {
      _draft = draft;
      _childOpen = !draft.reorder;
    });
    if (draft.reorder) {
      await draft.save();
    } else {
      await _showCommand(context, controller, lifecycle, isCurrent, draft);
    }
    if (!mounted) return;
    _childOpen = false;
    if (!current) return;
    if (draft.reloaded) {
      if (canCloseCurrentRoute) Navigator.pop(context);
      return;
    }
    setState(() {
      if (draft.completed) {
        _view = draft.confirmedView ?? _view;
        _draft = null;
      } else if (!draft.attempted) {
        _draft = null;
      }
    });
  }

  Future<void> _reload() async {
    final draft = _draft;
    if (!current || draft == null) return;
    await draft.reload();
    if (!mounted) return;
    if (canCloseCurrentRoute && draft.reloaded) Navigator.pop(context);
  }

  void _move(int index, int delta) {
    if (!editable || !current) return;
    final view = _view;
    final ids = view.categories.map((category) => category.id).toList();
    final id = ids.removeAt(index);
    ids.insert(index + delta, id);
    unawaited(
      _execute(
        _CategoryDraft(
          repository: widget.repository,
          view: view,
          title: '调整分类顺序',
          reorder: true,
          submit: (_, _) => widget.repository.reorderCategories(
            categoryIds: ids,
            expectedRevision: view.categoryRevision,
          ),
        ),
      ),
    );
  }

  void _command({LibraryCategory? category, bool delete = false}) {
    if (!editable || !current) return;
    final view = _view;
    final id = category?.id ?? const Uuid().v4();
    unawaited(
      _execute(
        _CategoryDraft(
          repository: widget.repository,
          view: view,
          title: delete
              ? '删除分类'
              : category == null
              ? '新建分类'
              : '重命名分类',
          name: delete ? null : category?.name ?? '',
          description: delete
              ? '删除“${category!.name}”及其漫画关联？漫画收藏和阅读进度会保留。'
              : null,
          submitLabel: delete ? '删除' : '保存',
          submit: (name, _) => delete
              ? widget.repository.deleteCategory(
                  categoryId: id,
                  expectedRevision: view.categoryRevision,
                )
              : category == null
              ? widget.repository.createCategory(
                  categoryId: id,
                  name: name,
                  expectedRevision: view.categoryRevision,
                )
              : widget.repository.renameCategory(
                  categoryId: id,
                  name: name,
                  expectedRevision: view.categoryRevision,
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    useSession();
    useOnListenableChange(_draft, _draftChanged);
    return PopScope(
      canPop: expired || _draft?.busy != true,
      child: EditSheet(
        key: const ValueKey('category-manager'),
        title: const Text('管理分类'),
        content: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              status(_draft),
              if (_view.categories.isEmpty) const Text('还没有分类。'),
              for (var index = 0; index < _view.categories.length; index++)
                _categoryRow(_view.categories[index], index),
              const SizedBox(height: 12),
              CupertinoButton(
                onPressed: editable && _view.categories.length < 64
                    ? _command
                    : null,
                child: const Text('新建分类'),
              ),
              if (_view.categories.length == 64) const Text('最多可创建 64 个分类。'),
              if (_draft case final draft? when !expired) ...[
                if (draft.blocked && !draft.completed)
                  CupertinoButton.filled(
                    onPressed: draft.busy ? null : _reload,
                    child: const Text('重新读取并关闭'),
                  )
                else if (draft.attempted && !draft.completed)
                  CupertinoButton.filled(
                    onPressed: draft.busy ? null : () => _execute(draft),
                    child: Text(draft.reorder ? draft.retryLabel : '继续未确认修改'),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          CupertinoButton(
            onPressed: !expired && _draft?.busy == true
                ? null
                : () => Navigator.pop(context),
            child: Text(
              _draft?.attempted == true && _draft?.completed != true
                  ? '稍后处理'
                  : '完成',
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryRow(LibraryCategory category, int index) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          category.name,
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        Wrap(
          children: [
            for (final (icon, label, action)
                in <(IconData, String, VoidCallback?)>[
                  (
                    CupertinoIcons.arrow_up,
                    '上移分类',
                    editable && index > 0 ? () => _move(index, -1) : null,
                  ),
                  (
                    CupertinoIcons.arrow_down,
                    '下移分类',
                    editable && index + 1 < _view.categories.length
                        ? () => _move(index, 1)
                        : null,
                  ),
                  (
                    CupertinoIcons.pencil,
                    '重命名分类',
                    editable ? () => _command(category: category) : null,
                  ),
                  (
                    CupertinoIcons.trash,
                    '删除分类',
                    editable
                        ? () => _command(category: category, delete: true)
                        : null,
                  ),
                ])
              CupertinoButton(
                onPressed: action,
                padding: const EdgeInsets.all(8),
                child: Icon(icon, semanticLabel: '$label ${category.name}'),
              ),
          ],
        ),
      ],
    ),
  );
}

class const _CategoryCommand({
  required final CatalogController controller,
  required final Listenable lifecycle,
  required final bool Function() isCurrent,
  required final _CategoryDraft draft,
}) extends StatefulHookWidget {
  @override
  State<_CategoryCommand> createState() => _CategoryCommandState();
}

class _CategoryCommandState extends _CategorySession<_CategoryCommand> {
  late TextEditingController _name;
  late final _selection = {...widget.draft.selection};
  final _form = GlobalKey<FormState>();
  _CategoryDraft get draft => widget.draft;
  @override
  CatalogController get controller => widget.controller;
  @override
  Listenable get lifecycle => widget.lifecycle;
  @override
  bool Function() get isCurrent => widget.isCurrent;
  bool get editable => !expired && !draft.attempted;

  Future<void> _save() async {
    if (!current || draft.busy || draft.blocked) return;
    if (!draft.attempted) {
      if (_form.currentState?.validate() == false) return;
      draft.name = draft.name == null ? null : _name.text.trim();
      draft.selection = Set.unmodifiable(_selection);
    }
    await draft.save();
    if (!mounted) return;
    if (canCloseCurrentRoute && draft.completed) Navigator.pop(context);
  }

  Future<void> _reload() async {
    if (!current) return;
    await draft.reload();
    if (!mounted) return;
    if (canCloseCurrentRoute && draft.reloaded) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    useSession();
    _name = useTextEditingController(text: draft.name ?? '');
    useListenable(draft);
    return PopScope(
      canPop: expired || !draft.busy,
      child: EditSheet(
        key: const ValueKey('category-command'),
        title: Text(draft.title),
        content: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (draft.description case final description?)
                  Text(description),
                if (draft.name != null)
                  CupertinoTextFormFieldRow(
                    controller: _name,
                    enabled: editable,
                    autofocus: true,
                    validator: (text) {
                      try {
                        validateBusinessCategoryName((text ?? '').trim());
                        return null;
                      } on FormatException {
                        return '名称不能为空，且最多 100 字、256 字节。';
                      }
                    },
                    prefix: Text('分类名称'),
                  ),
                if (draft.categories case final categories?) ...[
                  if (categories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('还没有分类，请先在书架中管理分类。'),
                    ),
                  for (final category in categories)
                    MergeSemantics(
                      child: CupertinoFormRow(
                        prefix: Expanded(flex: 3, child: Text(category.name)),
                        padding: EdgeInsets.zero,
                        child: CupertinoCheckbox(
                          value: _selection.contains(category.id),
                          onChanged: editable
                              ? (selected) => setState(() {
                                  if (selected == true) {
                                    _selection.add(category.id);
                                  } else {
                                    _selection.remove(category.id);
                                  }
                                })
                              : null,
                        ),
                      ),
                    ),
                ],
                status(draft),
              ],
            ),
          ),
        ),
        actions: [
          CupertinoButton(
            onPressed: !expired && draft.busy
                ? null
                : () => Navigator.pop(context),
            child: Text(
              draft.completed
                  ? '完成'
                  : draft.attempted
                  ? '稍后处理'
                  : '取消',
            ),
          ),
          if (draft.blocked)
            CupertinoButton.filled(
              onPressed: expired || draft.busy ? null : _reload,
              child: const Text('重新读取并关闭'),
            )
          else
            CupertinoButton.filled(
              onPressed: expired || draft.busy || draft.completed
                  ? null
                  : _save,
              child: Text(
                draft.attempted ? draft.retryLabel : draft.submitLabel,
              ),
            ),
        ],
      ),
    );
  }
}
