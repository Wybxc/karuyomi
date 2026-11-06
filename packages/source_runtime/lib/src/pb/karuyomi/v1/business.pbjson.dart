// This is a generated file - do not edit.
//
// Generated from karuyomi/v1/business.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use businessStateErrorCodeDescriptor instead')
const BusinessStateErrorCode$json = {
  '1': 'BusinessStateErrorCode',
  '2': [
    {'1': 'BUSINESS_STATE_ERROR_CODE_UNSPECIFIED', '2': 0},
    {'1': 'BUSINESS_STATE_ERROR_CODE_INVALID_INPUT', '2': 1},
    {'1': 'BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT', '2': 2},
    {'1': 'BUSINESS_STATE_ERROR_CODE_STALE_EPOCH', '2': 3},
    {'1': 'BUSINESS_STATE_ERROR_CODE_IDEMPOTENCY_CONFLICT', '2': 4},
    {'1': 'BUSINESS_STATE_ERROR_CODE_UNAVAILABLE', '2': 5},
    {'1': 'BUSINESS_STATE_ERROR_CODE_LIMIT_EXCEEDED', '2': 6},
  ],
};

/// Descriptor for `BusinessStateErrorCode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List businessStateErrorCodeDescriptor = $convert.base64Decode(
    'ChZCdXNpbmVzc1N0YXRlRXJyb3JDb2RlEikKJUJVU0lORVNTX1NUQVRFX0VSUk9SX0NPREVfVU'
    '5TUEVDSUZJRUQQABIrCidCVVNJTkVTU19TVEFURV9FUlJPUl9DT0RFX0lOVkFMSURfSU5QVVQQ'
    'ARIvCitCVVNJTkVTU19TVEFURV9FUlJPUl9DT0RFX1JFVklTSU9OX0NPTkZMSUNUEAISKQolQl'
    'VTSU5FU1NfU1RBVEVfRVJST1JfQ09ERV9TVEFMRV9FUE9DSBADEjIKLkJVU0lORVNTX1NUQVRF'
    'X0VSUk9SX0NPREVfSURFTVBPVEVOQ1lfQ09ORkxJQ1QQBBIpCiVCVVNJTkVTU19TVEFURV9FUl'
    'JPUl9DT0RFX1VOQVZBSUxBQkxFEAUSLAooQlVTSU5FU1NfU1RBVEVfRVJST1JfQ09ERV9MSU1J'
    'VF9FWENFRURFRBAG');

@$core.Deprecated('Use appThemeDescriptor instead')
const AppTheme$json = {
  '1': 'AppTheme',
  '2': [
    {'1': 'APP_THEME_UNSPECIFIED', '2': 0},
    {'1': 'APP_THEME_SYSTEM', '2': 1},
    {'1': 'APP_THEME_LIGHT', '2': 2},
    {'1': 'APP_THEME_DARK', '2': 3},
  ],
};

/// Descriptor for `AppTheme`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List appThemeDescriptor = $convert.base64Decode(
    'CghBcHBUaGVtZRIZChVBUFBfVEhFTUVfVU5TUEVDSUZJRUQQABIUChBBUFBfVEhFTUVfU1lTVE'
    'VNEAESEwoPQVBQX1RIRU1FX0xJR0hUEAISEgoOQVBQX1RIRU1FX0RBUksQAw==');

@$core.Deprecated('Use readerModeDescriptor instead')
const ReaderMode$json = {
  '1': 'ReaderMode',
  '2': [
    {'1': 'READER_MODE_UNSPECIFIED', '2': 0},
    {'1': 'READER_MODE_LEFT_TO_RIGHT', '2': 1},
    {'1': 'READER_MODE_RIGHT_TO_LEFT', '2': 2},
    {'1': 'READER_MODE_CONTINUOUS', '2': 3},
    {'1': 'READER_MODE_WEBTOON', '2': 4},
  ],
};

/// Descriptor for `ReaderMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List readerModeDescriptor = $convert.base64Decode(
    'CgpSZWFkZXJNb2RlEhsKF1JFQURFUl9NT0RFX1VOU1BFQ0lGSUVEEAASHQoZUkVBREVSX01PRE'
    'VfTEVGVF9UT19SSUdIVBABEh0KGVJFQURFUl9NT0RFX1JJR0hUX1RPX0xFRlQQAhIaChZSRUFE'
    'RVJfTU9ERV9DT05USU5VT1VTEAMSFwoTUkVBREVSX01PREVfV0VCVE9PThAE');

@$core.Deprecated('Use readerPageLayoutDescriptor instead')
const ReaderPageLayout$json = {
  '1': 'ReaderPageLayout',
  '2': [
    {'1': 'READER_PAGE_LAYOUT_UNSPECIFIED', '2': 0},
    {'1': 'READER_PAGE_LAYOUT_AUTO', '2': 1},
    {'1': 'READER_PAGE_LAYOUT_SINGLE', '2': 2},
    {'1': 'READER_PAGE_LAYOUT_DOUBLE', '2': 3},
  ],
};

/// Descriptor for `ReaderPageLayout`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List readerPageLayoutDescriptor = $convert.base64Decode(
    'ChBSZWFkZXJQYWdlTGF5b3V0EiIKHlJFQURFUl9QQUdFX0xBWU9VVF9VTlNQRUNJRklFRBAAEh'
    'sKF1JFQURFUl9QQUdFX0xBWU9VVF9BVVRPEAESHQoZUkVBREVSX1BBR0VfTEFZT1VUX1NJTkdM'
    'RRACEh0KGVJFQURFUl9QQUdFX0xBWU9VVF9ET1VCTEUQAw==');

@$core.Deprecated('Use readerBackgroundDescriptor instead')
const ReaderBackground$json = {
  '1': 'ReaderBackground',
  '2': [
    {'1': 'READER_BACKGROUND_UNSPECIFIED', '2': 0},
    {'1': 'READER_BACKGROUND_BLACK', '2': 1},
    {'1': 'READER_BACKGROUND_WHITE', '2': 2},
    {'1': 'READER_BACKGROUND_THEME', '2': 3},
  ],
};

/// Descriptor for `ReaderBackground`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List readerBackgroundDescriptor = $convert.base64Decode(
    'ChBSZWFkZXJCYWNrZ3JvdW5kEiEKHVJFQURFUl9CQUNLR1JPVU5EX1VOU1BFQ0lGSUVEEAASGw'
    'oXUkVBREVSX0JBQ0tHUk9VTkRfQkxBQ0sQARIbChdSRUFERVJfQkFDS0dST1VORF9XSElURRAC'
    'EhsKF1JFQURFUl9CQUNLR1JPVU5EX1RIRU1FEAM=');

@$core.Deprecated('Use readerInputPresetDescriptor instead')
const ReaderInputPreset$json = {
  '1': 'ReaderInputPreset',
  '2': [
    {'1': 'READER_INPUT_PRESET_UNSPECIFIED', '2': 0},
    {'1': 'READER_INPUT_PRESET_STANDARD', '2': 1},
    {'1': 'READER_INPUT_PRESET_REVERSED', '2': 2},
    {'1': 'READER_INPUT_PRESET_DISABLED', '2': 3},
  ],
};

/// Descriptor for `ReaderInputPreset`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List readerInputPresetDescriptor = $convert.base64Decode(
    'ChFSZWFkZXJJbnB1dFByZXNldBIjCh9SRUFERVJfSU5QVVRfUFJFU0VUX1VOU1BFQ0lGSUVEEA'
    'ASIAocUkVBREVSX0lOUFVUX1BSRVNFVF9TVEFOREFSRBABEiAKHFJFQURFUl9JTlBVVF9QUkVT'
    'RVRfUkVWRVJTRUQQAhIgChxSRUFERVJfSU5QVVRfUFJFU0VUX0RJU0FCTEVEEAM=');

@$core.Deprecated('Use readerFitDescriptor instead')
const ReaderFit$json = {
  '1': 'ReaderFit',
  '2': [
    {'1': 'READER_FIT_UNSPECIFIED', '2': 0},
    {'1': 'READER_FIT_CONTAIN', '2': 1},
    {'1': 'READER_FIT_WIDTH', '2': 2},
    {'1': 'READER_FIT_HEIGHT', '2': 3},
  ],
};

/// Descriptor for `ReaderFit`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List readerFitDescriptor = $convert.base64Decode(
    'CglSZWFkZXJGaXQSGgoWUkVBREVSX0ZJVF9VTlNQRUNJRklFRBAAEhYKElJFQURFUl9GSVRfQ0'
    '9OVEFJThABEhQKEFJFQURFUl9GSVRfV0lEVEgQAhIVChFSRUFERVJfRklUX0hFSUdIVBAD');

@$core.Deprecated('Use libraryMetadataDescriptor instead')
const LibraryMetadata$json = {
  '1': 'LibraryMetadata',
  '2': [
    {'1': 'package_name', '3': 1, '4': 1, '5': 9, '10': 'packageName'},
    {'1': 'source_id', '3': 2, '4': 1, '5': 9, '10': 'sourceId'},
    {'1': 'source_name', '3': 3, '4': 1, '5': 9, '10': 'sourceName'},
    {'1': 'source_lang', '3': 4, '4': 1, '5': 9, '10': 'sourceLang'},
    {
      '1': 'manga',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Manga',
      '10': 'manga'
    },
  ],
};

/// Descriptor for `LibraryMetadata`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List libraryMetadataDescriptor = $convert.base64Decode(
    'Cg9MaWJyYXJ5TWV0YWRhdGESIQoMcGFja2FnZV9uYW1lGAEgASgJUgtwYWNrYWdlTmFtZRIbCg'
    'lzb3VyY2VfaWQYAiABKAlSCHNvdXJjZUlkEh8KC3NvdXJjZV9uYW1lGAMgASgJUgpzb3VyY2VO'
    'YW1lEh8KC3NvdXJjZV9sYW5nGAQgASgJUgpzb3VyY2VMYW5nEigKBW1hbmdhGAUgASgLMhIua2'
    'FydXlvbWkudjEuTWFuZ2FSBW1hbmdh');

@$core.Deprecated('Use mangaResumeDescriptor instead')
const MangaResume$json = {
  '1': 'MangaResume',
  '2': [
    {'1': 'chapter_key', '3': 1, '4': 1, '5': 9, '10': 'chapterKey'},
    {'1': 'reversed_order', '3': 2, '4': 1, '5': 8, '10': 'reversedOrder'},
  ],
};

/// Descriptor for `MangaResume`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mangaResumeDescriptor = $convert.base64Decode(
    'CgtNYW5nYVJlc3VtZRIfCgtjaGFwdGVyX2tleRgBIAEoCVIKY2hhcHRlcktleRIlCg5yZXZlcn'
    'NlZF9vcmRlchgCIAEoCFINcmV2ZXJzZWRPcmRlcg==');

@$core.Deprecated('Use customCoverDescriptor instead')
const CustomCover$json = {
  '1': 'CustomCover',
  '2': [
    {'1': 'asset_id', '3': 1, '4': 1, '5': 9, '10': 'assetId'},
    {'1': 'content_type', '3': 2, '4': 1, '5': 9, '10': 'contentType'},
    {'1': 'byte_length', '3': 3, '4': 1, '5': 13, '10': 'byteLength'},
    {'1': 'sha256', '3': 4, '4': 1, '5': 9, '10': 'sha256'},
  ],
};

/// Descriptor for `CustomCover`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List customCoverDescriptor = $convert.base64Decode(
    'CgtDdXN0b21Db3ZlchIZCghhc3NldF9pZBgBIAEoCVIHYXNzZXRJZBIhCgxjb250ZW50X3R5cG'
    'UYAiABKAlSC2NvbnRlbnRUeXBlEh8KC2J5dGVfbGVuZ3RoGAMgASgNUgpieXRlTGVuZ3RoEhYK'
    'BnNoYTI1NhgEIAEoCVIGc2hhMjU2');

@$core.Deprecated('Use setCustomCoverDescriptor instead')
const SetCustomCover$json = {
  '1': 'SetCustomCover',
  '2': [
    {
      '1': 'cover',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.CustomCover',
      '10': 'cover'
    },
  ],
};

/// Descriptor for `SetCustomCover`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setCustomCoverDescriptor = $convert.base64Decode(
    'Cg5TZXRDdXN0b21Db3ZlchIuCgVjb3ZlchgBIAEoCzIYLmthcnV5b21pLnYxLkN1c3RvbUNvdm'
    'VyUgVjb3Zlcg==');

@$core.Deprecated('Use mangaStateDescriptor instead')
const MangaState$json = {
  '1': 'MangaState',
  '2': [
    {'1': 'manga_key', '3': 1, '4': 1, '5': 9, '10': 'mangaKey'},
    {'1': 'revision', '3': 2, '4': 1, '5': 13, '10': 'revision'},
    {
      '1': 'metadata',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.LibraryMetadata',
      '10': 'metadata'
    },
    {'1': 'favorite', '3': 4, '4': 1, '5': 8, '10': 'favorite'},
    {'1': 'added_at_seconds', '3': 5, '4': 1, '5': 13, '10': 'addedAtSeconds'},
    {
      '1': 'resume',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.MangaResume',
      '10': 'resume'
    },
    {'1': 'category_ids', '3': 7, '4': 3, '5': 9, '10': 'categoryIds'},
    {
      '1': 'custom_cover',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.CustomCover',
      '10': 'customCover'
    },
  ],
};

/// Descriptor for `MangaState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mangaStateDescriptor = $convert.base64Decode(
    'CgpNYW5nYVN0YXRlEhsKCW1hbmdhX2tleRgBIAEoCVIIbWFuZ2FLZXkSGgoIcmV2aXNpb24YAi'
    'ABKA1SCHJldmlzaW9uEjgKCG1ldGFkYXRhGAMgASgLMhwua2FydXlvbWkudjEuTGlicmFyeU1l'
    'dGFkYXRhUghtZXRhZGF0YRIaCghmYXZvcml0ZRgEIAEoCFIIZmF2b3JpdGUSKAoQYWRkZWRfYX'
    'Rfc2Vjb25kcxgFIAEoDVIOYWRkZWRBdFNlY29uZHMSMAoGcmVzdW1lGAYgASgLMhgua2FydXlv'
    'bWkudjEuTWFuZ2FSZXN1bWVSBnJlc3VtZRIhCgxjYXRlZ29yeV9pZHMYByADKAlSC2NhdGVnb3'
    'J5SWRzEjsKDGN1c3RvbV9jb3ZlchgIIAEoCzIYLmthcnV5b21pLnYxLkN1c3RvbUNvdmVyUgtj'
    'dXN0b21Db3Zlcg==');

@$core.Deprecated('Use categoryDescriptor instead')
const Category$json = {
  '1': 'Category',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `Category`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List categoryDescriptor = $convert.base64Decode(
    'CghDYXRlZ29yeRIOCgJpZBgBIAEoCVICaWQSEgoEbmFtZRgCIAEoCVIEbmFtZQ==');

@$core.Deprecated('Use categoryCatalogDescriptor instead')
const CategoryCatalog$json = {
  '1': 'CategoryCatalog',
  '2': [
    {'1': 'revision', '3': 1, '4': 1, '5': 13, '10': 'revision'},
    {
      '1': 'categories',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.Category',
      '10': 'categories'
    },
  ],
};

/// Descriptor for `CategoryCatalog`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List categoryCatalogDescriptor = $convert.base64Decode(
    'Cg9DYXRlZ29yeUNhdGFsb2cSGgoIcmV2aXNpb24YASABKA1SCHJldmlzaW9uEjUKCmNhdGVnb3'
    'JpZXMYAiADKAsyFS5rYXJ1eW9taS52MS5DYXRlZ29yeVIKY2F0ZWdvcmllcw==');

@$core.Deprecated('Use setCategoriesDescriptor instead')
const SetCategories$json = {
  '1': 'SetCategories',
  '2': [
    {'1': 'category_ids', '3': 1, '4': 3, '5': 9, '10': 'categoryIds'},
    {
      '1': 'expected_catalog_revision',
      '3': 2,
      '4': 1,
      '5': 13,
      '10': 'expectedCatalogRevision'
    },
  ],
};

/// Descriptor for `SetCategories`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setCategoriesDescriptor = $convert.base64Decode(
    'Cg1TZXRDYXRlZ29yaWVzEiEKDGNhdGVnb3J5X2lkcxgBIAMoCVILY2F0ZWdvcnlJZHMSOgoZZX'
    'hwZWN0ZWRfY2F0YWxvZ19yZXZpc2lvbhgCIAEoDVIXZXhwZWN0ZWRDYXRhbG9nUmV2aXNpb24=');

@$core.Deprecated('Use createCategoryDescriptor instead')
const CreateCategory$json = {
  '1': 'CreateCategory',
  '2': [
    {
      '1': 'category',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Category',
      '10': 'category'
    },
  ],
};

/// Descriptor for `CreateCategory`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createCategoryDescriptor = $convert.base64Decode(
    'Cg5DcmVhdGVDYXRlZ29yeRIxCghjYXRlZ29yeRgBIAEoCzIVLmthcnV5b21pLnYxLkNhdGVnb3'
    'J5UghjYXRlZ29yeQ==');

@$core.Deprecated('Use renameCategoryDescriptor instead')
const RenameCategory$json = {
  '1': 'RenameCategory',
  '2': [
    {'1': 'category_id', '3': 1, '4': 1, '5': 9, '10': 'categoryId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `RenameCategory`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List renameCategoryDescriptor = $convert.base64Decode(
    'Cg5SZW5hbWVDYXRlZ29yeRIfCgtjYXRlZ29yeV9pZBgBIAEoCVIKY2F0ZWdvcnlJZBISCgRuYW'
    '1lGAIgASgJUgRuYW1l');

@$core.Deprecated('Use reorderCategoriesDescriptor instead')
const ReorderCategories$json = {
  '1': 'ReorderCategories',
  '2': [
    {'1': 'category_ids', '3': 1, '4': 3, '5': 9, '10': 'categoryIds'},
  ],
};

/// Descriptor for `ReorderCategories`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reorderCategoriesDescriptor = $convert.base64Decode(
    'ChFSZW9yZGVyQ2F0ZWdvcmllcxIhCgxjYXRlZ29yeV9pZHMYASADKAlSC2NhdGVnb3J5SWRz');

@$core.Deprecated('Use deleteCategoryDescriptor instead')
const DeleteCategory$json = {
  '1': 'DeleteCategory',
  '2': [
    {'1': 'category_id', '3': 1, '4': 1, '5': 9, '10': 'categoryId'},
  ],
};

/// Descriptor for `DeleteCategory`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteCategoryDescriptor = $convert.base64Decode(
    'Cg5EZWxldGVDYXRlZ29yeRIfCgtjYXRlZ29yeV9pZBgBIAEoCVIKY2F0ZWdvcnlJZA==');

@$core.Deprecated('Use categoryMutationDescriptor instead')
const CategoryMutation$json = {
  '1': 'CategoryMutation',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'mutation_id', '3': 2, '4': 1, '5': 9, '10': 'mutationId'},
    {
      '1': 'expected_revision',
      '3': 3,
      '4': 1,
      '5': 13,
      '10': 'expectedRevision'
    },
    {
      '1': 'create_category',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.CreateCategory',
      '9': 0,
      '10': 'createCategory'
    },
    {
      '1': 'rename_category',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.RenameCategory',
      '9': 0,
      '10': 'renameCategory'
    },
    {
      '1': 'reorder_categories',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ReorderCategories',
      '9': 0,
      '10': 'reorderCategories'
    },
    {
      '1': 'delete_category',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.DeleteCategory',
      '9': 0,
      '10': 'deleteCategory'
    },
  ],
  '8': [
    {'1': 'operation'},
  ],
};

/// Descriptor for `CategoryMutation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List categoryMutationDescriptor = $convert.base64Decode(
    'ChBDYXRlZ29yeU11dGF0aW9uEiUKDnNjaGVtYV92ZXJzaW9uGAEgASgNUg1zY2hlbWFWZXJzaW'
    '9uEh8KC211dGF0aW9uX2lkGAIgASgJUgptdXRhdGlvbklkEisKEWV4cGVjdGVkX3JldmlzaW9u'
    'GAMgASgNUhBleHBlY3RlZFJldmlzaW9uEkYKD2NyZWF0ZV9jYXRlZ29yeRgKIAEoCzIbLmthcn'
    'V5b21pLnYxLkNyZWF0ZUNhdGVnb3J5SABSDmNyZWF0ZUNhdGVnb3J5EkYKD3JlbmFtZV9jYXRl'
    'Z29yeRgLIAEoCzIbLmthcnV5b21pLnYxLlJlbmFtZUNhdGVnb3J5SABSDnJlbmFtZUNhdGVnb3'
    'J5Ek8KEnJlb3JkZXJfY2F0ZWdvcmllcxgMIAEoCzIeLmthcnV5b21pLnYxLlJlb3JkZXJDYXRl'
    'Z29yaWVzSABSEXJlb3JkZXJDYXRlZ29yaWVzEkYKD2RlbGV0ZV9jYXRlZ29yeRgNIAEoCzIbLm'
    'thcnV5b21pLnYxLkRlbGV0ZUNhdGVnb3J5SABSDmRlbGV0ZUNhdGVnb3J5QgsKCW9wZXJhdGlv'
    'bg==');

@$core.Deprecated('Use readingAnchorDescriptor instead')
const ReadingAnchor$json = {
  '1': 'ReadingAnchor',
  '2': [
    {'1': 'chapter_key', '3': 1, '4': 1, '5': 9, '10': 'chapterKey'},
    {'1': 'page_key', '3': 2, '4': 1, '5': 9, '10': 'pageKey'},
    {'1': 'manifest_version', '3': 3, '4': 1, '5': 9, '10': 'manifestVersion'},
    {'1': 'page_index_hint', '3': 4, '4': 1, '5': 13, '10': 'pageIndexHint'},
    {
      '1': 'normalized_offset',
      '3': 5,
      '4': 1,
      '5': 1,
      '10': 'normalizedOffset'
    },
    {'1': 'normalized_x', '3': 6, '4': 1, '5': 1, '10': 'normalizedX'},
    {'1': 'viewport_x', '3': 7, '4': 1, '5': 1, '10': 'viewportX'},
    {'1': 'viewport_y', '3': 8, '4': 1, '5': 1, '10': 'viewportY'},
  ],
};

/// Descriptor for `ReadingAnchor`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readingAnchorDescriptor = $convert.base64Decode(
    'Cg1SZWFkaW5nQW5jaG9yEh8KC2NoYXB0ZXJfa2V5GAEgASgJUgpjaGFwdGVyS2V5EhkKCHBhZ2'
    'Vfa2V5GAIgASgJUgdwYWdlS2V5EikKEG1hbmlmZXN0X3ZlcnNpb24YAyABKAlSD21hbmlmZXN0'
    'VmVyc2lvbhImCg9wYWdlX2luZGV4X2hpbnQYBCABKA1SDXBhZ2VJbmRleEhpbnQSKwoRbm9ybW'
    'FsaXplZF9vZmZzZXQYBSABKAFSEG5vcm1hbGl6ZWRPZmZzZXQSIQoMbm9ybWFsaXplZF94GAYg'
    'ASgBUgtub3JtYWxpemVkWBIdCgp2aWV3cG9ydF94GAcgASgBUgl2aWV3cG9ydFgSHQoKdmlld3'
    'BvcnRfeRgIIAEoAVIJdmlld3BvcnRZ');

@$core.Deprecated('Use chapterProgressStateDescriptor instead')
const ChapterProgressState$json = {
  '1': 'ChapterProgressState',
  '2': [
    {'1': 'chapter_key', '3': 1, '4': 1, '5': 9, '10': 'chapterKey'},
    {
      '1': 'current',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ReadingAnchor',
      '10': 'current'
    },
    {
      '1': 'furthest',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ReadingAnchor',
      '10': 'furthest'
    },
    {'1': 'epoch', '3': 4, '4': 1, '5': 13, '10': 'epoch'},
    {'1': 'completed', '3': 5, '4': 1, '5': 8, '10': 'completed'},
  ],
};

/// Descriptor for `ChapterProgressState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chapterProgressStateDescriptor = $convert.base64Decode(
    'ChRDaGFwdGVyUHJvZ3Jlc3NTdGF0ZRIfCgtjaGFwdGVyX2tleRgBIAEoCVIKY2hhcHRlcktleR'
    'I0CgdjdXJyZW50GAIgASgLMhoua2FydXlvbWkudjEuUmVhZGluZ0FuY2hvclIHY3VycmVudBI2'
    'CghmdXJ0aGVzdBgDIAEoCzIaLmthcnV5b21pLnYxLlJlYWRpbmdBbmNob3JSCGZ1cnRoZXN0Eh'
    'QKBWVwb2NoGAQgASgNUgVlcG9jaBIcCgljb21wbGV0ZWQYBSABKAhSCWNvbXBsZXRlZA==');

@$core.Deprecated('Use chapterSnapshotDescriptor instead')
const ChapterSnapshot$json = {
  '1': 'ChapterSnapshot',
  '2': [
    {'1': 'chapter_key', '3': 1, '4': 1, '5': 9, '10': 'chapterKey'},
    {'1': 'manifest_version', '3': 2, '4': 1, '5': 9, '10': 'manifestVersion'},
    {'1': 'page_keys', '3': 3, '4': 3, '5': 9, '10': 'pageKeys'},
  ],
};

/// Descriptor for `ChapterSnapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chapterSnapshotDescriptor = $convert.base64Decode(
    'Cg9DaGFwdGVyU25hcHNob3QSHwoLY2hhcHRlcl9rZXkYASABKAlSCmNoYXB0ZXJLZXkSKQoQbW'
    'FuaWZlc3RfdmVyc2lvbhgCIAEoCVIPbWFuaWZlc3RWZXJzaW9uEhsKCXBhZ2Vfa2V5cxgDIAMo'
    'CVIIcGFnZUtleXM=');

@$core.Deprecated('Use chapterBookmarkDescriptor instead')
const ChapterBookmark$json = {
  '1': 'ChapterBookmark',
  '2': [
    {'1': 'chapter_key', '3': 1, '4': 1, '5': 9, '10': 'chapterKey'},
    {'1': 'bookmarked', '3': 2, '4': 1, '5': 8, '10': 'bookmarked'},
  ],
};

/// Descriptor for `ChapterBookmark`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chapterBookmarkDescriptor = $convert.base64Decode(
    'Cg9DaGFwdGVyQm9va21hcmsSHwoLY2hhcHRlcl9rZXkYASABKAlSCmNoYXB0ZXJLZXkSHgoKYm'
    '9va21hcmtlZBgCIAEoCFIKYm9va21hcmtlZA==');

@$core.Deprecated('Use setBookmarkDescriptor instead')
const SetBookmark$json = {
  '1': 'SetBookmark',
  '2': [
    {'1': 'chapter_key', '3': 1, '4': 1, '5': 9, '10': 'chapterKey'},
    {'1': 'bookmarked', '3': 2, '4': 1, '5': 8, '10': 'bookmarked'},
  ],
};

/// Descriptor for `SetBookmark`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setBookmarkDescriptor = $convert.base64Decode(
    'CgtTZXRCb29rbWFyaxIfCgtjaGFwdGVyX2tleRgBIAEoCVIKY2hhcHRlcktleRIeCgpib29rbW'
    'Fya2VkGAIgASgIUgpib29rbWFya2Vk');

@$core.Deprecated('Use setChapterReadDescriptor instead')
const SetChapterRead$json = {
  '1': 'SetChapterRead',
  '2': [
    {'1': 'chapter_key', '3': 1, '4': 1, '5': 9, '10': 'chapterKey'},
    {'1': 'read', '3': 2, '4': 1, '5': 8, '10': 'read'},
  ],
};

/// Descriptor for `SetChapterRead`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setChapterReadDescriptor = $convert.base64Decode(
    'Cg5TZXRDaGFwdGVyUmVhZBIfCgtjaGFwdGVyX2tleRgBIAEoCVIKY2hhcHRlcktleRISCgRyZW'
    'FkGAIgASgIUgRyZWFk');

@$core.Deprecated('Use setFavoriteDescriptor instead')
const SetFavorite$json = {
  '1': 'SetFavorite',
  '2': [
    {
      '1': 'metadata',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.LibraryMetadata',
      '10': 'metadata'
    },
    {'1': 'favorite', '3': 2, '4': 1, '5': 8, '10': 'favorite'},
  ],
};

/// Descriptor for `SetFavorite`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setFavoriteDescriptor = $convert.base64Decode(
    'CgtTZXRGYXZvcml0ZRI4CghtZXRhZGF0YRgBIAEoCzIcLmthcnV5b21pLnYxLkxpYnJhcnlNZX'
    'RhZGF0YVIIbWV0YWRhdGESGgoIZmF2b3JpdGUYAiABKAhSCGZhdm9yaXRl');

@$core.Deprecated('Use saveProgressDescriptor instead')
const SaveProgress$json = {
  '1': 'SaveProgress',
  '2': [
    {
      '1': 'snapshot',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ChapterSnapshot',
      '10': 'snapshot'
    },
    {
      '1': 'progress',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ChapterProgressState',
      '10': 'progress'
    },
    {'1': 'reversed_order', '3': 3, '4': 1, '5': 8, '10': 'reversedOrder'},
  ],
};

/// Descriptor for `SaveProgress`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List saveProgressDescriptor = $convert.base64Decode(
    'CgxTYXZlUHJvZ3Jlc3MSOAoIc25hcHNob3QYASABKAsyHC5rYXJ1eW9taS52MS5DaGFwdGVyU2'
    '5hcHNob3RSCHNuYXBzaG90Ej0KCHByb2dyZXNzGAIgASgLMiEua2FydXlvbWkudjEuQ2hhcHRl'
    'clByb2dyZXNzU3RhdGVSCHByb2dyZXNzEiUKDnJldmVyc2VkX29yZGVyGAMgASgIUg1yZXZlcn'
    'NlZE9yZGVy');

@$core.Deprecated('Use resetProgressDescriptor instead')
const ResetProgress$json = {
  '1': 'ResetProgress',
  '2': [
    {
      '1': 'snapshot',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ChapterSnapshot',
      '10': 'snapshot'
    },
    {'1': 'reversed_order', '3': 2, '4': 1, '5': 8, '10': 'reversedOrder'},
  ],
};

/// Descriptor for `ResetProgress`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resetProgressDescriptor = $convert.base64Decode(
    'Cg1SZXNldFByb2dyZXNzEjgKCHNuYXBzaG90GAEgASgLMhwua2FydXlvbWkudjEuQ2hhcHRlcl'
    'NuYXBzaG90UghzbmFwc2hvdBIlCg5yZXZlcnNlZF9vcmRlchgCIAEoCFINcmV2ZXJzZWRPcmRl'
    'cg==');

@$core.Deprecated('Use stateMutationDescriptor instead')
const StateMutation$json = {
  '1': 'StateMutation',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'mutation_id', '3': 2, '4': 1, '5': 9, '10': 'mutationId'},
    {'1': 'manga_key', '3': 3, '4': 1, '5': 9, '10': 'mangaKey'},
    {
      '1': 'expected_revision',
      '3': 4,
      '4': 1,
      '5': 13,
      '10': 'expectedRevision'
    },
    {
      '1': 'set_favorite',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SetFavorite',
      '9': 0,
      '10': 'setFavorite'
    },
    {
      '1': 'update_metadata',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.LibraryMetadata',
      '9': 0,
      '10': 'updateMetadata'
    },
    {
      '1': 'save_progress',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SaveProgress',
      '9': 0,
      '10': 'saveProgress'
    },
    {
      '1': 'reset_progress',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ResetProgress',
      '9': 0,
      '10': 'resetProgress'
    },
    {
      '1': 'set_categories',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SetCategories',
      '9': 0,
      '10': 'setCategories'
    },
    {
      '1': 'set_bookmark',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SetBookmark',
      '9': 0,
      '10': 'setBookmark'
    },
    {
      '1': 'set_chapter_read',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SetChapterRead',
      '9': 0,
      '10': 'setChapterRead'
    },
    {
      '1': 'set_custom_cover',
      '3': 17,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SetCustomCover',
      '9': 0,
      '10': 'setCustomCover'
    },
  ],
  '8': [
    {'1': 'operation'},
  ],
};

/// Descriptor for `StateMutation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stateMutationDescriptor = $convert.base64Decode(
    'Cg1TdGF0ZU11dGF0aW9uEiUKDnNjaGVtYV92ZXJzaW9uGAEgASgNUg1zY2hlbWFWZXJzaW9uEh'
    '8KC211dGF0aW9uX2lkGAIgASgJUgptdXRhdGlvbklkEhsKCW1hbmdhX2tleRgDIAEoCVIIbWFu'
    'Z2FLZXkSKwoRZXhwZWN0ZWRfcmV2aXNpb24YBCABKA1SEGV4cGVjdGVkUmV2aXNpb24SPQoMc2'
    'V0X2Zhdm9yaXRlGAogASgLMhgua2FydXlvbWkudjEuU2V0RmF2b3JpdGVIAFILc2V0RmF2b3Jp'
    'dGUSRwoPdXBkYXRlX21ldGFkYXRhGAsgASgLMhwua2FydXlvbWkudjEuTGlicmFyeU1ldGFkYX'
    'RhSABSDnVwZGF0ZU1ldGFkYXRhEkAKDXNhdmVfcHJvZ3Jlc3MYDCABKAsyGS5rYXJ1eW9taS52'
    'MS5TYXZlUHJvZ3Jlc3NIAFIMc2F2ZVByb2dyZXNzEkMKDnJlc2V0X3Byb2dyZXNzGA0gASgLMh'
    'oua2FydXlvbWkudjEuUmVzZXRQcm9ncmVzc0gAUg1yZXNldFByb2dyZXNzEkMKDnNldF9jYXRl'
    'Z29yaWVzGA4gASgLMhoua2FydXlvbWkudjEuU2V0Q2F0ZWdvcmllc0gAUg1zZXRDYXRlZ29yaW'
    'VzEj0KDHNldF9ib29rbWFyaxgPIAEoCzIYLmthcnV5b21pLnYxLlNldEJvb2ttYXJrSABSC3Nl'
    'dEJvb2ttYXJrEkcKEHNldF9jaGFwdGVyX3JlYWQYECABKAsyGy5rYXJ1eW9taS52MS5TZXRDaG'
    'FwdGVyUmVhZEgAUg5zZXRDaGFwdGVyUmVhZBJHChBzZXRfY3VzdG9tX2NvdmVyGBEgASgLMhsu'
    'a2FydXlvbWkudjEuU2V0Q3VzdG9tQ292ZXJIAFIOc2V0Q3VzdG9tQ292ZXJCCwoJb3BlcmF0aW'
    '9u');

@$core.Deprecated('Use businessStateErrorDescriptor instead')
const BusinessStateError$json = {
  '1': 'BusinessStateError',
  '2': [
    {
      '1': 'code',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.BusinessStateErrorCode',
      '10': 'code'
    },
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'retryable', '3': 3, '4': 1, '5': 8, '10': 'retryable'},
  ],
};

/// Descriptor for `BusinessStateError`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List businessStateErrorDescriptor = $convert.base64Decode(
    'ChJCdXNpbmVzc1N0YXRlRXJyb3ISNwoEY29kZRgBIAEoDjIjLmthcnV5b21pLnYxLkJ1c2luZX'
    'NzU3RhdGVFcnJvckNvZGVSBGNvZGUSGAoHbWVzc2FnZRgCIAEoCVIHbWVzc2FnZRIcCglyZXRy'
    'eWFibGUYAyABKAhSCXJldHJ5YWJsZQ==');

@$core.Deprecated('Use stateMutationResponseDescriptor instead')
const StateMutationResponse$json = {
  '1': 'StateMutationResponse',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'mutation_id', '3': 2, '4': 1, '5': 9, '10': 'mutationId'},
    {'1': 'account_revision', '3': 3, '4': 1, '5': 13, '10': 'accountRevision'},
    {
      '1': 'manga',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.MangaState',
      '10': 'manga'
    },
    {
      '1': 'progress',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ChapterProgressState',
      '10': 'progress'
    },
    {
      '1': 'error',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BusinessStateError',
      '10': 'error'
    },
    {
      '1': 'category_catalog',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.CategoryCatalog',
      '10': 'categoryCatalog'
    },
    {
      '1': 'bookmark',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ChapterBookmark',
      '10': 'bookmark'
    },
  ],
};

/// Descriptor for `StateMutationResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stateMutationResponseDescriptor = $convert.base64Decode(
    'ChVTdGF0ZU11dGF0aW9uUmVzcG9uc2USJQoOc2NoZW1hX3ZlcnNpb24YASABKA1SDXNjaGVtYV'
    'ZlcnNpb24SHwoLbXV0YXRpb25faWQYAiABKAlSCm11dGF0aW9uSWQSKQoQYWNjb3VudF9yZXZp'
    'c2lvbhgDIAEoDVIPYWNjb3VudFJldmlzaW9uEi0KBW1hbmdhGAQgASgLMhcua2FydXlvbWkudj'
    'EuTWFuZ2FTdGF0ZVIFbWFuZ2ESPQoIcHJvZ3Jlc3MYBSABKAsyIS5rYXJ1eW9taS52MS5DaGFw'
    'dGVyUHJvZ3Jlc3NTdGF0ZVIIcHJvZ3Jlc3MSNQoFZXJyb3IYBiABKAsyHy5rYXJ1eW9taS52MS'
    '5CdXNpbmVzc1N0YXRlRXJyb3JSBWVycm9yEkcKEGNhdGVnb3J5X2NhdGFsb2cYByABKAsyHC5r'
    'YXJ1eW9taS52MS5DYXRlZ29yeUNhdGFsb2dSD2NhdGVnb3J5Q2F0YWxvZxI4Cghib29rbWFyax'
    'gIIAEoCzIcLmthcnV5b21pLnYxLkNoYXB0ZXJCb29rbWFya1IIYm9va21hcms=');

@$core.Deprecated('Use mangaStateResponseDescriptor instead')
const MangaStateResponse$json = {
  '1': 'MangaStateResponse',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'account_revision', '3': 2, '4': 1, '5': 13, '10': 'accountRevision'},
    {
      '1': 'manga',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.MangaState',
      '10': 'manga'
    },
    {
      '1': 'progress',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ChapterProgressState',
      '10': 'progress'
    },
    {
      '1': 'error',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BusinessStateError',
      '10': 'error'
    },
    {
      '1': 'category_catalog',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.CategoryCatalog',
      '10': 'categoryCatalog'
    },
    {
      '1': 'bookmark',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ChapterBookmark',
      '10': 'bookmark'
    },
  ],
};

/// Descriptor for `MangaStateResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mangaStateResponseDescriptor = $convert.base64Decode(
    'ChJNYW5nYVN0YXRlUmVzcG9uc2USJQoOc2NoZW1hX3ZlcnNpb24YASABKA1SDXNjaGVtYVZlcn'
    'Npb24SKQoQYWNjb3VudF9yZXZpc2lvbhgCIAEoDVIPYWNjb3VudFJldmlzaW9uEi0KBW1hbmdh'
    'GAMgASgLMhcua2FydXlvbWkudjEuTWFuZ2FTdGF0ZVIFbWFuZ2ESPQoIcHJvZ3Jlc3MYBCABKA'
    'syIS5rYXJ1eW9taS52MS5DaGFwdGVyUHJvZ3Jlc3NTdGF0ZVIIcHJvZ3Jlc3MSNQoFZXJyb3IY'
    'BSABKAsyHy5rYXJ1eW9taS52MS5CdXNpbmVzc1N0YXRlRXJyb3JSBWVycm9yEkcKEGNhdGVnb3'
    'J5X2NhdGFsb2cYBiABKAsyHC5rYXJ1eW9taS52MS5DYXRlZ29yeUNhdGFsb2dSD2NhdGVnb3J5'
    'Q2F0YWxvZxI4Cghib29rbWFyaxgHIAEoCzIcLmthcnV5b21pLnYxLkNoYXB0ZXJCb29rbWFya1'
    'IIYm9va21hcms=');

@$core.Deprecated('Use bookmarkPageResponseDescriptor instead')
const BookmarkPageResponse$json = {
  '1': 'BookmarkPageResponse',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'account_revision', '3': 2, '4': 1, '5': 13, '10': 'accountRevision'},
    {'1': 'manga_key', '3': 3, '4': 1, '5': 9, '10': 'mangaKey'},
    {
      '1': 'entries',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.ChapterBookmark',
      '10': 'entries'
    },
    {'1': 'next_key', '3': 5, '4': 1, '5': 9, '10': 'nextKey'},
    {
      '1': 'error',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BusinessStateError',
      '10': 'error'
    },
  ],
};

/// Descriptor for `BookmarkPageResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bookmarkPageResponseDescriptor = $convert.base64Decode(
    'ChRCb29rbWFya1BhZ2VSZXNwb25zZRIlCg5zY2hlbWFfdmVyc2lvbhgBIAEoDVINc2NoZW1hVm'
    'Vyc2lvbhIpChBhY2NvdW50X3JldmlzaW9uGAIgASgNUg9hY2NvdW50UmV2aXNpb24SGwoJbWFu'
    'Z2Ffa2V5GAMgASgJUghtYW5nYUtleRI2CgdlbnRyaWVzGAQgAygLMhwua2FydXlvbWkudjEuQ2'
    'hhcHRlckJvb2ttYXJrUgdlbnRyaWVzEhkKCG5leHRfa2V5GAUgASgJUgduZXh0S2V5EjUKBWVy'
    'cm9yGAYgASgLMh8ua2FydXlvbWkudjEuQnVzaW5lc3NTdGF0ZUVycm9yUgVlcnJvcg==');

@$core.Deprecated('Use chapterProgressPageResponseDescriptor instead')
const ChapterProgressPageResponse$json = {
  '1': 'ChapterProgressPageResponse',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'account_revision', '3': 2, '4': 1, '5': 13, '10': 'accountRevision'},
    {'1': 'manga_key', '3': 3, '4': 1, '5': 9, '10': 'mangaKey'},
    {
      '1': 'entries',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.ChapterProgressState',
      '10': 'entries'
    },
    {'1': 'next_key', '3': 5, '4': 1, '5': 9, '10': 'nextKey'},
    {
      '1': 'error',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BusinessStateError',
      '10': 'error'
    },
  ],
};

/// Descriptor for `ChapterProgressPageResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chapterProgressPageResponseDescriptor = $convert.base64Decode(
    'ChtDaGFwdGVyUHJvZ3Jlc3NQYWdlUmVzcG9uc2USJQoOc2NoZW1hX3ZlcnNpb24YASABKA1SDX'
    'NjaGVtYVZlcnNpb24SKQoQYWNjb3VudF9yZXZpc2lvbhgCIAEoDVIPYWNjb3VudFJldmlzaW9u'
    'EhsKCW1hbmdhX2tleRgDIAEoCVIIbWFuZ2FLZXkSOwoHZW50cmllcxgEIAMoCzIhLmthcnV5b2'
    '1pLnYxLkNoYXB0ZXJQcm9ncmVzc1N0YXRlUgdlbnRyaWVzEhkKCG5leHRfa2V5GAUgASgJUgdu'
    'ZXh0S2V5EjUKBWVycm9yGAYgASgLMh8ua2FydXlvbWkudjEuQnVzaW5lc3NTdGF0ZUVycm9yUg'
    'VlcnJvcg==');

@$core.Deprecated('Use libraryPageResponseDescriptor instead')
const LibraryPageResponse$json = {
  '1': 'LibraryPageResponse',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'account_revision', '3': 2, '4': 1, '5': 13, '10': 'accountRevision'},
    {
      '1': 'entries',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.MangaState',
      '10': 'entries'
    },
    {'1': 'next_key', '3': 4, '4': 1, '5': 9, '10': 'nextKey'},
    {
      '1': 'error',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BusinessStateError',
      '10': 'error'
    },
    {
      '1': 'category_catalog',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.CategoryCatalog',
      '10': 'categoryCatalog'
    },
  ],
};

/// Descriptor for `LibraryPageResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List libraryPageResponseDescriptor = $convert.base64Decode(
    'ChNMaWJyYXJ5UGFnZVJlc3BvbnNlEiUKDnNjaGVtYV92ZXJzaW9uGAEgASgNUg1zY2hlbWFWZX'
    'JzaW9uEikKEGFjY291bnRfcmV2aXNpb24YAiABKA1SD2FjY291bnRSZXZpc2lvbhIxCgdlbnRy'
    'aWVzGAMgAygLMhcua2FydXlvbWkudjEuTWFuZ2FTdGF0ZVIHZW50cmllcxIZCghuZXh0X2tleR'
    'gEIAEoCVIHbmV4dEtleRI1CgVlcnJvchgFIAEoCzIfLmthcnV5b21pLnYxLkJ1c2luZXNzU3Rh'
    'dGVFcnJvclIFZXJyb3ISRwoQY2F0ZWdvcnlfY2F0YWxvZxgGIAEoCzIcLmthcnV5b21pLnYxLk'
    'NhdGVnb3J5Q2F0YWxvZ1IPY2F0ZWdvcnlDYXRhbG9n');

@$core.Deprecated('Use categoryMutationResponseDescriptor instead')
const CategoryMutationResponse$json = {
  '1': 'CategoryMutationResponse',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'mutation_id', '3': 2, '4': 1, '5': 9, '10': 'mutationId'},
    {'1': 'account_revision', '3': 3, '4': 1, '5': 13, '10': 'accountRevision'},
    {
      '1': 'category_catalog',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.CategoryCatalog',
      '10': 'categoryCatalog'
    },
    {
      '1': 'error',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BusinessStateError',
      '10': 'error'
    },
  ],
};

/// Descriptor for `CategoryMutationResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List categoryMutationResponseDescriptor = $convert.base64Decode(
    'ChhDYXRlZ29yeU11dGF0aW9uUmVzcG9uc2USJQoOc2NoZW1hX3ZlcnNpb24YASABKA1SDXNjaG'
    'VtYVZlcnNpb24SHwoLbXV0YXRpb25faWQYAiABKAlSCm11dGF0aW9uSWQSKQoQYWNjb3VudF9y'
    'ZXZpc2lvbhgDIAEoDVIPYWNjb3VudFJldmlzaW9uEkcKEGNhdGVnb3J5X2NhdGFsb2cYBCABKA'
    'syHC5rYXJ1eW9taS52MS5DYXRlZ29yeUNhdGFsb2dSD2NhdGVnb3J5Q2F0YWxvZxI1CgVlcnJv'
    'chgFIAEoCzIfLmthcnV5b21pLnYxLkJ1c2luZXNzU3RhdGVFcnJvclIFZXJyb3I=');

@$core.Deprecated('Use categoryCatalogResponseDescriptor instead')
const CategoryCatalogResponse$json = {
  '1': 'CategoryCatalogResponse',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'account_revision', '3': 2, '4': 1, '5': 13, '10': 'accountRevision'},
    {
      '1': 'category_catalog',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.CategoryCatalog',
      '10': 'categoryCatalog'
    },
    {
      '1': 'error',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BusinessStateError',
      '10': 'error'
    },
  ],
};

/// Descriptor for `CategoryCatalogResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List categoryCatalogResponseDescriptor = $convert.base64Decode(
    'ChdDYXRlZ29yeUNhdGFsb2dSZXNwb25zZRIlCg5zY2hlbWFfdmVyc2lvbhgBIAEoDVINc2NoZW'
    '1hVmVyc2lvbhIpChBhY2NvdW50X3JldmlzaW9uGAIgASgNUg9hY2NvdW50UmV2aXNpb24SRwoQ'
    'Y2F0ZWdvcnlfY2F0YWxvZxgDIAEoCzIcLmthcnV5b21pLnYxLkNhdGVnb3J5Q2F0YWxvZ1IPY2'
    'F0ZWdvcnlDYXRhbG9nEjUKBWVycm9yGAQgASgLMh8ua2FydXlvbWkudjEuQnVzaW5lc3NTdGF0'
    'ZUVycm9yUgVlcnJvcg==');

@$core.Deprecated('Use readerSettingsDescriptor instead')
const ReaderSettings$json = {
  '1': 'ReaderSettings',
  '2': [
    {
      '1': 'mode',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderMode',
      '10': 'mode'
    },
    {
      '1': 'page_layout',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderPageLayout',
      '10': 'pageLayout'
    },
    {
      '1': 'background',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderBackground',
      '10': 'background'
    },
    {'1': 'dim_percent', '3': 4, '4': 1, '5': 13, '10': 'dimPercent'},
    {
      '1': 'tap_zones',
      '3': 5,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderInputPreset',
      '10': 'tapZones'
    },
    {
      '1': 'keyboard',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderInputPreset',
      '10': 'keyboard'
    },
    {
      '1': 'fit',
      '3': 7,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderFit',
      '10': 'fit'
    },
    {'1': 'crop_borders', '3': 8, '4': 1, '5': 8, '10': 'cropBorders'},
  ],
};

/// Descriptor for `ReaderSettings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readerSettingsDescriptor = $convert.base64Decode(
    'Cg5SZWFkZXJTZXR0aW5ncxIrCgRtb2RlGAEgASgOMhcua2FydXlvbWkudjEuUmVhZGVyTW9kZV'
    'IEbW9kZRI+CgtwYWdlX2xheW91dBgCIAEoDjIdLmthcnV5b21pLnYxLlJlYWRlclBhZ2VMYXlv'
    'dXRSCnBhZ2VMYXlvdXQSPQoKYmFja2dyb3VuZBgDIAEoDjIdLmthcnV5b21pLnYxLlJlYWRlck'
    'JhY2tncm91bmRSCmJhY2tncm91bmQSHwoLZGltX3BlcmNlbnQYBCABKA1SCmRpbVBlcmNlbnQS'
    'OwoJdGFwX3pvbmVzGAUgASgOMh4ua2FydXlvbWkudjEuUmVhZGVySW5wdXRQcmVzZXRSCHRhcF'
    'pvbmVzEjoKCGtleWJvYXJkGAYgASgOMh4ua2FydXlvbWkudjEuUmVhZGVySW5wdXRQcmVzZXRS'
    'CGtleWJvYXJkEigKA2ZpdBgHIAEoDjIWLmthcnV5b21pLnYxLlJlYWRlckZpdFIDZml0EiEKDG'
    'Nyb3BfYm9yZGVycxgIIAEoCFILY3JvcEJvcmRlcnM=');

@$core.Deprecated('Use readerSettingsOverrideDescriptor instead')
const ReaderSettingsOverride$json = {
  '1': 'ReaderSettingsOverride',
  '2': [
    {
      '1': 'mode',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderMode',
      '9': 0,
      '10': 'mode',
      '17': true
    },
    {
      '1': 'page_layout',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderPageLayout',
      '9': 1,
      '10': 'pageLayout',
      '17': true
    },
    {
      '1': 'background',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderBackground',
      '9': 2,
      '10': 'background',
      '17': true
    },
    {
      '1': 'dim_percent',
      '3': 4,
      '4': 1,
      '5': 13,
      '9': 3,
      '10': 'dimPercent',
      '17': true
    },
    {
      '1': 'tap_zones',
      '3': 5,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderInputPreset',
      '9': 4,
      '10': 'tapZones',
      '17': true
    },
    {
      '1': 'keyboard',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderInputPreset',
      '9': 5,
      '10': 'keyboard',
      '17': true
    },
    {
      '1': 'fit',
      '3': 7,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.ReaderFit',
      '9': 6,
      '10': 'fit',
      '17': true
    },
    {
      '1': 'crop_borders',
      '3': 8,
      '4': 1,
      '5': 8,
      '9': 7,
      '10': 'cropBorders',
      '17': true
    },
  ],
  '8': [
    {'1': '_mode'},
    {'1': '_page_layout'},
    {'1': '_background'},
    {'1': '_dim_percent'},
    {'1': '_tap_zones'},
    {'1': '_keyboard'},
    {'1': '_fit'},
    {'1': '_crop_borders'},
  ],
};

/// Descriptor for `ReaderSettingsOverride`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readerSettingsOverrideDescriptor = $convert.base64Decode(
    'ChZSZWFkZXJTZXR0aW5nc092ZXJyaWRlEjAKBG1vZGUYASABKA4yFy5rYXJ1eW9taS52MS5SZW'
    'FkZXJNb2RlSABSBG1vZGWIAQESQwoLcGFnZV9sYXlvdXQYAiABKA4yHS5rYXJ1eW9taS52MS5S'
    'ZWFkZXJQYWdlTGF5b3V0SAFSCnBhZ2VMYXlvdXSIAQESQgoKYmFja2dyb3VuZBgDIAEoDjIdLm'
    'thcnV5b21pLnYxLlJlYWRlckJhY2tncm91bmRIAlIKYmFja2dyb3VuZIgBARIkCgtkaW1fcGVy'
    'Y2VudBgEIAEoDUgDUgpkaW1QZXJjZW50iAEBEkAKCXRhcF96b25lcxgFIAEoDjIeLmthcnV5b2'
    '1pLnYxLlJlYWRlcklucHV0UHJlc2V0SARSCHRhcFpvbmVziAEBEj8KCGtleWJvYXJkGAYgASgO'
    'Mh4ua2FydXlvbWkudjEuUmVhZGVySW5wdXRQcmVzZXRIBVIIa2V5Ym9hcmSIAQESLQoDZml0GA'
    'cgASgOMhYua2FydXlvbWkudjEuUmVhZGVyRml0SAZSA2ZpdIgBARImCgxjcm9wX2JvcmRlcnMY'
    'CCABKAhIB1ILY3JvcEJvcmRlcnOIAQFCBwoFX21vZGVCDgoMX3BhZ2VfbGF5b3V0Qg0KC19iYW'
    'NrZ3JvdW5kQg4KDF9kaW1fcGVyY2VudEIMCgpfdGFwX3pvbmVzQgsKCV9rZXlib2FyZEIGCgRf'
    'Zml0Qg8KDV9jcm9wX2JvcmRlcnM=');

@$core.Deprecated('Use favoriteSourceDescriptor instead')
const FavoriteSource$json = {
  '1': 'FavoriteSource',
  '2': [
    {'1': 'package_name', '3': 1, '4': 1, '5': 9, '10': 'packageName'},
    {'1': 'source_id', '3': 2, '4': 1, '5': 9, '10': 'sourceId'},
    {'1': 'source_name', '3': 3, '4': 1, '5': 9, '10': 'sourceName'},
    {'1': 'source_lang', '3': 4, '4': 1, '5': 9, '10': 'sourceLang'},
  ],
};

/// Descriptor for `FavoriteSource`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List favoriteSourceDescriptor = $convert.base64Decode(
    'Cg5GYXZvcml0ZVNvdXJjZRIhCgxwYWNrYWdlX25hbWUYASABKAlSC3BhY2thZ2VOYW1lEhsKCX'
    'NvdXJjZV9pZBgCIAEoCVIIc291cmNlSWQSHwoLc291cmNlX25hbWUYAyABKAlSCnNvdXJjZU5h'
    'bWUSHwoLc291cmNlX2xhbmcYBCABKAlSCnNvdXJjZUxhbmc=');

@$core.Deprecated('Use globalSettingsValuesDescriptor instead')
const GlobalSettingsValues$json = {
  '1': 'GlobalSettingsValues',
  '2': [
    {
      '1': 'theme',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.AppTheme',
      '10': 'theme'
    },
    {
      '1': 'reader',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ReaderSettings',
      '10': 'reader'
    },
    {
      '1': 'favorite_sources',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.FavoriteSource',
      '10': 'favoriteSources'
    },
  ],
};

/// Descriptor for `GlobalSettingsValues`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List globalSettingsValuesDescriptor = $convert.base64Decode(
    'ChRHbG9iYWxTZXR0aW5nc1ZhbHVlcxIrCgV0aGVtZRgBIAEoDjIVLmthcnV5b21pLnYxLkFwcF'
    'RoZW1lUgV0aGVtZRIzCgZyZWFkZXIYAiABKAsyGy5rYXJ1eW9taS52MS5SZWFkZXJTZXR0aW5n'
    'c1IGcmVhZGVyEkYKEGZhdm9yaXRlX3NvdXJjZXMYAyADKAsyGy5rYXJ1eW9taS52MS5GYXZvcm'
    'l0ZVNvdXJjZVIPZmF2b3JpdGVTb3VyY2Vz');

@$core.Deprecated('Use globalSettingsDescriptor instead')
const GlobalSettings$json = {
  '1': 'GlobalSettings',
  '2': [
    {'1': 'revision', '3': 1, '4': 1, '5': 13, '10': 'revision'},
    {
      '1': 'values',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.GlobalSettingsValues',
      '10': 'values'
    },
  ],
};

/// Descriptor for `GlobalSettings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List globalSettingsDescriptor = $convert.base64Decode(
    'Cg5HbG9iYWxTZXR0aW5ncxIaCghyZXZpc2lvbhgBIAEoDVIIcmV2aXNpb24SOQoGdmFsdWVzGA'
    'IgASgLMiEua2FydXlvbWkudjEuR2xvYmFsU2V0dGluZ3NWYWx1ZXNSBnZhbHVlcw==');

@$core.Deprecated('Use mangaReaderSettingsDescriptor instead')
const MangaReaderSettings$json = {
  '1': 'MangaReaderSettings',
  '2': [
    {'1': 'manga_key', '3': 1, '4': 1, '5': 9, '10': 'mangaKey'},
    {'1': 'revision', '3': 2, '4': 1, '5': 13, '10': 'revision'},
    {
      '1': 'overrides',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ReaderSettingsOverride',
      '10': 'overrides'
    },
  ],
};

/// Descriptor for `MangaReaderSettings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mangaReaderSettingsDescriptor = $convert.base64Decode(
    'ChNNYW5nYVJlYWRlclNldHRpbmdzEhsKCW1hbmdhX2tleRgBIAEoCVIIbWFuZ2FLZXkSGgoIcm'
    'V2aXNpb24YAiABKA1SCHJldmlzaW9uEkEKCW92ZXJyaWRlcxgDIAEoCzIjLmthcnV5b21pLnYx'
    'LlJlYWRlclNldHRpbmdzT3ZlcnJpZGVSCW92ZXJyaWRlcw==');

@$core.Deprecated('Use setMangaReaderSettingsDescriptor instead')
const SetMangaReaderSettings$json = {
  '1': 'SetMangaReaderSettings',
  '2': [
    {'1': 'manga_key', '3': 1, '4': 1, '5': 9, '10': 'mangaKey'},
    {
      '1': 'overrides',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ReaderSettingsOverride',
      '10': 'overrides'
    },
  ],
};

/// Descriptor for `SetMangaReaderSettings`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setMangaReaderSettingsDescriptor = $convert.base64Decode(
    'ChZTZXRNYW5nYVJlYWRlclNldHRpbmdzEhsKCW1hbmdhX2tleRgBIAEoCVIIbWFuZ2FLZXkSQQ'
    'oJb3ZlcnJpZGVzGAIgASgLMiMua2FydXlvbWkudjEuUmVhZGVyU2V0dGluZ3NPdmVycmlkZVIJ'
    'b3ZlcnJpZGVz');

@$core.Deprecated('Use settingsMutationDescriptor instead')
const SettingsMutation$json = {
  '1': 'SettingsMutation',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'mutation_id', '3': 2, '4': 1, '5': 9, '10': 'mutationId'},
    {
      '1': 'expected_revision',
      '3': 3,
      '4': 1,
      '5': 13,
      '10': 'expectedRevision'
    },
    {
      '1': 'set_global',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.GlobalSettingsValues',
      '9': 0,
      '10': 'setGlobal'
    },
    {
      '1': 'set_manga',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SetMangaReaderSettings',
      '9': 0,
      '10': 'setManga'
    },
  ],
  '8': [
    {'1': 'operation'},
  ],
};

/// Descriptor for `SettingsMutation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List settingsMutationDescriptor = $convert.base64Decode(
    'ChBTZXR0aW5nc011dGF0aW9uEiUKDnNjaGVtYV92ZXJzaW9uGAEgASgNUg1zY2hlbWFWZXJzaW'
    '9uEh8KC211dGF0aW9uX2lkGAIgASgJUgptdXRhdGlvbklkEisKEWV4cGVjdGVkX3JldmlzaW9u'
    'GAMgASgNUhBleHBlY3RlZFJldmlzaW9uEkIKCnNldF9nbG9iYWwYCiABKAsyIS5rYXJ1eW9taS'
    '52MS5HbG9iYWxTZXR0aW5nc1ZhbHVlc0gAUglzZXRHbG9iYWwSQgoJc2V0X21hbmdhGAsgASgL'
    'MiMua2FydXlvbWkudjEuU2V0TWFuZ2FSZWFkZXJTZXR0aW5nc0gAUghzZXRNYW5nYUILCglvcG'
    'VyYXRpb24=');

@$core.Deprecated('Use settingsResponseDescriptor instead')
const SettingsResponse$json = {
  '1': 'SettingsResponse',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'account_revision', '3': 2, '4': 1, '5': 13, '10': 'accountRevision'},
    {
      '1': 'global',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.GlobalSettings',
      '10': 'global'
    },
    {
      '1': 'manga',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.MangaReaderSettings',
      '10': 'manga'
    },
    {
      '1': 'effective_reader',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ReaderSettings',
      '10': 'effectiveReader'
    },
    {
      '1': 'error',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BusinessStateError',
      '10': 'error'
    },
  ],
};

/// Descriptor for `SettingsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List settingsResponseDescriptor = $convert.base64Decode(
    'ChBTZXR0aW5nc1Jlc3BvbnNlEiUKDnNjaGVtYV92ZXJzaW9uGAEgASgNUg1zY2hlbWFWZXJzaW'
    '9uEikKEGFjY291bnRfcmV2aXNpb24YAiABKA1SD2FjY291bnRSZXZpc2lvbhIzCgZnbG9iYWwY'
    'AyABKAsyGy5rYXJ1eW9taS52MS5HbG9iYWxTZXR0aW5nc1IGZ2xvYmFsEjYKBW1hbmdhGAQgAS'
    'gLMiAua2FydXlvbWkudjEuTWFuZ2FSZWFkZXJTZXR0aW5nc1IFbWFuZ2ESRgoQZWZmZWN0aXZl'
    'X3JlYWRlchgFIAEoCzIbLmthcnV5b21pLnYxLlJlYWRlclNldHRpbmdzUg9lZmZlY3RpdmVSZW'
    'FkZXISNQoFZXJyb3IYBiABKAsyHy5rYXJ1eW9taS52MS5CdXNpbmVzc1N0YXRlRXJyb3JSBWVy'
    'cm9y');

@$core.Deprecated('Use settingsMutationResponseDescriptor instead')
const SettingsMutationResponse$json = {
  '1': 'SettingsMutationResponse',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'mutation_id', '3': 2, '4': 1, '5': 9, '10': 'mutationId'},
    {'1': 'account_revision', '3': 3, '4': 1, '5': 13, '10': 'accountRevision'},
    {
      '1': 'global',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.GlobalSettings',
      '10': 'global'
    },
    {
      '1': 'manga',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.MangaReaderSettings',
      '10': 'manga'
    },
    {
      '1': 'effective_reader',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ReaderSettings',
      '10': 'effectiveReader'
    },
    {
      '1': 'error',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BusinessStateError',
      '10': 'error'
    },
  ],
};

/// Descriptor for `SettingsMutationResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List settingsMutationResponseDescriptor = $convert.base64Decode(
    'ChhTZXR0aW5nc011dGF0aW9uUmVzcG9uc2USJQoOc2NoZW1hX3ZlcnNpb24YASABKA1SDXNjaG'
    'VtYVZlcnNpb24SHwoLbXV0YXRpb25faWQYAiABKAlSCm11dGF0aW9uSWQSKQoQYWNjb3VudF9y'
    'ZXZpc2lvbhgDIAEoDVIPYWNjb3VudFJldmlzaW9uEjMKBmdsb2JhbBgEIAEoCzIbLmthcnV5b2'
    '1pLnYxLkdsb2JhbFNldHRpbmdzUgZnbG9iYWwSNgoFbWFuZ2EYBSABKAsyIC5rYXJ1eW9taS52'
    'MS5NYW5nYVJlYWRlclNldHRpbmdzUgVtYW5nYRJGChBlZmZlY3RpdmVfcmVhZGVyGAYgASgLMh'
    'sua2FydXlvbWkudjEuUmVhZGVyU2V0dGluZ3NSD2VmZmVjdGl2ZVJlYWRlchI1CgVlcnJvchgH'
    'IAEoCzIfLmthcnV5b21pLnYxLkJ1c2luZXNzU3RhdGVFcnJvclIFZXJyb3I=');

@$core.Deprecated('Use sourcePreferencesDescriptor instead')
const SourcePreferences$json = {
  '1': 'SourcePreferences',
  '2': [
    {'1': 'package_name', '3': 1, '4': 1, '5': 9, '10': 'packageName'},
    {'1': 'source_id', '3': 2, '4': 1, '5': 9, '10': 'sourceId'},
    {'1': 'revision', '3': 3, '4': 1, '5': 13, '10': 'revision'},
    {
      '1': 'entries',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.PreferenceEntry',
      '10': 'entries'
    },
  ],
};

/// Descriptor for `SourcePreferences`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sourcePreferencesDescriptor = $convert.base64Decode(
    'ChFTb3VyY2VQcmVmZXJlbmNlcxIhCgxwYWNrYWdlX25hbWUYASABKAlSC3BhY2thZ2VOYW1lEh'
    'sKCXNvdXJjZV9pZBgCIAEoCVIIc291cmNlSWQSGgoIcmV2aXNpb24YAyABKA1SCHJldmlzaW9u'
    'EjYKB2VudHJpZXMYBCADKAsyHC5rYXJ1eW9taS52MS5QcmVmZXJlbmNlRW50cnlSB2VudHJpZX'
    'M=');

@$core.Deprecated('Use sourcePreferencesResponseDescriptor instead')
const SourcePreferencesResponse$json = {
  '1': 'SourcePreferencesResponse',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'account_revision', '3': 2, '4': 1, '5': 13, '10': 'accountRevision'},
    {'1': 'package_name', '3': 3, '4': 1, '5': 9, '10': 'packageName'},
    {
      '1': 'sources',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.SourcePreferences',
      '10': 'sources'
    },
    {
      '1': 'error',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BusinessStateError',
      '10': 'error'
    },
  ],
};

/// Descriptor for `SourcePreferencesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sourcePreferencesResponseDescriptor = $convert.base64Decode(
    'ChlTb3VyY2VQcmVmZXJlbmNlc1Jlc3BvbnNlEiUKDnNjaGVtYV92ZXJzaW9uGAEgASgNUg1zY2'
    'hlbWFWZXJzaW9uEikKEGFjY291bnRfcmV2aXNpb24YAiABKA1SD2FjY291bnRSZXZpc2lvbhIh'
    'CgxwYWNrYWdlX25hbWUYAyABKAlSC3BhY2thZ2VOYW1lEjgKB3NvdXJjZXMYBCADKAsyHi5rYX'
    'J1eW9taS52MS5Tb3VyY2VQcmVmZXJlbmNlc1IHc291cmNlcxI1CgVlcnJvchgFIAEoCzIfLmth'
    'cnV5b21pLnYxLkJ1c2luZXNzU3RhdGVFcnJvclIFZXJyb3I=');

@$core.Deprecated('Use sourcePreferencesMutationDescriptor instead')
const SourcePreferencesMutation$json = {
  '1': 'SourcePreferencesMutation',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'mutation_id', '3': 2, '4': 1, '5': 9, '10': 'mutationId'},
    {'1': 'package_name', '3': 3, '4': 1, '5': 9, '10': 'packageName'},
    {'1': 'source_id', '3': 4, '4': 1, '5': 9, '10': 'sourceId'},
    {
      '1': 'expected_revision',
      '3': 5,
      '4': 1,
      '5': 13,
      '10': 'expectedRevision'
    },
    {
      '1': 'entries',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.PreferenceEntry',
      '10': 'entries'
    },
  ],
};

/// Descriptor for `SourcePreferencesMutation`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sourcePreferencesMutationDescriptor = $convert.base64Decode(
    'ChlTb3VyY2VQcmVmZXJlbmNlc011dGF0aW9uEiUKDnNjaGVtYV92ZXJzaW9uGAEgASgNUg1zY2'
    'hlbWFWZXJzaW9uEh8KC211dGF0aW9uX2lkGAIgASgJUgptdXRhdGlvbklkEiEKDHBhY2thZ2Vf'
    'bmFtZRgDIAEoCVILcGFja2FnZU5hbWUSGwoJc291cmNlX2lkGAQgASgJUghzb3VyY2VJZBIrCh'
    'FleHBlY3RlZF9yZXZpc2lvbhgFIAEoDVIQZXhwZWN0ZWRSZXZpc2lvbhI2CgdlbnRyaWVzGAYg'
    'AygLMhwua2FydXlvbWkudjEuUHJlZmVyZW5jZUVudHJ5UgdlbnRyaWVz');

@$core.Deprecated('Use sourcePreferencesMutationResponseDescriptor instead')
const SourcePreferencesMutationResponse$json = {
  '1': 'SourcePreferencesMutationResponse',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'mutation_id', '3': 2, '4': 1, '5': 9, '10': 'mutationId'},
    {'1': 'account_revision', '3': 3, '4': 1, '5': 13, '10': 'accountRevision'},
    {
      '1': 'preferences',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SourcePreferences',
      '10': 'preferences'
    },
    {
      '1': 'error',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BusinessStateError',
      '10': 'error'
    },
  ],
};

/// Descriptor for `SourcePreferencesMutationResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sourcePreferencesMutationResponseDescriptor = $convert.base64Decode(
    'CiFTb3VyY2VQcmVmZXJlbmNlc011dGF0aW9uUmVzcG9uc2USJQoOc2NoZW1hX3ZlcnNpb24YAS'
    'ABKA1SDXNjaGVtYVZlcnNpb24SHwoLbXV0YXRpb25faWQYAiABKAlSCm11dGF0aW9uSWQSKQoQ'
    'YWNjb3VudF9yZXZpc2lvbhgDIAEoDVIPYWNjb3VudFJldmlzaW9uEkAKC3ByZWZlcmVuY2VzGA'
    'QgASgLMh4ua2FydXlvbWkudjEuU291cmNlUHJlZmVyZW5jZXNSC3ByZWZlcmVuY2VzEjUKBWVy'
    'cm9yGAUgASgLMh8ua2FydXlvbWkudjEuQnVzaW5lc3NTdGF0ZUVycm9yUgVlcnJvcg==');
