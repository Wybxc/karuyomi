import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/source_preferences_repository.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import 'preference_fixtures.dart';

void main() {
  late PreferenceFixture fixture;
  setUp(() async {
    fixture = PreferenceFixture();
    await fixture.open();
  });
  tearDown(() => fixture.close());

  test(
    'opening a build forwards only the rules confirmed by the API',
    () async {
      final rule = wire.PreferenceSyncRule(
        key: 'alias',
        kind: wire.PreferenceValueKind.PREFERENCE_VALUE_KIND_BOOLEAN,
        sourceId: sourceId,
      );
      fixture.platform.afterBusinessReply = (request, reply) {
        if (request.method != 'GET' ||
            !request.uri.path.startsWith('/api/source-preferences/packages/')) {
          return reply;
        }
        final response = wire.decodeProtoJson(
          wire.SourcePreferencesResponse(),
          jsonDecode(reply.body),
        )..syncRules.add(rule);
        return ApiReply(
          status: reply.status,
          headers: reply.headers,
          body: jsonEncode(wire.encodeProtoJson(response)),
          redirected: reply.redirected,
        );
      };
      expect(fixture.platform.preferenceBootstraps.last.syncRules, isEmpty);
      await fixture.catalog.openBuild(fixture.catalog.builds.single);
      expect(fixture.platform.preferenceBootstraps.last.syncRules, [rule]);
    },
  );

  test(
    'settings for a removed Source stay in D1 without blocking the current extension',
    () async {
      await fixture.repository.save(
        catalog: fixture.catalog.defaultCatalog,
        packageName: preferencePackage,
        sourceId: '-999',
        basedOnRevision: 0,
        entries: [
          preferenceEntry('old-setting', wire.PreferenceValue(boolean: true)),
        ],
      );
      await fixture.catalog.openBuild(fixture.catalog.builds.single);
      expect(fixture.catalog.session, isNotNull);
      await fixture.catalog.selectSource(
        fixture.catalog.session!.sources.single,
      );
      expect(fixture.platform.preferenceBootstraps.last.sources, isEmpty);
      final retained = (await fixture.repository.load(
        preferencePackage,
        catalog: fixture.catalog.defaultCatalog,
      )).source('-999');
      expect(retained.revision, 1);
      expect(retained.entries.single.value.boolean, true);
      expect(fixture.catalog.mangas, isNotEmpty);
    },
  );

  test(
    'single session edits stay off the API and survive confirmed account edits and reopening',
    () async {
      final editor = fixture.editor();
      addTearDown(editor.dispose);
      expect(await editor.load(), true);
      expect(
        await editor.change([
          1,
        ], wire.PreferenceValue(text: 'session-password')),
        true,
      );
      expect(fixture.callbacks, 1);
      expect(fixture.postedBodies, isEmpty);
      expect(
        fixture
            .platform
            .preferenceBootstraps
            .last
            .sources
            .single
            .entries
            .single
            .value
            .text,
        'session-password',
      );
      expect(
        await editor.change([0], wire.PreferenceValue(boolean: true)),
        true,
      );
      expect(fixture.callbacks, 2);
      expect(fixture.postedBodies, hasLength(1));
      expect(fixture.postedBodies.single, isNot(contains('session-password')));
      expect(fixture.postedBodies.single, contains('alias'));
      expect(editor.confirmed!.revision, 1);
      expect(editor.snapshot!.nodes.first.toggle.value, true);
      expect(editor.snapshot!.nodes[4].group.nodes.first.enabled, true);
      expect(editor.snapshot!.nodes[1].text.value, 'session-password');
      expect(fixture.catalog.sourcePreferencesBlocked, false);
      expect(fixture.catalog.sourceFilterSnapshot, isNull);
      expect(fixture.catalog.page, 1);
    },
  );

  test(
    'fresh remote revision triggers reconstruction before editing rather than pairing old runtime values with new CAS',
    () async {
      final remote = BusinessStateClient(
        api: fixture.platform,
        identity: fixture.business.identity,
      );
      addTearDown(remote.dispose);
      await SourcePreferencesRepository(remote).save(
        catalog: fixture.catalog.defaultCatalog,
        packageName: preferencePackage,
        sourceId: sourceId,
        basedOnRevision: 0,
        entries: [
          preferenceEntry('remote-key', wire.PreferenceValue(integer: 8)),
        ],
      );
      final editor = fixture.editor();
      addTearDown(editor.dispose);
      expect(await editor.load(), true);
      expect(fixture.platform.rebuildCount, 1);
      expect(editor.confirmed!.revision, 1);
      expect(
        await editor.change([0], wire.PreferenceValue(boolean: true)),
        true,
      );
      final current = (await fixture.repository.load(
        preferencePackage,
        catalog: fixture.catalog.defaultCatalog,
      )).source(sourceId);
      expect(current.revision, 2);
      expect(
        current.entries.map((entry) => entry.key),
        containsAll(['remote-key', 'alias']),
      );
      expect(fixture.callbacks, 1);
    },
  );

  test(
    'lost business ACK blocks Source calls and only exact explicit business retry resumes; reopening editor is read-only',
    () async {
      final editor = fixture.editor();
      addTearDown(editor.dispose);
      await editor.load();
      fixture.loseNextPreferenceAck();
      expect(
        await editor.change([0], wire.PreferenceValue(boolean: true)),
        false,
      );
      final original = fixture.postedBodies.single;
      expect(editor.pending, isNotNull);
      expect(fixture.callbacks, 1);
      final calls = fixture.platform.invocations.length;
      await fixture.catalog.loadMangas(more: true);
      expect(fixture.platform.invocations, hasLength(calls));
      final replacement = fixture.editor();
      addTearDown(replacement.dispose);
      expect(await replacement.load(), true);
      expect(fixture.callbacks, 1);
      expect(fixture.postedBodies, hasLength(1));
      expect(await replacement.retry(), true);
      expect(fixture.postedBodies, [original, original]);
      expect(fixture.platform.businessServer.appliedMutations, 1);
      expect(fixture.callbacks, 1);
      expect(replacement.pending, isNull);
      expect(replacement.canEdit, true);
    },
  );

  test(
    'veto preserves actual callback side effects without persisting rejected input',
    () async {
      final editor = fixture.editor();
      addTearDown(editor.dispose);
      await editor.load();
      fixture.veto = true;
      expect(
        await editor.change([0], wire.PreferenceValue(boolean: true)),
        true,
      );
      expect(fixture.callbacks, 1);
      final current = (await fixture.repository.load(
        preferencePackage,
        catalog: fixture.catalog.defaultCatalog,
      )).source(sourceId);
      expect(current.entries.single.key, 'dependent');
      expect(current.entries.single.value.boolean, true);
      expect(editor.snapshot!.nodes.first.toggle.value, false);
      expect(editor.message, '漫画源已更新设置；请核对实际值。');
    },
  );

  test(
    'a listener returning false can store a normalized session value without an API write',
    () async {
      final editor = fixture.editor();
      addTearDown(editor.dispose);
      await editor.load();
      fixture.editGate = (_) async {
        fixture.values['note'] = preferenceEntry(
          'note',
          wire.PreferenceValue(text: 'https://example.com'),
        );
        return wire.SourceResult(
          preferenceEdit: wire.PreferenceEditResult(
            snapshot: fixture.snapshot(),
          ),
        );
      };
      expect(
        await editor.change([
          4,
          1,
        ], wire.PreferenceValue(text: 'https://example.com:443/catalog')),
        true,
      );
      expect(fixture.callbacks, 1);
      expect(fixture.postedBodies, isEmpty);
      expect(
        editor.snapshot!.nodes[4].group.nodes[1].text.value,
        'https://example.com',
      );
      expect(editor.message, '漫画源已更新设置；请核对实际值。');
    },
  );

  test('a rejection with existing session values reports no change', () async {
    final editor = fixture.editor();
    addTearDown(editor.dispose);
    await editor.load();
    expect(
      await editor.change([
        4,
        1,
      ], wire.PreferenceValue(text: 'https://example.com')),
      true,
    );
    fixture.editGate = (_) async => wire.SourceResult(
      preferenceEdit: wire.PreferenceEditResult(snapshot: fixture.snapshot()),
    );
    expect(
      await editor.change([4, 1], wire.PreferenceValue(text: 'not-a-url')),
      true,
    );
    expect(fixture.callbacks, 2);
    expect(fixture.postedBodies, isEmpty);
    expect(
      editor.snapshot!.nodes[4].group.nodes[1].text.value,
      'https://example.com',
    );
    expect(editor.message, '漫画源未接受输入；设置未更改。');
  });

  test(
    'unknown runtime result never replays its callback; explicit read and reconstruction restore confirmed state',
    () async {
      final editor = fixture.editor();
      addTearDown(editor.dispose);
      await editor.load();
      fixture.failEdit = true;
      expect(
        await editor.change([0], wire.PreferenceValue(boolean: true)),
        false,
      );
      expect(editor.needsRecovery, true);
      expect(fixture.postedBodies, isEmpty);
      expect(fixture.callbacks, 1);
      final calls = fixture.platform.invocations.length;
      await fixture.catalog.loadMangas();
      expect(fixture.platform.invocations, hasLength(calls));
      fixture.failEdit = false;
      expect(await editor.recover(), true);
      expect(fixture.callbacks, 1);
      expect(editor.snapshot!.nodes.first.toggle.value, false);
      expect(editor.pending, isNull);
    },
  );

  test(
    'a late edit response cannot create pending values or session secrets for a replacement identity',
    () async {
      final editor = fixture.editor();
      addTearDown(editor.dispose);
      await editor.load();
      final gate = Completer<wire.SourceResult>();
      addTearDown(() {
        if (!gate.isCompleted) {
          gate.complete(
            wire.SourceResult(
              preferenceEdit: wire.PreferenceEditResult(
                snapshot: fixture.snapshot(),
              ),
            ),
          );
        }
      });
      fixture.editGate = (_) => gate.future;
      final changing = editor.change([
        1,
      ], wire.PreferenceValue(text: 'late-secret'));
      fixture.platform.runtime.containerLost('Identity replacement');
      await Future<void>.delayed(Duration.zero);
      fixture.platform.bootstrapSubject = 'other';
      fixture.platform.seedInstalledBuilds(
        wire
            .decodeProtoJson(wire.ExtensionIndex(), fixture.platform.inventory)
            .builds,
      );
      await fixture.catalog.connect();
      await fixture.catalog.openBuild(fixture.catalog.builds.single);
      await fixture.catalog.selectSource(
        fixture.catalog.session!.sources.single,
      );
      gate.complete(
        wire.SourceResult(
          preferenceEdit: wire.PreferenceEditResult(
            accepted: true,
            snapshot: wire.PreferenceSnapshot(
              snapshotId: 'late',
              sessionValues: [
                preferenceEntry(
                  'password',
                  wire.PreferenceValue(text: 'late-secret'),
                ),
              ],
            ),
          ),
        ),
      );
      expect(await changing, false);
      expect(fixture.catalog.subject, 'other');
      expect(fixture.platform.preferenceBootstraps.last.sources, isEmpty);
      expect(fixture.postedBodies, isEmpty);
      expect(editor.available, false);
    },
  );
}
