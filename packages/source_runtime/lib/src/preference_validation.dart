part of '../control_protocol.dart';

const preferenceDepthLimit = 8;
const preferenceNodeLimit = 256;
const preferenceOptionLimit = 256;
const preferenceKeyLimit = 200;
const preferenceLabelLimit = 512;
const preferenceSummaryLimit = 2048;
const preferenceTextLimit = 4096;
const preferenceEntryLimit = 128;
const preferenceValuesLimit = 32 * 1024;
const preferenceBootstrapLimit = 128 * 1024;
const preferenceSnapshotLimit = 256 * 1024;

void _preferenceRequire(bool valid, String message) {
  if (!valid) throw FormatException(message);
}

void _preferenceKey(String value) => _preferenceRequire(
  value.isNotEmpty && value.length <= preferenceKeyLimit,
  'Invalid preference storage key',
);

void _preferenceText(String value) => _preferenceRequire(
  value.length <= preferenceTextLimit,
  'Preference text exceeds its budget',
);

void _preferenceStrings(List<String> values) {
  _preferenceRequire(
    values.length <= preferenceOptionLimit &&
        values.toSet().length == values.length,
    'Preference string set must be bounded and unique',
  );
  values.forEach(_preferenceText);
}

// fixnum parsing wraps overflowing decimal text. Reject it before the generated
// codec can change its value; the control contract carries longs as decimal strings.
void _checkPreferenceValueJson(Map<Object?, Object?> value) {
  final raw = value['longInteger'] ?? value['long_integer'];
  if (raw == null) return;
  final number = raw is String && RegExp(r'^-?(0|[1-9]\d*)$').hasMatch(raw)
      ? BigInt.tryParse(raw)
      : null;
  _preferenceRequire(
    number != null &&
        number >= BigInt.parse('-9223372036854775808') &&
        number <= BigInt.parse('9223372036854775807'),
    'Preference long integer must be an int64 decimal string',
  );
}

void validatePreferenceValue(PreferenceValue value) {
  switch (value.whichValue()) {
    case PreferenceValue_Value.boolean:
      break;
    case PreferenceValue_Value.text:
      _preferenceText(value.text);
    case PreferenceValue_Value.integer:
      _preferenceRequire(
        value.integer >= -2147483648 && value.integer <= 2147483647,
        'Preference integer exceeds int32',
      );
    case PreferenceValue_Value.longInteger:
      // The generated fixnum field preserves signed int64 without a JS number.
      break;
    case PreferenceValue_Value.decimal:
      _preferenceRequire(
        value.decimal.isFinite && value.decimal.abs() <= 3.4028234663852886e38,
        'Preference decimal must be a finite float',
      );
    case PreferenceValue_Value.strings:
      _preferenceStrings(value.strings.values);
    case PreferenceValue_Value.notSet:
      throw const FormatException(
        'A preference storage value must select its type',
      );
  }
}

void validatePreferenceEntries(
  List<PreferenceEntry> values, {
  int maximumBytes = preferenceValuesLimit,
}) {
  _preferenceRequire(
    values.length <= preferenceEntryLimit &&
        values.map((entry) => entry.key).toSet().length == values.length,
    'Preference entries must be bounded and unique',
  );
  for (final entry in values) {
    _preferenceKey(entry.key);
    _preferenceRequire(entry.hasValue(), 'Preference value is required');
    validatePreferenceValue(entry.value);
  }
  checkJsonBudget(
    values.map((entry) => entry.toProto3Json()).toList(),
    maxBytes: maximumBytes,
  );
}

void _preferenceSourceId(String value) {
  final number = BigInt.tryParse(value);
  _preferenceRequire(
    RegExp(r'^-?\d{1,19}$').hasMatch(value) &&
        number != null &&
        number >= BigInt.parse('-9223372036854775808') &&
        number <= BigInt.parse('9223372036854775807'),
    'Invalid preference Source identity',
  );
}

void validatePreferenceSyncRules(List<PreferenceSyncRule> rules) {
  _preferenceRequire(
    rules.length <= preferenceEntryLimit,
    'Too many preference sync rules',
  );
  final identities = <(String, String?)>{};
  for (final rule in rules) {
    _preferenceKey(rule.key);
    final sourceId = rule.hasSourceId() ? rule.sourceId : null;
    if (sourceId != null) _preferenceSourceId(sourceId);
    _preferenceRequire(
      rule.kind != PreferenceValueKind.PREFERENCE_VALUE_KIND_UNSPECIFIED &&
          identities.add((rule.key, sourceId)),
      'Invalid or duplicate preference sync rule',
    );
  }
}

void validatePreferenceBootstrap(PreferenceBootstrap value) {
  _preferenceRequire(
    RegExp(r'^eu\.kanade\.[A-Za-z0-9_.]+$').hasMatch(value.packageName) &&
        value.packageName.length <= 200,
    'Invalid preference package identity',
  );
  validatePreferenceSyncRules(value.syncRules);
  _preferenceRequire(
    value.sources.length <= 64 &&
        value.sources.map((source) => source.sourceId).toSet().length ==
            value.sources.length,
    'Preference bootstrap Sources must be bounded and unique',
  );
  var bytes = 0;
  for (final source in value.sources) {
    _preferenceSourceId(source.sourceId);
    validatePreferenceEntries(source.entries);
    bytes += utf8
        .encode(
          jsonEncode(
            source.entries.map((entry) => entry.toProto3Json()).toList(),
          ),
        )
        .length;
  }
  _preferenceRequire(
    bytes <= 64 * 1024,
    'Preference bootstrap exceeds its values budget',
  );
  encodeProtoJson(value, maxBytes: preferenceBootstrapLimit);
}

void _preferenceOptions(List<PreferenceOption> values) {
  _preferenceRequire(
    values.length <= preferenceOptionLimit &&
        values.map((option) => option.value).toSet().length == values.length,
    'Preference options must be bounded and unique',
  );
  for (final option in values) {
    _preferenceRequire(
      option.label.length <= preferenceLabelLimit,
      'Preference option label exceeds its budget',
    );
    _preferenceText(option.value);
  }
}

void validatePreferenceSnapshot(PreferenceSnapshot value) {
  _preferenceKey(value.snapshotId);
  validatePreferenceEntries([...value.syncValues, ...value.sessionValues]);
  var count = 0;
  void visit(List<PreferenceNode> nodes, int depth) {
    _preferenceRequire(
      depth <= preferenceDepthLimit,
      'Preference tree exceeds its depth budget',
    );
    for (final node in nodes) {
      _preferenceRequire(
        ++count <= preferenceNodeLimit,
        'Preference tree exceeds its node budget',
      );
      _preferenceRequire(
        node.key.length <= preferenceKeyLimit &&
            node.title.length <= preferenceLabelLimit &&
            node.summary.length <= preferenceSummaryLimit,
        'Preference description exceeds its text budget',
      );
      _preferenceRequire(
        node.syncScope ==
                PreferenceSyncScope.PREFERENCE_SYNC_SCOPE_CLIENT_SESSION ||
            node.syncScope == PreferenceSyncScope.PREFERENCE_SYNC_SCOPE_ACCOUNT,
        'Preference synchronization scope is required',
      );
      if (node.hasDefaultValue()) validatePreferenceValue(node.defaultValue);
      PreferenceValue_Value? expectedDefault;
      switch (node.whichKind()) {
        case PreferenceNode_Kind.toggle:
          expectedDefault = PreferenceValue_Value.boolean;
          _preferenceKey(node.key);
        case PreferenceNode_Kind.text:
          expectedDefault = PreferenceValue_Value.text;
          _preferenceKey(node.key);
          if (node.text.hasValue()) _preferenceText(node.text.value);
          if (node.text.hasHint()) {
            _preferenceRequire(
              !node.text.secret &&
                  utf8.encode(node.text.hint).length <= preferenceLabelLimit,
              'Preference input hint is secret or exceeds its text budget',
            );
          }
          _preferenceRequire(
            !node.text.secret ||
                node.syncScope ==
                    PreferenceSyncScope.PREFERENCE_SYNC_SCOPE_CLIENT_SESSION,
            'Secret preferences cannot use account synchronization',
          );
        case PreferenceNode_Kind.choice:
          expectedDefault = PreferenceValue_Value.text;
          _preferenceKey(node.key);
          _preferenceOptions(node.choice.options);
          if (node.choice.hasValue()) _preferenceText(node.choice.value);
        case PreferenceNode_Kind.multiChoice:
          expectedDefault = PreferenceValue_Value.strings;
          _preferenceKey(node.key);
          _preferenceOptions(node.multiChoice.options);
          _preferenceStrings(node.multiChoice.values);
        case PreferenceNode_Kind.group:
          if (node.group.nodes.isNotEmpty) visit(node.group.nodes, depth + 1);
        case PreferenceNode_Kind.action:
          break;
        case PreferenceNode_Kind.unsupported:
          _preferenceRequire(
            node.unsupported.reason.isNotEmpty &&
                node.unsupported.reason.length <= preferenceSummaryLimit,
            'Unsupported preference requires a bounded explanation',
          );
        case PreferenceNode_Kind.notSet:
          throw const FormatException('A preference node must select a kind');
      }
      if (node.hasDefaultValue() && expectedDefault != null) {
        _preferenceRequire(
          node.defaultValue.whichValue() == expectedDefault,
          'Preference default has the wrong type',
        );
      }
    }
  }

  visit(value.nodes, 1);
  encodeProtoJson(value, maxBytes: preferenceSnapshotLimit);
}

void validatePreferenceEditRequest(PreferenceEditRequest value) {
  _preferenceKey(value.snapshotId);
  _preferenceRequire(
    value.path.isNotEmpty &&
        value.path.length <= preferenceDepthLimit &&
        value.path.every((part) => part >= 0 && part < preferenceNodeLimit),
    'Preference edit path exceeds its budget',
  );
  switch (value.whichCommand()) {
    case PreferenceEditRequest_Command.change:
      validatePreferenceValue(value.change);
    case PreferenceEditRequest_Command.click:
      break;
    case PreferenceEditRequest_Command.notSet:
      throw const FormatException(
        'A preference edit must select change or click',
      );
  }
  encodeProtoJson(value);
}

void validatePreferenceEditResult(PreferenceEditResult value) {
  _preferenceRequire(
    value.hasSnapshot(),
    'Preference edit snapshot is required',
  );
  validatePreferenceSnapshot(value.snapshot);
}
