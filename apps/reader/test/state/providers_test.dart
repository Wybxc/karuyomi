import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/library/library_providers.dart';
import 'package:karuyomi/features/settings/settings_controller.dart';
import 'package:karuyomi/state/account_providers.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import '../settings/settings_fixture.dart';

void main() {
  test(
    'shared library reads and invalidation never write or dispose the runtime',
    () async {
      final fixture = SettingsFixture();
      await fixture.connect();
      addTearDown(fixture.dispose);
      final catalog = fixture.catalog;
      final repository = catalog.library!;
      final provider = libraryViewProvider(repository);
      final first = fixture.container.listen(provider, (_, _) {});
      final second = fixture.container.listen(provider, (_, _) {});
      final view = await fixture.container.read(provider.future);
      expect(view.entries, isEmpty);
      final requests = fixture.platform.businessServer.requests;
      expect(
        requests.where((request) => request.uri.path == '/api/library'),
        hasLength(1),
      );
      await repository.setFavorite(
        packageName: 'eu.kanade.source.test',
        sourceId: sourceId,
        sourceName: '测试漫画源',
        sourceLang: 'zh',
        manga: testManga,
        favorite: true,
      );
      await fixture.container.pump();
      expect(first.read().value!.entries.single.title, testManga.title);
      expect(identical(first.read(), second.read()), true);
      fixture.container.invalidate(provider);
      await fixture.container.read(provider.future);
      expect(
        requests.where((request) => request.method == 'POST'),
        hasLength(1),
      );
      first.close();
      second.close();
      await fixture.container.pump();
      expect(fixture.container.read(provider.exists), false);
      expect(fixture.platform.disposalCount, 0);
      expect(catalog.settings, isNotNull);
      expect(
        fixture.platform.controlCommands.where(
          (command) => command == wire.ControlRequest_Command.closeBuild,
        ),
        isEmpty,
      );
    },
  );

  test(
    'an old settings notifier cannot submit into a newly verified account',
    () async {
      final fixture = SettingsFixture();
      await fixture.connect();
      addTearDown(fixture.dispose);
      final oldRepository = fixture.catalog.settings!;
      final old = fixture.editor();
      final values = fixture.state().snapshot!.global.deepCopy()
        ..theme = wire.AppTheme.APP_THEME_DARK;
      fixture.platform.bootstrapSubject = 'other-owner';
      await fixture.catalog.connect();
      await fixture.container.pump();
      expect(
        fixture.container
            .read(confirmedAccountProvider(fixture.catalog))!
            .settings
            .identity
            .subject,
        'other-owner',
      );
      expect(
        fixture.container
            .read(settingsControllerProvider(fixture.catalog, oldRepository))
            .available,
        false,
      );
      expect(await old.saveGlobal(values, 0), false);
      expect(await old.retry(), false);
      final current = fixture.editor();
      expect(identical(old, current), false);
      expect(
        fixture.state().snapshot!.global.theme,
        wire.AppTheme.APP_THEME_SYSTEM,
      );
      expect(
        fixture.platform.businessServer.requests.where(
          (request) => request.method == 'POST',
        ),
        isEmpty,
      );
    },
  );
}
