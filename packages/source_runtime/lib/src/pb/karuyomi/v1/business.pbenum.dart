// This is a generated file - do not edit.
//
// Generated from karuyomi/v1/business.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class BusinessStateErrorCode extends $pb.ProtobufEnum {
  static const BusinessStateErrorCode BUSINESS_STATE_ERROR_CODE_UNSPECIFIED =
      BusinessStateErrorCode._(
          0, _omitEnumNames ? '' : 'BUSINESS_STATE_ERROR_CODE_UNSPECIFIED');
  static const BusinessStateErrorCode BUSINESS_STATE_ERROR_CODE_INVALID_INPUT =
      BusinessStateErrorCode._(
          1, _omitEnumNames ? '' : 'BUSINESS_STATE_ERROR_CODE_INVALID_INPUT');
  static const BusinessStateErrorCode
      BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT = BusinessStateErrorCode._(2,
          _omitEnumNames ? '' : 'BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT');
  static const BusinessStateErrorCode BUSINESS_STATE_ERROR_CODE_STALE_EPOCH =
      BusinessStateErrorCode._(
          3, _omitEnumNames ? '' : 'BUSINESS_STATE_ERROR_CODE_STALE_EPOCH');
  static const BusinessStateErrorCode
      BUSINESS_STATE_ERROR_CODE_IDEMPOTENCY_CONFLICT = BusinessStateErrorCode._(
          4,
          _omitEnumNames
              ? ''
              : 'BUSINESS_STATE_ERROR_CODE_IDEMPOTENCY_CONFLICT');
  static const BusinessStateErrorCode BUSINESS_STATE_ERROR_CODE_UNAVAILABLE =
      BusinessStateErrorCode._(
          5, _omitEnumNames ? '' : 'BUSINESS_STATE_ERROR_CODE_UNAVAILABLE');
  static const BusinessStateErrorCode BUSINESS_STATE_ERROR_CODE_LIMIT_EXCEEDED =
      BusinessStateErrorCode._(
          6, _omitEnumNames ? '' : 'BUSINESS_STATE_ERROR_CODE_LIMIT_EXCEEDED');

  static const $core.List<BusinessStateErrorCode> values =
      <BusinessStateErrorCode>[
    BUSINESS_STATE_ERROR_CODE_UNSPECIFIED,
    BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
    BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
    BUSINESS_STATE_ERROR_CODE_STALE_EPOCH,
    BUSINESS_STATE_ERROR_CODE_IDEMPOTENCY_CONFLICT,
    BUSINESS_STATE_ERROR_CODE_UNAVAILABLE,
    BUSINESS_STATE_ERROR_CODE_LIMIT_EXCEEDED,
  ];

  static final $core.List<BusinessStateErrorCode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 6);
  static BusinessStateErrorCode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const BusinessStateErrorCode._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
