import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/business_state_client.dart';
import '../../data/cover_repository.dart';
import '../browse/catalog_controller.dart';
import 'cover_selection.dart';
import 'custom_cover.dart';

Future<void> showCustomCoverEditor({
  required BuildContext context,
  required CatalogController controller,
  required CoverRepository repository,
  required String mangaKey,
  required Listenable lifecycle,
  required bool Function() isCurrent,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _CoverEditor(
    controller: controller,
    repository: repository,
    mangaKey: mangaKey,
    lifecycle: lifecycle,
    isCurrent: isCurrent,
  ),
);

class _CoverEditor extends StatefulWidget {
  const _CoverEditor({
    required this.controller,
    required this.repository,
    required this.mangaKey,
    required this.lifecycle,
    required this.isCurrent,
  });
  final CatalogController controller;
  final CoverRepository repository;
  final String mangaKey;
  final Listenable lifecycle;
  final bool Function() isCurrent;
  @override
  State<_CoverEditor> createState() => _CoverEditorState();
}

class _CoverEditorState extends State<_CoverEditor> {
  CoverSnapshot? _confirmed;
  Uint8List? _selected;
  bool _clearing = false;
  bool _busy = false;
  bool _attempted = false;
  bool _blocked = false;
  bool _expired = false;
  String? _error;
  CoverDraft? get _pending => widget.repository.pending(widget.mangaKey);
  late final _changes = Listenable.merge([widget.controller, widget.lifecycle]);
  bool get _current {
    _checkCurrent();
    return mounted && !_expired;
  }

  @override
  void initState() {
    super.initState();
    _expired = !widget.isCurrent();
    _changes.addListener(_checkCurrent);
    if (!_expired) unawaited(_load());
  }

  void _checkCurrent() {
    if (!mounted || _expired || widget.isCurrent()) return;
    _expired = true;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _load() async {
    if (!_current || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await widget.repository.load(widget.mangaKey);
      if (!_current) return;
      setState(() {
        _confirmed = snapshot;
        _blocked = _pending?.retryable == false;
        if (_pending == null) {
          _selected = null;
          _clearing = false;
          _attempted = false;
        }
      });
    } catch (_) {
      if (_current) setState(() => _error = '未能读取服务端封面，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select() async {
    if (!_current || _busy || _pending != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await selectCoverImage();
      if (!_current || bytes == null) return;
      setState(() {
        _selected = bytes;
        _clearing = false;
        _attempted = false;
      });
    } on FormatException catch (error) {
      if (_current) setState(() => _error = error.message);
    } catch (_) {
      if (_current) setState(() => _error = '未能读取所选图片，请重新选择。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({bool retry = false}) async {
    if (!_current || _busy || _blocked) return;
    if (!retry && (_confirmed == null || (!_clearing && _selected == null))) {
      return;
    }
    setState(() {
      _busy = true;
      _attempted = true;
      _error = null;
    });
    try {
      final CoverSnapshot snapshot;
      if (retry) {
        snapshot = await widget.repository.retry(widget.mangaKey);
      } else {
        final confirmed = _confirmed;
        if (confirmed == null) return;
        if (_clearing) {
          snapshot = await widget.repository.clear(
            mangaKey: widget.mangaKey,
            basedOnRevision: confirmed.revision,
          );
        } else {
          final selected = _selected;
          if (selected == null) return;
          snapshot = await widget.repository.replace(
            mangaKey: widget.mangaKey,
            bytes: selected,
            contentType: 'image/jpeg',
            basedOnRevision: confirmed.revision,
          );
        }
      }
      if (!_current) return;
      setState(() {
        _confirmed = snapshot;
        _selected = null;
        _clearing = false;
        _attempted = false;
      });
    } on BusinessStateException catch (failure) {
      if (!_current) return;
      setState(() {
        _blocked = failure.conflict || !failure.error.retryable;
        _error = failure.conflict
            ? '封面或作品已在其他设备更新。请重新读取后确认，不会覆盖远端修改。'
            : _blocked
            ? '封面未保存，请重新读取后再修改。'
            : '尚未确认保存。请重试原修改，当前显示的服务端封面未变。';
      });
    } on BusinessPendingMutationException {
      if (_current) {
        setState(() {
          _blocked = true;
          _error = '该作品还有另一项未确认修改，请先处理原操作后重新读取。';
        });
      }
    } catch (_) {
      if (_current) setState(() => _error = '尚未确认保存。请重试原修改，当前会话保留所选封面。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _close() {
    if ((!_expired && _busy) || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final preview = pending?.bytes ?? _selected;
    final clearing = pending != null ? pending.cover == null : _clearing;
    final editable =
        !_expired &&
        !_busy &&
        pending == null &&
        !_blocked &&
        _confirmed != null;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AlertDialog(
        title: const Text('自定义封面'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_expired)
                  const Text('身份或服务已变化，原窗口已停用。请关闭后重新打开。')
                else ...[
                  const Text('服务端已确认'),
                  const SizedBox(height: 8),
                  if (_confirmed case final confirmed?)
                    CustomCover(
                      repository: widget.repository,
                      cover: confirmed.cover,
                      width: 120,
                      height: 160,
                    )
                  else
                    const Text('正在读取封面'),
                  if (preview != null || clearing) ...[
                    const SizedBox(height: 16),
                    Text(_attempted || pending != null ? '尚未确认的修改' : '待保存的修改'),
                    if (clearing)
                      const Text('清除自定义封面')
                    else
                      Image.memory(
                        preview!,
                        width: 120,
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('cover-select-image'),
                        onPressed: editable ? _select : null,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(
                          _confirmed?.cover == null ? '选择图片' : '替换图片',
                        ),
                      ),
                      if (_confirmed?.cover != null)
                        TextButton(
                          key: const ValueKey('cover-clear'),
                          onPressed: editable
                              ? () => setState(() {
                                  _selected = null;
                                  _clearing = true;
                                  _attempted = false;
                                })
                              : null,
                          child: const Text('清除封面'),
                        ),
                    ],
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (pending != null)
                    const Text('当前会话保留原操作。重试不会更换图片或覆盖新的远端版本。'),
                  if (_error case final error?) Text(error),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: !_expired && _busy ? null : _close,
            child: Text(pending != null ? '稍后处理' : '关闭'),
          ),
          if (!_expired &&
              (_blocked || pending?.retryable == false || _confirmed == null))
            FilledButton(
              onPressed: _busy ? null : _load,
              child: const Text('重新读取'),
            ),
          if (!_expired && !_blocked && pending?.retryable == true)
            FilledButton(
              key: const ValueKey('cover-retry'),
              onPressed: _busy ? null : () => _save(retry: true),
              child: const Text('重试原修改'),
            ),
          if (!_expired &&
              pending == null &&
              !_blocked &&
              (_selected != null || _clearing))
            FilledButton(
              key: const ValueKey('cover-save'),
              onPressed: _busy || _confirmed == null ? null : _save,
              child: const Text('保存封面'),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _changes.removeListener(_checkCurrent);
    super.dispose();
  }
}
