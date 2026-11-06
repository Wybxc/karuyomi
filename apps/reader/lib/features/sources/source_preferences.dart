import 'dart:async';

import 'package:flutter/material.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/source_preferences_repository.dart';
import '../browse/catalog_controller.dart';
import 'source_preferences_controller.dart';

class SourcePreferencesSheet extends StatefulWidget {
  const SourcePreferencesSheet({
    super.key,
    required this.catalog,
    required this.target,
    required this.repository,
  });
  final CatalogController catalog;
  final SourcePreferencesTarget target;
  final SourcePreferencesRepository repository;

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
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _PreferenceTextDialog(node: node),
    );
    if (_current && result != null && _controller.canEdit) {
      await _controller.change(path, wire.PreferenceValue(text: result));
    }
  }

  Future<void> _choice(wire.PreferenceNode node, List<int> path) async {
    String? selected = node.choice.hasValue() ? node.choice.value : null;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(node.title),
          content: DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            items: [
              if (selected != null &&
                  !node.choice.options.any(
                    (option) => option.value == selected,
                  ))
                DropdownMenuItem(
                  value: selected,
                  enabled: false,
                  child: const Text('当前值已不在可选列表中'),
                ),
              for (final option in node.choice.options)
                DropdownMenuItem(
                  value: option.value,
                  child: Text(option.label),
                ),
            ],
            onChanged: (value) => setDialogState(() => selected = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed:
                  node.choice.options.any((option) => option.value == selected)
                  ? () => Navigator.pop(context, selected)
                  : null,
              child: const Text('应用此设置'),
            ),
          ],
        ),
      ),
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
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(node.title),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (missing.isNotEmpty)
                    const Text('部分当前值已不在可选列表中。应用新的选择时将移除这些不可用项。'),
                  for (final option in node.multiChoice.options)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(option.label),
                      value: selected.contains(option.value),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selected.add(option.value);
                        } else {
                          selected.remove(option.value);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
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
        return SwitchListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          title: Text(node.title),
          subtitle: Text(caption.join('\n')),
          value: node.toggle.value,
          onChanged: enabled
              ? (value) => unawaited(
                  _controller.change(
                    path,
                    wire.PreferenceValue(boolean: value),
                  ),
                )
              : null,
        );
      case wire.PreferenceNode_Kind.text:
        return ListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
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
          trailing: const Icon(Icons.edit_outlined),
          onTap: enabled ? () => _text(node, path) : null,
        );
      case wire.PreferenceNode_Kind.choice:
        final matches = node.choice.options.where(
          (option) => option.value == node.choice.value,
        );
        return ListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          title: Text(node.title),
          subtitle: Text(
            [
              if (!node.choice.hasValue())
                '未保存，使用漫画源默认值'
              else if (matches.isEmpty)
                '当前值已不在可选列表中'
              else
                matches.first.label,
              if (node.choice.options.isEmpty) '目前没有可选项',
              ...caption,
            ].join('\n'),
          ),
          trailing: const Icon(Icons.arrow_drop_down),
          onTap: enabled && node.choice.options.isNotEmpty
              ? () => _choice(node, path)
              : null,
        );
      case wire.PreferenceNode_Kind.multiChoice:
        final selected = node.multiChoice.values.toSet();
        final known = node.multiChoice.options
            .where((option) => selected.contains(option.value))
            .toList();
        return ListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
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
          trailing: const Icon(Icons.checklist),
          onTap: enabled && node.multiChoice.options.isNotEmpty
              ? () => _multi(node, path)
              : null,
        );
      case wire.PreferenceNode_Kind.group:
        return ExpansionTile(
          key: key,
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: true,
          title: Text(node.title),
          subtitle: !account || node.summary.isEmpty
              ? null
              : Text(node.summary),
          childrenPadding: const EdgeInsets.only(left: 12),
          children: [
            for (var index = 0; index < node.group.nodes.length; index++)
              _node(node.group.nodes[index], [
                ...path,
                index,
              ], parentEnabled && node.enabled),
          ],
        );
      case wire.PreferenceNode_Kind.action:
        return ListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          title: Text(node.title),
          subtitle: caption.isEmpty ? null : Text(caption.join('\n')),
          trailing: const Icon(Icons.play_arrow),
          onTap: enabled ? () => unawaited(_controller.click(path)) : null,
        );
      case wire.PreferenceNode_Kind.unsupported:
        return ListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          title: Text(node.title),
          subtitle: Text(node.unsupported.reason),
          leading: const Icon(Icons.info_outline),
        );
      case wire.PreferenceNode_Kind.notSet:
        throw const FormatException('漫画源设置缺少类型');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final snapshot = _controller.snapshot;
      final pending = _controller.pending;
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            ListTile(
              title: const Text('漫画源设置'),
              subtitle: Text(widget.target.source.name),
              trailing: IconButton(
                tooltip: '关闭设置',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _closing = true;
                  _controller.cancelActiveRequest();
                  Navigator.of(context).pop();
                },
              ),
            ),
            if (_controller.busy) ...[
              const LinearProgressIndicator(),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text('正在处理。关闭会取消运行中的请求，可能需要重新连接。'),
              ),
            ],
            Expanded(
              child: ListView(
                key: const ValueKey('source-preferences-form'),
                padding: const EdgeInsets.all(24),
                children: [
                  if (!_current) const Text('身份或服务已变化，请关闭后重新打开设置。'),
                  if (_controller.error != null) Text(_controller.error!),
                  if (_controller.message != null) Text(_controller.message!),
                  if (pending != null) ...[
                    Text(
                      '未确认的原保存请求 · 基于版本 ${pending.request.expectedRevision}',
                    ),
                    Text(
                      '包含 ${pending.request.entries.length} 项可同步设置；密码和会话值不在请求中。',
                    ),
                    FilledButton(
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
                    OutlinedButton(
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
                    OutlinedButton(
                      onPressed: _controller.available
                          ? () => unawaited(_controller.load())
                          : null,
                      child: const Text('重试读取设置'),
                    ),
                  if (snapshot != null) ...[
                    const Text('每次修改只执行一次漫画源操作。非敏感设置收到服务器确认后生效；密码及会话设置不会同步。'),
                    const SizedBox(height: 12),
                    if (snapshot.nodes.isEmpty) const Text('这个漫画源没有额外设置。'),
                    KeyedSubtree(
                      key: ValueKey(snapshot.snapshotId),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (
                            var index = 0;
                            index < snapshot.nodes.length;
                            index++
                          )
                            _node(snapshot.nodes[index], [index], true),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                key: const ValueKey('source-preferences-refresh'),
                onPressed:
                    _controller.available &&
                        !_controller.busy &&
                        pending == null
                    ? () => unawaited(_controller.load(reopen: true))
                    : null,
                icon: const Icon(Icons.refresh),
                label: const Text('重新读取并刷新漫画源'),
              ),
            ),
          ],
        ),
      );
    },
  );

  @override
  void dispose() {
    _closing = true;
    _controller.dispose();
    super.dispose();
  }
}

class _PreferenceTextDialog extends StatefulWidget {
  const _PreferenceTextDialog({required this.node});
  final wire.PreferenceNode node;
  @override
  State<_PreferenceTextDialog> createState() => _PreferenceTextDialogState();
}

class _PreferenceTextDialogState extends State<_PreferenceTextDialog> {
  late final TextEditingController _input;
  @override
  void initState() {
    super.initState();
    _input = TextEditingController(
      text: widget.node.text.hasValue() ? widget.node.text.value : '',
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.node.title),
    content: TextField(
      controller: _input,
      autofocus: true,
      obscureText: widget.node.text.secret,
      maxLength: 4096,
      decoration: InputDecoration(
        labelText: widget.node.title,
        helperText:
            widget.node.syncScope ==
                wire.PreferenceSyncScope.PREFERENCE_SYNC_SCOPE_ACCOUNT
            ? '确认后同步到其他设备'
            : '仅保留在当前客户端会话',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _input.text),
        child: const Text('应用此设置'),
      ),
    ],
  );
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }
}
