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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'control.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'control.pbenum.dart';

class Empty extends $pb.GeneratedMessage {
  factory Empty() => Empty._();

  Empty._();

  factory Empty.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Empty()..mergeFromBuffer(data, registry);
  factory Empty.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Empty()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Empty',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: Empty.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Empty clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Empty copyWith(void Function(Empty) updates) =>
      super.copyWith((message) => updates(message as Empty)) as Empty;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Empty() / Empty.new instead')
  static Empty create() => Empty._();
  static $pb.GeneratedMessage $_createMessage() => Empty._();
  @$core.override
  Empty createEmptyInstance() => Empty._();
  @$core.pragma('dart2js:noInline')
  static Empty getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Empty>(Empty.$_createMessage);
  static Empty? _defaultInstance;
}

/// Public static delivery identity, separate from the application/API origin.
class CatalogReference extends $pb.GeneratedMessage {
  factory CatalogReference({
    $core.String? catalogUrl,
    $core.String? repoId,
  }) {
    final result = CatalogReference._();
    if (catalogUrl != null) result.catalogUrl = catalogUrl;
    if (repoId != null) result.repoId = repoId;
    return result;
  }

  CatalogReference._();

  factory CatalogReference.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CatalogReference()..mergeFromBuffer(data, registry);
  factory CatalogReference.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CatalogReference()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CatalogReference',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CatalogReference.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'catalogUrl')
    ..aOS(2, _omitFieldNames ? '' : 'repoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CatalogReference clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CatalogReference copyWith(void Function(CatalogReference) updates) =>
      super.copyWith((message) => updates(message as CatalogReference))
          as CatalogReference;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CatalogReference() / CatalogReference.new instead')
  static CatalogReference create() => CatalogReference._();
  static $pb.GeneratedMessage $_createMessage() => CatalogReference._();
  @$core.override
  CatalogReference createEmptyInstance() => CatalogReference._();
  @$core.pragma('dart2js:noInline')
  static CatalogReference getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CatalogReference>(
          CatalogReference.$_createMessage);
  static CatalogReference? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get catalogUrl => $_getSZ(0);
  @$pb.TagNumber(1)
  set catalogUrl($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCatalogUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearCatalogUrl() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get repoId => $_getSZ(1);
  @$pb.TagNumber(2)
  set repoId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRepoId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRepoId() => $_clearField(2);
}

class RuntimeError extends $pb.GeneratedMessage {
  factory RuntimeError({
    RuntimeErrorCode? code,
    $core.String? message,
    $core.bool? retryable,
    $core.String? javaClass,
  }) {
    final result = RuntimeError._();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    if (retryable != null) result.retryable = retryable;
    if (javaClass != null) result.javaClass = javaClass;
    return result;
  }

  RuntimeError._();

  factory RuntimeError.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RuntimeError()..mergeFromBuffer(data, registry);
  factory RuntimeError.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RuntimeError()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RuntimeError',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: RuntimeError.$_createMessage)
    ..aE<RuntimeErrorCode>(1, _omitFieldNames ? '' : 'code',
        enumValues: RuntimeErrorCode.values)
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..aOB(3, _omitFieldNames ? '' : 'retryable')
    ..aOS(4, _omitFieldNames ? '' : 'javaClass')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RuntimeError clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RuntimeError copyWith(void Function(RuntimeError) updates) =>
      super.copyWith((message) => updates(message as RuntimeError))
          as RuntimeError;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RuntimeError() / RuntimeError.new instead')
  static RuntimeError create() => RuntimeError._();
  static $pb.GeneratedMessage $_createMessage() => RuntimeError._();
  @$core.override
  RuntimeError createEmptyInstance() => RuntimeError._();
  @$core.pragma('dart2js:noInline')
  static RuntimeError getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RuntimeError>(
          RuntimeError.$_createMessage);
  static RuntimeError? _defaultInstance;

  @$pb.TagNumber(1)
  RuntimeErrorCode get code => $_getN(0);
  @$pb.TagNumber(1)
  set code(RuntimeErrorCode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get retryable => $_getBF(2);
  @$pb.TagNumber(3)
  set retryable($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRetryable() => $_has(2);
  @$pb.TagNumber(3)
  void clearRetryable() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get javaClass => $_getSZ(3);
  @$pb.TagNumber(4)
  set javaClass($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasJavaClass() => $_has(3);
  @$pb.TagNumber(4)
  void clearJavaClass() => $_clearField(4);
}

class RuntimeHello extends $pb.GeneratedMessage {
  factory RuntimeHello({
    $core.int? protocolVersion,
    $core.String? hostAbi,
    $core.String? runtimeBaseline,
    $core.String? generation,
    $core.Iterable<$core.String>? capabilities,
    $core.bool? sourceReady,
  }) {
    final result = RuntimeHello._();
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (hostAbi != null) result.hostAbi = hostAbi;
    if (runtimeBaseline != null) result.runtimeBaseline = runtimeBaseline;
    if (generation != null) result.generation = generation;
    if (capabilities != null) result.capabilities.addAll(capabilities);
    if (sourceReady != null) result.sourceReady = sourceReady;
    return result;
  }

  RuntimeHello._();

  factory RuntimeHello.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RuntimeHello()..mergeFromBuffer(data, registry);
  factory RuntimeHello.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RuntimeHello()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RuntimeHello',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: RuntimeHello.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'hostAbi')
    ..aOS(3, _omitFieldNames ? '' : 'runtimeBaseline')
    ..aOS(4, _omitFieldNames ? '' : 'generation')
    ..pPS(5, _omitFieldNames ? '' : 'capabilities')
    ..aOB(6, _omitFieldNames ? '' : 'sourceReady')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RuntimeHello clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RuntimeHello copyWith(void Function(RuntimeHello) updates) =>
      super.copyWith((message) => updates(message as RuntimeHello))
          as RuntimeHello;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RuntimeHello() / RuntimeHello.new instead')
  static RuntimeHello create() => RuntimeHello._();
  static $pb.GeneratedMessage $_createMessage() => RuntimeHello._();
  @$core.override
  RuntimeHello createEmptyInstance() => RuntimeHello._();
  @$core.pragma('dart2js:noInline')
  static RuntimeHello getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RuntimeHello>(
          RuntimeHello.$_createMessage);
  static RuntimeHello? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get protocolVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set protocolVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProtocolVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearProtocolVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get hostAbi => $_getSZ(1);
  @$pb.TagNumber(2)
  set hostAbi($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHostAbi() => $_has(1);
  @$pb.TagNumber(2)
  void clearHostAbi() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get runtimeBaseline => $_getSZ(2);
  @$pb.TagNumber(3)
  set runtimeBaseline($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRuntimeBaseline() => $_has(2);
  @$pb.TagNumber(3)
  void clearRuntimeBaseline() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get generation => $_getSZ(3);
  @$pb.TagNumber(4)
  set generation($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasGeneration() => $_has(3);
  @$pb.TagNumber(4)
  void clearGeneration() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get capabilities => $_getList(4);

  @$pb.TagNumber(6)
  $core.bool get sourceReady => $_getBF(5);
  @$pb.TagNumber(6)
  set sourceReady($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSourceReady() => $_has(5);
  @$pb.TagNumber(6)
  void clearSourceReady() => $_clearField(6);
}

class SourceInfo extends $pb.GeneratedMessage {
  factory SourceInfo({
    $core.String? id,
    $core.String? name,
    $core.String? lang,
    $core.bool? supportsLatest,
    $core.String? baseUrl,
  }) {
    final result = SourceInfo._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (lang != null) result.lang = lang;
    if (supportsLatest != null) result.supportsLatest = supportsLatest;
    if (baseUrl != null) result.baseUrl = baseUrl;
    return result;
  }

  SourceInfo._();

  factory SourceInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourceInfo()..mergeFromBuffer(data, registry);
  factory SourceInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourceInfo()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SourceInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SourceInfo.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'lang')
    ..aOB(4, _omitFieldNames ? '' : 'supportsLatest')
    ..aOS(5, _omitFieldNames ? '' : 'baseUrl')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourceInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourceInfo copyWith(void Function(SourceInfo) updates) =>
      super.copyWith((message) => updates(message as SourceInfo)) as SourceInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SourceInfo() / SourceInfo.new instead')
  static SourceInfo create() => SourceInfo._();
  static $pb.GeneratedMessage $_createMessage() => SourceInfo._();
  @$core.override
  SourceInfo createEmptyInstance() => SourceInfo._();
  @$core.pragma('dart2js:noInline')
  static SourceInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SourceInfo>(SourceInfo.$_createMessage);
  static SourceInfo? _defaultInstance;

  /// Opaque signed 64-bit decimal identity; never a JavaScript number.
  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get lang => $_getSZ(2);
  @$pb.TagNumber(3)
  set lang($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLang() => $_has(2);
  @$pb.TagNumber(3)
  void clearLang() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get supportsLatest => $_getBF(3);
  @$pb.TagNumber(4)
  set supportsLatest($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSupportsLatest() => $_has(3);
  @$pb.TagNumber(4)
  void clearSupportsLatest() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get baseUrl => $_getSZ(4);
  @$pb.TagNumber(5)
  set baseUrl($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBaseUrl() => $_has(4);
  @$pb.TagNumber(5)
  void clearBaseUrl() => $_clearField(5);
}

class RuntimeSession extends $pb.GeneratedMessage {
  factory RuntimeSession({
    $core.int? protocolVersion,
    $core.String? workerInstanceId,
    $core.String? generation,
    $core.String? buildId,
    $core.Iterable<SourceInfo>? sources,
    $core.Iterable<$core.String>? capabilities,
    CatalogReference? catalog,
  }) {
    final result = RuntimeSession._();
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (workerInstanceId != null) result.workerInstanceId = workerInstanceId;
    if (generation != null) result.generation = generation;
    if (buildId != null) result.buildId = buildId;
    if (sources != null) result.sources.addAll(sources);
    if (capabilities != null) result.capabilities.addAll(capabilities);
    if (catalog != null) result.catalog = catalog;
    return result;
  }

  RuntimeSession._();

  factory RuntimeSession.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RuntimeSession()..mergeFromBuffer(data, registry);
  factory RuntimeSession.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RuntimeSession()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RuntimeSession',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: RuntimeSession.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'workerInstanceId')
    ..aOS(3, _omitFieldNames ? '' : 'generation')
    ..aOS(4, _omitFieldNames ? '' : 'buildId')
    ..pPM<SourceInfo>(5, _omitFieldNames ? '' : 'sources',
        subBuilder: SourceInfo.$_createMessage)
    ..pPS(6, _omitFieldNames ? '' : 'capabilities')
    ..aOM<CatalogReference>(7, _omitFieldNames ? '' : 'catalog',
        subBuilder: CatalogReference.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RuntimeSession clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RuntimeSession copyWith(void Function(RuntimeSession) updates) =>
      super.copyWith((message) => updates(message as RuntimeSession))
          as RuntimeSession;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RuntimeSession() / RuntimeSession.new instead')
  static RuntimeSession create() => RuntimeSession._();
  static $pb.GeneratedMessage $_createMessage() => RuntimeSession._();
  @$core.override
  RuntimeSession createEmptyInstance() => RuntimeSession._();
  @$core.pragma('dart2js:noInline')
  static RuntimeSession getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RuntimeSession>(
          RuntimeSession.$_createMessage);
  static RuntimeSession? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get protocolVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set protocolVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProtocolVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearProtocolVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get workerInstanceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set workerInstanceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWorkerInstanceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearWorkerInstanceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get generation => $_getSZ(2);
  @$pb.TagNumber(3)
  set generation($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGeneration() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeneration() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get buildId => $_getSZ(3);
  @$pb.TagNumber(4)
  set buildId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBuildId() => $_has(3);
  @$pb.TagNumber(4)
  void clearBuildId() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<SourceInfo> get sources => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbList<$core.String> get capabilities => $_getList(5);

  @$pb.TagNumber(7)
  CatalogReference get catalog => $_getN(6);
  @$pb.TagNumber(7)
  set catalog(CatalogReference value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasCatalog() => $_has(6);
  @$pb.TagNumber(7)
  void clearCatalog() => $_clearField(7);
  @$pb.TagNumber(7)
  CatalogReference ensureCatalog() => $_ensure(6);
}

class RpcEnvelope extends $pb.GeneratedMessage {
  factory RpcEnvelope({
    $core.int? protocolVersion,
    $core.String? workerInstanceId,
    $core.String? generation,
    $core.String? buildId,
    $core.String? requestId,
  }) {
    final result = RpcEnvelope._();
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (workerInstanceId != null) result.workerInstanceId = workerInstanceId;
    if (generation != null) result.generation = generation;
    if (buildId != null) result.buildId = buildId;
    if (requestId != null) result.requestId = requestId;
    return result;
  }

  RpcEnvelope._();

  factory RpcEnvelope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RpcEnvelope()..mergeFromBuffer(data, registry);
  factory RpcEnvelope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RpcEnvelope()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RpcEnvelope',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: RpcEnvelope.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'workerInstanceId')
    ..aOS(3, _omitFieldNames ? '' : 'generation')
    ..aOS(4, _omitFieldNames ? '' : 'buildId')
    ..aOS(5, _omitFieldNames ? '' : 'requestId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RpcEnvelope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RpcEnvelope copyWith(void Function(RpcEnvelope) updates) =>
      super.copyWith((message) => updates(message as RpcEnvelope))
          as RpcEnvelope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RpcEnvelope() / RpcEnvelope.new instead')
  static RpcEnvelope create() => RpcEnvelope._();
  static $pb.GeneratedMessage $_createMessage() => RpcEnvelope._();
  @$core.override
  RpcEnvelope createEmptyInstance() => RpcEnvelope._();
  @$core.pragma('dart2js:noInline')
  static RpcEnvelope getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RpcEnvelope>(
          RpcEnvelope.$_createMessage);
  static RpcEnvelope? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get protocolVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set protocolVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProtocolVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearProtocolVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get workerInstanceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set workerInstanceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWorkerInstanceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearWorkerInstanceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get generation => $_getSZ(2);
  @$pb.TagNumber(3)
  set generation($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGeneration() => $_has(2);
  @$pb.TagNumber(3)
  void clearGeneration() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get buildId => $_getSZ(3);
  @$pb.TagNumber(4)
  set buildId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBuildId() => $_has(3);
  @$pb.TagNumber(4)
  void clearBuildId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get requestId => $_getSZ(4);
  @$pb.TagNumber(5)
  set requestId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRequestId() => $_has(4);
  @$pb.TagNumber(5)
  void clearRequestId() => $_clearField(5);
}

class OpenRequest extends $pb.GeneratedMessage {
  factory OpenRequest({
    $core.String? manifestPath,
    $core.String? identity,
    $core.String? userAgent,
    $core.String? expectedBuildId,
    $core.String? expectedBundleSha256,
    PreferenceBootstrap? preferenceBootstrap,
    CatalogReference? catalog,
  }) {
    final result = OpenRequest._();
    if (manifestPath != null) result.manifestPath = manifestPath;
    if (identity != null) result.identity = identity;
    if (userAgent != null) result.userAgent = userAgent;
    if (expectedBuildId != null) result.expectedBuildId = expectedBuildId;
    if (expectedBundleSha256 != null)
      result.expectedBundleSha256 = expectedBundleSha256;
    if (preferenceBootstrap != null)
      result.preferenceBootstrap = preferenceBootstrap;
    if (catalog != null) result.catalog = catalog;
    return result;
  }

  OpenRequest._();

  factory OpenRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenRequest()..mergeFromBuffer(data, registry);
  factory OpenRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpenRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: OpenRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'manifestPath')
    ..aOS(2, _omitFieldNames ? '' : 'identity')
    ..aOS(3, _omitFieldNames ? '' : 'userAgent')
    ..aOS(4, _omitFieldNames ? '' : 'expectedBuildId')
    ..aOS(5, _omitFieldNames ? '' : 'expectedBundleSha256')
    ..aOM<PreferenceBootstrap>(6, _omitFieldNames ? '' : 'preferenceBootstrap',
        subBuilder: PreferenceBootstrap.$_createMessage)
    ..aOM<CatalogReference>(7, _omitFieldNames ? '' : 'catalog',
        subBuilder: CatalogReference.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenRequest copyWith(void Function(OpenRequest) updates) =>
      super.copyWith((message) => updates(message as OpenRequest))
          as OpenRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use OpenRequest() / OpenRequest.new instead')
  static OpenRequest create() => OpenRequest._();
  static $pb.GeneratedMessage $_createMessage() => OpenRequest._();
  @$core.override
  OpenRequest createEmptyInstance() => OpenRequest._();
  @$core.pragma('dart2js:noInline')
  static OpenRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OpenRequest>(
          OpenRequest.$_createMessage);
  static OpenRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get manifestPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set manifestPath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasManifestPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearManifestPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get identity => $_getSZ(1);
  @$pb.TagNumber(2)
  set identity($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIdentity() => $_has(1);
  @$pb.TagNumber(2)
  void clearIdentity() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get userAgent => $_getSZ(2);
  @$pb.TagNumber(3)
  set userAgent($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUserAgent() => $_has(2);
  @$pb.TagNumber(3)
  void clearUserAgent() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get expectedBuildId => $_getSZ(3);
  @$pb.TagNumber(4)
  set expectedBuildId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExpectedBuildId() => $_has(3);
  @$pb.TagNumber(4)
  void clearExpectedBuildId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get expectedBundleSha256 => $_getSZ(4);
  @$pb.TagNumber(5)
  set expectedBundleSha256($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasExpectedBundleSha256() => $_has(4);
  @$pb.TagNumber(5)
  void clearExpectedBundleSha256() => $_clearField(5);

  @$pb.TagNumber(6)
  PreferenceBootstrap get preferenceBootstrap => $_getN(5);
  @$pb.TagNumber(6)
  set preferenceBootstrap(PreferenceBootstrap value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasPreferenceBootstrap() => $_has(5);
  @$pb.TagNumber(6)
  void clearPreferenceBootstrap() => $_clearField(6);
  @$pb.TagNumber(6)
  PreferenceBootstrap ensurePreferenceBootstrap() => $_ensure(5);

  @$pb.TagNumber(7)
  CatalogReference get catalog => $_getN(6);
  @$pb.TagNumber(7)
  set catalog(CatalogReference value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasCatalog() => $_has(6);
  @$pb.TagNumber(7)
  void clearCatalog() => $_clearField(7);
  @$pb.TagNumber(7)
  CatalogReference ensureCatalog() => $_ensure(6);
}

class Manga extends $pb.GeneratedMessage {
  factory Manga({
    $core.String? url,
    $core.String? title,
    $core.String? author,
    $core.String? artist,
    $core.String? description,
    $core.String? genre,
    $core.Iterable<$core.String>? genres,
    $core.int? status,
    $core.String? thumbnailUrl,
    $core.bool? initialized,
    $core.String? updateStrategy,
    $core.String? memoJson,
  }) {
    final result = Manga._();
    if (url != null) result.url = url;
    if (title != null) result.title = title;
    if (author != null) result.author = author;
    if (artist != null) result.artist = artist;
    if (description != null) result.description = description;
    if (genre != null) result.genre = genre;
    if (genres != null) result.genres.addAll(genres);
    if (status != null) result.status = status;
    if (thumbnailUrl != null) result.thumbnailUrl = thumbnailUrl;
    if (initialized != null) result.initialized = initialized;
    if (updateStrategy != null) result.updateStrategy = updateStrategy;
    if (memoJson != null) result.memoJson = memoJson;
    return result;
  }

  Manga._();

  factory Manga.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Manga()..mergeFromBuffer(data, registry);
  factory Manga.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Manga()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Manga',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: Manga.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'author')
    ..aOS(4, _omitFieldNames ? '' : 'artist')
    ..aOS(5, _omitFieldNames ? '' : 'description')
    ..aOS(6, _omitFieldNames ? '' : 'genre')
    ..pPS(7, _omitFieldNames ? '' : 'genres')
    ..aI(8, _omitFieldNames ? '' : 'status')
    ..aOS(9, _omitFieldNames ? '' : 'thumbnailUrl')
    ..aOB(10, _omitFieldNames ? '' : 'initialized')
    ..aOS(11, _omitFieldNames ? '' : 'updateStrategy')
    ..aOS(12, _omitFieldNames ? '' : 'memoJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Manga clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Manga copyWith(void Function(Manga) updates) =>
      super.copyWith((message) => updates(message as Manga)) as Manga;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Manga() / Manga.new instead')
  static Manga create() => Manga._();
  static $pb.GeneratedMessage $_createMessage() => Manga._();
  @$core.override
  Manga createEmptyInstance() => Manga._();
  @$core.pragma('dart2js:noInline')
  static Manga getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Manga>(Manga.$_createMessage);
  static Manga? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get author => $_getSZ(2);
  @$pb.TagNumber(3)
  set author($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAuthor() => $_has(2);
  @$pb.TagNumber(3)
  void clearAuthor() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get artist => $_getSZ(3);
  @$pb.TagNumber(4)
  set artist($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasArtist() => $_has(3);
  @$pb.TagNumber(4)
  void clearArtist() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get description => $_getSZ(4);
  @$pb.TagNumber(5)
  set description($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDescription() => $_has(4);
  @$pb.TagNumber(5)
  void clearDescription() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get genre => $_getSZ(5);
  @$pb.TagNumber(6)
  set genre($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasGenre() => $_has(5);
  @$pb.TagNumber(6)
  void clearGenre() => $_clearField(6);

  @$pb.TagNumber(7)
  $pb.PbList<$core.String> get genres => $_getList(6);

  @$pb.TagNumber(8)
  $core.int get status => $_getIZ(7);
  @$pb.TagNumber(8)
  set status($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasStatus() => $_has(7);
  @$pb.TagNumber(8)
  void clearStatus() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get thumbnailUrl => $_getSZ(8);
  @$pb.TagNumber(9)
  set thumbnailUrl($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasThumbnailUrl() => $_has(8);
  @$pb.TagNumber(9)
  void clearThumbnailUrl() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.bool get initialized => $_getBF(9);
  @$pb.TagNumber(10)
  set initialized($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasInitialized() => $_has(9);
  @$pb.TagNumber(10)
  void clearInitialized() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get updateStrategy => $_getSZ(10);
  @$pb.TagNumber(11)
  set updateStrategy($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasUpdateStrategy() => $_has(10);
  @$pb.TagNumber(11)
  void clearUpdateStrategy() => $_clearField(11);

  /// The only extension-defined JSON escape hatch. A bounded UTF-8 JSON object,
  /// opaque to TS/Dart so large JSON numeric lexemes survive a round trip.
  @$pb.TagNumber(12)
  $core.String get memoJson => $_getSZ(11);
  @$pb.TagNumber(12)
  set memoJson($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasMemoJson() => $_has(11);
  @$pb.TagNumber(12)
  void clearMemoJson() => $_clearField(12);
}

class Chapter extends $pb.GeneratedMessage {
  factory Chapter({
    $core.String? url,
    $core.String? name,
    $core.double? chapterNumber,
    $core.String? scanlator,
    $core.String? dateUpload,
    $core.int? sourceOrder,
    $core.String? memoJson,
  }) {
    final result = Chapter._();
    if (url != null) result.url = url;
    if (name != null) result.name = name;
    if (chapterNumber != null) result.chapterNumber = chapterNumber;
    if (scanlator != null) result.scanlator = scanlator;
    if (dateUpload != null) result.dateUpload = dateUpload;
    if (sourceOrder != null) result.sourceOrder = sourceOrder;
    if (memoJson != null) result.memoJson = memoJson;
    return result;
  }

  Chapter._();

  factory Chapter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Chapter()..mergeFromBuffer(data, registry);
  factory Chapter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Chapter()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Chapter',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: Chapter.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aD(3, _omitFieldNames ? '' : 'chapterNumber',
        fieldType: $pb.PbFieldType.OF)
    ..aOS(4, _omitFieldNames ? '' : 'scanlator')
    ..aOS(5, _omitFieldNames ? '' : 'dateUpload')
    ..aI(6, _omitFieldNames ? '' : 'sourceOrder',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(7, _omitFieldNames ? '' : 'memoJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Chapter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Chapter copyWith(void Function(Chapter) updates) =>
      super.copyWith((message) => updates(message as Chapter)) as Chapter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Chapter() / Chapter.new instead')
  static Chapter create() => Chapter._();
  static $pb.GeneratedMessage $_createMessage() => Chapter._();
  @$core.override
  Chapter createEmptyInstance() => Chapter._();
  @$core.pragma('dart2js:noInline')
  static Chapter getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Chapter>(Chapter.$_createMessage);
  static Chapter? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get chapterNumber => $_getN(2);
  @$pb.TagNumber(3)
  set chapterNumber($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasChapterNumber() => $_has(2);
  @$pb.TagNumber(3)
  void clearChapterNumber() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get scanlator => $_getSZ(3);
  @$pb.TagNumber(4)
  set scanlator($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasScanlator() => $_has(3);
  @$pb.TagNumber(4)
  void clearScanlator() => $_clearField(4);

  /// Opaque signed int64 decimal text from the original Source.
  @$pb.TagNumber(5)
  $core.String get dateUpload => $_getSZ(4);
  @$pb.TagNumber(5)
  set dateUpload($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDateUpload() => $_has(4);
  @$pb.TagNumber(5)
  void clearDateUpload() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get sourceOrder => $_getIZ(5);
  @$pb.TagNumber(6)
  set sourceOrder($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSourceOrder() => $_has(5);
  @$pb.TagNumber(6)
  void clearSourceOrder() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get memoJson => $_getSZ(6);
  @$pb.TagNumber(7)
  set memoJson($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMemoJson() => $_has(6);
  @$pb.TagNumber(7)
  void clearMemoJson() => $_clearField(7);
}

class Page extends $pb.GeneratedMessage {
  factory Page({
    $core.String? pageKey,
    $core.int? index,
    $core.int? sourceIndex,
    $core.String? url,
    $core.String? imageUrl,
  }) {
    final result = Page._();
    if (pageKey != null) result.pageKey = pageKey;
    if (index != null) result.index = index;
    if (sourceIndex != null) result.sourceIndex = sourceIndex;
    if (url != null) result.url = url;
    if (imageUrl != null) result.imageUrl = imageUrl;
    return result;
  }

  Page._();

  factory Page.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Page()..mergeFromBuffer(data, registry);
  factory Page.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Page()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Page',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: Page.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'pageKey')
    ..aI(2, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'sourceIndex')
    ..aOS(4, _omitFieldNames ? '' : 'url')
    ..aOS(5, _omitFieldNames ? '' : 'imageUrl')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Page clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Page copyWith(void Function(Page) updates) =>
      super.copyWith((message) => updates(message as Page)) as Page;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Page() / Page.new instead')
  static Page create() => Page._();
  static $pb.GeneratedMessage $_createMessage() => Page._();
  @$core.override
  Page createEmptyInstance() => Page._();
  @$core.pragma('dart2js:noInline')
  static Page getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Page>(Page.$_createMessage);
  static Page? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get pageKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set pageKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPageKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearPageKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get index => $_getIZ(1);
  @$pb.TagNumber(2)
  set index($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIndex() => $_has(1);
  @$pb.TagNumber(2)
  void clearIndex() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get sourceIndex => $_getIZ(2);
  @$pb.TagNumber(3)
  set sourceIndex($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSourceIndex() => $_has(2);
  @$pb.TagNumber(3)
  void clearSourceIndex() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get url => $_getSZ(3);
  @$pb.TagNumber(4)
  set url($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUrl() => $_has(3);
  @$pb.TagNumber(4)
  void clearUrl() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get imageUrl => $_getSZ(4);
  @$pb.TagNumber(5)
  set imageUrl($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasImageUrl() => $_has(4);
  @$pb.TagNumber(5)
  void clearImageUrl() => $_clearField(5);
}

class PageRequest extends $pb.GeneratedMessage {
  factory PageRequest({
    $core.int? page,
  }) {
    final result = PageRequest._();
    if (page != null) result.page = page;
    return result;
  }

  PageRequest._();

  factory PageRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PageRequest()..mergeFromBuffer(data, registry);
  factory PageRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PageRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PageRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PageRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'page', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PageRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PageRequest copyWith(void Function(PageRequest) updates) =>
      super.copyWith((message) => updates(message as PageRequest))
          as PageRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PageRequest() / PageRequest.new instead')
  static PageRequest create() => PageRequest._();
  static $pb.GeneratedMessage $_createMessage() => PageRequest._();
  @$core.override
  PageRequest createEmptyInstance() => PageRequest._();
  @$core.pragma('dart2js:noInline')
  static PageRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PageRequest>(
          PageRequest.$_createMessage);
  static PageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get page => $_getIZ(0);
  @$pb.TagNumber(1)
  set page($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPage() => $_has(0);
  @$pb.TagNumber(1)
  void clearPage() => $_clearField(1);
}

/// Filter paths use zero-based indexes from the top-level list. Snapshots are
/// ephemeral and belong to the Source and generation that produced them.
class FilterText extends $pb.GeneratedMessage {
  factory FilterText({
    $core.String? state,
  }) {
    final result = FilterText._();
    if (state != null) result.state = state;
    return result;
  }

  FilterText._();

  factory FilterText.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterText()..mergeFromBuffer(data, registry);
  factory FilterText.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterText()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterText',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterText.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'state')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterText clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterText copyWith(void Function(FilterText) updates) =>
      super.copyWith((message) => updates(message as FilterText)) as FilterText;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterText() / FilterText.new instead')
  static FilterText create() => FilterText._();
  static $pb.GeneratedMessage $_createMessage() => FilterText._();
  @$core.override
  FilterText createEmptyInstance() => FilterText._();
  @$core.pragma('dart2js:noInline')
  static FilterText getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FilterText>(FilterText.$_createMessage);
  static FilterText? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get state => $_getSZ(0);
  @$pb.TagNumber(1)
  set state($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);
}

class FilterCheckBox extends $pb.GeneratedMessage {
  factory FilterCheckBox({
    $core.bool? state,
  }) {
    final result = FilterCheckBox._();
    if (state != null) result.state = state;
    return result;
  }

  FilterCheckBox._();

  factory FilterCheckBox.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterCheckBox()..mergeFromBuffer(data, registry);
  factory FilterCheckBox.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterCheckBox()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterCheckBox',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterCheckBox.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'state')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterCheckBox clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterCheckBox copyWith(void Function(FilterCheckBox) updates) =>
      super.copyWith((message) => updates(message as FilterCheckBox))
          as FilterCheckBox;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterCheckBox() / FilterCheckBox.new instead')
  static FilterCheckBox create() => FilterCheckBox._();
  static $pb.GeneratedMessage $_createMessage() => FilterCheckBox._();
  @$core.override
  FilterCheckBox createEmptyInstance() => FilterCheckBox._();
  @$core.pragma('dart2js:noInline')
  static FilterCheckBox getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FilterCheckBox>(
          FilterCheckBox.$_createMessage);
  static FilterCheckBox? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get state => $_getBF(0);
  @$pb.TagNumber(1)
  set state($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);
}

class FilterTriState extends $pb.GeneratedMessage {
  factory FilterTriState({
    $core.int? state,
  }) {
    final result = FilterTriState._();
    if (state != null) result.state = state;
    return result;
  }

  FilterTriState._();

  factory FilterTriState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterTriState()..mergeFromBuffer(data, registry);
  factory FilterTriState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterTriState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterTriState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterTriState.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'state', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterTriState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterTriState copyWith(void Function(FilterTriState) updates) =>
      super.copyWith((message) => updates(message as FilterTriState))
          as FilterTriState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterTriState() / FilterTriState.new instead')
  static FilterTriState create() => FilterTriState._();
  static $pb.GeneratedMessage $_createMessage() => FilterTriState._();
  @$core.override
  FilterTriState createEmptyInstance() => FilterTriState._();
  @$core.pragma('dart2js:noInline')
  static FilterTriState getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FilterTriState>(
          FilterTriState.$_createMessage);
  static FilterTriState? _defaultInstance;

  /// Original Source states: 0 ignore, 1 include, 2 exclude.
  @$pb.TagNumber(1)
  $core.int get state => $_getIZ(0);
  @$pb.TagNumber(1)
  set state($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => $_clearField(1);
}

class FilterSelect extends $pb.GeneratedMessage {
  factory FilterSelect({
    $core.Iterable<$core.String>? options,
    $core.int? state,
  }) {
    final result = FilterSelect._();
    if (options != null) result.options.addAll(options);
    if (state != null) result.state = state;
    return result;
  }

  FilterSelect._();

  factory FilterSelect.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSelect()..mergeFromBuffer(data, registry);
  factory FilterSelect.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSelect()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterSelect',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterSelect.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'options')
    ..aI(2, _omitFieldNames ? '' : 'state', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSelect clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSelect copyWith(void Function(FilterSelect) updates) =>
      super.copyWith((message) => updates(message as FilterSelect))
          as FilterSelect;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterSelect() / FilterSelect.new instead')
  static FilterSelect create() => FilterSelect._();
  static $pb.GeneratedMessage $_createMessage() => FilterSelect._();
  @$core.override
  FilterSelect createEmptyInstance() => FilterSelect._();
  @$core.pragma('dart2js:noInline')
  static FilterSelect getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FilterSelect>(
          FilterSelect.$_createMessage);
  static FilterSelect? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get options => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get state => $_getIZ(1);
  @$pb.TagNumber(2)
  set state($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);
}

class FilterSortSelection extends $pb.GeneratedMessage {
  factory FilterSortSelection({
    $core.int? index,
    $core.bool? ascending,
  }) {
    final result = FilterSortSelection._();
    if (index != null) result.index = index;
    if (ascending != null) result.ascending = ascending;
    return result;
  }

  FilterSortSelection._();

  factory FilterSortSelection.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSortSelection()..mergeFromBuffer(data, registry);
  factory FilterSortSelection.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSortSelection()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterSortSelection',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterSortSelection.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'index', fieldType: $pb.PbFieldType.OU3)
    ..aOB(2, _omitFieldNames ? '' : 'ascending')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSortSelection clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSortSelection copyWith(void Function(FilterSortSelection) updates) =>
      super.copyWith((message) => updates(message as FilterSortSelection))
          as FilterSortSelection;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use FilterSortSelection() / FilterSortSelection.new instead')
  static FilterSortSelection create() => FilterSortSelection._();
  static $pb.GeneratedMessage $_createMessage() => FilterSortSelection._();
  @$core.override
  FilterSortSelection createEmptyInstance() => FilterSortSelection._();
  @$core.pragma('dart2js:noInline')
  static FilterSortSelection getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FilterSortSelection>(
          FilterSortSelection.$_createMessage);
  static FilterSortSelection? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get index => $_getIZ(0);
  @$pb.TagNumber(1)
  set index($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIndex() => $_has(0);
  @$pb.TagNumber(1)
  void clearIndex() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get ascending => $_getBF(1);
  @$pb.TagNumber(2)
  set ascending($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAscending() => $_has(1);
  @$pb.TagNumber(2)
  void clearAscending() => $_clearField(2);
}

class FilterSortState extends $pb.GeneratedMessage {
  factory FilterSortState({
    FilterSortSelection? selection,
  }) {
    final result = FilterSortState._();
    if (selection != null) result.selection = selection;
    return result;
  }

  FilterSortState._();

  factory FilterSortState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSortState()..mergeFromBuffer(data, registry);
  factory FilterSortState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSortState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterSortState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterSortState.$_createMessage)
    ..aOM<FilterSortSelection>(1, _omitFieldNames ? '' : 'selection',
        subBuilder: FilterSortSelection.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSortState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSortState copyWith(void Function(FilterSortState) updates) =>
      super.copyWith((message) => updates(message as FilterSortState))
          as FilterSortState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterSortState() / FilterSortState.new instead')
  static FilterSortState create() => FilterSortState._();
  static $pb.GeneratedMessage $_createMessage() => FilterSortState._();
  @$core.override
  FilterSortState createEmptyInstance() => FilterSortState._();
  @$core.pragma('dart2js:noInline')
  static FilterSortState getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FilterSortState>(
          FilterSortState.$_createMessage);
  static FilterSortState? _defaultInstance;

  /// Absence explicitly means the Source's nullable sort selection.
  @$pb.TagNumber(1)
  FilterSortSelection get selection => $_getN(0);
  @$pb.TagNumber(1)
  set selection(FilterSortSelection value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSelection() => $_has(0);
  @$pb.TagNumber(1)
  void clearSelection() => $_clearField(1);
  @$pb.TagNumber(1)
  FilterSortSelection ensureSelection() => $_ensure(0);
}

class FilterSort extends $pb.GeneratedMessage {
  factory FilterSort({
    $core.Iterable<$core.String>? options,
    FilterSortState? state,
  }) {
    final result = FilterSort._();
    if (options != null) result.options.addAll(options);
    if (state != null) result.state = state;
    return result;
  }

  FilterSort._();

  factory FilterSort.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSort()..mergeFromBuffer(data, registry);
  factory FilterSort.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSort()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterSort',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterSort.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'options')
    ..aOM<FilterSortState>(2, _omitFieldNames ? '' : 'state',
        subBuilder: FilterSortState.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSort clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSort copyWith(void Function(FilterSort) updates) =>
      super.copyWith((message) => updates(message as FilterSort)) as FilterSort;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterSort() / FilterSort.new instead')
  static FilterSort create() => FilterSort._();
  static $pb.GeneratedMessage $_createMessage() => FilterSort._();
  @$core.override
  FilterSort createEmptyInstance() => FilterSort._();
  @$core.pragma('dart2js:noInline')
  static FilterSort getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FilterSort>(FilterSort.$_createMessage);
  static FilterSort? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get options => $_getList(0);

  @$pb.TagNumber(2)
  FilterSortState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state(FilterSortState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);
  @$pb.TagNumber(2)
  FilterSortState ensureState() => $_ensure(1);
}

class FilterGroup extends $pb.GeneratedMessage {
  factory FilterGroup({
    $core.Iterable<FilterNode>? nodes,
  }) {
    final result = FilterGroup._();
    if (nodes != null) result.nodes.addAll(nodes);
    return result;
  }

  FilterGroup._();

  factory FilterGroup.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterGroup()..mergeFromBuffer(data, registry);
  factory FilterGroup.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterGroup()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterGroup',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterGroup.$_createMessage)
    ..pPM<FilterNode>(1, _omitFieldNames ? '' : 'nodes',
        subBuilder: FilterNode.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterGroup clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterGroup copyWith(void Function(FilterGroup) updates) =>
      super.copyWith((message) => updates(message as FilterGroup))
          as FilterGroup;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterGroup() / FilterGroup.new instead')
  static FilterGroup create() => FilterGroup._();
  static $pb.GeneratedMessage $_createMessage() => FilterGroup._();
  @$core.override
  FilterGroup createEmptyInstance() => FilterGroup._();
  @$core.pragma('dart2js:noInline')
  static FilterGroup getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FilterGroup>(
          FilterGroup.$_createMessage);
  static FilterGroup? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<FilterNode> get nodes => $_getList(0);
}

enum FilterNode_Kind {
  header,
  separator,
  text,
  checkBox,
  triState,
  select,
  sort,
  group,
  notSet
}

class FilterNode extends $pb.GeneratedMessage {
  factory FilterNode({
    $core.String? name,
    Empty? header,
    Empty? separator,
    FilterText? text,
    FilterCheckBox? checkBox,
    FilterTriState? triState,
    FilterSelect? select,
    FilterSort? sort,
    FilterGroup? group,
  }) {
    final result = FilterNode._();
    if (name != null) result.name = name;
    if (header != null) result.header = header;
    if (separator != null) result.separator = separator;
    if (text != null) result.text = text;
    if (checkBox != null) result.checkBox = checkBox;
    if (triState != null) result.triState = triState;
    if (select != null) result.select = select;
    if (sort != null) result.sort = sort;
    if (group != null) result.group = group;
    return result;
  }

  FilterNode._();

  factory FilterNode.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterNode()..mergeFromBuffer(data, registry);
  factory FilterNode.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterNode()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, FilterNode_Kind> _FilterNode_KindByTag = {
    2: FilterNode_Kind.header,
    3: FilterNode_Kind.separator,
    4: FilterNode_Kind.text,
    5: FilterNode_Kind.checkBox,
    6: FilterNode_Kind.triState,
    7: FilterNode_Kind.select,
    8: FilterNode_Kind.sort,
    9: FilterNode_Kind.group,
    0: FilterNode_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterNode',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterNode.$_createMessage)
    ..oo(0, [2, 3, 4, 5, 6, 7, 8, 9])
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOM<Empty>(2, _omitFieldNames ? '' : 'header',
        subBuilder: Empty.$_createMessage)
    ..aOM<Empty>(3, _omitFieldNames ? '' : 'separator',
        subBuilder: Empty.$_createMessage)
    ..aOM<FilterText>(4, _omitFieldNames ? '' : 'text',
        subBuilder: FilterText.$_createMessage)
    ..aOM<FilterCheckBox>(5, _omitFieldNames ? '' : 'checkBox',
        subBuilder: FilterCheckBox.$_createMessage)
    ..aOM<FilterTriState>(6, _omitFieldNames ? '' : 'triState',
        subBuilder: FilterTriState.$_createMessage)
    ..aOM<FilterSelect>(7, _omitFieldNames ? '' : 'select',
        subBuilder: FilterSelect.$_createMessage)
    ..aOM<FilterSort>(8, _omitFieldNames ? '' : 'sort',
        subBuilder: FilterSort.$_createMessage)
    ..aOM<FilterGroup>(9, _omitFieldNames ? '' : 'group',
        subBuilder: FilterGroup.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterNode clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterNode copyWith(void Function(FilterNode) updates) =>
      super.copyWith((message) => updates(message as FilterNode)) as FilterNode;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterNode() / FilterNode.new instead')
  static FilterNode create() => FilterNode._();
  static $pb.GeneratedMessage $_createMessage() => FilterNode._();
  @$core.override
  FilterNode createEmptyInstance() => FilterNode._();
  @$core.pragma('dart2js:noInline')
  static FilterNode getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FilterNode>(FilterNode.$_createMessage);
  static FilterNode? _defaultInstance;

  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  FilterNode_Kind whichKind() => _FilterNode_KindByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  void clearKind() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  Empty get header => $_getN(1);
  @$pb.TagNumber(2)
  set header(Empty value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasHeader() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeader() => $_clearField(2);
  @$pb.TagNumber(2)
  Empty ensureHeader() => $_ensure(1);

  @$pb.TagNumber(3)
  Empty get separator => $_getN(2);
  @$pb.TagNumber(3)
  set separator(Empty value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasSeparator() => $_has(2);
  @$pb.TagNumber(3)
  void clearSeparator() => $_clearField(3);
  @$pb.TagNumber(3)
  Empty ensureSeparator() => $_ensure(2);

  @$pb.TagNumber(4)
  FilterText get text => $_getN(3);
  @$pb.TagNumber(4)
  set text(FilterText value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasText() => $_has(3);
  @$pb.TagNumber(4)
  void clearText() => $_clearField(4);
  @$pb.TagNumber(4)
  FilterText ensureText() => $_ensure(3);

  @$pb.TagNumber(5)
  FilterCheckBox get checkBox => $_getN(4);
  @$pb.TagNumber(5)
  set checkBox(FilterCheckBox value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasCheckBox() => $_has(4);
  @$pb.TagNumber(5)
  void clearCheckBox() => $_clearField(5);
  @$pb.TagNumber(5)
  FilterCheckBox ensureCheckBox() => $_ensure(4);

  @$pb.TagNumber(6)
  FilterTriState get triState => $_getN(5);
  @$pb.TagNumber(6)
  set triState(FilterTriState value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasTriState() => $_has(5);
  @$pb.TagNumber(6)
  void clearTriState() => $_clearField(6);
  @$pb.TagNumber(6)
  FilterTriState ensureTriState() => $_ensure(5);

  @$pb.TagNumber(7)
  FilterSelect get select => $_getN(6);
  @$pb.TagNumber(7)
  set select(FilterSelect value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasSelect() => $_has(6);
  @$pb.TagNumber(7)
  void clearSelect() => $_clearField(7);
  @$pb.TagNumber(7)
  FilterSelect ensureSelect() => $_ensure(6);

  @$pb.TagNumber(8)
  FilterSort get sort => $_getN(7);
  @$pb.TagNumber(8)
  set sort(FilterSort value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasSort() => $_has(7);
  @$pb.TagNumber(8)
  void clearSort() => $_clearField(8);
  @$pb.TagNumber(8)
  FilterSort ensureSort() => $_ensure(7);

  @$pb.TagNumber(9)
  FilterGroup get group => $_getN(8);
  @$pb.TagNumber(9)
  set group(FilterGroup value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasGroup() => $_has(8);
  @$pb.TagNumber(9)
  void clearGroup() => $_clearField(9);
  @$pb.TagNumber(9)
  FilterGroup ensureGroup() => $_ensure(8);
}

class GetFiltersRequest extends $pb.GeneratedMessage {
  factory GetFiltersRequest({
    $core.String? retainedSnapshotId,
  }) {
    final result = GetFiltersRequest._();
    if (retainedSnapshotId != null)
      result.retainedSnapshotId = retainedSnapshotId;
    return result;
  }

  GetFiltersRequest._();

  factory GetFiltersRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetFiltersRequest()..mergeFromBuffer(data, registry);
  factory GetFiltersRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GetFiltersRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GetFiltersRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: GetFiltersRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'retainedSnapshotId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFiltersRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GetFiltersRequest copyWith(void Function(GetFiltersRequest) updates) =>
      super.copyWith((message) => updates(message as GetFiltersRequest))
          as GetFiltersRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GetFiltersRequest() / GetFiltersRequest.new instead')
  static GetFiltersRequest create() => GetFiltersRequest._();
  static $pb.GeneratedMessage $_createMessage() => GetFiltersRequest._();
  @$core.override
  GetFiltersRequest createEmptyInstance() => GetFiltersRequest._();
  @$core.pragma('dart2js:noInline')
  static GetFiltersRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GetFiltersRequest>(
          GetFiltersRequest.$_createMessage);
  static GetFiltersRequest? _defaultInstance;

  /// Keep the client's applied snapshot while publishing a fresh draft.
  @$pb.TagNumber(1)
  $core.String get retainedSnapshotId => $_getSZ(0);
  @$pb.TagNumber(1)
  set retainedSnapshotId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRetainedSnapshotId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRetainedSnapshotId() => $_clearField(1);
}

class FilterSnapshot extends $pb.GeneratedMessage {
  factory FilterSnapshot({
    $core.String? snapshotId,
    $core.Iterable<FilterNode>? nodes,
  }) {
    final result = FilterSnapshot._();
    if (snapshotId != null) result.snapshotId = snapshotId;
    if (nodes != null) result.nodes.addAll(nodes);
    return result;
  }

  FilterSnapshot._();

  factory FilterSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSnapshot()..mergeFromBuffer(data, registry);
  factory FilterSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSnapshot()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterSnapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterSnapshot.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'snapshotId')
    ..pPM<FilterNode>(2, _omitFieldNames ? '' : 'nodes',
        subBuilder: FilterNode.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSnapshot copyWith(void Function(FilterSnapshot) updates) =>
      super.copyWith((message) => updates(message as FilterSnapshot))
          as FilterSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterSnapshot() / FilterSnapshot.new instead')
  static FilterSnapshot create() => FilterSnapshot._();
  static $pb.GeneratedMessage $_createMessage() => FilterSnapshot._();
  @$core.override
  FilterSnapshot createEmptyInstance() => FilterSnapshot._();
  @$core.pragma('dart2js:noInline')
  static FilterSnapshot getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FilterSnapshot>(
          FilterSnapshot.$_createMessage);
  static FilterSnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get snapshotId => $_getSZ(0);
  @$pb.TagNumber(1)
  set snapshotId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSnapshotId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSnapshotId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<FilterNode> get nodes => $_getList(1);
}

enum FilterUpdate_State { text, checkBox, triState, select, sort, notSet }

class FilterUpdate extends $pb.GeneratedMessage {
  factory FilterUpdate({
    $core.Iterable<$core.int>? path,
    $core.String? text,
    $core.bool? checkBox,
    $core.int? triState,
    $core.int? select,
    FilterSortState? sort,
  }) {
    final result = FilterUpdate._();
    if (path != null) result.path.addAll(path);
    if (text != null) result.text = text;
    if (checkBox != null) result.checkBox = checkBox;
    if (triState != null) result.triState = triState;
    if (select != null) result.select = select;
    if (sort != null) result.sort = sort;
    return result;
  }

  FilterUpdate._();

  factory FilterUpdate.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterUpdate()..mergeFromBuffer(data, registry);
  factory FilterUpdate.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterUpdate()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, FilterUpdate_State>
      _FilterUpdate_StateByTag = {
    2: FilterUpdate_State.text,
    3: FilterUpdate_State.checkBox,
    4: FilterUpdate_State.triState,
    5: FilterUpdate_State.select,
    6: FilterUpdate_State.sort,
    0: FilterUpdate_State.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterUpdate',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterUpdate.$_createMessage)
    ..oo(0, [2, 3, 4, 5, 6])
    ..p<$core.int>(1, _omitFieldNames ? '' : 'path', $pb.PbFieldType.KU3)
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..aOB(3, _omitFieldNames ? '' : 'checkBox')
    ..aI(4, _omitFieldNames ? '' : 'triState', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'select', fieldType: $pb.PbFieldType.OU3)
    ..aOM<FilterSortState>(6, _omitFieldNames ? '' : 'sort',
        subBuilder: FilterSortState.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterUpdate clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterUpdate copyWith(void Function(FilterUpdate) updates) =>
      super.copyWith((message) => updates(message as FilterUpdate))
          as FilterUpdate;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterUpdate() / FilterUpdate.new instead')
  static FilterUpdate create() => FilterUpdate._();
  static $pb.GeneratedMessage $_createMessage() => FilterUpdate._();
  @$core.override
  FilterUpdate createEmptyInstance() => FilterUpdate._();
  @$core.pragma('dart2js:noInline')
  static FilterUpdate getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FilterUpdate>(
          FilterUpdate.$_createMessage);
  static FilterUpdate? _defaultInstance;

  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  FilterUpdate_State whichState() => _FilterUpdate_StateByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  void clearState() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $pb.PbList<$core.int> get path => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get checkBox => $_getBF(2);
  @$pb.TagNumber(3)
  set checkBox($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCheckBox() => $_has(2);
  @$pb.TagNumber(3)
  void clearCheckBox() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get triState => $_getIZ(3);
  @$pb.TagNumber(4)
  set triState($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTriState() => $_has(3);
  @$pb.TagNumber(4)
  void clearTriState() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get select => $_getIZ(4);
  @$pb.TagNumber(5)
  set select($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSelect() => $_has(4);
  @$pb.TagNumber(5)
  void clearSelect() => $_clearField(5);

  @$pb.TagNumber(6)
  FilterSortState get sort => $_getN(5);
  @$pb.TagNumber(6)
  set sort(FilterSortState value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasSort() => $_has(5);
  @$pb.TagNumber(6)
  void clearSort() => $_clearField(6);
  @$pb.TagNumber(6)
  FilterSortState ensureSort() => $_ensure(5);
}

class FilterSelection extends $pb.GeneratedMessage {
  factory FilterSelection({
    $core.String? snapshotId,
    $core.Iterable<FilterUpdate>? updates,
  }) {
    final result = FilterSelection._();
    if (snapshotId != null) result.snapshotId = snapshotId;
    if (updates != null) result.updates.addAll(updates);
    return result;
  }

  FilterSelection._();

  factory FilterSelection.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSelection()..mergeFromBuffer(data, registry);
  factory FilterSelection.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FilterSelection()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterSelection',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FilterSelection.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'snapshotId')
    ..pPM<FilterUpdate>(2, _omitFieldNames ? '' : 'updates',
        subBuilder: FilterUpdate.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSelection clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterSelection copyWith(void Function(FilterSelection) updates) =>
      super.copyWith((message) => updates(message as FilterSelection))
          as FilterSelection;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FilterSelection() / FilterSelection.new instead')
  static FilterSelection create() => FilterSelection._();
  static $pb.GeneratedMessage $_createMessage() => FilterSelection._();
  @$core.override
  FilterSelection createEmptyInstance() => FilterSelection._();
  @$core.pragma('dart2js:noInline')
  static FilterSelection getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FilterSelection>(
          FilterSelection.$_createMessage);
  static FilterSelection? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get snapshotId => $_getSZ(0);
  @$pb.TagNumber(1)
  set snapshotId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSnapshotId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSnapshotId() => $_clearField(1);

  /// Every editable leaf is supplied, including false, zero and null sort.
  @$pb.TagNumber(2)
  $pb.PbList<FilterUpdate> get updates => $_getList(1);
}

class SearchRequest extends $pb.GeneratedMessage {
  factory SearchRequest({
    $core.int? page,
    $core.String? query,
    FilterSelection? filters,
  }) {
    final result = SearchRequest._();
    if (page != null) result.page = page;
    if (query != null) result.query = query;
    if (filters != null) result.filters = filters;
    return result;
  }

  SearchRequest._();

  factory SearchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchRequest()..mergeFromBuffer(data, registry);
  factory SearchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SearchRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SearchRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SearchRequest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'page', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'query')
    ..aOM<FilterSelection>(3, _omitFieldNames ? '' : 'filters',
        subBuilder: FilterSelection.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SearchRequest copyWith(void Function(SearchRequest) updates) =>
      super.copyWith((message) => updates(message as SearchRequest))
          as SearchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SearchRequest() / SearchRequest.new instead')
  static SearchRequest create() => SearchRequest._();
  static $pb.GeneratedMessage $_createMessage() => SearchRequest._();
  @$core.override
  SearchRequest createEmptyInstance() => SearchRequest._();
  @$core.pragma('dart2js:noInline')
  static SearchRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SearchRequest>(
          SearchRequest.$_createMessage);
  static SearchRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get page => $_getIZ(0);
  @$pb.TagNumber(1)
  set page($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPage() => $_has(0);
  @$pb.TagNumber(1)
  void clearPage() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get query => $_getSZ(1);
  @$pb.TagNumber(2)
  set query($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasQuery() => $_has(1);
  @$pb.TagNumber(2)
  void clearQuery() => $_clearField(2);

  /// Omission requests the Source defaults; a present selection is explicit.
  @$pb.TagNumber(3)
  FilterSelection get filters => $_getN(2);
  @$pb.TagNumber(3)
  set filters(FilterSelection value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFilters() => $_has(2);
  @$pb.TagNumber(3)
  void clearFilters() => $_clearField(3);
  @$pb.TagNumber(3)
  FilterSelection ensureFilters() => $_ensure(2);
}

class MangaRequest extends $pb.GeneratedMessage {
  factory MangaRequest({
    Manga? manga,
  }) {
    final result = MangaRequest._();
    if (manga != null) result.manga = manga;
    return result;
  }

  MangaRequest._();

  factory MangaRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaRequest()..mergeFromBuffer(data, registry);
  factory MangaRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MangaRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: MangaRequest.$_createMessage)
    ..aOM<Manga>(1, _omitFieldNames ? '' : 'manga',
        subBuilder: Manga.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaRequest copyWith(void Function(MangaRequest) updates) =>
      super.copyWith((message) => updates(message as MangaRequest))
          as MangaRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MangaRequest() / MangaRequest.new instead')
  static MangaRequest create() => MangaRequest._();
  static $pb.GeneratedMessage $_createMessage() => MangaRequest._();
  @$core.override
  MangaRequest createEmptyInstance() => MangaRequest._();
  @$core.pragma('dart2js:noInline')
  static MangaRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MangaRequest>(
          MangaRequest.$_createMessage);
  static MangaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  Manga get manga => $_getN(0);
  @$pb.TagNumber(1)
  set manga(Manga value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasManga() => $_has(0);
  @$pb.TagNumber(1)
  void clearManga() => $_clearField(1);
  @$pb.TagNumber(1)
  Manga ensureManga() => $_ensure(0);
}

class ChapterRequest extends $pb.GeneratedMessage {
  factory ChapterRequest({
    Chapter? chapter,
  }) {
    final result = ChapterRequest._();
    if (chapter != null) result.chapter = chapter;
    return result;
  }

  ChapterRequest._();

  factory ChapterRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterRequest()..mergeFromBuffer(data, registry);
  factory ChapterRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChapterRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ChapterRequest.$_createMessage)
    ..aOM<Chapter>(1, _omitFieldNames ? '' : 'chapter',
        subBuilder: Chapter.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterRequest copyWith(void Function(ChapterRequest) updates) =>
      super.copyWith((message) => updates(message as ChapterRequest))
          as ChapterRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ChapterRequest() / ChapterRequest.new instead')
  static ChapterRequest create() => ChapterRequest._();
  static $pb.GeneratedMessage $_createMessage() => ChapterRequest._();
  @$core.override
  ChapterRequest createEmptyInstance() => ChapterRequest._();
  @$core.pragma('dart2js:noInline')
  static ChapterRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChapterRequest>(
          ChapterRequest.$_createMessage);
  static ChapterRequest? _defaultInstance;

  @$pb.TagNumber(1)
  Chapter get chapter => $_getN(0);
  @$pb.TagNumber(1)
  set chapter(Chapter value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasChapter() => $_has(0);
  @$pb.TagNumber(1)
  void clearChapter() => $_clearField(1);
  @$pb.TagNumber(1)
  Chapter ensureChapter() => $_ensure(0);
}

/// Typed Android Source preferences. Storage entries describe the real
/// `source_<id>` SharedPreferences namespace, including listener alias writes.
class PreferenceStringSet extends $pb.GeneratedMessage {
  factory PreferenceStringSet({
    $core.Iterable<$core.String>? values,
  }) {
    final result = PreferenceStringSet._();
    if (values != null) result.values.addAll(values);
    return result;
  }

  PreferenceStringSet._();

  factory PreferenceStringSet.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceStringSet()..mergeFromBuffer(data, registry);
  factory PreferenceStringSet.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceStringSet()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceStringSet',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceStringSet.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'values')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceStringSet clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceStringSet copyWith(void Function(PreferenceStringSet) updates) =>
      super.copyWith((message) => updates(message as PreferenceStringSet))
          as PreferenceStringSet;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use PreferenceStringSet() / PreferenceStringSet.new instead')
  static PreferenceStringSet create() => PreferenceStringSet._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceStringSet._();
  @$core.override
  PreferenceStringSet createEmptyInstance() => PreferenceStringSet._();
  @$core.pragma('dart2js:noInline')
  static PreferenceStringSet getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreferenceStringSet>(
          PreferenceStringSet.$_createMessage);
  static PreferenceStringSet? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get values => $_getList(0);
}

enum PreferenceValue_Value {
  boolean,
  text,
  integer,
  decimal,
  strings,
  longInteger,
  notSet
}

class PreferenceValue extends $pb.GeneratedMessage {
  factory PreferenceValue({
    $core.bool? boolean,
    $core.String? text,
    $core.int? integer,
    $core.double? decimal,
    PreferenceStringSet? strings,
    $fixnum.Int64? longInteger,
  }) {
    final result = PreferenceValue._();
    if (boolean != null) result.boolean = boolean;
    if (text != null) result.text = text;
    if (integer != null) result.integer = integer;
    if (decimal != null) result.decimal = decimal;
    if (strings != null) result.strings = strings;
    if (longInteger != null) result.longInteger = longInteger;
    return result;
  }

  PreferenceValue._();

  factory PreferenceValue.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceValue()..mergeFromBuffer(data, registry);
  factory PreferenceValue.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceValue()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, PreferenceValue_Value>
      _PreferenceValue_ValueByTag = {
    1: PreferenceValue_Value.boolean,
    2: PreferenceValue_Value.text,
    3: PreferenceValue_Value.integer,
    4: PreferenceValue_Value.decimal,
    5: PreferenceValue_Value.strings,
    6: PreferenceValue_Value.longInteger,
    0: PreferenceValue_Value.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceValue',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceValue.$_createMessage)
    ..oo(0, [1, 2, 3, 4, 5, 6])
    ..aOB(1, _omitFieldNames ? '' : 'boolean')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..aI(3, _omitFieldNames ? '' : 'integer', fieldType: $pb.PbFieldType.OS3)
    ..aD(4, _omitFieldNames ? '' : 'decimal', fieldType: $pb.PbFieldType.OF)
    ..aOM<PreferenceStringSet>(5, _omitFieldNames ? '' : 'strings',
        subBuilder: PreferenceStringSet.$_createMessage)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'longInteger', $pb.PbFieldType.OS6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceValue clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceValue copyWith(void Function(PreferenceValue) updates) =>
      super.copyWith((message) => updates(message as PreferenceValue))
          as PreferenceValue;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PreferenceValue() / PreferenceValue.new instead')
  static PreferenceValue create() => PreferenceValue._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceValue._();
  @$core.override
  PreferenceValue createEmptyInstance() => PreferenceValue._();
  @$core.pragma('dart2js:noInline')
  static PreferenceValue getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PreferenceValue>(
          PreferenceValue.$_createMessage);
  static PreferenceValue? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  PreferenceValue_Value whichValue() =>
      _PreferenceValue_ValueByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  void clearValue() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.bool get boolean => $_getBF(0);
  @$pb.TagNumber(1)
  set boolean($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBoolean() => $_has(0);
  @$pb.TagNumber(1)
  void clearBoolean() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get integer => $_getIZ(2);
  @$pb.TagNumber(3)
  set integer($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasInteger() => $_has(2);
  @$pb.TagNumber(3)
  void clearInteger() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get decimal => $_getN(3);
  @$pb.TagNumber(4)
  set decimal($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDecimal() => $_has(3);
  @$pb.TagNumber(4)
  void clearDecimal() => $_clearField(4);

  @$pb.TagNumber(5)
  PreferenceStringSet get strings => $_getN(4);
  @$pb.TagNumber(5)
  set strings(PreferenceStringSet value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasStrings() => $_has(4);
  @$pb.TagNumber(5)
  void clearStrings() => $_clearField(5);
  @$pb.TagNumber(5)
  PreferenceStringSet ensureStrings() => $_ensure(4);

  @$pb.TagNumber(6)
  $fixnum.Int64 get longInteger => $_getI64(5);
  @$pb.TagNumber(6)
  set longInteger($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLongInteger() => $_has(5);
  @$pb.TagNumber(6)
  void clearLongInteger() => $_clearField(6);
}

class PreferenceEntry extends $pb.GeneratedMessage {
  factory PreferenceEntry({
    $core.String? key,
    PreferenceValue? value,
  }) {
    final result = PreferenceEntry._();
    if (key != null) result.key = key;
    if (value != null) result.value = value;
    return result;
  }

  PreferenceEntry._();

  factory PreferenceEntry.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceEntry()..mergeFromBuffer(data, registry);
  factory PreferenceEntry.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceEntry()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceEntry',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceEntry.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOM<PreferenceValue>(2, _omitFieldNames ? '' : 'value',
        subBuilder: PreferenceValue.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceEntry clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceEntry copyWith(void Function(PreferenceEntry) updates) =>
      super.copyWith((message) => updates(message as PreferenceEntry))
          as PreferenceEntry;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PreferenceEntry() / PreferenceEntry.new instead')
  static PreferenceEntry create() => PreferenceEntry._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceEntry._();
  @$core.override
  PreferenceEntry createEmptyInstance() => PreferenceEntry._();
  @$core.pragma('dart2js:noInline')
  static PreferenceEntry getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PreferenceEntry>(
          PreferenceEntry.$_createMessage);
  static PreferenceEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  PreferenceValue get value => $_getN(1);
  @$pb.TagNumber(2)
  set value(PreferenceValue value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);
  @$pb.TagNumber(2)
  PreferenceValue ensureValue() => $_ensure(1);
}

class SourcePreferenceValues extends $pb.GeneratedMessage {
  factory SourcePreferenceValues({
    $core.String? sourceId,
    $core.Iterable<PreferenceEntry>? entries,
  }) {
    final result = SourcePreferenceValues._();
    if (sourceId != null) result.sourceId = sourceId;
    if (entries != null) result.entries.addAll(entries);
    return result;
  }

  SourcePreferenceValues._();

  factory SourcePreferenceValues.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourcePreferenceValues()..mergeFromBuffer(data, registry);
  factory SourcePreferenceValues.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourcePreferenceValues()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SourcePreferenceValues',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SourcePreferenceValues.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sourceId')
    ..pPM<PreferenceEntry>(2, _omitFieldNames ? '' : 'entries',
        subBuilder: PreferenceEntry.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourcePreferenceValues clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourcePreferenceValues copyWith(
          void Function(SourcePreferenceValues) updates) =>
      super.copyWith((message) => updates(message as SourcePreferenceValues))
          as SourcePreferenceValues;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SourcePreferenceValues() / SourcePreferenceValues.new instead')
  static SourcePreferenceValues create() => SourcePreferenceValues._();
  static $pb.GeneratedMessage $_createMessage() => SourcePreferenceValues._();
  @$core.override
  SourcePreferenceValues createEmptyInstance() => SourcePreferenceValues._();
  @$core.pragma('dart2js:noInline')
  static SourcePreferenceValues getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SourcePreferenceValues>(
          SourcePreferenceValues.$_createMessage);
  static SourcePreferenceValues? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sourceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set sourceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSourceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSourceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<PreferenceEntry> get entries => $_getList(1);
}

class PreferenceBootstrap extends $pb.GeneratedMessage {
  factory PreferenceBootstrap({
    $core.String? packageName,
    $core.Iterable<SourcePreferenceValues>? sources,
  }) {
    final result = PreferenceBootstrap._();
    if (packageName != null) result.packageName = packageName;
    if (sources != null) result.sources.addAll(sources);
    return result;
  }

  PreferenceBootstrap._();

  factory PreferenceBootstrap.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceBootstrap()..mergeFromBuffer(data, registry);
  factory PreferenceBootstrap.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceBootstrap()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceBootstrap',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceBootstrap.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'packageName')
    ..pPM<SourcePreferenceValues>(2, _omitFieldNames ? '' : 'sources',
        subBuilder: SourcePreferenceValues.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceBootstrap clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceBootstrap copyWith(void Function(PreferenceBootstrap) updates) =>
      super.copyWith((message) => updates(message as PreferenceBootstrap))
          as PreferenceBootstrap;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use PreferenceBootstrap() / PreferenceBootstrap.new instead')
  static PreferenceBootstrap create() => PreferenceBootstrap._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceBootstrap._();
  @$core.override
  PreferenceBootstrap createEmptyInstance() => PreferenceBootstrap._();
  @$core.pragma('dart2js:noInline')
  static PreferenceBootstrap getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreferenceBootstrap>(
          PreferenceBootstrap.$_createMessage);
  static PreferenceBootstrap? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get packageName => $_getSZ(0);
  @$pb.TagNumber(1)
  set packageName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPackageName() => $_has(0);
  @$pb.TagNumber(1)
  void clearPackageName() => $_clearField(1);

  /// Only namespaces with values need an entry. Missing keys use Source defaults.
  @$pb.TagNumber(2)
  $pb.PbList<SourcePreferenceValues> get sources => $_getList(1);
}

class PreferenceSyncRule extends $pb.GeneratedMessage {
  factory PreferenceSyncRule({
    $core.String? key,
    PreferenceValueKind? kind,
    $core.String? sourceId,
  }) {
    final result = PreferenceSyncRule._();
    if (key != null) result.key = key;
    if (kind != null) result.kind = kind;
    if (sourceId != null) result.sourceId = sourceId;
    return result;
  }

  PreferenceSyncRule._();

  factory PreferenceSyncRule.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceSyncRule()..mergeFromBuffer(data, registry);
  factory PreferenceSyncRule.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceSyncRule()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceSyncRule',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceSyncRule.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aE<PreferenceValueKind>(2, _omitFieldNames ? '' : 'kind',
        enumValues: PreferenceValueKind.values)
    ..aOS(3, _omitFieldNames ? '' : 'sourceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceSyncRule clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceSyncRule copyWith(void Function(PreferenceSyncRule) updates) =>
      super.copyWith((message) => updates(message as PreferenceSyncRule))
          as PreferenceSyncRule;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PreferenceSyncRule() / PreferenceSyncRule.new instead')
  static PreferenceSyncRule create() => PreferenceSyncRule._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceSyncRule._();
  @$core.override
  PreferenceSyncRule createEmptyInstance() => PreferenceSyncRule._();
  @$core.pragma('dart2js:noInline')
  static PreferenceSyncRule getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreferenceSyncRule>(
          PreferenceSyncRule.$_createMessage);
  static PreferenceSyncRule? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  PreferenceValueKind get kind => $_getN(1);
  @$pb.TagNumber(2)
  set kind(PreferenceValueKind value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasKind() => $_has(1);
  @$pb.TagNumber(2)
  void clearKind() => $_clearField(2);

  /// Missing means the approved key has the same meaning throughout this package.
  @$pb.TagNumber(3)
  $core.String get sourceId => $_getSZ(2);
  @$pb.TagNumber(3)
  set sourceId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSourceId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSourceId() => $_clearField(3);
}

/// Constructed by the host from the package's owned policy, never from a Source
/// claiming that arbitrary keys are safe to send to the business API.
class PreferenceHostConfiguration extends $pb.GeneratedMessage {
  factory PreferenceHostConfiguration({
    PreferenceBootstrap? bootstrap,
    $core.Iterable<PreferenceSyncRule>? syncRules,
  }) {
    final result = PreferenceHostConfiguration._();
    if (bootstrap != null) result.bootstrap = bootstrap;
    if (syncRules != null) result.syncRules.addAll(syncRules);
    return result;
  }

  PreferenceHostConfiguration._();

  factory PreferenceHostConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceHostConfiguration()..mergeFromBuffer(data, registry);
  factory PreferenceHostConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceHostConfiguration()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceHostConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceHostConfiguration.$_createMessage)
    ..aOM<PreferenceBootstrap>(1, _omitFieldNames ? '' : 'bootstrap',
        subBuilder: PreferenceBootstrap.$_createMessage)
    ..pPM<PreferenceSyncRule>(2, _omitFieldNames ? '' : 'syncRules',
        subBuilder: PreferenceSyncRule.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceHostConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceHostConfiguration copyWith(
          void Function(PreferenceHostConfiguration) updates) =>
      super.copyWith(
              (message) => updates(message as PreferenceHostConfiguration))
          as PreferenceHostConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PreferenceHostConfiguration() / PreferenceHostConfiguration.new instead')
  static PreferenceHostConfiguration create() =>
      PreferenceHostConfiguration._();
  static $pb.GeneratedMessage $_createMessage() =>
      PreferenceHostConfiguration._();
  @$core.override
  PreferenceHostConfiguration createEmptyInstance() =>
      PreferenceHostConfiguration._();
  @$core.pragma('dart2js:noInline')
  static PreferenceHostConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreferenceHostConfiguration>(
          PreferenceHostConfiguration.$_createMessage);
  static PreferenceHostConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  PreferenceBootstrap get bootstrap => $_getN(0);
  @$pb.TagNumber(1)
  set bootstrap(PreferenceBootstrap value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasBootstrap() => $_has(0);
  @$pb.TagNumber(1)
  void clearBootstrap() => $_clearField(1);
  @$pb.TagNumber(1)
  PreferenceBootstrap ensureBootstrap() => $_ensure(0);

  @$pb.TagNumber(2)
  $pb.PbList<PreferenceSyncRule> get syncRules => $_getList(1);
}

class PreferenceOption extends $pb.GeneratedMessage {
  factory PreferenceOption({
    $core.String? label,
    $core.String? value,
  }) {
    final result = PreferenceOption._();
    if (label != null) result.label = label;
    if (value != null) result.value = value;
    return result;
  }

  PreferenceOption._();

  factory PreferenceOption.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceOption()..mergeFromBuffer(data, registry);
  factory PreferenceOption.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceOption()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceOption',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceOption.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'label')
    ..aOS(2, _omitFieldNames ? '' : 'value')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceOption clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceOption copyWith(void Function(PreferenceOption) updates) =>
      super.copyWith((message) => updates(message as PreferenceOption))
          as PreferenceOption;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PreferenceOption() / PreferenceOption.new instead')
  static PreferenceOption create() => PreferenceOption._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceOption._();
  @$core.override
  PreferenceOption createEmptyInstance() => PreferenceOption._();
  @$core.pragma('dart2js:noInline')
  static PreferenceOption getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PreferenceOption>(
          PreferenceOption.$_createMessage);
  static PreferenceOption? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get label => $_getSZ(0);
  @$pb.TagNumber(1)
  set label($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLabel() => $_has(0);
  @$pb.TagNumber(1)
  void clearLabel() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get value => $_getSZ(1);
  @$pb.TagNumber(2)
  set value($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);
}

class PreferenceToggle extends $pb.GeneratedMessage {
  factory PreferenceToggle({
    $core.bool? value,
  }) {
    final result = PreferenceToggle._();
    if (value != null) result.value = value;
    return result;
  }

  PreferenceToggle._();

  factory PreferenceToggle.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceToggle()..mergeFromBuffer(data, registry);
  factory PreferenceToggle.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceToggle()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceToggle',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceToggle.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'value')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceToggle clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceToggle copyWith(void Function(PreferenceToggle) updates) =>
      super.copyWith((message) => updates(message as PreferenceToggle))
          as PreferenceToggle;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PreferenceToggle() / PreferenceToggle.new instead')
  static PreferenceToggle create() => PreferenceToggle._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceToggle._();
  @$core.override
  PreferenceToggle createEmptyInstance() => PreferenceToggle._();
  @$core.pragma('dart2js:noInline')
  static PreferenceToggle getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PreferenceToggle>(
          PreferenceToggle.$_createMessage);
  static PreferenceToggle? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get value => $_getBF(0);
  @$pb.TagNumber(1)
  set value($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearValue() => $_clearField(1);
}

class PreferenceText extends $pb.GeneratedMessage {
  factory PreferenceText({
    $core.String? value,
    $core.bool? secret,
    $core.int? inputType,
  }) {
    final result = PreferenceText._();
    if (value != null) result.value = value;
    if (secret != null) result.secret = secret;
    if (inputType != null) result.inputType = inputType;
    return result;
  }

  PreferenceText._();

  factory PreferenceText.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceText()..mergeFromBuffer(data, registry);
  factory PreferenceText.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceText()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceText',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceText.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'value')
    ..aOB(2, _omitFieldNames ? '' : 'secret')
    ..aI(3, _omitFieldNames ? '' : 'inputType')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceText clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceText copyWith(void Function(PreferenceText) updates) =>
      super.copyWith((message) => updates(message as PreferenceText))
          as PreferenceText;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PreferenceText() / PreferenceText.new instead')
  static PreferenceText create() => PreferenceText._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceText._();
  @$core.override
  PreferenceText createEmptyInstance() => PreferenceText._();
  @$core.pragma('dart2js:noInline')
  static PreferenceText getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PreferenceText>(
          PreferenceText.$_createMessage);
  static PreferenceText? _defaultInstance;

  /// Missing is distinct from an explicitly stored empty string.
  @$pb.TagNumber(1)
  $core.String get value => $_getSZ(0);
  @$pb.TagNumber(1)
  set value($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasValue() => $_has(0);
  @$pb.TagNumber(1)
  void clearValue() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get secret => $_getBF(1);
  @$pb.TagNumber(2)
  set secret($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSecret() => $_has(1);
  @$pb.TagNumber(2)
  void clearSecret() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get inputType => $_getIZ(2);
  @$pb.TagNumber(3)
  set inputType($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasInputType() => $_has(2);
  @$pb.TagNumber(3)
  void clearInputType() => $_clearField(3);
}

class PreferenceChoice extends $pb.GeneratedMessage {
  factory PreferenceChoice({
    $core.Iterable<PreferenceOption>? options,
    $core.String? value,
  }) {
    final result = PreferenceChoice._();
    if (options != null) result.options.addAll(options);
    if (value != null) result.value = value;
    return result;
  }

  PreferenceChoice._();

  factory PreferenceChoice.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceChoice()..mergeFromBuffer(data, registry);
  factory PreferenceChoice.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceChoice()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceChoice',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceChoice.$_createMessage)
    ..pPM<PreferenceOption>(1, _omitFieldNames ? '' : 'options',
        subBuilder: PreferenceOption.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'value')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceChoice clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceChoice copyWith(void Function(PreferenceChoice) updates) =>
      super.copyWith((message) => updates(message as PreferenceChoice))
          as PreferenceChoice;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PreferenceChoice() / PreferenceChoice.new instead')
  static PreferenceChoice create() => PreferenceChoice._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceChoice._();
  @$core.override
  PreferenceChoice createEmptyInstance() => PreferenceChoice._();
  @$core.pragma('dart2js:noInline')
  static PreferenceChoice getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PreferenceChoice>(
          PreferenceChoice.$_createMessage);
  static PreferenceChoice? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PreferenceOption> get options => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get value => $_getSZ(1);
  @$pb.TagNumber(2)
  set value($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasValue() => $_has(1);
  @$pb.TagNumber(2)
  void clearValue() => $_clearField(2);
}

class PreferenceMultiChoice extends $pb.GeneratedMessage {
  factory PreferenceMultiChoice({
    $core.Iterable<PreferenceOption>? options,
    $core.Iterable<$core.String>? values,
  }) {
    final result = PreferenceMultiChoice._();
    if (options != null) result.options.addAll(options);
    if (values != null) result.values.addAll(values);
    return result;
  }

  PreferenceMultiChoice._();

  factory PreferenceMultiChoice.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceMultiChoice()..mergeFromBuffer(data, registry);
  factory PreferenceMultiChoice.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceMultiChoice()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceMultiChoice',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceMultiChoice.$_createMessage)
    ..pPM<PreferenceOption>(1, _omitFieldNames ? '' : 'options',
        subBuilder: PreferenceOption.$_createMessage)
    ..pPS(2, _omitFieldNames ? '' : 'values')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceMultiChoice clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceMultiChoice copyWith(
          void Function(PreferenceMultiChoice) updates) =>
      super.copyWith((message) => updates(message as PreferenceMultiChoice))
          as PreferenceMultiChoice;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PreferenceMultiChoice() / PreferenceMultiChoice.new instead')
  static PreferenceMultiChoice create() => PreferenceMultiChoice._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceMultiChoice._();
  @$core.override
  PreferenceMultiChoice createEmptyInstance() => PreferenceMultiChoice._();
  @$core.pragma('dart2js:noInline')
  static PreferenceMultiChoice getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreferenceMultiChoice>(
          PreferenceMultiChoice.$_createMessage);
  static PreferenceMultiChoice? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PreferenceOption> get options => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<$core.String> get values => $_getList(1);
}

class PreferenceGroup extends $pb.GeneratedMessage {
  factory PreferenceGroup({
    $core.Iterable<PreferenceNode>? nodes,
  }) {
    final result = PreferenceGroup._();
    if (nodes != null) result.nodes.addAll(nodes);
    return result;
  }

  PreferenceGroup._();

  factory PreferenceGroup.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceGroup()..mergeFromBuffer(data, registry);
  factory PreferenceGroup.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceGroup()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceGroup',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceGroup.$_createMessage)
    ..pPM<PreferenceNode>(1, _omitFieldNames ? '' : 'nodes',
        subBuilder: PreferenceNode.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceGroup clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceGroup copyWith(void Function(PreferenceGroup) updates) =>
      super.copyWith((message) => updates(message as PreferenceGroup))
          as PreferenceGroup;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PreferenceGroup() / PreferenceGroup.new instead')
  static PreferenceGroup create() => PreferenceGroup._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceGroup._();
  @$core.override
  PreferenceGroup createEmptyInstance() => PreferenceGroup._();
  @$core.pragma('dart2js:noInline')
  static PreferenceGroup getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PreferenceGroup>(
          PreferenceGroup.$_createMessage);
  static PreferenceGroup? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PreferenceNode> get nodes => $_getList(0);
}

class PreferenceUnsupported extends $pb.GeneratedMessage {
  factory PreferenceUnsupported({
    $core.String? reason,
  }) {
    final result = PreferenceUnsupported._();
    if (reason != null) result.reason = reason;
    return result;
  }

  PreferenceUnsupported._();

  factory PreferenceUnsupported.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceUnsupported()..mergeFromBuffer(data, registry);
  factory PreferenceUnsupported.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceUnsupported()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceUnsupported',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceUnsupported.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'reason')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceUnsupported clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceUnsupported copyWith(
          void Function(PreferenceUnsupported) updates) =>
      super.copyWith((message) => updates(message as PreferenceUnsupported))
          as PreferenceUnsupported;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PreferenceUnsupported() / PreferenceUnsupported.new instead')
  static PreferenceUnsupported create() => PreferenceUnsupported._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceUnsupported._();
  @$core.override
  PreferenceUnsupported createEmptyInstance() => PreferenceUnsupported._();
  @$core.pragma('dart2js:noInline')
  static PreferenceUnsupported getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreferenceUnsupported>(
          PreferenceUnsupported.$_createMessage);
  static PreferenceUnsupported? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get reason => $_getSZ(0);
  @$pb.TagNumber(1)
  set reason($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReason() => $_has(0);
  @$pb.TagNumber(1)
  void clearReason() => $_clearField(1);
}

enum PreferenceNode_Kind {
  toggle,
  text,
  choice,
  multiChoice,
  group,
  action,
  unsupported,
  notSet
}

class PreferenceNode extends $pb.GeneratedMessage {
  factory PreferenceNode({
    $core.String? key,
    $core.String? title,
    $core.String? summary,
    $core.bool? enabled,
    $core.bool? visible,
    PreferenceSyncScope? syncScope,
    PreferenceValue? defaultValue,
    PreferenceToggle? toggle,
    PreferenceText? text,
    PreferenceChoice? choice,
    PreferenceMultiChoice? multiChoice,
    PreferenceGroup? group,
    Empty? action,
    PreferenceUnsupported? unsupported,
  }) {
    final result = PreferenceNode._();
    if (key != null) result.key = key;
    if (title != null) result.title = title;
    if (summary != null) result.summary = summary;
    if (enabled != null) result.enabled = enabled;
    if (visible != null) result.visible = visible;
    if (syncScope != null) result.syncScope = syncScope;
    if (defaultValue != null) result.defaultValue = defaultValue;
    if (toggle != null) result.toggle = toggle;
    if (text != null) result.text = text;
    if (choice != null) result.choice = choice;
    if (multiChoice != null) result.multiChoice = multiChoice;
    if (group != null) result.group = group;
    if (action != null) result.action = action;
    if (unsupported != null) result.unsupported = unsupported;
    return result;
  }

  PreferenceNode._();

  factory PreferenceNode.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceNode()..mergeFromBuffer(data, registry);
  factory PreferenceNode.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceNode()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, PreferenceNode_Kind>
      _PreferenceNode_KindByTag = {
    10: PreferenceNode_Kind.toggle,
    11: PreferenceNode_Kind.text,
    12: PreferenceNode_Kind.choice,
    13: PreferenceNode_Kind.multiChoice,
    14: PreferenceNode_Kind.group,
    15: PreferenceNode_Kind.action,
    16: PreferenceNode_Kind.unsupported,
    0: PreferenceNode_Kind.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceNode',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceNode.$_createMessage)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16])
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..aOS(3, _omitFieldNames ? '' : 'summary')
    ..aOB(4, _omitFieldNames ? '' : 'enabled')
    ..aOB(5, _omitFieldNames ? '' : 'visible')
    ..aE<PreferenceSyncScope>(6, _omitFieldNames ? '' : 'syncScope',
        enumValues: PreferenceSyncScope.values)
    ..aOM<PreferenceValue>(7, _omitFieldNames ? '' : 'defaultValue',
        subBuilder: PreferenceValue.$_createMessage)
    ..aOM<PreferenceToggle>(10, _omitFieldNames ? '' : 'toggle',
        subBuilder: PreferenceToggle.$_createMessage)
    ..aOM<PreferenceText>(11, _omitFieldNames ? '' : 'text',
        subBuilder: PreferenceText.$_createMessage)
    ..aOM<PreferenceChoice>(12, _omitFieldNames ? '' : 'choice',
        subBuilder: PreferenceChoice.$_createMessage)
    ..aOM<PreferenceMultiChoice>(13, _omitFieldNames ? '' : 'multiChoice',
        subBuilder: PreferenceMultiChoice.$_createMessage)
    ..aOM<PreferenceGroup>(14, _omitFieldNames ? '' : 'group',
        subBuilder: PreferenceGroup.$_createMessage)
    ..aOM<Empty>(15, _omitFieldNames ? '' : 'action',
        subBuilder: Empty.$_createMessage)
    ..aOM<PreferenceUnsupported>(16, _omitFieldNames ? '' : 'unsupported',
        subBuilder: PreferenceUnsupported.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceNode clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceNode copyWith(void Function(PreferenceNode) updates) =>
      super.copyWith((message) => updates(message as PreferenceNode))
          as PreferenceNode;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PreferenceNode() / PreferenceNode.new instead')
  static PreferenceNode create() => PreferenceNode._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceNode._();
  @$core.override
  PreferenceNode createEmptyInstance() => PreferenceNode._();
  @$core.pragma('dart2js:noInline')
  static PreferenceNode getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PreferenceNode>(
          PreferenceNode.$_createMessage);
  static PreferenceNode? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  PreferenceNode_Kind whichKind() =>
      _PreferenceNode_KindByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  void clearKind() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTitle() => $_has(1);
  @$pb.TagNumber(2)
  void clearTitle() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get summary => $_getSZ(2);
  @$pb.TagNumber(3)
  set summary($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSummary() => $_has(2);
  @$pb.TagNumber(3)
  void clearSummary() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get enabled => $_getBF(3);
  @$pb.TagNumber(4)
  set enabled($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEnabled() => $_has(3);
  @$pb.TagNumber(4)
  void clearEnabled() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get visible => $_getBF(4);
  @$pb.TagNumber(5)
  set visible($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasVisible() => $_has(4);
  @$pb.TagNumber(5)
  void clearVisible() => $_clearField(5);

  @$pb.TagNumber(6)
  PreferenceSyncScope get syncScope => $_getN(5);
  @$pb.TagNumber(6)
  set syncScope(PreferenceSyncScope value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasSyncScope() => $_has(5);
  @$pb.TagNumber(6)
  void clearSyncScope() => $_clearField(6);

  @$pb.TagNumber(7)
  PreferenceValue get defaultValue => $_getN(6);
  @$pb.TagNumber(7)
  set defaultValue(PreferenceValue value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasDefaultValue() => $_has(6);
  @$pb.TagNumber(7)
  void clearDefaultValue() => $_clearField(7);
  @$pb.TagNumber(7)
  PreferenceValue ensureDefaultValue() => $_ensure(6);

  @$pb.TagNumber(10)
  PreferenceToggle get toggle => $_getN(7);
  @$pb.TagNumber(10)
  set toggle(PreferenceToggle value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasToggle() => $_has(7);
  @$pb.TagNumber(10)
  void clearToggle() => $_clearField(10);
  @$pb.TagNumber(10)
  PreferenceToggle ensureToggle() => $_ensure(7);

  @$pb.TagNumber(11)
  PreferenceText get text => $_getN(8);
  @$pb.TagNumber(11)
  set text(PreferenceText value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasText() => $_has(8);
  @$pb.TagNumber(11)
  void clearText() => $_clearField(11);
  @$pb.TagNumber(11)
  PreferenceText ensureText() => $_ensure(8);

  @$pb.TagNumber(12)
  PreferenceChoice get choice => $_getN(9);
  @$pb.TagNumber(12)
  set choice(PreferenceChoice value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasChoice() => $_has(9);
  @$pb.TagNumber(12)
  void clearChoice() => $_clearField(12);
  @$pb.TagNumber(12)
  PreferenceChoice ensureChoice() => $_ensure(9);

  @$pb.TagNumber(13)
  PreferenceMultiChoice get multiChoice => $_getN(10);
  @$pb.TagNumber(13)
  set multiChoice(PreferenceMultiChoice value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasMultiChoice() => $_has(10);
  @$pb.TagNumber(13)
  void clearMultiChoice() => $_clearField(13);
  @$pb.TagNumber(13)
  PreferenceMultiChoice ensureMultiChoice() => $_ensure(10);

  @$pb.TagNumber(14)
  PreferenceGroup get group => $_getN(11);
  @$pb.TagNumber(14)
  set group(PreferenceGroup value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasGroup() => $_has(11);
  @$pb.TagNumber(14)
  void clearGroup() => $_clearField(14);
  @$pb.TagNumber(14)
  PreferenceGroup ensureGroup() => $_ensure(11);

  @$pb.TagNumber(15)
  Empty get action => $_getN(12);
  @$pb.TagNumber(15)
  set action(Empty value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasAction() => $_has(12);
  @$pb.TagNumber(15)
  void clearAction() => $_clearField(15);
  @$pb.TagNumber(15)
  Empty ensureAction() => $_ensure(12);

  @$pb.TagNumber(16)
  PreferenceUnsupported get unsupported => $_getN(13);
  @$pb.TagNumber(16)
  set unsupported(PreferenceUnsupported value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasUnsupported() => $_has(13);
  @$pb.TagNumber(16)
  void clearUnsupported() => $_clearField(16);
  @$pb.TagNumber(16)
  PreferenceUnsupported ensureUnsupported() => $_ensure(13);
}

class PreferenceSnapshot extends $pb.GeneratedMessage {
  factory PreferenceSnapshot({
    $core.String? snapshotId,
    $core.Iterable<PreferenceNode>? nodes,
    $core.Iterable<PreferenceEntry>? syncValues,
    $core.Iterable<PreferenceEntry>? sessionValues,
  }) {
    final result = PreferenceSnapshot._();
    if (snapshotId != null) result.snapshotId = snapshotId;
    if (nodes != null) result.nodes.addAll(nodes);
    if (syncValues != null) result.syncValues.addAll(syncValues);
    if (sessionValues != null) result.sessionValues.addAll(sessionValues);
    return result;
  }

  PreferenceSnapshot._();

  factory PreferenceSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceSnapshot()..mergeFromBuffer(data, registry);
  factory PreferenceSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceSnapshot()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceSnapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceSnapshot.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'snapshotId')
    ..pPM<PreferenceNode>(2, _omitFieldNames ? '' : 'nodes',
        subBuilder: PreferenceNode.$_createMessage)
    ..pPM<PreferenceEntry>(3, _omitFieldNames ? '' : 'syncValues',
        subBuilder: PreferenceEntry.$_createMessage)
    ..pPM<PreferenceEntry>(4, _omitFieldNames ? '' : 'sessionValues',
        subBuilder: PreferenceEntry.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceSnapshot copyWith(void Function(PreferenceSnapshot) updates) =>
      super.copyWith((message) => updates(message as PreferenceSnapshot))
          as PreferenceSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PreferenceSnapshot() / PreferenceSnapshot.new instead')
  static PreferenceSnapshot create() => PreferenceSnapshot._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceSnapshot._();
  @$core.override
  PreferenceSnapshot createEmptyInstance() => PreferenceSnapshot._();
  @$core.pragma('dart2js:noInline')
  static PreferenceSnapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreferenceSnapshot>(
          PreferenceSnapshot.$_createMessage);
  static PreferenceSnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get snapshotId => $_getSZ(0);
  @$pb.TagNumber(1)
  set snapshotId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSnapshotId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSnapshotId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<PreferenceNode> get nodes => $_getList(1);

  /// Full actual stored values in each partition; never upload session_values.
  @$pb.TagNumber(3)
  $pb.PbList<PreferenceEntry> get syncValues => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<PreferenceEntry> get sessionValues => $_getList(3);
}

enum PreferenceEditRequest_Command { change, click, notSet }

class PreferenceEditRequest extends $pb.GeneratedMessage {
  factory PreferenceEditRequest({
    $core.String? snapshotId,
    $core.Iterable<$core.int>? path,
    PreferenceValue? change,
    Empty? click,
  }) {
    final result = PreferenceEditRequest._();
    if (snapshotId != null) result.snapshotId = snapshotId;
    if (path != null) result.path.addAll(path);
    if (change != null) result.change = change;
    if (click != null) result.click = click;
    return result;
  }

  PreferenceEditRequest._();

  factory PreferenceEditRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceEditRequest()..mergeFromBuffer(data, registry);
  factory PreferenceEditRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceEditRequest()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, PreferenceEditRequest_Command>
      _PreferenceEditRequest_CommandByTag = {
    3: PreferenceEditRequest_Command.change,
    4: PreferenceEditRequest_Command.click,
    0: PreferenceEditRequest_Command.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceEditRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceEditRequest.$_createMessage)
    ..oo(0, [3, 4])
    ..aOS(1, _omitFieldNames ? '' : 'snapshotId')
    ..p<$core.int>(2, _omitFieldNames ? '' : 'path', $pb.PbFieldType.KU3)
    ..aOM<PreferenceValue>(3, _omitFieldNames ? '' : 'change',
        subBuilder: PreferenceValue.$_createMessage)
    ..aOM<Empty>(4, _omitFieldNames ? '' : 'click',
        subBuilder: Empty.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceEditRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceEditRequest copyWith(
          void Function(PreferenceEditRequest) updates) =>
      super.copyWith((message) => updates(message as PreferenceEditRequest))
          as PreferenceEditRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PreferenceEditRequest() / PreferenceEditRequest.new instead')
  static PreferenceEditRequest create() => PreferenceEditRequest._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceEditRequest._();
  @$core.override
  PreferenceEditRequest createEmptyInstance() => PreferenceEditRequest._();
  @$core.pragma('dart2js:noInline')
  static PreferenceEditRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreferenceEditRequest>(
          PreferenceEditRequest.$_createMessage);
  static PreferenceEditRequest? _defaultInstance;

  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  PreferenceEditRequest_Command whichCommand() =>
      _PreferenceEditRequest_CommandByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  void clearCommand() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get snapshotId => $_getSZ(0);
  @$pb.TagNumber(1)
  set snapshotId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSnapshotId() => $_has(0);
  @$pb.TagNumber(1)
  void clearSnapshotId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<$core.int> get path => $_getList(1);

  @$pb.TagNumber(3)
  PreferenceValue get change => $_getN(2);
  @$pb.TagNumber(3)
  set change(PreferenceValue value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasChange() => $_has(2);
  @$pb.TagNumber(3)
  void clearChange() => $_clearField(3);
  @$pb.TagNumber(3)
  PreferenceValue ensureChange() => $_ensure(2);

  @$pb.TagNumber(4)
  Empty get click => $_getN(3);
  @$pb.TagNumber(4)
  set click(Empty value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasClick() => $_has(3);
  @$pb.TagNumber(4)
  void clearClick() => $_clearField(4);
  @$pb.TagNumber(4)
  Empty ensureClick() => $_ensure(3);
}

class PreferenceEditResult extends $pb.GeneratedMessage {
  factory PreferenceEditResult({
    $core.bool? accepted,
    $core.bool? clickHandled,
    PreferenceSnapshot? snapshot,
  }) {
    final result = PreferenceEditResult._();
    if (accepted != null) result.accepted = accepted;
    if (clickHandled != null) result.clickHandled = clickHandled;
    if (snapshot != null) result.snapshot = snapshot;
    return result;
  }

  PreferenceEditResult._();

  factory PreferenceEditResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceEditResult()..mergeFromBuffer(data, registry);
  factory PreferenceEditResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreferenceEditResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreferenceEditResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreferenceEditResult.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOB(2, _omitFieldNames ? '' : 'clickHandled')
    ..aOM<PreferenceSnapshot>(3, _omitFieldNames ? '' : 'snapshot',
        subBuilder: PreferenceSnapshot.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceEditResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreferenceEditResult copyWith(void Function(PreferenceEditResult) updates) =>
      super.copyWith((message) => updates(message as PreferenceEditResult))
          as PreferenceEditResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use PreferenceEditResult() / PreferenceEditResult.new instead')
  static PreferenceEditResult create() => PreferenceEditResult._();
  static $pb.GeneratedMessage $_createMessage() => PreferenceEditResult._();
  @$core.override
  PreferenceEditResult createEmptyInstance() => PreferenceEditResult._();
  @$core.pragma('dart2js:noInline')
  static PreferenceEditResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PreferenceEditResult>(
          PreferenceEditResult.$_createMessage);
  static PreferenceEditResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get clickHandled => $_getBF(1);
  @$pb.TagNumber(2)
  set clickHandled($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasClickHandled() => $_has(1);
  @$pb.TagNumber(2)
  void clearClickHandled() => $_clearField(2);

  @$pb.TagNumber(3)
  PreferenceSnapshot get snapshot => $_getN(2);
  @$pb.TagNumber(3)
  set snapshot(PreferenceSnapshot value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasSnapshot() => $_has(2);
  @$pb.TagNumber(3)
  void clearSnapshot() => $_clearField(3);
  @$pb.TagNumber(3)
  PreferenceSnapshot ensureSnapshot() => $_ensure(2);
}

enum SourceCall_Request {
  popular,
  latest,
  search,
  details,
  chapters,
  pages,
  getFilters,
  getPreferences,
  editPreference,
  notSet
}

class SourceCall extends $pb.GeneratedMessage {
  factory SourceCall({
    $core.String? requestId,
    $core.String? sourceId,
    $core.int? timeoutMs,
    $core.String? generation,
    PageRequest? popular,
    PageRequest? latest,
    SearchRequest? search,
    MangaRequest? details,
    MangaRequest? chapters,
    ChapterRequest? pages,
    GetFiltersRequest? getFilters,
    Empty? getPreferences,
    PreferenceEditRequest? editPreference,
  }) {
    final result = SourceCall._();
    if (requestId != null) result.requestId = requestId;
    if (sourceId != null) result.sourceId = sourceId;
    if (timeoutMs != null) result.timeoutMs = timeoutMs;
    if (generation != null) result.generation = generation;
    if (popular != null) result.popular = popular;
    if (latest != null) result.latest = latest;
    if (search != null) result.search = search;
    if (details != null) result.details = details;
    if (chapters != null) result.chapters = chapters;
    if (pages != null) result.pages = pages;
    if (getFilters != null) result.getFilters = getFilters;
    if (getPreferences != null) result.getPreferences = getPreferences;
    if (editPreference != null) result.editPreference = editPreference;
    return result;
  }

  SourceCall._();

  factory SourceCall.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourceCall()..mergeFromBuffer(data, registry);
  factory SourceCall.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourceCall()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, SourceCall_Request>
      _SourceCall_RequestByTag = {
    10: SourceCall_Request.popular,
    11: SourceCall_Request.latest,
    12: SourceCall_Request.search,
    13: SourceCall_Request.details,
    14: SourceCall_Request.chapters,
    15: SourceCall_Request.pages,
    16: SourceCall_Request.getFilters,
    17: SourceCall_Request.getPreferences,
    18: SourceCall_Request.editPreference,
    0: SourceCall_Request.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SourceCall',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SourceCall.$_createMessage)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17, 18])
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'sourceId')
    ..aI(3, _omitFieldNames ? '' : 'timeoutMs', fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'generation')
    ..aOM<PageRequest>(10, _omitFieldNames ? '' : 'popular',
        subBuilder: PageRequest.$_createMessage)
    ..aOM<PageRequest>(11, _omitFieldNames ? '' : 'latest',
        subBuilder: PageRequest.$_createMessage)
    ..aOM<SearchRequest>(12, _omitFieldNames ? '' : 'search',
        subBuilder: SearchRequest.$_createMessage)
    ..aOM<MangaRequest>(13, _omitFieldNames ? '' : 'details',
        subBuilder: MangaRequest.$_createMessage)
    ..aOM<MangaRequest>(14, _omitFieldNames ? '' : 'chapters',
        subBuilder: MangaRequest.$_createMessage)
    ..aOM<ChapterRequest>(15, _omitFieldNames ? '' : 'pages',
        subBuilder: ChapterRequest.$_createMessage)
    ..aOM<GetFiltersRequest>(16, _omitFieldNames ? '' : 'getFilters',
        subBuilder: GetFiltersRequest.$_createMessage)
    ..aOM<Empty>(17, _omitFieldNames ? '' : 'getPreferences',
        subBuilder: Empty.$_createMessage)
    ..aOM<PreferenceEditRequest>(18, _omitFieldNames ? '' : 'editPreference',
        subBuilder: PreferenceEditRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourceCall clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourceCall copyWith(void Function(SourceCall) updates) =>
      super.copyWith((message) => updates(message as SourceCall)) as SourceCall;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SourceCall() / SourceCall.new instead')
  static SourceCall create() => SourceCall._();
  static $pb.GeneratedMessage $_createMessage() => SourceCall._();
  @$core.override
  SourceCall createEmptyInstance() => SourceCall._();
  @$core.pragma('dart2js:noInline')
  static SourceCall getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SourceCall>(SourceCall.$_createMessage);
  static SourceCall? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  SourceCall_Request whichRequest() =>
      _SourceCall_RequestByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  void clearRequest() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sourceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSourceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get timeoutMs => $_getIZ(2);
  @$pb.TagNumber(3)
  set timeoutMs($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTimeoutMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimeoutMs() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get generation => $_getSZ(3);
  @$pb.TagNumber(4)
  set generation($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasGeneration() => $_has(3);
  @$pb.TagNumber(4)
  void clearGeneration() => $_clearField(4);

  @$pb.TagNumber(10)
  PageRequest get popular => $_getN(4);
  @$pb.TagNumber(10)
  set popular(PageRequest value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasPopular() => $_has(4);
  @$pb.TagNumber(10)
  void clearPopular() => $_clearField(10);
  @$pb.TagNumber(10)
  PageRequest ensurePopular() => $_ensure(4);

  @$pb.TagNumber(11)
  PageRequest get latest => $_getN(5);
  @$pb.TagNumber(11)
  set latest(PageRequest value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasLatest() => $_has(5);
  @$pb.TagNumber(11)
  void clearLatest() => $_clearField(11);
  @$pb.TagNumber(11)
  PageRequest ensureLatest() => $_ensure(5);

  @$pb.TagNumber(12)
  SearchRequest get search => $_getN(6);
  @$pb.TagNumber(12)
  set search(SearchRequest value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasSearch() => $_has(6);
  @$pb.TagNumber(12)
  void clearSearch() => $_clearField(12);
  @$pb.TagNumber(12)
  SearchRequest ensureSearch() => $_ensure(6);

  @$pb.TagNumber(13)
  MangaRequest get details => $_getN(7);
  @$pb.TagNumber(13)
  set details(MangaRequest value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasDetails() => $_has(7);
  @$pb.TagNumber(13)
  void clearDetails() => $_clearField(13);
  @$pb.TagNumber(13)
  MangaRequest ensureDetails() => $_ensure(7);

  @$pb.TagNumber(14)
  MangaRequest get chapters => $_getN(8);
  @$pb.TagNumber(14)
  set chapters(MangaRequest value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasChapters() => $_has(8);
  @$pb.TagNumber(14)
  void clearChapters() => $_clearField(14);
  @$pb.TagNumber(14)
  MangaRequest ensureChapters() => $_ensure(8);

  @$pb.TagNumber(15)
  ChapterRequest get pages => $_getN(9);
  @$pb.TagNumber(15)
  set pages(ChapterRequest value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasPages() => $_has(9);
  @$pb.TagNumber(15)
  void clearPages() => $_clearField(15);
  @$pb.TagNumber(15)
  ChapterRequest ensurePages() => $_ensure(9);

  @$pb.TagNumber(16)
  GetFiltersRequest get getFilters => $_getN(10);
  @$pb.TagNumber(16)
  set getFilters(GetFiltersRequest value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasGetFilters() => $_has(10);
  @$pb.TagNumber(16)
  void clearGetFilters() => $_clearField(16);
  @$pb.TagNumber(16)
  GetFiltersRequest ensureGetFilters() => $_ensure(10);

  @$pb.TagNumber(17)
  Empty get getPreferences => $_getN(11);
  @$pb.TagNumber(17)
  set getPreferences(Empty value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasGetPreferences() => $_has(11);
  @$pb.TagNumber(17)
  void clearGetPreferences() => $_clearField(17);
  @$pb.TagNumber(17)
  Empty ensureGetPreferences() => $_ensure(11);

  @$pb.TagNumber(18)
  PreferenceEditRequest get editPreference => $_getN(12);
  @$pb.TagNumber(18)
  set editPreference(PreferenceEditRequest value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasEditPreference() => $_has(12);
  @$pb.TagNumber(18)
  void clearEditPreference() => $_clearField(18);
  @$pb.TagNumber(18)
  PreferenceEditRequest ensureEditPreference() => $_ensure(12);
}

class MangaPage extends $pb.GeneratedMessage {
  factory MangaPage({
    $core.Iterable<Manga>? mangas,
    $core.bool? hasNextPage,
  }) {
    final result = MangaPage._();
    if (mangas != null) result.mangas.addAll(mangas);
    if (hasNextPage != null) result.hasNextPage = hasNextPage;
    return result;
  }

  MangaPage._();

  factory MangaPage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaPage()..mergeFromBuffer(data, registry);
  factory MangaPage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaPage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MangaPage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: MangaPage.$_createMessage)
    ..pPM<Manga>(1, _omitFieldNames ? '' : 'mangas',
        subBuilder: Manga.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'hasNextPage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaPage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaPage copyWith(void Function(MangaPage) updates) =>
      super.copyWith((message) => updates(message as MangaPage)) as MangaPage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MangaPage() / MangaPage.new instead')
  static MangaPage create() => MangaPage._();
  static $pb.GeneratedMessage $_createMessage() => MangaPage._();
  @$core.override
  MangaPage createEmptyInstance() => MangaPage._();
  @$core.pragma('dart2js:noInline')
  static MangaPage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MangaPage>(MangaPage.$_createMessage);
  static MangaPage? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Manga> get mangas => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get hasNextPage => $_getBF(1);
  @$pb.TagNumber(2)
  set hasNextPage($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHasNextPage() => $_has(1);
  @$pb.TagNumber(2)
  void clearHasNextPage() => $_clearField(2);
}

class ChapterList extends $pb.GeneratedMessage {
  factory ChapterList({
    $core.Iterable<Chapter>? chapters,
  }) {
    final result = ChapterList._();
    if (chapters != null) result.chapters.addAll(chapters);
    return result;
  }

  ChapterList._();

  factory ChapterList.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterList()..mergeFromBuffer(data, registry);
  factory ChapterList.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterList()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChapterList',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ChapterList.$_createMessage)
    ..pPM<Chapter>(1, _omitFieldNames ? '' : 'chapters',
        subBuilder: Chapter.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterList clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterList copyWith(void Function(ChapterList) updates) =>
      super.copyWith((message) => updates(message as ChapterList))
          as ChapterList;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ChapterList() / ChapterList.new instead')
  static ChapterList create() => ChapterList._();
  static $pb.GeneratedMessage $_createMessage() => ChapterList._();
  @$core.override
  ChapterList createEmptyInstance() => ChapterList._();
  @$core.pragma('dart2js:noInline')
  static ChapterList getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChapterList>(
          ChapterList.$_createMessage);
  static ChapterList? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Chapter> get chapters => $_getList(0);
}

class PageList extends $pb.GeneratedMessage {
  factory PageList({
    $core.String? pageSessionId,
    $core.Iterable<Page>? pages,
  }) {
    final result = PageList._();
    if (pageSessionId != null) result.pageSessionId = pageSessionId;
    if (pages != null) result.pages.addAll(pages);
    return result;
  }

  PageList._();

  factory PageList.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PageList()..mergeFromBuffer(data, registry);
  factory PageList.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PageList()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PageList',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PageList.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'pageSessionId')
    ..pPM<Page>(2, _omitFieldNames ? '' : 'pages',
        subBuilder: Page.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PageList clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PageList copyWith(void Function(PageList) updates) =>
      super.copyWith((message) => updates(message as PageList)) as PageList;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PageList() / PageList.new instead')
  static PageList create() => PageList._();
  static $pb.GeneratedMessage $_createMessage() => PageList._();
  @$core.override
  PageList createEmptyInstance() => PageList._();
  @$core.pragma('dart2js:noInline')
  static PageList getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PageList>(PageList.$_createMessage);
  static PageList? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get pageSessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set pageSessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPageSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPageSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<Page> get pages => $_getList(1);
}

enum SourceResult_Payload {
  mangaPage,
  manga,
  chapters,
  pageList,
  filters,
  preferences,
  preferenceEdit,
  notSet
}

class SourceResult extends $pb.GeneratedMessage {
  factory SourceResult({
    $core.String? requestId,
    $core.String? generation,
    $core.String? buildId,
    MangaPage? mangaPage,
    Manga? manga,
    ChapterList? chapters,
    PageList? pageList,
    FilterSnapshot? filters,
    PreferenceSnapshot? preferences,
    PreferenceEditResult? preferenceEdit,
  }) {
    final result = SourceResult._();
    if (requestId != null) result.requestId = requestId;
    if (generation != null) result.generation = generation;
    if (buildId != null) result.buildId = buildId;
    if (mangaPage != null) result.mangaPage = mangaPage;
    if (manga != null) result.manga = manga;
    if (chapters != null) result.chapters = chapters;
    if (pageList != null) result.pageList = pageList;
    if (filters != null) result.filters = filters;
    if (preferences != null) result.preferences = preferences;
    if (preferenceEdit != null) result.preferenceEdit = preferenceEdit;
    return result;
  }

  SourceResult._();

  factory SourceResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourceResult()..mergeFromBuffer(data, registry);
  factory SourceResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourceResult()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, SourceResult_Payload>
      _SourceResult_PayloadByTag = {
    10: SourceResult_Payload.mangaPage,
    11: SourceResult_Payload.manga,
    12: SourceResult_Payload.chapters,
    13: SourceResult_Payload.pageList,
    14: SourceResult_Payload.filters,
    15: SourceResult_Payload.preferences,
    16: SourceResult_Payload.preferenceEdit,
    0: SourceResult_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SourceResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SourceResult.$_createMessage)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16])
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'generation')
    ..aOS(3, _omitFieldNames ? '' : 'buildId')
    ..aOM<MangaPage>(10, _omitFieldNames ? '' : 'mangaPage',
        subBuilder: MangaPage.$_createMessage)
    ..aOM<Manga>(11, _omitFieldNames ? '' : 'manga',
        subBuilder: Manga.$_createMessage)
    ..aOM<ChapterList>(12, _omitFieldNames ? '' : 'chapters',
        subBuilder: ChapterList.$_createMessage)
    ..aOM<PageList>(13, _omitFieldNames ? '' : 'pageList',
        subBuilder: PageList.$_createMessage)
    ..aOM<FilterSnapshot>(14, _omitFieldNames ? '' : 'filters',
        subBuilder: FilterSnapshot.$_createMessage)
    ..aOM<PreferenceSnapshot>(15, _omitFieldNames ? '' : 'preferences',
        subBuilder: PreferenceSnapshot.$_createMessage)
    ..aOM<PreferenceEditResult>(16, _omitFieldNames ? '' : 'preferenceEdit',
        subBuilder: PreferenceEditResult.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourceResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourceResult copyWith(void Function(SourceResult) updates) =>
      super.copyWith((message) => updates(message as SourceResult))
          as SourceResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SourceResult() / SourceResult.new instead')
  static SourceResult create() => SourceResult._();
  static $pb.GeneratedMessage $_createMessage() => SourceResult._();
  @$core.override
  SourceResult createEmptyInstance() => SourceResult._();
  @$core.pragma('dart2js:noInline')
  static SourceResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SourceResult>(
          SourceResult.$_createMessage);
  static SourceResult? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  SourceResult_Payload whichPayload() =>
      _SourceResult_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get generation => $_getSZ(1);
  @$pb.TagNumber(2)
  set generation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeneration() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeneration() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get buildId => $_getSZ(2);
  @$pb.TagNumber(3)
  set buildId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBuildId() => $_has(2);
  @$pb.TagNumber(3)
  void clearBuildId() => $_clearField(3);

  @$pb.TagNumber(10)
  MangaPage get mangaPage => $_getN(3);
  @$pb.TagNumber(10)
  set mangaPage(MangaPage value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasMangaPage() => $_has(3);
  @$pb.TagNumber(10)
  void clearMangaPage() => $_clearField(10);
  @$pb.TagNumber(10)
  MangaPage ensureMangaPage() => $_ensure(3);

  @$pb.TagNumber(11)
  Manga get manga => $_getN(4);
  @$pb.TagNumber(11)
  set manga(Manga value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasManga() => $_has(4);
  @$pb.TagNumber(11)
  void clearManga() => $_clearField(11);
  @$pb.TagNumber(11)
  Manga ensureManga() => $_ensure(4);

  @$pb.TagNumber(12)
  ChapterList get chapters => $_getN(5);
  @$pb.TagNumber(12)
  set chapters(ChapterList value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasChapters() => $_has(5);
  @$pb.TagNumber(12)
  void clearChapters() => $_clearField(12);
  @$pb.TagNumber(12)
  ChapterList ensureChapters() => $_ensure(5);

  @$pb.TagNumber(13)
  PageList get pageList => $_getN(6);
  @$pb.TagNumber(13)
  set pageList(PageList value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasPageList() => $_has(6);
  @$pb.TagNumber(13)
  void clearPageList() => $_clearField(13);
  @$pb.TagNumber(13)
  PageList ensurePageList() => $_ensure(6);

  @$pb.TagNumber(14)
  FilterSnapshot get filters => $_getN(7);
  @$pb.TagNumber(14)
  set filters(FilterSnapshot value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasFilters() => $_has(7);
  @$pb.TagNumber(14)
  void clearFilters() => $_clearField(14);
  @$pb.TagNumber(14)
  FilterSnapshot ensureFilters() => $_ensure(7);

  @$pb.TagNumber(15)
  PreferenceSnapshot get preferences => $_getN(8);
  @$pb.TagNumber(15)
  set preferences(PreferenceSnapshot value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasPreferences() => $_has(8);
  @$pb.TagNumber(15)
  void clearPreferences() => $_clearField(15);
  @$pb.TagNumber(15)
  PreferenceSnapshot ensurePreferences() => $_ensure(8);

  @$pb.TagNumber(16)
  PreferenceEditResult get preferenceEdit => $_getN(9);
  @$pb.TagNumber(16)
  set preferenceEdit(PreferenceEditResult value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasPreferenceEdit() => $_has(9);
  @$pb.TagNumber(16)
  void clearPreferenceEdit() => $_clearField(16);
  @$pb.TagNumber(16)
  PreferenceEditResult ensurePreferenceEdit() => $_ensure(9);
}

class CancelSourceRequest extends $pb.GeneratedMessage {
  factory CancelSourceRequest({
    $core.String? requestId,
    $core.String? generation,
  }) {
    final result = CancelSourceRequest._();
    if (requestId != null) result.requestId = requestId;
    if (generation != null) result.generation = generation;
    return result;
  }

  CancelSourceRequest._();

  factory CancelSourceRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelSourceRequest()..mergeFromBuffer(data, registry);
  factory CancelSourceRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelSourceRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CancelSourceRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CancelSourceRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'generation')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelSourceRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelSourceRequest copyWith(void Function(CancelSourceRequest) updates) =>
      super.copyWith((message) => updates(message as CancelSourceRequest))
          as CancelSourceRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use CancelSourceRequest() / CancelSourceRequest.new instead')
  static CancelSourceRequest create() => CancelSourceRequest._();
  static $pb.GeneratedMessage $_createMessage() => CancelSourceRequest._();
  @$core.override
  CancelSourceRequest createEmptyInstance() => CancelSourceRequest._();
  @$core.pragma('dart2js:noInline')
  static CancelSourceRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CancelSourceRequest>(
          CancelSourceRequest.$_createMessage);
  static CancelSourceRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get generation => $_getSZ(1);
  @$pb.TagNumber(2)
  set generation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeneration() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeneration() => $_clearField(2);
}

class AcquireImage extends $pb.GeneratedMessage {
  factory AcquireImage({
    $core.String? requestId,
    $core.String? sourceId,
    $core.String? pageSessionId,
    $core.String? pageKey,
    $core.String? generation,
    $core.int? timeoutMs,
  }) {
    final result = AcquireImage._();
    if (requestId != null) result.requestId = requestId;
    if (sourceId != null) result.sourceId = sourceId;
    if (pageSessionId != null) result.pageSessionId = pageSessionId;
    if (pageKey != null) result.pageKey = pageKey;
    if (generation != null) result.generation = generation;
    if (timeoutMs != null) result.timeoutMs = timeoutMs;
    return result;
  }

  AcquireImage._();

  factory AcquireImage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AcquireImage()..mergeFromBuffer(data, registry);
  factory AcquireImage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AcquireImage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AcquireImage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: AcquireImage.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'sourceId')
    ..aOS(3, _omitFieldNames ? '' : 'pageSessionId')
    ..aOS(4, _omitFieldNames ? '' : 'pageKey')
    ..aOS(5, _omitFieldNames ? '' : 'generation')
    ..aI(6, _omitFieldNames ? '' : 'timeoutMs', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcquireImage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcquireImage copyWith(void Function(AcquireImage) updates) =>
      super.copyWith((message) => updates(message as AcquireImage))
          as AcquireImage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AcquireImage() / AcquireImage.new instead')
  static AcquireImage create() => AcquireImage._();
  static $pb.GeneratedMessage $_createMessage() => AcquireImage._();
  @$core.override
  AcquireImage createEmptyInstance() => AcquireImage._();
  @$core.pragma('dart2js:noInline')
  static AcquireImage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AcquireImage>(
          AcquireImage.$_createMessage);
  static AcquireImage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sourceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSourceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get pageSessionId => $_getSZ(2);
  @$pb.TagNumber(3)
  set pageSessionId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPageSessionId() => $_has(2);
  @$pb.TagNumber(3)
  void clearPageSessionId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get pageKey => $_getSZ(3);
  @$pb.TagNumber(4)
  set pageKey($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPageKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearPageKey() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get generation => $_getSZ(4);
  @$pb.TagNumber(5)
  set generation($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasGeneration() => $_has(4);
  @$pb.TagNumber(5)
  void clearGeneration() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get timeoutMs => $_getIZ(5);
  @$pb.TagNumber(6)
  set timeoutMs($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTimeoutMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimeoutMs() => $_clearField(6);
}

class CancelImage extends $pb.GeneratedMessage {
  factory CancelImage({
    $core.String? requestId,
    $core.String? generation,
  }) {
    final result = CancelImage._();
    if (requestId != null) result.requestId = requestId;
    if (generation != null) result.generation = generation;
    return result;
  }

  CancelImage._();

  factory CancelImage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelImage()..mergeFromBuffer(data, registry);
  factory CancelImage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelImage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CancelImage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CancelImage.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'generation')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelImage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelImage copyWith(void Function(CancelImage) updates) =>
      super.copyWith((message) => updates(message as CancelImage))
          as CancelImage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CancelImage() / CancelImage.new instead')
  static CancelImage create() => CancelImage._();
  static $pb.GeneratedMessage $_createMessage() => CancelImage._();
  @$core.override
  CancelImage createEmptyInstance() => CancelImage._();
  @$core.pragma('dart2js:noInline')
  static CancelImage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CancelImage>(
          CancelImage.$_createMessage);
  static CancelImage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get generation => $_getSZ(1);
  @$pb.TagNumber(2)
  set generation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeneration() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeneration() => $_clearField(2);
}

class ReleaseImage extends $pb.GeneratedMessage {
  factory ReleaseImage({
    $core.String? resourceId,
    $core.String? generation,
  }) {
    final result = ReleaseImage._();
    if (resourceId != null) result.resourceId = resourceId;
    if (generation != null) result.generation = generation;
    return result;
  }

  ReleaseImage._();

  factory ReleaseImage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReleaseImage()..mergeFromBuffer(data, registry);
  factory ReleaseImage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReleaseImage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReleaseImage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ReleaseImage.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'resourceId')
    ..aOS(2, _omitFieldNames ? '' : 'generation')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReleaseImage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReleaseImage copyWith(void Function(ReleaseImage) updates) =>
      super.copyWith((message) => updates(message as ReleaseImage))
          as ReleaseImage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReleaseImage() / ReleaseImage.new instead')
  static ReleaseImage create() => ReleaseImage._();
  static $pb.GeneratedMessage $_createMessage() => ReleaseImage._();
  @$core.override
  ReleaseImage createEmptyInstance() => ReleaseImage._();
  @$core.pragma('dart2js:noInline')
  static ReleaseImage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReleaseImage>(
          ReleaseImage.$_createMessage);
  static ReleaseImage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get resourceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set resourceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasResourceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearResourceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get generation => $_getSZ(1);
  @$pb.TagNumber(2)
  set generation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeneration() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeneration() => $_clearField(2);
}

class ClosePageSession extends $pb.GeneratedMessage {
  factory ClosePageSession({
    $core.String? pageSessionId,
    $core.String? generation,
  }) {
    final result = ClosePageSession._();
    if (pageSessionId != null) result.pageSessionId = pageSessionId;
    if (generation != null) result.generation = generation;
    return result;
  }

  ClosePageSession._();

  factory ClosePageSession.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClosePageSession()..mergeFromBuffer(data, registry);
  factory ClosePageSession.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ClosePageSession()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ClosePageSession',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ClosePageSession.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'pageSessionId')
    ..aOS(2, _omitFieldNames ? '' : 'generation')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClosePageSession clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ClosePageSession copyWith(void Function(ClosePageSession) updates) =>
      super.copyWith((message) => updates(message as ClosePageSession))
          as ClosePageSession;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ClosePageSession() / ClosePageSession.new instead')
  static ClosePageSession create() => ClosePageSession._();
  static $pb.GeneratedMessage $_createMessage() => ClosePageSession._();
  @$core.override
  ClosePageSession createEmptyInstance() => ClosePageSession._();
  @$core.pragma('dart2js:noInline')
  static ClosePageSession getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ClosePageSession>(
          ClosePageSession.$_createMessage);
  static ClosePageSession? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get pageSessionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set pageSessionId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPageSessionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPageSessionId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get generation => $_getSZ(1);
  @$pb.TagNumber(2)
  set generation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeneration() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeneration() => $_clearField(2);
}

class Released extends $pb.GeneratedMessage {
  factory Released({
    $core.bool? released,
  }) {
    final result = Released._();
    if (released != null) result.released = released;
    return result;
  }

  Released._();

  factory Released.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Released()..mergeFromBuffer(data, registry);
  factory Released.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Released()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Released',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: Released.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'released')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Released clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Released copyWith(void Function(Released) updates) =>
      super.copyWith((message) => updates(message as Released)) as Released;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Released() / Released.new instead')
  static Released create() => Released._();
  static $pb.GeneratedMessage $_createMessage() => Released._();
  @$core.override
  Released createEmptyInstance() => Released._();
  @$core.pragma('dart2js:noInline')
  static Released getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Released>(Released.$_createMessage);
  static Released? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get released => $_getBF(0);
  @$pb.TagNumber(1)
  set released($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasReleased() => $_has(0);
  @$pb.TagNumber(1)
  void clearReleased() => $_clearField(1);
}

class Closed extends $pb.GeneratedMessage {
  factory Closed({
    $core.bool? closed,
  }) {
    final result = Closed._();
    if (closed != null) result.closed = closed;
    return result;
  }

  Closed._();

  factory Closed.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Closed()..mergeFromBuffer(data, registry);
  factory Closed.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Closed()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Closed',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: Closed.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'closed')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Closed clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Closed copyWith(void Function(Closed) updates) =>
      super.copyWith((message) => updates(message as Closed)) as Closed;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Closed() / Closed.new instead')
  static Closed create() => Closed._();
  static $pb.GeneratedMessage $_createMessage() => Closed._();
  @$core.override
  Closed createEmptyInstance() => Closed._();
  @$core.pragma('dart2js:noInline')
  static Closed getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Closed>(Closed.$_createMessage);
  static Closed? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get closed => $_getBF(0);
  @$pb.TagNumber(1)
  set closed($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasClosed() => $_has(0);
  @$pb.TagNumber(1)
  void clearClosed() => $_clearField(1);
}

class Completed extends $pb.GeneratedMessage {
  factory Completed({
    $core.bool? completed,
  }) {
    final result = Completed._();
    if (completed != null) result.completed = completed;
    return result;
  }

  Completed._();

  factory Completed.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Completed()..mergeFromBuffer(data, registry);
  factory Completed.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Completed()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Completed',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: Completed.$_createMessage)
    ..aOB(1, _omitFieldNames ? '' : 'completed')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Completed clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Completed copyWith(void Function(Completed) updates) =>
      super.copyWith((message) => updates(message as Completed)) as Completed;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Completed() / Completed.new instead')
  static Completed create() => Completed._();
  static $pb.GeneratedMessage $_createMessage() => Completed._();
  @$core.override
  Completed createEmptyInstance() => Completed._();
  @$core.pragma('dart2js:noInline')
  static Completed getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Completed>(Completed.$_createMessage);
  static Completed? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get completed => $_getBF(0);
  @$pb.TagNumber(1)
  set completed($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCompleted() => $_has(0);
  @$pb.TagNumber(1)
  void clearCompleted() => $_clearField(1);
}

/// An opaque Source-processed body. Image interpretation belongs to the UI.
class ProcessedImage extends $pb.GeneratedMessage {
  factory ProcessedImage({
    $core.String? resourceId,
    $core.String? generation,
    $core.int? byteLength,
  }) {
    final result = ProcessedImage._();
    if (resourceId != null) result.resourceId = resourceId;
    if (generation != null) result.generation = generation;
    if (byteLength != null) result.byteLength = byteLength;
    return result;
  }

  ProcessedImage._();

  factory ProcessedImage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ProcessedImage()..mergeFromBuffer(data, registry);
  factory ProcessedImage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ProcessedImage()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ProcessedImage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ProcessedImage.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'resourceId')
    ..aOS(2, _omitFieldNames ? '' : 'generation')
    ..aI(3, _omitFieldNames ? '' : 'byteLength', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProcessedImage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ProcessedImage copyWith(void Function(ProcessedImage) updates) =>
      super.copyWith((message) => updates(message as ProcessedImage))
          as ProcessedImage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ProcessedImage() / ProcessedImage.new instead')
  static ProcessedImage create() => ProcessedImage._();
  static $pb.GeneratedMessage $_createMessage() => ProcessedImage._();
  @$core.override
  ProcessedImage createEmptyInstance() => ProcessedImage._();
  @$core.pragma('dart2js:noInline')
  static ProcessedImage getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ProcessedImage>(
          ProcessedImage.$_createMessage);
  static ProcessedImage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get resourceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set resourceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasResourceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearResourceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get generation => $_getSZ(1);
  @$pb.TagNumber(2)
  set generation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeneration() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeneration() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get byteLength => $_getIZ(2);
  @$pb.TagNumber(3)
  set byteLength($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasByteLength() => $_has(2);
  @$pb.TagNumber(3)
  void clearByteLength() => $_clearField(3);
}

class ImageResource extends $pb.GeneratedMessage {
  factory ImageResource({
    $core.String? resourceId,
    $core.String? generation,
    $core.int? byteLength,
    $core.String? url,
  }) {
    final result = ImageResource._();
    if (resourceId != null) result.resourceId = resourceId;
    if (generation != null) result.generation = generation;
    if (byteLength != null) result.byteLength = byteLength;
    if (url != null) result.url = url;
    return result;
  }

  ImageResource._();

  factory ImageResource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageResource()..mergeFromBuffer(data, registry);
  factory ImageResource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageResource()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageResource',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ImageResource.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'resourceId')
    ..aOS(2, _omitFieldNames ? '' : 'generation')
    ..aI(3, _omitFieldNames ? '' : 'byteLength', fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'url')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageResource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageResource copyWith(void Function(ImageResource) updates) =>
      super.copyWith((message) => updates(message as ImageResource))
          as ImageResource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ImageResource() / ImageResource.new instead')
  static ImageResource create() => ImageResource._();
  static $pb.GeneratedMessage $_createMessage() => ImageResource._();
  @$core.override
  ImageResource createEmptyInstance() => ImageResource._();
  @$core.pragma('dart2js:noInline')
  static ImageResource getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ImageResource>(
          ImageResource.$_createMessage);
  static ImageResource? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get resourceId => $_getSZ(0);
  @$pb.TagNumber(1)
  set resourceId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasResourceId() => $_has(0);
  @$pb.TagNumber(1)
  void clearResourceId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get generation => $_getSZ(1);
  @$pb.TagNumber(2)
  set generation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeneration() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeneration() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get byteLength => $_getIZ(2);
  @$pb.TagNumber(3)
  set byteLength($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasByteLength() => $_has(2);
  @$pb.TagNumber(3)
  void clearByteLength() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get url => $_getSZ(3);
  @$pb.TagNumber(4)
  set url($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUrl() => $_has(3);
  @$pb.TagNumber(4)
  void clearUrl() => $_clearField(4);
}

class ImageMeta extends $pb.GeneratedMessage {
  factory ImageMeta() => ImageMeta._();

  ImageMeta._();

  factory ImageMeta.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageMeta()..mergeFromBuffer(data, registry);
  factory ImageMeta.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageMeta()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageMeta',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ImageMeta.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageMeta clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageMeta copyWith(void Function(ImageMeta) updates) =>
      super.copyWith((message) => updates(message as ImageMeta)) as ImageMeta;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ImageMeta() / ImageMeta.new instead')
  static ImageMeta create() => ImageMeta._();
  static $pb.GeneratedMessage $_createMessage() => ImageMeta._();
  @$core.override
  ImageMeta createEmptyInstance() => ImageMeta._();
  @$core.pragma('dart2js:noInline')
  static ImageMeta getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ImageMeta>(ImageMeta.$_createMessage);
  static ImageMeta? _defaultInstance;
}

class ImageData extends $pb.GeneratedMessage {
  factory ImageData({
    $core.int? seq,
    $core.int? byteLength,
  }) {
    final result = ImageData._();
    if (seq != null) result.seq = seq;
    if (byteLength != null) result.byteLength = byteLength;
    return result;
  }

  ImageData._();

  factory ImageData.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageData()..mergeFromBuffer(data, registry);
  factory ImageData.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageData()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageData',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ImageData.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'seq', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'byteLength', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageData clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageData copyWith(void Function(ImageData) updates) =>
      super.copyWith((message) => updates(message as ImageData)) as ImageData;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ImageData() / ImageData.new instead')
  static ImageData create() => ImageData._();
  static $pb.GeneratedMessage $_createMessage() => ImageData._();
  @$core.override
  ImageData createEmptyInstance() => ImageData._();
  @$core.pragma('dart2js:noInline')
  static ImageData getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ImageData>(ImageData.$_createMessage);
  static ImageData? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get seq => $_getIZ(0);
  @$pb.TagNumber(1)
  set seq($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get byteLength => $_getIZ(1);
  @$pb.TagNumber(2)
  set byteLength($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasByteLength() => $_has(1);
  @$pb.TagNumber(2)
  void clearByteLength() => $_clearField(2);
}

class ImageEnd extends $pb.GeneratedMessage {
  factory ImageEnd({
    $core.int? seq,
    $core.int? totalBytes,
  }) {
    final result = ImageEnd._();
    if (seq != null) result.seq = seq;
    if (totalBytes != null) result.totalBytes = totalBytes;
    return result;
  }

  ImageEnd._();

  factory ImageEnd.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageEnd()..mergeFromBuffer(data, registry);
  factory ImageEnd.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageEnd()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageEnd',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ImageEnd.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'seq', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'totalBytes', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageEnd clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageEnd copyWith(void Function(ImageEnd) updates) =>
      super.copyWith((message) => updates(message as ImageEnd)) as ImageEnd;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ImageEnd() / ImageEnd.new instead')
  static ImageEnd create() => ImageEnd._();
  static $pb.GeneratedMessage $_createMessage() => ImageEnd._();
  @$core.override
  ImageEnd createEmptyInstance() => ImageEnd._();
  @$core.pragma('dart2js:noInline')
  static ImageEnd getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ImageEnd>(ImageEnd.$_createMessage);
  static ImageEnd? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get seq => $_getIZ(0);
  @$pb.TagNumber(1)
  set seq($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get totalBytes => $_getIZ(1);
  @$pb.TagNumber(2)
  set totalBytes($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotalBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotalBytes() => $_clearField(2);
}

class ImageAck extends $pb.GeneratedMessage {
  factory ImageAck({
    $core.int? seq,
    ProcessedImage? resource,
  }) {
    final result = ImageAck._();
    if (seq != null) result.seq = seq;
    if (resource != null) result.resource = resource;
    return result;
  }

  ImageAck._();

  factory ImageAck.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageAck()..mergeFromBuffer(data, registry);
  factory ImageAck.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageAck()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageAck',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ImageAck.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'seq', fieldType: $pb.PbFieldType.OU3)
    ..aOM<ProcessedImage>(2, _omitFieldNames ? '' : 'resource',
        subBuilder: ProcessedImage.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageAck clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageAck copyWith(void Function(ImageAck) updates) =>
      super.copyWith((message) => updates(message as ImageAck)) as ImageAck;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ImageAck() / ImageAck.new instead')
  static ImageAck create() => ImageAck._();
  static $pb.GeneratedMessage $_createMessage() => ImageAck._();
  @$core.override
  ImageAck createEmptyInstance() => ImageAck._();
  @$core.pragma('dart2js:noInline')
  static ImageAck getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ImageAck>(ImageAck.$_createMessage);
  static ImageAck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get seq => $_getIZ(0);
  @$pb.TagNumber(1)
  set seq($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  @$pb.TagNumber(2)
  ProcessedImage get resource => $_getN(1);
  @$pb.TagNumber(2)
  set resource(ProcessedImage value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasResource() => $_has(1);
  @$pb.TagNumber(2)
  void clearResource() => $_clearField(2);
  @$pb.TagNumber(2)
  ProcessedImage ensureResource() => $_ensure(1);
}

enum ImageFrameControl_Frame { meta, data, end, ack, abort, notSet }

class ImageFrameControl extends $pb.GeneratedMessage {
  factory ImageFrameControl({
    ImageMeta? meta,
    ImageData? data,
    ImageEnd? end,
    ImageAck? ack,
    RuntimeError? abort,
  }) {
    final result = ImageFrameControl._();
    if (meta != null) result.meta = meta;
    if (data != null) result.data = data;
    if (end != null) result.end = end;
    if (ack != null) result.ack = ack;
    if (abort != null) result.abort = abort;
    return result;
  }

  ImageFrameControl._();

  factory ImageFrameControl.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageFrameControl()..mergeFromBuffer(data, registry);
  factory ImageFrameControl.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ImageFrameControl()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ImageFrameControl_Frame>
      _ImageFrameControl_FrameByTag = {
    1: ImageFrameControl_Frame.meta,
    2: ImageFrameControl_Frame.data,
    3: ImageFrameControl_Frame.end,
    4: ImageFrameControl_Frame.ack,
    5: ImageFrameControl_Frame.abort,
    0: ImageFrameControl_Frame.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ImageFrameControl',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ImageFrameControl.$_createMessage)
    ..oo(0, [1, 2, 3, 4, 5])
    ..aOM<ImageMeta>(1, _omitFieldNames ? '' : 'meta',
        subBuilder: ImageMeta.$_createMessage)
    ..aOM<ImageData>(2, _omitFieldNames ? '' : 'data',
        subBuilder: ImageData.$_createMessage)
    ..aOM<ImageEnd>(3, _omitFieldNames ? '' : 'end',
        subBuilder: ImageEnd.$_createMessage)
    ..aOM<ImageAck>(4, _omitFieldNames ? '' : 'ack',
        subBuilder: ImageAck.$_createMessage)
    ..aOM<RuntimeError>(5, _omitFieldNames ? '' : 'abort',
        subBuilder: RuntimeError.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageFrameControl clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ImageFrameControl copyWith(void Function(ImageFrameControl) updates) =>
      super.copyWith((message) => updates(message as ImageFrameControl))
          as ImageFrameControl;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ImageFrameControl() / ImageFrameControl.new instead')
  static ImageFrameControl create() => ImageFrameControl._();
  static $pb.GeneratedMessage $_createMessage() => ImageFrameControl._();
  @$core.override
  ImageFrameControl createEmptyInstance() => ImageFrameControl._();
  @$core.pragma('dart2js:noInline')
  static ImageFrameControl getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ImageFrameControl>(
          ImageFrameControl.$_createMessage);
  static ImageFrameControl? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  ImageFrameControl_Frame whichFrame() =>
      _ImageFrameControl_FrameByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  void clearFrame() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  ImageMeta get meta => $_getN(0);
  @$pb.TagNumber(1)
  set meta(ImageMeta value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMeta() => $_has(0);
  @$pb.TagNumber(1)
  void clearMeta() => $_clearField(1);
  @$pb.TagNumber(1)
  ImageMeta ensureMeta() => $_ensure(0);

  @$pb.TagNumber(2)
  ImageData get data => $_getN(1);
  @$pb.TagNumber(2)
  set data(ImageData value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasData() => $_has(1);
  @$pb.TagNumber(2)
  void clearData() => $_clearField(2);
  @$pb.TagNumber(2)
  ImageData ensureData() => $_ensure(1);

  @$pb.TagNumber(3)
  ImageEnd get end => $_getN(2);
  @$pb.TagNumber(3)
  set end(ImageEnd value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasEnd() => $_has(2);
  @$pb.TagNumber(3)
  void clearEnd() => $_clearField(3);
  @$pb.TagNumber(3)
  ImageEnd ensureEnd() => $_ensure(2);

  @$pb.TagNumber(4)
  ImageAck get ack => $_getN(3);
  @$pb.TagNumber(4)
  set ack(ImageAck value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasAck() => $_has(3);
  @$pb.TagNumber(4)
  void clearAck() => $_clearField(4);
  @$pb.TagNumber(4)
  ImageAck ensureAck() => $_ensure(3);

  @$pb.TagNumber(5)
  RuntimeError get abort => $_getN(4);
  @$pb.TagNumber(5)
  set abort(RuntimeError value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasAbort() => $_has(4);
  @$pb.TagNumber(5)
  void clearAbort() => $_clearField(5);
  @$pb.TagNumber(5)
  RuntimeError ensureAbort() => $_ensure(4);
}

class Artifact extends $pb.GeneratedMessage {
  factory Artifact({
    $core.String? path,
    $core.String? sha256,
    $core.int? size,
    $core.String? contentType,
    $core.String? logicalName,
  }) {
    final result = Artifact._();
    if (path != null) result.path = path;
    if (sha256 != null) result.sha256 = sha256;
    if (size != null) result.size = size;
    if (contentType != null) result.contentType = contentType;
    if (logicalName != null) result.logicalName = logicalName;
    return result;
  }

  Artifact._();

  factory Artifact.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Artifact()..mergeFromBuffer(data, registry);
  factory Artifact.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Artifact()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Artifact',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: Artifact.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOS(2, _omitFieldNames ? '' : 'sha256')
    ..aI(3, _omitFieldNames ? '' : 'size', fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'contentType')
    ..aOS(5, _omitFieldNames ? '' : 'logicalName')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Artifact clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Artifact copyWith(void Function(Artifact) updates) =>
      super.copyWith((message) => updates(message as Artifact)) as Artifact;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Artifact() / Artifact.new instead')
  static Artifact create() => Artifact._();
  static $pb.GeneratedMessage $_createMessage() => Artifact._();
  @$core.override
  Artifact createEmptyInstance() => Artifact._();
  @$core.pragma('dart2js:noInline')
  static Artifact getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Artifact>(Artifact.$_createMessage);
  static Artifact? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sha256 => $_getSZ(1);
  @$pb.TagNumber(2)
  set sha256($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSha256() => $_has(1);
  @$pb.TagNumber(2)
  void clearSha256() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get size => $_getIZ(2);
  @$pb.TagNumber(3)
  set size($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearSize() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get contentType => $_getSZ(3);
  @$pb.TagNumber(4)
  set contentType($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContentType() => $_has(3);
  @$pb.TagNumber(4)
  void clearContentType() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get logicalName => $_getSZ(4);
  @$pb.TagNumber(5)
  set logicalName($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasLogicalName() => $_has(4);
  @$pb.TagNumber(5)
  void clearLogicalName() => $_clearField(5);
}

class BundleArtifact extends $pb.GeneratedMessage {
  factory BundleArtifact({
    $core.String? path,
    $core.String? sha256,
    $core.int? size,
    $core.String? contentType,
    $core.String? encoding,
    $core.String? encodedSha256,
    $core.int? encodedSize,
  }) {
    final result = BundleArtifact._();
    if (path != null) result.path = path;
    if (sha256 != null) result.sha256 = sha256;
    if (size != null) result.size = size;
    if (contentType != null) result.contentType = contentType;
    if (encoding != null) result.encoding = encoding;
    if (encodedSha256 != null) result.encodedSha256 = encodedSha256;
    if (encodedSize != null) result.encodedSize = encodedSize;
    return result;
  }

  BundleArtifact._();

  factory BundleArtifact.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BundleArtifact()..mergeFromBuffer(data, registry);
  factory BundleArtifact.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BundleArtifact()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BundleArtifact',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: BundleArtifact.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOS(2, _omitFieldNames ? '' : 'sha256')
    ..aI(3, _omitFieldNames ? '' : 'size', fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'contentType')
    ..aOS(5, _omitFieldNames ? '' : 'encoding')
    ..aOS(6, _omitFieldNames ? '' : 'encodedSha256')
    ..aI(7, _omitFieldNames ? '' : 'encodedSize',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BundleArtifact clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BundleArtifact copyWith(void Function(BundleArtifact) updates) =>
      super.copyWith((message) => updates(message as BundleArtifact))
          as BundleArtifact;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BundleArtifact() / BundleArtifact.new instead')
  static BundleArtifact create() => BundleArtifact._();
  static $pb.GeneratedMessage $_createMessage() => BundleArtifact._();
  @$core.override
  BundleArtifact createEmptyInstance() => BundleArtifact._();
  @$core.pragma('dart2js:noInline')
  static BundleArtifact getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BundleArtifact>(
          BundleArtifact.$_createMessage);
  static BundleArtifact? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sha256 => $_getSZ(1);
  @$pb.TagNumber(2)
  set sha256($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSha256() => $_has(1);
  @$pb.TagNumber(2)
  void clearSha256() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get size => $_getIZ(2);
  @$pb.TagNumber(3)
  set size($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearSize() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get contentType => $_getSZ(3);
  @$pb.TagNumber(4)
  set contentType($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasContentType() => $_has(3);
  @$pb.TagNumber(4)
  void clearContentType() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get encoding => $_getSZ(4);
  @$pb.TagNumber(5)
  set encoding($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasEncoding() => $_has(4);
  @$pb.TagNumber(5)
  void clearEncoding() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get encodedSha256 => $_getSZ(5);
  @$pb.TagNumber(6)
  set encodedSha256($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEncodedSha256() => $_has(5);
  @$pb.TagNumber(6)
  void clearEncodedSha256() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get encodedSize => $_getIZ(6);
  @$pb.TagNumber(7)
  set encodedSize($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEncodedSize() => $_has(6);
  @$pb.TagNumber(7)
  void clearEncodedSize() => $_clearField(7);
}

/// Display metadata from the unchanged official extension build.
/// Runtime capabilities still come from actual Source initialization.
class CatalogSource extends $pb.GeneratedMessage {
  factory CatalogSource({
    $core.String? id,
    $core.String? name,
    $core.String? lang,
  }) {
    final result = CatalogSource._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    if (lang != null) result.lang = lang;
    return result;
  }

  CatalogSource._();

  factory CatalogSource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CatalogSource()..mergeFromBuffer(data, registry);
  factory CatalogSource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CatalogSource()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CatalogSource',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CatalogSource.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'lang')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CatalogSource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CatalogSource copyWith(void Function(CatalogSource) updates) =>
      super.copyWith((message) => updates(message as CatalogSource))
          as CatalogSource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CatalogSource() / CatalogSource.new instead')
  static CatalogSource create() => CatalogSource._();
  static $pb.GeneratedMessage $_createMessage() => CatalogSource._();
  @$core.override
  CatalogSource createEmptyInstance() => CatalogSource._();
  @$core.pragma('dart2js:noInline')
  static CatalogSource getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CatalogSource>(
          CatalogSource.$_createMessage);
  static CatalogSource? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get lang => $_getSZ(2);
  @$pb.TagNumber(3)
  set lang($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLang() => $_has(2);
  @$pb.TagNumber(3)
  void clearLang() => $_clearField(3);
}

class BuildManifest extends $pb.GeneratedMessage {
  factory BuildManifest({
    $core.int? protocolVersion,
    $core.String? hostAbi,
    $core.String? runtimeBaseline,
    $core.int? bridgeVersion,
    $core.String? buildId,
    $core.String? packageName,
    $core.String? repoId,
    $core.String? version,
    $core.String? storageSchema,
    $core.Iterable<$core.String>? sourceIds,
    BundleArtifact? bundle,
    $core.Iterable<Artifact>? hostScripts,
    $core.Iterable<Artifact>? resources,
    $core.Iterable<CatalogSource>? sources,
  }) {
    final result = BuildManifest._();
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (hostAbi != null) result.hostAbi = hostAbi;
    if (runtimeBaseline != null) result.runtimeBaseline = runtimeBaseline;
    if (bridgeVersion != null) result.bridgeVersion = bridgeVersion;
    if (buildId != null) result.buildId = buildId;
    if (packageName != null) result.packageName = packageName;
    if (repoId != null) result.repoId = repoId;
    if (version != null) result.version = version;
    if (storageSchema != null) result.storageSchema = storageSchema;
    if (sourceIds != null) result.sourceIds.addAll(sourceIds);
    if (bundle != null) result.bundle = bundle;
    if (hostScripts != null) result.hostScripts.addAll(hostScripts);
    if (resources != null) result.resources.addAll(resources);
    if (sources != null) result.sources.addAll(sources);
    return result;
  }

  BuildManifest._();

  factory BuildManifest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BuildManifest()..mergeFromBuffer(data, registry);
  factory BuildManifest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BuildManifest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BuildManifest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: BuildManifest.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'hostAbi')
    ..aOS(3, _omitFieldNames ? '' : 'runtimeBaseline')
    ..aI(4, _omitFieldNames ? '' : 'bridgeVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(5, _omitFieldNames ? '' : 'buildId')
    ..aOS(6, _omitFieldNames ? '' : 'packageName')
    ..aOS(7, _omitFieldNames ? '' : 'repoId')
    ..aOS(8, _omitFieldNames ? '' : 'version')
    ..aOS(9, _omitFieldNames ? '' : 'storageSchema')
    ..pPS(10, _omitFieldNames ? '' : 'sourceIds')
    ..aOM<BundleArtifact>(11, _omitFieldNames ? '' : 'bundle',
        subBuilder: BundleArtifact.$_createMessage)
    ..pPM<Artifact>(12, _omitFieldNames ? '' : 'hostScripts',
        subBuilder: Artifact.$_createMessage)
    ..pPM<Artifact>(13, _omitFieldNames ? '' : 'resources',
        subBuilder: Artifact.$_createMessage)
    ..pPM<CatalogSource>(14, _omitFieldNames ? '' : 'sources',
        subBuilder: CatalogSource.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BuildManifest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BuildManifest copyWith(void Function(BuildManifest) updates) =>
      super.copyWith((message) => updates(message as BuildManifest))
          as BuildManifest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BuildManifest() / BuildManifest.new instead')
  static BuildManifest create() => BuildManifest._();
  static $pb.GeneratedMessage $_createMessage() => BuildManifest._();
  @$core.override
  BuildManifest createEmptyInstance() => BuildManifest._();
  @$core.pragma('dart2js:noInline')
  static BuildManifest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BuildManifest>(
          BuildManifest.$_createMessage);
  static BuildManifest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get protocolVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set protocolVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProtocolVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearProtocolVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get hostAbi => $_getSZ(1);
  @$pb.TagNumber(2)
  set hostAbi($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHostAbi() => $_has(1);
  @$pb.TagNumber(2)
  void clearHostAbi() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get runtimeBaseline => $_getSZ(2);
  @$pb.TagNumber(3)
  set runtimeBaseline($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRuntimeBaseline() => $_has(2);
  @$pb.TagNumber(3)
  void clearRuntimeBaseline() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get bridgeVersion => $_getIZ(3);
  @$pb.TagNumber(4)
  set bridgeVersion($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBridgeVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearBridgeVersion() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get buildId => $_getSZ(4);
  @$pb.TagNumber(5)
  set buildId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBuildId() => $_has(4);
  @$pb.TagNumber(5)
  void clearBuildId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get packageName => $_getSZ(5);
  @$pb.TagNumber(6)
  set packageName($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasPackageName() => $_has(5);
  @$pb.TagNumber(6)
  void clearPackageName() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get repoId => $_getSZ(6);
  @$pb.TagNumber(7)
  set repoId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRepoId() => $_has(6);
  @$pb.TagNumber(7)
  void clearRepoId() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get version => $_getSZ(7);
  @$pb.TagNumber(8)
  set version($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasVersion() => $_has(7);
  @$pb.TagNumber(8)
  void clearVersion() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get storageSchema => $_getSZ(8);
  @$pb.TagNumber(9)
  set storageSchema($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasStorageSchema() => $_has(8);
  @$pb.TagNumber(9)
  void clearStorageSchema() => $_clearField(9);

  @$pb.TagNumber(10)
  $pb.PbList<$core.String> get sourceIds => $_getList(9);

  @$pb.TagNumber(11)
  BundleArtifact get bundle => $_getN(10);
  @$pb.TagNumber(11)
  set bundle(BundleArtifact value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasBundle() => $_has(10);
  @$pb.TagNumber(11)
  void clearBundle() => $_clearField(11);
  @$pb.TagNumber(11)
  BundleArtifact ensureBundle() => $_ensure(10);

  @$pb.TagNumber(12)
  $pb.PbList<Artifact> get hostScripts => $_getList(11);

  @$pb.TagNumber(13)
  $pb.PbList<Artifact> get resources => $_getList(12);

  /// Complete metadata for exactly source_ids, without running the extension.
  @$pb.TagNumber(14)
  $pb.PbList<CatalogSource> get sources => $_getList(13);
}

class ExtensionBuildDescriptor extends $pb.GeneratedMessage {
  factory ExtensionBuildDescriptor({
    $core.String? buildId,
    $core.String? packageName,
    $core.String? repoId,
    $core.String? version,
    $core.Iterable<$core.String>? sourceIds,
    $core.String? manifestPath,
    $core.Iterable<CatalogSource>? sources,
  }) {
    final result = ExtensionBuildDescriptor._();
    if (buildId != null) result.buildId = buildId;
    if (packageName != null) result.packageName = packageName;
    if (repoId != null) result.repoId = repoId;
    if (version != null) result.version = version;
    if (sourceIds != null) result.sourceIds.addAll(sourceIds);
    if (manifestPath != null) result.manifestPath = manifestPath;
    if (sources != null) result.sources.addAll(sources);
    return result;
  }

  ExtensionBuildDescriptor._();

  factory ExtensionBuildDescriptor.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExtensionBuildDescriptor()..mergeFromBuffer(data, registry);
  factory ExtensionBuildDescriptor.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExtensionBuildDescriptor()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExtensionBuildDescriptor',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ExtensionBuildDescriptor.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'buildId')
    ..aOS(2, _omitFieldNames ? '' : 'packageName')
    ..aOS(3, _omitFieldNames ? '' : 'repoId')
    ..aOS(4, _omitFieldNames ? '' : 'version')
    ..pPS(5, _omitFieldNames ? '' : 'sourceIds')
    ..aOS(6, _omitFieldNames ? '' : 'manifestPath')
    ..pPM<CatalogSource>(7, _omitFieldNames ? '' : 'sources',
        subBuilder: CatalogSource.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExtensionBuildDescriptor clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExtensionBuildDescriptor copyWith(
          void Function(ExtensionBuildDescriptor) updates) =>
      super.copyWith((message) => updates(message as ExtensionBuildDescriptor))
          as ExtensionBuildDescriptor;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ExtensionBuildDescriptor() / ExtensionBuildDescriptor.new instead')
  static ExtensionBuildDescriptor create() => ExtensionBuildDescriptor._();
  static $pb.GeneratedMessage $_createMessage() => ExtensionBuildDescriptor._();
  @$core.override
  ExtensionBuildDescriptor createEmptyInstance() =>
      ExtensionBuildDescriptor._();
  @$core.pragma('dart2js:noInline')
  static ExtensionBuildDescriptor getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExtensionBuildDescriptor>(
          ExtensionBuildDescriptor.$_createMessage);
  static ExtensionBuildDescriptor? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get buildId => $_getSZ(0);
  @$pb.TagNumber(1)
  set buildId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBuildId() => $_has(0);
  @$pb.TagNumber(1)
  void clearBuildId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get packageName => $_getSZ(1);
  @$pb.TagNumber(2)
  set packageName($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPackageName() => $_has(1);
  @$pb.TagNumber(2)
  void clearPackageName() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get repoId => $_getSZ(2);
  @$pb.TagNumber(3)
  set repoId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRepoId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRepoId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get version => $_getSZ(3);
  @$pb.TagNumber(4)
  set version($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearVersion() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get sourceIds => $_getList(4);

  @$pb.TagNumber(6)
  $core.String get manifestPath => $_getSZ(5);
  @$pb.TagNumber(6)
  set manifestPath($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasManifestPath() => $_has(5);
  @$pb.TagNumber(6)
  void clearManifestPath() => $_clearField(6);

  @$pb.TagNumber(7)
  $pb.PbList<CatalogSource> get sources => $_getList(6);
}

class ExtensionIndex extends $pb.GeneratedMessage {
  factory ExtensionIndex({
    $core.int? schemaVersion,
    $core.Iterable<ExtensionBuildDescriptor>? builds,
    $core.String? repoId,
  }) {
    final result = ExtensionIndex._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (builds != null) result.builds.addAll(builds);
    if (repoId != null) result.repoId = repoId;
    return result;
  }

  ExtensionIndex._();

  factory ExtensionIndex.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExtensionIndex()..mergeFromBuffer(data, registry);
  factory ExtensionIndex.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExtensionIndex()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExtensionIndex',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ExtensionIndex.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..pPM<ExtensionBuildDescriptor>(2, _omitFieldNames ? '' : 'builds',
        subBuilder: ExtensionBuildDescriptor.$_createMessage)
    ..aOS(3, _omitFieldNames ? '' : 'repoId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExtensionIndex clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExtensionIndex copyWith(void Function(ExtensionIndex) updates) =>
      super.copyWith((message) => updates(message as ExtensionIndex))
          as ExtensionIndex;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ExtensionIndex() / ExtensionIndex.new instead')
  static ExtensionIndex create() => ExtensionIndex._();
  static $pb.GeneratedMessage $_createMessage() => ExtensionIndex._();
  @$core.override
  ExtensionIndex createEmptyInstance() => ExtensionIndex._();
  @$core.pragma('dart2js:noInline')
  static ExtensionIndex getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ExtensionIndex>(
          ExtensionIndex.$_createMessage);
  static ExtensionIndex? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<ExtensionBuildDescriptor> get builds => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get repoId => $_getSZ(2);
  @$pb.TagNumber(3)
  set repoId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRepoId() => $_has(2);
  @$pb.TagNumber(3)
  void clearRepoId() => $_clearField(3);
}

class Identity extends $pb.GeneratedMessage {
  factory Identity({
    $core.String? subject,
    $core.String? email,
  }) {
    final result = Identity._();
    if (subject != null) result.subject = subject;
    if (email != null) result.email = email;
    return result;
  }

  Identity._();

  factory Identity.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Identity()..mergeFromBuffer(data, registry);
  factory Identity.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Identity()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Identity',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: Identity.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'subject')
    ..aOS(2, _omitFieldNames ? '' : 'email')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Identity clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Identity copyWith(void Function(Identity) updates) =>
      super.copyWith((message) => updates(message as Identity)) as Identity;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Identity() / Identity.new instead')
  static Identity create() => Identity._();
  static $pb.GeneratedMessage $_createMessage() => Identity._();
  @$core.override
  Identity createEmptyInstance() => Identity._();
  @$core.pragma('dart2js:noInline')
  static Identity getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Identity>(Identity.$_createMessage);
  static Identity? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get subject => $_getSZ(0);
  @$pb.TagNumber(1)
  set subject($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSubject() => $_has(0);
  @$pb.TagNumber(1)
  void clearSubject() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get email => $_getSZ(1);
  @$pb.TagNumber(2)
  set email($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEmail() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmail() => $_clearField(2);
}

class Bootstrap extends $pb.GeneratedMessage {
  factory Bootstrap({
    $core.int? protocolVersion,
    Identity? identity,
    $core.double? expiresAt,
    BootstrapStage? stage,
  }) {
    final result = Bootstrap._();
    if (protocolVersion != null) result.protocolVersion = protocolVersion;
    if (identity != null) result.identity = identity;
    if (expiresAt != null) result.expiresAt = expiresAt;
    if (stage != null) result.stage = stage;
    return result;
  }

  Bootstrap._();

  factory Bootstrap.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Bootstrap()..mergeFromBuffer(data, registry);
  factory Bootstrap.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Bootstrap()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Bootstrap',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: Bootstrap.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'protocolVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<Identity>(2, _omitFieldNames ? '' : 'identity',
        subBuilder: Identity.$_createMessage)
    ..aD(3, _omitFieldNames ? '' : 'expiresAt')
    ..aE<BootstrapStage>(4, _omitFieldNames ? '' : 'stage',
        enumValues: BootstrapStage.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bootstrap clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Bootstrap copyWith(void Function(Bootstrap) updates) =>
      super.copyWith((message) => updates(message as Bootstrap)) as Bootstrap;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Bootstrap() / Bootstrap.new instead')
  static Bootstrap create() => Bootstrap._();
  static $pb.GeneratedMessage $_createMessage() => Bootstrap._();
  @$core.override
  Bootstrap createEmptyInstance() => Bootstrap._();
  @$core.pragma('dart2js:noInline')
  static Bootstrap getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Bootstrap>(Bootstrap.$_createMessage);
  static Bootstrap? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get protocolVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set protocolVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasProtocolVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearProtocolVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  Identity get identity => $_getN(1);
  @$pb.TagNumber(2)
  set identity(Identity value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasIdentity() => $_has(1);
  @$pb.TagNumber(2)
  void clearIdentity() => $_clearField(2);
  @$pb.TagNumber(2)
  Identity ensureIdentity() => $_ensure(1);

  /// Millisecond/second epoch value supplied by the existing Access endpoint;
  /// semantic validation requires a positive safe integer.
  @$pb.TagNumber(3)
  $core.double get expiresAt => $_getN(2);
  @$pb.TagNumber(3)
  set expiresAt($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpiresAt() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpiresAt() => $_clearField(3);

  @$pb.TagNumber(4)
  BootstrapStage get stage => $_getN(3);
  @$pb.TagNumber(4)
  set stage(BootstrapStage value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasStage() => $_has(3);
  @$pb.TagNumber(4)
  void clearStage() => $_clearField(4);
}

class ApiFetchRequest extends $pb.GeneratedMessage {
  factory ApiFetchRequest({
    $core.String? path,
    $core.String? method,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? headers,
    $core.String? body,
  }) {
    final result = ApiFetchRequest._();
    if (path != null) result.path = path;
    if (method != null) result.method = method;
    if (headers != null) result.headers.addEntries(headers);
    if (body != null) result.body = body;
    return result;
  }

  ApiFetchRequest._();

  factory ApiFetchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApiFetchRequest()..mergeFromBuffer(data, registry);
  factory ApiFetchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApiFetchRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ApiFetchRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ApiFetchRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'path')
    ..aOS(2, _omitFieldNames ? '' : 'method')
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'headers',
        entryClassName: 'ApiFetchRequest.HeadersEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('karuyomi.v1'))
    ..aOS(4, _omitFieldNames ? '' : 'body')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApiFetchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApiFetchRequest copyWith(void Function(ApiFetchRequest) updates) =>
      super.copyWith((message) => updates(message as ApiFetchRequest))
          as ApiFetchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ApiFetchRequest() / ApiFetchRequest.new instead')
  static ApiFetchRequest create() => ApiFetchRequest._();
  static $pb.GeneratedMessage $_createMessage() => ApiFetchRequest._();
  @$core.override
  ApiFetchRequest createEmptyInstance() => ApiFetchRequest._();
  @$core.pragma('dart2js:noInline')
  static ApiFetchRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ApiFetchRequest>(
          ApiFetchRequest.$_createMessage);
  static ApiFetchRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get path => $_getSZ(0);
  @$pb.TagNumber(1)
  set path($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get method => $_getSZ(1);
  @$pb.TagNumber(2)
  set method($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMethod() => $_has(1);
  @$pb.TagNumber(2)
  void clearMethod() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbMap<$core.String, $core.String> get headers => $_getMap(2);

  @$pb.TagNumber(4)
  $core.String get body => $_getSZ(3);
  @$pb.TagNumber(4)
  set body($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBody() => $_has(3);
  @$pb.TagNumber(4)
  void clearBody() => $_clearField(4);
}

class ApiFetchResponse extends $pb.GeneratedMessage {
  factory ApiFetchResponse({
    $core.int? status,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? headers,
    $core.String? body,
    $core.bool? redirected,
  }) {
    final result = ApiFetchResponse._();
    if (status != null) result.status = status;
    if (headers != null) result.headers.addEntries(headers);
    if (body != null) result.body = body;
    if (redirected != null) result.redirected = redirected;
    return result;
  }

  ApiFetchResponse._();

  factory ApiFetchResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApiFetchResponse()..mergeFromBuffer(data, registry);
  factory ApiFetchResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ApiFetchResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ApiFetchResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ApiFetchResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'status', fieldType: $pb.PbFieldType.OU3)
    ..m<$core.String, $core.String>(2, _omitFieldNames ? '' : 'headers',
        entryClassName: 'ApiFetchResponse.HeadersEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('karuyomi.v1'))
    ..aOS(3, _omitFieldNames ? '' : 'body')
    ..aOB(4, _omitFieldNames ? '' : 'redirected')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApiFetchResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ApiFetchResponse copyWith(void Function(ApiFetchResponse) updates) =>
      super.copyWith((message) => updates(message as ApiFetchResponse))
          as ApiFetchResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ApiFetchResponse() / ApiFetchResponse.new instead')
  static ApiFetchResponse create() => ApiFetchResponse._();
  static $pb.GeneratedMessage $_createMessage() => ApiFetchResponse._();
  @$core.override
  ApiFetchResponse createEmptyInstance() => ApiFetchResponse._();
  @$core.pragma('dart2js:noInline')
  static ApiFetchResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ApiFetchResponse>(
          ApiFetchResponse.$_createMessage);
  static ApiFetchResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get status => $_getIZ(0);
  @$pb.TagNumber(1)
  set status($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbMap<$core.String, $core.String> get headers => $_getMap(1);

  @$pb.TagNumber(3)
  $core.String get body => $_getSZ(2);
  @$pb.TagNumber(3)
  set body($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasBody() => $_has(2);
  @$pb.TagNumber(3)
  void clearBody() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get redirected => $_getBF(3);
  @$pb.TagNumber(4)
  set redirected($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRedirected() => $_has(3);
  @$pb.TagNumber(4)
  void clearRedirected() => $_clearField(4);
}

/// Local preparation never constructs or executes a Source.
class PrepareBuildRequest extends $pb.GeneratedMessage {
  factory PrepareBuildRequest({
    $core.String? preparationId,
    ExtensionBuildDescriptor? build,
    CatalogReference? catalog,
  }) {
    final result = PrepareBuildRequest._();
    if (preparationId != null) result.preparationId = preparationId;
    if (build != null) result.build = build;
    if (catalog != null) result.catalog = catalog;
    return result;
  }

  PrepareBuildRequest._();

  factory PrepareBuildRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PrepareBuildRequest()..mergeFromBuffer(data, registry);
  factory PrepareBuildRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PrepareBuildRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PrepareBuildRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PrepareBuildRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'preparationId')
    ..aOM<ExtensionBuildDescriptor>(2, _omitFieldNames ? '' : 'build',
        subBuilder: ExtensionBuildDescriptor.$_createMessage)
    ..aOM<CatalogReference>(3, _omitFieldNames ? '' : 'catalog',
        subBuilder: CatalogReference.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareBuildRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PrepareBuildRequest copyWith(void Function(PrepareBuildRequest) updates) =>
      super.copyWith((message) => updates(message as PrepareBuildRequest))
          as PrepareBuildRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use PrepareBuildRequest() / PrepareBuildRequest.new instead')
  static PrepareBuildRequest create() => PrepareBuildRequest._();
  static $pb.GeneratedMessage $_createMessage() => PrepareBuildRequest._();
  @$core.override
  PrepareBuildRequest createEmptyInstance() => PrepareBuildRequest._();
  @$core.pragma('dart2js:noInline')
  static PrepareBuildRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PrepareBuildRequest>(
          PrepareBuildRequest.$_createMessage);
  static PrepareBuildRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get preparationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set preparationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPreparationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPreparationId() => $_clearField(1);

  @$pb.TagNumber(2)
  ExtensionBuildDescriptor get build => $_getN(1);
  @$pb.TagNumber(2)
  set build(ExtensionBuildDescriptor value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasBuild() => $_has(1);
  @$pb.TagNumber(2)
  void clearBuild() => $_clearField(2);
  @$pb.TagNumber(2)
  ExtensionBuildDescriptor ensureBuild() => $_ensure(1);

  @$pb.TagNumber(3)
  CatalogReference get catalog => $_getN(2);
  @$pb.TagNumber(3)
  set catalog(CatalogReference value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCatalog() => $_has(2);
  @$pb.TagNumber(3)
  void clearCatalog() => $_clearField(3);
  @$pb.TagNumber(3)
  CatalogReference ensureCatalog() => $_ensure(2);
}

class CancelPreparationRequest extends $pb.GeneratedMessage {
  factory CancelPreparationRequest({
    $core.String? preparationId,
  }) {
    final result = CancelPreparationRequest._();
    if (preparationId != null) result.preparationId = preparationId;
    return result;
  }

  CancelPreparationRequest._();

  factory CancelPreparationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelPreparationRequest()..mergeFromBuffer(data, registry);
  factory CancelPreparationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CancelPreparationRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CancelPreparationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CancelPreparationRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'preparationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelPreparationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancelPreparationRequest copyWith(
          void Function(CancelPreparationRequest) updates) =>
      super.copyWith((message) => updates(message as CancelPreparationRequest))
          as CancelPreparationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CancelPreparationRequest() / CancelPreparationRequest.new instead')
  static CancelPreparationRequest create() => CancelPreparationRequest._();
  static $pb.GeneratedMessage $_createMessage() => CancelPreparationRequest._();
  @$core.override
  CancelPreparationRequest createEmptyInstance() =>
      CancelPreparationRequest._();
  @$core.pragma('dart2js:noInline')
  static CancelPreparationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CancelPreparationRequest>(
          CancelPreparationRequest.$_createMessage);
  static CancelPreparationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get preparationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set preparationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPreparationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPreparationId() => $_clearField(1);
}

class PreparedBuild extends $pb.GeneratedMessage {
  factory PreparedBuild({
    ExtensionBuildDescriptor? build,
    $core.String? bundleSha256,
    $core.int? byteLength,
    CatalogReference? catalog,
  }) {
    final result = PreparedBuild._();
    if (build != null) result.build = build;
    if (bundleSha256 != null) result.bundleSha256 = bundleSha256;
    if (byteLength != null) result.byteLength = byteLength;
    if (catalog != null) result.catalog = catalog;
    return result;
  }

  PreparedBuild._();

  factory PreparedBuild.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreparedBuild()..mergeFromBuffer(data, registry);
  factory PreparedBuild.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      PreparedBuild()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PreparedBuild',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: PreparedBuild.$_createMessage)
    ..aOM<ExtensionBuildDescriptor>(1, _omitFieldNames ? '' : 'build',
        subBuilder: ExtensionBuildDescriptor.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'bundleSha256')
    ..aI(3, _omitFieldNames ? '' : 'byteLength', fieldType: $pb.PbFieldType.OU3)
    ..aOM<CatalogReference>(4, _omitFieldNames ? '' : 'catalog',
        subBuilder: CatalogReference.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreparedBuild clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PreparedBuild copyWith(void Function(PreparedBuild) updates) =>
      super.copyWith((message) => updates(message as PreparedBuild))
          as PreparedBuild;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use PreparedBuild() / PreparedBuild.new instead')
  static PreparedBuild create() => PreparedBuild._();
  static $pb.GeneratedMessage $_createMessage() => PreparedBuild._();
  @$core.override
  PreparedBuild createEmptyInstance() => PreparedBuild._();
  @$core.pragma('dart2js:noInline')
  static PreparedBuild getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PreparedBuild>(
          PreparedBuild.$_createMessage);
  static PreparedBuild? _defaultInstance;

  @$pb.TagNumber(1)
  ExtensionBuildDescriptor get build => $_getN(0);
  @$pb.TagNumber(1)
  set build(ExtensionBuildDescriptor value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasBuild() => $_has(0);
  @$pb.TagNumber(1)
  void clearBuild() => $_clearField(1);
  @$pb.TagNumber(1)
  ExtensionBuildDescriptor ensureBuild() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get bundleSha256 => $_getSZ(1);
  @$pb.TagNumber(2)
  set bundleSha256($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBundleSha256() => $_has(1);
  @$pb.TagNumber(2)
  void clearBundleSha256() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get byteLength => $_getIZ(2);
  @$pb.TagNumber(3)
  set byteLength($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasByteLength() => $_has(2);
  @$pb.TagNumber(3)
  void clearByteLength() => $_clearField(3);

  @$pb.TagNumber(4)
  CatalogReference get catalog => $_getN(3);
  @$pb.TagNumber(4)
  set catalog(CatalogReference value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCatalog() => $_has(3);
  @$pb.TagNumber(4)
  void clearCatalog() => $_clearField(4);
  @$pb.TagNumber(4)
  CatalogReference ensureCatalog() => $_ensure(3);
}

class CachedExtensionArtifact extends $pb.GeneratedMessage {
  factory CachedExtensionArtifact({
    $core.String? sha256,
    $core.int? byteLength,
    $core.String? contentType,
  }) {
    final result = CachedExtensionArtifact._();
    if (sha256 != null) result.sha256 = sha256;
    if (byteLength != null) result.byteLength = byteLength;
    if (contentType != null) result.contentType = contentType;
    return result;
  }

  CachedExtensionArtifact._();

  factory CachedExtensionArtifact.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CachedExtensionArtifact()..mergeFromBuffer(data, registry);
  factory CachedExtensionArtifact.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CachedExtensionArtifact()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CachedExtensionArtifact',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CachedExtensionArtifact.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sha256')
    ..aI(2, _omitFieldNames ? '' : 'byteLength', fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'contentType')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CachedExtensionArtifact clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CachedExtensionArtifact copyWith(
          void Function(CachedExtensionArtifact) updates) =>
      super.copyWith((message) => updates(message as CachedExtensionArtifact))
          as CachedExtensionArtifact;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CachedExtensionArtifact() / CachedExtensionArtifact.new instead')
  static CachedExtensionArtifact create() => CachedExtensionArtifact._();
  static $pb.GeneratedMessage $_createMessage() => CachedExtensionArtifact._();
  @$core.override
  CachedExtensionArtifact createEmptyInstance() => CachedExtensionArtifact._();
  @$core.pragma('dart2js:noInline')
  static CachedExtensionArtifact getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CachedExtensionArtifact>(
          CachedExtensionArtifact.$_createMessage);
  static CachedExtensionArtifact? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sha256 => $_getSZ(0);
  @$pb.TagNumber(1)
  set sha256($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSha256() => $_has(0);
  @$pb.TagNumber(1)
  void clearSha256() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get byteLength => $_getIZ(1);
  @$pb.TagNumber(2)
  set byteLength($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasByteLength() => $_has(1);
  @$pb.TagNumber(2)
  void clearByteLength() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get contentType => $_getSZ(2);
  @$pb.TagNumber(3)
  set contentType($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasContentType() => $_has(2);
  @$pb.TagNumber(3)
  void clearContentType() => $_clearField(3);
}

class ExtensionCacheState extends $pb.GeneratedMessage {
  factory ExtensionCacheState({
    $core.Iterable<CachedExtensionArtifact>? artifacts,
    $core.int? totalBytes,
    $core.int? maxBytes,
    $core.int? maxArtifacts,
  }) {
    final result = ExtensionCacheState._();
    if (artifacts != null) result.artifacts.addAll(artifacts);
    if (totalBytes != null) result.totalBytes = totalBytes;
    if (maxBytes != null) result.maxBytes = maxBytes;
    if (maxArtifacts != null) result.maxArtifacts = maxArtifacts;
    return result;
  }

  ExtensionCacheState._();

  factory ExtensionCacheState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExtensionCacheState()..mergeFromBuffer(data, registry);
  factory ExtensionCacheState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExtensionCacheState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExtensionCacheState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ExtensionCacheState.$_createMessage)
    ..pPM<CachedExtensionArtifact>(1, _omitFieldNames ? '' : 'artifacts',
        subBuilder: CachedExtensionArtifact.$_createMessage)
    ..aI(2, _omitFieldNames ? '' : 'totalBytes', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'maxBytes', fieldType: $pb.PbFieldType.OU3)
    ..aI(4, _omitFieldNames ? '' : 'maxArtifacts',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExtensionCacheState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExtensionCacheState copyWith(void Function(ExtensionCacheState) updates) =>
      super.copyWith((message) => updates(message as ExtensionCacheState))
          as ExtensionCacheState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ExtensionCacheState() / ExtensionCacheState.new instead')
  static ExtensionCacheState create() => ExtensionCacheState._();
  static $pb.GeneratedMessage $_createMessage() => ExtensionCacheState._();
  @$core.override
  ExtensionCacheState createEmptyInstance() => ExtensionCacheState._();
  @$core.pragma('dart2js:noInline')
  static ExtensionCacheState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExtensionCacheState>(
          ExtensionCacheState.$_createMessage);
  static ExtensionCacheState? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<CachedExtensionArtifact> get artifacts => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get totalBytes => $_getIZ(1);
  @$pb.TagNumber(2)
  set totalBytes($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTotalBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearTotalBytes() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxBytes => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxBytes($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get maxArtifacts => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxArtifacts($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxArtifacts() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxArtifacts() => $_clearField(4);
}

class ForgetExtensionArtifactRequest extends $pb.GeneratedMessage {
  factory ForgetExtensionArtifactRequest({
    $core.String? sha256,
  }) {
    final result = ForgetExtensionArtifactRequest._();
    if (sha256 != null) result.sha256 = sha256;
    return result;
  }

  ForgetExtensionArtifactRequest._();

  factory ForgetExtensionArtifactRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ForgetExtensionArtifactRequest()..mergeFromBuffer(data, registry);
  factory ForgetExtensionArtifactRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ForgetExtensionArtifactRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ForgetExtensionArtifactRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ForgetExtensionArtifactRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sha256')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForgetExtensionArtifactRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ForgetExtensionArtifactRequest copyWith(
          void Function(ForgetExtensionArtifactRequest) updates) =>
      super.copyWith(
              (message) => updates(message as ForgetExtensionArtifactRequest))
          as ForgetExtensionArtifactRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ForgetExtensionArtifactRequest() / ForgetExtensionArtifactRequest.new instead')
  static ForgetExtensionArtifactRequest create() =>
      ForgetExtensionArtifactRequest._();
  static $pb.GeneratedMessage $_createMessage() =>
      ForgetExtensionArtifactRequest._();
  @$core.override
  ForgetExtensionArtifactRequest createEmptyInstance() =>
      ForgetExtensionArtifactRequest._();
  @$core.pragma('dart2js:noInline')
  static ForgetExtensionArtifactRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ForgetExtensionArtifactRequest>(
          ForgetExtensionArtifactRequest.$_createMessage);
  static ForgetExtensionArtifactRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sha256 => $_getSZ(0);
  @$pb.TagNumber(1)
  set sha256($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSha256() => $_has(0);
  @$pb.TagNumber(1)
  void clearSha256() => $_clearField(1);
}

class CloseBuildRequest extends $pb.GeneratedMessage {
  factory CloseBuildRequest({
    $core.String? buildId,
    $core.String? generation,
  }) {
    final result = CloseBuildRequest._();
    if (buildId != null) result.buildId = buildId;
    if (generation != null) result.generation = generation;
    return result;
  }

  CloseBuildRequest._();

  factory CloseBuildRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CloseBuildRequest()..mergeFromBuffer(data, registry);
  factory CloseBuildRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CloseBuildRequest()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CloseBuildRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CloseBuildRequest.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'buildId')
    ..aOS(2, _omitFieldNames ? '' : 'generation')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloseBuildRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CloseBuildRequest copyWith(void Function(CloseBuildRequest) updates) =>
      super.copyWith((message) => updates(message as CloseBuildRequest))
          as CloseBuildRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CloseBuildRequest() / CloseBuildRequest.new instead')
  static CloseBuildRequest create() => CloseBuildRequest._();
  static $pb.GeneratedMessage $_createMessage() => CloseBuildRequest._();
  @$core.override
  CloseBuildRequest createEmptyInstance() => CloseBuildRequest._();
  @$core.pragma('dart2js:noInline')
  static CloseBuildRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CloseBuildRequest>(
          CloseBuildRequest.$_createMessage);
  static CloseBuildRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get buildId => $_getSZ(0);
  @$pb.TagNumber(1)
  set buildId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasBuildId() => $_has(0);
  @$pb.TagNumber(1)
  void clearBuildId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get generation => $_getSZ(1);
  @$pb.TagNumber(2)
  set generation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasGeneration() => $_has(1);
  @$pb.TagNumber(2)
  void clearGeneration() => $_clearField(2);
}

enum ControlRequest_Command {
  ready,
  open,
  invoke,
  cancel,
  acquireImage,
  cancelImage,
  releaseImage,
  closePageSession,
  rebuild,
  fetchApi,
  dispose,
  prepareBuild,
  cancelPreparation,
  extensionCache,
  forgetExtensionArtifact,
  closeBuild,
  notSet
}

class ControlRequest extends $pb.GeneratedMessage {
  factory ControlRequest({
    $core.String? requestId,
    Empty? ready,
    OpenRequest? open,
    SourceCall? invoke,
    CancelSourceRequest? cancel,
    AcquireImage? acquireImage,
    CancelImage? cancelImage,
    ReleaseImage? releaseImage,
    ClosePageSession? closePageSession,
    Empty? rebuild,
    ApiFetchRequest? fetchApi,
    Empty? dispose,
    PrepareBuildRequest? prepareBuild,
    CancelPreparationRequest? cancelPreparation,
    Empty? extensionCache,
    ForgetExtensionArtifactRequest? forgetExtensionArtifact,
    CloseBuildRequest? closeBuild,
  }) {
    final result = ControlRequest._();
    if (requestId != null) result.requestId = requestId;
    if (ready != null) result.ready = ready;
    if (open != null) result.open = open;
    if (invoke != null) result.invoke = invoke;
    if (cancel != null) result.cancel = cancel;
    if (acquireImage != null) result.acquireImage = acquireImage;
    if (cancelImage != null) result.cancelImage = cancelImage;
    if (releaseImage != null) result.releaseImage = releaseImage;
    if (closePageSession != null) result.closePageSession = closePageSession;
    if (rebuild != null) result.rebuild = rebuild;
    if (fetchApi != null) result.fetchApi = fetchApi;
    if (dispose != null) result.dispose = dispose;
    if (prepareBuild != null) result.prepareBuild = prepareBuild;
    if (cancelPreparation != null) result.cancelPreparation = cancelPreparation;
    if (extensionCache != null) result.extensionCache = extensionCache;
    if (forgetExtensionArtifact != null)
      result.forgetExtensionArtifact = forgetExtensionArtifact;
    if (closeBuild != null) result.closeBuild = closeBuild;
    return result;
  }

  ControlRequest._();

  factory ControlRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ControlRequest()..mergeFromBuffer(data, registry);
  factory ControlRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ControlRequest()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ControlRequest_Command>
      _ControlRequest_CommandByTag = {
    10: ControlRequest_Command.ready,
    11: ControlRequest_Command.open,
    12: ControlRequest_Command.invoke,
    13: ControlRequest_Command.cancel,
    14: ControlRequest_Command.acquireImage,
    15: ControlRequest_Command.cancelImage,
    16: ControlRequest_Command.releaseImage,
    17: ControlRequest_Command.closePageSession,
    18: ControlRequest_Command.rebuild,
    19: ControlRequest_Command.fetchApi,
    20: ControlRequest_Command.dispose,
    21: ControlRequest_Command.prepareBuild,
    22: ControlRequest_Command.cancelPreparation,
    23: ControlRequest_Command.extensionCache,
    24: ControlRequest_Command.forgetExtensionArtifact,
    25: ControlRequest_Command.closeBuild,
    0: ControlRequest_Command.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ControlRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ControlRequest.$_createMessage)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25])
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOM<Empty>(10, _omitFieldNames ? '' : 'ready',
        subBuilder: Empty.$_createMessage)
    ..aOM<OpenRequest>(11, _omitFieldNames ? '' : 'open',
        subBuilder: OpenRequest.$_createMessage)
    ..aOM<SourceCall>(12, _omitFieldNames ? '' : 'invoke',
        subBuilder: SourceCall.$_createMessage)
    ..aOM<CancelSourceRequest>(13, _omitFieldNames ? '' : 'cancel',
        subBuilder: CancelSourceRequest.$_createMessage)
    ..aOM<AcquireImage>(14, _omitFieldNames ? '' : 'acquireImage',
        subBuilder: AcquireImage.$_createMessage)
    ..aOM<CancelImage>(15, _omitFieldNames ? '' : 'cancelImage',
        subBuilder: CancelImage.$_createMessage)
    ..aOM<ReleaseImage>(16, _omitFieldNames ? '' : 'releaseImage',
        subBuilder: ReleaseImage.$_createMessage)
    ..aOM<ClosePageSession>(17, _omitFieldNames ? '' : 'closePageSession',
        subBuilder: ClosePageSession.$_createMessage)
    ..aOM<Empty>(18, _omitFieldNames ? '' : 'rebuild',
        subBuilder: Empty.$_createMessage)
    ..aOM<ApiFetchRequest>(19, _omitFieldNames ? '' : 'fetchApi',
        subBuilder: ApiFetchRequest.$_createMessage)
    ..aOM<Empty>(20, _omitFieldNames ? '' : 'dispose',
        subBuilder: Empty.$_createMessage)
    ..aOM<PrepareBuildRequest>(21, _omitFieldNames ? '' : 'prepareBuild',
        subBuilder: PrepareBuildRequest.$_createMessage)
    ..aOM<CancelPreparationRequest>(
        22, _omitFieldNames ? '' : 'cancelPreparation',
        subBuilder: CancelPreparationRequest.$_createMessage)
    ..aOM<Empty>(23, _omitFieldNames ? '' : 'extensionCache',
        subBuilder: Empty.$_createMessage)
    ..aOM<ForgetExtensionArtifactRequest>(
        24, _omitFieldNames ? '' : 'forgetExtensionArtifact',
        subBuilder: ForgetExtensionArtifactRequest.$_createMessage)
    ..aOM<CloseBuildRequest>(25, _omitFieldNames ? '' : 'closeBuild',
        subBuilder: CloseBuildRequest.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ControlRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ControlRequest copyWith(void Function(ControlRequest) updates) =>
      super.copyWith((message) => updates(message as ControlRequest))
          as ControlRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ControlRequest() / ControlRequest.new instead')
  static ControlRequest create() => ControlRequest._();
  static $pb.GeneratedMessage $_createMessage() => ControlRequest._();
  @$core.override
  ControlRequest createEmptyInstance() => ControlRequest._();
  @$core.pragma('dart2js:noInline')
  static ControlRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ControlRequest>(
          ControlRequest.$_createMessage);
  static ControlRequest? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  ControlRequest_Command whichCommand() =>
      _ControlRequest_CommandByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  void clearCommand() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(10)
  Empty get ready => $_getN(1);
  @$pb.TagNumber(10)
  set ready(Empty value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasReady() => $_has(1);
  @$pb.TagNumber(10)
  void clearReady() => $_clearField(10);
  @$pb.TagNumber(10)
  Empty ensureReady() => $_ensure(1);

  @$pb.TagNumber(11)
  OpenRequest get open => $_getN(2);
  @$pb.TagNumber(11)
  set open(OpenRequest value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasOpen() => $_has(2);
  @$pb.TagNumber(11)
  void clearOpen() => $_clearField(11);
  @$pb.TagNumber(11)
  OpenRequest ensureOpen() => $_ensure(2);

  @$pb.TagNumber(12)
  SourceCall get invoke => $_getN(3);
  @$pb.TagNumber(12)
  set invoke(SourceCall value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasInvoke() => $_has(3);
  @$pb.TagNumber(12)
  void clearInvoke() => $_clearField(12);
  @$pb.TagNumber(12)
  SourceCall ensureInvoke() => $_ensure(3);

  @$pb.TagNumber(13)
  CancelSourceRequest get cancel => $_getN(4);
  @$pb.TagNumber(13)
  set cancel(CancelSourceRequest value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasCancel() => $_has(4);
  @$pb.TagNumber(13)
  void clearCancel() => $_clearField(13);
  @$pb.TagNumber(13)
  CancelSourceRequest ensureCancel() => $_ensure(4);

  @$pb.TagNumber(14)
  AcquireImage get acquireImage => $_getN(5);
  @$pb.TagNumber(14)
  set acquireImage(AcquireImage value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasAcquireImage() => $_has(5);
  @$pb.TagNumber(14)
  void clearAcquireImage() => $_clearField(14);
  @$pb.TagNumber(14)
  AcquireImage ensureAcquireImage() => $_ensure(5);

  @$pb.TagNumber(15)
  CancelImage get cancelImage => $_getN(6);
  @$pb.TagNumber(15)
  set cancelImage(CancelImage value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasCancelImage() => $_has(6);
  @$pb.TagNumber(15)
  void clearCancelImage() => $_clearField(15);
  @$pb.TagNumber(15)
  CancelImage ensureCancelImage() => $_ensure(6);

  @$pb.TagNumber(16)
  ReleaseImage get releaseImage => $_getN(7);
  @$pb.TagNumber(16)
  set releaseImage(ReleaseImage value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasReleaseImage() => $_has(7);
  @$pb.TagNumber(16)
  void clearReleaseImage() => $_clearField(16);
  @$pb.TagNumber(16)
  ReleaseImage ensureReleaseImage() => $_ensure(7);

  @$pb.TagNumber(17)
  ClosePageSession get closePageSession => $_getN(8);
  @$pb.TagNumber(17)
  set closePageSession(ClosePageSession value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasClosePageSession() => $_has(8);
  @$pb.TagNumber(17)
  void clearClosePageSession() => $_clearField(17);
  @$pb.TagNumber(17)
  ClosePageSession ensureClosePageSession() => $_ensure(8);

  @$pb.TagNumber(18)
  Empty get rebuild => $_getN(9);
  @$pb.TagNumber(18)
  set rebuild(Empty value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasRebuild() => $_has(9);
  @$pb.TagNumber(18)
  void clearRebuild() => $_clearField(18);
  @$pb.TagNumber(18)
  Empty ensureRebuild() => $_ensure(9);

  @$pb.TagNumber(19)
  ApiFetchRequest get fetchApi => $_getN(10);
  @$pb.TagNumber(19)
  set fetchApi(ApiFetchRequest value) => $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasFetchApi() => $_has(10);
  @$pb.TagNumber(19)
  void clearFetchApi() => $_clearField(19);
  @$pb.TagNumber(19)
  ApiFetchRequest ensureFetchApi() => $_ensure(10);

  @$pb.TagNumber(20)
  Empty get dispose => $_getN(11);
  @$pb.TagNumber(20)
  set dispose(Empty value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasDispose() => $_has(11);
  @$pb.TagNumber(20)
  void clearDispose() => $_clearField(20);
  @$pb.TagNumber(20)
  Empty ensureDispose() => $_ensure(11);

  @$pb.TagNumber(21)
  PrepareBuildRequest get prepareBuild => $_getN(12);
  @$pb.TagNumber(21)
  set prepareBuild(PrepareBuildRequest value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasPrepareBuild() => $_has(12);
  @$pb.TagNumber(21)
  void clearPrepareBuild() => $_clearField(21);
  @$pb.TagNumber(21)
  PrepareBuildRequest ensurePrepareBuild() => $_ensure(12);

  @$pb.TagNumber(22)
  CancelPreparationRequest get cancelPreparation => $_getN(13);
  @$pb.TagNumber(22)
  set cancelPreparation(CancelPreparationRequest value) =>
      $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasCancelPreparation() => $_has(13);
  @$pb.TagNumber(22)
  void clearCancelPreparation() => $_clearField(22);
  @$pb.TagNumber(22)
  CancelPreparationRequest ensureCancelPreparation() => $_ensure(13);

  @$pb.TagNumber(23)
  Empty get extensionCache => $_getN(14);
  @$pb.TagNumber(23)
  set extensionCache(Empty value) => $_setField(23, value);
  @$pb.TagNumber(23)
  $core.bool hasExtensionCache() => $_has(14);
  @$pb.TagNumber(23)
  void clearExtensionCache() => $_clearField(23);
  @$pb.TagNumber(23)
  Empty ensureExtensionCache() => $_ensure(14);

  @$pb.TagNumber(24)
  ForgetExtensionArtifactRequest get forgetExtensionArtifact => $_getN(15);
  @$pb.TagNumber(24)
  set forgetExtensionArtifact(ForgetExtensionArtifactRequest value) =>
      $_setField(24, value);
  @$pb.TagNumber(24)
  $core.bool hasForgetExtensionArtifact() => $_has(15);
  @$pb.TagNumber(24)
  void clearForgetExtensionArtifact() => $_clearField(24);
  @$pb.TagNumber(24)
  ForgetExtensionArtifactRequest ensureForgetExtensionArtifact() =>
      $_ensure(15);

  @$pb.TagNumber(25)
  CloseBuildRequest get closeBuild => $_getN(16);
  @$pb.TagNumber(25)
  set closeBuild(CloseBuildRequest value) => $_setField(25, value);
  @$pb.TagNumber(25)
  $core.bool hasCloseBuild() => $_has(16);
  @$pb.TagNumber(25)
  void clearCloseBuild() => $_clearField(25);
  @$pb.TagNumber(25)
  CloseBuildRequest ensureCloseBuild() => $_ensure(16);
}

enum ControlResponse_Result {
  hello,
  session,
  source,
  image,
  released,
  closed,
  completed,
  api,
  error,
  preparedBuild,
  extensionCache,
  notSet
}

class ControlResponse extends $pb.GeneratedMessage {
  factory ControlResponse({
    $core.String? requestId,
    RuntimeHello? hello,
    RuntimeSession? session,
    SourceResult? source,
    ImageResource? image,
    Released? released,
    Closed? closed,
    Completed? completed,
    ApiFetchResponse? api,
    RuntimeError? error,
    PreparedBuild? preparedBuild,
    ExtensionCacheState? extensionCache,
  }) {
    final result = ControlResponse._();
    if (requestId != null) result.requestId = requestId;
    if (hello != null) result.hello = hello;
    if (session != null) result.session = session;
    if (source != null) result.source = source;
    if (image != null) result.image = image;
    if (released != null) result.released = released;
    if (closed != null) result.closed = closed;
    if (completed != null) result.completed = completed;
    if (api != null) result.api = api;
    if (error != null) result.error = error;
    if (preparedBuild != null) result.preparedBuild = preparedBuild;
    if (extensionCache != null) result.extensionCache = extensionCache;
    return result;
  }

  ControlResponse._();

  factory ControlResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ControlResponse()..mergeFromBuffer(data, registry);
  factory ControlResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ControlResponse()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ControlResponse_Result>
      _ControlResponse_ResultByTag = {
    10: ControlResponse_Result.hello,
    11: ControlResponse_Result.session,
    12: ControlResponse_Result.source,
    13: ControlResponse_Result.image,
    14: ControlResponse_Result.released,
    15: ControlResponse_Result.closed,
    16: ControlResponse_Result.completed,
    17: ControlResponse_Result.api,
    18: ControlResponse_Result.error,
    19: ControlResponse_Result.preparedBuild,
    20: ControlResponse_Result.extensionCache,
    0: ControlResponse_Result.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ControlResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ControlResponse.$_createMessage)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOM<RuntimeHello>(10, _omitFieldNames ? '' : 'hello',
        subBuilder: RuntimeHello.$_createMessage)
    ..aOM<RuntimeSession>(11, _omitFieldNames ? '' : 'session',
        subBuilder: RuntimeSession.$_createMessage)
    ..aOM<SourceResult>(12, _omitFieldNames ? '' : 'source',
        subBuilder: SourceResult.$_createMessage)
    ..aOM<ImageResource>(13, _omitFieldNames ? '' : 'image',
        subBuilder: ImageResource.$_createMessage)
    ..aOM<Released>(14, _omitFieldNames ? '' : 'released',
        subBuilder: Released.$_createMessage)
    ..aOM<Closed>(15, _omitFieldNames ? '' : 'closed',
        subBuilder: Closed.$_createMessage)
    ..aOM<Completed>(16, _omitFieldNames ? '' : 'completed',
        subBuilder: Completed.$_createMessage)
    ..aOM<ApiFetchResponse>(17, _omitFieldNames ? '' : 'api',
        subBuilder: ApiFetchResponse.$_createMessage)
    ..aOM<RuntimeError>(18, _omitFieldNames ? '' : 'error',
        subBuilder: RuntimeError.$_createMessage)
    ..aOM<PreparedBuild>(19, _omitFieldNames ? '' : 'preparedBuild',
        subBuilder: PreparedBuild.$_createMessage)
    ..aOM<ExtensionCacheState>(20, _omitFieldNames ? '' : 'extensionCache',
        subBuilder: ExtensionCacheState.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ControlResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ControlResponse copyWith(void Function(ControlResponse) updates) =>
      super.copyWith((message) => updates(message as ControlResponse))
          as ControlResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ControlResponse() / ControlResponse.new instead')
  static ControlResponse create() => ControlResponse._();
  static $pb.GeneratedMessage $_createMessage() => ControlResponse._();
  @$core.override
  ControlResponse createEmptyInstance() => ControlResponse._();
  @$core.pragma('dart2js:noInline')
  static ControlResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ControlResponse>(
          ControlResponse.$_createMessage);
  static ControlResponse? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  ControlResponse_Result whichResult() =>
      _ControlResponse_ResultByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  void clearResult() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(10)
  RuntimeHello get hello => $_getN(1);
  @$pb.TagNumber(10)
  set hello(RuntimeHello value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasHello() => $_has(1);
  @$pb.TagNumber(10)
  void clearHello() => $_clearField(10);
  @$pb.TagNumber(10)
  RuntimeHello ensureHello() => $_ensure(1);

  @$pb.TagNumber(11)
  RuntimeSession get session => $_getN(2);
  @$pb.TagNumber(11)
  set session(RuntimeSession value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasSession() => $_has(2);
  @$pb.TagNumber(11)
  void clearSession() => $_clearField(11);
  @$pb.TagNumber(11)
  RuntimeSession ensureSession() => $_ensure(2);

  @$pb.TagNumber(12)
  SourceResult get source => $_getN(3);
  @$pb.TagNumber(12)
  set source(SourceResult value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasSource() => $_has(3);
  @$pb.TagNumber(12)
  void clearSource() => $_clearField(12);
  @$pb.TagNumber(12)
  SourceResult ensureSource() => $_ensure(3);

  @$pb.TagNumber(13)
  ImageResource get image => $_getN(4);
  @$pb.TagNumber(13)
  set image(ImageResource value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasImage() => $_has(4);
  @$pb.TagNumber(13)
  void clearImage() => $_clearField(13);
  @$pb.TagNumber(13)
  ImageResource ensureImage() => $_ensure(4);

  @$pb.TagNumber(14)
  Released get released => $_getN(5);
  @$pb.TagNumber(14)
  set released(Released value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasReleased() => $_has(5);
  @$pb.TagNumber(14)
  void clearReleased() => $_clearField(14);
  @$pb.TagNumber(14)
  Released ensureReleased() => $_ensure(5);

  @$pb.TagNumber(15)
  Closed get closed => $_getN(6);
  @$pb.TagNumber(15)
  set closed(Closed value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasClosed() => $_has(6);
  @$pb.TagNumber(15)
  void clearClosed() => $_clearField(15);
  @$pb.TagNumber(15)
  Closed ensureClosed() => $_ensure(6);

  @$pb.TagNumber(16)
  Completed get completed => $_getN(7);
  @$pb.TagNumber(16)
  set completed(Completed value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasCompleted() => $_has(7);
  @$pb.TagNumber(16)
  void clearCompleted() => $_clearField(16);
  @$pb.TagNumber(16)
  Completed ensureCompleted() => $_ensure(7);

  @$pb.TagNumber(17)
  ApiFetchResponse get api => $_getN(8);
  @$pb.TagNumber(17)
  set api(ApiFetchResponse value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasApi() => $_has(8);
  @$pb.TagNumber(17)
  void clearApi() => $_clearField(17);
  @$pb.TagNumber(17)
  ApiFetchResponse ensureApi() => $_ensure(8);

  @$pb.TagNumber(18)
  RuntimeError get error => $_getN(9);
  @$pb.TagNumber(18)
  set error(RuntimeError value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasError() => $_has(9);
  @$pb.TagNumber(18)
  void clearError() => $_clearField(18);
  @$pb.TagNumber(18)
  RuntimeError ensureError() => $_ensure(9);

  @$pb.TagNumber(19)
  PreparedBuild get preparedBuild => $_getN(10);
  @$pb.TagNumber(19)
  set preparedBuild(PreparedBuild value) => $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasPreparedBuild() => $_has(10);
  @$pb.TagNumber(19)
  void clearPreparedBuild() => $_clearField(19);
  @$pb.TagNumber(19)
  PreparedBuild ensurePreparedBuild() => $_ensure(10);

  @$pb.TagNumber(20)
  ExtensionCacheState get extensionCache => $_getN(11);
  @$pb.TagNumber(20)
  set extensionCache(ExtensionCacheState value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasExtensionCache() => $_has(11);
  @$pb.TagNumber(20)
  void clearExtensionCache() => $_clearField(20);
  @$pb.TagNumber(20)
  ExtensionCacheState ensureExtensionCache() => $_ensure(11);
}

class OpenWorker extends $pb.GeneratedMessage {
  factory OpenWorker({
    BuildManifest? manifest,
    $core.String? userAgent,
    PreferenceBootstrap? preferenceBootstrap,
    CatalogReference? catalog,
  }) {
    final result = OpenWorker._();
    if (manifest != null) result.manifest = manifest;
    if (userAgent != null) result.userAgent = userAgent;
    if (preferenceBootstrap != null)
      result.preferenceBootstrap = preferenceBootstrap;
    if (catalog != null) result.catalog = catalog;
    return result;
  }

  OpenWorker._();

  factory OpenWorker.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenWorker()..mergeFromBuffer(data, registry);
  factory OpenWorker.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      OpenWorker()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OpenWorker',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: OpenWorker.$_createMessage)
    ..aOM<BuildManifest>(1, _omitFieldNames ? '' : 'manifest',
        subBuilder: BuildManifest.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'userAgent')
    ..aOM<PreferenceBootstrap>(3, _omitFieldNames ? '' : 'preferenceBootstrap',
        subBuilder: PreferenceBootstrap.$_createMessage)
    ..aOM<CatalogReference>(4, _omitFieldNames ? '' : 'catalog',
        subBuilder: CatalogReference.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenWorker clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OpenWorker copyWith(void Function(OpenWorker) updates) =>
      super.copyWith((message) => updates(message as OpenWorker)) as OpenWorker;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use OpenWorker() / OpenWorker.new instead')
  static OpenWorker create() => OpenWorker._();
  static $pb.GeneratedMessage $_createMessage() => OpenWorker._();
  @$core.override
  OpenWorker createEmptyInstance() => OpenWorker._();
  @$core.pragma('dart2js:noInline')
  static OpenWorker getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OpenWorker>(OpenWorker.$_createMessage);
  static OpenWorker? _defaultInstance;

  @$pb.TagNumber(1)
  BuildManifest get manifest => $_getN(0);
  @$pb.TagNumber(1)
  set manifest(BuildManifest value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasManifest() => $_has(0);
  @$pb.TagNumber(1)
  void clearManifest() => $_clearField(1);
  @$pb.TagNumber(1)
  BuildManifest ensureManifest() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get userAgent => $_getSZ(1);
  @$pb.TagNumber(2)
  set userAgent($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUserAgent() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserAgent() => $_clearField(2);

  @$pb.TagNumber(3)
  PreferenceBootstrap get preferenceBootstrap => $_getN(2);
  @$pb.TagNumber(3)
  set preferenceBootstrap(PreferenceBootstrap value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPreferenceBootstrap() => $_has(2);
  @$pb.TagNumber(3)
  void clearPreferenceBootstrap() => $_clearField(3);
  @$pb.TagNumber(3)
  PreferenceBootstrap ensurePreferenceBootstrap() => $_ensure(2);

  @$pb.TagNumber(4)
  CatalogReference get catalog => $_getN(3);
  @$pb.TagNumber(4)
  set catalog(CatalogReference value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCatalog() => $_has(3);
  @$pb.TagNumber(4)
  void clearCatalog() => $_clearField(4);
  @$pb.TagNumber(4)
  CatalogReference ensureCatalog() => $_ensure(3);
}

class AcquireImageWorker extends $pb.GeneratedMessage {
  factory AcquireImageWorker({
    AcquireImage? request,
    $core.String? resourceId,
  }) {
    final result = AcquireImageWorker._();
    if (request != null) result.request = request;
    if (resourceId != null) result.resourceId = resourceId;
    return result;
  }

  AcquireImageWorker._();

  factory AcquireImageWorker.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AcquireImageWorker()..mergeFromBuffer(data, registry);
  factory AcquireImageWorker.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      AcquireImageWorker()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AcquireImageWorker',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: AcquireImageWorker.$_createMessage)
    ..aOM<AcquireImage>(1, _omitFieldNames ? '' : 'request',
        subBuilder: AcquireImage.$_createMessage)
    ..aOS(2, _omitFieldNames ? '' : 'resourceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcquireImageWorker clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AcquireImageWorker copyWith(void Function(AcquireImageWorker) updates) =>
      super.copyWith((message) => updates(message as AcquireImageWorker))
          as AcquireImageWorker;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use AcquireImageWorker() / AcquireImageWorker.new instead')
  static AcquireImageWorker create() => AcquireImageWorker._();
  static $pb.GeneratedMessage $_createMessage() => AcquireImageWorker._();
  @$core.override
  AcquireImageWorker createEmptyInstance() => AcquireImageWorker._();
  @$core.pragma('dart2js:noInline')
  static AcquireImageWorker getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AcquireImageWorker>(
          AcquireImageWorker.$_createMessage);
  static AcquireImageWorker? _defaultInstance;

  @$pb.TagNumber(1)
  AcquireImage get request => $_getN(0);
  @$pb.TagNumber(1)
  set request(AcquireImage value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRequest() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequest() => $_clearField(1);
  @$pb.TagNumber(1)
  AcquireImage ensureRequest() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get resourceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set resourceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasResourceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearResourceId() => $_clearField(2);
}

enum WorkerCommand_Command {
  open,
  invoke,
  acquireImage,
  closePageSession,
  shutdown,
  notSet
}

class WorkerCommand extends $pb.GeneratedMessage {
  factory WorkerCommand({
    RpcEnvelope? envelope,
    OpenWorker? open,
    SourceCall? invoke,
    AcquireImageWorker? acquireImage,
    ClosePageSession? closePageSession,
    Empty? shutdown,
  }) {
    final result = WorkerCommand._();
    if (envelope != null) result.envelope = envelope;
    if (open != null) result.open = open;
    if (invoke != null) result.invoke = invoke;
    if (acquireImage != null) result.acquireImage = acquireImage;
    if (closePageSession != null) result.closePageSession = closePageSession;
    if (shutdown != null) result.shutdown = shutdown;
    return result;
  }

  WorkerCommand._();

  factory WorkerCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WorkerCommand()..mergeFromBuffer(data, registry);
  factory WorkerCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WorkerCommand()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, WorkerCommand_Command>
      _WorkerCommand_CommandByTag = {
    10: WorkerCommand_Command.open,
    11: WorkerCommand_Command.invoke,
    12: WorkerCommand_Command.acquireImage,
    13: WorkerCommand_Command.closePageSession,
    14: WorkerCommand_Command.shutdown,
    0: WorkerCommand_Command.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WorkerCommand',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: WorkerCommand.$_createMessage)
    ..oo(0, [10, 11, 12, 13, 14])
    ..aOM<RpcEnvelope>(1, _omitFieldNames ? '' : 'envelope',
        subBuilder: RpcEnvelope.$_createMessage)
    ..aOM<OpenWorker>(10, _omitFieldNames ? '' : 'open',
        subBuilder: OpenWorker.$_createMessage)
    ..aOM<SourceCall>(11, _omitFieldNames ? '' : 'invoke',
        subBuilder: SourceCall.$_createMessage)
    ..aOM<AcquireImageWorker>(12, _omitFieldNames ? '' : 'acquireImage',
        subBuilder: AcquireImageWorker.$_createMessage)
    ..aOM<ClosePageSession>(13, _omitFieldNames ? '' : 'closePageSession',
        subBuilder: ClosePageSession.$_createMessage)
    ..aOM<Empty>(14, _omitFieldNames ? '' : 'shutdown',
        subBuilder: Empty.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WorkerCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WorkerCommand copyWith(void Function(WorkerCommand) updates) =>
      super.copyWith((message) => updates(message as WorkerCommand))
          as WorkerCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WorkerCommand() / WorkerCommand.new instead')
  static WorkerCommand create() => WorkerCommand._();
  static $pb.GeneratedMessage $_createMessage() => WorkerCommand._();
  @$core.override
  WorkerCommand createEmptyInstance() => WorkerCommand._();
  @$core.pragma('dart2js:noInline')
  static WorkerCommand getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WorkerCommand>(
          WorkerCommand.$_createMessage);
  static WorkerCommand? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  WorkerCommand_Command whichCommand() =>
      _WorkerCommand_CommandByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  void clearCommand() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  RpcEnvelope get envelope => $_getN(0);
  @$pb.TagNumber(1)
  set envelope(RpcEnvelope value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEnvelope() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnvelope() => $_clearField(1);
  @$pb.TagNumber(1)
  RpcEnvelope ensureEnvelope() => $_ensure(0);

  @$pb.TagNumber(10)
  OpenWorker get open => $_getN(1);
  @$pb.TagNumber(10)
  set open(OpenWorker value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasOpen() => $_has(1);
  @$pb.TagNumber(10)
  void clearOpen() => $_clearField(10);
  @$pb.TagNumber(10)
  OpenWorker ensureOpen() => $_ensure(1);

  @$pb.TagNumber(11)
  SourceCall get invoke => $_getN(2);
  @$pb.TagNumber(11)
  set invoke(SourceCall value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasInvoke() => $_has(2);
  @$pb.TagNumber(11)
  void clearInvoke() => $_clearField(11);
  @$pb.TagNumber(11)
  SourceCall ensureInvoke() => $_ensure(2);

  @$pb.TagNumber(12)
  AcquireImageWorker get acquireImage => $_getN(3);
  @$pb.TagNumber(12)
  set acquireImage(AcquireImageWorker value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasAcquireImage() => $_has(3);
  @$pb.TagNumber(12)
  void clearAcquireImage() => $_clearField(12);
  @$pb.TagNumber(12)
  AcquireImageWorker ensureAcquireImage() => $_ensure(3);

  @$pb.TagNumber(13)
  ClosePageSession get closePageSession => $_getN(4);
  @$pb.TagNumber(13)
  set closePageSession(ClosePageSession value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasClosePageSession() => $_has(4);
  @$pb.TagNumber(13)
  void clearClosePageSession() => $_clearField(13);
  @$pb.TagNumber(13)
  ClosePageSession ensureClosePageSession() => $_ensure(4);

  @$pb.TagNumber(14)
  Empty get shutdown => $_getN(5);
  @$pb.TagNumber(14)
  set shutdown(Empty value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasShutdown() => $_has(5);
  @$pb.TagNumber(14)
  void clearShutdown() => $_clearField(14);
  @$pb.TagNumber(14)
  Empty ensureShutdown() => $_ensure(5);
}

enum WorkerResponse_Result { session, source, image, closed, error, notSet }

class WorkerResponse extends $pb.GeneratedMessage {
  factory WorkerResponse({
    RpcEnvelope? envelope,
    RuntimeSession? session,
    SourceResult? source,
    ProcessedImage? image,
    Closed? closed,
    RuntimeError? error,
  }) {
    final result = WorkerResponse._();
    if (envelope != null) result.envelope = envelope;
    if (session != null) result.session = session;
    if (source != null) result.source = source;
    if (image != null) result.image = image;
    if (closed != null) result.closed = closed;
    if (error != null) result.error = error;
    return result;
  }

  WorkerResponse._();

  factory WorkerResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WorkerResponse()..mergeFromBuffer(data, registry);
  factory WorkerResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      WorkerResponse()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, WorkerResponse_Result>
      _WorkerResponse_ResultByTag = {
    10: WorkerResponse_Result.session,
    11: WorkerResponse_Result.source,
    12: WorkerResponse_Result.image,
    13: WorkerResponse_Result.closed,
    14: WorkerResponse_Result.error,
    0: WorkerResponse_Result.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WorkerResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: WorkerResponse.$_createMessage)
    ..oo(0, [10, 11, 12, 13, 14])
    ..aOM<RpcEnvelope>(1, _omitFieldNames ? '' : 'envelope',
        subBuilder: RpcEnvelope.$_createMessage)
    ..aOM<RuntimeSession>(10, _omitFieldNames ? '' : 'session',
        subBuilder: RuntimeSession.$_createMessage)
    ..aOM<SourceResult>(11, _omitFieldNames ? '' : 'source',
        subBuilder: SourceResult.$_createMessage)
    ..aOM<ProcessedImage>(12, _omitFieldNames ? '' : 'image',
        subBuilder: ProcessedImage.$_createMessage)
    ..aOM<Closed>(13, _omitFieldNames ? '' : 'closed',
        subBuilder: Closed.$_createMessage)
    ..aOM<RuntimeError>(14, _omitFieldNames ? '' : 'error',
        subBuilder: RuntimeError.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WorkerResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WorkerResponse copyWith(void Function(WorkerResponse) updates) =>
      super.copyWith((message) => updates(message as WorkerResponse))
          as WorkerResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use WorkerResponse() / WorkerResponse.new instead')
  static WorkerResponse create() => WorkerResponse._();
  static $pb.GeneratedMessage $_createMessage() => WorkerResponse._();
  @$core.override
  WorkerResponse createEmptyInstance() => WorkerResponse._();
  @$core.pragma('dart2js:noInline')
  static WorkerResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WorkerResponse>(
          WorkerResponse.$_createMessage);
  static WorkerResponse? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  WorkerResponse_Result whichResult() =>
      _WorkerResponse_ResultByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  void clearResult() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  RpcEnvelope get envelope => $_getN(0);
  @$pb.TagNumber(1)
  set envelope(RpcEnvelope value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEnvelope() => $_has(0);
  @$pb.TagNumber(1)
  void clearEnvelope() => $_clearField(1);
  @$pb.TagNumber(1)
  RpcEnvelope ensureEnvelope() => $_ensure(0);

  @$pb.TagNumber(10)
  RuntimeSession get session => $_getN(1);
  @$pb.TagNumber(10)
  set session(RuntimeSession value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasSession() => $_has(1);
  @$pb.TagNumber(10)
  void clearSession() => $_clearField(10);
  @$pb.TagNumber(10)
  RuntimeSession ensureSession() => $_ensure(1);

  @$pb.TagNumber(11)
  SourceResult get source => $_getN(2);
  @$pb.TagNumber(11)
  set source(SourceResult value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasSource() => $_has(2);
  @$pb.TagNumber(11)
  void clearSource() => $_clearField(11);
  @$pb.TagNumber(11)
  SourceResult ensureSource() => $_ensure(2);

  @$pb.TagNumber(12)
  ProcessedImage get image => $_getN(3);
  @$pb.TagNumber(12)
  set image(ProcessedImage value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasImage() => $_has(3);
  @$pb.TagNumber(12)
  void clearImage() => $_clearField(12);
  @$pb.TagNumber(12)
  ProcessedImage ensureImage() => $_ensure(3);

  @$pb.TagNumber(13)
  Closed get closed => $_getN(4);
  @$pb.TagNumber(13)
  set closed(Closed value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasClosed() => $_has(4);
  @$pb.TagNumber(13)
  void clearClosed() => $_clearField(13);
  @$pb.TagNumber(13)
  Closed ensureClosed() => $_ensure(4);

  @$pb.TagNumber(14)
  RuntimeError get error => $_getN(5);
  @$pb.TagNumber(14)
  set error(RuntimeError value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(14)
  void clearError() => $_clearField(14);
  @$pb.TagNumber(14)
  RuntimeError ensureError() => $_ensure(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
