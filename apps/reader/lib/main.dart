import 'widgets/app_routes.dart';
import 'widgets/adaptive_layout.dart';
import 'widgets/adaptive_detail_layout.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'diagnostics/reader_baseline.dart';
import 'diagnostics/reader_baseline_host.dart';
import 'features/reader/reading_progress_controller.dart';
import 'features/reader/reader_recovery.dart';
import 'features/reader/source_input_dialog.dart';
import 'features/reader/reader_slider_focus.dart'
    if (dart.library.js_interop) 'features/reader/reader_slider_focus_web.dart';
import 'features/reader/chapter_reader_route.dart';
import 'features/browse/catalog_controller.dart';
import 'features/browse/catalog_page.dart';
import 'features/browse/manga_details_destination.dart';
import 'features/history/browsing_history_page.dart';
import 'features/library/library_page.dart';
import 'features/settings/reader_device_settings.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/settings_widgets.dart';
import 'navigation/app_location.dart';
import 'navigation/app_navigation.dart';
import 'navigation/addressed_pages.dart';
import 'runtime/platform_runtime.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final preferences = SharedPreferencesAsync();
  runApp(
    ProviderScope(
      overrides: [readerDeviceStorageProvider.overrideWithValue(preferences)],
      child: KaruyomiApp(
        connectionPreferences: kIsWeb ? null : preferences,
        appearancePreferences: preferences,
      ),
    ),
  );
}

class const KaruyomiApp({
  super.key,
  final PlatformRuntime? platform,
  final PlatformRuntime Function(Uri? origin)? platformFactory,
  final SharedPreferencesAsync? connectionPreferences,
  final SharedPreferencesAsync? appearancePreferences,
}) extends StatefulWidget {
  @override
  State<KaruyomiApp> createState() => _KaruyomiAppState();
}

class _KaruyomiAppState extends State<KaruyomiApp> {
  static const _appearanceKey = 'device_appearance';
  AppAppearance _appearance = AppAppearance.system;
  AppAppearance? _failedAppearance;
  bool _restoringAppearance = false;
  bool _savingAppearance = false;
  late final VoidCallback _stopPreservingSliderFocus;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          redirect: (_, state) => _tabAddress(state.uri, AppTab.library),
        ),
        GoRoute(
          path: '/browse',
          redirect: (_, state) => _tabAddress(state.uri, AppTab.browse),
        ),
        GoRoute(
          path: '/settings',
          redirect: (_, state) => _tabAddress(state.uri, AppTab.settings),
        ),
        GoRoute(
          path: '/app',
          redirect: (_, state) => _tabAddress(state.uri, AppTab.library),
        ),
        GoRoute(path: '/app/:tab', pageBuilder: _appPage),
        GoRoute(path: '/app/:tab/:subpath(.+)', pageBuilder: _appPage),
      ],
      errorPageBuilder: _unavailableRoute,
    );
    _stopPreservingSliderFocus = preserveReaderSliderFocus();
    if (widget.appearancePreferences case final preferences?) {
      _restoringAppearance = true;
      unawaited(_restoreAppearance(preferences));
    }
  }

  String _tabAddress(Uri incoming, AppTab tab) =>
      incoming.replace(path: AppLocation(tab).path).toString();

  Future<void> _restoreAppearance(SharedPreferencesAsync preferences) async {
    String? stored;
    try {
      stored = await preferences
          .getString(_appearanceKey)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // A failed read still permits following the platform's appearance.
    }
    if (!mounted) return;
    setState(() {
      _appearance =
          AppAppearance.values.asNameMap()[stored] ?? AppAppearance.system;
      _restoringAppearance = false;
    });
  }

  Future<void> _saveAppearance(AppAppearance value) async {
    if (_restoringAppearance || _savingAppearance || value == _appearance) {
      return;
    }
    setState(() {
      _savingAppearance = true;
      _failedAppearance = null;
    });
    AppAppearance? failed;
    try {
      await widget.appearancePreferences?.setString(_appearanceKey, value.name);
    } catch (_) {
      failed = value;
    }
    if (!mounted) return;
    setState(() {
      if (failed == null) _appearance = value;
      _failedAppearance = failed;
      _savingAppearance = false;
    });
  }

  @override
  void dispose() {
    _router.dispose();
    _stopPreservingSliderFocus();
    super.dispose();
  }

  Page<void> _appPage(BuildContext context, GoRouterState state) {
    final location = AppLocation.parse(state.uri);
    if (location == null) return _unavailableRoute(context, state);
    return AppPage<void>(
      key: const ValueKey('app-shell'),
      child: Builder(
        builder: (context) => AppShell(
          location: location,
          previousPath: state.extra is String ? state.extra as String : null,
          appearance: context
              .dependOnInheritedWidgetOfExactType<_Appearance>()!
              .settings,
          platform: widget.platform,
          platformFactory: widget.platformFactory,
          connectionPreferences: widget.connectionPreferences,
        ),
      ),
    );
  }

  Page<void> _unavailableRoute(BuildContext context, GoRouterState state) =>
      AppPage<void>(
        key: state.pageKey,
        child: Builder(
          builder: (context) => CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(middle: Text('页面不存在')),
            child: Center(
              child: CupertinoButton(
                onPressed: () =>
                    context.go(const AppLocation(AppTab.library).path),
                child: const Text('前往书架'),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => CupertinoApp.router(
    routerConfig: _router,
    title: 'Karuyomi',
    // Web's default Enter intent is ButtonActivateIntent; CupertinoButton
    // handles ActivateIntent. Keep the other platform shortcuts unchanged.
    shortcuts: {
      ...WidgetsApp.defaultShortcuts,
      const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
      const SingleActivator(LogicalKeyboardKey.numpadEnter):
          const ActivateIntent(),
    },
    // Sheet transitions expose the area outside the transformed page. Paint
    // that area in the confirmed appearance rather than the host's background.
    builder: (context, child) => _Appearance(
      settings: DeviceAppearanceSettings(
        value: _appearance,
        restoring: _restoringAppearance,
        saving: _savingAppearance,
        failed: _failedAppearance,
        onChanged: (value) => unawaited(_saveAppearance(value)),
      ),
      child: ColoredBox(
        color: CupertinoTheme.of(context).scaffoldBackgroundColor,
        child: readerBaselineEnabled
            ? ReaderBaselineHost(child: child!)
            : child!,
      ),
    ),
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalCupertinoLocalizations.delegates,
    theme: readerAppTheme(_appearance.brightness),
  );
}

class const _Appearance({required final Widget settings, required super.child})
    extends InheritedWidget {
  @override
  bool updateShouldNotify(_Appearance oldWidget) =>
      settings != oldWidget.settings;
}

class const AppShell({
  super.key,
  required final AppLocation location,
  final String? previousPath,
  required final Widget appearance,
  final PlatformRuntime? platform,
  final PlatformRuntime Function(Uri? origin)? platformFactory,
  final SharedPreferencesAsync? connectionPreferences,
}) extends StatefulHookConsumerWidget {
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

final class _ReaderPageRequest {
  _ReaderPageRequest(this.location, [this.builder]);

  AppLocation location;
  final ReaderPageBuilder? builder;
  final _closed = Completer<void>();
  bool _attached = false;
  Future<void> get closed => _closed.future;

  void attach(Future<void> completion) {
    _attached = true;
    unawaited(completion.then((_) => _close()));
  }

  void retire() {
    if (!_attached) _close();
  }

  void _close() {
    if (!_closed.isCompleted) _closed.complete();
  }
}

class _AppShellState extends ConsumerState<AppShell> {
  AppTab get _selected => widget.location.tab;
  PlatformRuntime? _platform;
  CatalogController? _catalog;
  SettingsController? get _settings => _catalog == null
      ? null
      : ref.read(
          settingsControllerProvider(_catalog!, _catalog!.settings).notifier,
        );
  String? _configurationError;
  String? _notice;
  Map<String, Object?>? _pendingContinuation;
  final _retiredProgress = <ReadingProgressController>{};
  bool _retryingProgress = false;
  bool _changingService = false;
  bool _restoringOrigin = false;
  final _connectionStatusKey = GlobalKey();
  String? _originPersistenceError;
  static const _defaultOrigin = String.fromEnvironment('APP_ORIGIN');
  static const _originKey = 'native_service_origin';
  static const _sidebarWidth = 176.0;
  late TextEditingController _originField;
  final _tabFocusNodes = {
    for (final destination in AppTab.values)
      destination: FocusNode(debugLabel: destination.label),
  };
  final _pages = GlobalKey<NavigatorState>();
  ({SourceLocation source, CatalogBuild build})? _sourceRequest;
  ({
    AppLocation location,
    AdaptiveDetailBuilder builder,
    Completer<void> closed,
  })?
  _mangaRequest;
  AppLocation? _shownDetail;
  _ReaderPageRequest? _readerPage;
  _ReaderPageRequest? _pendingReader;
  bool _waitingForBrowserBack = false;

  @override
  void initState() {
    super.initState();
    _syncLocation();
  }

  void _select(AppTab destination) {
    if (destination == AppTab.settings && _selected == AppTab.settings) {
      unawaited(_settings?.refresh());
    }
    _navigate(
      AppLocation(
        destination,
        setting: destination == AppTab.settings && _catalog == null
            ? SettingsSection.connection
            : null,
      ),
    );
  }

  @override
  void didUpdateWidget(AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.location != oldWidget.location) _syncLocation();
    if (oldWidget.location.tab == _selected) return;
    if (_selected != AppTab.settings) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selected == AppTab.settings) {
        unawaited(_settings?.refresh());
      }
    });
  }

  void _syncLocation() {
    final location = widget.location;
    final detail = location.chapterKey == null ? location : location.parent;
    if (location.chapterKey == null || _shownDetail != detail) {
      _shownDetail = location.chapterKey == null && location.mangaKey != null
          ? location
          : null;
    }
    if (_mangaRequest case final request? when request.location != detail) {
      _mangaRequest = null;
      request.closed.complete();
    }
    if (_sourceRequest?.source != location.source) _sourceRequest = null;
    if (_readerPage?.location != location) {
      _readerPage?.retire();
      _readerPage = location.chapterKey == null
          ? null
          : _pendingReader?.location == location
          ? _pendingReader
          : _ReaderPageRequest(location);
    }
    if (_pendingReader != _readerPage) _pendingReader?.retire();
    _pendingReader = null;
  }

  void _openSource(CatalogBuild build, wire.CatalogSource source) {
    final target = (packageName: build.packageName, sourceId: source.id);
    _sourceRequest = (source: target, build: build);
    final item = widget.location.extension;
    final container =
        item == null ||
            (item.packageName == target.packageName &&
                item.catalogKey == catalogLocationKey(build.catalog))
        ? widget.location
        : AppLocation(_selected);
    _navigate(container.withSource(target));
  }

  Future<void> _openManga(String mangaKey, AdaptiveDetailBuilder builder) {
    final location = widget.location.withManga(mangaKey);
    if (location == widget.location) return Future.value();
    _mangaRequest?.closed.complete();
    final closed = Completer<void>();
    _mangaRequest = (location: location, builder: builder, closed: closed);
    _navigate(location);
    return closed.future;
  }

  Future<void> _openReader(
    String mangaKey,
    String chapterKey,
    ReaderPageBuilder builder,
  ) {
    final location = widget.location.withChapter(mangaKey, chapterKey);
    if (location == widget.location) return Future.value();
    _pendingReader?.retire();
    final request = _pendingReader = _ReaderPageRequest(location, builder);
    _navigate(location);
    return request.closed;
  }

  void _navigate(AppLocation location) {
    if (widget.location != location) {
      context.go(_addressWithQuery(location), extra: widget.location.path);
    }
  }

  String _addressWithQuery(AppLocation location) =>
      GoRouter.of(context).routeInformationProvider.value.uri
          .replace(path: location.path)
          .toString();

  void _replaceLocation(AppLocation location) => Router.neglect(
    context,
    () => context.go(_addressWithQuery(location), extra: widget.previousPath),
  );

  void _backFromAddress(AppLocation location) {
    if (!mounted || widget.location != location || _waitingForBrowserBack) {
      return;
    }
    final parent = location.parent;
    if (kIsWeb && widget.previousPath == parent.path) {
      _waitingForBrowserBack = true;
      unawaited(() async {
        try {
          await PathUrlStrategy().go(-1).timeout(const Duration(seconds: 2));
        } on TimeoutException {
          if (mounted && widget.location == location) _replaceLocation(parent);
        } finally {
          _waitingForBrowserBack = false;
        }
      }());
    } else {
      _replaceLocation(parent);
    }
  }

  void _updateChapterAddress(_ReaderPageRequest reader, String chapter) {
    final location = widget.location;
    if (!mounted ||
        !identical(_readerPage, reader) ||
        reader.location != location) {
      return;
    }
    final next = location.withChapter(location.mangaKey!, chapter);
    if (next == location) return;
    reader.location = next;
    _replaceLocation(next);
  }

  void _tapTab(AppTab destination) {
    final focusedTab = _tabFocusNodes.values
        .where((node) => node.hasFocus)
        .firstOrNull;
    if (focusedTab != null) {
      if (FocusManager.instance.highlightMode ==
          FocusHighlightMode.traditional) {
        _tabFocusNodes[destination]!.requestFocus();
      } else {
        focusedTab.unfocus();
      }
    }
    _select(destination);
  }

  void _initialize() {
    final preferences = widget.connectionPreferences;
    if (kIsWeb || widget.platform != null || preferences == null) {
      _configure(widget.platform);
    } else {
      _restoringOrigin = true;
      unawaited(_restoreOrigin(preferences));
    }
  }

  Future<void> _restoreOrigin(SharedPreferencesAsync preferences) async {
    String? stored;
    try {
      stored = await preferences
          .getString(_originKey)
          .timeout(const Duration(seconds: 3));
    } on Exception {
      // A missing platform preference must not prevent connecting manually.
    }
    if (!mounted) return;
    setState(() {
      _restoringOrigin = false;
      if (stored != null && stored.trim().isNotEmpty) {
        _originField.text = stored;
        _configure();
        if (_catalog != null) return;
        _originField.text = _defaultOrigin;
      }
      _configure();
    });
  }

  Future<void> _rememberOrigin(Uri origin) async {
    final preferences = widget.connectionPreferences;
    if (kIsWeb || preferences == null) return;
    try {
      await preferences.setString(_originKey, origin.origin);
    } on Exception {
      if (mounted) {
        setState(() => _originPersistenceError = '未能在本机记住服务地址，下次打开可能需要重新填写。');
      }
    }
  }

  PlatformRuntime _createPlatform() {
    final configured = _originField.text.trim();
    return (widget.platformFactory ??
        ((origin) => createPlatformRuntime(origin: origin)))(
      configured.isEmpty ? null : Uri.parse(configured),
    );
  }

  void _configurationFailed(Object error, {bool initializing = false}) {
    _configurationError = switch (error) {
      ArgumentError() || FormatException()
          when initializing && _originField.text.trim().isEmpty =>
        null,
      ArgumentError() || FormatException() => '请先在设置中填写服务的 HTTPS 地址。',
      _ => '服务初始化未完成，请在设置中重新连接。',
    };
  }

  void _configure([PlatformRuntime? injected]) {
    try {
      _platform = injected ?? _createPlatform();
      _originField.text = _platform!.origin.toString();
      _catalog = CatalogController(
        api: _platform!,
        runtime: _platform!.runtime,
        rebuildRuntime: _platform!.rebuild,
        deploymentOrigin: _platform!.origin,
      );
      _configurationError = null;
      final continuation = _platform!.takePendingAuthentication();
      if (continuation?['pending'] case final Map pending) {
        _pendingContinuation = Map<String, Object?>.from(pending);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final tab = AppTab.values.asNameMap()[_pendingContinuation?['tab']];
        if (widget.location == const AppLocation(AppTab.library)) {
          final saved = _pendingContinuation?['location'];
          final uri = saved is String ? Uri.tryParse(saved) : null;
          final destination = uri == null ? null : AppLocation.parse(uri);
          if (destination != null) {
            _replaceLocation(destination);
          } else if (tab != null) {
            _replaceLocation(AppLocation(tab));
          }
        }
        unawaited(_connect(_pendingContinuation));
      });
    } catch (error) {
      _configurationFailed(error, initializing: true);
    }
  }

  Future<void> _connect([Map<String, Object?>? continuation]) async {
    final controller = _catalog;
    if (controller == null) {
      _select(AppTab.settings);
      return;
    }
    await controller.connect();
    if (mounted &&
        identical(controller, _catalog) &&
        controller.status == ServiceStatus.ready) {
      for (final client in _retiredProgress.toList()) {
        if (!controller.adoptReadingProgress(client)) continue;
        _retiredProgress.remove(client);
      }
      setState(() {});
    }
    if (!mounted ||
        !identical(controller, _catalog) ||
        controller.status != ServiceStatus.ready ||
        continuation == null) {
      return;
    }
    _pendingContinuation = null;
    if (widget.location.chapterKey != null) return;
    if (continuation['reader'] case final Object reader) {
      try {
        final recovery = ReaderRecoveryContext.fromJson(reader);
        final recovered = await recoverReader(
          controller,
          recovery,
          isCurrent: () => mounted && identical(controller, _catalog),
          onInput: (prompt, ended) async {
            if (!mounted || !identical(controller, _catalog)) return null;
            return showSourceInputDialog(
              context,
              sourceName: controller.activeSource?.name ?? '漫画源',
              prompt: prompt,
              operationEnded: ended,
            );
          },
        );
        if (recovered == null) {
          if (!mounted || !identical(controller, _catalog)) return;
          throw StateError(controller.error ?? '阅读恢复未完成，请重新选择章节');
        }
        if (!mounted || !identical(controller, _catalog)) {
          await recovered.opened.provider.close();
          return;
        }
        try {
          await _openReader(
            recovered.sequence.mangaKey,
            recovered.chapter.key,
            (_, onChapterChanged) => ChapterReaderRoute(
              catalog: controller,
              manga: recovered.manga,
              source: recovered.source,
              sequence: recovered.sequence,
              initialChapter: recovered.chapter,
              initialOpened: recovered.opened,
              initialPosition: recovered.position,
              initialOrder: recovery.order,
              initialMode: recovery.mode,
              initialDoublePage: recovery.doublePage,
              onAuthenticate: _authenticateReader,
              onChapterChanged: onChapterChanged,
            ),
          );
        } finally {
          await controller.closeChapter(recovered.opened);
        }
      } catch (error) {
        if (mounted) {
          setState(
            () => _notice = error is StateError
                ? error.message.toString()
                : '阅读恢复状态无效，请重新选择章节',
          );
        }
      }
      return;
    }
    if (widget.location.source != null || widget.location.mangaKey != null) {
      return;
    }
    final packageName = continuation['packageName'];
    if (packageName is! String) return;
    final build = await controller.openSelectedBuild(
      packageName,
      shouldContinue: () => mounted && identical(controller, _catalog),
    );
    if (!mounted ||
        !identical(controller, _catalog) ||
        build == null ||
        controller.activeBuild?.catalog != build.catalog ||
        controller.activeBuild?.id != build.id) {
      return;
    }
    final sourceId = continuation['sourceId'];
    final sources = controller.session?.sources.where(
      (source) => source.id == sourceId,
    );
    if (sources == null || sources.isEmpty) return;
    await controller.selectSource(sources.first);
    final query = continuation['query'];
    if (query is String && query.isNotEmpty && controller.session != null) {
      await controller.loadMangas(search: query);
    }
  }

  Future<void> _authenticate() async {
    final platform = _platform;
    if (platform == null) {
      _select(AppTab.settings);
      return;
    }
    try {
      if (!mounted) return;
      final authenticated = await platform.authenticate(
        context,
        pending: {
          ...?_pendingContinuation,
          'tab': _selected.name,
          'location': widget.location.path,
          if (_catalog?.lastPackageName != null)
            'packageName': _catalog!.lastPackageName,
          if (_catalog?.lastSourceId != null)
            'sourceId': _catalog!.lastSourceId,
          if (_catalog?.query.isNotEmpty == true) 'query': _catalog!.query,
        },
      );
      if (mounted && authenticated) {
        final pending = platform.takePendingAuthentication()?['pending'];
        await _connect(
          pending is Map ? Map<String, Object?>.from(pending) : null,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _notice = error is StateError
              ? error.message.toString()
              : '登录未完成，请重试。',
        );
      }
    }
  }

  Future<bool> _authenticateReader(ReaderRecoveryContext recovery) async {
    final platform = _platform;
    if (platform == null || recovery.origin != platform.origin.origin) {
      throw StateError('服务已改变，请返回浏览');
    }
    if (!mounted) return false;
    // Authentication retains this document and its unconfirmed session drafts.
    final authenticated = await platform.authenticate(
      context,
      pending: {
        'tab': AppTab.browse.name,
        'location': widget.location.path,
        'reader': recovery.toJson(),
      },
    );
    platform.takePendingAuthentication();
    return authenticated;
  }

  void _revealConnectionStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final status = _connectionStatusKey.currentContext;
      if (!mounted ||
          status == null ||
          ModalRoute.of(status)?.isCurrent != true) {
        return;
      }
      unawaited(
        Scrollable.ensureVisible(
          status,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ),
      );
    });
  }

  Future<void> _changeService() async {
    if (_changingService || _restoringOrigin) return;
    setState(() {
      _changingService = true;
      _originPersistenceError = null;
    });
    try {
      final platform = _platform;
      final requested = Uri.tryParse(_originField.text.trim());
      final sameService =
          platform != null &&
          (requested == platform.origin.replace(path: '') ||
              requested == platform.origin.replace(path: '/'));
      // Reconnecting the same service keeps identity-bound pending commands.
      // Bootstrap still verifies the current subject before they can be retried.
      if (platform != null && (kIsWeb || sameService)) {
        _revealConnectionStatus();
        await platform.rebuild();
        if (mounted) {
          setState(() {
            _configurationError = null;
            _originField.text = platform.origin.toString();
          });
          await _rememberOrigin(platform.origin);
          if (!mounted) return;
          await _connect();
        }
        return;
      }
      // Validate with the real platform constructor before retiring a session.
      final PlatformRuntime candidate;
      try {
        candidate = _createPlatform();
      } catch (error) {
        if (mounted) setState(() => _configurationFailed(error));
        return;
      }
      var adopted = false;
      try {
        final old = _platform;
        final oldCatalog = _catalog;
        if (oldCatalog != null) {
          await oldCatalog.flushReadingProgress();
          if (!mounted) return;
          _retiredProgress.addAll(oldCatalog.takeUnsavedReadingProgress());
          oldCatalog.dispose();
          _catalog = null;
          await oldCatalog.closeReadingProgress();
        }
        if (!mounted) return;
        _catalog = null;
        _platform = null;
        if (old != null) await old.dispose();
        if (!mounted) return;
        setState(() {
          adopted = true;
          _configure(candidate);
        });
        if (_catalog != null) await _rememberOrigin(candidate.origin);
      } finally {
        if (!adopted) await candidate.dispose();
      }
    } finally {
      if (mounted) setState(() => _changingService = false);
    }
  }

  Future<void> _retryProgress() async {
    if (_retryingProgress) return;
    setState(() => _retryingProgress = true);
    await _catalog?.flushReadingProgress(explicitRetry: true);
    for (final client in _retiredProgress.toList()) {
      if (!await client.flush()) continue;
      if (_retiredProgress.remove(client)) client.dispose();
    }
    if (mounted) setState(() => _retryingProgress = false);
  }

  Widget _destination(Widget child) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(middle: Text(_selected.label)),
    child: SafeArea(child: child),
  );

  AdaptiveDetailSelection? _addressedDetail() {
    final location = _shownDetail;
    if (location == null) return null;
    final request = _mangaRequest;
    return (
      token: location,
      builder: request?.location == location
          ? request!.builder
          : (context, close) => _withService(
              title: '作品详情',
              onBack: close ?? () => _backFromAddress(location),
              builder: (catalog) => buildCatalogMangaDetails(
                title: '作品详情',
                catalog: catalog,
                onClose: close,
                onAuthenticateReader: _authenticateReader,
                load: (isCurrent) async => (await catalog.openMangaLocation(
                  location.mangaKey!,
                  packageName: location.source?.packageName,
                  sourceId: location.source?.sourceId,
                  shouldContinue: isCurrent,
                ))?.details,
              ),
            ),
    );
  }

  void _closeDetail() {
    if (widget.location.chapterKey == null) {
      _backFromAddress(widget.location);
    }
  }

  Widget _withService({
    required String title,
    required VoidCallback onBack,
    required Widget Function(CatalogController) builder,
  }) => AddressedService(
    catalog: _catalog,
    title: title,
    onConnect: () => unawaited(_connect()),
    onAuthenticate: () => unawaited(_authenticate()),
    onBack: onBack,
    builder: builder,
  );

  Widget _page({required bool singleColumn}) => switch (_selected) {
    AppTab.library => AdaptiveDetailLayout(
      owner: _catalog?.library,
      detail: _addressedDetail(),
      onCloseDetail: _closeDetail,
      singleColumn: singleColumn,
      child: _destination(
        LibraryPage(
          controller: _catalog,
          onBrowse: () => _select(AppTab.browse),
          onConnect: () => unawaited(_connect()),
          onAuthenticate: () => unawaited(_authenticate()),
          onAuthenticateReader: _authenticateReader,
        ),
      ),
    ),
    AppTab.browse || AppTab.extensions => AdaptiveDetailLayout(
      detail: widget.location.source == null && widget.location.panel == null
          ? _addressedDetail()
          : null,
      onCloseDetail: _closeDetail,
      singleColumn: singleColumn,
      child: _destination(
        CatalogPage(
          key: ValueKey(_selected),
          controller: _catalog,
          showExtensions: _selected == AppTab.extensions,
          onManageExtensions: () => _select(AppTab.extensions),
          onConnect: () => unawaited(_connect()),
          onAuthenticate: () => unawaited(_authenticate()),
          onAuthenticateReader: _authenticateReader,
          configurationError: _configurationError,
        ),
      ),
    ),
    AppTab.history => AdaptiveDetailLayout(
      owner: _catalog?.library?.client,
      detail: _addressedDetail(),
      onCloseDetail: _closeDetail,
      singleColumn: singleColumn,
      child: _destination(
        BrowsingHistoryPage(
          catalog: _catalog,
          onConnect: () => unawaited(_connect()),
          onAuthenticate: () => unawaited(_authenticate()),
          onAuthenticateReader: _authenticateReader,
        ),
      ),
    ),
    AppTab.settings => GlobalSettingsPanel(
      catalog: _catalog,
      connection: _connectionSettings(),
      appearance: widget.appearance,
      addressedSection: widget.location.setting,
      onSectionChanged: (section) {
        if (section == null) {
          _backFromAddress(widget.location);
        } else {
          _navigate(AppLocation(AppTab.settings, setting: section));
        }
      },
    ),
  };

  Widget _connectionSettings() {
    final controller = _catalog;
    final connecting =
        _changingService || controller?.status == ServiceStatus.connecting;
    final confirmed =
        !_restoringOrigin &&
        !connecting &&
        controller?.status == ServiceStatus.ready;
    final canConnect =
        controller?.busy != true && !_changingService && !_restoringOrigin;
    final hasService = _platform != null;
    final gap = hasService ? 12.0 : 8.0;
    final connect = canConnect ? _changeService : null;
    final status = _restoringOrigin
        ? '正在读取服务地址'
        : connecting
        ? '正在连接服务'
        : switch (controller?.status) {
            ServiceStatus.ready => '已连接，身份已确认',
            ServiceStatus.loginRequired => '需要重新登录',
            ServiceStatus.denied => '访问被拒绝',
            ServiceStatus.failed => '连接未完成',
            _ => '尚未连接',
          };
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: '服务地址',
          child: CupertinoTextField(
            key: const ValueKey('service-origin'),
            controller: _originField,
            readOnly: kIsWeb || _restoringOrigin || connecting,
            autofillHints: null,
            keyboardType: TextInputType.url,
            autocorrect: false,
            placeholder: 'https://你的服务域名',
            placeholderStyle: TextStyle(
              color: AppColors.secondaryLabel.resolveFrom(context),
            ),
            decoration: BoxDecoration(
              color: AppColors.groupedSurface.resolveFrom(context),
              border: Border.all(
                color: AppColors.separator.resolveFrom(context),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        SizedBox(height: gap),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Semantics(
              enabled: canConnect,
              child: hasService
                  ? CupertinoButton(
                      onPressed: connect,
                      child: const Text('连接服务'),
                    )
                  : CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      onPressed: connect,
                      child: const Text('连接服务'),
                    ),
            ),
            if (hasService)
              Semantics(
                enabled: canConnect,
                child: CupertinoButton.filled(
                  foregroundColor: canConnect
                      ? null
                      : CupertinoColors.tertiaryLabel.resolveFrom(context),
                  onPressed: canConnect ? _authenticate : null,
                  child: const Text('登录'),
                ),
              ),
          ],
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CupertinoFormSection.insetGrouped(
          margin: EdgeInsets.zero,
          children: [
            if (_platform != null)
              CupertinoFormRow(
                prefix: const Text('服务'),
                child: Text(
                  _changingService
                      ? _originField.text.trim()
                      : _platform!.origin.origin,
                ),
              ),
            CupertinoFormRow(
              key: _connectionStatusKey,
              prefix: const Text('状态'),
              child: Semantics(
                liveRegion: true,
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_restoringOrigin || connecting)
                      const CupertinoActivityIndicator(),
                    Text(status),
                  ],
                ),
              ),
            ),
            if (confirmed && controller?.email != null)
              CupertinoFormRow(
                prefix: const Text('账号'),
                child: Text(controller!.email!),
              ),
          ],
        ),
        SizedBox(height: gap),
        form,
        if (_configurationError case final error?)
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              style: TextStyle(
                color: AppColors.error.resolveFrom(context),
                fontSize: hasService ? null : 13,
              ),
            ),
          ),
        if (_originPersistenceError != null)
          Text(
            _originPersistenceError!,
            style: TextStyle(color: AppColors.error.resolveFrom(context)),
          ),
        if (controller?.error != null)
          Text(
            controller!.error!,
            style: TextStyle(color: AppColors.error.resolveFrom(context)),
          ),
        if (_retiredProgress.isNotEmpty ||
            controller?.hasUnsavedReadingProgress == true) ...[
          const SizedBox(height: 12),
          const Text('部分阅读进度尚未保存；原服务和身份的记录仍保留，可继续连接服务。'),
          CupertinoButton(
            onPressed: _retryingProgress ? null : _retryProgress,
            child: const Text('重试保存所有进度'),
          ),
        ],
      ],
    );
  }

  BottomNavigationBarItem _navigationItem(AppTab destination) =>
      BottomNavigationBarItem(
        label: destination.label,
        // The selected item gains theme wrappers in CupertinoTabBar. Keep the
        // focus node attached to the same destination across those changes.
        icon: CupertinoFocusHalo.withRoundedSuperellipse(
          key: GlobalObjectKey(_tabFocusNodes[destination]!),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: FocusableActionDetector(
            focusNode: _tabFocusNodes[destination],
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _select(destination);
                  return null;
                },
              ),
            },
            child: SizedBox(
              width: kMinInteractiveDimensionCupertino,
              height: double.infinity,
              child: Center(
                child: Icon(
                  destination.icon,
                  key: ValueKey(('app-destination', destination.name)),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _navigationBar() => LayoutBuilder(
    builder: (context, constraints) {
      final bar = CupertinoTabBar(
        key: const ValueKey('app-navigation'),
        backgroundColor: AppColors.toolbar.resolveFrom(context),
        inactiveColor: AppColors.secondaryLabel.resolveFrom(context),
        currentIndex: _selected.index,
        onTap: (index) => _tapTab(AppTab.values[index]),
        items: AppTab.values.map(_navigationItem).toList(),
      );
      final labelStyle = CupertinoTheme.of(context).textTheme.tabLabelTextStyle;
      final textScaler = MediaQuery.textScalerOf(context);
      final effectiveStyle = labelStyle.copyWith(
        fontWeight: MediaQuery.boldTextOf(context) ? FontWeight.bold : null,
        height: MediaQuery.maybeLineHeightScaleFactorOverrideOf(context),
        letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
        wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
      );
      final fontSize = labelStyle.fontSize!;
      if (effectiveStyle == labelStyle &&
          textScaler.scale(fontSize) <= fontSize) {
        return bar;
      }
      final painter = TextPainter(
        textDirection: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
        textHeightBehavior: DefaultTextHeightBehavior.maybeOf(context),
      );
      final labelWidth = constraints.maxWidth / AppTab.values.length;

      double largestLabelHeight(TextStyle style, TextScaler scaler) {
        painter.textScaler = scaler;
        var height = 0.0;
        for (final destination in AppTab.values) {
          painter.text = TextSpan(text: destination.label, style: style);
          painter.layout(maxWidth: labelWidth);
          height = math.max(height, painter.height);
        }
        return height;
      }

      // Keep the same icon space as the default Cupertino bar when labels grow.
      try {
        final extra =
            largestLabelHeight(effectiveStyle, textScaler) -
            largestLabelHeight(labelStyle, TextScaler.noScaling);
        return bar.copyWith(height: bar.height + math.max(0.0, extra));
      } finally {
        painter.dispose();
      }
    },
  );

  Widget _sidebar() => SizedBox(
    key: const ValueKey('app-navigation'),
    width: _sidebarWidth,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.toolbar.resolveFrom(context),
        border: BorderDirectional(
          end: BorderSide(color: AppColors.separator.resolveFrom(context)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        primary: false,
        children: [
          for (final destination in AppTab.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: CupertinoFocusHalo.withRoundedSuperellipse(
                key: GlobalObjectKey(_tabFocusNodes[destination]!),
                borderRadius: const BorderRadius.all(Radius.circular(10)),
                child: Semantics(
                  selected: _selected == destination,
                  child: CupertinoButton(
                    key: ValueKey(('app-destination', destination.name)),
                    focusNode: _tabFocusNodes[destination],
                    onPressed: () => _tapTab(destination),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    color: _selected == destination
                        ? AppColors.selection.resolveFrom(context)
                        : null,
                    foregroundColor: _selected == destination
                        ? AppColors.accent.resolveFrom(context)
                        : AppColors.label.resolveFrom(context),
                    borderRadius: BorderRadius.circular(10),
                    child: Row(
                      children: [
                        Icon(destination.icon, size: 22),
                        const SizedBox(width: 10),
                        Expanded(child: Text(destination.label)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    _originField = useTextEditingController(text: _defaultOrigin);
    useEffect(() {
      _initialize();
      return null;
    }, const []);
    useOnAppLifecycleStateChange((_, state) {
      if (state == AppLifecycleState.resumed) unawaited(_settings?.refresh());
    });
    final catalog = useListenable(_catalog);
    if (catalog != null) {
      ref.watch(settingsControllerProvider(catalog, catalog.settings).notifier);
    }
    final location = widget.location;
    final reader = _readerPage;
    final item = location.extension;
    final panel = location.panel;
    return AppNavigation(
      location: location,
      navigate: _navigate,
      openSource: _openSource,
      openManga: _openManga,
      openReader: _openReader,
      child: NavigatorPopHandler<void>(
        onPopWithResult: (_) => unawaited(_pages.currentState?.maybePop()),
        child: Navigator(
          key: _pages,
          pages: [
            AppPage<void>(key: const ValueKey('tabs'), child: _homeFrame()),
            if (item != null)
              AppPage<void>(
                key: ValueKey<Object?>(item),
                child: _extensionAddress(
                  AppLocation(AppTab.extensions, extension: item),
                ),
              ),
            if (panel != null)
              AppPage<void>(
                key: ValueKey((panel, item)),
                child: panel == AppPanel.search
                    ? _withService(
                        title: '跨源搜索',
                        onBack: () => _backFromAddress(location),
                        builder: (controller) => AddressedSearchPage(
                          catalog: controller,
                          detail: _addressedDetail(),
                          onBack: () => _backFromAddress(location),
                          onCloseDetail: _closeDetail,
                          onManageExtensions: () => _select(AppTab.extensions),
                          onAuthenticateReader: _authenticateReader,
                        ),
                      )
                    : _extensionAddress(location),
              ),
            if (location.source case final target?)
              AppPage<void>(
                key: _sourcePageKey(location),
                child: _withService(
                  title: '漫画源',
                  onBack: () => _backFromAddress(location),
                  builder: (controller) => AddressedSourcePage(
                    catalog: controller,
                    target: target,
                    selectedBuild: _sourceRequest?.build,
                    catalogKey: item?.catalogKey,
                    detail: _addressedDetail(),
                    loadListing: location.chapterKey == null,
                    onBack: () => _backFromAddress(location),
                    onCloseDetail: _closeDetail,
                    onAuthenticate: () => unawaited(_authenticate()),
                    onAuthenticateReader: _authenticateReader,
                  ),
                ),
              ),
            if (reader != null)
              AppPage<void>(
                key: ObjectKey(reader),
                onCompleted: reader.attach,
                child: Builder(
                  builder: (context) {
                    void changed(String chapter) =>
                        _updateChapterAddress(reader, chapter);
                    final builder = reader.builder;
                    return builder != null
                        ? builder(context, changed)
                        : _withService(
                            title: '阅读',
                            onBack: () => _backFromAddress(location),
                            builder: (controller) => AddressedReaderPage(
                              key: ObjectKey(controller),
                              catalog: controller,
                              location: location,
                              onBack: () => _backFromAddress(location),
                              onAuthenticate: () => unawaited(_authenticate()),
                              onAuthenticateReader: _authenticateReader,
                              onChapterChanged: changed,
                            ),
                          );
                  },
                ),
              ),
          ],
          onDidRemovePage: (page) {
            final current = widget.location;
            final currentKey = switch (current) {
              AppLocation(chapterKey: final String _) => ObjectKey(_readerPage),
              AppLocation(source: final SourceLocation _) => _sourcePageKey(
                current,
              ),
              AppLocation(panel: final AppPanel panel) => ValueKey((
                panel,
                current.extension,
              )),
              AppLocation(extension: final ExtensionLocation item) =>
                ValueKey<Object?>(item),
              _ => null,
            };
            if (currentKey != null && page.key == currentKey) {
              _backFromAddress(current);
            }
          },
        ),
      ),
    );
  }

  LocalKey _sourcePageKey(AppLocation location) =>
      ValueKey((location.tab, location.extension, location.source));

  Widget _extensionAddress(AppLocation location) => _withService(
    title: '扩展',
    onBack: () => _backFromAddress(location),
    builder: (controller) {
      final repository = controller.settings;
      if (repository == null) {
        return AddressStatusPage(
          title: '扩展',
          message: '登录后打开此链接',
          onBack: () => _backFromAddress(location),
          action: (label: '登录', onPressed: () => unawaited(_authenticate())),
        );
      }
      return AddressedExtensionPage(
        catalog: controller,
        repository: repository,
        location: location,
        onBack: () => _backFromAddress(location),
      );
    },
  );

  Widget _homeFrame() => CupertinoPageScaffold(
    child: SafeArea(
      child: Column(
        children: [
          if (_notice case final notice?)
            CupertinoListTile(
              title: Text(notice, maxLines: 4),
              trailing: CupertinoButton(
                onPressed: () => setState(() => _notice = null),
                child: const Icon(CupertinoIcons.xmark, semanticLabel: '关闭提示'),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final prefersSidebar = fitsColumns(
                  context,
                  constraints,
                  minimumWidth: _sidebarWidth + 540,
                );
                final contentWidth =
                    constraints.maxWidth - (prefersSidebar ? _sidebarWidth : 0);
                final singleColumn =
                    _shownDetail != null &&
                    widget.location.source == null &&
                    !fitsColumns(
                      context,
                      BoxConstraints(maxWidth: contentWidth),
                      minimumWidth: 832,
                    );
                final sidebar = prefersSidebar && !singleColumn;
                return Flex(
                  direction: sidebar ? Axis.horizontal : Axis.vertical,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (sidebar) _sidebar(),
                    Expanded(
                      key: const ValueKey('app-content'),
                      child: _page(singleColumn: singleColumn),
                    ),
                    if (!sidebar && !singleColumn) _navigationBar(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _mangaRequest?.closed.complete();
    _readerPage?.retire();
    _pendingReader?.retire();
    for (final node in _tabFocusNodes.values) {
      node.dispose();
    }
    final catalog = _catalog;
    final platform = _platform;
    final retired = _retiredProgress.toList();
    catalog?.dispose();
    unawaited(() async {
      await catalog?.closeReadingProgress();
      for (final client in retired) {
        await client.flush();
        client.dispose();
      }
      await platform?.dispose();
    }());
    super.dispose();
  }
}
