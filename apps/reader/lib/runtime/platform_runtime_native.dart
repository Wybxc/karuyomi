import '../widgets/app_page_route.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/io_client.dart';

import 'cover_transport.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'runtime_platform_types.dart';
import 'native_runtime_assets.dart';
import 'native_image_files.dart';
import 'android_image_files.dart';

PlatformRuntime createPlatformRuntime({Uri? origin}) {
  if (origin == null) {
    throw ArgumentError('Native runtime requires the deployment HTTPS origin');
  }
  return NativePlatformRuntime(origin);
}

final class _NativeRun {
  _NativeRun(HeadlessInAppWebView view) {
    acknowledgement = Future<void>.microtask(view.run).whenComplete(() {
      settled = true;
    });
  }

  late final Future<void> acknowledgement;
  bool settled = false;
}

final class NativePlatformRuntime extends PlatformRuntime
    implements ManagedImageTransport {
  NativePlatformRuntime(Uri origin)
    : this._(origin, const Duration(seconds: 20));

  @visibleForTesting
  NativePlatformRuntime.withStartupTimeout(Uri origin, Duration startupTimeout)
    : this._(origin, startupTimeout);

  NativePlatformRuntime._(this.origin, this._startupTimeout) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError(
        'Native runtime must use a single deployment HTTPS origin',
      );
    }
  }

  @override
  final Uri origin;
  final Duration _startupTimeout;
  @override
  late final CoverTransport coverTransport = HttpCoverTransport(
    origin: origin,
    createClient: IOClient.new,
    sessionHeaders: (target) async {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(target.toString()),
      );
      return {
        if (cookies.isNotEmpty)
          'Cookie': cookies
              .map((cookie) => '${cookie.name}=${cookie.value}')
              .join('; '),
      };
    },
  );
  HeadlessInAppWebView? _view;
  _NativeRun? _viewRunning;
  Future<void>? _retiringStartup;
  InAppWebViewController? _controller;
  Future<void>? _opening;
  int _generation = 0;
  bool _disposed = false;
  bool _closing = false;
  bool _hostReady = false;
  NativeImageControl? _images;
  Completer<void>? _containerEnded;
  Future<void>? _resetting;
  Future<void>? _disposing;

  @override
  bool get runtimeRestartBlocked => _retiringStartup != null;

  @override
  bool ownsImageLocation(String resourceId, String generation, Uri location) =>
      _images?.owns(resourceId, generation, location) ?? false;
  bool _authenticating = false;
  Map<String, Object?>? _authenticationContinuation;

  @override
  Future<bool> authenticate(
    BuildContext context, {
    String returnTo = '/',
    Map<String, Object?> pending = const {},
  }) async {
    if (_disposed || _closing) throw StateError('服务已关闭，请重新连接。');
    if (_authenticating) throw StateError('登录页已打开，请先完成或关闭。');
    final attempt = authenticationAttempt(origin, returnTo);
    final continuation = {'returnTo': returnTo, 'pending': pending};
    wire.checkJsonBudget(continuation, maxBytes: wire.controlRequestLimit);
    _authenticating = true;
    _authenticationContinuation = null;
    try {
      final authenticated = await Navigator.of(context).push<bool>(
        AppPageRoute<bool>(
          builder: (_) => _AuthenticationPage(
            login: attempt.login,
            callback: attempt.callback,
          ),
        ),
      );
      if (authenticated != true || _closing || _disposed) return false;
      // The caller retires the old Reader before reconnecting and verifying the
      // identity. Rebuilding here would delete files behind the visible page.
      _authenticationContinuation = continuation;
      return true;
    } finally {
      _authenticating = false;
    }
  }

  @override
  Map<String, Object?>? takePendingAuthentication() {
    final value = _authenticationContinuation;
    _authenticationContinuation = null;
    return value;
  }

  Future<void> _ensureHost() {
    if (_disposed) {
      return Future.error(
        const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Native runtime container was disposed',
        ),
      );
    }
    if (runtimeRestartBlocked) {
      return Future.error(
        const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Previous Native runtime startup has not finished retiring',
        ),
      );
    }
    final resetting = _resetting;
    if (resetting != null) return resetting.then((_) => _ensureHost());
    final current = _opening;
    if (current != null) return current;
    final opening = _startHost();
    _opening = opening;
    unawaited(
      opening.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(_opening, opening)) _opening = null;
        },
      ),
    );
    return opening;
  }

  Future<void> _startHost() async {
    final generation = ++_generation;
    final ended = Completer<void>();
    _containerEnded = ended;
    final assets = await NativeRuntimeAssets.load();
    final imageFiles =
        Platform.isIOS ||
        (Platform.isAndroid && await AndroidImageFileStore.supported());
    final random = Random.secure();
    final imageToken = imageFiles
        ? 'native-$generation-${List.generate(24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}'
        : null;
    if (Platform.isAndroid &&
        !await WebViewFeature.isFeatureSupported(
          WebViewFeature.DOCUMENT_START_SCRIPT,
        )) {
      throw const RuntimeException(
        RuntimeErrorCode.unsupportedCapability,
        'This Android WebView cannot install the bundled runtime before page scripts',
      );
    }
    if (_closing || _disposed || generation != _generation) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native runtime container was replaced while loading app assets',
      );
    }
    final loaded = Completer<void>();
    var handshaking = false;
    _view = HeadlessInAppWebView(
      initialUserScripts: UnmodifiableListView([
        UserScript(
          groupName: 'karuyomi-native-runtime',
          source: assets.documentStartScript(
            origin,
            imageFileToken: imageToken,
          ),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          contentWorld: ContentWorld.PAGE,
          forMainFrameOnly: true,
          allowedOriginRules: {origin.origin},
        ),
      ]),
      initialUrlRequest: URLRequest(
        // Avoid the static host.html -> host redirect: Android can report an
        // intermediate onLoadStop before the new document's plugin bridge exists.
        url: WebUri(origin.resolve('/runtime/host').toString()),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        sharedCookiesEnabled: true,
        useShouldOverrideUrlLoading: true,
        useOnRenderProcessGone: true,
      ),
      onWebViewCreated: (controller) {
        if (!_closing && !_disposed && generation == _generation) {
          _controller = controller;
        }
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final target = action.request.url;
        // Interactive Access/IdP login uses a separate visible flow; the hidden
        // runtime never silently follows a cross-origin login document.
        if (target != null &&
            Uri.parse(target.toString()).origin != origin.origin) {
          if (generation == _generation && !loaded.isCompleted) {
            loaded.completeError(
              const RuntimeException(
                RuntimeErrorCode.accessRequired,
                'Access login requires a visible authentication flow',
              ),
            );
          }
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onLoadStop: (controller, url) async {
        if (_closing ||
            _disposed ||
            generation != _generation ||
            loaded.isCompleted ||
            handshaking) {
          return;
        }
        if (url == null || Uri.parse(url.toString()).origin != origin.origin) {
          loaded.completeError(
            const RuntimeException(
              RuntimeErrorCode.accessRequired,
              'Access login requires a visible authentication flow',
            ),
          );
          return;
        }
        try {
          final bridgeReady = await controller.evaluateJavascript(
            source:
                '''
              (() => {
                const installed = window.__karuyomiNativeRuntimeInstalled;
                return (document.readyState === 'interactive' ||
                    document.readyState === 'complete') &&
                  location.origin === ${jsonEncode(origin.origin)} &&
                  location.pathname === '/runtime/host' &&
                  !location.search && !location.hash &&
                  typeof window.flutter_inappwebview?.callHandler === 'function' &&
                  !!installed && installed.materialVersion === ${jsonEncode(assets.materialVersion)} &&
                  installed.runtime === window.karuyomiRuntime;
              })();
            ''',
          );
          if (_closing ||
              _disposed ||
              generation != _generation ||
              loaded.isCompleted ||
              handshaking) {
            return;
          }
          if (bridgeReady is! bool) {
            throw const RuntimeException(
              RuntimeErrorCode.protocolError,
              'Native bridge readiness did not return a boolean',
            );
          }
          // An intermediate load event must not claim the handshake. A later
          // initialized document can retry within the existing overall timeout.
          if (!bridgeReady) return;
          handshaking = true;
          final result = await controller.callAsyncJavaScript(
            functionBody: '''
              const installed = window.__karuyomiNativeRuntimeInstalled;
              if (!installed || installed.materialVersion !== materialVersion ||
                  installed.runtime !== window.karuyomiRuntime) {
                throw new Error('Bundled Native runtime is missing or was replaced');
              }
              return JSON.stringify(await window.karuyomiRuntime.control(request));
            ''',
            arguments: {
              'materialVersion': assets.materialVersion,
              'request': wire.encodeProtoJson(
                wire.ControlRequest(
                  slotId: wire.RuntimeSlot.RUNTIME_SLOT_FOREGROUND,
                  requestId: 'native-handshake-$generation',
                  ready: wire.Empty(),
                ),
              ),
            },
          );
          if (_closing || _disposed || generation != _generation) return;
          if (result?.error != null) {
            throw RuntimeException(
              RuntimeErrorCode.runtimeLost,
              'Native runtime control handshake failed: ${result!.error}',
            );
          }
          if (result?.value is! String) {
            throw const RuntimeException(
              RuntimeErrorCode.protocolError,
              'Native runtime handshake did not return ProtoJSON text',
            );
          }
          final response = wire.decodeProtoJson(
            wire.ControlResponse(),
            decodeNativeControlResult(result!.value),
          );
          if (response.whichResult() == wire.ControlResponse_Result.error) {
            throw RuntimeException.fromProto(response.error);
          }
          if (response.requestId != 'native-handshake-$generation' ||
              response.slotId != wire.RuntimeSlot.RUNTIME_SLOT_FOREGROUND ||
              response.whichResult() != wire.ControlResponse_Result.hello ||
              !isCompatibleHost(response.hello) ||
              response.hello.runtimeBaseline != runtimeBaseline) {
            throw const RuntimeException(
              RuntimeErrorCode.protocolError,
              'Incompatible bundled Native runtime',
            );
          }
          if (imageToken != null) {
            final NativeImageFileStore files = Platform.isIOS
                ? await IosImageFileStore.bind(
                    token: imageToken,
                    origin: origin,
                  )
                : await AndroidImageFileStore.bind(controller, origin);
            if (_closing || _disposed || generation != _generation) {
              await files.clear();
              throw const RuntimeException(
                RuntimeErrorCode.runtimeLost,
                'Native image container was replaced during binding',
              );
            }
            _images = NativeImageControl(
              store: files,
              origin: origin,
              call: (request) async => wire.decodeProtoJson(
                wire.ControlResponse(),
                await _callExistingHost(
                  wire.encodeProtoJson(request),
                  generation,
                ),
              ),
            );
          }
          if (!loaded.isCompleted) loaded.complete();
        } catch (error) {
          if (!loaded.isCompleted) loaded.completeError(error);
        }
      },
      onReceivedError: (controller, request, error) {
        if (generation == _generation &&
            request.isForMainFrame == true &&
            !loaded.isCompleted) {
          loaded.completeError(
            RuntimeException(RuntimeErrorCode.runtimeLost, error.description),
          );
        }
      },
      onWebContentProcessDidTerminate: (controller) {
        if (!_closing && !_disposed && generation == _generation) {
          unawaited(rebuild());
        }
      },
      onRenderProcessGone: (controller, detail) {
        if (!_closing && !_disposed && generation == _generation) {
          unawaited(rebuild());
        }
      },
    );
    final view = _view!;
    // Listen to load/termination before the platform run ACK: Android can
    // deliver callbacks before run() marks the view as running.
    final running = _NativeRun(view);
    _viewRunning = running;
    try {
      await Future.any<void>([
        Future.wait<void>([
          running.acknowledgement,
          loaded.future,
        ], eagerError: true),
        ended.future.then<void>(
          (_) => throw const RuntimeException(
            RuntimeErrorCode.runtimeLost,
            'Native runtime container ended during initialization',
          ),
        ),
      ]).timeout(
        _startupTimeout,
        onTimeout: () => throw const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Native runtime initialization timed out',
        ),
      );
    } catch (error, stack) {
      if (generation == _generation) {
        if (!ended.isCompleted) ended.complete();
        ++_generation;
        _view = null;
        _viewRunning = null;
        _controller = null;
        final images = _images;
        _images = null;
        try {
          await _retireHost(images, view, running);
        } catch (cleanupError) {
          debugPrint('Native runtime startup cleanup failed: $cleanupError');
        }
      }
      // A reset/dispose that detached this generation owns its cleanup.
      Error.throwWithStackTrace(error, stack);
    }
    if (_closing || _disposed || generation != _generation) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native runtime container was replaced',
      );
    }
    _hostReady = true;
  }

  Future<void> _retireHost(
    NativeImageControl? images,
    HeadlessInAppWebView? view,
    _NativeRun? running,
  ) async {
    final cleanup = _disposeHost(images, view, running);
    if (running?.settled != false) {
      await cleanup;
      return;
    }
    // Let startup, rebuild or component close finish without waiting for a
    // lost ACK. Keep one retiring owner until its plugin cleanup finishes;
    // a reconnect must not accumulate additional unacknowledged WebViews.
    _retiringStartup = cleanup;
    void clear() {
      if (identical(_retiringStartup, cleanup)) _retiringStartup = null;
    }

    unawaited(
      cleanup.then<void>(
        (_) => clear(),
        onError: (Object error, StackTrace stack) {
          debugPrint('Native runtime startup cleanup failed: $error');
          // Disposal was not confirmed. Require an app restart rather than
          // allocating another headless instance over an unowned view.
        },
      ),
    );
  }

  Future<void> _disposeHost(
    NativeImageControl? images,
    HeadlessInAppWebView? view,
    _NativeRun? running,
  ) async {
    try {
      await images?.close();
    } finally {
      // The plugin ignores dispose() until run() receives its platform ACK.
      var started = true;
      try {
        await running?.acknowledgement;
      } catch (_) {
        // The plugin never marked the view as running. Its dispose is a no-op.
        started = false;
      }
      if (started) await view?.dispose();
    }
  }

  @override
  Future<Object?> control(Map<String, Object?> request) async {
    final message = wire.decodeProtoJson(
      wire.ControlRequest(),
      request,
      maxBytes: wire.controlRequestLimit,
    );
    final command = message.whichCommand();
    if (!{
      wire.RuntimeSlot.RUNTIME_SLOT_FOREGROUND,
      wire.RuntimeSlot.RUNTIME_SLOT_SEARCH,
    }.contains(message.slotId)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Unknown runtime slot',
      );
    }
    if (message.slotId == wire.RuntimeSlot.RUNTIME_SLOT_SEARCH &&
        {
          wire.ControlRequest_Command.acquireImage,
          wire.ControlRequest_Command.cancelImage,
          wire.ControlRequest_Command.releaseImage,
          wire.ControlRequest_Command.closePageSession,
        }.contains(command)) {
      throw const RuntimeException(
        RuntimeErrorCode.unsupportedCapability,
        'Search slot does not own reading images',
      );
    }
    if (_closing && command != wire.ControlRequest_Command.dispose) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native runtime container is closing',
      );
    }
    if ({wire.ControlRequest_Command.acquireImage}.contains(command) &&
        !Platform.isIOS &&
        !Platform.isAndroid) {
      throw const RuntimeException(
        RuntimeErrorCode.unsupportedCapability,
        'Native processed-image files are not implemented on this platform',
      );
    }
    if (_view == null &&
        {
          wire.ControlRequest_Command.cancelImage,
          wire.ControlRequest_Command.releaseImage,
          wire.ControlRequest_Command.closePageSession,
          wire.ControlRequest_Command.closeBuild,
        }.contains(command)) {
      // Cleanup of an expired handle must not create a replacement WebView.
      await _resetting;
      return wire.encodeProtoJson(
        wire.ControlResponse(
          requestId: message.requestId,
          slotId: message.slotId,
          closed:
              {
                wire.ControlRequest_Command.closePageSession,
                wire.ControlRequest_Command.closeBuild,
              }.contains(command)
              ? wire.Closed(closed: true)
              : null,
          released:
              {
                wire.ControlRequest_Command.closePageSession,
                wire.ControlRequest_Command.closeBuild,
              }.contains(command)
              ? null
              : wire.Released(released: true),
        ),
      );
    }
    if (command == wire.ControlRequest_Command.dispose && !_hostReady) {
      return wire.encodeProtoJson(
        wire.ControlResponse(
          requestId: message.requestId,
          slotId: message.slotId,
          completed: wire.Completed(completed: true),
        ),
      );
    }
    await _ensureHost();
    final generation = _generation;
    try {
      final images = _images;
      if (command == wire.ControlRequest_Command.acquireImage) {
        if (images == null) {
          throw const RuntimeException(
            RuntimeErrorCode.unsupportedCapability,
            'This WebView does not support managed image files',
          );
        }
        return wire.encodeProtoJson(
          await images.acquire(message),
          maxBytes: wire.controlJsonLimit,
        );
      }
      if (command == wire.ControlRequest_Command.cancelImage &&
          images != null) {
        return wire.encodeProtoJson(
          await images.cancel(message),
          maxBytes: wire.controlJsonLimit,
        );
      }
      if (command == wire.ControlRequest_Command.releaseImage &&
          images != null) {
        return wire.encodeProtoJson(
          await images.release(message),
          maxBytes: wire.controlJsonLimit,
        );
      }
      if (command == wire.ControlRequest_Command.dispose &&
          message.slotId == wire.RuntimeSlot.RUNTIME_SLOT_FOREGROUND) {
        await images?.close();
      }
      return await _callExistingHost(request, generation);
    } catch (error, stack) {
      final failure = error is PlatformException
          ? RuntimeException(switch (error.code) {
              'cancelled' => RuntimeErrorCode.cancelled,
              'timeout' => RuntimeErrorCode.timeout,
              'unsupported_capability' =>
                RuntimeErrorCode.unsupportedCapability,
              'limit_exceeded' => RuntimeErrorCode.limitExceeded,
              'integrity_error' => RuntimeErrorCode.integrityError,
              'protocol_error' => RuntimeErrorCode.protocolError,
              _ => RuntimeErrorCode.runtimeLost,
            }, error.message ?? 'Native image file operation failed')
          : error is RuntimeException
          ? error
          : const RuntimeException(
              RuntimeErrorCode.runtimeLost,
              'Native runtime operation failed',
            );
      if (failure.code == RuntimeErrorCode.runtimeLost &&
          !_closing &&
          !_disposed &&
          generation == _generation) {
        unawaited(rebuild().catchError((Object _) {}));
      }
      Error.throwWithStackTrace(failure, stack);
    }
  }

  Future<Object?> _callExistingHost(
    Map<String, Object?> request,
    int expectedGeneration,
  ) async {
    if (expectedGeneration != _generation || _controller == null) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native runtime container was replaced',
      );
    }
    final generation = _generation;
    final result = await Future.any([
      _controller!.callAsyncJavaScript(
        functionBody: '''
        const host = window.karuyomiRuntime;
        if (!host) throw new Error('Runtime control module was lost');
        return JSON.stringify(await host.control(request));
      ''',
        arguments: {'request': request},
      ),
      _containerEnded!.future.then<CallAsyncJavaScriptResult?>(
        (_) => throw const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Native runtime container was replaced',
        ),
      ),
    ]);
    if (_disposed || generation != _generation) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native runtime call belongs to an expired container',
      );
    }
    if (result?.error != null) {
      throw RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native runtime control call failed: ${result!.error}',
      );
    }
    if (result?.value is! String) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Native runtime control did not return ProtoJSON text',
      );
    }
    return decodeNativeControlResult(result!.value);
  }

  @override
  Future<void> rebuild() {
    if (_closing || _disposed) return Future<void>.value();
    return _resetting ??= Future<void>.microtask(_reset).whenComplete(() {
      _resetting = null;
    });
  }

  Future<void> _reset() async {
    runtime.containerLost('Native runtime container was rebuilt');
    searchRuntime.containerLost('Native runtime container was rebuilt');
    if (_containerEnded != null && !_containerEnded!.isCompleted) {
      _containerEnded!.complete();
    }
    ++_generation;
    final images = _images;
    final view = _view;
    final running = _viewRunning;
    _images = null;
    _view = null;
    _viewRunning = null;
    _controller = null;
    _opening = null;
    _hostReady = false;
    await _retireHost(images, view, running);
  }

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    coverTransport.close();
    catalogTransport.close();
    if (_disposed) return;
    _closing = true;
    final opening = _opening;
    if (!_hostReady &&
        _containerEnded != null &&
        !_containerEnded!.isCompleted) {
      _containerEnded!.complete();
    }
    try {
      await _resetting;
      await Future.wait([runtime.dispose(), searchRuntime.dispose()]);
    } finally {
      _disposed = true;
      if (_containerEnded != null && !_containerEnded!.isCompleted) {
        _containerEnded!.complete();
      }
      ++_generation;
      final images = _images;
      final view = _view;
      final running = _viewRunning;
      _images = null;
      _view = null;
      _viewRunning = null;
      _controller = null;
      _opening = null;
      _hostReady = false;
      await _retireHost(images, view, running);
      try {
        await opening;
      } catch (_) {
        // The pending caller receives its startup error; disposal owns cleanup.
      }
    }
  }
}

/// Access and the IdP stay inside the app, sharing the runtime's cookie store.
final class _AuthenticationPage extends StatefulWidget {
  const _AuthenticationPage({required this.login, required this.callback});
  final Uri login;
  final Uri callback;

  @override
  State<_AuthenticationPage> createState() => _AuthenticationPageState();
}

final class _AuthenticationPageState extends State<_AuthenticationPage> {
  String? _error;
  bool _completed = false;
  InAppWebViewController? _controller;

  void _complete(InAppWebViewController controller, WebUri? url) {
    // WebView can report intermediate redirects out of order. Only the
    // matching main-frame return signals that this navigation has finished.
    if (_completed ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent != true ||
        url == null ||
        Uri.tryParse(url.toString()) != widget.callback) {
      return;
    }
    _completed = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(middle: const Text('登录')),
    child: SafeArea(
      child: Column(
        children: [
          if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!),
                Wrap(
                  children: [
                    CupertinoButton(
                      onPressed: () {
                        setState(() => _error = null);
                        unawaited(
                          _controller?.loadUrl(
                            urlRequest: URLRequest(
                              url: WebUri(widget.login.toString()),
                            ),
                          ),
                        );
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ],
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.login.toString()),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                sharedCookiesEnabled: true,
                useShouldOverrideUrlLoading: true,
              ),
              onWebViewCreated: (controller) => _controller = controller,
              shouldOverrideUrlLoading: (controller, action) async {
                final target = action.request.url;
                return target == null || target.scheme == 'https'
                    ? NavigationActionPolicy.ALLOW
                    : NavigationActionPolicy.CANCEL;
              },
              onPageCommitVisible: _complete,
              onLoadStop: _complete,
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame == true && mounted) {
                  setState(() => _error = error.description);
                }
              },
            ),
          ),
        ],
      ),
    ),
  );
}
