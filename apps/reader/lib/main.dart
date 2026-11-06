import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

void main() => runApp(const KaruyomiApp());

class KaruyomiApp extends StatefulWidget {
  const KaruyomiApp({super.key, this.platform, this.platformFactory});
  final PlatformRuntime? platform;
  final PlatformRuntime Function(Uri? origin)? platformFactory;

  @override
  State<KaruyomiApp> createState() => _KaruyomiAppState();
}

class _KaruyomiAppState extends State<KaruyomiApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Karuyomi',
    builder: readerBaselineEnabled
        ? (context, child) => ReaderBaselineHost(child: child!)
        : null,
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    themeMode: _themeMode,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff476b5d)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff476b5d),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: AppShell(
      themeMode: _themeMode,
      onThemeChanged: (value) => setState(() => _themeMode = value),
      platform: widget.platform,
      platformFactory: widget.platformFactory,
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    this.platform,
    this.platformFactory,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final PlatformRuntime? platform;
  final PlatformRuntime Function(Uri? origin)? platformFactory;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  PlatformRuntime? _platform;
  CatalogController? _catalog;
  SettingsController? _settings;
  ThemeMode _confirmedTheme = ThemeMode.system;
  String? _configurationError;
  Map<String, Object?>? _pendingContinuation;
  final _retiredProgress = <ReadingProgressController>{};
  bool _retryingProgress = false;
  bool _changingService = false;
  final _originField = TextEditingController(
    text: const String.fromEnvironment('APP_ORIGIN'),
  );
  static const _labels = ['书架', '浏览', '设置'];
  static const _icons = [
    Icons.collections_bookmark_outlined,
    Icons.explore_outlined,
    Icons.tune_outlined,
  ];

  void _select(int index) {
    setState(() => _index = index);
    if (index == 2) unawaited(_settings?.refresh());
  }

  void _clearSettings() {
    _settings?.removeListener(_settingsChanged);
    _settings?.dispose();
    _settings = null;
  }

  void _settingsChanged() {
    if (!mounted) return;
    final settings = _settings;
    final snapshot = settings?.snapshot;
    if (settings?.available == true && snapshot != null) {
      _applyTheme(appTheme(snapshot.global.theme));
    }
    setState(() {});
  }

  void _applyTheme(ThemeMode value) {
    if (_confirmedTheme == value) return;
    _confirmedTheme = value;
    widget.onThemeChanged(value);
  }

  void _catalogChanged() {
    if (!mounted) return;
    final catalog = _catalog;
    _settings?.checkCurrent();
    if (catalog == null || catalog.status != ServiceStatus.ready) return;
    final repository = catalog.settings;
    if (repository == null ||
        (identical(repository, _settings?.repository) &&
            _settings!.available)) {
      return;
    }
    if (_settings?.repository.identity.key != repository.identity.key) {
      _applyTheme(ThemeMode.system);
    }
    _clearSettings();
    final subject = catalog.subject;
    final origin = catalog.deploymentOrigin?.origin;
    _settings = SettingsController(
      repository: repository,
      isCurrent: () =>
          mounted &&
          identical(catalog, _catalog) &&
          !catalog.accessPaused &&
          catalog.subject == subject &&
          catalog.deploymentOrigin?.origin == origin &&
          identical(catalog.settings, repository),
    )..addListener(_settingsChanged);
    unawaited(_settings!.refresh());
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_settings?.refresh());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configure(widget.platform);
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
      )..addListener(_catalogChanged);
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
      _catalogChanged();
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
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
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
            ),
          );
        } finally {
          await controller.closeChapter(recovered.opened);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error is StateError
                    ? error.message.toString()
                    : '阅读恢复状态无效，请重新选择章节',
              ),
            ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError ? error.message.toString() : '登录未完成，请重试。',
            ),
          ),
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
    if (_changingService) return;
    setState(() => _changingService = true);
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
        _clearSettings();
        _applyTheme(ThemeMode.system);
        if (oldCatalog != null) {
          oldCatalog.removeListener(_catalogChanged);
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
    await _catalog?.flushReadingProgress();
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
            if (_settings case final settings?)
              GlobalSettingsPanel(
                key: ObjectKey(settings),
                controller: settings,
              )
            else
              const Text('连接并确认身份后可读取和保存同步设置。'),
            const SizedBox(height: 24),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Karuyomi'),
              subtitle: Text('轻松翻开下一页'),
              trailing: Text('0.1.0'),
            ),
          ],
        ),
      ),
    ),
  };

  Widget _connectionSettings() {
    final controller = _catalog;
    Widget content() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('服务连接', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _originField,
          readOnly: kIsWeb,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: '服务地址',
            hintText: 'https://你的服务域名',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (_configurationError != null) Text(_configurationError!),
        if (controller?.email != null) Text('账号：${controller!.email}'),
        if (controller?.error != null) Text(controller!.error!),
        if (_retiredProgress.isNotEmpty ||
            controller?.hasUnsavedReadingProgress == true) ...[
          const SizedBox(height: 12),
          const Text('部分阅读进度尚未保存；原服务和身份的记录仍保留，可继续连接服务。'),
          TextButton(
            onPressed: _retryingProgress ? null : _retryProgress,
            child: const Text('重试保存所有进度'),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: controller?.busy == true || _changingService
                  ? null
                  : _changeService,
              icon: const Icon(Icons.link),
              label: const Text('连接服务'),
            ),
            FilledButton.icon(
              onPressed: _platform == null || controller?.busy == true
                  ? null
                  : _authenticate,
              icon: const Icon(Icons.login),
              label: const Text('登录'),
            ),
          ],
        ),
      ],
    );
    return controller == null
        ? content()
        : AnimatedBuilder(
            animation: controller,
            builder: (context, _) => content(),
          );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 840;
      return Scaffold(
        appBar: AppBar(title: Text(_labels[_index])),
        body: SafeArea(
          child: Row(
            children: [
              if (wide) ...[
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (var i = 0; i < _labels.length; i++)
                      NavigationRailDestination(
                        icon: Icon(_icons[i]),
                        label: Text(_labels[i]),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
              ],
              Expanded(child: _page()),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: [
                  for (var i = 0; i < _labels.length; i++)
                    NavigationDestination(
                      icon: Icon(_icons[i]),
                      label: _labels[i],
                    ),
                ],
              ),
      );
    },
  );

  @override
  void dispose() {
    final catalog = _catalog;
    final platform = _platform;
    final retired = _retiredProgress.toList();
    WidgetsBinding.instance.removeObserver(this);
    _clearSettings();
    catalog?.removeListener(_catalogChanged);
    catalog?.dispose();
    unawaited(() async {
      await catalog?.closeReadingProgress();
      for (final client in retired) {
        await client.flush();
        client.dispose();
      }
      await platform?.dispose();
    }());
    _originField.dispose();
    super.dispose();
  }
}
