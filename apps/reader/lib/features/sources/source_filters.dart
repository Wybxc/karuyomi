import '../../theme/app_theme.dart';
import '../../widgets/edit_sheet.dart';
import '../../widgets/choice_field.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/catalog_controller.dart';

enum _FilterWork { loading, resetting, applying }

/// Source filter edits are session drafts. Only applying a successful search
/// changes the catalog; closing this sheet discards its unsubmitted edits.
class const SourceFiltersSheet({
  super.key,
  required final CatalogController catalog,
  required final String query,
}) extends StatefulHookWidget {
  @override
  State<SourceFiltersSheet> createState() => _SourceFiltersSheetState();
}

class _SourceFiltersSheetState extends State<SourceFiltersSheet> {
  late final CatalogSourceRef _source;
  late final String? _subject;
  late final String _worker;
  wire.FilterSnapshot? _draft;
  String? _requestId;
  String? _error;
  _FilterWork? _work;
  bool _disposing = false;
  bool _closing = false;

  bool get _working => _work != null;

  @override
  void initState() {
    super.initState();
    _source = widget.catalog.sourceReference;
    _subject = widget.catalog.subject;
    _worker = widget.catalog.session!.workerInstanceId;
    final snapshot = widget.catalog.sourceFilterSnapshot;
    if (snapshot != null) _seed(snapshot);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _draft == null) unawaited(_load());
    });
  }

  bool get _current =>
      mounted &&
      !_disposing &&
      !_closing &&
      widget.catalog.subject == _subject &&
      widget.catalog.session?.workerInstanceId == _worker &&
      widget.catalog.isCurrentSource(_source) &&
      // A dropdown is a child popup route; it must not invalidate its sheet.
      // Popping the sheet itself makes its owning route inactive immediately.
      ModalRoute.of(context)?.isActive == true;

  void _seed(wire.FilterSnapshot snapshot) {
    final draft = snapshot.deepCopy();
    final applied = widget.catalog.appliedSourceFilters;
    if (applied != null && applied.snapshotId == draft.snapshotId) {
      for (final update in applied.updates) {
        var nodes = draft.nodes;
        for (var index = 0; index < update.path.length - 1; index++) {
          nodes = nodes[update.path[index]].group.nodes;
        }
        final node = nodes[update.path.last];
        switch (update.whichState()) {
          case wire.FilterUpdate_State.text:
            node.text.state = update.text;
          case wire.FilterUpdate_State.checkBox:
            node.checkBox.state = update.checkBox;
          case wire.FilterUpdate_State.triState:
            node.triState.state = update.triState;
          case wire.FilterUpdate_State.select:
            node.select.state = update.select;
          case wire.FilterUpdate_State.sort:
            node.sort.state = update.sort.deepCopy();
          case wire.FilterUpdate_State.notSet:
            throw const FormatException('筛选值缺少类型');
        }
      }
    }
    _draft = draft;
  }

  Future<void> _load({bool reset = false}) async {
    if (!_current || _working || widget.catalog.busy) return;
    setState(() {
      _work = reset ? _FilterWork.resetting : _FilterWork.loading;
      _error = null;
    });
    final loaded = await widget.catalog.loadSourceFilters(
      reset: reset,
      shouldContinue: () => _current,
      onRequest: (id) => _requestId = id,
    );
    _requestId = null;
    if (!mounted || _disposing) return;
    if (!_current) {
      setState(() => _work = null);
      return;
    }
    setState(() {
      _work = null;
      final snapshot = widget.catalog.sourceFilterSnapshot;
      if (loaded && snapshot != null) {
        _seed(snapshot);
      } else {
        _draft = null;
        _error = widget.catalog.sourceFilterError ?? '筛选条件未能加载，仍可默认浏览。';
      }
    });
  }

  Iterable<wire.FilterUpdate> _updates(
    List<wire.FilterNode> nodes, [
    List<int> parent = const [],
  ]) sync* {
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      final path = [...parent, index];
      switch (node.whichKind()) {
        case wire.FilterNode_Kind.header:
        case wire.FilterNode_Kind.separator:
          break;
        case wire.FilterNode_Kind.text:
          yield wire.FilterUpdate(path: path, text: node.text.state);
        case wire.FilterNode_Kind.checkBox:
          yield wire.FilterUpdate(path: path, checkBox: node.checkBox.state);
        case wire.FilterNode_Kind.triState:
          yield wire.FilterUpdate(path: path, triState: node.triState.state);
        case wire.FilterNode_Kind.select:
          yield wire.FilterUpdate(path: path, select: node.select.state);
        case wire.FilterNode_Kind.sort:
          yield wire.FilterUpdate(path: path, sort: node.sort.state.deepCopy());
        case wire.FilterNode_Kind.group:
          yield* _updates(node.group.nodes, path);
        case wire.FilterNode_Kind.notSet:
          throw const FormatException('筛选条件缺少类型');
      }
    }
  }

  Future<void> _apply() async {
    final draft = _draft;
    if (!_current || _working || widget.catalog.busy || draft == null) return;
    setState(() {
      _work = _FilterWork.applying;
      _error = null;
    });
    final applied = await widget.catalog.applySourceFilters(
      wire.FilterSelection(
        snapshotId: draft.snapshotId,
        updates: _updates(draft.nodes),
      ),
      search: widget.query,
      shouldContinue: () => _current,
      onRequest: (id) => _requestId = id,
    );
    _requestId = null;
    if (!mounted || _disposing) return;
    if (!_current) {
      setState(() => _work = null);
      return;
    }
    if (applied) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _work = null;
        _error = widget.catalog.error ?? '筛选尚未应用，原列表保留，可重试或取消。';
      });
    }
  }

  void _close() {
    _closing = true;
    final requestId = _requestId;
    _requestId = null;
    if (requestId != null) {
      unawaited(widget.catalog.cancelSourceFilterRequest(requestId));
    }
    Navigator.of(context).pop(false);
  }

  List<Widget> _sections(
    List<wire.FilterNode> nodes,
    List<int> parentPath,
    bool enabled, {
    Widget? header,
  }) {
    final sections = <Widget>[];
    var rows = <Widget>[];
    void flush() {
      if (rows.isEmpty && header == null) return;
      sections.add(
        Semantics(
          container: true,
          explicitChildNodes: true,
          child: rows.isEmpty
              ? CupertinoListSection.insetGrouped(header: header)
              : CupertinoFormSection.insetGrouped(
                  header: header,
                  children: rows,
                ),
        ),
      );
      rows = [];
      header = null;
    }

    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      final path = [...parentPath, index];
      switch (node.whichKind()) {
        case wire.FilterNode_Kind.header:
          flush();
          header = Text(node.name);
        case wire.FilterNode_Kind.separator:
          flush();
        case wire.FilterNode_Kind.group:
          flush();
          sections.add(
            Column(
              key: ValueKey(('source-filter-group', path.join('.'))),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _sections(
                node.group.nodes,
                path,
                enabled,
                header: Text(node.name),
              ),
            ),
          );
        default:
          rows.add(_field(node, path, enabled));
      }
    }
    flush();
    return sections;
  }

  Widget _field(wire.FilterNode node, List<int> path, bool enabled) {
    Key key(String kind) => ValueKey(('source-filter-$kind', path.join('.')));
    switch (node.whichKind()) {
      case wire.FilterNode_Kind.text:
        return CupertinoTextFormFieldRow(
          key: key('text'),
          autofillHints: null,
          initialValue: node.text.state,
          enabled: enabled,
          maxLength: 4096,
          onChanged: (value) => node.text.state = value,
          prefix: Text(node.name),
        );
      case wire.FilterNode_Kind.checkBox:
        return MergeSemantics(
          child: CupertinoFormRow(
            prefix: Expanded(flex: 3, child: Text(node.name)),
            child: CupertinoSwitch(
              key: key('check'),
              value: node.checkBox.state,
              onChanged: enabled
                  ? (value) => setState(() => node.checkBox.state = value)
                  : null,
            ),
          ),
        );
      case wire.FilterNode_Kind.triState:
        return ChoiceField<int>(
          key: key('tri'),
          inline: false,
          label: node.name,
          value: node.triState.state,
          options: {
            for (final item in [(0, '忽略'), (1, '包含'), (2, '排除')])
              item.$1: item.$2,
          },
          onChanged: enabled
              ? (value) => setState(() => node.triState.state = value!)
              : null,
        );
      case wire.FilterNode_Kind.select:
        return ChoiceField<int>(
          key: key('select'),
          inline: false,
          label: node.name,
          value: node.select.state,
          options: {
            for (var index = 0; index < node.select.options.length; index++)
              index: node.select.options[index],
          },
          onChanged: enabled
              ? (value) => setState(() => node.select.state = value!)
              : null,
        );
      case wire.FilterNode_Kind.sort:
        final state = node.sort.state;
        final selection = state.hasSelection() ? state.selection : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChoiceField<int>(
              key: key('sort'),
              inline: false,
              label: node.name,
              value: selection?.index,
              options: {
                null: '默认排序',
                for (var index = 0; index < node.sort.options.length; index++)
                  index: node.sort.options[index],
              },
              onChanged: enabled
                  ? (index) => setState(() {
                      node.sort.state = wire.FilterSortState(
                        selection: index == null
                            ? null
                            : wire.FilterSortSelection(
                                index: index,
                                ascending: selection?.ascending ?? true,
                              ),
                      );
                    })
                  : null,
            ),
            CupertinoFormRow(
              prefix: const Expanded(flex: 3, child: Text('排序方向')),
              child: CupertinoButton(
                key: key('ascending'),
                onPressed: enabled && selection != null
                    ? () => setState(
                        () => selection.ascending = !selection.ascending,
                      )
                    : null,
                child: Text(selection?.ascending == false ? '降序' : '升序'),
              ),
            ),
          ],
        );
      case wire.FilterNode_Kind.header:
      case wire.FilterNode_Kind.separator:
      case wire.FilterNode_Kind.group:
      case wire.FilterNode_Kind.notSet:
        throw const FormatException('筛选字段缺少输入类型');
    }
  }

  @override
  Widget build(BuildContext context) {
    useListenable(widget.catalog);
    final current = _current;
    final enabled = current && !_working && !widget.catalog.busy;
    final draft = _draft;
    return EditSheet(
      title: const Text('筛选漫画'),
      content: ListView(
        key: const ValueKey('source-filter-form'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.query.isEmpty ? '应用后按筛选条件搜索' : '搜索词：${widget.query}',
                ),
                if (_work case final work?) ...[
                  Row(
                    children: [
                      const CupertinoActivityIndicator(),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(switch (work) {
                          _FilterWork.loading => '正在读取筛选条件',
                          _FilterWork.resetting => '正在重置筛选条件',
                          _FilterWork.applying => '正在应用筛选条件',
                        }),
                      ),
                    ],
                  ),
                  Text(
                    '关闭将取消请求，可能需要重新连接漫画源。',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
                if (!current)
                  Text(
                    '漫画源会话已变化，请关闭后重新打开筛选。',
                    style: TextStyle(
                      color: AppColors.error.resolveFrom(context),
                    ),
                  )
                else ...[
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: AppColors.error.resolveFrom(context),
                      ),
                    ),
                  if (draft == null && !_working)
                    CupertinoButton(
                      onPressed: enabled ? () => _load() : null,
                      child: const Text('重试加载筛选'),
                    ),
                ],
              ],
            ),
          ),
          if (current && draft != null)
            KeyedSubtree(
              key: ValueKey(draft.snapshotId),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (draft.nodes.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('这个漫画源没有额外筛选条件。'),
                    ),
                  ..._sections(draft.nodes, [], enabled),
                ],
              ),
            ),
        ],
      ),
      actions: [
        CupertinoButton(
          onPressed: _close,
          padding: const EdgeInsets.all(8),
          child: Icon(
            CupertinoIcons.xmark,
            semanticLabel: _working ? '取消请求并关闭筛选' : '取消筛选编辑',
          ),
        ),
        CupertinoButton(
          key: const ValueKey('source-filter-reset'),
          onPressed: enabled ? () => _load(reset: true) : null,
          child: const Text('重置筛选'),
        ),
        CupertinoButton.filled(
          key: const ValueKey('source-filter-apply'),
          onPressed: enabled && draft != null ? _apply : null,
          child: const Text('应用筛选'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _disposing = true;
    final requestId = _requestId;
    if (requestId != null) {
      final catalog = widget.catalog;
      unawaited(
        Future<void>.microtask(
          () => catalog.cancelSourceFilterRequest(requestId),
        ),
      );
    }
    super.dispose();
  }
}
