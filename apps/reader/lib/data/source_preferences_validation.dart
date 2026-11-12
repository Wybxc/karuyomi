import 'dart:convert';

import 'package:source_runtime/control_protocol.dart' as wire;

import 'business_state_validation.dart';

void validateSourcePreferencesIdentity(String packageName, [String? sourceId]) {
  wire.validatePreferencePackageName(packageName);
  if (sourceId != null) {
    final value = BigInt.tryParse(sourceId);
    if (!RegExp(r'^-?\d{1,19}$').hasMatch(sourceId) ||
        value == null ||
        value < BigInt.parse('-9223372036854775808') ||
        value > BigInt.parse('9223372036854775807')) {
      throw const FormatException('Invalid Source preference identity');
    }
  }
}

void validateSourcePreferences(
  wire.SourcePreferences value,
  String packageName,
) {
  validateSourcePreferencesIdentity(value.packageName, value.sourceId);
  if (value.packageName != packageName) {
    throw const FormatException('Source preference package mismatch');
  }
  validateBusinessRevision(value.revision);
  wire.validatePreferenceEntries(value.entries);
}

void validateSourcePreferencesResponse(
  wire.SourcePreferencesResponse value,
  String packageName, {
  required wire.CatalogReference catalog,
}) {
  validateBusinessCatalogReference(catalog);
  if (!value.hasCatalog() || value.catalog != catalog) {
    throw const FormatException('Source preference repository mismatch');
  }
  if (value.schemaVersion != 1 || value.packageName != packageName) {
    throw const FormatException('Source preference response identity mismatch');
  }
  validateBusinessRevision(value.accountRevision);
  wire.validatePreferenceSyncRules(value.syncRules);
  if (value.sources.length > 64 ||
      value.sources.map((source) => source.sourceId).toSet().length !=
          value.sources.length ||
      value.sources.fold<int>(
            0,
            (sum, source) =>
                sum +
                utf8
                    .encode(
                      jsonEncode(
                        source.entries
                            .map((entry) => wire.encodeProtoJson(entry))
                            .toList(),
                      ),
                    )
                    .length,
          ) >
          64 * 1024 ||
      utf8.encode(jsonEncode(wire.encodeProtoJson(value))).length >
          128 * 1024) {
    throw const FormatException('Source preference package exceeds budget');
  }
  for (final source in value.sources) {
    validateSourcePreferences(source, packageName);
  }
}

List<wire.PreferenceEntry> canonicalPreferenceEntries(
  Iterable<wire.PreferenceEntry> values,
) {
  final entries = values.map((entry) => entry.deepCopy()).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final entry in entries) {
    if (entry.value.hasStrings()) entry.value.strings.values.sort();
  }
  return entries;
}

bool samePreferenceEntries(
  Iterable<wire.PreferenceEntry> a,
  Iterable<wire.PreferenceEntry> b,
) {
  final left = canonicalPreferenceEntries(a);
  final right = canonicalPreferenceEntries(b);
  return left.length == right.length &&
      Iterable<int>.generate(left.length)
          .every((index) => left[index] == right[index]);
}
