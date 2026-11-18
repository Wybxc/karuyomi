import '../../widgets/edit_sheet.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/scheduler.dart';

import '../../data/business_state_client.dart';
import '../../data/cover_repository.dart';
import '../../theme/app_theme.dart';
import '../browse/catalog_controller.dart';
import 'cover_selection.dart';
import 'custom_cover.dart';

Future<bool?> showCustomCoverEditor({
  required BuildContext context,
  required CatalogController controller,
  required CoverRepository repository,
  required String mangaKey,
  required Listenable lifecycle,
  required bool Function() isCurrent,
}) => showCupertinoSheet<bool>(
  context: context,
  enableDrag: false,
  scrollableBuilder: (context, _) => _CoverEditor(
    controller: controller,
    repository: repository,
    mangaKey: mangaKey,
    lifecycle: lifecycle,
    isCurrent: isCurrent,
  ),
);

class const _CoverEditor({
  required final CatalogController controller,
  required final CoverRepository repository,
  required final String mangaKey,
  required final Listenable lifecycle,
  required final bool Function() isCurrent,
}) extends StatefulHookWidget {
  @override
  State<_CoverEditor> createState() => _CoverEditorState();
}

enum _CoverOperation { load, pick, save }

class _CoverEditorState extends State<_CoverEditor> {
  CoverSnapshot? _confirmed;
  Uint8List? _selected;
  bool _clearing = false;
  _CoverOperation? _operation;
  bool get _busy => _operation != null;
  bool _attempted = false;
  bool _saved = false;
  bool _blocked = false;
  bool _expired = false;
  String? _error;
  bool get _canClose =>
      _expired || _operation == null || _operation == _CoverOperation.load;
  CoverDraft? get _pending => widget.repository.pending(widget.mangaKey);
  bool get _current {
    _checkCurrent();
    return mounted && !_expired;
  }

  @override
  void initState() {
    super.initState();
    _expired = !widget.isCurrent();
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
      _operation = _CoverOperation.load;
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
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _select() async {
    if (!_current || _busy || _pending != null) return;
    setState(() {
      _operation = _CoverOperation.pick;
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
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _save({bool retry = false}) async {
    if (!_current || _busy || _blocked) return;
    if (!retry && (_confirmed == null || (!_clearing && _selected == null))) {
      return;
    }
    setState(() {
      _operation = _CoverOperation.save;
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
        _saved = true;
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
            : '尚未确认保存。请重试原修改，当前展示上次确认的封面。';
      });
    } on BusinessPendingMutationException {
      if (_current) {
        setState(() {
          _blocked = true;
          _error = '该作品还有另一项未确认修改，请先处理原操作后重新读取。';
        });
      }
    } catch (_) {
      if (_current) setState(() => _error = '尚未确认保存。请重试原修改，当前会话保留原修改。');
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  void _close() {
    if (!_canClose || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    Navigator.pop(context, _saved);
  }

  @override
  Widget build(BuildContext context) {
    final changes = useMemoized(
      () => Listenable.merge([widget.controller, widget.lifecycle]),
      [widget.controller, widget.lifecycle],
    );
    useOnListenableChange(changes, _checkCurrent);
    final pending = _pending;
    final preview = pending?.bytes ?? _selected;
    final clearing = pending != null ? pending.cover == null : _clearing;
    final editable =
        !_expired &&
        !_busy &&
        pending == null &&
        !_blocked &&
        _confirmed != null;
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: EditSheet(
        key: const ValueKey('cover-editor'),
        title: const Text('自定义封面'),
        leading: Semantics(
          enabled: _canClose,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _canClose ? _close : null,
            child: Text(
              pending != null ? '稍后' : '关闭',
              semanticsLabel: pending != null ? '稍后处理' : null,
            ),
          ),
        ),
        trailing: !_expired && !_blocked && pending?.retryable == true
            ? CupertinoButton(
                key: const ValueKey('cover-retry'),
                padding: EdgeInsets.zero,
                onPressed: _busy ? null : () => _save(retry: true),
                child: const Text('重试', semanticsLabel: '重试原修改'),
              )
            : !_expired &&
                  pending == null &&
                  !_blocked &&
                  (_selected != null || _clearing)
            ? CupertinoButton(
                key: const ValueKey('cover-save'),
                padding: EdgeInsets.zero,
                onPressed: _busy || _confirmed == null ? null : _save,
                child: const Text('保存', semanticsLabel: '保存封面'),
              )
            : null,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_expired)
                CupertinoListSection.insetGrouped(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '身份或服务已变化，原窗口已停用。请关闭后重新打开。',
                        style: TextStyle(
                          color: AppColors.error.resolveFrom(context),
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                CupertinoFormSection.insetGrouped(
                  header: Text(
                    _confirmed == null
                        ? '服务端封面'
                        : _attempted || pending != null
                        ? '上次服务端确认'
                        : '服务端已确认',
                  ),
                  footer: _error == null
                      ? null
                      : Semantics(
                          container: true,
                          liveRegion: true,
                          child: Text(
                            _error!,
                            key: const ValueKey('cover-error'),
                            style: TextStyle(
                              color: AppColors.error.resolveFrom(context),
                            ),
                          ),
                        ),
                  children: [
                    if (_confirmed case final confirmed?)
                      CupertinoFormRow(
                        prefix: confirmed.cover == null
                            ? null
                            : Expanded(child: const Text('当前自定义封面')),
                        child: confirmed.cover == null
                            ? const Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text('未设置自定义封面'),
                              )
                            : CustomCover(
                                repository: widget.repository,
                                cover: confirmed.cover,
                                width: 120,
                                height: 160,
                              ),
                      )
                    else if (!_busy)
                      const CupertinoFormRow(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text('尚未读取服务端封面'),
                        ),
                      ),
                    if (_operation case final operation?)
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: CupertinoFormRow(
                          prefix: Expanded(
                            child: Text(switch (operation) {
                              _CoverOperation.load => '正在读取封面',
                              _CoverOperation.pick => '正在读取所选图片',
                              _CoverOperation.save => '正在等待服务端确认',
                            }),
                          ),
                          child: const CupertinoActivityIndicator(),
                        ),
                      ),
                    Semantics(
                      enabled: editable,
                      child: CupertinoButton(
                        key: const ValueKey('cover-select-image'),
                        alignment: AlignmentDirectional.centerStart,
                        onPressed: editable ? _select : null,
                        child: Text(
                          _confirmed?.cover == null ? '选择图片' : '替换图片',
                        ),
                      ),
                    ),
                    if (_confirmed?.cover != null)
                      Semantics(
                        enabled: editable,
                        child: CupertinoButton(
                          key: const ValueKey('cover-clear'),
                          alignment: AlignmentDirectional.centerStart,
                          foregroundColor: editable
                              ? AppColors.error.resolveFrom(context)
                              : null,
                          onPressed: editable
                              ? () => setState(() {
                                  _selected = null;
                                  _clearing = true;
                                  _attempted = false;
                                })
                              : null,
                          child: const Text('清除封面'),
                        ),
                      ),
                  ],
                ),
                if (preview != null || clearing)
                  CupertinoFormSection.insetGrouped(
                    header: Text(
                      _attempted || pending != null ? '尚未确认的修改' : '待保存的修改',
                    ),
                    footer: Text(
                      _blocked || pending?.retryable == false
                          ? '当前会话保留原修改。请重新读取后再修改，不会覆盖新的远端版本。'
                          : pending != null
                          ? '当前会话保留原操作。重试不会更换图片或覆盖新的远端版本。'
                          : '仅当前会话保留，保存并收到服务端确认后才更新封面。',
                    ),
                    children: [
                      CupertinoFormRow(
                        child: clearing
                            ? const Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Text('清除自定义封面'),
                              )
                            : Image.memory(
                                preview!,
                                width: 120,
                                height: 160,
                                fit: BoxFit.cover,
                                semanticLabel: _attempted || pending != null
                                    ? '尚未确认的封面预览'
                                    : '待保存的封面预览',
                              ),
                      ),
                    ],
                  ),
                if (_blocked ||
                    pending?.retryable == false ||
                    _confirmed == null)
                  CupertinoButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('重新读取'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
