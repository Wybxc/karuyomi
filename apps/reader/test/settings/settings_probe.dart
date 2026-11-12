import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:karuyomi/data/settings_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';

/// Tests observe provider state independently of the editor widget's lifetime.
final class SettingsProbe {
  SettingsProbe(
    ProviderContainer container,
    CatalogController catalog, {
    this.mangaKey,
  }) : repository = catalog.settings! {
    final provider = settingsControllerProvider(
      catalog,
      catalog.settings,
      mangaKey: mangaKey,
    );
    state = container.read(provider);
    commands = container.read(provider.notifier);
    final subscription = container.listen(provider, (_, next) => state = next);
    addTearDown(subscription.close);
  }
  late SettingsState state;
  late final SettingsController commands;
  final SettingsRepository repository;
  final String? mangaKey;
}

SettingsProbe globalSettings(WidgetTester tester) {
  final panel = find.byType(GlobalSettingsPanel);
  return SettingsProbe(
    ProviderScope.containerOf(tester.element(panel), listen: false),
    tester.widget<GlobalSettingsPanel>(panel).catalog,
  );
}
