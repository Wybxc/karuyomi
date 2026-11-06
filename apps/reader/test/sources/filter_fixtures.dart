import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

wire.FilterSnapshot filterSnapshot(String id) => wire.FilterSnapshot(
  snapshotId: id,
  nodes: [
    wire.FilterNode(name: '作品条件', header: wire.Empty()),
    wire.FilterNode(
      name: '作者',
      text: wire.FilterText(state: ''),
    ),
    wire.FilterNode(name: '仅有译本', checkBox: wire.FilterCheckBox(state: false)),
    wire.FilterNode(name: '冒险', triState: wire.FilterTriState(state: 0)),
    wire.FilterNode(
      name: '连载状态',
      select: wire.FilterSelect(options: ['全部状态', '连载', '完结'], state: 0),
    ),
    wire.FilterNode(
      name: '排序方式',
      sort: wire.FilterSort(
        options: ['更新时间', '作品名称'],
        state: wire.FilterSortState(
          selection: wire.FilterSortSelection(index: 0, ascending: false),
        ),
      ),
    ),
    wire.FilterNode(
      name: '更多条件',
      group: wire.FilterGroup(
        nodes: [
          wire.FilterNode(
            name: '包含短篇',
            checkBox: wire.FilterCheckBox(state: false),
          ),
        ],
      ),
    ),
    wire.FilterNode(separator: wire.Empty()),
  ],
);

wire.FilterSelection filterSelection(
  String id, {
  String text = '',
  bool check = false,
  int tri = 0,
  int select = 0,
  int? sortIndex,
  bool ascending = true,
  bool nested = false,
}) => wire.FilterSelection(
  snapshotId: id,
  updates: [
    wire.FilterUpdate(path: [1], text: text),
    wire.FilterUpdate(path: [2], checkBox: check),
    wire.FilterUpdate(path: [3], triState: tri),
    wire.FilterUpdate(path: [4], select: select),
    wire.FilterUpdate(
      path: [5],
      sort: wire.FilterSortState(
        selection: sortIndex == null
            ? null
            : wire.FilterSortSelection(index: sortIndex, ascending: ascending),
      ),
    ),
    wire.FilterUpdate(path: [6, 0], checkBox: nested),
  ],
);

/// The real manager retires its generation when an active Source request is
/// cancelled. Return its actual control error through the Dart transport, so
/// tests exercise event delivery instead of manually injecting container loss.
final class FilterRuntimeTransport implements RuntimeTransport {
  FilterRuntimeTransport(this.delegate);
  final RuntimeTransport delegate;

  @override
  Future<Object?> control(Map<String, Object?> json) async {
    final request = wire.decodeProtoJson(wire.ControlRequest(), json);
    final reply = await delegate.control(json);
    if (request.whichCommand() != wire.ControlRequest_Command.cancel) {
      return reply;
    }
    return wire.encodeProtoJson(
      wire.ControlResponse(
        requestId: request.requestId,
        error: wire.RuntimeError(
          code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST,
          message: 'Active Source cancellation retired its worker',
        ),
      ),
    );
  }
}
