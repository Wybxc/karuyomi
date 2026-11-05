import 'dart:async';

/// Waits on one explicitly opened window. The browser adapter owns that window
/// handle, so another tab cannot supply this attempt's completion location.
final class PopupAuthentication {
  PopupAuthentication({
    this.pollInterval = const Duration(milliseconds: 200),
    this.timeout = const Duration(minutes: 3),
  });

  final Duration pollInterval;
  final Duration timeout;
  final _result = Completer<bool>();
  Timer? _poll;
  Timer? _deadline;
  void Function()? _close;

  Future<bool> wait({
    required Uri origin,
    required String attempt,
    required Uri? Function() readLocation,
    required bool Function() isClosed,
    required void Function() close,
  }) {
    if (_close != null || _result.isCompleted) {
      throw StateError('登录窗口已在使用中');
    }
    _close = close;
    void check() {
      if (_result.isCompleted) return;
      // Access pages can be cross-origin until the first-party redirect. Only
      // the adapter's same-origin location read can complete authentication.
      final location = readLocation();
      if (location != null &&
          location.hasAuthority &&
          location.origin == origin.origin &&
          location.path == '/auth/complete' &&
          location.queryParameters['attempt'] == attempt) {
        _finish();
      } else if (isClosed()) {
        _finish(StateError('登录窗口已关闭或被浏览器隔离，请重新登录。'));
      }
    }

    _poll = Timer.periodic(pollInterval, (_) => check());
    _deadline = Timer(timeout, () {
      _finish(StateError('等待登录超时，请重新登录。'));
    });
    check();
    return _result.future;
  }

  void cancel() {
    if (!_result.isCompleted) _finish(StateError('登录已取消，请重新登录。'));
  }

  void _finish([StateError? error]) {
    if (_result.isCompleted) return;
    _poll?.cancel();
    _deadline?.cancel();
    try {
      _close?.call();
    } catch (_) {
      // Browser policy may prevent closing a window after it was isolated.
    }
    if (error == null) {
      _result.complete(true);
    } else {
      _result.completeError(error);
    }
  }
}
