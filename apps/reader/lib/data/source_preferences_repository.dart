import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_client.dart';
import 'reading_progress.dart';

final class SourcePreferencesSnapshot {
  SourcePreferencesSnapshot(wire.SourcePreferencesResponse value)
    : catalog = value.catalog.deepCopy()..freeze(),
      syncRules = List.unmodifiable(
        value.syncRules.map((rule) => rule.deepCopy()..freeze()),
      ),
      packageName = value.packageName,
      accountRevision = value.accountRevision,
      sources = List.unmodifiable(
        value.sources.map((source) => source.deepCopy()..freeze()),
      );
  final wire.CatalogReference catalog;
  final List<wire.PreferenceSyncRule> syncRules;
  final String packageName;
  final int accountRevision;
  final List<wire.SourcePreferences> sources;

  wire.SourcePreferences source(String sourceId) => sources.firstWhere(
    (source) => source.sourceId == sourceId,
    orElse: () =>
        wire.SourcePreferences(packageName: packageName, sourceId: sourceId)
          ..freeze(),
  );
}

final class SourcePreferencesDraft {
  SourcePreferencesDraft(wire.SourcePreferencesMutation value, this.retryable)
    : request = value.deepCopy()..freeze();
  final wire.SourcePreferencesMutation request;
  final bool retryable;
}

/// The identity-bound business client owns the exact pending request, so a
/// sheet or a replacement repository can only explicitly retry that request.
final class SourcePreferencesRepository {
  SourcePreferencesRepository(this.client);
  final BusinessStateClient client;
  ProgressIdentity get identity => client.identity;

  SourcePreferencesDraft? pending(
    String packageName,
    String sourceId, {
    required wire.CatalogReference catalog,
  }) {
    final value = client.pendingSourcePreferences(
      packageName,
      sourceId,
      catalog: catalog,
    );
    return value == null
        ? null
        : SourcePreferencesDraft(value.request, value.retryable);
  }

  bool hasPendingPackage(
    String packageName, {
    required wire.CatalogReference catalog,
  }) => client.hasPendingSourcePreferences(packageName, catalog: catalog);

  Future<SourcePreferencesSnapshot> load(
    String packageName, {
    required wire.CatalogReference catalog,
  }) async => SourcePreferencesSnapshot(
    await client.readSourcePreferences(packageName, catalog: catalog),
  );

  Future<SourcePreferencesSnapshot> save({
    required wire.CatalogReference catalog,
    required String packageName,
    required String sourceId,
    required int basedOnRevision,
    required List<wire.PreferenceEntry> entries,
  }) async => SourcePreferencesSnapshot(
    await client.mutateSourcePreferences(
      wire.SourcePreferencesMutation(
        catalog: catalog,
        packageName: packageName,
        sourceId: sourceId,
        expectedRevision: basedOnRevision,
        entries: entries,
      ),
    ),
  );

  Future<SourcePreferencesSnapshot> retry(
    String packageName,
    String sourceId, {
    required wire.CatalogReference catalog,
  }) async => SourcePreferencesSnapshot(
    await client.retrySourcePreferences(
      packageName,
      sourceId,
      catalog: catalog,
    ),
  );

  /// Reading current server values does not undo a request that may have
  /// committed. It only abandons this session's uncertain draft explicitly.
  Future<SourcePreferencesSnapshot> discard(
    String packageName,
    String sourceId, {
    required wire.CatalogReference catalog,
  }) async => SourcePreferencesSnapshot(
    await client.discardSourcePreferences(
      packageName,
      sourceId,
      catalog: catalog,
    ),
  );
}
