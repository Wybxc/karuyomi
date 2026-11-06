// This is a generated file - do not edit.
//
// Generated from karuyomi/v1/control.proto.

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

@$core.Deprecated('Use runtimeErrorCodeDescriptor instead')
const RuntimeErrorCode$json = {
  '1': 'RuntimeErrorCode',
  '2': [
    {'1': 'RUNTIME_ERROR_CODE_UNSPECIFIED', '2': 0},
    {'1': 'RUNTIME_ERROR_CODE_CANCELLED', '2': 1},
    {'1': 'RUNTIME_ERROR_CODE_TIMEOUT', '2': 2},
    {'1': 'RUNTIME_ERROR_CODE_ACCESS_REQUIRED', '2': 3},
    {'1': 'RUNTIME_ERROR_CODE_ACCESS_DENIED', '2': 4},
    {'1': 'RUNTIME_ERROR_CODE_SOURCE_ERROR', '2': 5},
    {'1': 'RUNTIME_ERROR_CODE_UNSUPPORTED_CAPABILITY', '2': 6},
    {'1': 'RUNTIME_ERROR_CODE_RUNTIME_LOST', '2': 7},
    {'1': 'RUNTIME_ERROR_CODE_PROTOCOL_ERROR', '2': 8},
    {'1': 'RUNTIME_ERROR_CODE_INTEGRITY_ERROR', '2': 9},
    {'1': 'RUNTIME_ERROR_CODE_LIMIT_EXCEEDED', '2': 10},
    {'1': 'RUNTIME_ERROR_CODE_STORAGE_BUSY', '2': 11},
  ],
};

/// Descriptor for `RuntimeErrorCode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List runtimeErrorCodeDescriptor = $convert.base64Decode(
    'ChBSdW50aW1lRXJyb3JDb2RlEiIKHlJVTlRJTUVfRVJST1JfQ09ERV9VTlNQRUNJRklFRBAAEi'
    'AKHFJVTlRJTUVfRVJST1JfQ09ERV9DQU5DRUxMRUQQARIeChpSVU5USU1FX0VSUk9SX0NPREVf'
    'VElNRU9VVBACEiYKIlJVTlRJTUVfRVJST1JfQ09ERV9BQ0NFU1NfUkVRVUlSRUQQAxIkCiBSVU'
    '5USU1FX0VSUk9SX0NPREVfQUNDRVNTX0RFTklFRBAEEiMKH1JVTlRJTUVfRVJST1JfQ09ERV9T'
    'T1VSQ0VfRVJST1IQBRItCilSVU5USU1FX0VSUk9SX0NPREVfVU5TVVBQT1JURURfQ0FQQUJJTE'
    'lUWRAGEiMKH1JVTlRJTUVfRVJST1JfQ09ERV9SVU5USU1FX0xPU1QQBxIlCiFSVU5USU1FX0VS'
    'Uk9SX0NPREVfUFJPVE9DT0xfRVJST1IQCBImCiJSVU5USU1FX0VSUk9SX0NPREVfSU5URUdSSV'
    'RZX0VSUk9SEAkSJQohUlVOVElNRV9FUlJPUl9DT0RFX0xJTUlUX0VYQ0VFREVEEAoSIwofUlVO'
    'VElNRV9FUlJPUl9DT0RFX1NUT1JBR0VfQlVTWRAL');

@$core.Deprecated('Use bootstrapStageDescriptor instead')
const BootstrapStage$json = {
  '1': 'BootstrapStage',
  '2': [
    {'1': 'BOOTSTRAP_STAGE_UNSPECIFIED', '2': 0},
    {'1': 'BOOTSTRAP_STAGE_SCAFFOLD', '2': 1},
    {'1': 'BOOTSTRAP_STAGE_P0', '2': 2},
  ],
};

/// Descriptor for `BootstrapStage`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List bootstrapStageDescriptor = $convert.base64Decode(
    'Cg5Cb290c3RyYXBTdGFnZRIfChtCT09UU1RSQVBfU1RBR0VfVU5TUEVDSUZJRUQQABIcChhCT0'
    '9UU1RSQVBfU1RBR0VfU0NBRkZPTEQQARIWChJCT09UU1RSQVBfU1RBR0VfUDAQAg==');

@$core.Deprecated('Use emptyDescriptor instead')
const Empty$json = {
  '1': 'Empty',
};

/// Descriptor for `Empty`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List emptyDescriptor =
    $convert.base64Decode('CgVFbXB0eQ==');

@$core.Deprecated('Use runtimeErrorDescriptor instead')
const RuntimeError$json = {
  '1': 'RuntimeError',
  '2': [
    {
      '1': 'code',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.RuntimeErrorCode',
      '10': 'code'
    },
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'retryable', '3': 3, '4': 1, '5': 8, '10': 'retryable'},
    {
      '1': 'java_class',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'javaClass',
      '17': true
    },
  ],
  '8': [
    {'1': '_java_class'},
  ],
};

/// Descriptor for `RuntimeError`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List runtimeErrorDescriptor = $convert.base64Decode(
    'CgxSdW50aW1lRXJyb3ISMQoEY29kZRgBIAEoDjIdLmthcnV5b21pLnYxLlJ1bnRpbWVFcnJvck'
    'NvZGVSBGNvZGUSGAoHbWVzc2FnZRgCIAEoCVIHbWVzc2FnZRIcCglyZXRyeWFibGUYAyABKAhS'
    'CXJldHJ5YWJsZRIiCgpqYXZhX2NsYXNzGAQgASgJSABSCWphdmFDbGFzc4gBAUINCgtfamF2YV'
    '9jbGFzcw==');

@$core.Deprecated('Use runtimeHelloDescriptor instead')
const RuntimeHello$json = {
  '1': 'RuntimeHello',
  '2': [
    {'1': 'protocol_version', '3': 1, '4': 1, '5': 13, '10': 'protocolVersion'},
    {'1': 'host_abi', '3': 2, '4': 1, '5': 9, '10': 'hostAbi'},
    {'1': 'runtime_baseline', '3': 3, '4': 1, '5': 9, '10': 'runtimeBaseline'},
    {'1': 'generation', '3': 4, '4': 1, '5': 9, '10': 'generation'},
    {'1': 'capabilities', '3': 5, '4': 3, '5': 9, '10': 'capabilities'},
    {'1': 'source_ready', '3': 6, '4': 1, '5': 8, '10': 'sourceReady'},
  ],
};

/// Descriptor for `RuntimeHello`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List runtimeHelloDescriptor = $convert.base64Decode(
    'CgxSdW50aW1lSGVsbG8SKQoQcHJvdG9jb2xfdmVyc2lvbhgBIAEoDVIPcHJvdG9jb2xWZXJzaW'
    '9uEhkKCGhvc3RfYWJpGAIgASgJUgdob3N0QWJpEikKEHJ1bnRpbWVfYmFzZWxpbmUYAyABKAlS'
    'D3J1bnRpbWVCYXNlbGluZRIeCgpnZW5lcmF0aW9uGAQgASgJUgpnZW5lcmF0aW9uEiIKDGNhcG'
    'FiaWxpdGllcxgFIAMoCVIMY2FwYWJpbGl0aWVzEiEKDHNvdXJjZV9yZWFkeRgGIAEoCFILc291'
    'cmNlUmVhZHk=');

@$core.Deprecated('Use sourceInfoDescriptor instead')
const SourceInfo$json = {
  '1': 'SourceInfo',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'lang', '3': 3, '4': 1, '5': 9, '10': 'lang'},
    {
      '1': 'supports_latest',
      '3': 4,
      '4': 1,
      '5': 8,
      '9': 0,
      '10': 'supportsLatest',
      '17': true
    },
    {
      '1': 'base_url',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'baseUrl',
      '17': true
    },
  ],
  '8': [
    {'1': '_supports_latest'},
    {'1': '_base_url'},
  ],
};

/// Descriptor for `SourceInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sourceInfoDescriptor = $convert.base64Decode(
    'CgpTb3VyY2VJbmZvEg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEhIKBGxhbm'
    'cYAyABKAlSBGxhbmcSLAoPc3VwcG9ydHNfbGF0ZXN0GAQgASgISABSDnN1cHBvcnRzTGF0ZXN0'
    'iAEBEh4KCGJhc2VfdXJsGAUgASgJSAFSB2Jhc2VVcmyIAQFCEgoQX3N1cHBvcnRzX2xhdGVzdE'
    'ILCglfYmFzZV91cmw=');

@$core.Deprecated('Use runtimeSessionDescriptor instead')
const RuntimeSession$json = {
  '1': 'RuntimeSession',
  '2': [
    {'1': 'protocol_version', '3': 1, '4': 1, '5': 13, '10': 'protocolVersion'},
    {
      '1': 'worker_instance_id',
      '3': 2,
      '4': 1,
      '5': 9,
      '10': 'workerInstanceId'
    },
    {'1': 'generation', '3': 3, '4': 1, '5': 9, '10': 'generation'},
    {'1': 'build_id', '3': 4, '4': 1, '5': 9, '10': 'buildId'},
    {
      '1': 'sources',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.SourceInfo',
      '10': 'sources'
    },
    {'1': 'capabilities', '3': 6, '4': 3, '5': 9, '10': 'capabilities'},
  ],
};

/// Descriptor for `RuntimeSession`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List runtimeSessionDescriptor = $convert.base64Decode(
    'Cg5SdW50aW1lU2Vzc2lvbhIpChBwcm90b2NvbF92ZXJzaW9uGAEgASgNUg9wcm90b2NvbFZlcn'
    'Npb24SLAoSd29ya2VyX2luc3RhbmNlX2lkGAIgASgJUhB3b3JrZXJJbnN0YW5jZUlkEh4KCmdl'
    'bmVyYXRpb24YAyABKAlSCmdlbmVyYXRpb24SGQoIYnVpbGRfaWQYBCABKAlSB2J1aWxkSWQSMQ'
    'oHc291cmNlcxgFIAMoCzIXLmthcnV5b21pLnYxLlNvdXJjZUluZm9SB3NvdXJjZXMSIgoMY2Fw'
    'YWJpbGl0aWVzGAYgAygJUgxjYXBhYmlsaXRpZXM=');

@$core.Deprecated('Use rpcEnvelopeDescriptor instead')
const RpcEnvelope$json = {
  '1': 'RpcEnvelope',
  '2': [
    {'1': 'protocol_version', '3': 1, '4': 1, '5': 13, '10': 'protocolVersion'},
    {
      '1': 'worker_instance_id',
      '3': 2,
      '4': 1,
      '5': 9,
      '10': 'workerInstanceId'
    },
    {'1': 'generation', '3': 3, '4': 1, '5': 9, '10': 'generation'},
    {'1': 'build_id', '3': 4, '4': 1, '5': 9, '10': 'buildId'},
    {'1': 'request_id', '3': 5, '4': 1, '5': 9, '10': 'requestId'},
  ],
};

/// Descriptor for `RpcEnvelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rpcEnvelopeDescriptor = $convert.base64Decode(
    'CgtScGNFbnZlbG9wZRIpChBwcm90b2NvbF92ZXJzaW9uGAEgASgNUg9wcm90b2NvbFZlcnNpb2'
    '4SLAoSd29ya2VyX2luc3RhbmNlX2lkGAIgASgJUhB3b3JrZXJJbnN0YW5jZUlkEh4KCmdlbmVy'
    'YXRpb24YAyABKAlSCmdlbmVyYXRpb24SGQoIYnVpbGRfaWQYBCABKAlSB2J1aWxkSWQSHQoKcm'
    'VxdWVzdF9pZBgFIAEoCVIJcmVxdWVzdElk');

@$core.Deprecated('Use openRequestDescriptor instead')
const OpenRequest$json = {
  '1': 'OpenRequest',
  '2': [
    {'1': 'manifest_path', '3': 1, '4': 1, '5': 9, '10': 'manifestPath'},
    {'1': 'identity', '3': 2, '4': 1, '5': 9, '10': 'identity'},
    {
      '1': 'user_agent',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'userAgent',
      '17': true
    },
    {
      '1': 'expected_build_id',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'expectedBuildId',
      '17': true
    },
    {
      '1': 'expected_bundle_sha256',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 2,
      '10': 'expectedBundleSha256',
      '17': true
    },
  ],
  '8': [
    {'1': '_user_agent'},
    {'1': '_expected_build_id'},
    {'1': '_expected_bundle_sha256'},
  ],
};

/// Descriptor for `OpenRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List openRequestDescriptor = $convert.base64Decode(
    'CgtPcGVuUmVxdWVzdBIjCg1tYW5pZmVzdF9wYXRoGAEgASgJUgxtYW5pZmVzdFBhdGgSGgoIaW'
    'RlbnRpdHkYAiABKAlSCGlkZW50aXR5EiIKCnVzZXJfYWdlbnQYAyABKAlIAFIJdXNlckFnZW50'
    'iAEBEi8KEWV4cGVjdGVkX2J1aWxkX2lkGAQgASgJSAFSD2V4cGVjdGVkQnVpbGRJZIgBARI5Ch'
    'ZleHBlY3RlZF9idW5kbGVfc2hhMjU2GAUgASgJSAJSFGV4cGVjdGVkQnVuZGxlU2hhMjU2iAEB'
    'Qg0KC191c2VyX2FnZW50QhQKEl9leHBlY3RlZF9idWlsZF9pZEIZChdfZXhwZWN0ZWRfYnVuZG'
    'xlX3NoYTI1Ng==');

@$core.Deprecated('Use mangaDescriptor instead')
const Manga$json = {
  '1': 'Manga',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'author', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'author', '17': true},
    {'1': 'artist', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'artist', '17': true},
    {
      '1': 'description',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 2,
      '10': 'description',
      '17': true
    },
    {'1': 'genre', '3': 6, '4': 1, '5': 9, '9': 3, '10': 'genre', '17': true},
    {'1': 'genres', '3': 7, '4': 3, '5': 9, '10': 'genres'},
    {'1': 'status', '3': 8, '4': 1, '5': 5, '10': 'status'},
    {
      '1': 'thumbnail_url',
      '3': 9,
      '4': 1,
      '5': 9,
      '9': 4,
      '10': 'thumbnailUrl',
      '17': true
    },
    {'1': 'initialized', '3': 10, '4': 1, '5': 8, '10': 'initialized'},
    {'1': 'update_strategy', '3': 11, '4': 1, '5': 9, '10': 'updateStrategy'},
    {
      '1': 'memo_json',
      '3': 12,
      '4': 1,
      '5': 9,
      '9': 5,
      '10': 'memoJson',
      '17': true
    },
  ],
  '8': [
    {'1': '_author'},
    {'1': '_artist'},
    {'1': '_description'},
    {'1': '_genre'},
    {'1': '_thumbnail_url'},
    {'1': '_memo_json'},
  ],
};

/// Descriptor for `Manga`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mangaDescriptor = $convert.base64Decode(
    'CgVNYW5nYRIQCgN1cmwYASABKAlSA3VybBIUCgV0aXRsZRgCIAEoCVIFdGl0bGUSGwoGYXV0aG'
    '9yGAMgASgJSABSBmF1dGhvcogBARIbCgZhcnRpc3QYBCABKAlIAVIGYXJ0aXN0iAEBEiUKC2Rl'
    'c2NyaXB0aW9uGAUgASgJSAJSC2Rlc2NyaXB0aW9uiAEBEhkKBWdlbnJlGAYgASgJSANSBWdlbn'
    'JliAEBEhYKBmdlbnJlcxgHIAMoCVIGZ2VucmVzEhYKBnN0YXR1cxgIIAEoBVIGc3RhdHVzEigK'
    'DXRodW1ibmFpbF91cmwYCSABKAlIBFIMdGh1bWJuYWlsVXJsiAEBEiAKC2luaXRpYWxpemVkGA'
    'ogASgIUgtpbml0aWFsaXplZBInCg91cGRhdGVfc3RyYXRlZ3kYCyABKAlSDnVwZGF0ZVN0cmF0'
    'ZWd5EiAKCW1lbW9fanNvbhgMIAEoCUgFUghtZW1vSnNvbogBAUIJCgdfYXV0aG9yQgkKB19hcn'
    'Rpc3RCDgoMX2Rlc2NyaXB0aW9uQggKBl9nZW5yZUIQCg5fdGh1bWJuYWlsX3VybEIMCgpfbWVt'
    'b19qc29u');

@$core.Deprecated('Use chapterDescriptor instead')
const Chapter$json = {
  '1': 'Chapter',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'chapter_number',
      '3': 3,
      '4': 1,
      '5': 2,
      '9': 0,
      '10': 'chapterNumber',
      '17': true
    },
    {
      '1': 'scanlator',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'scanlator',
      '17': true
    },
    {'1': 'date_upload', '3': 5, '4': 1, '5': 9, '10': 'dateUpload'},
    {'1': 'source_order', '3': 6, '4': 1, '5': 13, '10': 'sourceOrder'},
    {
      '1': 'memo_json',
      '3': 7,
      '4': 1,
      '5': 9,
      '9': 2,
      '10': 'memoJson',
      '17': true
    },
  ],
  '8': [
    {'1': '_chapter_number'},
    {'1': '_scanlator'},
    {'1': '_memo_json'},
  ],
};

/// Descriptor for `Chapter`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chapterDescriptor = $convert.base64Decode(
    'CgdDaGFwdGVyEhAKA3VybBgBIAEoCVIDdXJsEhIKBG5hbWUYAiABKAlSBG5hbWUSKgoOY2hhcH'
    'Rlcl9udW1iZXIYAyABKAJIAFINY2hhcHRlck51bWJlcogBARIhCglzY2FubGF0b3IYBCABKAlI'
    'AVIJc2NhbmxhdG9yiAEBEh8KC2RhdGVfdXBsb2FkGAUgASgJUgpkYXRlVXBsb2FkEiEKDHNvdX'
    'JjZV9vcmRlchgGIAEoDVILc291cmNlT3JkZXISIAoJbWVtb19qc29uGAcgASgJSAJSCG1lbW9K'
    'c29uiAEBQhEKD19jaGFwdGVyX251bWJlckIMCgpfc2NhbmxhdG9yQgwKCl9tZW1vX2pzb24=');

@$core.Deprecated('Use pageDescriptor instead')
const Page$json = {
  '1': 'Page',
  '2': [
    {'1': 'page_key', '3': 1, '4': 1, '5': 9, '10': 'pageKey'},
    {'1': 'index', '3': 2, '4': 1, '5': 13, '10': 'index'},
    {'1': 'source_index', '3': 3, '4': 1, '5': 5, '10': 'sourceIndex'},
    {'1': 'url', '3': 4, '4': 1, '5': 9, '10': 'url'},
    {
      '1': 'image_url',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'imageUrl',
      '17': true
    },
  ],
  '8': [
    {'1': '_image_url'},
  ],
};

/// Descriptor for `Page`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pageDescriptor = $convert.base64Decode(
    'CgRQYWdlEhkKCHBhZ2Vfa2V5GAEgASgJUgdwYWdlS2V5EhQKBWluZGV4GAIgASgNUgVpbmRleB'
    'IhCgxzb3VyY2VfaW5kZXgYAyABKAVSC3NvdXJjZUluZGV4EhAKA3VybBgEIAEoCVIDdXJsEiAK'
    'CWltYWdlX3VybBgFIAEoCUgAUghpbWFnZVVybIgBAUIMCgpfaW1hZ2VfdXJs');

@$core.Deprecated('Use pageRequestDescriptor instead')
const PageRequest$json = {
  '1': 'PageRequest',
  '2': [
    {'1': 'page', '3': 1, '4': 1, '5': 13, '10': 'page'},
  ],
};

/// Descriptor for `PageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pageRequestDescriptor =
    $convert.base64Decode('CgtQYWdlUmVxdWVzdBISCgRwYWdlGAEgASgNUgRwYWdl');

@$core.Deprecated('Use filterTextDescriptor instead')
const FilterText$json = {
  '1': 'FilterText',
  '2': [
    {'1': 'state', '3': 1, '4': 1, '5': 9, '10': 'state'},
  ],
};

/// Descriptor for `FilterText`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterTextDescriptor =
    $convert.base64Decode('CgpGaWx0ZXJUZXh0EhQKBXN0YXRlGAEgASgJUgVzdGF0ZQ==');

@$core.Deprecated('Use filterCheckBoxDescriptor instead')
const FilterCheckBox$json = {
  '1': 'FilterCheckBox',
  '2': [
    {'1': 'state', '3': 1, '4': 1, '5': 8, '10': 'state'},
  ],
};

/// Descriptor for `FilterCheckBox`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterCheckBoxDescriptor = $convert
    .base64Decode('Cg5GaWx0ZXJDaGVja0JveBIUCgVzdGF0ZRgBIAEoCFIFc3RhdGU=');

@$core.Deprecated('Use filterTriStateDescriptor instead')
const FilterTriState$json = {
  '1': 'FilterTriState',
  '2': [
    {'1': 'state', '3': 1, '4': 1, '5': 13, '10': 'state'},
  ],
};

/// Descriptor for `FilterTriState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterTriStateDescriptor = $convert
    .base64Decode('Cg5GaWx0ZXJUcmlTdGF0ZRIUCgVzdGF0ZRgBIAEoDVIFc3RhdGU=');

@$core.Deprecated('Use filterSelectDescriptor instead')
const FilterSelect$json = {
  '1': 'FilterSelect',
  '2': [
    {'1': 'options', '3': 1, '4': 3, '5': 9, '10': 'options'},
    {'1': 'state', '3': 2, '4': 1, '5': 13, '10': 'state'},
  ],
};

/// Descriptor for `FilterSelect`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterSelectDescriptor = $convert.base64Decode(
    'CgxGaWx0ZXJTZWxlY3QSGAoHb3B0aW9ucxgBIAMoCVIHb3B0aW9ucxIUCgVzdGF0ZRgCIAEoDV'
    'IFc3RhdGU=');

@$core.Deprecated('Use filterSortSelectionDescriptor instead')
const FilterSortSelection$json = {
  '1': 'FilterSortSelection',
  '2': [
    {'1': 'index', '3': 1, '4': 1, '5': 13, '10': 'index'},
    {'1': 'ascending', '3': 2, '4': 1, '5': 8, '10': 'ascending'},
  ],
};

/// Descriptor for `FilterSortSelection`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterSortSelectionDescriptor = $convert.base64Decode(
    'ChNGaWx0ZXJTb3J0U2VsZWN0aW9uEhQKBWluZGV4GAEgASgNUgVpbmRleBIcCglhc2NlbmRpbm'
    'cYAiABKAhSCWFzY2VuZGluZw==');

@$core.Deprecated('Use filterSortStateDescriptor instead')
const FilterSortState$json = {
  '1': 'FilterSortState',
  '2': [
    {
      '1': 'selection',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.FilterSortSelection',
      '9': 0,
      '10': 'selection',
      '17': true
    },
  ],
  '8': [
    {'1': '_selection'},
  ],
};

/// Descriptor for `FilterSortState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterSortStateDescriptor = $convert.base64Decode(
    'Cg9GaWx0ZXJTb3J0U3RhdGUSQwoJc2VsZWN0aW9uGAEgASgLMiAua2FydXlvbWkudjEuRmlsdG'
    'VyU29ydFNlbGVjdGlvbkgAUglzZWxlY3Rpb26IAQFCDAoKX3NlbGVjdGlvbg==');

@$core.Deprecated('Use filterSortDescriptor instead')
const FilterSort$json = {
  '1': 'FilterSort',
  '2': [
    {'1': 'options', '3': 1, '4': 3, '5': 9, '10': 'options'},
    {
      '1': 'state',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.FilterSortState',
      '10': 'state'
    },
  ],
};

/// Descriptor for `FilterSort`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterSortDescriptor = $convert.base64Decode(
    'CgpGaWx0ZXJTb3J0EhgKB29wdGlvbnMYASADKAlSB29wdGlvbnMSMgoFc3RhdGUYAiABKAsyHC'
    '5rYXJ1eW9taS52MS5GaWx0ZXJTb3J0U3RhdGVSBXN0YXRl');

@$core.Deprecated('Use filterGroupDescriptor instead')
const FilterGroup$json = {
  '1': 'FilterGroup',
  '2': [
    {
      '1': 'nodes',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.FilterNode',
      '10': 'nodes'
    },
  ],
};

/// Descriptor for `FilterGroup`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterGroupDescriptor = $convert.base64Decode(
    'CgtGaWx0ZXJHcm91cBItCgVub2RlcxgBIAMoCzIXLmthcnV5b21pLnYxLkZpbHRlck5vZGVSBW'
    '5vZGVz');

@$core.Deprecated('Use filterNodeDescriptor instead')
const FilterNode$json = {
  '1': 'FilterNode',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'header',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Empty',
      '9': 0,
      '10': 'header'
    },
    {
      '1': 'separator',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Empty',
      '9': 0,
      '10': 'separator'
    },
    {
      '1': 'text',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.FilterText',
      '9': 0,
      '10': 'text'
    },
    {
      '1': 'check_box',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.FilterCheckBox',
      '9': 0,
      '10': 'checkBox'
    },
    {
      '1': 'tri_state',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.FilterTriState',
      '9': 0,
      '10': 'triState'
    },
    {
      '1': 'select',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.FilterSelect',
      '9': 0,
      '10': 'select'
    },
    {
      '1': 'sort',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.FilterSort',
      '9': 0,
      '10': 'sort'
    },
    {
      '1': 'group',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.FilterGroup',
      '9': 0,
      '10': 'group'
    },
  ],
  '8': [
    {'1': 'kind'},
  ],
};

/// Descriptor for `FilterNode`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterNodeDescriptor = $convert.base64Decode(
    'CgpGaWx0ZXJOb2RlEhIKBG5hbWUYASABKAlSBG5hbWUSLAoGaGVhZGVyGAIgASgLMhIua2FydX'
    'lvbWkudjEuRW1wdHlIAFIGaGVhZGVyEjIKCXNlcGFyYXRvchgDIAEoCzISLmthcnV5b21pLnYx'
    'LkVtcHR5SABSCXNlcGFyYXRvchItCgR0ZXh0GAQgASgLMhcua2FydXlvbWkudjEuRmlsdGVyVG'
    'V4dEgAUgR0ZXh0EjoKCWNoZWNrX2JveBgFIAEoCzIbLmthcnV5b21pLnYxLkZpbHRlckNoZWNr'
    'Qm94SABSCGNoZWNrQm94EjoKCXRyaV9zdGF0ZRgGIAEoCzIbLmthcnV5b21pLnYxLkZpbHRlcl'
    'RyaVN0YXRlSABSCHRyaVN0YXRlEjMKBnNlbGVjdBgHIAEoCzIZLmthcnV5b21pLnYxLkZpbHRl'
    'clNlbGVjdEgAUgZzZWxlY3QSLQoEc29ydBgIIAEoCzIXLmthcnV5b21pLnYxLkZpbHRlclNvcn'
    'RIAFIEc29ydBIwCgVncm91cBgJIAEoCzIYLmthcnV5b21pLnYxLkZpbHRlckdyb3VwSABSBWdy'
    'b3VwQgYKBGtpbmQ=');

@$core.Deprecated('Use getFiltersRequestDescriptor instead')
const GetFiltersRequest$json = {
  '1': 'GetFiltersRequest',
  '2': [
    {
      '1': 'retained_snapshot_id',
      '3': 1,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'retainedSnapshotId',
      '17': true
    },
  ],
  '8': [
    {'1': '_retained_snapshot_id'},
  ],
};

/// Descriptor for `GetFiltersRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getFiltersRequestDescriptor = $convert.base64Decode(
    'ChFHZXRGaWx0ZXJzUmVxdWVzdBI1ChRyZXRhaW5lZF9zbmFwc2hvdF9pZBgBIAEoCUgAUhJyZX'
    'RhaW5lZFNuYXBzaG90SWSIAQFCFwoVX3JldGFpbmVkX3NuYXBzaG90X2lk');

@$core.Deprecated('Use filterSnapshotDescriptor instead')
const FilterSnapshot$json = {
  '1': 'FilterSnapshot',
  '2': [
    {'1': 'snapshot_id', '3': 1, '4': 1, '5': 9, '10': 'snapshotId'},
    {
      '1': 'nodes',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.FilterNode',
      '10': 'nodes'
    },
  ],
};

/// Descriptor for `FilterSnapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterSnapshotDescriptor = $convert.base64Decode(
    'Cg5GaWx0ZXJTbmFwc2hvdBIfCgtzbmFwc2hvdF9pZBgBIAEoCVIKc25hcHNob3RJZBItCgVub2'
    'RlcxgCIAMoCzIXLmthcnV5b21pLnYxLkZpbHRlck5vZGVSBW5vZGVz');

@$core.Deprecated('Use filterUpdateDescriptor instead')
const FilterUpdate$json = {
  '1': 'FilterUpdate',
  '2': [
    {'1': 'path', '3': 1, '4': 3, '5': 13, '10': 'path'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'text'},
    {'1': 'check_box', '3': 3, '4': 1, '5': 8, '9': 0, '10': 'checkBox'},
    {'1': 'tri_state', '3': 4, '4': 1, '5': 13, '9': 0, '10': 'triState'},
    {'1': 'select', '3': 5, '4': 1, '5': 13, '9': 0, '10': 'select'},
    {
      '1': 'sort',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.FilterSortState',
      '9': 0,
      '10': 'sort'
    },
  ],
  '8': [
    {'1': 'state'},
  ],
};

/// Descriptor for `FilterUpdate`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterUpdateDescriptor = $convert.base64Decode(
    'CgxGaWx0ZXJVcGRhdGUSEgoEcGF0aBgBIAMoDVIEcGF0aBIUCgR0ZXh0GAIgASgJSABSBHRleH'
    'QSHQoJY2hlY2tfYm94GAMgASgISABSCGNoZWNrQm94Eh0KCXRyaV9zdGF0ZRgEIAEoDUgAUgh0'
    'cmlTdGF0ZRIYCgZzZWxlY3QYBSABKA1IAFIGc2VsZWN0EjIKBHNvcnQYBiABKAsyHC5rYXJ1eW'
    '9taS52MS5GaWx0ZXJTb3J0U3RhdGVIAFIEc29ydEIHCgVzdGF0ZQ==');

@$core.Deprecated('Use filterSelectionDescriptor instead')
const FilterSelection$json = {
  '1': 'FilterSelection',
  '2': [
    {'1': 'snapshot_id', '3': 1, '4': 1, '5': 9, '10': 'snapshotId'},
    {
      '1': 'updates',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.FilterUpdate',
      '10': 'updates'
    },
  ],
};

/// Descriptor for `FilterSelection`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterSelectionDescriptor = $convert.base64Decode(
    'Cg9GaWx0ZXJTZWxlY3Rpb24SHwoLc25hcHNob3RfaWQYASABKAlSCnNuYXBzaG90SWQSMwoHdX'
    'BkYXRlcxgCIAMoCzIZLmthcnV5b21pLnYxLkZpbHRlclVwZGF0ZVIHdXBkYXRlcw==');

@$core.Deprecated('Use searchRequestDescriptor instead')
const SearchRequest$json = {
  '1': 'SearchRequest',
  '2': [
    {'1': 'page', '3': 1, '4': 1, '5': 13, '10': 'page'},
    {'1': 'query', '3': 2, '4': 1, '5': 9, '10': 'query'},
    {
      '1': 'filters',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.FilterSelection',
      '10': 'filters'
    },
  ],
};

/// Descriptor for `SearchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List searchRequestDescriptor = $convert.base64Decode(
    'Cg1TZWFyY2hSZXF1ZXN0EhIKBHBhZ2UYASABKA1SBHBhZ2USFAoFcXVlcnkYAiABKAlSBXF1ZX'
    'J5EjYKB2ZpbHRlcnMYAyABKAsyHC5rYXJ1eW9taS52MS5GaWx0ZXJTZWxlY3Rpb25SB2ZpbHRl'
    'cnM=');

@$core.Deprecated('Use mangaRequestDescriptor instead')
const MangaRequest$json = {
  '1': 'MangaRequest',
  '2': [
    {
      '1': 'manga',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Manga',
      '10': 'manga'
    },
  ],
};

/// Descriptor for `MangaRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mangaRequestDescriptor = $convert.base64Decode(
    'CgxNYW5nYVJlcXVlc3QSKAoFbWFuZ2EYASABKAsyEi5rYXJ1eW9taS52MS5NYW5nYVIFbWFuZ2'
    'E=');

@$core.Deprecated('Use chapterRequestDescriptor instead')
const ChapterRequest$json = {
  '1': 'ChapterRequest',
  '2': [
    {
      '1': 'chapter',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Chapter',
      '10': 'chapter'
    },
  ],
};

/// Descriptor for `ChapterRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chapterRequestDescriptor = $convert.base64Decode(
    'Cg5DaGFwdGVyUmVxdWVzdBIuCgdjaGFwdGVyGAEgASgLMhQua2FydXlvbWkudjEuQ2hhcHRlcl'
    'IHY2hhcHRlcg==');

@$core.Deprecated('Use sourceCallDescriptor instead')
const SourceCall$json = {
  '1': 'SourceCall',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'source_id', '3': 2, '4': 1, '5': 9, '10': 'sourceId'},
    {
      '1': 'timeout_ms',
      '3': 3,
      '4': 1,
      '5': 13,
      '9': 1,
      '10': 'timeoutMs',
      '17': true
    },
    {'1': 'generation', '3': 4, '4': 1, '5': 9, '10': 'generation'},
    {
      '1': 'popular',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.PageRequest',
      '9': 0,
      '10': 'popular'
    },
    {
      '1': 'latest',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.PageRequest',
      '9': 0,
      '10': 'latest'
    },
    {
      '1': 'search',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SearchRequest',
      '9': 0,
      '10': 'search'
    },
    {
      '1': 'details',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.MangaRequest',
      '9': 0,
      '10': 'details'
    },
    {
      '1': 'chapters',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.MangaRequest',
      '9': 0,
      '10': 'chapters'
    },
    {
      '1': 'pages',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ChapterRequest',
      '9': 0,
      '10': 'pages'
    },
    {
      '1': 'get_filters',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.GetFiltersRequest',
      '9': 0,
      '10': 'getFilters'
    },
  ],
  '8': [
    {'1': 'request'},
    {'1': '_timeout_ms'},
  ],
};

/// Descriptor for `SourceCall`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sourceCallDescriptor = $convert.base64Decode(
    'CgpTb3VyY2VDYWxsEh0KCnJlcXVlc3RfaWQYASABKAlSCXJlcXVlc3RJZBIbCglzb3VyY2VfaW'
    'QYAiABKAlSCHNvdXJjZUlkEiIKCnRpbWVvdXRfbXMYAyABKA1IAVIJdGltZW91dE1ziAEBEh4K'
    'CmdlbmVyYXRpb24YBCABKAlSCmdlbmVyYXRpb24SNAoHcG9wdWxhchgKIAEoCzIYLmthcnV5b2'
    '1pLnYxLlBhZ2VSZXF1ZXN0SABSB3BvcHVsYXISMgoGbGF0ZXN0GAsgASgLMhgua2FydXlvbWku'
    'djEuUGFnZVJlcXVlc3RIAFIGbGF0ZXN0EjQKBnNlYXJjaBgMIAEoCzIaLmthcnV5b21pLnYxLl'
    'NlYXJjaFJlcXVlc3RIAFIGc2VhcmNoEjUKB2RldGFpbHMYDSABKAsyGS5rYXJ1eW9taS52MS5N'
    'YW5nYVJlcXVlc3RIAFIHZGV0YWlscxI3CghjaGFwdGVycxgOIAEoCzIZLmthcnV5b21pLnYxLk'
    '1hbmdhUmVxdWVzdEgAUghjaGFwdGVycxIzCgVwYWdlcxgPIAEoCzIbLmthcnV5b21pLnYxLkNo'
    'YXB0ZXJSZXF1ZXN0SABSBXBhZ2VzEkEKC2dldF9maWx0ZXJzGBAgASgLMh4ua2FydXlvbWkudj'
    'EuR2V0RmlsdGVyc1JlcXVlc3RIAFIKZ2V0RmlsdGVyc0IJCgdyZXF1ZXN0Qg0KC190aW1lb3V0'
    'X21z');

@$core.Deprecated('Use mangaPageDescriptor instead')
const MangaPage$json = {
  '1': 'MangaPage',
  '2': [
    {
      '1': 'mangas',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.Manga',
      '10': 'mangas'
    },
    {'1': 'has_next_page', '3': 2, '4': 1, '5': 8, '10': 'hasNextPage'},
  ],
};

/// Descriptor for `MangaPage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List mangaPageDescriptor = $convert.base64Decode(
    'CglNYW5nYVBhZ2USKgoGbWFuZ2FzGAEgAygLMhIua2FydXlvbWkudjEuTWFuZ2FSBm1hbmdhcx'
    'IiCg1oYXNfbmV4dF9wYWdlGAIgASgIUgtoYXNOZXh0UGFnZQ==');

@$core.Deprecated('Use chapterListDescriptor instead')
const ChapterList$json = {
  '1': 'ChapterList',
  '2': [
    {
      '1': 'chapters',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.Chapter',
      '10': 'chapters'
    },
  ],
};

/// Descriptor for `ChapterList`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List chapterListDescriptor = $convert.base64Decode(
    'CgtDaGFwdGVyTGlzdBIwCghjaGFwdGVycxgBIAMoCzIULmthcnV5b21pLnYxLkNoYXB0ZXJSCG'
    'NoYXB0ZXJz');

@$core.Deprecated('Use pageListDescriptor instead')
const PageList$json = {
  '1': 'PageList',
  '2': [
    {'1': 'page_session_id', '3': 1, '4': 1, '5': 9, '10': 'pageSessionId'},
    {
      '1': 'pages',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.Page',
      '10': 'pages'
    },
  ],
};

/// Descriptor for `PageList`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pageListDescriptor = $convert.base64Decode(
    'CghQYWdlTGlzdBImCg9wYWdlX3Nlc3Npb25faWQYASABKAlSDXBhZ2VTZXNzaW9uSWQSJwoFcG'
    'FnZXMYAiADKAsyES5rYXJ1eW9taS52MS5QYWdlUgVwYWdlcw==');

@$core.Deprecated('Use sourceResultDescriptor instead')
const SourceResult$json = {
  '1': 'SourceResult',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'generation', '3': 2, '4': 1, '5': 9, '10': 'generation'},
    {'1': 'build_id', '3': 3, '4': 1, '5': 9, '10': 'buildId'},
    {
      '1': 'manga_page',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.MangaPage',
      '9': 0,
      '10': 'mangaPage'
    },
    {
      '1': 'manga',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Manga',
      '9': 0,
      '10': 'manga'
    },
    {
      '1': 'chapters',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ChapterList',
      '9': 0,
      '10': 'chapters'
    },
    {
      '1': 'page_list',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.PageList',
      '9': 0,
      '10': 'pageList'
    },
    {
      '1': 'filters',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.FilterSnapshot',
      '9': 0,
      '10': 'filters'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `SourceResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sourceResultDescriptor = $convert.base64Decode(
    'CgxTb3VyY2VSZXN1bHQSHQoKcmVxdWVzdF9pZBgBIAEoCVIJcmVxdWVzdElkEh4KCmdlbmVyYX'
    'Rpb24YAiABKAlSCmdlbmVyYXRpb24SGQoIYnVpbGRfaWQYAyABKAlSB2J1aWxkSWQSNwoKbWFu'
    'Z2FfcGFnZRgKIAEoCzIWLmthcnV5b21pLnYxLk1hbmdhUGFnZUgAUgltYW5nYVBhZ2USKgoFbW'
    'FuZ2EYCyABKAsyEi5rYXJ1eW9taS52MS5NYW5nYUgAUgVtYW5nYRI2CghjaGFwdGVycxgMIAEo'
    'CzIYLmthcnV5b21pLnYxLkNoYXB0ZXJMaXN0SABSCGNoYXB0ZXJzEjQKCXBhZ2VfbGlzdBgNIA'
    'EoCzIVLmthcnV5b21pLnYxLlBhZ2VMaXN0SABSCHBhZ2VMaXN0EjcKB2ZpbHRlcnMYDiABKAsy'
    'Gy5rYXJ1eW9taS52MS5GaWx0ZXJTbmFwc2hvdEgAUgdmaWx0ZXJzQgkKB3BheWxvYWQ=');

@$core.Deprecated('Use cancelSourceRequestDescriptor instead')
const CancelSourceRequest$json = {
  '1': 'CancelSourceRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'generation', '3': 2, '4': 1, '5': 9, '10': 'generation'},
  ],
};

/// Descriptor for `CancelSourceRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cancelSourceRequestDescriptor = $convert.base64Decode(
    'ChNDYW5jZWxTb3VyY2VSZXF1ZXN0Eh0KCnJlcXVlc3RfaWQYASABKAlSCXJlcXVlc3RJZBIeCg'
    'pnZW5lcmF0aW9uGAIgASgJUgpnZW5lcmF0aW9u');

@$core.Deprecated('Use acquireImageDescriptor instead')
const AcquireImage$json = {
  '1': 'AcquireImage',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'source_id', '3': 2, '4': 1, '5': 9, '10': 'sourceId'},
    {'1': 'page_session_id', '3': 3, '4': 1, '5': 9, '10': 'pageSessionId'},
    {'1': 'page_key', '3': 4, '4': 1, '5': 9, '10': 'pageKey'},
    {'1': 'generation', '3': 5, '4': 1, '5': 9, '10': 'generation'},
    {
      '1': 'timeout_ms',
      '3': 6,
      '4': 1,
      '5': 13,
      '9': 0,
      '10': 'timeoutMs',
      '17': true
    },
  ],
  '8': [
    {'1': '_timeout_ms'},
  ],
};

/// Descriptor for `AcquireImage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List acquireImageDescriptor = $convert.base64Decode(
    'CgxBY3F1aXJlSW1hZ2USHQoKcmVxdWVzdF9pZBgBIAEoCVIJcmVxdWVzdElkEhsKCXNvdXJjZV'
    '9pZBgCIAEoCVIIc291cmNlSWQSJgoPcGFnZV9zZXNzaW9uX2lkGAMgASgJUg1wYWdlU2Vzc2lv'
    'bklkEhkKCHBhZ2Vfa2V5GAQgASgJUgdwYWdlS2V5Eh4KCmdlbmVyYXRpb24YBSABKAlSCmdlbm'
    'VyYXRpb24SIgoKdGltZW91dF9tcxgGIAEoDUgAUgl0aW1lb3V0TXOIAQFCDQoLX3RpbWVvdXRf'
    'bXM=');

@$core.Deprecated('Use cancelImageDescriptor instead')
const CancelImage$json = {
  '1': 'CancelImage',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'generation', '3': 2, '4': 1, '5': 9, '10': 'generation'},
  ],
};

/// Descriptor for `CancelImage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cancelImageDescriptor = $convert.base64Decode(
    'CgtDYW5jZWxJbWFnZRIdCgpyZXF1ZXN0X2lkGAEgASgJUglyZXF1ZXN0SWQSHgoKZ2VuZXJhdG'
    'lvbhgCIAEoCVIKZ2VuZXJhdGlvbg==');

@$core.Deprecated('Use releaseImageDescriptor instead')
const ReleaseImage$json = {
  '1': 'ReleaseImage',
  '2': [
    {'1': 'resource_id', '3': 1, '4': 1, '5': 9, '10': 'resourceId'},
    {'1': 'generation', '3': 2, '4': 1, '5': 9, '10': 'generation'},
  ],
};

/// Descriptor for `ReleaseImage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List releaseImageDescriptor = $convert.base64Decode(
    'CgxSZWxlYXNlSW1hZ2USHwoLcmVzb3VyY2VfaWQYASABKAlSCnJlc291cmNlSWQSHgoKZ2VuZX'
    'JhdGlvbhgCIAEoCVIKZ2VuZXJhdGlvbg==');

@$core.Deprecated('Use closePageSessionDescriptor instead')
const ClosePageSession$json = {
  '1': 'ClosePageSession',
  '2': [
    {'1': 'page_session_id', '3': 1, '4': 1, '5': 9, '10': 'pageSessionId'},
    {'1': 'generation', '3': 2, '4': 1, '5': 9, '10': 'generation'},
  ],
};

/// Descriptor for `ClosePageSession`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List closePageSessionDescriptor = $convert.base64Decode(
    'ChBDbG9zZVBhZ2VTZXNzaW9uEiYKD3BhZ2Vfc2Vzc2lvbl9pZBgBIAEoCVINcGFnZVNlc3Npb2'
    '5JZBIeCgpnZW5lcmF0aW9uGAIgASgJUgpnZW5lcmF0aW9u');

@$core.Deprecated('Use releasedDescriptor instead')
const Released$json = {
  '1': 'Released',
  '2': [
    {'1': 'released', '3': 1, '4': 1, '5': 8, '10': 'released'},
  ],
};

/// Descriptor for `Released`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List releasedDescriptor = $convert
    .base64Decode('CghSZWxlYXNlZBIaCghyZWxlYXNlZBgBIAEoCFIIcmVsZWFzZWQ=');

@$core.Deprecated('Use closedDescriptor instead')
const Closed$json = {
  '1': 'Closed',
  '2': [
    {'1': 'closed', '3': 1, '4': 1, '5': 8, '10': 'closed'},
  ],
};

/// Descriptor for `Closed`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List closedDescriptor =
    $convert.base64Decode('CgZDbG9zZWQSFgoGY2xvc2VkGAEgASgIUgZjbG9zZWQ=');

@$core.Deprecated('Use completedDescriptor instead')
const Completed$json = {
  '1': 'Completed',
  '2': [
    {'1': 'completed', '3': 1, '4': 1, '5': 8, '10': 'completed'},
  ],
};

/// Descriptor for `Completed`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List completedDescriptor = $convert
    .base64Decode('CglDb21wbGV0ZWQSHAoJY29tcGxldGVkGAEgASgIUgljb21wbGV0ZWQ=');

@$core.Deprecated('Use processedImageDescriptor instead')
const ProcessedImage$json = {
  '1': 'ProcessedImage',
  '2': [
    {'1': 'resource_id', '3': 1, '4': 1, '5': 9, '10': 'resourceId'},
    {'1': 'generation', '3': 2, '4': 1, '5': 9, '10': 'generation'},
    {'1': 'byte_length', '3': 3, '4': 1, '5': 13, '10': 'byteLength'},
  ],
};

/// Descriptor for `ProcessedImage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List processedImageDescriptor = $convert.base64Decode(
    'Cg5Qcm9jZXNzZWRJbWFnZRIfCgtyZXNvdXJjZV9pZBgBIAEoCVIKcmVzb3VyY2VJZBIeCgpnZW'
    '5lcmF0aW9uGAIgASgJUgpnZW5lcmF0aW9uEh8KC2J5dGVfbGVuZ3RoGAMgASgNUgpieXRlTGVu'
    'Z3Ro');

@$core.Deprecated('Use imageResourceDescriptor instead')
const ImageResource$json = {
  '1': 'ImageResource',
  '2': [
    {'1': 'resource_id', '3': 1, '4': 1, '5': 9, '10': 'resourceId'},
    {'1': 'generation', '3': 2, '4': 1, '5': 9, '10': 'generation'},
    {'1': 'byte_length', '3': 3, '4': 1, '5': 13, '10': 'byteLength'},
    {'1': 'url', '3': 4, '4': 1, '5': 9, '10': 'url'},
  ],
};

/// Descriptor for `ImageResource`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageResourceDescriptor = $convert.base64Decode(
    'Cg1JbWFnZVJlc291cmNlEh8KC3Jlc291cmNlX2lkGAEgASgJUgpyZXNvdXJjZUlkEh4KCmdlbm'
    'VyYXRpb24YAiABKAlSCmdlbmVyYXRpb24SHwoLYnl0ZV9sZW5ndGgYAyABKA1SCmJ5dGVMZW5n'
    'dGgSEAoDdXJsGAQgASgJUgN1cmw=');

@$core.Deprecated('Use imageMetaDescriptor instead')
const ImageMeta$json = {
  '1': 'ImageMeta',
};

/// Descriptor for `ImageMeta`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageMetaDescriptor =
    $convert.base64Decode('CglJbWFnZU1ldGE=');

@$core.Deprecated('Use imageDataDescriptor instead')
const ImageData$json = {
  '1': 'ImageData',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 13, '10': 'seq'},
    {'1': 'byte_length', '3': 2, '4': 1, '5': 13, '10': 'byteLength'},
  ],
};

/// Descriptor for `ImageData`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageDataDescriptor = $convert.base64Decode(
    'CglJbWFnZURhdGESEAoDc2VxGAEgASgNUgNzZXESHwoLYnl0ZV9sZW5ndGgYAiABKA1SCmJ5dG'
    'VMZW5ndGg=');

@$core.Deprecated('Use imageEndDescriptor instead')
const ImageEnd$json = {
  '1': 'ImageEnd',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 13, '10': 'seq'},
    {'1': 'total_bytes', '3': 2, '4': 1, '5': 13, '10': 'totalBytes'},
  ],
};

/// Descriptor for `ImageEnd`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageEndDescriptor = $convert.base64Decode(
    'CghJbWFnZUVuZBIQCgNzZXEYASABKA1SA3NlcRIfCgt0b3RhbF9ieXRlcxgCIAEoDVIKdG90YW'
    'xCeXRlcw==');

@$core.Deprecated('Use imageAckDescriptor instead')
const ImageAck$json = {
  '1': 'ImageAck',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 13, '10': 'seq'},
    {
      '1': 'resource',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ProcessedImage',
      '9': 0,
      '10': 'resource',
      '17': true
    },
  ],
  '8': [
    {'1': '_resource'},
  ],
};

/// Descriptor for `ImageAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageAckDescriptor = $convert.base64Decode(
    'CghJbWFnZUFjaxIQCgNzZXEYASABKA1SA3NlcRI8CghyZXNvdXJjZRgCIAEoCzIbLmthcnV5b2'
    '1pLnYxLlByb2Nlc3NlZEltYWdlSABSCHJlc291cmNliAEBQgsKCV9yZXNvdXJjZQ==');

@$core.Deprecated('Use imageFrameControlDescriptor instead')
const ImageFrameControl$json = {
  '1': 'ImageFrameControl',
  '2': [
    {
      '1': 'meta',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ImageMeta',
      '9': 0,
      '10': 'meta'
    },
    {
      '1': 'data',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ImageData',
      '9': 0,
      '10': 'data'
    },
    {
      '1': 'end',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ImageEnd',
      '9': 0,
      '10': 'end'
    },
    {
      '1': 'ack',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ImageAck',
      '9': 0,
      '10': 'ack'
    },
    {
      '1': 'abort',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.RuntimeError',
      '9': 0,
      '10': 'abort'
    },
  ],
  '8': [
    {'1': 'frame'},
  ],
};

/// Descriptor for `ImageFrameControl`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageFrameControlDescriptor = $convert.base64Decode(
    'ChFJbWFnZUZyYW1lQ29udHJvbBIsCgRtZXRhGAEgASgLMhYua2FydXlvbWkudjEuSW1hZ2VNZX'
    'RhSABSBG1ldGESLAoEZGF0YRgCIAEoCzIWLmthcnV5b21pLnYxLkltYWdlRGF0YUgAUgRkYXRh'
    'EikKA2VuZBgDIAEoCzIVLmthcnV5b21pLnYxLkltYWdlRW5kSABSA2VuZBIpCgNhY2sYBCABKA'
    'syFS5rYXJ1eW9taS52MS5JbWFnZUFja0gAUgNhY2sSMQoFYWJvcnQYBSABKAsyGS5rYXJ1eW9t'
    'aS52MS5SdW50aW1lRXJyb3JIAFIFYWJvcnRCBwoFZnJhbWU=');

@$core.Deprecated('Use artifactDescriptor instead')
const Artifact$json = {
  '1': 'Artifact',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
    {'1': 'sha256', '3': 2, '4': 1, '5': 9, '10': 'sha256'},
    {'1': 'size', '3': 3, '4': 1, '5': 13, '10': 'size'},
    {
      '1': 'content_type',
      '3': 4,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'contentType',
      '17': true
    },
    {
      '1': 'logical_name',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'logicalName',
      '17': true
    },
  ],
  '8': [
    {'1': '_content_type'},
    {'1': '_logical_name'},
  ],
};

/// Descriptor for `Artifact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List artifactDescriptor = $convert.base64Decode(
    'CghBcnRpZmFjdBISCgRwYXRoGAEgASgJUgRwYXRoEhYKBnNoYTI1NhgCIAEoCVIGc2hhMjU2Eh'
    'IKBHNpemUYAyABKA1SBHNpemUSJgoMY29udGVudF90eXBlGAQgASgJSABSC2NvbnRlbnRUeXBl'
    'iAEBEiYKDGxvZ2ljYWxfbmFtZRgFIAEoCUgBUgtsb2dpY2FsTmFtZYgBAUIPCg1fY29udGVudF'
    '90eXBlQg8KDV9sb2dpY2FsX25hbWU=');

@$core.Deprecated('Use bundleArtifactDescriptor instead')
const BundleArtifact$json = {
  '1': 'BundleArtifact',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
    {'1': 'sha256', '3': 2, '4': 1, '5': 9, '10': 'sha256'},
    {'1': 'size', '3': 3, '4': 1, '5': 13, '10': 'size'},
    {'1': 'content_type', '3': 4, '4': 1, '5': 9, '10': 'contentType'},
    {'1': 'encoding', '3': 5, '4': 1, '5': 9, '10': 'encoding'},
    {'1': 'encoded_sha256', '3': 6, '4': 1, '5': 9, '10': 'encodedSha256'},
    {'1': 'encoded_size', '3': 7, '4': 1, '5': 13, '10': 'encodedSize'},
  ],
};

/// Descriptor for `BundleArtifact`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bundleArtifactDescriptor = $convert.base64Decode(
    'Cg5CdW5kbGVBcnRpZmFjdBISCgRwYXRoGAEgASgJUgRwYXRoEhYKBnNoYTI1NhgCIAEoCVIGc2'
    'hhMjU2EhIKBHNpemUYAyABKA1SBHNpemUSIQoMY29udGVudF90eXBlGAQgASgJUgtjb250ZW50'
    'VHlwZRIaCghlbmNvZGluZxgFIAEoCVIIZW5jb2RpbmcSJQoOZW5jb2RlZF9zaGEyNTYYBiABKA'
    'lSDWVuY29kZWRTaGEyNTYSIQoMZW5jb2RlZF9zaXplGAcgASgNUgtlbmNvZGVkU2l6ZQ==');

@$core.Deprecated('Use buildManifestDescriptor instead')
const BuildManifest$json = {
  '1': 'BuildManifest',
  '2': [
    {'1': 'protocol_version', '3': 1, '4': 1, '5': 13, '10': 'protocolVersion'},
    {'1': 'host_abi', '3': 2, '4': 1, '5': 9, '10': 'hostAbi'},
    {'1': 'runtime_baseline', '3': 3, '4': 1, '5': 9, '10': 'runtimeBaseline'},
    {'1': 'bridge_version', '3': 4, '4': 1, '5': 13, '10': 'bridgeVersion'},
    {'1': 'build_id', '3': 5, '4': 1, '5': 9, '10': 'buildId'},
    {'1': 'package_name', '3': 6, '4': 1, '5': 9, '10': 'packageName'},
    {'1': 'repo_id', '3': 7, '4': 1, '5': 9, '10': 'repoId'},
    {'1': 'version', '3': 8, '4': 1, '5': 9, '10': 'version'},
    {'1': 'storage_schema', '3': 9, '4': 1, '5': 9, '10': 'storageSchema'},
    {'1': 'source_ids', '3': 10, '4': 3, '5': 9, '10': 'sourceIds'},
    {
      '1': 'bundle',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BundleArtifact',
      '10': 'bundle'
    },
    {
      '1': 'host_scripts',
      '3': 12,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.Artifact',
      '10': 'hostScripts'
    },
    {
      '1': 'resources',
      '3': 13,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.Artifact',
      '10': 'resources'
    },
  ],
};

/// Descriptor for `BuildManifest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List buildManifestDescriptor = $convert.base64Decode(
    'Cg1CdWlsZE1hbmlmZXN0EikKEHByb3RvY29sX3ZlcnNpb24YASABKA1SD3Byb3RvY29sVmVyc2'
    'lvbhIZCghob3N0X2FiaRgCIAEoCVIHaG9zdEFiaRIpChBydW50aW1lX2Jhc2VsaW5lGAMgASgJ'
    'Ug9ydW50aW1lQmFzZWxpbmUSJQoOYnJpZGdlX3ZlcnNpb24YBCABKA1SDWJyaWRnZVZlcnNpb2'
    '4SGQoIYnVpbGRfaWQYBSABKAlSB2J1aWxkSWQSIQoMcGFja2FnZV9uYW1lGAYgASgJUgtwYWNr'
    'YWdlTmFtZRIXCgdyZXBvX2lkGAcgASgJUgZyZXBvSWQSGAoHdmVyc2lvbhgIIAEoCVIHdmVyc2'
    'lvbhIlCg5zdG9yYWdlX3NjaGVtYRgJIAEoCVINc3RvcmFnZVNjaGVtYRIdCgpzb3VyY2VfaWRz'
    'GAogAygJUglzb3VyY2VJZHMSMwoGYnVuZGxlGAsgASgLMhsua2FydXlvbWkudjEuQnVuZGxlQX'
    'J0aWZhY3RSBmJ1bmRsZRI4Cgxob3N0X3NjcmlwdHMYDCADKAsyFS5rYXJ1eW9taS52MS5BcnRp'
    'ZmFjdFILaG9zdFNjcmlwdHMSMwoJcmVzb3VyY2VzGA0gAygLMhUua2FydXlvbWkudjEuQXJ0aW'
    'ZhY3RSCXJlc291cmNlcw==');

@$core.Deprecated('Use extensionBuildDescriptorDescriptor instead')
const ExtensionBuildDescriptor$json = {
  '1': 'ExtensionBuildDescriptor',
  '2': [
    {'1': 'build_id', '3': 1, '4': 1, '5': 9, '10': 'buildId'},
    {'1': 'package_name', '3': 2, '4': 1, '5': 9, '10': 'packageName'},
    {'1': 'repo_id', '3': 3, '4': 1, '5': 9, '10': 'repoId'},
    {'1': 'version', '3': 4, '4': 1, '5': 9, '10': 'version'},
    {'1': 'source_ids', '3': 5, '4': 3, '5': 9, '10': 'sourceIds'},
    {'1': 'manifest_path', '3': 6, '4': 1, '5': 9, '10': 'manifestPath'},
  ],
};

/// Descriptor for `ExtensionBuildDescriptor`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List extensionBuildDescriptorDescriptor = $convert.base64Decode(
    'ChhFeHRlbnNpb25CdWlsZERlc2NyaXB0b3ISGQoIYnVpbGRfaWQYASABKAlSB2J1aWxkSWQSIQ'
    'oMcGFja2FnZV9uYW1lGAIgASgJUgtwYWNrYWdlTmFtZRIXCgdyZXBvX2lkGAMgASgJUgZyZXBv'
    'SWQSGAoHdmVyc2lvbhgEIAEoCVIHdmVyc2lvbhIdCgpzb3VyY2VfaWRzGAUgAygJUglzb3VyY2'
    'VJZHMSIwoNbWFuaWZlc3RfcGF0aBgGIAEoCVIMbWFuaWZlc3RQYXRo');

@$core.Deprecated('Use extensionIndexDescriptor instead')
const ExtensionIndex$json = {
  '1': 'ExtensionIndex',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {
      '1': 'builds',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.ExtensionBuildDescriptor',
      '10': 'builds'
    },
  ],
};

/// Descriptor for `ExtensionIndex`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List extensionIndexDescriptor = $convert.base64Decode(
    'Cg5FeHRlbnNpb25JbmRleBIlCg5zY2hlbWFfdmVyc2lvbhgBIAEoDVINc2NoZW1hVmVyc2lvbh'
    'I9CgZidWlsZHMYAiADKAsyJS5rYXJ1eW9taS52MS5FeHRlbnNpb25CdWlsZERlc2NyaXB0b3JS'
    'BmJ1aWxkcw==');

@$core.Deprecated('Use identityDescriptor instead')
const Identity$json = {
  '1': 'Identity',
  '2': [
    {'1': 'subject', '3': 1, '4': 1, '5': 9, '10': 'subject'},
    {'1': 'email', '3': 2, '4': 1, '5': 9, '10': 'email'},
  ],
};

/// Descriptor for `Identity`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List identityDescriptor = $convert.base64Decode(
    'CghJZGVudGl0eRIYCgdzdWJqZWN0GAEgASgJUgdzdWJqZWN0EhQKBWVtYWlsGAIgASgJUgVlbW'
    'FpbA==');

@$core.Deprecated('Use bootstrapDescriptor instead')
const Bootstrap$json = {
  '1': 'Bootstrap',
  '2': [
    {'1': 'protocol_version', '3': 1, '4': 1, '5': 13, '10': 'protocolVersion'},
    {
      '1': 'identity',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Identity',
      '10': 'identity'
    },
    {'1': 'expires_at', '3': 3, '4': 1, '5': 1, '10': 'expiresAt'},
    {
      '1': 'stage',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.karuyomi.v1.BootstrapStage',
      '10': 'stage'
    },
  ],
};

/// Descriptor for `Bootstrap`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bootstrapDescriptor = $convert.base64Decode(
    'CglCb290c3RyYXASKQoQcHJvdG9jb2xfdmVyc2lvbhgBIAEoDVIPcHJvdG9jb2xWZXJzaW9uEj'
    'EKCGlkZW50aXR5GAIgASgLMhUua2FydXlvbWkudjEuSWRlbnRpdHlSCGlkZW50aXR5Eh0KCmV4'
    'cGlyZXNfYXQYAyABKAFSCWV4cGlyZXNBdBIxCgVzdGFnZRgEIAEoDjIbLmthcnV5b21pLnYxLk'
    'Jvb3RzdHJhcFN0YWdlUgVzdGFnZQ==');

@$core.Deprecated('Use apiFetchRequestDescriptor instead')
const ApiFetchRequest$json = {
  '1': 'ApiFetchRequest',
  '2': [
    {'1': 'path', '3': 1, '4': 1, '5': 9, '10': 'path'},
    {'1': 'method', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'method', '17': true},
    {
      '1': 'headers',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.ApiFetchRequest.HeadersEntry',
      '10': 'headers'
    },
    {'1': 'body', '3': 4, '4': 1, '5': 9, '9': 1, '10': 'body', '17': true},
  ],
  '3': [ApiFetchRequest_HeadersEntry$json],
  '8': [
    {'1': '_method'},
    {'1': '_body'},
  ],
};

@$core.Deprecated('Use apiFetchRequestDescriptor instead')
const ApiFetchRequest_HeadersEntry$json = {
  '1': 'HeadersEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ApiFetchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List apiFetchRequestDescriptor = $convert.base64Decode(
    'Cg9BcGlGZXRjaFJlcXVlc3QSEgoEcGF0aBgBIAEoCVIEcGF0aBIbCgZtZXRob2QYAiABKAlIAF'
    'IGbWV0aG9kiAEBEkMKB2hlYWRlcnMYAyADKAsyKS5rYXJ1eW9taS52MS5BcGlGZXRjaFJlcXVl'
    'c3QuSGVhZGVyc0VudHJ5UgdoZWFkZXJzEhcKBGJvZHkYBCABKAlIAVIEYm9keYgBARo6CgxIZW'
    'FkZXJzRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFsdWUYAiABKAlSBXZhbHVlOgI4AUIJ'
    'CgdfbWV0aG9kQgcKBV9ib2R5');

@$core.Deprecated('Use apiFetchResponseDescriptor instead')
const ApiFetchResponse$json = {
  '1': 'ApiFetchResponse',
  '2': [
    {'1': 'status', '3': 1, '4': 1, '5': 13, '10': 'status'},
    {
      '1': 'headers',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.karuyomi.v1.ApiFetchResponse.HeadersEntry',
      '10': 'headers'
    },
    {'1': 'body', '3': 3, '4': 1, '5': 9, '10': 'body'},
    {'1': 'redirected', '3': 4, '4': 1, '5': 8, '10': 'redirected'},
  ],
  '3': [ApiFetchResponse_HeadersEntry$json],
};

@$core.Deprecated('Use apiFetchResponseDescriptor instead')
const ApiFetchResponse_HeadersEntry$json = {
  '1': 'HeadersEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ApiFetchResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List apiFetchResponseDescriptor = $convert.base64Decode(
    'ChBBcGlGZXRjaFJlc3BvbnNlEhYKBnN0YXR1cxgBIAEoDVIGc3RhdHVzEkQKB2hlYWRlcnMYAi'
    'ADKAsyKi5rYXJ1eW9taS52MS5BcGlGZXRjaFJlc3BvbnNlLkhlYWRlcnNFbnRyeVIHaGVhZGVy'
    'cxISCgRib2R5GAMgASgJUgRib2R5Eh4KCnJlZGlyZWN0ZWQYBCABKAhSCnJlZGlyZWN0ZWQaOg'
    'oMSGVhZGVyc0VudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbHVlGAIgASgJUgV2YWx1ZToC'
    'OAE=');

@$core.Deprecated('Use controlRequestDescriptor instead')
const ControlRequest$json = {
  '1': 'ControlRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {
      '1': 'ready',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Empty',
      '9': 0,
      '10': 'ready'
    },
    {
      '1': 'open',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.OpenRequest',
      '9': 0,
      '10': 'open'
    },
    {
      '1': 'invoke',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SourceCall',
      '9': 0,
      '10': 'invoke'
    },
    {
      '1': 'cancel',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.CancelSourceRequest',
      '9': 0,
      '10': 'cancel'
    },
    {
      '1': 'acquire_image',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.AcquireImage',
      '9': 0,
      '10': 'acquireImage'
    },
    {
      '1': 'cancel_image',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.CancelImage',
      '9': 0,
      '10': 'cancelImage'
    },
    {
      '1': 'release_image',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ReleaseImage',
      '9': 0,
      '10': 'releaseImage'
    },
    {
      '1': 'close_page_session',
      '3': 17,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ClosePageSession',
      '9': 0,
      '10': 'closePageSession'
    },
    {
      '1': 'rebuild',
      '3': 18,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Empty',
      '9': 0,
      '10': 'rebuild'
    },
    {
      '1': 'fetch_api',
      '3': 19,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ApiFetchRequest',
      '9': 0,
      '10': 'fetchApi'
    },
    {
      '1': 'dispose',
      '3': 20,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Empty',
      '9': 0,
      '10': 'dispose'
    },
  ],
  '8': [
    {'1': 'command'},
  ],
};

/// Descriptor for `ControlRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlRequestDescriptor = $convert.base64Decode(
    'Cg5Db250cm9sUmVxdWVzdBIdCgpyZXF1ZXN0X2lkGAEgASgJUglyZXF1ZXN0SWQSKgoFcmVhZH'
    'kYCiABKAsyEi5rYXJ1eW9taS52MS5FbXB0eUgAUgVyZWFkeRIuCgRvcGVuGAsgASgLMhgua2Fy'
    'dXlvbWkudjEuT3BlblJlcXVlc3RIAFIEb3BlbhIxCgZpbnZva2UYDCABKAsyFy5rYXJ1eW9taS'
    '52MS5Tb3VyY2VDYWxsSABSBmludm9rZRI6CgZjYW5jZWwYDSABKAsyIC5rYXJ1eW9taS52MS5D'
    'YW5jZWxTb3VyY2VSZXF1ZXN0SABSBmNhbmNlbBJACg1hY3F1aXJlX2ltYWdlGA4gASgLMhkua2'
    'FydXlvbWkudjEuQWNxdWlyZUltYWdlSABSDGFjcXVpcmVJbWFnZRI9CgxjYW5jZWxfaW1hZ2UY'
    'DyABKAsyGC5rYXJ1eW9taS52MS5DYW5jZWxJbWFnZUgAUgtjYW5jZWxJbWFnZRJACg1yZWxlYX'
    'NlX2ltYWdlGBAgASgLMhkua2FydXlvbWkudjEuUmVsZWFzZUltYWdlSABSDHJlbGVhc2VJbWFn'
    'ZRJNChJjbG9zZV9wYWdlX3Nlc3Npb24YESABKAsyHS5rYXJ1eW9taS52MS5DbG9zZVBhZ2VTZX'
    'NzaW9uSABSEGNsb3NlUGFnZVNlc3Npb24SLgoHcmVidWlsZBgSIAEoCzISLmthcnV5b21pLnYx'
    'LkVtcHR5SABSB3JlYnVpbGQSOwoJZmV0Y2hfYXBpGBMgASgLMhwua2FydXlvbWkudjEuQXBpRm'
    'V0Y2hSZXF1ZXN0SABSCGZldGNoQXBpEi4KB2Rpc3Bvc2UYFCABKAsyEi5rYXJ1eW9taS52MS5F'
    'bXB0eUgAUgdkaXNwb3NlQgkKB2NvbW1hbmQ=');

@$core.Deprecated('Use controlResponseDescriptor instead')
const ControlResponse$json = {
  '1': 'ControlResponse',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {
      '1': 'hello',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.RuntimeHello',
      '9': 0,
      '10': 'hello'
    },
    {
      '1': 'session',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.RuntimeSession',
      '9': 0,
      '10': 'session'
    },
    {
      '1': 'source',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SourceResult',
      '9': 0,
      '10': 'source'
    },
    {
      '1': 'image',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ImageResource',
      '9': 0,
      '10': 'image'
    },
    {
      '1': 'released',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Released',
      '9': 0,
      '10': 'released'
    },
    {
      '1': 'closed',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Closed',
      '9': 0,
      '10': 'closed'
    },
    {
      '1': 'completed',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Completed',
      '9': 0,
      '10': 'completed'
    },
    {
      '1': 'api',
      '3': 17,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ApiFetchResponse',
      '9': 0,
      '10': 'api'
    },
    {
      '1': 'error',
      '3': 18,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.RuntimeError',
      '9': 0,
      '10': 'error'
    },
  ],
  '8': [
    {'1': 'result'},
  ],
};

/// Descriptor for `ControlResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List controlResponseDescriptor = $convert.base64Decode(
    'Cg9Db250cm9sUmVzcG9uc2USHQoKcmVxdWVzdF9pZBgBIAEoCVIJcmVxdWVzdElkEjEKBWhlbG'
    'xvGAogASgLMhkua2FydXlvbWkudjEuUnVudGltZUhlbGxvSABSBWhlbGxvEjcKB3Nlc3Npb24Y'
    'CyABKAsyGy5rYXJ1eW9taS52MS5SdW50aW1lU2Vzc2lvbkgAUgdzZXNzaW9uEjMKBnNvdXJjZR'
    'gMIAEoCzIZLmthcnV5b21pLnYxLlNvdXJjZVJlc3VsdEgAUgZzb3VyY2USMgoFaW1hZ2UYDSAB'
    'KAsyGi5rYXJ1eW9taS52MS5JbWFnZVJlc291cmNlSABSBWltYWdlEjMKCHJlbGVhc2VkGA4gAS'
    'gLMhUua2FydXlvbWkudjEuUmVsZWFzZWRIAFIIcmVsZWFzZWQSLQoGY2xvc2VkGA8gASgLMhMu'
    'a2FydXlvbWkudjEuQ2xvc2VkSABSBmNsb3NlZBI2Cgljb21wbGV0ZWQYECABKAsyFi5rYXJ1eW'
    '9taS52MS5Db21wbGV0ZWRIAFIJY29tcGxldGVkEjEKA2FwaRgRIAEoCzIdLmthcnV5b21pLnYx'
    'LkFwaUZldGNoUmVzcG9uc2VIAFIDYXBpEjEKBWVycm9yGBIgASgLMhkua2FydXlvbWkudjEuUn'
    'VudGltZUVycm9ySABSBWVycm9yQggKBnJlc3VsdA==');

@$core.Deprecated('Use openWorkerDescriptor instead')
const OpenWorker$json = {
  '1': 'OpenWorker',
  '2': [
    {
      '1': 'manifest',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.BuildManifest',
      '10': 'manifest'
    },
    {'1': 'user_agent', '3': 2, '4': 1, '5': 9, '10': 'userAgent'},
  ],
};

/// Descriptor for `OpenWorker`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List openWorkerDescriptor = $convert.base64Decode(
    'CgpPcGVuV29ya2VyEjYKCG1hbmlmZXN0GAEgASgLMhoua2FydXlvbWkudjEuQnVpbGRNYW5pZm'
    'VzdFIIbWFuaWZlc3QSHQoKdXNlcl9hZ2VudBgCIAEoCVIJdXNlckFnZW50');

@$core.Deprecated('Use acquireImageWorkerDescriptor instead')
const AcquireImageWorker$json = {
  '1': 'AcquireImageWorker',
  '2': [
    {
      '1': 'request',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.AcquireImage',
      '10': 'request'
    },
    {'1': 'resource_id', '3': 2, '4': 1, '5': 9, '10': 'resourceId'},
  ],
};

/// Descriptor for `AcquireImageWorker`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List acquireImageWorkerDescriptor = $convert.base64Decode(
    'ChJBY3F1aXJlSW1hZ2VXb3JrZXISMwoHcmVxdWVzdBgBIAEoCzIZLmthcnV5b21pLnYxLkFjcX'
    'VpcmVJbWFnZVIHcmVxdWVzdBIfCgtyZXNvdXJjZV9pZBgCIAEoCVIKcmVzb3VyY2VJZA==');

@$core.Deprecated('Use workerCommandDescriptor instead')
const WorkerCommand$json = {
  '1': 'WorkerCommand',
  '2': [
    {
      '1': 'envelope',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.RpcEnvelope',
      '10': 'envelope'
    },
    {
      '1': 'open',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.OpenWorker',
      '9': 0,
      '10': 'open'
    },
    {
      '1': 'invoke',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SourceCall',
      '9': 0,
      '10': 'invoke'
    },
    {
      '1': 'acquire_image',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.AcquireImageWorker',
      '9': 0,
      '10': 'acquireImage'
    },
    {
      '1': 'close_page_session',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ClosePageSession',
      '9': 0,
      '10': 'closePageSession'
    },
    {
      '1': 'shutdown',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Empty',
      '9': 0,
      '10': 'shutdown'
    },
  ],
  '8': [
    {'1': 'command'},
  ],
};

/// Descriptor for `WorkerCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List workerCommandDescriptor = $convert.base64Decode(
    'Cg1Xb3JrZXJDb21tYW5kEjQKCGVudmVsb3BlGAEgASgLMhgua2FydXlvbWkudjEuUnBjRW52ZW'
    'xvcGVSCGVudmVsb3BlEi0KBG9wZW4YCiABKAsyFy5rYXJ1eW9taS52MS5PcGVuV29ya2VySABS'
    'BG9wZW4SMQoGaW52b2tlGAsgASgLMhcua2FydXlvbWkudjEuU291cmNlQ2FsbEgAUgZpbnZva2'
    'USRgoNYWNxdWlyZV9pbWFnZRgMIAEoCzIfLmthcnV5b21pLnYxLkFjcXVpcmVJbWFnZVdvcmtl'
    'ckgAUgxhY3F1aXJlSW1hZ2USTQoSY2xvc2VfcGFnZV9zZXNzaW9uGA0gASgLMh0ua2FydXlvbW'
    'kudjEuQ2xvc2VQYWdlU2Vzc2lvbkgAUhBjbG9zZVBhZ2VTZXNzaW9uEjAKCHNodXRkb3duGA4g'
    'ASgLMhIua2FydXlvbWkudjEuRW1wdHlIAFIIc2h1dGRvd25CCQoHY29tbWFuZA==');

@$core.Deprecated('Use workerResponseDescriptor instead')
const WorkerResponse$json = {
  '1': 'WorkerResponse',
  '2': [
    {
      '1': 'envelope',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.RpcEnvelope',
      '10': 'envelope'
    },
    {
      '1': 'session',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.RuntimeSession',
      '9': 0,
      '10': 'session'
    },
    {
      '1': 'source',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.SourceResult',
      '9': 0,
      '10': 'source'
    },
    {
      '1': 'image',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.ProcessedImage',
      '9': 0,
      '10': 'image'
    },
    {
      '1': 'closed',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.Closed',
      '9': 0,
      '10': 'closed'
    },
    {
      '1': 'error',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.karuyomi.v1.RuntimeError',
      '9': 0,
      '10': 'error'
    },
  ],
  '8': [
    {'1': 'result'},
  ],
};

/// Descriptor for `WorkerResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List workerResponseDescriptor = $convert.base64Decode(
    'Cg5Xb3JrZXJSZXNwb25zZRI0CghlbnZlbG9wZRgBIAEoCzIYLmthcnV5b21pLnYxLlJwY0Vudm'
    'Vsb3BlUghlbnZlbG9wZRI3CgdzZXNzaW9uGAogASgLMhsua2FydXlvbWkudjEuUnVudGltZVNl'
    'c3Npb25IAFIHc2Vzc2lvbhIzCgZzb3VyY2UYCyABKAsyGS5rYXJ1eW9taS52MS5Tb3VyY2VSZX'
    'N1bHRIAFIGc291cmNlEjMKBWltYWdlGAwgASgLMhsua2FydXlvbWkudjEuUHJvY2Vzc2VkSW1h'
    'Z2VIAFIFaW1hZ2USLQoGY2xvc2VkGA0gASgLMhMua2FydXlvbWkudjEuQ2xvc2VkSABSBmNsb3'
    'NlZBIxCgVlcnJvchgOIAEoCzIZLmthcnV5b21pLnYxLlJ1bnRpbWVFcnJvckgAUgVlcnJvckII'
    'CgZyZXN1bHQ=');
