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

class AppTheme extends $pb.ProtobufEnum {
  static const AppTheme APP_THEME_UNSPECIFIED =
      AppTheme._(0, _omitEnumNames ? '' : 'APP_THEME_UNSPECIFIED');
  static const AppTheme APP_THEME_SYSTEM =
      AppTheme._(1, _omitEnumNames ? '' : 'APP_THEME_SYSTEM');
  static const AppTheme APP_THEME_LIGHT =
      AppTheme._(2, _omitEnumNames ? '' : 'APP_THEME_LIGHT');
  static const AppTheme APP_THEME_DARK =
      AppTheme._(3, _omitEnumNames ? '' : 'APP_THEME_DARK');

  static const $core.List<AppTheme> values = <AppTheme>[
    APP_THEME_UNSPECIFIED,
    APP_THEME_SYSTEM,
    APP_THEME_LIGHT,
    APP_THEME_DARK,
  ];

  static final $core.List<AppTheme?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static AppTheme? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const AppTheme._(super.value, super.name);
}

class ReaderMode extends $pb.ProtobufEnum {
  static const ReaderMode READER_MODE_UNSPECIFIED =
      ReaderMode._(0, _omitEnumNames ? '' : 'READER_MODE_UNSPECIFIED');
  static const ReaderMode READER_MODE_LEFT_TO_RIGHT =
      ReaderMode._(1, _omitEnumNames ? '' : 'READER_MODE_LEFT_TO_RIGHT');
  static const ReaderMode READER_MODE_RIGHT_TO_LEFT =
      ReaderMode._(2, _omitEnumNames ? '' : 'READER_MODE_RIGHT_TO_LEFT');
  static const ReaderMode READER_MODE_CONTINUOUS =
      ReaderMode._(3, _omitEnumNames ? '' : 'READER_MODE_CONTINUOUS');
  static const ReaderMode READER_MODE_WEBTOON =
      ReaderMode._(4, _omitEnumNames ? '' : 'READER_MODE_WEBTOON');

  static const $core.List<ReaderMode> values = <ReaderMode>[
    READER_MODE_UNSPECIFIED,
    READER_MODE_LEFT_TO_RIGHT,
    READER_MODE_RIGHT_TO_LEFT,
    READER_MODE_CONTINUOUS,
    READER_MODE_WEBTOON,
  ];

  static final $core.List<ReaderMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 4);
  static ReaderMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ReaderMode._(super.value, super.name);
}

class ReaderPageLayout extends $pb.ProtobufEnum {
  static const ReaderPageLayout READER_PAGE_LAYOUT_UNSPECIFIED =
      ReaderPageLayout._(
          0, _omitEnumNames ? '' : 'READER_PAGE_LAYOUT_UNSPECIFIED');
  static const ReaderPageLayout READER_PAGE_LAYOUT_AUTO =
      ReaderPageLayout._(1, _omitEnumNames ? '' : 'READER_PAGE_LAYOUT_AUTO');
  static const ReaderPageLayout READER_PAGE_LAYOUT_SINGLE =
      ReaderPageLayout._(2, _omitEnumNames ? '' : 'READER_PAGE_LAYOUT_SINGLE');
  static const ReaderPageLayout READER_PAGE_LAYOUT_DOUBLE =
      ReaderPageLayout._(3, _omitEnumNames ? '' : 'READER_PAGE_LAYOUT_DOUBLE');

  static const $core.List<ReaderPageLayout> values = <ReaderPageLayout>[
    READER_PAGE_LAYOUT_UNSPECIFIED,
    READER_PAGE_LAYOUT_AUTO,
    READER_PAGE_LAYOUT_SINGLE,
    READER_PAGE_LAYOUT_DOUBLE,
  ];

  static final $core.List<ReaderPageLayout?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ReaderPageLayout? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ReaderPageLayout._(super.value, super.name);
}

class ReaderBackground extends $pb.ProtobufEnum {
  static const ReaderBackground READER_BACKGROUND_UNSPECIFIED =
      ReaderBackground._(
          0, _omitEnumNames ? '' : 'READER_BACKGROUND_UNSPECIFIED');
  static const ReaderBackground READER_BACKGROUND_BLACK =
      ReaderBackground._(1, _omitEnumNames ? '' : 'READER_BACKGROUND_BLACK');
  static const ReaderBackground READER_BACKGROUND_WHITE =
      ReaderBackground._(2, _omitEnumNames ? '' : 'READER_BACKGROUND_WHITE');
  static const ReaderBackground READER_BACKGROUND_THEME =
      ReaderBackground._(3, _omitEnumNames ? '' : 'READER_BACKGROUND_THEME');

  static const $core.List<ReaderBackground> values = <ReaderBackground>[
    READER_BACKGROUND_UNSPECIFIED,
    READER_BACKGROUND_BLACK,
    READER_BACKGROUND_WHITE,
    READER_BACKGROUND_THEME,
  ];

  static final $core.List<ReaderBackground?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ReaderBackground? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ReaderBackground._(super.value, super.name);
}

class ReaderInputPreset extends $pb.ProtobufEnum {
  static const ReaderInputPreset READER_INPUT_PRESET_UNSPECIFIED =
      ReaderInputPreset._(
          0, _omitEnumNames ? '' : 'READER_INPUT_PRESET_UNSPECIFIED');
  static const ReaderInputPreset READER_INPUT_PRESET_STANDARD =
      ReaderInputPreset._(
          1, _omitEnumNames ? '' : 'READER_INPUT_PRESET_STANDARD');
  static const ReaderInputPreset READER_INPUT_PRESET_REVERSED =
      ReaderInputPreset._(
          2, _omitEnumNames ? '' : 'READER_INPUT_PRESET_REVERSED');
  static const ReaderInputPreset READER_INPUT_PRESET_DISABLED =
      ReaderInputPreset._(
          3, _omitEnumNames ? '' : 'READER_INPUT_PRESET_DISABLED');

  static const $core.List<ReaderInputPreset> values = <ReaderInputPreset>[
    READER_INPUT_PRESET_UNSPECIFIED,
    READER_INPUT_PRESET_STANDARD,
    READER_INPUT_PRESET_REVERSED,
    READER_INPUT_PRESET_DISABLED,
  ];

  static final $core.List<ReaderInputPreset?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ReaderInputPreset? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ReaderInputPreset._(super.value, super.name);
}

class ReaderFit extends $pb.ProtobufEnum {
  static const ReaderFit READER_FIT_UNSPECIFIED =
      ReaderFit._(0, _omitEnumNames ? '' : 'READER_FIT_UNSPECIFIED');
  static const ReaderFit READER_FIT_CONTAIN =
      ReaderFit._(1, _omitEnumNames ? '' : 'READER_FIT_CONTAIN');
  static const ReaderFit READER_FIT_WIDTH =
      ReaderFit._(2, _omitEnumNames ? '' : 'READER_FIT_WIDTH');
  static const ReaderFit READER_FIT_HEIGHT =
      ReaderFit._(3, _omitEnumNames ? '' : 'READER_FIT_HEIGHT');

  static const $core.List<ReaderFit> values = <ReaderFit>[
    READER_FIT_UNSPECIFIED,
    READER_FIT_CONTAIN,
    READER_FIT_WIDTH,
    READER_FIT_HEIGHT,
  ];

  static final $core.List<ReaderFit?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ReaderFit? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ReaderFit._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
