import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/library_repository.dart';
import '../data/settings_repository.dart';
import '../features/browse/catalog_controller.dart';

part 'account_providers.g.dart';

typedef ConfirmedAccount = ({
  LibraryRepository library,
  SettingsRepository settings,
});

/// A read dependency for a verified identity. The catalog continues to own the
/// business client and runtime; unsubscribing never closes either of them.
@riverpod
ConfirmedAccount? confirmedAccount(Ref ref, CatalogController catalog) {
  if (catalog.closed) return null;
  catalog.addListener(ref.invalidateSelf);
  ref.onDispose(() => catalog.removeListener(ref.invalidateSelf));
  if (catalog.subject == null ||
      catalog.accessPaused ||
      !{ServiceStatus.ready, ServiceStatus.failed}.contains(catalog.status)) {
    return null;
  }
  final library = catalog.library;
  final settings = catalog.settings;
  return library == null || settings == null
      ? null
      : (library: library, settings: settings);
}

/// Reads are refreshed by explicit UI/foreground actions. A provider error must
/// not create an unbounded retry loop or replay a business command.
Duration? noAutomaticRetry(int retryCount, Object error) => null;
