part of '../source_runtime.dart';

final _extensionControlId = RegExp(r'^[a-zA-Z0-9._-]{1,200}$');
final _extensionDigest = RegExp(r'^[a-f0-9]{64}$');

void _extensionRequire(bool condition, String message) {
  if (!condition) throw FormatException(message);
}
