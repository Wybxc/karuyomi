import '../../theme/app_theme.dart';
import '../../widgets/app_routes.dart';
import '../../widgets/edit_sheet.dart';
import '../../widgets/choice_field.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/source_preferences_repository.dart';
import '../browse/catalog_controller.dart';
import 'source_preferences_controller.dart';

class const SourcePreferencesSheet({
  super.key,
  required final CatalogController catalog,
  required final SourcePreferencesTarget target,
  required final SourcePreferencesRepository repository,
}) extends StatefulHookWidget {
  @override
  State<SourcePreferencesSheet> createState() => _SourcePreferencesSheetState();
}

class _SourcePreferencesSheetState extends State<SourcePreferencesSheet> {
  late final SourcePreferencesController _controller;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = SourcePreferencesController(
      catalog: widget.catalog,
      target: widget.target,
      repository: widget.repository,
      isCurrent: () => _current,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_controller.load());
    });
  }

  bool get _current =>
      mounted &&
      !_closing &&
      identical(widget.catalog.sourcePreferences, widget.repository) &&
      !widget.catalog.accessPaused &&
      ModalRoute.of(context)?.isActive == true;

  Future<void> _text(wire.PreferenceNode node, List<int> path) async {
    final result = await showAppDialog<String>(
      context: context,
      builder: (_) =>
          _PreferenceTextDialog(node: node, controller: _controller),
    );
    if (_current && result != null && _controller.canEdit) {
      await _controller.change(path, wire.PreferenceValue(text: result));
    }
  }

  Future<void> _multi(wire.PreferenceNode node, List<int> path) async {
    final selected = node.multiChoice.values.toSet();
    final available = node.multiChoice.options
        .map((option) => option.value)
        .toSet();
    final missing = selected.difference(available);
    var closing = false;
    final result = await showAppSheet<List<String>>(
      context: context,
      enableDrag: false,
      scrollableBuilder: (context, _) => StatefulBuilder(
        builder: (context, setDialogState) => ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            // A successful dismissal can start saving before the reverse
            // transition ends. Keep that frame stable and freeze its actions.
            final editable = closing || _controller.canEdit;
            void dismiss([List<String>? value]) {
              if (closing) return;
              closing = true;
              Navigator.pop(context, value);
            }

            void change(String value, bool checked) {
              if (closing || !_controller.canEdit) return;
              setDialogState(() {
                if (checked) {
                  selected.add(value);
                } else {
                  selected.remove(value);
                }
              });
            }

            return EditSheet(
              title: Text(node.title),
              leading: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: dismiss,
                child: Text(editable ? '取消' : '关闭'),
              ),
              trailing: editable
                  ? CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () =>
                          dismiss(selected.intersection(available).toList()),
                      child: const Text('应用', semanticsLabel: '应用此设置'),
                    )
                  : null,
              content: ListView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: [
                  CupertinoFormSection.insetGrouped(
                    footer: editable
                        ? Text(
                            missing.isNotEmpty
                                ? '部分当前值已不在可选列表中。应用新的选择时将移除这些不可用项。'
                                : '应用前只保留当前选择，取消不会修改设置。',
                          )
                        : null,
                    children: [
                      if (!editable)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('身份或漫画源已变化，请关闭后重新打开设置。'),
                        )
                      else
                        for (final option in node.multiChoice.options)
                          MergeSemantics(
                            child: CupertinoListTile(
                              onTap: () => change(
                                option.value,
                                !selected.contains(option.value),
                              ),
                              title: Builder(
                                builder: (context) => DefaultTextStyle(
                                  style: DefaultTextStyle.of(context).style,
                                  child: Text(option.label),
                                ),
                              ),
                              trailing: CupertinoCheckbox(
                                value: selected.contains(option.value),
                                onChanged: (value) =>
                                    change(option.value, value == true),
                              ),
                            ),
                          ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    if (_current && result != null && _controller.canEdit) {
      await _controller.change(
        path,
        wire.PreferenceValue(strings: wire.PreferenceStringSet(values: result)),
      );
    }
  }

  Widget _node(wire.PreferenceNode node, List<int> path, bool parentEnabled) {
    if (!node.visible) return const SizedBox.shrink();
    final enabled = parentEnabled && node.enabled && _controller.canEdit;
    final account =
        node.syncScope ==
        wire.PreferenceSyncScope.PREFERENCE_SYNC_SCOPE_ACCOUNT;
    final scopeLabel = account ? '服务端确认后同步' : '仅当前客户端会话';
    final caption = <String>[
      if (account && node.summary.isNotEmpty) node.summary,
      if (node.whichKind() != wire.PreferenceNode_Kind.group) scopeLabel,
    ];
    final captionStyle = TextStyle(
      fontSize: 13,
      color: AppColors.secondaryLabel.resolveFrom(context),
    );
    final key = ValueKey(('source-preference', path.join('.')));
    switch (node.whichKind()) {
      case wire.PreferenceNode_Kind.toggle:
        return MergeSemantics(
          child: CupertinoFormRow(
            prefix: Expanded(flex: 3, child: Text(node.title)),
            helper: Text(caption.join('\n'), style: captionStyle),
            child: CupertinoSwitch(
              key: key,
              value: node.toggle.value,
              onChanged: enabled
                  ? (value) => unawaited(
                      _controller.change(
                        path,
                        wire.PreferenceValue(boolean: value),
                      ),
                    )
                  : null,
            ),
          ),
        );
      case wire.PreferenceNode_Kind.text:
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: enabled ? () => _text(node, path) : null,
          child: CupertinoListTile(
            key: key,
            title: Text(node.title),
            subtitle: Text(
              [
                if (node.text.secret)
                  '密码内容已隐藏'
                else if (node.text.hasValue())
                  node.text.value
                else
                  '未保存，使用漫画源默认值',
                ...caption,
              ].join('\n'),
              maxLines: 4,
            ),
            trailing: const Icon(CupertinoIcons.pencil),
          ),
        );
      case wire.PreferenceNode_Kind.choice:
        final choice = node.choice;
        final value = choice.hasValue() ? choice.value : null;
        final options = <String?, String>{
          null: '未保存，使用漫画源默认值',
          if (value != null &&
              !choice.options.any((option) => option.value == value))
            value: '当前值已不在可选列表中',
          for (final option in choice.options) option.value: option.label,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChoiceField<String>(
              inline: false,
              key: key,
              label: node.title,
              value: value,
              options: options,
              disabledValues: {null, ?value},
              onChanged: enabled && choice.options.isNotEmpty
                  ? (value) {
                      if (_current && _controller.canEdit && value != null) {
                        unawaited(
                          _controller.change(
                            path,
                            wire.PreferenceValue(text: value),
                          ),
                        );
                      }
                    }
                  : null,
            ),
            if (choice.options.isEmpty) const Text('目前没有可选项'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                node.summary == options[value]
                    ? scopeLabel
                    : caption.join('\n'),
                style: captionStyle,
              ),
            ),
          ],
        );
      case wire.PreferenceNode_Kind.multiChoice:
        final selected = node.multiChoice.values.toSet();
        final known = node.multiChoice.options
            .where((option) => selected.contains(option.value))
            .toList();
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: enabled && node.multiChoice.options.isNotEmpty
              ? () => _multi(node, path)
              : null,
          child: CupertinoListTile(
            key: key,
            title: Text(node.title),
            subtitle: Text(
              [
                if (selected.isEmpty)
                  '未选择'
                else
                  known.map((option) => option.label).join('、'),
                if (known.length != selected.length) '部分当前值已不在可选列表中',
                if (node.multiChoice.options.isEmpty) '目前没有可选项',
                ...caption,
              ].join('\n'),
              maxLines: 4,
            ),
            trailing: const Icon(CupertinoIcons.list_bullet),
          ),
        );
      case wire.PreferenceNode_Kind.group:
        return Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _sections(
            node.group.nodes,
            path,
            parentEnabled && node.enabled,
            header: Text(node.title),
            footer: !account || node.summary.isEmpty
                ? null
                : Text(node.summary),
          ),
        );
      case wire.PreferenceNode_Kind.action:
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: enabled ? () => unawaited(_controller.click(path)) : null,
          child: CupertinoListTile(
            key: key,
            title: Text(node.title),
            subtitle: caption.isEmpty
                ? null
                : Text(caption.join('\n'), maxLines: 4),
            trailing: const Icon(CupertinoIcons.play),
          ),
        );
      case wire.PreferenceNode_Kind.unsupported:
        return CupertinoListTile(
          key: key,
          title: Text(node.title),
          subtitle: Text(node.unsupported.reason, maxLines: 6),
          leading: const Icon(CupertinoIcons.info_circle),
        );
      case wire.PreferenceNode_Kind.notSet:
        throw const FormatException('漫画源设置缺少类型');
    }
  }

  List<Widget> _sections(
    List<wire.PreferenceNode> nodes,
    List<int> parentPath,
    bool parentEnabled, {
    Widget? header,
    Widget? footer,
  }) {
    final sections = <Widget>[];
    final captionStyle = TextStyle(
      fontSize: 13,
      color: AppColors.secondaryLabel.resolveFrom(context),
    );
    var rows = <Widget>[];
    void flush() {
      if (rows.isEmpty && header == null) return;
      sections.add(
        Semantics(
          container: true,
          explicitChildNodes: true,
          child: rows.isEmpty
              ? CupertinoListSection.insetGrouped(
                  header: header == null
                      ? null
                      : DefaultTextStyle(style: captionStyle, child: header!),
                  footer: footer == null
                      ? null
                      : DefaultTextStyle(style: captionStyle, child: footer!),
                )
              : CupertinoFormSection.insetGrouped(
                  header: header,
                  footer: footer,
                  children: rows,
                ),
        ),
      );
      rows = [];
      header = null;
      footer = null;
    }

    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      if (!node.visible) continue;
      final path = [...parentPath, index];
      if (node.whichKind() == wire.PreferenceNode_Kind.group) {
        flush();
        sections.add(_node(node, path, parentEnabled));
      } else {
        rows.add(_node(node, path, parentEnabled));
      }
    }
    flush();
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    useListenable(_controller);
    final snapshot = _controller.snapshot;
    final pending = _controller.available ? _controller.pending : null;
    final activity = _controller.activity;
    return EditSheet(
      title: const Text('漫画源设置'),
      leading: CupertinoButton(
        onPressed: () {
          _closing = true;
          _controller.cancelActiveRequest();
          Navigator.of(context).pop();
        },
        padding: EdgeInsets.zero,
        child: const Icon(CupertinoIcons.xmark, semanticLabel: '关闭设置'),
      ),
      content: ListView(
        key: const ValueKey('source-preferences-form'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (snapshot == null && pending == null)
                  Text(
                    '${widget.target.source.name} · ${widget.target.source.lang}',
                  ),
                if (activity != null) ...[
                  const CupertinoActivityIndicator(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: Text(switch (activity) {
                      SourcePreferencesActivity.reading => '正在读取漫画源设置。可关闭此页。',
                      SourcePreferencesActivity.editing =>
                        '正在应用漫画源设置。关闭会取消运行中的漫画源请求。',
                      SourcePreferencesActivity.saving =>
                        '正在保存漫画源设置，等待服务端确认。关闭后仍可处理原请求。',
                      SourcePreferencesActivity.readingConfirmed =>
                        '保存已确认，正在读取最新设置。',
                    }),
                  ),
                ],
                if (!_current) const Text('身份或服务已变化，请关闭后重新打开设置。'),
                if (_controller.error case final error?)
                  Text(
                    error,
                    style: TextStyle(
                      color: AppColors.error.resolveFrom(context),
                    ),
                  ),
                if (_controller.message != null) Text(_controller.message!),
                if (pending != null) ...[
                  _PendingSourcePreferences(
                    source:
                        '${widget.target.source.name} · ${widget.target.source.lang}',
                    draft: pending,
                  ),
                  if (pending.retryable)
                    CupertinoButton.filled(
                      key: const ValueKey('source-preferences-retry'),
                      onPressed: _controller.busy
                          ? null
                          : () => unawaited(_controller.retry()),
                      child: Text(
                        pending.acknowledged ? '重试读取最新设置' : '重试原保存请求',
                      ),
                    ),
                ],
                if ((_controller.needsRecovery || pending != null) &&
                    !(pending?.acknowledged == true &&
                        pending?.retryable == true))
                  CupertinoButton(
                    key: const ValueKey('source-preferences-recover'),
                    onPressed: _controller.available && !_controller.busy
                        ? () => unawaited(_controller.recover())
                        : null,
                    child: const Text('读取服务端状态并重新打开'),
                  ),
                if (snapshot == null &&
                    !_controller.busy &&
                    !_controller.needsRecovery &&
                    pending == null)
                  CupertinoButton(
                    onPressed: _controller.available
                        ? () => unawaited(_controller.load())
                        : null,
                    child: const Text('重试读取设置'),
                  ),
              ],
            ),
          ),
          if (snapshot != null) ...[
            KeyedSubtree(
              key: ValueKey(snapshot.snapshotId),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _sections(
                  snapshot.nodes,
                  [],
                  true,
                  header: Text(widget.target.source.name),
                  footer: Text(
                    snapshot.nodes.isEmpty
                        ? '这个漫画源没有额外设置。'
                        : '每次修改只执行一次漫画源操作。非敏感设置收到服务器确认后生效；密码及会话设置不会同步。',
                  ),
                ),
              ),
            ),
          ],
          CupertinoButton(
            key: const ValueKey('source-preferences-refresh'),
            onPressed:
                _controller.available && !_controller.busy && pending == null
                ? () => unawaited(_controller.load(reopen: true))
                : null,
            child: const Text('重新读取并刷新漫画源'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _closing = true;
    _controller.dispose();
    super.dispose();
  }
}

class const _PendingSourcePreferences({
  required final String source,
  required final SourcePreferencesDraft draft,
}) extends HookWidget {
  static String _value(wire.PreferenceValue value) => switch (value
      .whichValue()) {
    wire.PreferenceValue_Value.boolean => value.boolean ? '开启' : '关闭',
    wire.PreferenceValue_Value.text => value.text.isEmpty ? '空文本' : value.text,
    wire.PreferenceValue_Value.integer => value.integer.toString(),
    wire.PreferenceValue_Value.decimal => value.decimal.toString(),
    wire.PreferenceValue_Value.strings =>
      value.strings.values.isEmpty ? '空列表' : value.strings.values.join('、'),
    wire.PreferenceValue_Value.longInteger => value.longInteger.toString(),
    wire.PreferenceValue_Value.notSet => '无值',
  };

  @override
  Widget build(BuildContext context) {
    final expansion = useMemoized(ExpansibleController.new);
    useEffect(() => expansion.dispose, [expansion]);
    final request = draft.request;
    final status = draft.acknowledged
        ? '已确认'
        : draft.retryable
        ? '未确认'
        : '已拒绝';
    return CupertinoListSection.insetGrouped(
      margin: EdgeInsets.zero,
      header: Text('$status的原保存请求 · 基于版本 ${request.expectedRevision}'),
      children: [
        CupertinoListTile(
          title: DefaultTextStyle(
            style: CupertinoTheme.of(context).textTheme.textStyle,
            child: Text(source),
          ),
          subtitle: Text('${request.entries.length} 项同步值'),
        ),
        Expansible(
          key: const PageStorageKey('source-preferences-submitted-values'),
          controller: expansion,
          animationStyle:
              MediaQuery.reduceMotionOf(context) ||
                  MediaQuery.disableAnimationsOf(context)
              ? AnimationStyle.noAnimation
              : null,
          headerBuilder: (context, animation) => Semantics(
            expanded: expansion.isExpanded,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => expansion.isExpanded
                  ? expansion.collapse()
                  : expansion.expand(),
              child: CupertinoListTile(
                title: const Text('查看原提交值'),
                trailing: RotationTransition(
                  turns: animation.drive(Tween(begin: 0.0, end: 0.25)),
                  child: Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: AppColors.accent.resolveFrom(context),
                  ),
                ),
              ),
            ),
          ),
          bodyBuilder: (context, animation) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (request.entries.isEmpty) const Text('清空此漫画源的同步值'),
                for (final entry in request.entries)
                  Text('${entry.key}：${_value(entry.value)}'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class const _PreferenceTextDialog({
  required final wire.PreferenceNode node,
  required final SourcePreferencesController controller,
}) extends HookWidget {
  @override
  Widget build(BuildContext context) {
    useListenable(controller);
    final closing = useRef(false);
    final editable = closing.value || controller.canEdit;
    final preference = node.text;
    final text = preference.hasValue() ? preference.value : '';
    final input = useTextEditingController(text: text);
    useEffect(() {
      if (preference.selectAllOnOpen) {
        input.selection = TextSelection(
          baseOffset: 0,
          extentOffset: text.length,
        );
      }
      return null;
    }, const []);
    void dismiss([String? value]) {
      if (closing.value) return;
      closing.value = true;
      Navigator.pop(context, value);
    }

    return CupertinoAlertDialog(
      title: Text(node.title),
      content: editable
          ? CupertinoTextField(
              controller: input,
              readOnly: closing.value,
              autofocus: true,
              autofillHints: null,
              obscureText: preference.secret,
              maxLength: 4096,
              placeholder: preference.hasHint() ? preference.hint : null,
            )
          : const Text('身份或漫画源已变化，请关闭后重新打开设置。'),
      actions: [
        CupertinoButton(
          onPressed: dismiss,
          child: Text(editable ? '取消' : '关闭'),
        ),
        if (editable)
          CupertinoButton(
            onPressed: () => dismiss(input.text),
            child: const Text(
              '应用',
              semanticsLabel: '应用此设置',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
