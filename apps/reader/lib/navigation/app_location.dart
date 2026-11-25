import 'package:cupertino_ui/cupertino_ui.dart';

enum AppTab {
  library('书架', CupertinoIcons.book),
  history('历史', CupertinoIcons.clock),
  browse('浏览', CupertinoIcons.compass),
  extensions('扩展', CupertinoIcons.cube),
  settings('设置', CupertinoIcons.slider_horizontal_3);

  const AppTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

typedef SourceLocation = ({String packageName, String sourceId});
typedef ExtensionLocation = ({String catalogKey, String packageName});

enum AppPanel { search, repositories, storage }

enum SettingsSection {
  appearance('外观与主题', '跟随系统、浅色与深色', CupertinoIcons.paintbrush),
  reading('账户阅读偏好', '阅读方式、分页布局、图像适配和裁白', CupertinoIcons.book),
  input('翻页与快捷键', '点击区与键盘操作', CupertinoIcons.keyboard),
  connection('服务连接', '服务地址与登录', CupertinoIcons.cloud),
  about('关于', 'Karuyomi', CupertinoIcons.info);

  const SettingsSection(this.title, this.subtitle, this.icon);
  String get id => name;
  final String title;
  final String subtitle;
  final IconData icon;
  bool get isLocal => this == appearance || this == input;
}

/// URL state contains only stable identifiers. Account and Source data are
/// loaded separately, with the same checks as navigation from a list.
final class AppLocation {
  const AppLocation(
    this.tab, {
    this.panel,
    this.extension,
    this.setting,
    this.source,
    this.mangaKey,
    this.chapterKey,
    this.showDetails = true,
  });

  final AppTab tab;
  final AppPanel? panel;
  final ExtensionLocation? extension;
  final SettingsSection? setting;
  final SourceLocation? source;
  final String? mangaKey;
  final String? chapterKey;

  /// Resuming from the shelf opens the reader directly above the shelf.
  final bool showDetails;

  static final _package = RegExp(r'^[a-zA-Z0-9_.-]{1,200}$');
  static final _id = RegExp(r'^-?\d{1,19}$');
  static final _key = RegExp(r'^[0-9a-f]{64}$');
  static final _chapter = RegExp(r'^(snapshot-)?[0-9a-f]{64}$');
  static final _minimumSourceId = -(BigInt.one << 63);
  static final _maximumSourceId = (BigInt.one << 63) - BigInt.one;

  static bool _sourceId(String input) {
    if (!_id.hasMatch(input)) return false;
    final value = BigInt.parse(input);
    return value >= _minimumSourceId && value <= _maximumSourceId;
  }

  static AppLocation? parse(Uri uri) {
    if (uri.hasScheme || uri.hasAuthority || uri.hasFragment) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length < 2 || segments.first != 'app') return null;
    final tab = AppTab.values.asNameMap()[segments[1]];
    if (tab == null) return null;
    var rest = segments.skip(2).toList();
    if (tab == AppTab.settings) {
      final section = SettingsSection.values.asNameMap()[rest.firstOrNull];
      return rest.isEmpty || (rest.length == 1 && section != null)
          ? AppLocation(tab, setting: section)
          : null;
    }
    ExtensionLocation? extension;
    if (tab == AppTab.extensions && rest.firstOrNull == 'item') {
      if (rest.length < 3 ||
          !_key.hasMatch(rest[1]) ||
          !_package.hasMatch(rest[2])) {
        return null;
      }
      extension = (catalogKey: rest[1], packageName: rest[2]);
      rest = rest.sublist(3);
    }
    final panel = AppPanel.values.asNameMap()[rest.firstOrNull];
    if (panel != null) {
      final valid = switch (panel) {
        AppPanel.search => tab == AppTab.browse,
        AppPanel.repositories => tab == AppTab.extensions && extension == null,
        AppPanel.storage => tab == AppTab.extensions,
      };
      if (!valid) return null;
      rest = rest.sublist(1);
    }
    SourceLocation? source;
    if (rest.firstOrNull == 'source') {
      if (panel != null ||
          (tab != AppTab.browse && tab != AppTab.extensions) ||
          rest.length < 3 ||
          !_package.hasMatch(rest[1]) ||
          (extension != null && rest[1] != extension.packageName) ||
          !_sourceId(rest[2])) {
        return null;
      }
      source = (packageName: rest[1], sourceId: rest[2]);
      rest = rest.sublist(3);
    }
    final base = AppLocation(
      tab,
      source: source,
      panel: panel,
      extension: extension,
    );
    if (rest.isEmpty) return base;
    if (tab == AppTab.extensions && source == null) return null;
    return switch (rest) {
      ['manga', final manga] when _key.hasMatch(manga) => base.withManga(manga),
      ['manga', final manga, 'read', final chapter]
          when _key.hasMatch(manga) && _chapter.hasMatch(chapter) =>
        base.withManga(manga).withChapter(manga, chapter),
      ['read', final manga, final chapter]
          when _key.hasMatch(manga) && _chapter.hasMatch(chapter) =>
        base.withChapter(manga, chapter),
      _ => null,
    };
  }

  AppLocation withSource(SourceLocation selected) =>
      AppLocation(tab, source: selected, extension: extension);

  AppLocation withManga(String key) => AppLocation(
    tab,
    source: source,
    panel: panel,
    extension: extension,
    mangaKey: key,
  );

  AppLocation withChapter(String manga, String chapter) => AppLocation(
    tab,
    source: source,
    panel: panel,
    extension: extension,
    mangaKey: manga,
    chapterKey: chapter,
    showDetails: mangaKey == manga && showDetails,
  );

  AppLocation get parent {
    if (chapterKey != null && showDetails) return withManga(mangaKey!);
    if (mangaKey != null) {
      return AppLocation(
        tab,
        source: source,
        panel: panel,
        extension: extension,
      );
    }
    if (source != null || panel != null) {
      return AppLocation(tab, extension: extension);
    }
    return AppLocation(tab);
  }

  String get path => Uri(
    pathSegments: [
      '',
      'app',
      tab.name,
      if (setting != null) setting!.id,
      if (extension case final item?) ...[
        'item',
        item.catalogKey,
        item.packageName,
      ],
      if (panel != null) panel!.name,
      if (source case final selected?) ...[
        'source',
        selected.packageName,
        selected.sourceId,
      ],
      if (mangaKey case final manga?) ...[
        if (showDetails) 'manga',
        if (!showDetails) 'read',
        manga,
        if (chapterKey case final chapter?) ...[
          if (showDetails) 'read',
          chapter,
        ],
      ],
    ],
  ).path;

  @override
  bool operator ==(Object other) =>
      other is AppLocation &&
      tab == other.tab &&
      panel == other.panel &&
      extension == other.extension &&
      setting == other.setting &&
      source == other.source &&
      mangaKey == other.mangaKey &&
      chapterKey == other.chapterKey &&
      showDetails == other.showDetails;

  @override
  int get hashCode => Object.hash(
    tab,
    panel,
    extension,
    setting,
    source,
    mangaKey,
    chapterKey,
    showDetails,
  );
}
