// This is a generated file - do not edit.
//
// Generated from karuyomi/v1/control.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class RuntimeErrorCode extends $pb.ProtobufEnum {
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_UNSPECIFIED =
      RuntimeErrorCode._(
          0, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_UNSPECIFIED');
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_CANCELLED =
      RuntimeErrorCode._(
          1, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_CANCELLED');
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_TIMEOUT =
      RuntimeErrorCode._(2, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_TIMEOUT');
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_ACCESS_REQUIRED =
      RuntimeErrorCode._(
          3, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_ACCESS_REQUIRED');
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_ACCESS_DENIED =
      RuntimeErrorCode._(
          4, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_ACCESS_DENIED');
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_SOURCE_ERROR =
      RuntimeErrorCode._(
          5, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_SOURCE_ERROR');
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_UNSUPPORTED_CAPABILITY =
      RuntimeErrorCode._(
          6, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_UNSUPPORTED_CAPABILITY');
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_RUNTIME_LOST =
      RuntimeErrorCode._(
          7, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_RUNTIME_LOST');
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_PROTOCOL_ERROR =
      RuntimeErrorCode._(
          8, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_PROTOCOL_ERROR');
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_INTEGRITY_ERROR =
      RuntimeErrorCode._(
          9, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_INTEGRITY_ERROR');
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_LIMIT_EXCEEDED =
      RuntimeErrorCode._(
          10, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_LIMIT_EXCEEDED');
  static const RuntimeErrorCode RUNTIME_ERROR_CODE_STORAGE_BUSY =
      RuntimeErrorCode._(
          11, _omitEnumNames ? '' : 'RUNTIME_ERROR_CODE_STORAGE_BUSY');

  static const $core.List<RuntimeErrorCode> values = <RuntimeErrorCode>[
    RUNTIME_ERROR_CODE_UNSPECIFIED,
    RUNTIME_ERROR_CODE_CANCELLED,
    RUNTIME_ERROR_CODE_TIMEOUT,
    RUNTIME_ERROR_CODE_ACCESS_REQUIRED,
    RUNTIME_ERROR_CODE_ACCESS_DENIED,
    RUNTIME_ERROR_CODE_SOURCE_ERROR,
    RUNTIME_ERROR_CODE_UNSUPPORTED_CAPABILITY,
    RUNTIME_ERROR_CODE_RUNTIME_LOST,
    RUNTIME_ERROR_CODE_PROTOCOL_ERROR,
    RUNTIME_ERROR_CODE_INTEGRITY_ERROR,
    RUNTIME_ERROR_CODE_LIMIT_EXCEEDED,
    RUNTIME_ERROR_CODE_STORAGE_BUSY,
  ];

  static final $core.List<RuntimeErrorCode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 11);
  static RuntimeErrorCode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RuntimeErrorCode._(super.value, super.name);
}

class PreferenceValueKind extends $pb.ProtobufEnum {
  static const PreferenceValueKind PREFERENCE_VALUE_KIND_UNSPECIFIED =
      PreferenceValueKind._(
          0, _omitEnumNames ? '' : 'PREFERENCE_VALUE_KIND_UNSPECIFIED');
  static const PreferenceValueKind PREFERENCE_VALUE_KIND_BOOLEAN =
      PreferenceValueKind._(
          1, _omitEnumNames ? '' : 'PREFERENCE_VALUE_KIND_BOOLEAN');
  static const PreferenceValueKind PREFERENCE_VALUE_KIND_TEXT =
      PreferenceValueKind._(
          2, _omitEnumNames ? '' : 'PREFERENCE_VALUE_KIND_TEXT');
  static const PreferenceValueKind PREFERENCE_VALUE_KIND_INTEGER =
      PreferenceValueKind._(
          3, _omitEnumNames ? '' : 'PREFERENCE_VALUE_KIND_INTEGER');
  static const PreferenceValueKind PREFERENCE_VALUE_KIND_DECIMAL =
      PreferenceValueKind._(
          4, _omitEnumNames ? '' : 'PREFERENCE_VALUE_KIND_DECIMAL');
  static const PreferenceValueKind PREFERENCE_VALUE_KIND_STRINGS =
      PreferenceValueKind._(
          5, _omitEnumNames ? '' : 'PREFERENCE_VALUE_KIND_STRINGS');
  static const PreferenceValueKind PREFERENCE_VALUE_KIND_LONG_INTEGER =
      PreferenceValueKind._(
          6, _omitEnumNames ? '' : 'PREFERENCE_VALUE_KIND_LONG_INTEGER');

  static const $core.List<PreferenceValueKind> values = <PreferenceValueKind>[
    PREFERENCE_VALUE_KIND_UNSPECIFIED,
    PREFERENCE_VALUE_KIND_BOOLEAN,
    PREFERENCE_VALUE_KIND_TEXT,
    PREFERENCE_VALUE_KIND_INTEGER,
    PREFERENCE_VALUE_KIND_DECIMAL,
    PREFERENCE_VALUE_KIND_STRINGS,
    PREFERENCE_VALUE_KIND_LONG_INTEGER,
  ];

  static final $core.List<PreferenceValueKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static PreferenceValueKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PreferenceValueKind._(super.value, super.name);
}

class PreferenceSyncScope extends $pb.ProtobufEnum {
  static const PreferenceSyncScope PREFERENCE_SYNC_SCOPE_UNSPECIFIED =
      PreferenceSyncScope._(
          0, _omitEnumNames ? '' : 'PREFERENCE_SYNC_SCOPE_UNSPECIFIED');
  static const PreferenceSyncScope PREFERENCE_SYNC_SCOPE_CLIENT_SESSION =
      PreferenceSyncScope._(
          1, _omitEnumNames ? '' : 'PREFERENCE_SYNC_SCOPE_CLIENT_SESSION');
  static const PreferenceSyncScope PREFERENCE_SYNC_SCOPE_ACCOUNT =
      PreferenceSyncScope._(
          2, _omitEnumNames ? '' : 'PREFERENCE_SYNC_SCOPE_ACCOUNT');

  static const $core.List<PreferenceSyncScope> values = <PreferenceSyncScope>[
    PREFERENCE_SYNC_SCOPE_UNSPECIFIED,
    PREFERENCE_SYNC_SCOPE_CLIENT_SESSION,
    PREFERENCE_SYNC_SCOPE_ACCOUNT,
  ];

  static final $core.List<PreferenceSyncScope?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static PreferenceSyncScope? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PreferenceSyncScope._(super.value, super.name);
}

class BootstrapStage extends $pb.ProtobufEnum {
  static const BootstrapStage BOOTSTRAP_STAGE_UNSPECIFIED =
      BootstrapStage._(0, _omitEnumNames ? '' : 'BOOTSTRAP_STAGE_UNSPECIFIED');
  static const BootstrapStage BOOTSTRAP_STAGE_SCAFFOLD =
      BootstrapStage._(1, _omitEnumNames ? '' : 'BOOTSTRAP_STAGE_SCAFFOLD');
  static const BootstrapStage BOOTSTRAP_STAGE_P0 =
      BootstrapStage._(2, _omitEnumNames ? '' : 'BOOTSTRAP_STAGE_P0');

  static const $core.List<BootstrapStage> values = <BootstrapStage>[
    BOOTSTRAP_STAGE_UNSPECIFIED,
    BOOTSTRAP_STAGE_SCAFFOLD,
    BOOTSTRAP_STAGE_P0,
  ];

  static final $core.List<BootstrapStage?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static BootstrapStage? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const BootstrapStage._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
