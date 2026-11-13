import 'widgets/app_page_route.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diagnostics/reader_baseline.dart';
import 'diagnostics/reader_baseline_host.dart';
import 'features/reader/reading_progress_controller.dart';
import 'features/reader/reader_recovery.dart';
import 'features/reader/chapter_reader_route.dart';
import 'features/browse/catalog_controller.dart';
import 'features/browse/catalog_page.dart';
import 'features/library/library_page.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/settings_widgets.dart';
import 'runtime/platform_runtime.dart';
import 'state/account_providers.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      child: KaruyomiApp(
        connectionPreferences: kIsWeb ? null : SharedPreferencesAsync(),
      ),
    ),
  );
}

class const KaruyomiApp({
  super.key,
  final PlatformRuntime? platform,
  final PlatformRuntime Function(Uri? origin)? platformFactory,
  final SharedPreferencesAsync? connectionPreferences,
}) extends StatefulWidget {
  @override
  State<KaruyomiApp> createState() => _KaruyomiAppState();
}

class _KaruyomiAppState extends State<KaruyomiApp> {
  Brightness? _brightness;

  @override
  Widget build(BuildContext context) => CupertinoApp(
    title: 'Karuyomi',
    builder: readerBaselineEnabled
        ? (context, child) => ReaderBaselineHost(child: child!)
        : null,
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalCupertinoLocalizations.delegates,
    theme: readerAppTheme(_brightness),
    home: AppShell(
      brightness: _brightness,
      onThemeChanged: (value) => setState(() => _brightness = value),
      platform: widget.platform,
      platformFactory: widget.platformFactory,
      connectionPreferences: widget.connectionPreferences,
    ),
  );
}

class const AppShell({
  super.key,
  required final Brightness? brightness,
  required final ValueChanged<Brightness?> onThemeChanged,
  final PlatformRuntime? platform,
  final PlatformRuntime Function(Uri? origin)? platformFactory,
  final SharedPreferencesAsync? connectionPreferences,
}) extends StatefulHookConsumerWidget {
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  PlatformRuntime? _platform;
  CatalogController? _catalog;
  SettingsController? get _settings => _catalog == null
      ? null
      : ref.read(
          settingsControllerProvider(_catalog!, _catalog!.settings).notifier,
        );
  Brightness? _confirmedTheme;
  String? _configurationError;
  String? _notice;
  Map<String, Object?>? _pendingContinuation;
  final _retiredProgress = <ReadingProgressController>{};
  bool _retryingProgress = false;
  bool _changingService = false;
  bool _restoringOrigin = false;
  String? _originPersistenceError;
  static const _defaultOrigin = String.fromEnvironment('APP_ORIGIN');
  static const _originKey = 'native_service_origin';
  late TextEditingController _originField;
  static const _labels = ['书架', '浏览', '设置'];
  static const _icons = [
    CupertinoIcons.book,
    CupertinoIcons.compass,
    CupertinoIcons.slider_horizontal_3,
  ];

  void _select(int index) {
    setState(() => _index = index);
    if (index == 2) unawaited(_settings?.refresh());
  }

  void _applyTheme(Brightness? value) {
    if (_confirmedTheme == value) return;
    _confirmedTheme = value;
    widget.onThemeChanged(value);
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

  void _configurationFailed(Object error) {
    _configurationError = switch (error) {
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
        final tab = pending['tab'];
        if (tab is int && tab >= 0 && tab < 3) _index = tab;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_connect(_pendingContinuation));
      });
    } catch (error) {
      _configurationFailed(error);
    }
  }

  Future<void> _connect([Map<String, Object?>? continuation]) async {
    final controller = _catalog;
    if (controller == null) {
      _select(2);
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
    if (continuation['reader'] case final Object reader) {
      try {
        final recovery = ReaderRecoveryContext.fromJson(reader);
        final recovered = await recoverReader(
          controller,
          recovery,
          isCurrent: () => mounted && identical(controller, _catalog),
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
          final readerRoute = AppPageRoute<void>(
            builder: (_) => ChapterReaderRoute(
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
            ),
          );
          await Navigator.of(context).push<void>(readerRoute);
          await readerRoute.completed;
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
      _select(2);
      return;
    }
    try {
      if (!mounted) return;
      final authenticated = await platform.authenticate(
        context,
        pending: {
          ...?_pendingContinuation,
          'tab': _index,
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
      pending: {'tab': 1, 'reader': recovery.toJson()},
    );
    platform.takePendingAuthentication();
    return authenticated;
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
        _applyTheme(null);
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

  Widget _page() => switch (_index) {
    0 => LibraryPage(
      controller: _catalog,
      onBrowse: () => _select(1),
      onConnect: () => unawaited(_connect()),
      onAuthenticate: () => unawaited(_authenticate()),
      onAuthenticateReader: _authenticateReader,
    ),
    1 => CatalogPage(
      controller: _catalog,
      onConnect: () => unawaited(_connect()),
      onAuthenticate: () => unawaited(_authenticate()),
      onAuthenticateReader: _authenticateReader,
      configurationError: _configurationError,
    ),
    _ => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _connectionSettings(),
            const SizedBox(height: 24),
            if (_catalog case final catalog?
                when ref.watch(confirmedAccountProvider(catalog)) != null)
              GlobalSettingsPanel(catalog: catalog)
            else
              const Text('连接并确认身份后可读取和保存同步设置。'),
            const SizedBox(height: 24),
            const CupertinoListTile(
              title: Text('Karuyomi'),
              subtitle: Text('轻松翻开下一页'),
              trailing: Text('0.1.0'),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    ),
  };

  Widget _connectionSettings() {
    final controller = _catalog;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '服务连接',
          style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
        ),
        const SizedBox(height: 16),
        CupertinoTextField(
          controller: _originField,
          readOnly: kIsWeb || _restoringOrigin,
          keyboardType: TextInputType.url,
          autocorrect: false,
          placeholder: 'https://你的服务域名',
        ),
        const SizedBox(height: 12),
        if (_configurationError != null) Text(_configurationError!),
        if (_originPersistenceError != null) Text(_originPersistenceError!),
        if (controller?.email != null) Text('账号：${controller!.email}'),
        if (controller?.error != null) Text(controller!.error!),
        if (_retiredProgress.isNotEmpty ||
            controller?.hasUnsavedReadingProgress == true) ...[
          const SizedBox(height: 12),
          const Text('部分阅读进度尚未保存；原服务和身份的记录仍保留，可继续连接服务。'),
          CupertinoButton(
            onPressed: _retryingProgress ? null : _retryProgress,
            child: const Text('重试保存所有进度'),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            CupertinoButton(
              onPressed:
                  controller?.busy == true ||
                      _changingService ||
                      _restoringOrigin
                  ? null
                  : _changeService,
              child: const Text('连接服务'),
            ),
            CupertinoButton.filled(
              onPressed: _platform == null || controller?.busy == true
                  ? null
                  : _authenticate,
              child: const Text('登录'),
            ),
          ],
        ),
      ],
    );
  }

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
      final theme = ref.watch(
        settingsControllerProvider(catalog, catalog.settings).select(
          (state) => state.available ? state.snapshot?.global.theme : null,
        ),
      );
      final desired = theme == null ? null : appBrightness(theme);
      if (_confirmedTheme != desired) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(catalog, _catalog)) _applyTheme(desired);
        });
      }
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        return CupertinoPageScaffold(
          navigationBar: CupertinoNavigationBar(middle: Text(_labels[_index])),
          child: SafeArea(
            child: Column(
              children: [
                if (_notice case final notice?)
                  CupertinoListTile(
                    title: Text(notice, maxLines: 4),
                    trailing: CupertinoButton(
                      onPressed: () => setState(() => _notice = null),
                      child: const Icon(
                        CupertinoIcons.xmark,
                        semanticLabel: '关闭提示',
                      ),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      if (wide)
                        SizedBox(
                          width: 148,
                          child: Column(
                            key: const ValueKey('app-navigation'),
                            children: [
                              for (var i = 0; i < _labels.length; i++)
                                CupertinoButton(
                                  onPressed: () => _select(i),
                                  color: _index == i
                                      ? AppColors.selection.resolveFrom(context)
                                      : null,
                                  child: Row(
                                    children: [
                                      Icon(
                                        _icons[i],
                                        color:
                                            (_index == i
                                                    ? AppColors.onSelection
                                                    : AppColors.secondaryLabel)
                                                .resolveFrom(context),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _labels[i],
                                        style: TextStyle(
                                          color:
                                              (_index == i
                                                      ? AppColors.onSelection
                                                      : AppColors
                                                            .secondaryLabel)
                                                  .resolveFrom(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Expanded(child: _page()),
                    ],
                  ),
                ),
                if (!wide)
                  CupertinoTabBar(
                    key: const ValueKey('app-navigation'),
                    backgroundColor: AppColors.toolbar.resolveFrom(context),
                    inactiveColor: AppColors.secondaryLabel.resolveFrom(
                      context,
                    ),
                    currentIndex: _index,
                    onTap: _select,
                    items: [
                      for (var i = 0; i < _labels.length; i++)
                        BottomNavigationBarItem(
                          icon: Icon(_icons[i]),
                          label: _labels[i],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
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
