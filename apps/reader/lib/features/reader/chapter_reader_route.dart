import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../widgets/app_appearance.dart';

import '../../widgets/choice_field.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/reading_progress.dart';
import '../../diagnostics/reader_baseline.dart';
import '../browse/catalog_controller.dart';
import '../bookmarks/chapter_bookmarks_controller.dart';
import '../bookmarks/bookmark_status.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_widgets.dart' as settings_ui;
import 'chapter_sequence.dart';
import 'chapter_preparation.dart';
import 'reader_screen.dart';
import 'reader_preferences.dart';
import 'reading_progress_controller.dart';
import 'reader_recovery.dart';

/// One navigation route owns the whole reading session, not one route per page
/// list. A new leaf can only acquire images after the previous leaf's ACKs.
class const ChapterReaderRoute({
  super.key,
  required final CatalogController catalog,
  required final MangaEntry manga,
  required final CatalogSourceRef source,
  required final ChapterSequence sequence,
  required final SequenceChapter initialChapter,
  required final OpenedChapter initialOpened,
  final ReaderAuthentication? onAuthenticate,
  final ReadingPosition? initialPosition,
  final ChapterOrder? initialOrder,
  final ReadingMode initialMode = ReadingMode.leftToRight,
  final bool? initialDoublePage,
}) extends StatefulHookConsumerWidget {
  @override
  ConsumerState<ChapterReaderRoute> createState() => _ChapterReaderRouteState();
}

class _ChapterReaderRouteState extends ConsumerState<ChapterReaderRoute> {
  late OpenedChapter _opened = widget.initialOpened;
  late SequenceChapter _chapter = widget.initialChapter;
  late MangaEntry _manga = widget.manga;
  late CatalogSourceRef _source = widget.source;
  late ChapterSequence _sequence = widget.sequence;
  late final String? _subject;
  late final String? _packageName;
  late final String? _origin;
  ChapterOrder _order = ChapterOrder.source;
  late ReadingMode _mode = widget.initialMode;
  late bool? _doublePage = widget.initialDoublePage;
  ReaderFit _fit = ReaderFit.contain;
  bool _cropBorders = false;
  ReaderBackground _background = ReaderBackground.black;
  int _dimPercent = 0;
  ReaderInputPreset _tapZones = ReaderInputPreset.standard;
  ReaderInputPreset _keyboard = ReaderInputPreset.standard;
  Completer<void> _viewClosed = Completer<void>();
  bool _visible = true;
  bool _busy = false;
  bool _closing = false;
  bool _viewAttached = false;
  String? _error;
  Future<void>? _moving;
  late final _preparation = ChapterPreparation(_openChapter);
  ReaderViewportState? _viewport;
  bool _preparationScheduled = false;
  String? _preparationAttempt;
  ReadingProgressController? _progress;
  ReadingPosition? _initialPosition;
  bool _preserveInitialPlacement = false;
  late ValueNotifier<ReadingPosition?> _positionRequest;
  bool _allowPop = false;
  bool _exitPending = false;
  bool _accessPaused = false;
  bool _recovering = false;
  bool _initializing = false;
  bool _refreshingProgress = false;
  ChapterBookmarksController? _bookmarks;
  SettingsControllerProvider get _settingsProvider =>
      settingsControllerProvider(
        widget.catalog,
        widget.catalog.settings,
        mangaKey: _sequence.mangaKey,
      );
  bool get _settingsCurrent =>
      widget.catalog.subject == _subject &&
      widget.catalog.deploymentOrigin?.origin == _origin;
  SettingsState get _settingsState =>
      _settingsCurrent ? ref.read(_settingsProvider) : const SettingsState();
  SettingsController? get _settings =>
      _settingsCurrent ? ref.read(_settingsProvider.notifier) : null;
  Object? _appliedSettings;

  @override
  void initState() {
    super.initState();
    // Capture identity before a reconnect clears Catalog's live identity.
    _subject = widget.catalog.subject;
    _packageName = widget.catalog.activeBuild?.packageName;
    _origin = widget.catalog.deploymentOrigin?.origin;
    _order = widget.initialOrder ?? ChapterOrder.source;
    _initialPosition = widget.initialPosition;
    _accessPaused = widget.catalog.accessPaused;
    _progress = widget.catalog.createReadingProgress(_sequence.mangaKey);
    _installBookmarks();
    if (_progress != null && _opened.manifest.pages.isNotEmpty) {
      _visible = false;
      _initializing = true;
      unawaited(_restoreInitial());
    }
  }

  void _installBookmarks() {
    _bookmarks?.dispose();
    _bookmarks = null;
    final repository = widget.catalog.bookmarks;
    if (repository == null) return;
    _bookmarks = ChapterBookmarksController(
      repository: repository,
      mangaKey: _sequence.mangaKey,
      isCurrent: () =>
          mounted &&
          !_closing &&
          widget.catalog.subject == _subject &&
          widget.catalog.deploymentOrigin?.origin == _origin,
    );
    unawaited(_bookmarks!.refresh());
  }

  void _applySettings(SettingsState settings) {
    final value = settings.snapshot;
    if (settings.available &&
        value != null &&
        !identical(value, _appliedSettings)) {
      _appliedSettings = value;
      _mode = settings_ui.readerMode(value.effectiveReader.mode);
      _doublePage = settings_ui.doublePage(value.effectiveReader.pageLayout);
      _background = settings_ui.readerBackground(
        value.effectiveReader.background,
      );
      _fit = settings_ui.readerFit(value.effectiveReader.fit);
      _cropBorders = value.effectiveReader.cropBorders;
      _dimPercent = value.effectiveReader.dimPercent;
      _tapZones = settings_ui.readerInputPreset(value.effectiveReader.tapZones);
      _keyboard = settings_ui.readerInputPreset(value.effectiveReader.keyboard);
    }
  }

  bool get _canEditSettings =>
      !_busy &&
      !_accessPaused &&
      !_recovering &&
      !_initializing &&
      _settingsState.canEdit;

  void _changeMode(ReadingMode value) {
    final controller = _settings;
    final snapshot = _settingsState.snapshot;
    if (!_canEditSettings || controller == null || snapshot == null) return;
    setState(() => _mode = value);
    final draft = wire.ReaderSettingsOverride()
      ..mergeFromMessage(snapshot.overrides!)
      ..mode = settings_ui.wireReaderMode(value);
    unawaited(controller.saveOverrides(draft, snapshot.mangaRevision!));
  }

  void _changePageLayout(bool? value) {
    final controller = _settings;
    final snapshot = _settingsState.snapshot;
    if (!_canEditSettings || controller == null || snapshot == null) return;
    setState(() => _doublePage = value);
    final draft = wire.ReaderSettingsOverride()
      ..mergeFromMessage(snapshot.overrides!)
      ..pageLayout = settings_ui.wirePageLayout(value);
    unawaited(controller.saveOverrides(draft, snapshot.mangaRevision!));
  }

  Future<void> _editSettings() async {
    final controller = _settings;
    if (controller == null || _accessPaused || _recovering || _closing) return;
    await showCupertinoSheet<void>(
      context: context,
      enableDrag: false,
      scrollableBuilder: (context, _) => settings_ui.MangaSettingsEditor(
        catalog: widget.catalog,
        mangaKey: _sequence.mangaKey,
      ),
    );
  }

  Future<void> _restoreInitial() async {
    final position = await _progress!.restore(_opened.manifest);
    if (_closing || !mounted) return;
    setState(() {
      _initialPosition = widget.initialPosition ?? position;
      _preserveInitialPlacement =
          widget.initialPosition == null &&
          position != null &&
          !_progress!.awaitingViewport;
      _order =
          widget.initialOrder ??
          (_progress!.reversedOrder
              ? ChapterOrder.reversed
              : ChapterOrder.source);
      _visible = true;
      _initializing = false;
    });
  }

  void _progressChanged() {
    if (!_closing && mounted) setState(() {});
  }

  void _catalogChanged() {
    if (_closing || !mounted) return;
    _bookmarks?.checkCurrent();
    if (widget.catalog.extensionUnavailableReason case final reason?) {
      setState(() => _error = reason);
    }
    if (widget.catalog.accessPaused && !_accessPaused) {
      setState(() => _accessPaused = true);
      // The displayed leaf keeps its resources. Only the extra page session is
      // discarded; an active Source call settles before its owner is closed.
      unawaited(
        _preparation.discard().catchError((Object _) {
          if (mounted && !_closing) {
            setState(() => _error = '下一章资源清理未完成，请重新连接');
          }
        }),
      );
    }
    _schedulePreparation();
  }

  Future<void> _recoverReading() async {
    final authenticate = widget.onAuthenticate;
    final subject = _subject;
    final packageName = _packageName;
    final origin = _origin;
    if (_recovering ||
        _busy ||
        _refreshingProgress ||
        _initializing ||
        _closing ||
        authenticate == null ||
        subject == null ||
        packageName == null ||
        origin == null) {
      return;
    }
    final continuation = ReaderRecoveryContext(
      origin: origin,
      subject: subject,
      packageName: packageName,
      sourceId: _source.sourceId,
      manga: _manga.snapshot,
      chapterKey: _chapter.key,
      position: _viewport?.current ?? _initialPosition,
      order: _order,
      mode: _mode,
      doublePage: _doublePage,
    );
    setState(() {
      _recovering = true;
      _error = null;
    });
    RecoveredReader? recovered;
    try {
      if (!await authenticate(continuation) || _closing || !mounted) return;
      _mode = continuation.mode;
      _doublePage = continuation.doublePage;
      // The visible login has finished. Unmount and ACK the old leaf before a
      // Native rebuild can delete its files or a new identity can own the slot.
      setState(() => _visible = false);
      if (!_viewAttached && !_viewClosed.isCompleted) {
        _viewClosed.complete(_opened.provider.close());
      }
      await _viewClosed.future;
      await _preparation.discard();
      if (_closing || !mounted) return;
      await widget.catalog.connect();
      if (_closing || !mounted) return;
      if (widget.catalog.status != ServiceStatus.ready) {
        throw StateError(widget.catalog.error ?? '服务重新连接未完成');
      }
      if (widget.catalog.subject != subject ||
          widget.catalog.deploymentOrigin?.origin != origin) {
        setState(() {
          _error = '登录身份或服务已改变，原阅读资源已清理，请返回浏览。';
          _allowPop = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_closing) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        });
        return;
      }
      recovered = await recoverReader(
        widget.catalog,
        continuation,
        isCurrent: () => !_closing && mounted,
      );
      if (_closing || !mounted) return;
      if (recovered == null) {
        throw StateError(widget.catalog.error ?? '当前章节恢复未完成，可重新连接');
      }
      final next = recovered;
      // Reauthentication resumes the existing view; it is not an explicit
      // acceptance of another device's progress. Keep its original CAS/epoch
      // until a deliberate reopen adopts the current server position.
      await _progress?.refreshFromServer(next.opened.manifest);
      if (_closing || !mounted) return;
      if (widget.catalog.status != ServiceStatus.ready ||
          widget.catalog.subject != subject ||
          !widget.catalog.isCurrentSource(next.source)) {
        throw StateError(widget.catalog.error ?? '恢复时漫画源会话已改变，请重新连接');
      }
      final anchor = next.position;
      final manifest = next.opened.manifest;
      setState(() {
        _manga = next.manga;
        _sequence = next.sequence;
        _source = next.source;
        _chapter = next.chapter;
        _opened = next.opened;
        _initialPosition = anchor;
        // A fresh leaf can center the same decoded point differently. Keep
        // the original placement so removing recovery controls does not save
        // a synthetic move. Missing pages still use the normal fallback.
        _preserveInitialPlacement =
            anchor != null &&
            anchor.chapterKey == manifest.chapterKey &&
            anchor.manifestVersion == manifest.version &&
            manifest.pages.any((page) => page.key == anchor.pageKey);
        _viewport = null;
        _positionRequest.value = null;
        _viewClosed = Completer<void>();
        _viewAttached = false;
        _preparationAttempt = null;
        _accessPaused = false;
        _visible = true;
      });
      _installBookmarks();
      recovered = null;
    } catch (error) {
      if (!_closing && mounted) {
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : '重新登录未完成，请重试',
        );
      }
    } finally {
      try {
        if (recovered != null) await recovered.opened.provider.close();
      } catch (_) {
        if (!_closing && mounted) {
          setState(() => _error = '恢复章节的资源清理未完成，请返回重新连接');
        }
      } finally {
        if (!_closing && mounted) setState(() => _recovering = false);
      }
    }
  }

  Widget _accessNotice() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          widget.catalog.status == ServiceStatus.denied
              ? '当前身份没有访问权限，已暂停新请求。当前画面与未保存草稿保留。'
              : '访问验证已失效，已暂停新的图片和下一章请求。当前画面与未保存草稿保留。',
        ),
      ),
      if (widget.onAuthenticate != null)
        CupertinoButton.filled(
          onPressed:
              _recovering || _busy || _initializing || _refreshingProgress
              ? null
              : () => unawaited(_recoverReading()),
          child: Text(_recovering ? '正在恢复阅读' : '重新登录并恢复本章'),
        ),
    ],
  );

  void _lifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshProgress());
      if (!_accessPaused && !_recovering) {
        unawaited(_bookmarks?.refresh());
        unawaited(_settings?.refresh());
      }
    } else if (!_accessPaused && !_recovering) {
      unawaited(_progress?.flush());
    }
  }

  Future<void> _refreshProgress() async {
    final progress = _progress;
    if (progress == null ||
        _refreshingProgress ||
        _closing ||
        _busy ||
        _recovering ||
        _initializing ||
        _accessPaused ||
        !widget.catalog.isCurrentSource(_source)) {
      return;
    }
    setState(() => _refreshingProgress = true);
    try {
      await progress.refreshFromServer(_opened.manifest);
    } finally {
      if (!_closing && mounted) {
        setState(() => _refreshingProgress = false);
      }
    }
  }

  void _recordViewport({bool complete = false}) {
    final viewport = _viewport;
    if (viewport == null || _closing) return;
    _progress?.observe(
      manifest: _opened.manifest,
      current: viewport.current,
      observed: viewport.observed,
      reversedOrder: _order == ChapterOrder.reversed,
      complete: complete,
    );
  }

  Future<void> _finishChapter() async {
    final canComplete = _viewport?.atEnd == true && _viewport?.observed != null;
    if (_busy || _recovering || _refreshingProgress || !canComplete) return;
    _recordViewport(complete: true);
    await _progress?.flush();
  }

  Future<void> _resetChapter() async {
    final progress = _progress;
    if (_busy || _recovering || _refreshingProgress || progress == null) return;
    setState(() => _busy = true);
    final reset = await progress.reset(_opened.manifest);
    if (!_closing && mounted) {
      if (reset != null &&
          identical(_progress, progress) &&
          widget.catalog.subject == _subject &&
          widget.catalog.deploymentOrigin?.origin == _origin &&
          widget.catalog.isCurrentSource(_source)) {
        _viewport = null;
        final first = reset.current;
        final leadingX = _mode == ReadingMode.rightToLeft ? 1.0 : 0.0;
        // Reset is confirmed by the server before the explicit local jump;
        // only this new navigation uses the current direction's leading edge.
        _positionRequest.value = ReadingPosition(
          chapterKey: first.chapterKey,
          pageKey: first.pageKey,
          manifestVersion: first.manifestVersion,
          pageIndexHint: first.pageIndexHint,
          normalizedOffset: 0,
          normalizedX: leadingX,
          viewportX: leadingX,
          viewportY: 0,
        );
      }
      setState(() => _busy = false);
    }
  }

  Future<void> _exit() async {
    if (_exitPending || _closing) return;
    _exitPending = true;
    await _progress?.flush();
    if (_closing || !mounted) return;
    setState(() => _allowPop = true);
    // Update PopScope before requesting the second, now permitted pop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) Navigator.of(context).pop();
    });
  }

  void _schedulePreparation() {
    if (_preparationScheduled || _closing) return;
    _preparationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preparationScheduled = false;
      if (!mounted ||
          _closing ||
          _accessPaused ||
          _recovering ||
          _busy ||
          _preparation.busy ||
          _preparation.ready ||
          _preparation.blocked ||
          widget.catalog.busy ||
          !widget.catalog.isCurrentSource(_source) ||
          _viewport?.atEnd != true ||
          _viewport?.windowReady != true) {
        return;
      }
      final next = _sequence.adjacent(_chapter.sourceIndex, _order, 1);
      if (next == null) return;
      final attempt = '${_chapter.key}:${next.key}';
      if (_preparationAttempt == attempt) return;
      _preparationAttempt = attempt;
      unawaited(_prepareNext(next));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<OpenedChapter?> _openChapter(SequenceChapter chapter) =>
      widget.catalog.openChapter(
        _manga,
        ChapterEntry(chapter.snapshot),
        reference: _source,
        logicalChapterKey: chapter.key,
      );

  Future<void> _prepareNext(SequenceChapter target) async {
    if (_busy ||
        _accessPaused ||
        _recovering ||
        _closing ||
        _preparation.busy ||
        _preparation.ready ||
        _preparation.blocked) {
      return;
    }
    final pending = _preparation.prepare(target);
    setState(() => _error = null);
    try {
      await pending;
      if (!_closing && mounted) {
        setState(() {
          if (!_preparation.ready && widget.catalog.error != null) {
            _error = widget.catalog.error;
          }
        });
      }
    } catch (_) {
      if (!_closing && mounted) {
        setState(() => _error = '下一章准备未完成，可进入时重试');
      }
    }
  }

  void _changeOrder(ChapterOrder order) {
    final pending = _preparation.discard();
    setState(() {
      _order = order;
      _preparationAttempt = null;
    });
    _recordViewport();
    unawaited(() async {
      try {
        await pending;
      } catch (_) {
        if (!_closing && mounted) {
          setState(() => _error = '章节资源清理失败，请返回重新连接漫画源');
        }
      }
      if (!_closing && mounted) setState(() {});
      _schedulePreparation();
    }());
  }

  Future<void> _move(SequenceChapter target, {bool reopen = false}) {
    if (_busy ||
        _closing ||
        _accessPaused ||
        _recovering ||
        _refreshingProgress ||
        (target.key == _chapter.key && !reopen)) {
      return Future.value();
    }
    ReaderBaselineScope.read(context)?.event('navigation', {
      'action': reopen ? 'reopen_chapter' : 'change_chapter',
      'fromChapterKey': _chapter.key,
      'targetChapterKey': target.key,
    });
    setState(() {
      _busy = true;
      _error = null;
    });
    final operation = _changeChapter(target);
    _moving = operation;
    return operation;
  }

  Future<void> _changeChapter(SequenceChapter target) async {
    final source = _source;
    OpenedChapter? next;
    try {
      // Next is an explicit completion action only when the real viewport has
      // displayed the chapter end. A jump or a prepared session is not one.
      if (_sequence.adjacent(_chapter.sourceIndex, _order, 1)?.key ==
              target.key &&
          _viewport?.atEnd == true &&
          _viewport?.observed != null) {
        _recordViewport(complete: true);
      }
      await _progress?.flush();
      next = await _preparation.take(target);
      if (_closing || !mounted) return;
      next ??= await _openChapter(target);
      if (next == null) {
        if (!_closing && mounted) {
          setState(() => _error = widget.catalog.error ?? '章节未能打开，请重试');
        }
        return;
      }
      if (_closing || !mounted) return;
      setState(() {
        _visible = false;
      });
      await _viewClosed.future;
      if (_closing || !mounted) return;
      await _progress?.flush();
      final adoptingServerState = _progress?.needsReopen(target.key) ?? false;
      final position = await _progress?.restore(next.manifest);
      if (_closing || !mounted) return;
      if (!widget.catalog.isCurrentSource(source)) {
        throw StateError('Source session expired during chapter transition');
      }
      setState(() {
        _opened = next!;
        _chapter = target;
        _viewClosed = Completer<void>();
        _viewAttached = false;
        _viewport = null;
        _initialPosition = position;
        _preserveInitialPlacement =
            adoptingServerState &&
            position != null &&
            _progress?.awaitingViewport == false;
        if (adoptingServerState &&
            _progress?.needsReopen(target.key) == false) {
          _order = _progress!.reversedOrder
              ? ChapterOrder.reversed
              : ChapterOrder.source;
        }
        _positionRequest.value = null;
        _preparationAttempt = null;
        _visible = true;
      });
      next = null; // The route owns it until onAttached mounts the new leaf.
    } catch (_) {
      if (!_closing && mounted) {
        setState(() => _error = '章节切换未完成，请返回重新连接漫画源');
      }
    } finally {
      if (next != null) {
        try {
          await next.provider.close();
        } catch (_) {
          if (!_closing && mounted) {
            setState(() => _error = '章节资源清理失败，请返回重新连接漫画源');
          }
        }
      }
      if (!_closing && mounted) setState(() => _busy = false);
    }
  }

  bool get _blocked => _busy || _accessPaused || _recovering;
  bool get _progressBlocked => _blocked || _refreshingProgress;
  bool _progressRecovery(ReadingProgressController progress) =>
      progress.error != null || progress.needsReopen(_chapter.key);
  bool _bookmarkRecovery(ChapterBookmarksController bookmarks) =>
      bookmarks.busy || bookmarks.error != null || bookmarks.pending != null;

  Widget _readerStatus() => Column(
    key: const ValueKey('reader-persistent-status'),
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_busy || _preparation.busy) const CupertinoActivityIndicator(),
      if (_accessPaused) _accessNotice(),
      if (_error case final error?) Text(error),
      if (_settings case final settings?)
        if (_settingsState.error != null || _settingsState.pending != null)
          settings_ui.SettingsStatus(
            controller: settings,
            state: _settingsState,
          ),
      if (_progress case final progress?) ...[
        Text(
          _opened.manifest.pages.isEmpty
              ? '本章没有页面，不记录进度'
              : progress.error ??
                    switch (progress.storageMode) {
                      ProgressStorageMode.serverConfirmed =>
                        progress.unsaved || progress.awaitingViewport
                            ? '阅读进度待服务端确认'
                            : '阅读进度已保存到服务端',
                      null => '正在读取服务端进度',
                    },
        ),
        if (_progressRecovery(progress))
          _progressControls(progress, recovery: true),
      ],
      if (_bookmarks case final bookmarks?)
        if (_bookmarkRecovery(bookmarks))
          BookmarkStatus(
            controller: bookmarks,
            enabled: !_blocked && !_initializing,
          ),
    ],
  );

  Widget _chapterControls() {
    final previous = _sequence.adjacent(_chapter.sourceIndex, _order, -1);
    final next = _sequence.adjacent(_chapter.sourceIndex, _order, 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_settings != null)
          CupertinoButton(
            onPressed: _blocked ? null : _editSettings,
            child: const Text('阅读设置'),
          ),
        if (_progress case final progress?) _progressControls(progress),
        if (_bookmarks case final bookmarks?) ...[
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                !bookmarks.loaded
                    ? bookmarks.busy
                          ? '正在读取本章书签'
                          : '本章书签尚未确认'
                    : bookmarks.contains(_chapter.key)
                    ? '本章已标记书签'
                    : '本章未标记书签',
              ),
              ChapterBookmarkButton(
                controller: bookmarks,
                chapterKey: _chapter.key,
                chapterName: _chapter.name,
                enabled: !_progressBlocked && !_initializing,
              ),
            ],
          ),
          if (!_bookmarkRecovery(bookmarks))
            BookmarkStatus(
              controller: bookmarks,
              enabled: !_blocked && !_initializing,
            ),
        ],
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CupertinoButton(
              onPressed: _progressBlocked || previous == null
                  ? null
                  : () => unawaited(_move(previous)),
              child: const Text('上一章'),
            ),
            ChoiceField<ChapterOrder>(
              label: '章节排序',
              value: _order,
              options: const {
                ChapterOrder.source: '来源顺序',
                ChapterOrder.reversed: '反向来源顺序',
              },
              onChanged: _busy || _recovering || _refreshingProgress
                  ? null
                  : (order) {
                      if (order != null) _changeOrder(order);
                    },
            ),
            CupertinoButton(
              onPressed: _progressBlocked || next == null
                  ? null
                  : () => unawaited(_move(next)),
              child: const Text('下一章'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _progressControls(
    ReadingProgressController progress, {
    bool recovery = false,
  }) {
    if (_opened.manifest.pages.isEmpty) return const SizedBox.shrink();
    final saved = progress.chapter(_chapter.key);
    final unresolved = saved?.furthestUnresolved(_opened.manifest) ?? false;
    final far = saved?.furthest;
    final needsReopen = progress.needsReopen(_chapter.key);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!recovery && unresolved) const Text('旧最远页已不在当前清单中；保留原记录，未按旧页码猜测'),
        if (!recovery && !unresolved && far != null)
          Text(
            '最远：第 ${far.pageIndexHint + 1} 页${saved!.completed ? ' · 本章已读完' : ''}',
          ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (final (label, action) in <(String, VoidCallback?)>[
              if (recovery || !_progressRecovery(progress))
                (
                  _refreshingProgress
                      ? '正在刷新进度'
                      : needsReopen
                      ? '重新打开本章'
                      : '刷新进度',
                  _progressBlocked
                      ? null
                      : needsReopen
                      ? () => unawaited(_move(_chapter, reopen: true))
                      : () => unawaited(_refreshProgress()),
                ),
              if (!recovery)
                (
                  '重新阅读本章',
                  _progressBlocked || needsReopen
                      ? null
                      : () => unawaited(_resetChapter()),
                ),
              if (!recovery)
                (
                  '读完本章',
                  _progressBlocked ||
                          needsReopen ||
                          _viewport?.atEnd != true ||
                          _viewport?.observed == null ||
                          saved?.completed == true
                      ? null
                      : () => unawaited(_finishChapter()),
                ),
              if (recovery &&
                  progress.error != null &&
                  progress.unsaved &&
                  !needsReopen)
                (
                  '重试保存',
                  _progressBlocked ? null : () => unawaited(progress.retry()),
                ),
            ])
              CupertinoButton(onPressed: action, child: Text(label)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _positionRequest = useValueNotifier<ReadingPosition?>(null);
    useOnListenableChange(widget.catalog, _catalogChanged);
    useOnListenableChange(_progress, _progressChanged);
    useOnListenableChange(_bookmarks, _progressChanged);
    useOnAppLifecycleStateChange((_, state) => _lifecycleChanged(state));
    if (_settingsCurrent) _applySettings(ref.watch(_settingsProvider));
    return PopScope<void>(
      canPop: _progress == null || _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_exit());
      },
      child: _reader(),
    );
  }

  Widget _reader() {
    if (!_visible) {
      return GlassScaffold(
        enableBackgroundSampling: false,
        extendBody: false,
        backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
        appBar: GlassAppBar.pinned(
          backgroundColor: AppAppearance.chromeColor(context),
          onBack: () => unawaited(_exit()),
          title: Text(_manga.title),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              if (_accessPaused && !_allowPop) _accessNotice(),
              Expanded(
                child: Center(
                  child: _error == null
                      ? const CupertinoActivityIndicator()
                      : Text(_error!),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final opened = _opened;
    final completion = _viewClosed;
    return ReaderScreen(
      key: ValueKey('${opened.generation}:${opened.provider.pageSessionId}'),
      manifest: opened.manifest,
      provider: opened.provider,
      generation: opened.generation,
      title: opened.title,
      onExit: () => unawaited(_exit()),
      initialPosition: _initialPosition,
      preserveInitialPlacement: _preserveInitialPlacement,
      initialMode: _mode,
      doublePage: _doublePage,
      fit: _fit,
      cropBorders: _cropBorders,
      background: _background,
      dimPercent: _dimPercent,
      tapZones: _tapZones,
      keyboard: _keyboard,
      onModeChanged: _changeMode,
      onDoublePageChanged: _changePageLayout,
      layoutSettingsEnabled: _canEditSettings,
      positionRequest: _positionRequest,
      paused: _accessPaused || _recovering,
      chapterControls: _chapterControls(),
      persistentStatus: _readerStatus(),
      onViewportChanged: (viewport) {
        if (_closing || !identical(opened, _opened)) return;
        final changed =
            _viewport?.atEnd != viewport.atEnd ||
            _viewport?.windowReady != viewport.windowReady;
        _viewport = viewport;
        _recordViewport();
        if (changed && !_closing && mounted) setState(() {});
        _schedulePreparation();
      },
      onAttached: () {
        if (identical(completion, _viewClosed)) _viewAttached = true;
      },
      onClosed: opened.provider.close,
      onClosing: (cleanup) {
        if (identical(completion, _viewClosed)) _viewAttached = false;
        if (!completion.isCompleted) completion.complete(cleanup);
      },
    );
  }

  @override
  void dispose() {
    _closing = true;
    final progress = _progress;
    if (progress != null) {
      final released = widget.catalog.releaseReadingProgress(progress);
      unawaited(released);
    }
    _bookmarks?.dispose();
    final preparationClosed = _preparation.close();
    if (!_viewAttached && !_viewClosed.isCompleted) {
      // setState may install a provider just before a pop removes this route,
      // before the next frame ever mounts its Reader leaf. The route retains
      // ownership until onAttached, so that provider still has a close owner.
      _viewClosed.complete(_opened.provider.close());
    }
    // Child disposal publishes cleanup synchronously; wait through a possible
    // late pages() result as well. Never recycle the runtime to cancel a hop.
    unawaited(() async {
      try {
        await Future.wait<void>([
          _viewClosed.future,
          ?_moving,
          preparationClosed,
        ]);
      } catch (_) {
        // The route has gone; Catalog/runtime errors remain available on return.
      }
    }());
    super.dispose();
  }
}
