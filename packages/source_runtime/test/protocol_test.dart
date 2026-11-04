import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:test/test.dart';

void main() {
  test('generated hello still requires the current protocol and host ABI', () {
    expect(
      isCompatibleHost(
        wire.RuntimeHello(protocolVersion: protocolVersion, hostAbi: hostAbi),
      ),
      true,
    );
    expect(
      isCompatibleHost(
        wire.RuntimeHello(protocolVersion: 999, hostAbi: hostAbi),
      ),
      false,
    );
    expect(
      isCompatibleHost(
        wire.RuntimeHello(protocolVersion: protocolVersion, hostAbi: 'unknown'),
      ),
      false,
    );
  });

  test('standard ProtoJSON retains optional false, null and opaque IDs', () {
    final absent = wire.decodeProtoJson(wire.SourceInfo(), {
      'id': '9223372036854775806',
      'supportsLatest': null,
    });
    final explicit = wire.decodeProtoJson(wire.SourceInfo(), {
      'id': '9223372036854775806',
      'supportsLatest': false,
    });
    expect(absent.hasSupportsLatest(), false);
    expect(explicit.hasSupportsLatest(), true);
    expect(wire.encodeProtoJson(explicit), {
      'id': '9223372036854775806',
      'supportsLatest': false,
    });
    expect(
      wire.decodeProtoJson(wire.Chapter(), {
        'dateUpload': '9223372036854775806',
      }).dateUpload,
      '9223372036854775806',
    );
  });

  test(
    'generated descriptors reject nested oneof conflicts and field aliases',
    () {
      for (final json in [
        {
          'requestId': 'c',
          'ready': <String, Object?>{},
          'dispose': <String, Object?>{},
        },
        {
          'requestId': 'c',
          'invoke': {
            'popular': {'page': 1},
            'latest': {'page': 1},
          },
        },
        {
          'requestId': 'c',
          'invoke': {
            'pages': {
              'chapter': {'dateUpload': '0', 'date_upload': '1'},
            },
          },
        },
      ]) {
        expect(
          () => wire.decodeProtoJson(wire.ControlRequest(), json),
          throwsFormatException,
        );
      }
    },
  );

  test('unknown fields and enum names fail official ProtoJSON decoding', () {
    expect(
      () => wire.decodeProtoJson(wire.ControlRequest(), {'future': true}),
      throwsFormatException,
    );
    expect(
      () => wire.decodeProtoJson(wire.RuntimeError(), {'code': 'FUTURE_ERROR'}),
      throwsFormatException,
    );
    expect(
      () => wire.decodeProtoJson(wire.ImageResource(), {'byteLength': 1.5}),
      throwsFormatException,
    );
  });

  test(
    'opaque memo validates its JSON object without rewriting numeric text',
    () {
      expect(
        () => wire.checkSourceMemo('{"n":9223372036854775806,"big":1e1000}'),
        returnsNormally,
      );
      for (final invalid in [
        '[]',
        'null',
        '{',
        '{"value":"${'x' * wire.sourceMemoLimit}"}',
      ]) {
        expect(() => wire.checkSourceMemo(invalid), throwsFormatException);
      }
      Object nested = 0;
      for (var i = 0; i < 65; i++) {
        nested = [nested];
      }
      expect(() => wire.checkJsonBudget(nested), throwsFormatException);
    },
  );
}
