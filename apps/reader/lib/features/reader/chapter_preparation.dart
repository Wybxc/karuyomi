import '../browse/catalog_controller.dart';
import 'chapter_sequence.dart';

/// Owns at most one extra pages() session. Active Source metadata calls cannot
/// be preempted safely: obsolete results are closed after the call completes.
final class ChapterPreparation {
  ChapterPreparation(this._open);
  final Future<OpenedChapter?> Function(SequenceChapter) _open;
  (String, OpenedChapter)? _ready;
  String? _wanted;
  Future<void>? _pending;
  Future<void>? _discarding;
  bool _closed = false;
  OpenedChapter? _failedOwner;
  Object? _cleanupError;
  StackTrace? _cleanupStack;

  bool get busy => _pending != null || _discarding != null;
  bool get ready => _ready != null;
  bool get blocked => _failedOwner != null;

  void _checkCleanup() {
    if (_cleanupError != null) {
      Error.throwWithStackTrace(_cleanupError!, _cleanupStack!);
    }
  }

  Future<void> _closeOwned(OpenedChapter opened) async {
    try {
      await opened.provider.close();
    } catch (error, stack) {
      // A rejected ACK is not a release. Retain this owner and fence further
      // opens until the runtime is rebuilt; provider.close itself is terminal.
      _failedOwner = opened;
      _cleanupError = error;
      _cleanupStack = stack;
      rethrow;
    }
  }

  Future<void> prepare(SequenceChapter chapter) {
    if (blocked) return Future.error(_cleanupError!, _cleanupStack);
    if (_closed || busy || ready) return Future.value();
    _wanted = chapter.key;
    return _pending = _load(chapter).whenComplete(() => _pending = null);
  }

  Future<void> _load(SequenceChapter chapter) async {
    final opened = await _open(chapter);
    if (opened == null) return;
    if (_closed || _wanted != chapter.key) {
      await _closeOwned(opened);
    } else {
      _ready = (chapter.key, opened);
    }
  }

  Future<OpenedChapter?> take(SequenceChapter chapter) async {
    _checkCleanup();
    await _discarding;
    await _pending;
    _checkCleanup();
    if (_closed) return null;
    final prepared = _ready;
    if (prepared != null && prepared.$1 == chapter.key) {
      _ready = null;
      _wanted = null;
      return prepared.$2;
    }
    await discard();
    return null;
  }

  Future<void> discard() {
    _wanted = null;
    if (blocked) return Future.error(_cleanupError!, _cleanupStack);
    return _discarding ??= _discard().whenComplete(() => _discarding = null);
  }

  Future<void> _discard() async {
    final prepared = _ready;
    _ready = null;
    if (prepared != null) await _closeOwned(prepared.$2);
    await _pending;
  }

  Future<void> close() {
    _closed = true;
    return discard();
  }
}
