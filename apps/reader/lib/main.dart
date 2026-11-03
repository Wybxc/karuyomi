import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'features/browse/catalog_controller.dart';
import 'features/browse/catalog_page.dart';
import 'runtime/platform_runtime.dart';

void main() => runApp(const KaruyomiApp());

class KaruyomiApp extends StatefulWidget {
  const KaruyomiApp({super.key, this.platform});
  final PlatformRuntime? platform;

  @override
  State<KaruyomiApp> createState() => _KaruyomiAppState();
}

class _KaruyomiAppState extends State<KaruyomiApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Karuyomi',
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
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    this.platform,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final PlatformRuntime? platform;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  PlatformRuntime? _platform;
  CatalogController? _catalog;
  String? _configurationError;
  Map<String, Object?>? _pendingContinuation;
  final _originField = TextEditingController(
    text: const String.fromEnvironment('APP_ORIGIN'),
  );
  static const _labels = ['书架', '浏览', '设置'];
  static const _icons = [
    Icons.collections_bookmark_outlined,
    Icons.explore_outlined,
    Icons.tune_outlined,
  ];

  void _select(int index) => setState(() => _index = index);

  @override
  void initState() {
    super.initState();
    _configure(widget.platform);
  }

  void _configure([PlatformRuntime? injected]) {
    try {
      final configured = _originField.text.trim();
      _platform =
          injected ??
          createPlatformRuntime(
            origin: configured.isEmpty ? null : Uri.parse(configured),
          );
      _originField.text = _platform!.origin.toString();
      _catalog = CatalogController(
        api: _platform!,
        runtime: _platform!.runtime,
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
    } on ArgumentError {
      _configurationError = '请先在设置中填写服务的 HTTPS 地址。';
    } catch (_) {
      _configurationError = '服务初始化未完成，请在设置中重新连接。';
    }
  }

  Future<void> _connect([Map<String, Object?>? continuation]) async {
    final controller = _catalog;
    if (controller == null) {
      _select(2);
      return;
    }
    await controller.connect();
    if (!mounted ||
        !identical(controller, _catalog) ||
        controller.status != ServiceStatus.ready ||
        continuation == null) {
      return;
    }
    _pendingContinuation = null;
    final buildId = continuation['buildId'];
    final builds = controller.builds.where((build) => build.id == buildId);
    if (builds.isEmpty) return;
    await controller.openBuild(builds.first);
    if (!mounted || !identical(controller, _catalog)) return;
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
      final authenticated = await platform.authenticate(
        context,
        pending: {
          ...?_pendingContinuation,
          'tab': _index,
          if (_catalog?.lastBuildId != null) 'buildId': _catalog!.lastBuildId,
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('登录未完成，请重试。')));
      }
    }
  }

  Future<void> _changeService() async {
    if (kIsWeb && _platform != null) {
      await _platform!.rebuild();
      if (mounted) await _connect();
      return;
    }
    final old = _platform;
    _catalog?.dispose();
    _catalog = null;
    _platform = null;
    if (old != null) await old.dispose();
    if (!mounted) return;
    setState(_configure);
  }

  Widget _page() => switch (_index) {
    0 => _EmptyState(
      icon: Icons.auto_stories_outlined,
      title: '书架还是空的',
      description: '从浏览添加你喜欢的漫画。',
      action: FilledButton.icon(
        onPressed: () => _select(1),
        icon: const Icon(Icons.explore_outlined),
        label: const Text('去浏览'),
      ),
    ),
    1 => CatalogPage(
      controller: _catalog,
      onConnect: () => unawaited(_connect()),
      onAuthenticate: () => unawaited(_authenticate()),
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
            DropdownButtonFormField<ThemeMode>(
              initialValue: widget.themeMode,
              decoration: const InputDecoration(
                labelText: '外观',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
              ],
              onChanged: (value) {
                if (value != null) widget.onThemeChanged(value);
              },
            ),
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
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: controller?.busy == true ? null : _changeService,
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
    _catalog?.dispose();
    unawaited(_platform?.dispose());
    _originField.dispose();
    super.dispose();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(description, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    ),
  );
}
