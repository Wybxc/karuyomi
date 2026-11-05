/// Generated control models and the standard ProtoJSON boundary codec.
library;

import 'dart:convert';
import 'package:protobuf/protobuf.dart';

export 'src/pb/karuyomi/v1/control.pb.dart';
export 'src/pb/karuyomi/v1/business.pb.dart';

const controlJsonLimit = 8 * 1024 * 1024;
const controlRequestLimit = 128 * 1024;
const sourceMemoLimit = 64 * 1024;
const controlJsonDepthLimit = 64;
const imageByteLimit = 64 * 1024 * 1024;
const imageResourceLimit = 6;

/// Checks transport budgets, without duplicating the generated field schema.
void _checkJsonNesting(Object? value) {
  final pending = <(Object?, int)>[(value, 0)];
  while (pending.isNotEmpty) {
    final (item, depth) = pending.removeLast();
    if (depth > controlJsonDepthLimit) {
      throw const FormatException('Control JSON nesting exceeds its budget');
    }
    if (item is Map) {
      for (final entry in item.entries) {
        if (entry.key is! String) {
          throw const FormatException(
            'Control JSON object keys must be strings',
          );
        }
        pending.add((entry.value, depth + 1));
      }
    } else if (item is List) {
      pending.addAll(item.map((child) => (child, depth + 1)));
    }
  }
}

void checkJsonBudget(Object? value, {int maxBytes = controlJsonLimit}) {
  _checkJsonNesting(value);
  try {
    if (utf8.encode(jsonEncode(value)).length > maxBytes) {
      throw const FormatException('Control JSON exceeds its byte budget');
    }
  } on JsonUnsupportedObjectError {
    throw const FormatException('Control payload is not valid JSON');
  }
}

T decodeProtoJson<T extends GeneratedMessage>(
  T message,
  Object? value, {
  int maxBytes = controlJsonLimit,
}) {
  if (value is! Map) {
    throw const FormatException('Expected a ProtoJSON object');
  }
  checkJsonBudget(value, maxBytes: maxBytes);
  _checkOneofFields(message, value);
  message.mergeFromProto3Json(value);
  return message;
}

// The Dart runtime accepts last-one-wins ProtoJSON oneofs. The control boundary
// requires one explicit command/result, matching Protobuf-ES. Reflect generated
// descriptors rather than maintaining another list of protocol fields.
void _checkOneofFields(GeneratedMessage message, Map<Object?, Object?> value) {
  final fields = <String, FieldInfo<Object?>>{};
  for (final field in message.info_.fieldInfo.values) {
    fields[field.name] = field;
    fields[field.protoName] = field;
  }
  final seenFields = <int>{};
  final seenOneofs = <int>{};
  for (final entry in value.entries) {
    final field = fields[entry.key];
    if (field == null || entry.value == null) continue;
    final oneof = message.info_.oneofs[field.tagNumber];
    if (!seenFields.add(field.tagNumber) ||
        (oneof != null && !seenOneofs.add(oneof))) {
      throw const FormatException('Conflicting ProtoJSON field or oneof');
    }
    final builder = field.subBuilder;
    if (builder != null) {
      if (field.isRepeated && entry.value is List) {
        for (final child in entry.value as List) {
          if (child is Map) _checkOneofFields(builder(), child);
        }
      } else if (entry.value is Map) {
        _checkOneofFields(builder(), entry.value as Map);
      }
    }
  }
}

Map<String, Object?> encodeProtoJson(
  GeneratedMessage message, {
  int maxBytes = controlRequestLimit,
}) {
  final value = message.toProto3Json();
  checkJsonBudget(value, maxBytes: maxBytes);
  return Map<String, Object?>.from(value as Map);
}

/// Validate opaque Source JSON without decoding and rewriting its numeric text.
void checkSourceMemo(String value) {
  if (utf8.encode(value).length > sourceMemoLimit) {
    throw const FormatException('Source memo exceeds its byte budget');
  }
  final decoded = jsonDecode(value);
  if (decoded is! Map) {
    throw const FormatException('Source memo must contain a JSON object');
  }
  _checkJsonNesting(decoded);
}
