import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/source_preferences_repository.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:karuyomi/features/sources/source_preferences_controller.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import '../browse/fakes.dart';

const preferencePackage = 'eu.kanade.source.test';
const accountScope = wire.PreferenceSyncScope.PREFERENCE_SYNC_SCOPE_ACCOUNT;
const sessionScope =
    wire.PreferenceSyncScope.PREFERENCE_SYNC_SCOPE_CLIENT_SESSION;
wire.PreferenceEntry preferenceEntry(String key, wire.PreferenceValue value) =>
    wire.PreferenceEntry(key: key, value: value);

final class PreferenceFixture {
  final platform = TestPlatform();
  late final CatalogController catalog;
  int descriptions = 0;
  int callbacks = 0;
  bool veto = false;
  bool failEdit = false;
  bool missingChoice = false;
  bool emptyOptions = false;
  Future<wire.SourceResult> Function(wire.SourceCall call)? editGate;
  final edits = <wire.PreferenceEditRequest>[];
  Map<String, wire.PreferenceEntry> values = {};
  int _opened = 0;

  Future<void> open() async {
    platform.invokeHandler = _invoke;
    catalog = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    await catalog.openBuild(catalog.builds.single);
    await catalog.selectSource(catalog.session!.sources.single);
  }

  void _readBootstrap() {
    if (_opened == platform.preferenceBootstraps.length) return;
    _opened = platform.preferenceBootstraps.length;
    values = {
      for (final source in platform.preferenceBootstraps.last.sources)
        for (final entry in source.entries) entry.key: entry.deepCopy(),
    };
  }

  wire.PreferenceSnapshot snapshot() {
    _readBootstrap();
    final enabled = values['alias']?.value.boolean ?? false;
    return wire.PreferenceSnapshot(
      snapshotId: 'preferences-${++descriptions}',
      syncValues: values.values.where(
        (entry) => entry.key != 'password' && entry.key != 'note',
      ),
      sessionValues: values.values.where(
        (entry) => entry.key == 'password' || entry.key == 'note',
      ),
      nodes: [
        wire.PreferenceNode(
          key: 'enabled',
          title: '隐藏付费章节',
          summary: enabled ? '已隐藏付费章节' : '显示全部章节',
          enabled: true,
          visible: true,
          syncScope: accountScope,
          toggle: wire.PreferenceToggle(value: enabled),
        ),
        wire.PreferenceNode(
          key: 'password',
          title: '登录密码',
          summary: '不应回显的密码摘要',
          enabled: true,
          visible: true,
          syncScope: sessionScope,
          text: wire.PreferenceText(
            secret: true,
            value: values['password']?.value.text,
          ),
        ),
        wire.PreferenceNode(
          key: 'choice',
          title: '服务器',
          enabled: true,
          visible: true,
          syncScope: accountScope,
          choice: wire.PreferenceChoice(
            value: missingChoice ? 'gone' : values['choice']?.value.text ?? 'a',
            options: emptyOptions
                ? []
                : [
                    wire.PreferenceOption(label: '服务器甲', value: 'a'),
                    wire.PreferenceOption(label: '服务器乙', value: 'b'),
                  ],
          ),
        ),
        wire.PreferenceNode(
          key: 'multi',
          title: '章节语言',
          enabled: true,
          visible: true,
          syncScope: accountScope,
          multiChoice: wire.PreferenceMultiChoice(
            values: values['multi']?.value.strings.values ?? [],
            options: [
              wire.PreferenceOption(label: '中文', value: 'zh'),
              wire.PreferenceOption(label: '英文', value: 'en'),
            ],
          ),
        ),
        wire.PreferenceNode(
          title: '阅读依赖',
          enabled: true,
          visible: true,
          syncScope: accountScope,
          group: wire.PreferenceGroup(
            nodes: [
              wire.PreferenceNode(
                key: 'dependent',
                title: '合并章节',
                enabled: enabled,
                visible: true,
                syncScope: accountScope,
                toggle: wire.PreferenceToggle(
                  value: values['dependent']?.value.boolean ?? false,
                ),
              ),
              wire.PreferenceNode(
                key: 'note',
                title: '会话备注',
                enabled: true,
                visible: true,
                syncScope: sessionScope,
                text: wire.PreferenceText(
                  value: values['note']?.value.text ?? '原备注',
                  hint: '可填写备注',
                  selectAllOnOpen: true,
                ),
              ),
            ],
          ),
        ),
        wire.PreferenceNode(
          title: '清理来源状态',
          enabled: true,
          visible: true,
          syncScope: sessionScope,
          action: wire.Empty(),
        ),
        wire.PreferenceNode(
          title: '自定义登录页面',
          enabled: false,
          visible: true,
          syncScope: sessionScope,
          unsupported: wire.PreferenceUnsupported(
            reason: '需要 Android Activity，当前不支持。',
          ),
        ),
      ],
    );
  }

  Future<wire.SourceResult> _invoke(wire.SourceCall call) async {
    _readBootstrap();
    if (call.hasGetPreferences()) {
      return wire.SourceResult(preferences: snapshot());
    }
    if (call.hasEditPreference()) {
      callbacks++;
      edits.add(call.editPreference.deepCopy());
      if (editGate != null) return editGate!(call);
      if (failEdit) {
        throw const RuntimeException(
          RuntimeErrorCode.sourceError,
          'Unknown edit response',
        );
      }
      final edit = call.editPreference;
      if (veto) {
        values['dependent'] = preferenceEntry(
          'dependent',
          wire.PreferenceValue(boolean: true),
        );
      } else if (edit.hasChange()) {
        final key = switch (edit.path.join('.')) {
          '0' => 'alias',
          '1' => 'password',
          '2' => 'choice',
          '3' => 'multi',
          '4.0' => 'dependent',
          '4.1' => 'note',
          _ => throw StateError('Unexpected preference path'),
        };
        values[key] = preferenceEntry(key, edit.change.deepCopy());
      }
      return wire.SourceResult(
        preferenceEdit: wire.PreferenceEditResult(
          accepted: !veto && edit.hasChange(),
          clickHandled: edit.hasClick(),
          snapshot: snapshot(),
        ),
      );
    }
    return wire.SourceResult(
      mangaPage: wire.MangaPage(mangas: [testManga], hasNextPage: true),
    );
  }

  SourcePreferencesController editor({bool Function()? isCurrent}) =>
      SourcePreferencesController(
        catalog: catalog,
        repository: repository,
        target:
            catalog.currentPreferencesTarget ??
            catalog.sourcePreferenceRecoveries.single,
        isCurrent: isCurrent ?? () => true,
      );
  void loseNextPreferenceAck() {
    var lost = false;
    platform.afterBusinessReply = (request, reply) {
      if (!lost &&
          request.method == 'POST' &&
          request.uri.path == '/api/source-preferences/mutations') {
        lost = true;
        return const ApiReply(
          status: 502,
          headers: {'content-type': 'application/json'},
          body: '{}',
          redirected: false,
        );
      }
      return reply;
    };
  }

  SourcePreferencesRepository get repository => catalog.sourcePreferences!;
  List<String?> get postedBodies => platform.businessServer.requests
      .where(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/api/source-preferences/mutations',
      )
      .map((request) => request.body)
      .toList();
  BusinessStateClient get business => repository.client;

  Future<void> close() async {
    catalog.dispose();
    await catalog.closeReadingProgress();
    await platform.dispose();
  }
}
