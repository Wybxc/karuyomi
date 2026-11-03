import 'package:source_runtime/source_runtime.dart';
import 'package:test/test.dart';

void main() {
  test('rejects protocol and host ABI mismatches', () {
    expect(
      isCompatibleHost({
        'protocolVersion': protocolVersion,
        'hostAbi': hostAbi,
      }),
      isTrue,
    );
    expect(
      isCompatibleHost({'protocolVersion': 999, 'hostAbi': hostAbi}),
      isFalse,
    );
    expect(
      isCompatibleHost({
        'protocolVersion': protocolVersion,
        'hostAbi': 'unknown',
      }),
      isFalse,
    );
  });
}
