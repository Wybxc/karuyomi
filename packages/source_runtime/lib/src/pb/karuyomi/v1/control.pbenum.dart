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
  ];

  static final $core.List<RuntimeErrorCode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 10);
  static RuntimeErrorCode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const RuntimeErrorCode._(super.value, super.name);
}

class ImageWindowState extends $pb.ProtobufEnum {
  static const ImageWindowState IMAGE_WINDOW_STATE_UNSPECIFIED =
      ImageWindowState._(
          0, _omitEnumNames ? '' : 'IMAGE_WINDOW_STATE_UNSPECIFIED');
  static const ImageWindowState IMAGE_WINDOW_STATE_PENDING =
      ImageWindowState._(1, _omitEnumNames ? '' : 'IMAGE_WINDOW_STATE_PENDING');
  static const ImageWindowState IMAGE_WINDOW_STATE_COMPLETE =
      ImageWindowState._(
          2, _omitEnumNames ? '' : 'IMAGE_WINDOW_STATE_COMPLETE');
  static const ImageWindowState IMAGE_WINDOW_STATE_FAILED =
      ImageWindowState._(3, _omitEnumNames ? '' : 'IMAGE_WINDOW_STATE_FAILED');

  static const $core.List<ImageWindowState> values = <ImageWindowState>[
    IMAGE_WINDOW_STATE_UNSPECIFIED,
    IMAGE_WINDOW_STATE_PENDING,
    IMAGE_WINDOW_STATE_COMPLETE,
    IMAGE_WINDOW_STATE_FAILED,
  ];

  static final $core.List<ImageWindowState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ImageWindowState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ImageWindowState._(super.value, super.name);
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
