import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() => runApp(const KaruyomiApp());

class KaruyomiApp extends StatefulWidget {
  const KaruyomiApp({super.key});

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
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  static const _labels = ['书架', '浏览', '设置'];
  static const _icons = [
    Icons.collections_bookmark_outlined,
    Icons.explore_outlined,
    Icons.tune_outlined,
  ];

  void _select(int index) => setState(() => _index = index);

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
    1 => const _EmptyState(
      icon: Icons.travel_explore_outlined,
      title: '尚未安装漫画源',
      description: '接入漫画源后，可以在这里搜索和浏览。',
    ),
    _ => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
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
