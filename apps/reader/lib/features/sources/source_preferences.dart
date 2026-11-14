import '../../theme/app_theme.dart';
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
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => _PreferenceTextDialog(node: node),
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
    final result = await showCupertinoSheet<List<String>>(
      context: context,
      enableDrag: false,
      scrollableBuilder: (context, _) => StatefulBuilder(
        builder: (context, setDialogState) => EditSheet(
          title: Text(node.title),
          content: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (missing.isNotEmpty)
                const Text('部分当前值已不在可选列表中。应用新的选择时将移除这些不可用项。'),
              for (final option in node.multiChoice.options)
                MergeSemantics(
                  child: CupertinoFormRow(
                    prefix: Expanded(flex: 3, child: Text(option.label)),
                    padding: EdgeInsets.zero,
                    child: CupertinoCheckbox(
                      value: selected.contains(option.value),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selected.add(option.value);
                        } else {
                          selected.remove(option.value);
                        }
                      }),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            CupertinoButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            CupertinoButton(
              onPressed: () => Navigator.pop(
                context,
                selected.intersection(available).toList(),
              ),

              child: const Text('应用此设置'),
            ),
          ],
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
    final caption = <String>[
      if (account && node.summary.isNotEmpty) node.summary,
      if (node.whichKind() != wire.PreferenceNode_Kind.group)
        account ? '服务端确认后同步' : '仅当前客户端会话',
    ];
    final key = ValueKey(('source-preference', path.join('.')));
    switch (node.whichKind()) {
      case wire.PreferenceNode_Kind.toggle:
        return MergeSemantics(
          child: CupertinoFormRow(
            prefix: Expanded(flex: 3, child: Text(node.title)),
            helper: Text(caption.join('\n')),
            padding: EdgeInsets.zero,
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
            ),
            trailing: const Icon(CupertinoIcons.pencil),
            padding: EdgeInsets.zero,
          ),
        );
      case wire.PreferenceNode_Kind.choice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChoiceField<String>(
              inline: false,
              key: key,
              label: node.title,
              value: node.choice.hasValue() ? node.choice.value : null,
              options: {
                null: '未保存，使用漫画源默认值',
                if (node.choice.hasValue() &&
                    !node.choice.options.any(
                      (option) => option.value == node.choice.value,
                    ))
                  node.choice.value: '当前值已不在可选列表中',
                for (final option in node.choice.options)
                  option.value: option.label,
              },
              disabledValues: {
                null,
                if (node.choice.hasValue()) node.choice.value,
              },
              onChanged: enabled && node.choice.options.isNotEmpty
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
            if (node.choice.options.isEmpty) const Text('目前没有可选项'),
            Text(caption.join('\n')),
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
            ),
            trailing: const Icon(CupertinoIcons.list_bullet),
            padding: EdgeInsets.zero,
          ),
        );
      case wire.PreferenceNode_Kind.group:
        return CupertinoListSection(
          backgroundColor: AppColors.background.resolveFrom(context),
          separatorColor: AppColors.separator.resolveFrom(context),
          decoration: BoxDecoration(
            color: AppColors.groupedSurface.resolveFrom(context),
          ),
          key: key,
          header: Text(node.title),
          footer: !account || node.summary.isEmpty ? null : Text(node.summary),
          children: [
            for (var index = 0; index < node.group.nodes.length; index++)
              _node(node.group.nodes[index], [
                ...path,
                index,
              ], parentEnabled && node.enabled),
          ],
        );
      case wire.PreferenceNode_Kind.action:
        return CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: enabled ? () => unawaited(_controller.click(path)) : null,
          child: CupertinoListTile(
            key: key,
            title: Text(node.title),
            subtitle: caption.isEmpty ? null : Text(caption.join('\n')),
            trailing: const Icon(CupertinoIcons.play),
            padding: EdgeInsets.zero,
          ),
        );
      case wire.PreferenceNode_Kind.unsupported:
        return CupertinoListTile(
          key: key,
          title: Text(node.title),
          subtitle: Text(node.unsupported.reason),
          leading: const Icon(CupertinoIcons.info_circle),
          padding: EdgeInsets.zero,
        );
      case wire.PreferenceNode_Kind.notSet:
        throw const FormatException('漫画源设置缺少类型');
    }
  }

  @override
  Widget build(BuildContext context) {
    useListenable(_controller);
    final snapshot = _controller.snapshot;
    final pending = _controller.pending;
    return EditSheet(
      title: const Text('漫画源设置'),
      content: ListView(
        key: const ValueKey('source-preferences-form'),
        padding: const EdgeInsets.all(24),
        children: [
          Text(widget.target.source.name),
          if (_controller.busy) ...[
            const CupertinoActivityIndicator(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text('正在处理。关闭会取消运行中的请求，可能需要重新连接。'),
            ),
          ],
          if (!_current) const Text('身份或服务已变化，请关闭后重新打开设置。'),
          if (_controller.error != null) Text(_controller.error!),
          if (_controller.message != null) Text(_controller.message!),
          if (pending != null) ...[
            Text('未确认的原保存请求 · 基于版本 ${pending.request.expectedRevision}'),
            Text('包含 ${pending.request.entries.length} 项可同步设置；密码和会话值不在请求中。'),
            CupertinoButton.filled(
              key: const ValueKey('source-preferences-retry'),
              onPressed:
                  _controller.available &&
                      !_controller.busy &&
                      pending.retryable
                  ? () => unawaited(_controller.retry())
                  : null,
              child: const Text('重试原保存请求'),
            ),
          ],
          if (_controller.needsRecovery || pending != null)
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
          if (snapshot != null) ...[
            const Text('每次修改只执行一次漫画源操作。非敏感设置收到服务器确认后生效；密码及会话设置不会同步。'),
            SizedBox(height: 12),
            if (snapshot.nodes.isEmpty) const Text('这个漫画源没有额外设置。'),
            KeyedSubtree(
              key: ValueKey(snapshot.snapshotId),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < snapshot.nodes.length; index++)
                    _node(snapshot.nodes[index], [index], true),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        CupertinoButton(
          onPressed: () {
            _closing = true;
            _controller.cancelActiveRequest();
            Navigator.of(context).pop();
          },
          padding: const EdgeInsets.all(8),
          child: const Icon(CupertinoIcons.xmark, semanticLabel: '关闭设置'),
        ),
        CupertinoButton(
          key: const ValueKey('source-preferences-refresh'),
          onPressed:
              _controller.available && !_controller.busy && pending == null
              ? () => unawaited(_controller.load(reopen: true))
              : null,
          child: const Text('重新读取并刷新漫画源'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _closing = true;
    _controller.dispose();
    super.dispose();
  }
}

class const _PreferenceTextDialog({required final wire.PreferenceNode node})
    extends HookWidget {
  @override
  Widget build(BuildContext context) {
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
    return CupertinoAlertDialog(
      title: Text(node.title),
      content: CupertinoTextField(
        controller: input,
        autofocus: true,
        obscureText: preference.secret,
        maxLength: 4096,
        placeholder: preference.hasHint() ? preference.hint : null,
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, input.text),
          isDefaultAction: true,
          child: const Text('应用此设置'),
        ),
      ],
    );
  }
}
