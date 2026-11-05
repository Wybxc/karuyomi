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
  ],
};

/// Descriptor for `MangaState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mangaStateDescriptor = $convert.base64Decode(
    'CgpNYW5nYVN0YXRlEhsKCW1hbmdhX2tleRgBIAEoCVIIbWFuZ2FLZXkSGgoIcmV2aXNpb24YAi'
    'ABKA1SCHJldmlzaW9uEjgKCG1ldGFkYXRhGAMgASgLMhwua2FydXlvbWkudjEuTGlicmFyeU1l'
    'dGFkYXRhUghtZXRhZGF0YRIaCghmYXZvcml0ZRgEIAEoCFIIZmF2b3JpdGUSKAoQYWRkZWRfYX'
    'Rfc2Vjb25kcxgFIAEoDVIOYWRkZWRBdFNlY29uZHMSMAoGcmVzdW1lGAYgASgLMhgua2FydXlv'
    'bWkudjEuTWFuZ2FSZXN1bWVSBnJlc3VtZQ==');

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
  ],
};

/// Descriptor for `ReadingAnchor`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readingAnchorDescriptor = $convert.base64Decode(
    'Cg1SZWFkaW5nQW5jaG9yEh8KC2NoYXB0ZXJfa2V5GAEgASgJUgpjaGFwdGVyS2V5EhkKCHBhZ2'
    'Vfa2V5GAIgASgJUgdwYWdlS2V5EikKEG1hbmlmZXN0X3ZlcnNpb24YAyABKAlSD21hbmlmZXN0'
    'VmVyc2lvbhImCg9wYWdlX2luZGV4X2hpbnQYBCABKA1SDXBhZ2VJbmRleEhpbnQSKwoRbm9ybW'
    'FsaXplZF9vZmZzZXQYBSABKAFSEG5vcm1hbGl6ZWRPZmZzZXQ=');

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
    'oua2FydXlvbWkudjEuUmVzZXRQcm9ncmVzc0gAUg1yZXNldFByb2dyZXNzQgsKCW9wZXJhdGlv'
    'bg==');

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
  ],
};

/// Descriptor for `StateMutationResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stateMutationResponseDescriptor = $convert.base64Decode(
    'ChVTdGF0ZU11dGF0aW9uUmVzcG9uc2USJQoOc2NoZW1hX3ZlcnNpb24YASABKA1SDXNjaGVtYV'
    'ZlcnNpb24SHwoLbXV0YXRpb25faWQYAiABKAlSCm11dGF0aW9uSWQSKQoQYWNjb3VudF9yZXZp'
    'c2lvbhgDIAEoDVIPYWNjb3VudFJldmlzaW9uEi0KBW1hbmdhGAQgASgLMhcua2FydXlvbWkudj'
    'EuTWFuZ2FTdGF0ZVIFbWFuZ2ESPQoIcHJvZ3Jlc3MYBSABKAsyIS5rYXJ1eW9taS52MS5DaGFw'
    'dGVyUHJvZ3Jlc3NTdGF0ZVIIcHJvZ3Jlc3MSNQoFZXJyb3IYBiABKAsyHy5rYXJ1eW9taS52MS'
    '5CdXNpbmVzc1N0YXRlRXJyb3JSBWVycm9y');

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
  ],
};

/// Descriptor for `MangaStateResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mangaStateResponseDescriptor = $convert.base64Decode(
    'ChJNYW5nYVN0YXRlUmVzcG9uc2USJQoOc2NoZW1hX3ZlcnNpb24YASABKA1SDXNjaGVtYVZlcn'
    'Npb24SKQoQYWNjb3VudF9yZXZpc2lvbhgCIAEoDVIPYWNjb3VudFJldmlzaW9uEi0KBW1hbmdh'
    'GAMgASgLMhcua2FydXlvbWkudjEuTWFuZ2FTdGF0ZVIFbWFuZ2ESPQoIcHJvZ3Jlc3MYBCABKA'
    'syIS5rYXJ1eW9taS52MS5DaGFwdGVyUHJvZ3Jlc3NTdGF0ZVIIcHJvZ3Jlc3MSNQoFZXJyb3IY'
    'BSABKAsyHy5rYXJ1eW9taS52MS5CdXNpbmVzc1N0YXRlRXJyb3JSBWVycm9y');

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
  ],
};

/// Descriptor for `LibraryPageResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List libraryPageResponseDescriptor = $convert.base64Decode(
    'ChNMaWJyYXJ5UGFnZVJlc3BvbnNlEiUKDnNjaGVtYV92ZXJzaW9uGAEgASgNUg1zY2hlbWFWZX'
    'JzaW9uEikKEGFjY291bnRfcmV2aXNpb24YAiABKA1SD2FjY291bnRSZXZpc2lvbhIxCgdlbnRy'
    'aWVzGAMgAygLMhcua2FydXlvbWkudjEuTWFuZ2FTdGF0ZVIHZW50cmllcxIZCghuZXh0X2tleR'
    'gEIAEoCVIHbmV4dEtleRI1CgVlcnJvchgFIAEoCzIfLmthcnV5b21pLnYxLkJ1c2luZXNzU3Rh'
    'dGVFcnJvclIFZXJyb3I=');
