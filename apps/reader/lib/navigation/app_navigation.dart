import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:crypto/crypto.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../data/business_state_validation.dart';
import '../features/browse/catalog_controller.dart';
import '../widgets/adaptive_detail_layout.dart';
import '../widgets/app_routes.dart';
import 'app_location.dart';

typedef ReaderPageBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String>? changedChapter,
);

/// UI requests a location. Live builders can reuse the current Source session;
/// a browser-provided location is resolved from the account independently.
class const AppNavigation({
  super.key,
  required final AppLocation location,
  required final void Function(AppLocation) navigate,
  required final void Function(CatalogBuild, wire.CatalogSource) openSource,
  required final Future<void> Function(String, AdaptiveDetailBuilder) openManga,
  required final Future<void> Function(String, String, ReaderPageBuilder)
  openReader,
  required super.child,
}) extends InheritedWidget {
  static AppNavigation? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppNavigation>();

  @override
  bool updateShouldNotify(AppNavigation oldWidget) =>
      location != oldWidget.location;
}

String catalogLocationKey(wire.CatalogReference catalog) =>
    sha256.convert(utf8.encode(catalogReferenceKey(catalog))).toString();

Future<void> openReaderPage(
  BuildContext context, {
  required String mangaKey,
  required String chapterKey,
  required ReaderPageBuilder builder,
}) async {
  if (AppNavigation.maybeOf(context) case final navigation?) {
    await navigation.openReader(mangaKey, chapterKey, builder);
    return;
  }
  final route = AppPageRoute<void>(
    builder: (context) => builder(context, null),
  );
  await Navigator.of(context, rootNavigator: true).push<void>(route);
  await route.completed;
}
