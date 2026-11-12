import 'package:source_runtime/control_protocol.dart' as wire;

import '../../data/business_state_validation.dart';
import '../browse/catalog_controller.dart';

String sourceLanguage(String value) => value.isEmpty ? '未标注语言' : value;

String extensionName(String packageName, Iterable<wire.CatalogSource> sources) {
  final names = sources.map((source) => source.name).toSet().toList();
  if (names.isEmpty) return packageName.split('.').last;
  if (names.length == 1) return names.single;
  return '${names.take(2).join(' / ')}${names.length > 2 ? ' 等 ${names.length} 个源' : ''}';
}

/// A view of confirmed account intent and public metadata. No Source executes
/// while constructing, sorting or filtering this directory.
final class ExtensionListing {
  ExtensionListing({required this.catalog, this.installed, this.candidate});
  final CatalogController catalog;
  final wire.InstalledExtension? installed;
  final CatalogBuild? candidate;

  String get packageName => installed?.packageName ?? candidate!.packageName;
  CatalogBuild? get latest => installed == null
      ? candidate
      : catalog.builds
            .where(
              (build) =>
                  build.packageName == packageName &&
                  build.catalogUrl == installed!.catalogUrl &&
                  build.repoId == installed!.repoId,
            )
            .firstOrNull;
  CatalogBuild? get exact {
    final build = latest;
    return build?.id == installed?.buildId ? build : null;
  }

  wire.CatalogReference get reference => installed == null
      ? candidate!.catalog
      : wire.CatalogReference(
          catalogUrl: installed!.catalogUrl,
          repoId: installed!.repoId,
        );
  String get name =>
      extensionName(packageName, (latest ?? candidate)?.sources ?? const []);
  List<String> get languages =>
      ((latest ?? candidate)?.sources
                .map((source) => source.lang)
                .toSet()
                .toList() ??
            <String>[])
        ..sort();
  String get languageLabel =>
      languages.isEmpty ? '语言未知' : languages.map(sourceLanguage).join(' · ');
  bool get registered => catalog.isRepositoryRegistered(reference);
  String? get repositoryError =>
      catalog.repositoryErrors[catalogReferenceKey(reference)];
  String get repositoryName =>
      catalog.repositories
          .where(
            (repo) =>
                repo.catalogUrl == reference.catalogUrl &&
                repo.repoId == reference.repoId,
          )
          .firstOrNull
          ?.name ??
      Uri.parse(reference.catalogUrl).host;
  bool get needsUpdate =>
      installed != null && registered && latest != null && exact == null;
  bool get needsAttention =>
      installed != null &&
      (!registered ||
          repositoryError != null ||
          exact == null ||
          !installed!.enabled);
  String? get blockedReason {
    if (installed == null) return '扩展尚未安装';
    if (!registered) return '仓库已移除';
    if (repositoryError != null) return '仓库暂时读取失败';
    if (exact == null) return latest == null ? '所选构建已下架' : '所选构建已下架，需更新';
    if (!installed!.enabled) return '扩展已停用';
    if ((catalog.sourcePreferences?.hasPendingPackage(
              packageName,
              catalog: reference,
            ) ==
            true ||
        catalog.sourcePreferenceRecoveries.any(
          (target) =>
              target.build.packageName == packageName &&
              target.build.catalog == reference,
        )))
      return '漫画源设置待确认';
    return null;
  }

  String status(wire.ExtensionCacheState? cache) {
    if (installed == null) return '可安装';
    final blocked = blockedReason;
    if (blocked != null) return blocked;
    if (cache == null) return '已安装 · 正在检查本机副本';
    return cache.artifacts.any((item) => item.sha256 == installed!.bundleSha256)
        ? '已安装 · 本机就绪'
        : '已安装 · 首次打开时下载';
  }

  bool matches(String query, String? language) =>
      (language == null || languages.contains(language)) &&
      (query.isEmpty ||
          name.toLowerCase().contains(query) ||
          packageName.toLowerCase().contains(query) ||
          ((latest ?? candidate)?.sources.any(
                (source) => source.name.toLowerCase().contains(query),
              ) ??
              false));
}

List<ExtensionListing> extensionListings(
  CatalogController catalog,
  Iterable<wire.InstalledExtension> installed,
) {
  final values = installed.toList();
  final result = [
    for (final extension in values)
      ExtensionListing(catalog: catalog, installed: extension),
    for (final build in catalog.builds)
      if (!values.any(
        (value) =>
            value.packageName == build.packageName &&
            value.catalogUrl == build.catalogUrl &&
            value.repoId == build.repoId,
      ))
        ExtensionListing(catalog: catalog, candidate: build),
  ];
  result.sort((a, b) {
    final language = a.languageLabel.compareTo(b.languageLabel);
    return language == 0
        ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
        : language;
  });
  return result;
}
