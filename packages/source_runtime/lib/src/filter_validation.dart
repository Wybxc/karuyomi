part of '../control_protocol.dart';

const filterDepthLimit = 8;
const filterNodeLimit = 256;
const filterOptionLimit = 256;
const filterLabelLimit = 512;
const filterTextLimit = 4096;
const filterSnapshotJsonLimit = 256 * 1024;

void _filterRequire(bool valid, String message) {
  if (!valid) throw FormatException(message);
}

void _filterSnapshotId(String value) => _filterRequire(
  value.isNotEmpty && value.length <= 200,
  'Invalid filter snapshot identity',
);

void _filterIndex(int value, [int limit = filterOptionLimit]) => _filterRequire(
  value >= 0 && value < limit,
  'Filter index exceeds its range',
);

void _filterSortState(
  FilterSortState value, [
  int options = filterOptionLimit,
]) {
  if (value.hasSelection()) _filterIndex(value.selection.index, options);
}

void _filterOptions(List<String> values) => _filterRequire(
  values.isNotEmpty &&
      values.length <= filterOptionLimit &&
      values.every((value) => value.length <= filterLabelLimit),
  'Filter options exceed their count or label budget',
);

void validateGetFiltersRequest(GetFiltersRequest value) {
  if (value.hasRetainedSnapshotId()) {
    _filterSnapshotId(value.retainedSnapshotId);
  }
}

void validateFilterSnapshot(FilterSnapshot value) {
  _filterSnapshotId(value.snapshotId);
  var count = 0;
  void visit(List<FilterNode> nodes, int depth) {
    _filterRequire(
      depth <= filterDepthLimit,
      'Filter tree exceeds its depth budget',
    );
    for (final node in nodes) {
      _filterRequire(
        ++count <= filterNodeLimit,
        'Filter tree exceeds its node budget',
      );
      _filterRequire(
        node.name.length <= filterLabelLimit,
        'Filter label exceeds its budget',
      );
      switch (node.whichKind()) {
        case FilterNode_Kind.header ||
            FilterNode_Kind.separator ||
            FilterNode_Kind.checkBox:
          break;
        case FilterNode_Kind.text:
          _filterRequire(
            node.text.state.length <= filterTextLimit,
            'Filter text exceeds its budget',
          );
        case FilterNode_Kind.triState:
          _filterIndex(node.triState.state, 3);
        case FilterNode_Kind.select:
          _filterOptions(node.select.options);
          _filterIndex(node.select.state, node.select.options.length);
        case FilterNode_Kind.sort:
          _filterOptions(node.sort.options);
          _filterRequire(node.sort.hasState(), 'Missing filter sort state');
          _filterSortState(node.sort.state, node.sort.options.length);
        case FilterNode_Kind.group:
          if (node.group.nodes.isNotEmpty) visit(node.group.nodes, depth + 1);
        case FilterNode_Kind.notSet:
          throw const FormatException(
            'A filter node must select a supported kind',
          );
      }
    }
  }

  visit(value.nodes, 1);
  encodeProtoJson(value, maxBytes: filterSnapshotJsonLimit);
}

void validateFilterSelection(FilterSelection value) {
  _filterSnapshotId(value.snapshotId);
  _filterRequire(
    value.updates.length <= filterNodeLimit,
    'Filter updates exceed their count budget',
  );
  final paths = <String>{};
  for (final update in value.updates) {
    _filterRequire(
      update.path.isNotEmpty && update.path.length <= filterDepthLimit,
      'Filter path exceeds its depth budget',
    );
    for (final index in update.path) {
      _filterIndex(index, filterNodeLimit);
    }
    _filterRequire(
      paths.add(jsonEncode(update.path)),
      'Duplicate filter update path',
    );
    switch (update.whichState()) {
      case FilterUpdate_State.text:
        _filterRequire(
          update.text.length <= filterTextLimit,
          'Filter text exceeds its budget',
        );
      case FilterUpdate_State.checkBox:
        break;
      case FilterUpdate_State.triState:
        _filterIndex(update.triState, 3);
      case FilterUpdate_State.select:
        _filterIndex(update.select);
      case FilterUpdate_State.sort:
        _filterSortState(update.sort);
      case FilterUpdate_State.notSet:
        throw const FormatException(
          'A filter update must select an editable state',
        );
    }
  }
  encodeProtoJson(value, maxBytes: controlRequestLimit);
}
