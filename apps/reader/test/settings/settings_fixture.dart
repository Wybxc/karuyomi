import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';

import '../browse/fakes.dart';
import '../data/business_state_server.dart';

final class SettingsFixture {
  SettingsFixture({TestBusinessServer? server})
    : platform = TestPlatform(
        businessServer: server,
        seedDefaultInstallation: false,
      );

  final TestPlatform platform;
  final container = ProviderContainer();
  late final catalog = CatalogController(
    api: platform,
    runtime: platform.runtime,
    rebuildRuntime: platform.rebuild,
    deploymentOrigin: platform.origin,
  );
  final _subscriptions = <ProviderSubscription<SettingsState>>[];

  Future<void> connect() => catalog.connect();
  SettingsController editor({String? mangaKey}) {
    final provider = settingsControllerProvider(
      catalog,
      catalog.settings,
      mangaKey: mangaKey,
    );
    _subscriptions.add(container.listen(provider, (_, _) {}));
    return container.read(provider.notifier);
  }

  SettingsState state({String? mangaKey}) => container.read(
    settingsControllerProvider(catalog, catalog.settings, mangaKey: mangaKey),
  );
  void invalidate({String? mangaKey}) => container.invalidate(
    settingsControllerProvider(catalog, catalog.settings, mangaKey: mangaKey),
  );

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    container.dispose();
    catalog.dispose();
    await catalog.closeReadingProgress();
    await platform.dispose();
  }
}
