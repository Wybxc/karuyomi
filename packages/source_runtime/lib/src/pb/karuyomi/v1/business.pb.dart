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

import 'business.pbenum.dart';
import 'control.pb.dart' as $0;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'business.pbenum.dart';

/// Server-owned, account-scoped business state. Authentication is supplied by
/// the API transport, never by an identity field in the request body.
class LibraryMetadata extends $pb.GeneratedMessage {
  factory LibraryMetadata({
    $core.String? packageName,
    $core.String? sourceId,
    $core.String? sourceName,
    $core.String? sourceLang,
    $0.Manga? manga,
  }) {
    final result = LibraryMetadata._();
    if (packageName != null) result.packageName = packageName;
    if (sourceId != null) result.sourceId = sourceId;
    if (sourceName != null) result.sourceName = sourceName;
    if (sourceLang != null) result.sourceLang = sourceLang;
    if (manga != null) result.manga = manga;
    return result;
  }

  LibraryMetadata._();

  factory LibraryMetadata.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LibraryMetadata()..mergeFromBuffer(data, registry);
  factory LibraryMetadata.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LibraryMetadata()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LibraryMetadata',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: LibraryMetadata.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'packageName')
    ..aOS(2, _omitFieldNames ? '' : 'sourceId')
    ..aOS(3, _omitFieldNames ? '' : 'sourceName')
    ..aOS(4, _omitFieldNames ? '' : 'sourceLang')
    ..aOM<$0.Manga>(5, _omitFieldNames ? '' : 'manga',
        subBuilder: $0.Manga.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LibraryMetadata clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LibraryMetadata copyWith(void Function(LibraryMetadata) updates) =>
      super.copyWith((message) => updates(message as LibraryMetadata))
          as LibraryMetadata;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use LibraryMetadata() / LibraryMetadata.new instead')
  static LibraryMetadata create() => LibraryMetadata._();
  static $pb.GeneratedMessage $_createMessage() => LibraryMetadata._();
  @$core.override
  LibraryMetadata createEmptyInstance() => LibraryMetadata._();
  @$core.pragma('dart2js:noInline')
  static LibraryMetadata getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LibraryMetadata>(
          LibraryMetadata.$_createMessage);
  static LibraryMetadata? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get packageName => $_getSZ(0);
  @$pb.TagNumber(1)
  set packageName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPackageName() => $_has(0);
  @$pb.TagNumber(1)
  void clearPackageName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sourceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSourceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get sourceName => $_getSZ(2);
  @$pb.TagNumber(3)
  set sourceName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSourceName() => $_has(2);
  @$pb.TagNumber(3)
  void clearSourceName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get sourceLang => $_getSZ(3);
  @$pb.TagNumber(4)
  set sourceLang($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSourceLang() => $_has(3);
  @$pb.TagNumber(4)
  void clearSourceLang() => $_clearField(4);

  @$pb.TagNumber(5)
  $0.Manga get manga => $_getN(4);
  @$pb.TagNumber(5)
  set manga($0.Manga value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasManga() => $_has(4);
  @$pb.TagNumber(5)
  void clearManga() => $_clearField(5);
  @$pb.TagNumber(5)
  $0.Manga ensureManga() => $_ensure(4);
}

class MangaResume extends $pb.GeneratedMessage {
  factory MangaResume({
    $core.String? chapterKey,
    $core.bool? reversedOrder,
  }) {
    final result = MangaResume._();
    if (chapterKey != null) result.chapterKey = chapterKey;
    if (reversedOrder != null) result.reversedOrder = reversedOrder;
    return result;
  }

  MangaResume._();

  factory MangaResume.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaResume()..mergeFromBuffer(data, registry);
  factory MangaResume.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaResume()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MangaResume',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: MangaResume.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'chapterKey')
    ..aOB(2, _omitFieldNames ? '' : 'reversedOrder')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaResume clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaResume copyWith(void Function(MangaResume) updates) =>
      super.copyWith((message) => updates(message as MangaResume))
          as MangaResume;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MangaResume() / MangaResume.new instead')
  static MangaResume create() => MangaResume._();
  static $pb.GeneratedMessage $_createMessage() => MangaResume._();
  @$core.override
  MangaResume createEmptyInstance() => MangaResume._();
  @$core.pragma('dart2js:noInline')
  static MangaResume getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MangaResume>(
          MangaResume.$_createMessage);
  static MangaResume? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chapterKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set chapterKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChapterKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearChapterKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get reversedOrder => $_getBF(1);
  @$pb.TagNumber(2)
  set reversedOrder($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReversedOrder() => $_has(1);
  @$pb.TagNumber(2)
  void clearReversedOrder() => $_clearField(2);
}

class CustomCover extends $pb.GeneratedMessage {
  factory CustomCover({
    $core.String? assetId,
    $core.String? contentType,
    $core.int? byteLength,
    $core.String? sha256,
  }) {
    final result = CustomCover._();
    if (assetId != null) result.assetId = assetId;
    if (contentType != null) result.contentType = contentType;
    if (byteLength != null) result.byteLength = byteLength;
    if (sha256 != null) result.sha256 = sha256;
    return result;
  }

  CustomCover._();

  factory CustomCover.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CustomCover()..mergeFromBuffer(data, registry);
  factory CustomCover.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CustomCover()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CustomCover',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CustomCover.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'assetId')
    ..aOS(2, _omitFieldNames ? '' : 'contentType')
    ..aI(3, _omitFieldNames ? '' : 'byteLength', fieldType: $pb.PbFieldType.OU3)
    ..aOS(4, _omitFieldNames ? '' : 'sha256')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CustomCover clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CustomCover copyWith(void Function(CustomCover) updates) =>
      super.copyWith((message) => updates(message as CustomCover))
          as CustomCover;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CustomCover() / CustomCover.new instead')
  static CustomCover create() => CustomCover._();
  static $pb.GeneratedMessage $_createMessage() => CustomCover._();
  @$core.override
  CustomCover createEmptyInstance() => CustomCover._();
  @$core.pragma('dart2js:noInline')
  static CustomCover getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CustomCover>(
          CustomCover.$_createMessage);
  static CustomCover? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get assetId => $_getSZ(0);
  @$pb.TagNumber(1)
  set assetId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAssetId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAssetId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get contentType => $_getSZ(1);
  @$pb.TagNumber(2)
  set contentType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasContentType() => $_has(1);
  @$pb.TagNumber(2)
  void clearContentType() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get byteLength => $_getIZ(2);
  @$pb.TagNumber(3)
  set byteLength($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasByteLength() => $_has(2);
  @$pb.TagNumber(3)
  void clearByteLength() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get sha256 => $_getSZ(3);
  @$pb.TagNumber(4)
  set sha256($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSha256() => $_has(3);
  @$pb.TagNumber(4)
  void clearSha256() => $_clearField(4);
}

class SetCustomCover extends $pb.GeneratedMessage {
  factory SetCustomCover({
    CustomCover? cover,
  }) {
    final result = SetCustomCover._();
    if (cover != null) result.cover = cover;
    return result;
  }

  SetCustomCover._();

  factory SetCustomCover.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCustomCover()..mergeFromBuffer(data, registry);
  factory SetCustomCover.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCustomCover()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetCustomCover',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SetCustomCover.$_createMessage)
    ..aOM<CustomCover>(1, _omitFieldNames ? '' : 'cover',
        subBuilder: CustomCover.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCustomCover clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCustomCover copyWith(void Function(SetCustomCover) updates) =>
      super.copyWith((message) => updates(message as SetCustomCover))
          as SetCustomCover;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetCustomCover() / SetCustomCover.new instead')
  static SetCustomCover create() => SetCustomCover._();
  static $pb.GeneratedMessage $_createMessage() => SetCustomCover._();
  @$core.override
  SetCustomCover createEmptyInstance() => SetCustomCover._();
  @$core.pragma('dart2js:noInline')
  static SetCustomCover getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetCustomCover>(
          SetCustomCover.$_createMessage);
  static SetCustomCover? _defaultInstance;

  /// Missing cover clears the current custom cover.
  @$pb.TagNumber(1)
  CustomCover get cover => $_getN(0);
  @$pb.TagNumber(1)
  set cover(CustomCover value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCover() => $_has(0);
  @$pb.TagNumber(1)
  void clearCover() => $_clearField(1);
  @$pb.TagNumber(1)
  CustomCover ensureCover() => $_ensure(0);
}

class MangaState extends $pb.GeneratedMessage {
  factory MangaState({
    $core.String? mangaKey,
    $core.int? revision,
    LibraryMetadata? metadata,
    $core.bool? favorite,
    $core.int? addedAtSeconds,
    MangaResume? resume,
    $core.Iterable<$core.String>? categoryIds,
    CustomCover? customCover,
  }) {
    final result = MangaState._();
    if (mangaKey != null) result.mangaKey = mangaKey;
    if (revision != null) result.revision = revision;
    if (metadata != null) result.metadata = metadata;
    if (favorite != null) result.favorite = favorite;
    if (addedAtSeconds != null) result.addedAtSeconds = addedAtSeconds;
    if (resume != null) result.resume = resume;
    if (categoryIds != null) result.categoryIds.addAll(categoryIds);
    if (customCover != null) result.customCover = customCover;
    return result;
  }

  MangaState._();

  factory MangaState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaState()..mergeFromBuffer(data, registry);
  factory MangaState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MangaState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: MangaState.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'mangaKey')
    ..aI(2, _omitFieldNames ? '' : 'revision', fieldType: $pb.PbFieldType.OU3)
    ..aOM<LibraryMetadata>(3, _omitFieldNames ? '' : 'metadata',
        subBuilder: LibraryMetadata.$_createMessage)
    ..aOB(4, _omitFieldNames ? '' : 'favorite')
    ..aI(5, _omitFieldNames ? '' : 'addedAtSeconds',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<MangaResume>(6, _omitFieldNames ? '' : 'resume',
        subBuilder: MangaResume.$_createMessage)
    ..pPS(7, _omitFieldNames ? '' : 'categoryIds')
    ..aOM<CustomCover>(8, _omitFieldNames ? '' : 'customCover',
        subBuilder: CustomCover.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaState copyWith(void Function(MangaState) updates) =>
      super.copyWith((message) => updates(message as MangaState)) as MangaState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MangaState() / MangaState.new instead')
  static MangaState create() => MangaState._();
  static $pb.GeneratedMessage $_createMessage() => MangaState._();
  @$core.override
  MangaState createEmptyInstance() => MangaState._();
  @$core.pragma('dart2js:noInline')
  static MangaState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MangaState>(MangaState.$_createMessage);
  static MangaState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mangaKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set mangaKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMangaKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearMangaKey() => $_clearField(1);

  /// Covers every metadata, favorite, category, bookmark, progress and resume mutation.
  @$pb.TagNumber(2)
  $core.int get revision => $_getIZ(1);
  @$pb.TagNumber(2)
  set revision($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  LibraryMetadata get metadata => $_getN(2);
  @$pb.TagNumber(3)
  set metadata(LibraryMetadata value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasMetadata() => $_has(2);
  @$pb.TagNumber(3)
  void clearMetadata() => $_clearField(3);
  @$pb.TagNumber(3)
  LibraryMetadata ensureMetadata() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.bool get favorite => $_getBF(3);
  @$pb.TagNumber(4)
  set favorite($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasFavorite() => $_has(3);
  @$pb.TagNumber(4)
  void clearFavorite() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get addedAtSeconds => $_getIZ(4);
  @$pb.TagNumber(5)
  set addedAtSeconds($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAddedAtSeconds() => $_has(4);
  @$pb.TagNumber(5)
  void clearAddedAtSeconds() => $_clearField(5);

  @$pb.TagNumber(6)
  MangaResume get resume => $_getN(5);
  @$pb.TagNumber(6)
  set resume(MangaResume value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasResume() => $_has(5);
  @$pb.TagNumber(6)
  void clearResume() => $_clearField(6);
  @$pb.TagNumber(6)
  MangaResume ensureResume() => $_ensure(5);

  @$pb.TagNumber(7)
  $pb.PbList<$core.String> get categoryIds => $_getList(6);

  @$pb.TagNumber(8)
  CustomCover get customCover => $_getN(7);
  @$pb.TagNumber(8)
  set customCover(CustomCover value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasCustomCover() => $_has(7);
  @$pb.TagNumber(8)
  void clearCustomCover() => $_clearField(8);
  @$pb.TagNumber(8)
  CustomCover ensureCustomCover() => $_ensure(7);
}

class Category extends $pb.GeneratedMessage {
  factory Category({
    $core.String? id,
    $core.String? name,
  }) {
    final result = Category._();
    if (id != null) result.id = id;
    if (name != null) result.name = name;
    return result;
  }

  Category._();

  factory Category.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Category()..mergeFromBuffer(data, registry);
  factory Category.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Category()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Category',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: Category.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Category clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Category copyWith(void Function(Category) updates) =>
      super.copyWith((message) => updates(message as Category)) as Category;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Category() / Category.new instead')
  static Category create() => Category._();
  static $pb.GeneratedMessage $_createMessage() => Category._();
  @$core.override
  Category createEmptyInstance() => Category._();
  @$core.pragma('dart2js:noInline')
  static Category getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Category>(Category.$_createMessage);
  static Category? _defaultInstance;

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
}

class CategoryCatalog extends $pb.GeneratedMessage {
  factory CategoryCatalog({
    $core.int? revision,
    $core.Iterable<Category>? categories,
  }) {
    final result = CategoryCatalog._();
    if (revision != null) result.revision = revision;
    if (categories != null) result.categories.addAll(categories);
    return result;
  }

  CategoryCatalog._();

  factory CategoryCatalog.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CategoryCatalog()..mergeFromBuffer(data, registry);
  factory CategoryCatalog.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CategoryCatalog()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CategoryCatalog',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CategoryCatalog.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'revision', fieldType: $pb.PbFieldType.OU3)
    ..pPM<Category>(2, _omitFieldNames ? '' : 'categories',
        subBuilder: Category.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategoryCatalog clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategoryCatalog copyWith(void Function(CategoryCatalog) updates) =>
      super.copyWith((message) => updates(message as CategoryCatalog))
          as CategoryCatalog;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CategoryCatalog() / CategoryCatalog.new instead')
  static CategoryCatalog create() => CategoryCatalog._();
  static $pb.GeneratedMessage $_createMessage() => CategoryCatalog._();
  @$core.override
  CategoryCatalog createEmptyInstance() => CategoryCatalog._();
  @$core.pragma('dart2js:noInline')
  static CategoryCatalog getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CategoryCatalog>(
          CategoryCatalog.$_createMessage);
  static CategoryCatalog? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get revision => $_getIZ(0);
  @$pb.TagNumber(1)
  set revision($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRevision() => $_has(0);
  @$pb.TagNumber(1)
  void clearRevision() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<Category> get categories => $_getList(1);
}

class SetCategories extends $pb.GeneratedMessage {
  factory SetCategories({
    $core.Iterable<$core.String>? categoryIds,
    $core.int? expectedCatalogRevision,
  }) {
    final result = SetCategories._();
    if (categoryIds != null) result.categoryIds.addAll(categoryIds);
    if (expectedCatalogRevision != null)
      result.expectedCatalogRevision = expectedCatalogRevision;
    return result;
  }

  SetCategories._();

  factory SetCategories.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCategories()..mergeFromBuffer(data, registry);
  factory SetCategories.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetCategories()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetCategories',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SetCategories.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'categoryIds')
    ..aI(2, _omitFieldNames ? '' : 'expectedCatalogRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCategories clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetCategories copyWith(void Function(SetCategories) updates) =>
      super.copyWith((message) => updates(message as SetCategories))
          as SetCategories;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetCategories() / SetCategories.new instead')
  static SetCategories create() => SetCategories._();
  static $pb.GeneratedMessage $_createMessage() => SetCategories._();
  @$core.override
  SetCategories createEmptyInstance() => SetCategories._();
  @$core.pragma('dart2js:noInline')
  static SetCategories getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetCategories>(
          SetCategories.$_createMessage);
  static SetCategories? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get categoryIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get expectedCatalogRevision => $_getIZ(1);
  @$pb.TagNumber(2)
  set expectedCatalogRevision($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasExpectedCatalogRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpectedCatalogRevision() => $_clearField(2);
}

class CreateCategory extends $pb.GeneratedMessage {
  factory CreateCategory({
    Category? category,
  }) {
    final result = CreateCategory._();
    if (category != null) result.category = category;
    return result;
  }

  CreateCategory._();

  factory CreateCategory.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateCategory()..mergeFromBuffer(data, registry);
  factory CreateCategory.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CreateCategory()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateCategory',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CreateCategory.$_createMessage)
    ..aOM<Category>(1, _omitFieldNames ? '' : 'category',
        subBuilder: Category.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateCategory clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateCategory copyWith(void Function(CreateCategory) updates) =>
      super.copyWith((message) => updates(message as CreateCategory))
          as CreateCategory;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CreateCategory() / CreateCategory.new instead')
  static CreateCategory create() => CreateCategory._();
  static $pb.GeneratedMessage $_createMessage() => CreateCategory._();
  @$core.override
  CreateCategory createEmptyInstance() => CreateCategory._();
  @$core.pragma('dart2js:noInline')
  static CreateCategory getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CreateCategory>(
          CreateCategory.$_createMessage);
  static CreateCategory? _defaultInstance;

  @$pb.TagNumber(1)
  Category get category => $_getN(0);
  @$pb.TagNumber(1)
  set category(Category value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCategory() => $_has(0);
  @$pb.TagNumber(1)
  void clearCategory() => $_clearField(1);
  @$pb.TagNumber(1)
  Category ensureCategory() => $_ensure(0);
}

class RenameCategory extends $pb.GeneratedMessage {
  factory RenameCategory({
    $core.String? categoryId,
    $core.String? name,
  }) {
    final result = RenameCategory._();
    if (categoryId != null) result.categoryId = categoryId;
    if (name != null) result.name = name;
    return result;
  }

  RenameCategory._();

  factory RenameCategory.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenameCategory()..mergeFromBuffer(data, registry);
  factory RenameCategory.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      RenameCategory()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RenameCategory',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: RenameCategory.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'categoryId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenameCategory clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RenameCategory copyWith(void Function(RenameCategory) updates) =>
      super.copyWith((message) => updates(message as RenameCategory))
          as RenameCategory;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use RenameCategory() / RenameCategory.new instead')
  static RenameCategory create() => RenameCategory._();
  static $pb.GeneratedMessage $_createMessage() => RenameCategory._();
  @$core.override
  RenameCategory createEmptyInstance() => RenameCategory._();
  @$core.pragma('dart2js:noInline')
  static RenameCategory getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RenameCategory>(
          RenameCategory.$_createMessage);
  static RenameCategory? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get categoryId => $_getSZ(0);
  @$pb.TagNumber(1)
  set categoryId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCategoryId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCategoryId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);
}

class ReorderCategories extends $pb.GeneratedMessage {
  factory ReorderCategories({
    $core.Iterable<$core.String>? categoryIds,
  }) {
    final result = ReorderCategories._();
    if (categoryIds != null) result.categoryIds.addAll(categoryIds);
    return result;
  }

  ReorderCategories._();

  factory ReorderCategories.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReorderCategories()..mergeFromBuffer(data, registry);
  factory ReorderCategories.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReorderCategories()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReorderCategories',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ReorderCategories.$_createMessage)
    ..pPS(1, _omitFieldNames ? '' : 'categoryIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReorderCategories clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReorderCategories copyWith(void Function(ReorderCategories) updates) =>
      super.copyWith((message) => updates(message as ReorderCategories))
          as ReorderCategories;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReorderCategories() / ReorderCategories.new instead')
  static ReorderCategories create() => ReorderCategories._();
  static $pb.GeneratedMessage $_createMessage() => ReorderCategories._();
  @$core.override
  ReorderCategories createEmptyInstance() => ReorderCategories._();
  @$core.pragma('dart2js:noInline')
  static ReorderCategories getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReorderCategories>(
          ReorderCategories.$_createMessage);
  static ReorderCategories? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get categoryIds => $_getList(0);
}

class DeleteCategory extends $pb.GeneratedMessage {
  factory DeleteCategory({
    $core.String? categoryId,
  }) {
    final result = DeleteCategory._();
    if (categoryId != null) result.categoryId = categoryId;
    return result;
  }

  DeleteCategory._();

  factory DeleteCategory.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteCategory()..mergeFromBuffer(data, registry);
  factory DeleteCategory.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      DeleteCategory()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteCategory',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: DeleteCategory.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'categoryId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteCategory clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteCategory copyWith(void Function(DeleteCategory) updates) =>
      super.copyWith((message) => updates(message as DeleteCategory))
          as DeleteCategory;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use DeleteCategory() / DeleteCategory.new instead')
  static DeleteCategory create() => DeleteCategory._();
  static $pb.GeneratedMessage $_createMessage() => DeleteCategory._();
  @$core.override
  DeleteCategory createEmptyInstance() => DeleteCategory._();
  @$core.pragma('dart2js:noInline')
  static DeleteCategory getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DeleteCategory>(
          DeleteCategory.$_createMessage);
  static DeleteCategory? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get categoryId => $_getSZ(0);
  @$pb.TagNumber(1)
  set categoryId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCategoryId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCategoryId() => $_clearField(1);
}

enum CategoryMutation_Operation {
  createCategory,
  renameCategory,
  reorderCategories,
  deleteCategory,
  notSet
}

class CategoryMutation extends $pb.GeneratedMessage {
  factory CategoryMutation({
    $core.int? schemaVersion,
    $core.String? mutationId,
    $core.int? expectedRevision,
    CreateCategory? createCategory,
    RenameCategory? renameCategory,
    ReorderCategories? reorderCategories,
    DeleteCategory? deleteCategory,
  }) {
    final result = CategoryMutation._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (mutationId != null) result.mutationId = mutationId;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    if (createCategory != null) result.createCategory = createCategory;
    if (renameCategory != null) result.renameCategory = renameCategory;
    if (reorderCategories != null) result.reorderCategories = reorderCategories;
    if (deleteCategory != null) result.deleteCategory = deleteCategory;
    return result;
  }

  CategoryMutation._();

  factory CategoryMutation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CategoryMutation()..mergeFromBuffer(data, registry);
  factory CategoryMutation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CategoryMutation()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, CategoryMutation_Operation>
      _CategoryMutation_OperationByTag = {
    10: CategoryMutation_Operation.createCategory,
    11: CategoryMutation_Operation.renameCategory,
    12: CategoryMutation_Operation.reorderCategories,
    13: CategoryMutation_Operation.deleteCategory,
    0: CategoryMutation_Operation.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CategoryMutation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CategoryMutation.$_createMessage)
    ..oo(0, [10, 11, 12, 13])
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'mutationId')
    ..aI(3, _omitFieldNames ? '' : 'expectedRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<CreateCategory>(10, _omitFieldNames ? '' : 'createCategory',
        subBuilder: CreateCategory.$_createMessage)
    ..aOM<RenameCategory>(11, _omitFieldNames ? '' : 'renameCategory',
        subBuilder: RenameCategory.$_createMessage)
    ..aOM<ReorderCategories>(12, _omitFieldNames ? '' : 'reorderCategories',
        subBuilder: ReorderCategories.$_createMessage)
    ..aOM<DeleteCategory>(13, _omitFieldNames ? '' : 'deleteCategory',
        subBuilder: DeleteCategory.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategoryMutation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategoryMutation copyWith(void Function(CategoryMutation) updates) =>
      super.copyWith((message) => updates(message as CategoryMutation))
          as CategoryMutation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use CategoryMutation() / CategoryMutation.new instead')
  static CategoryMutation create() => CategoryMutation._();
  static $pb.GeneratedMessage $_createMessage() => CategoryMutation._();
  @$core.override
  CategoryMutation createEmptyInstance() => CategoryMutation._();
  @$core.pragma('dart2js:noInline')
  static CategoryMutation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CategoryMutation>(
          CategoryMutation.$_createMessage);
  static CategoryMutation? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  CategoryMutation_Operation whichOperation() =>
      _CategoryMutation_OperationByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  void clearOperation() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mutationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set mutationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMutationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMutationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get expectedRevision => $_getIZ(2);
  @$pb.TagNumber(3)
  set expectedRevision($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpectedRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpectedRevision() => $_clearField(3);

  @$pb.TagNumber(10)
  CreateCategory get createCategory => $_getN(3);
  @$pb.TagNumber(10)
  set createCategory(CreateCategory value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasCreateCategory() => $_has(3);
  @$pb.TagNumber(10)
  void clearCreateCategory() => $_clearField(10);
  @$pb.TagNumber(10)
  CreateCategory ensureCreateCategory() => $_ensure(3);

  @$pb.TagNumber(11)
  RenameCategory get renameCategory => $_getN(4);
  @$pb.TagNumber(11)
  set renameCategory(RenameCategory value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasRenameCategory() => $_has(4);
  @$pb.TagNumber(11)
  void clearRenameCategory() => $_clearField(11);
  @$pb.TagNumber(11)
  RenameCategory ensureRenameCategory() => $_ensure(4);

  @$pb.TagNumber(12)
  ReorderCategories get reorderCategories => $_getN(5);
  @$pb.TagNumber(12)
  set reorderCategories(ReorderCategories value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasReorderCategories() => $_has(5);
  @$pb.TagNumber(12)
  void clearReorderCategories() => $_clearField(12);
  @$pb.TagNumber(12)
  ReorderCategories ensureReorderCategories() => $_ensure(5);

  @$pb.TagNumber(13)
  DeleteCategory get deleteCategory => $_getN(6);
  @$pb.TagNumber(13)
  set deleteCategory(DeleteCategory value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasDeleteCategory() => $_has(6);
  @$pb.TagNumber(13)
  void clearDeleteCategory() => $_clearField(13);
  @$pb.TagNumber(13)
  DeleteCategory ensureDeleteCategory() => $_ensure(6);
}

class ReadingAnchor extends $pb.GeneratedMessage {
  factory ReadingAnchor({
    $core.String? chapterKey,
    $core.String? pageKey,
    $core.String? manifestVersion,
    $core.int? pageIndexHint,
    $core.double? normalizedOffset,
    $core.double? normalizedX,
    $core.double? viewportX,
    $core.double? viewportY,
  }) {
    final result = ReadingAnchor._();
    if (chapterKey != null) result.chapterKey = chapterKey;
    if (pageKey != null) result.pageKey = pageKey;
    if (manifestVersion != null) result.manifestVersion = manifestVersion;
    if (pageIndexHint != null) result.pageIndexHint = pageIndexHint;
    if (normalizedOffset != null) result.normalizedOffset = normalizedOffset;
    if (normalizedX != null) result.normalizedX = normalizedX;
    if (viewportX != null) result.viewportX = viewportX;
    if (viewportY != null) result.viewportY = viewportY;
    return result;
  }

  ReadingAnchor._();

  factory ReadingAnchor.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadingAnchor()..mergeFromBuffer(data, registry);
  factory ReadingAnchor.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReadingAnchor()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReadingAnchor',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ReadingAnchor.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'chapterKey')
    ..aOS(2, _omitFieldNames ? '' : 'pageKey')
    ..aOS(3, _omitFieldNames ? '' : 'manifestVersion')
    ..aI(4, _omitFieldNames ? '' : 'pageIndexHint',
        fieldType: $pb.PbFieldType.OU3)
    ..aD(5, _omitFieldNames ? '' : 'normalizedOffset')
    ..aD(6, _omitFieldNames ? '' : 'normalizedX')
    ..aD(7, _omitFieldNames ? '' : 'viewportX')
    ..aD(8, _omitFieldNames ? '' : 'viewportY')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadingAnchor clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReadingAnchor copyWith(void Function(ReadingAnchor) updates) =>
      super.copyWith((message) => updates(message as ReadingAnchor))
          as ReadingAnchor;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReadingAnchor() / ReadingAnchor.new instead')
  static ReadingAnchor create() => ReadingAnchor._();
  static $pb.GeneratedMessage $_createMessage() => ReadingAnchor._();
  @$core.override
  ReadingAnchor createEmptyInstance() => ReadingAnchor._();
  @$core.pragma('dart2js:noInline')
  static ReadingAnchor getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReadingAnchor>(
          ReadingAnchor.$_createMessage);
  static ReadingAnchor? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chapterKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set chapterKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChapterKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearChapterKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get pageKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set pageKey($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPageKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearPageKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get manifestVersion => $_getSZ(2);
  @$pb.TagNumber(3)
  set manifestVersion($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasManifestVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearManifestVersion() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get pageIndexHint => $_getIZ(3);
  @$pb.TagNumber(4)
  set pageIndexHint($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPageIndexHint() => $_has(3);
  @$pb.TagNumber(4)
  void clearPageIndexHint() => $_clearField(4);

  /// Source-image y; viewport coordinates identify where that point appears.
  @$pb.TagNumber(5)
  $core.double get normalizedOffset => $_getN(4);
  @$pb.TagNumber(5)
  set normalizedOffset($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNormalizedOffset() => $_has(4);
  @$pb.TagNumber(5)
  void clearNormalizedOffset() => $_clearField(5);

  /// Source-image x is physical and is not mirrored in RTL.
  @$pb.TagNumber(6)
  $core.double get normalizedX => $_getN(5);
  @$pb.TagNumber(6)
  set normalizedX($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasNormalizedX() => $_has(5);
  @$pb.TagNumber(6)
  void clearNormalizedX() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get viewportX => $_getN(6);
  @$pb.TagNumber(7)
  set viewportX($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasViewportX() => $_has(6);
  @$pb.TagNumber(7)
  void clearViewportX() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get viewportY => $_getN(7);
  @$pb.TagNumber(8)
  set viewportY($core.double value) => $_setDouble(7, value);
  @$pb.TagNumber(8)
  $core.bool hasViewportY() => $_has(7);
  @$pb.TagNumber(8)
  void clearViewportY() => $_clearField(8);
}

class ChapterProgressState extends $pb.GeneratedMessage {
  factory ChapterProgressState({
    $core.String? chapterKey,
    ReadingAnchor? current,
    ReadingAnchor? furthest,
    $core.int? epoch,
    $core.bool? completed,
  }) {
    final result = ChapterProgressState._();
    if (chapterKey != null) result.chapterKey = chapterKey;
    if (current != null) result.current = current;
    if (furthest != null) result.furthest = furthest;
    if (epoch != null) result.epoch = epoch;
    if (completed != null) result.completed = completed;
    return result;
  }

  ChapterProgressState._();

  factory ChapterProgressState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterProgressState()..mergeFromBuffer(data, registry);
  factory ChapterProgressState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterProgressState()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChapterProgressState',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ChapterProgressState.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'chapterKey')
    ..aOM<ReadingAnchor>(2, _omitFieldNames ? '' : 'current',
        subBuilder: ReadingAnchor.$_createMessage)
    ..aOM<ReadingAnchor>(3, _omitFieldNames ? '' : 'furthest',
        subBuilder: ReadingAnchor.$_createMessage)
    ..aI(4, _omitFieldNames ? '' : 'epoch', fieldType: $pb.PbFieldType.OU3)
    ..aOB(5, _omitFieldNames ? '' : 'completed')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterProgressState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterProgressState copyWith(void Function(ChapterProgressState) updates) =>
      super.copyWith((message) => updates(message as ChapterProgressState))
          as ChapterProgressState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ChapterProgressState() / ChapterProgressState.new instead')
  static ChapterProgressState create() => ChapterProgressState._();
  static $pb.GeneratedMessage $_createMessage() => ChapterProgressState._();
  @$core.override
  ChapterProgressState createEmptyInstance() => ChapterProgressState._();
  @$core.pragma('dart2js:noInline')
  static ChapterProgressState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChapterProgressState>(
          ChapterProgressState.$_createMessage);
  static ChapterProgressState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chapterKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set chapterKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChapterKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearChapterKey() => $_clearField(1);

  /// Anchors are absent for an unopened chapter marked from its detail list.
  @$pb.TagNumber(2)
  ReadingAnchor get current => $_getN(1);
  @$pb.TagNumber(2)
  set current(ReadingAnchor value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCurrent() => $_has(1);
  @$pb.TagNumber(2)
  void clearCurrent() => $_clearField(2);
  @$pb.TagNumber(2)
  ReadingAnchor ensureCurrent() => $_ensure(1);

  @$pb.TagNumber(3)
  ReadingAnchor get furthest => $_getN(2);
  @$pb.TagNumber(3)
  set furthest(ReadingAnchor value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFurthest() => $_has(2);
  @$pb.TagNumber(3)
  void clearFurthest() => $_clearField(3);
  @$pb.TagNumber(3)
  ReadingAnchor ensureFurthest() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.int get epoch => $_getIZ(3);
  @$pb.TagNumber(4)
  set epoch($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasEpoch() => $_has(3);
  @$pb.TagNumber(4)
  void clearEpoch() => $_clearField(4);

  /// Chapter-level read state; only reset or marking unread clears it.
  @$pb.TagNumber(5)
  $core.bool get completed => $_getBF(4);
  @$pb.TagNumber(5)
  set completed($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCompleted() => $_has(4);
  @$pb.TagNumber(5)
  void clearCompleted() => $_clearField(5);
}

/// The server projects anchors by page identity, never by a stale index hint.
class ChapterSnapshot extends $pb.GeneratedMessage {
  factory ChapterSnapshot({
    $core.String? chapterKey,
    $core.String? manifestVersion,
    $core.Iterable<$core.String>? pageKeys,
  }) {
    final result = ChapterSnapshot._();
    if (chapterKey != null) result.chapterKey = chapterKey;
    if (manifestVersion != null) result.manifestVersion = manifestVersion;
    if (pageKeys != null) result.pageKeys.addAll(pageKeys);
    return result;
  }

  ChapterSnapshot._();

  factory ChapterSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterSnapshot()..mergeFromBuffer(data, registry);
  factory ChapterSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterSnapshot()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChapterSnapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ChapterSnapshot.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'chapterKey')
    ..aOS(2, _omitFieldNames ? '' : 'manifestVersion')
    ..pPS(3, _omitFieldNames ? '' : 'pageKeys')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterSnapshot copyWith(void Function(ChapterSnapshot) updates) =>
      super.copyWith((message) => updates(message as ChapterSnapshot))
          as ChapterSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ChapterSnapshot() / ChapterSnapshot.new instead')
  static ChapterSnapshot create() => ChapterSnapshot._();
  static $pb.GeneratedMessage $_createMessage() => ChapterSnapshot._();
  @$core.override
  ChapterSnapshot createEmptyInstance() => ChapterSnapshot._();
  @$core.pragma('dart2js:noInline')
  static ChapterSnapshot getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChapterSnapshot>(
          ChapterSnapshot.$_createMessage);
  static ChapterSnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chapterKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set chapterKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChapterKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearChapterKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get manifestVersion => $_getSZ(1);
  @$pb.TagNumber(2)
  set manifestVersion($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasManifestVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearManifestVersion() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get pageKeys => $_getList(2);
}

class ChapterBookmark extends $pb.GeneratedMessage {
  factory ChapterBookmark({
    $core.String? chapterKey,
    $core.bool? bookmarked,
  }) {
    final result = ChapterBookmark._();
    if (chapterKey != null) result.chapterKey = chapterKey;
    if (bookmarked != null) result.bookmarked = bookmarked;
    return result;
  }

  ChapterBookmark._();

  factory ChapterBookmark.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterBookmark()..mergeFromBuffer(data, registry);
  factory ChapterBookmark.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterBookmark()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChapterBookmark',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ChapterBookmark.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'chapterKey')
    ..aOB(2, _omitFieldNames ? '' : 'bookmarked')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterBookmark clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterBookmark copyWith(void Function(ChapterBookmark) updates) =>
      super.copyWith((message) => updates(message as ChapterBookmark))
          as ChapterBookmark;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ChapterBookmark() / ChapterBookmark.new instead')
  static ChapterBookmark create() => ChapterBookmark._();
  static $pb.GeneratedMessage $_createMessage() => ChapterBookmark._();
  @$core.override
  ChapterBookmark createEmptyInstance() => ChapterBookmark._();
  @$core.pragma('dart2js:noInline')
  static ChapterBookmark getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChapterBookmark>(
          ChapterBookmark.$_createMessage);
  static ChapterBookmark? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chapterKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set chapterKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChapterKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearChapterKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get bookmarked => $_getBF(1);
  @$pb.TagNumber(2)
  set bookmarked($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBookmarked() => $_has(1);
  @$pb.TagNumber(2)
  void clearBookmarked() => $_clearField(2);
}

class SetBookmark extends $pb.GeneratedMessage {
  factory SetBookmark({
    $core.String? chapterKey,
    $core.bool? bookmarked,
  }) {
    final result = SetBookmark._();
    if (chapterKey != null) result.chapterKey = chapterKey;
    if (bookmarked != null) result.bookmarked = bookmarked;
    return result;
  }

  SetBookmark._();

  factory SetBookmark.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetBookmark()..mergeFromBuffer(data, registry);
  factory SetBookmark.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetBookmark()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetBookmark',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SetBookmark.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'chapterKey')
    ..aOB(2, _omitFieldNames ? '' : 'bookmarked')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetBookmark clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetBookmark copyWith(void Function(SetBookmark) updates) =>
      super.copyWith((message) => updates(message as SetBookmark))
          as SetBookmark;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetBookmark() / SetBookmark.new instead')
  static SetBookmark create() => SetBookmark._();
  static $pb.GeneratedMessage $_createMessage() => SetBookmark._();
  @$core.override
  SetBookmark createEmptyInstance() => SetBookmark._();
  @$core.pragma('dart2js:noInline')
  static SetBookmark getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetBookmark>(
          SetBookmark.$_createMessage);
  static SetBookmark? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chapterKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set chapterKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChapterKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearChapterKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get bookmarked => $_getBF(1);
  @$pb.TagNumber(2)
  set bookmarked($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasBookmarked() => $_has(1);
  @$pb.TagNumber(2)
  void clearBookmarked() => $_clearField(2);
}

class SetChapterRead extends $pb.GeneratedMessage {
  factory SetChapterRead({
    $core.String? chapterKey,
    $core.bool? read,
  }) {
    final result = SetChapterRead._();
    if (chapterKey != null) result.chapterKey = chapterKey;
    if (read != null) result.read = read;
    return result;
  }

  SetChapterRead._();

  factory SetChapterRead.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetChapterRead()..mergeFromBuffer(data, registry);
  factory SetChapterRead.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetChapterRead()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetChapterRead',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SetChapterRead.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'chapterKey')
    ..aOB(2, _omitFieldNames ? '' : 'read')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetChapterRead clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetChapterRead copyWith(void Function(SetChapterRead) updates) =>
      super.copyWith((message) => updates(message as SetChapterRead))
          as SetChapterRead;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetChapterRead() / SetChapterRead.new instead')
  static SetChapterRead create() => SetChapterRead._();
  static $pb.GeneratedMessage $_createMessage() => SetChapterRead._();
  @$core.override
  SetChapterRead createEmptyInstance() => SetChapterRead._();
  @$core.pragma('dart2js:noInline')
  static SetChapterRead getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetChapterRead>(
          SetChapterRead.$_createMessage);
  static SetChapterRead? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get chapterKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set chapterKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasChapterKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearChapterKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get read => $_getBF(1);
  @$pb.TagNumber(2)
  set read($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRead() => $_has(1);
  @$pb.TagNumber(2)
  void clearRead() => $_clearField(2);
}

class SetFavorite extends $pb.GeneratedMessage {
  factory SetFavorite({
    LibraryMetadata? metadata,
    $core.bool? favorite,
  }) {
    final result = SetFavorite._();
    if (metadata != null) result.metadata = metadata;
    if (favorite != null) result.favorite = favorite;
    return result;
  }

  SetFavorite._();

  factory SetFavorite.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetFavorite()..mergeFromBuffer(data, registry);
  factory SetFavorite.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetFavorite()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetFavorite',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SetFavorite.$_createMessage)
    ..aOM<LibraryMetadata>(1, _omitFieldNames ? '' : 'metadata',
        subBuilder: LibraryMetadata.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'favorite')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFavorite clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetFavorite copyWith(void Function(SetFavorite) updates) =>
      super.copyWith((message) => updates(message as SetFavorite))
          as SetFavorite;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SetFavorite() / SetFavorite.new instead')
  static SetFavorite create() => SetFavorite._();
  static $pb.GeneratedMessage $_createMessage() => SetFavorite._();
  @$core.override
  SetFavorite createEmptyInstance() => SetFavorite._();
  @$core.pragma('dart2js:noInline')
  static SetFavorite getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SetFavorite>(
          SetFavorite.$_createMessage);
  static SetFavorite? _defaultInstance;

  @$pb.TagNumber(1)
  LibraryMetadata get metadata => $_getN(0);
  @$pb.TagNumber(1)
  set metadata(LibraryMetadata value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMetadata() => $_has(0);
  @$pb.TagNumber(1)
  void clearMetadata() => $_clearField(1);
  @$pb.TagNumber(1)
  LibraryMetadata ensureMetadata() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.bool get favorite => $_getBF(1);
  @$pb.TagNumber(2)
  set favorite($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFavorite() => $_has(1);
  @$pb.TagNumber(2)
  void clearFavorite() => $_clearField(2);
}

class SaveProgress extends $pb.GeneratedMessage {
  factory SaveProgress({
    ChapterSnapshot? snapshot,
    ChapterProgressState? progress,
    $core.bool? reversedOrder,
  }) {
    final result = SaveProgress._();
    if (snapshot != null) result.snapshot = snapshot;
    if (progress != null) result.progress = progress;
    if (reversedOrder != null) result.reversedOrder = reversedOrder;
    return result;
  }

  SaveProgress._();

  factory SaveProgress.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SaveProgress()..mergeFromBuffer(data, registry);
  factory SaveProgress.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SaveProgress()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SaveProgress',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SaveProgress.$_createMessage)
    ..aOM<ChapterSnapshot>(1, _omitFieldNames ? '' : 'snapshot',
        subBuilder: ChapterSnapshot.$_createMessage)
    ..aOM<ChapterProgressState>(2, _omitFieldNames ? '' : 'progress',
        subBuilder: ChapterProgressState.$_createMessage)
    ..aOB(3, _omitFieldNames ? '' : 'reversedOrder')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SaveProgress clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SaveProgress copyWith(void Function(SaveProgress) updates) =>
      super.copyWith((message) => updates(message as SaveProgress))
          as SaveProgress;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SaveProgress() / SaveProgress.new instead')
  static SaveProgress create() => SaveProgress._();
  static $pb.GeneratedMessage $_createMessage() => SaveProgress._();
  @$core.override
  SaveProgress createEmptyInstance() => SaveProgress._();
  @$core.pragma('dart2js:noInline')
  static SaveProgress getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SaveProgress>(
          SaveProgress.$_createMessage);
  static SaveProgress? _defaultInstance;

  @$pb.TagNumber(1)
  ChapterSnapshot get snapshot => $_getN(0);
  @$pb.TagNumber(1)
  set snapshot(ChapterSnapshot value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSnapshot() => $_has(0);
  @$pb.TagNumber(1)
  void clearSnapshot() => $_clearField(1);
  @$pb.TagNumber(1)
  ChapterSnapshot ensureSnapshot() => $_ensure(0);

  @$pb.TagNumber(2)
  ChapterProgressState get progress => $_getN(1);
  @$pb.TagNumber(2)
  set progress(ChapterProgressState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasProgress() => $_has(1);
  @$pb.TagNumber(2)
  void clearProgress() => $_clearField(2);
  @$pb.TagNumber(2)
  ChapterProgressState ensureProgress() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.bool get reversedOrder => $_getBF(2);
  @$pb.TagNumber(3)
  set reversedOrder($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasReversedOrder() => $_has(2);
  @$pb.TagNumber(3)
  void clearReversedOrder() => $_clearField(3);
}

class ResetProgress extends $pb.GeneratedMessage {
  factory ResetProgress({
    ChapterSnapshot? snapshot,
    $core.bool? reversedOrder,
  }) {
    final result = ResetProgress._();
    if (snapshot != null) result.snapshot = snapshot;
    if (reversedOrder != null) result.reversedOrder = reversedOrder;
    return result;
  }

  ResetProgress._();

  factory ResetProgress.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResetProgress()..mergeFromBuffer(data, registry);
  factory ResetProgress.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ResetProgress()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResetProgress',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ResetProgress.$_createMessage)
    ..aOM<ChapterSnapshot>(1, _omitFieldNames ? '' : 'snapshot',
        subBuilder: ChapterSnapshot.$_createMessage)
    ..aOB(2, _omitFieldNames ? '' : 'reversedOrder')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetProgress clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResetProgress copyWith(void Function(ResetProgress) updates) =>
      super.copyWith((message) => updates(message as ResetProgress))
          as ResetProgress;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ResetProgress() / ResetProgress.new instead')
  static ResetProgress create() => ResetProgress._();
  static $pb.GeneratedMessage $_createMessage() => ResetProgress._();
  @$core.override
  ResetProgress createEmptyInstance() => ResetProgress._();
  @$core.pragma('dart2js:noInline')
  static ResetProgress getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ResetProgress>(
          ResetProgress.$_createMessage);
  static ResetProgress? _defaultInstance;

  @$pb.TagNumber(1)
  ChapterSnapshot get snapshot => $_getN(0);
  @$pb.TagNumber(1)
  set snapshot(ChapterSnapshot value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasSnapshot() => $_has(0);
  @$pb.TagNumber(1)
  void clearSnapshot() => $_clearField(1);
  @$pb.TagNumber(1)
  ChapterSnapshot ensureSnapshot() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.bool get reversedOrder => $_getBF(1);
  @$pb.TagNumber(2)
  set reversedOrder($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReversedOrder() => $_has(1);
  @$pb.TagNumber(2)
  void clearReversedOrder() => $_clearField(2);
}

/// Explicit user-confirmed one-to-one chapter identities; flags select positive
/// source read/bookmark state only. Source page anchors never cross sources.
class ChapterMigration extends $pb.GeneratedMessage {
  factory ChapterMigration({
    $core.String? sourceChapterKey,
    $core.String? targetChapterKey,
    $core.bool? copyRead,
    $core.bool? copyBookmark,
  }) {
    final result = ChapterMigration._();
    if (sourceChapterKey != null) result.sourceChapterKey = sourceChapterKey;
    if (targetChapterKey != null) result.targetChapterKey = targetChapterKey;
    if (copyRead != null) result.copyRead = copyRead;
    if (copyBookmark != null) result.copyBookmark = copyBookmark;
    return result;
  }

  ChapterMigration._();

  factory ChapterMigration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterMigration()..mergeFromBuffer(data, registry);
  factory ChapterMigration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterMigration()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChapterMigration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ChapterMigration.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sourceChapterKey')
    ..aOS(2, _omitFieldNames ? '' : 'targetChapterKey')
    ..aOB(3, _omitFieldNames ? '' : 'copyRead')
    ..aOB(4, _omitFieldNames ? '' : 'copyBookmark')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterMigration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterMigration copyWith(void Function(ChapterMigration) updates) =>
      super.copyWith((message) => updates(message as ChapterMigration))
          as ChapterMigration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ChapterMigration() / ChapterMigration.new instead')
  static ChapterMigration create() => ChapterMigration._();
  static $pb.GeneratedMessage $_createMessage() => ChapterMigration._();
  @$core.override
  ChapterMigration createEmptyInstance() => ChapterMigration._();
  @$core.pragma('dart2js:noInline')
  static ChapterMigration getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ChapterMigration>(
          ChapterMigration.$_createMessage);
  static ChapterMigration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sourceChapterKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set sourceChapterKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSourceChapterKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearSourceChapterKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get targetChapterKey => $_getSZ(1);
  @$pb.TagNumber(2)
  set targetChapterKey($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTargetChapterKey() => $_has(1);
  @$pb.TagNumber(2)
  void clearTargetChapterKey() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get copyRead => $_getBF(2);
  @$pb.TagNumber(3)
  set copyRead($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCopyRead() => $_has(2);
  @$pb.TagNumber(3)
  void clearCopyRead() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get copyBookmark => $_getBF(3);
  @$pb.TagNumber(4)
  set copyBookmark($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCopyBookmark() => $_has(3);
  @$pb.TagNumber(4)
  void clearCopyBookmark() => $_clearField(4);
}

class MigrateFrom extends $pb.GeneratedMessage {
  factory MigrateFrom({
    $core.String? sourceMangaKey,
    $core.int? expectedSourceRevision,
    $core.int? expectedCatalogRevision,
    LibraryMetadata? targetMetadata,
    $core.bool? copyCategories,
    $core.Iterable<ChapterMigration>? chapters,
  }) {
    final result = MigrateFrom._();
    if (sourceMangaKey != null) result.sourceMangaKey = sourceMangaKey;
    if (expectedSourceRevision != null)
      result.expectedSourceRevision = expectedSourceRevision;
    if (expectedCatalogRevision != null)
      result.expectedCatalogRevision = expectedCatalogRevision;
    if (targetMetadata != null) result.targetMetadata = targetMetadata;
    if (copyCategories != null) result.copyCategories = copyCategories;
    if (chapters != null) result.chapters.addAll(chapters);
    return result;
  }

  MigrateFrom._();

  factory MigrateFrom.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MigrateFrom()..mergeFromBuffer(data, registry);
  factory MigrateFrom.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MigrateFrom()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MigrateFrom',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: MigrateFrom.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'sourceMangaKey')
    ..aI(2, _omitFieldNames ? '' : 'expectedSourceRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'expectedCatalogRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<LibraryMetadata>(4, _omitFieldNames ? '' : 'targetMetadata',
        subBuilder: LibraryMetadata.$_createMessage)
    ..aOB(5, _omitFieldNames ? '' : 'copyCategories')
    ..pPM<ChapterMigration>(6, _omitFieldNames ? '' : 'chapters',
        subBuilder: ChapterMigration.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MigrateFrom clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MigrateFrom copyWith(void Function(MigrateFrom) updates) =>
      super.copyWith((message) => updates(message as MigrateFrom))
          as MigrateFrom;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MigrateFrom() / MigrateFrom.new instead')
  static MigrateFrom create() => MigrateFrom._();
  static $pb.GeneratedMessage $_createMessage() => MigrateFrom._();
  @$core.override
  MigrateFrom createEmptyInstance() => MigrateFrom._();
  @$core.pragma('dart2js:noInline')
  static MigrateFrom getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MigrateFrom>(
          MigrateFrom.$_createMessage);
  static MigrateFrom? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get sourceMangaKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set sourceMangaKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSourceMangaKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearSourceMangaKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get expectedSourceRevision => $_getIZ(1);
  @$pb.TagNumber(2)
  set expectedSourceRevision($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasExpectedSourceRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearExpectedSourceRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get expectedCatalogRevision => $_getIZ(2);
  @$pb.TagNumber(3)
  set expectedCatalogRevision($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpectedCatalogRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpectedCatalogRevision() => $_clearField(3);

  @$pb.TagNumber(4)
  LibraryMetadata get targetMetadata => $_getN(3);
  @$pb.TagNumber(4)
  set targetMetadata(LibraryMetadata value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasTargetMetadata() => $_has(3);
  @$pb.TagNumber(4)
  void clearTargetMetadata() => $_clearField(4);
  @$pb.TagNumber(4)
  LibraryMetadata ensureTargetMetadata() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.bool get copyCategories => $_getBF(4);
  @$pb.TagNumber(5)
  set copyCategories($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCopyCategories() => $_has(4);
  @$pb.TagNumber(5)
  void clearCopyCategories() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<ChapterMigration> get chapters => $_getList(5);
}

class MigrationResult extends $pb.GeneratedMessage {
  factory MigrationResult({
    $core.int? copiedReadChapters,
    $core.int? copiedBookmarks,
  }) {
    final result = MigrationResult._();
    if (copiedReadChapters != null)
      result.copiedReadChapters = copiedReadChapters;
    if (copiedBookmarks != null) result.copiedBookmarks = copiedBookmarks;
    return result;
  }

  MigrationResult._();

  factory MigrationResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MigrationResult()..mergeFromBuffer(data, registry);
  factory MigrationResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MigrationResult()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MigrationResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: MigrationResult.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'copiedReadChapters',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'copiedBookmarks',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MigrationResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MigrationResult copyWith(void Function(MigrationResult) updates) =>
      super.copyWith((message) => updates(message as MigrationResult))
          as MigrationResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MigrationResult() / MigrationResult.new instead')
  static MigrationResult create() => MigrationResult._();
  static $pb.GeneratedMessage $_createMessage() => MigrationResult._();
  @$core.override
  MigrationResult createEmptyInstance() => MigrationResult._();
  @$core.pragma('dart2js:noInline')
  static MigrationResult getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<MigrationResult>(
          MigrationResult.$_createMessage);
  static MigrationResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get copiedReadChapters => $_getIZ(0);
  @$pb.TagNumber(1)
  set copiedReadChapters($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCopiedReadChapters() => $_has(0);
  @$pb.TagNumber(1)
  void clearCopiedReadChapters() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get copiedBookmarks => $_getIZ(1);
  @$pb.TagNumber(2)
  set copiedBookmarks($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCopiedBookmarks() => $_has(1);
  @$pb.TagNumber(2)
  void clearCopiedBookmarks() => $_clearField(2);
}

enum StateMutation_Operation {
  setFavorite,
  updateMetadata,
  saveProgress,
  resetProgress,
  setCategories,
  setBookmark,
  setChapterRead,
  setCustomCover,
  migrateFrom,
  notSet
}

class StateMutation extends $pb.GeneratedMessage {
  factory StateMutation({
    $core.int? schemaVersion,
    $core.String? mutationId,
    $core.String? mangaKey,
    $core.int? expectedRevision,
    SetFavorite? setFavorite,
    LibraryMetadata? updateMetadata,
    SaveProgress? saveProgress,
    ResetProgress? resetProgress,
    SetCategories? setCategories,
    SetBookmark? setBookmark,
    SetChapterRead? setChapterRead,
    SetCustomCover? setCustomCover,
    MigrateFrom? migrateFrom,
  }) {
    final result = StateMutation._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (mutationId != null) result.mutationId = mutationId;
    if (mangaKey != null) result.mangaKey = mangaKey;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    if (setFavorite != null) result.setFavorite = setFavorite;
    if (updateMetadata != null) result.updateMetadata = updateMetadata;
    if (saveProgress != null) result.saveProgress = saveProgress;
    if (resetProgress != null) result.resetProgress = resetProgress;
    if (setCategories != null) result.setCategories = setCategories;
    if (setBookmark != null) result.setBookmark = setBookmark;
    if (setChapterRead != null) result.setChapterRead = setChapterRead;
    if (setCustomCover != null) result.setCustomCover = setCustomCover;
    if (migrateFrom != null) result.migrateFrom = migrateFrom;
    return result;
  }

  StateMutation._();

  factory StateMutation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StateMutation()..mergeFromBuffer(data, registry);
  factory StateMutation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StateMutation()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, StateMutation_Operation>
      _StateMutation_OperationByTag = {
    10: StateMutation_Operation.setFavorite,
    11: StateMutation_Operation.updateMetadata,
    12: StateMutation_Operation.saveProgress,
    13: StateMutation_Operation.resetProgress,
    14: StateMutation_Operation.setCategories,
    15: StateMutation_Operation.setBookmark,
    16: StateMutation_Operation.setChapterRead,
    17: StateMutation_Operation.setCustomCover,
    18: StateMutation_Operation.migrateFrom,
    0: StateMutation_Operation.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StateMutation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: StateMutation.$_createMessage)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17, 18])
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'mutationId')
    ..aOS(3, _omitFieldNames ? '' : 'mangaKey')
    ..aI(4, _omitFieldNames ? '' : 'expectedRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<SetFavorite>(10, _omitFieldNames ? '' : 'setFavorite',
        subBuilder: SetFavorite.$_createMessage)
    ..aOM<LibraryMetadata>(11, _omitFieldNames ? '' : 'updateMetadata',
        subBuilder: LibraryMetadata.$_createMessage)
    ..aOM<SaveProgress>(12, _omitFieldNames ? '' : 'saveProgress',
        subBuilder: SaveProgress.$_createMessage)
    ..aOM<ResetProgress>(13, _omitFieldNames ? '' : 'resetProgress',
        subBuilder: ResetProgress.$_createMessage)
    ..aOM<SetCategories>(14, _omitFieldNames ? '' : 'setCategories',
        subBuilder: SetCategories.$_createMessage)
    ..aOM<SetBookmark>(15, _omitFieldNames ? '' : 'setBookmark',
        subBuilder: SetBookmark.$_createMessage)
    ..aOM<SetChapterRead>(16, _omitFieldNames ? '' : 'setChapterRead',
        subBuilder: SetChapterRead.$_createMessage)
    ..aOM<SetCustomCover>(17, _omitFieldNames ? '' : 'setCustomCover',
        subBuilder: SetCustomCover.$_createMessage)
    ..aOM<MigrateFrom>(18, _omitFieldNames ? '' : 'migrateFrom',
        subBuilder: MigrateFrom.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StateMutation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StateMutation copyWith(void Function(StateMutation) updates) =>
      super.copyWith((message) => updates(message as StateMutation))
          as StateMutation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use StateMutation() / StateMutation.new instead')
  static StateMutation create() => StateMutation._();
  static $pb.GeneratedMessage $_createMessage() => StateMutation._();
  @$core.override
  StateMutation createEmptyInstance() => StateMutation._();
  @$core.pragma('dart2js:noInline')
  static StateMutation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StateMutation>(
          StateMutation.$_createMessage);
  static StateMutation? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  StateMutation_Operation whichOperation() =>
      _StateMutation_OperationByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  void clearOperation() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  /// UUID, retained with the exact acknowledged response for idempotent retries.
  @$pb.TagNumber(2)
  $core.String get mutationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set mutationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMutationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMutationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get mangaKey => $_getSZ(2);
  @$pb.TagNumber(3)
  set mangaKey($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMangaKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearMangaKey() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get expectedRevision => $_getIZ(3);
  @$pb.TagNumber(4)
  set expectedRevision($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasExpectedRevision() => $_has(3);
  @$pb.TagNumber(4)
  void clearExpectedRevision() => $_clearField(4);

  @$pb.TagNumber(10)
  SetFavorite get setFavorite => $_getN(4);
  @$pb.TagNumber(10)
  set setFavorite(SetFavorite value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasSetFavorite() => $_has(4);
  @$pb.TagNumber(10)
  void clearSetFavorite() => $_clearField(10);
  @$pb.TagNumber(10)
  SetFavorite ensureSetFavorite() => $_ensure(4);

  @$pb.TagNumber(11)
  LibraryMetadata get updateMetadata => $_getN(5);
  @$pb.TagNumber(11)
  set updateMetadata(LibraryMetadata value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasUpdateMetadata() => $_has(5);
  @$pb.TagNumber(11)
  void clearUpdateMetadata() => $_clearField(11);
  @$pb.TagNumber(11)
  LibraryMetadata ensureUpdateMetadata() => $_ensure(5);

  @$pb.TagNumber(12)
  SaveProgress get saveProgress => $_getN(6);
  @$pb.TagNumber(12)
  set saveProgress(SaveProgress value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasSaveProgress() => $_has(6);
  @$pb.TagNumber(12)
  void clearSaveProgress() => $_clearField(12);
  @$pb.TagNumber(12)
  SaveProgress ensureSaveProgress() => $_ensure(6);

  @$pb.TagNumber(13)
  ResetProgress get resetProgress => $_getN(7);
  @$pb.TagNumber(13)
  set resetProgress(ResetProgress value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasResetProgress() => $_has(7);
  @$pb.TagNumber(13)
  void clearResetProgress() => $_clearField(13);
  @$pb.TagNumber(13)
  ResetProgress ensureResetProgress() => $_ensure(7);

  @$pb.TagNumber(14)
  SetCategories get setCategories => $_getN(8);
  @$pb.TagNumber(14)
  set setCategories(SetCategories value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasSetCategories() => $_has(8);
  @$pb.TagNumber(14)
  void clearSetCategories() => $_clearField(14);
  @$pb.TagNumber(14)
  SetCategories ensureSetCategories() => $_ensure(8);

  @$pb.TagNumber(15)
  SetBookmark get setBookmark => $_getN(9);
  @$pb.TagNumber(15)
  set setBookmark(SetBookmark value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasSetBookmark() => $_has(9);
  @$pb.TagNumber(15)
  void clearSetBookmark() => $_clearField(15);
  @$pb.TagNumber(15)
  SetBookmark ensureSetBookmark() => $_ensure(9);

  @$pb.TagNumber(16)
  SetChapterRead get setChapterRead => $_getN(10);
  @$pb.TagNumber(16)
  set setChapterRead(SetChapterRead value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasSetChapterRead() => $_has(10);
  @$pb.TagNumber(16)
  void clearSetChapterRead() => $_clearField(16);
  @$pb.TagNumber(16)
  SetChapterRead ensureSetChapterRead() => $_ensure(10);

  @$pb.TagNumber(17)
  SetCustomCover get setCustomCover => $_getN(11);
  @$pb.TagNumber(17)
  set setCustomCover(SetCustomCover value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasSetCustomCover() => $_has(11);
  @$pb.TagNumber(17)
  void clearSetCustomCover() => $_clearField(17);
  @$pb.TagNumber(17)
  SetCustomCover ensureSetCustomCover() => $_ensure(11);

  @$pb.TagNumber(18)
  MigrateFrom get migrateFrom => $_getN(12);
  @$pb.TagNumber(18)
  set migrateFrom(MigrateFrom value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasMigrateFrom() => $_has(12);
  @$pb.TagNumber(18)
  void clearMigrateFrom() => $_clearField(18);
  @$pb.TagNumber(18)
  MigrateFrom ensureMigrateFrom() => $_ensure(12);
}

class BusinessStateError extends $pb.GeneratedMessage {
  factory BusinessStateError({
    BusinessStateErrorCode? code,
    $core.String? message,
    $core.bool? retryable,
  }) {
    final result = BusinessStateError._();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    if (retryable != null) result.retryable = retryable;
    return result;
  }

  BusinessStateError._();

  factory BusinessStateError.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BusinessStateError()..mergeFromBuffer(data, registry);
  factory BusinessStateError.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BusinessStateError()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BusinessStateError',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: BusinessStateError.$_createMessage)
    ..aE<BusinessStateErrorCode>(1, _omitFieldNames ? '' : 'code',
        enumValues: BusinessStateErrorCode.values)
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..aOB(3, _omitFieldNames ? '' : 'retryable')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BusinessStateError clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BusinessStateError copyWith(void Function(BusinessStateError) updates) =>
      super.copyWith((message) => updates(message as BusinessStateError))
          as BusinessStateError;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use BusinessStateError() / BusinessStateError.new instead')
  static BusinessStateError create() => BusinessStateError._();
  static $pb.GeneratedMessage $_createMessage() => BusinessStateError._();
  @$core.override
  BusinessStateError createEmptyInstance() => BusinessStateError._();
  @$core.pragma('dart2js:noInline')
  static BusinessStateError getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BusinessStateError>(
          BusinessStateError.$_createMessage);
  static BusinessStateError? _defaultInstance;

  @$pb.TagNumber(1)
  BusinessStateErrorCode get code => $_getN(0);
  @$pb.TagNumber(1)
  set code(BusinessStateErrorCode value) => $_setField(1, value);
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
}

class StateMutationResponse extends $pb.GeneratedMessage {
  factory StateMutationResponse({
    $core.int? schemaVersion,
    $core.String? mutationId,
    $core.int? accountRevision,
    MangaState? manga,
    ChapterProgressState? progress,
    BusinessStateError? error,
    CategoryCatalog? categoryCatalog,
    ChapterBookmark? bookmark,
    MigrationResult? migration,
  }) {
    final result = StateMutationResponse._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (mutationId != null) result.mutationId = mutationId;
    if (accountRevision != null) result.accountRevision = accountRevision;
    if (manga != null) result.manga = manga;
    if (progress != null) result.progress = progress;
    if (error != null) result.error = error;
    if (categoryCatalog != null) result.categoryCatalog = categoryCatalog;
    if (bookmark != null) result.bookmark = bookmark;
    if (migration != null) result.migration = migration;
    return result;
  }

  StateMutationResponse._();

  factory StateMutationResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StateMutationResponse()..mergeFromBuffer(data, registry);
  factory StateMutationResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      StateMutationResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StateMutationResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: StateMutationResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'mutationId')
    ..aI(3, _omitFieldNames ? '' : 'accountRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<MangaState>(4, _omitFieldNames ? '' : 'manga',
        subBuilder: MangaState.$_createMessage)
    ..aOM<ChapterProgressState>(5, _omitFieldNames ? '' : 'progress',
        subBuilder: ChapterProgressState.$_createMessage)
    ..aOM<BusinessStateError>(6, _omitFieldNames ? '' : 'error',
        subBuilder: BusinessStateError.$_createMessage)
    ..aOM<CategoryCatalog>(7, _omitFieldNames ? '' : 'categoryCatalog',
        subBuilder: CategoryCatalog.$_createMessage)
    ..aOM<ChapterBookmark>(8, _omitFieldNames ? '' : 'bookmark',
        subBuilder: ChapterBookmark.$_createMessage)
    ..aOM<MigrationResult>(9, _omitFieldNames ? '' : 'migration',
        subBuilder: MigrationResult.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StateMutationResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StateMutationResponse copyWith(
          void Function(StateMutationResponse) updates) =>
      super.copyWith((message) => updates(message as StateMutationResponse))
          as StateMutationResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use StateMutationResponse() / StateMutationResponse.new instead')
  static StateMutationResponse create() => StateMutationResponse._();
  static $pb.GeneratedMessage $_createMessage() => StateMutationResponse._();
  @$core.override
  StateMutationResponse createEmptyInstance() => StateMutationResponse._();
  @$core.pragma('dart2js:noInline')
  static StateMutationResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StateMutationResponse>(
          StateMutationResponse.$_createMessage);
  static StateMutationResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mutationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set mutationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMutationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMutationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get accountRevision => $_getIZ(2);
  @$pb.TagNumber(3)
  set accountRevision($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccountRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccountRevision() => $_clearField(3);

  @$pb.TagNumber(4)
  MangaState get manga => $_getN(3);
  @$pb.TagNumber(4)
  set manga(MangaState value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasManga() => $_has(3);
  @$pb.TagNumber(4)
  void clearManga() => $_clearField(4);
  @$pb.TagNumber(4)
  MangaState ensureManga() => $_ensure(3);

  @$pb.TagNumber(5)
  ChapterProgressState get progress => $_getN(4);
  @$pb.TagNumber(5)
  set progress(ChapterProgressState value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasProgress() => $_has(4);
  @$pb.TagNumber(5)
  void clearProgress() => $_clearField(5);
  @$pb.TagNumber(5)
  ChapterProgressState ensureProgress() => $_ensure(4);

  @$pb.TagNumber(6)
  BusinessStateError get error => $_getN(5);
  @$pb.TagNumber(6)
  set error(BusinessStateError value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  BusinessStateError ensureError() => $_ensure(5);

  @$pb.TagNumber(7)
  CategoryCatalog get categoryCatalog => $_getN(6);
  @$pb.TagNumber(7)
  set categoryCatalog(CategoryCatalog value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasCategoryCatalog() => $_has(6);
  @$pb.TagNumber(7)
  void clearCategoryCatalog() => $_clearField(7);
  @$pb.TagNumber(7)
  CategoryCatalog ensureCategoryCatalog() => $_ensure(6);

  @$pb.TagNumber(8)
  ChapterBookmark get bookmark => $_getN(7);
  @$pb.TagNumber(8)
  set bookmark(ChapterBookmark value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasBookmark() => $_has(7);
  @$pb.TagNumber(8)
  void clearBookmark() => $_clearField(8);
  @$pb.TagNumber(8)
  ChapterBookmark ensureBookmark() => $_ensure(7);

  @$pb.TagNumber(9)
  MigrationResult get migration => $_getN(8);
  @$pb.TagNumber(9)
  set migration(MigrationResult value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasMigration() => $_has(8);
  @$pb.TagNumber(9)
  void clearMigration() => $_clearField(9);
  @$pb.TagNumber(9)
  MigrationResult ensureMigration() => $_ensure(8);
}

class MangaStateResponse extends $pb.GeneratedMessage {
  factory MangaStateResponse({
    $core.int? schemaVersion,
    $core.int? accountRevision,
    MangaState? manga,
    ChapterProgressState? progress,
    BusinessStateError? error,
    CategoryCatalog? categoryCatalog,
    ChapterBookmark? bookmark,
  }) {
    final result = MangaStateResponse._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (accountRevision != null) result.accountRevision = accountRevision;
    if (manga != null) result.manga = manga;
    if (progress != null) result.progress = progress;
    if (error != null) result.error = error;
    if (categoryCatalog != null) result.categoryCatalog = categoryCatalog;
    if (bookmark != null) result.bookmark = bookmark;
    return result;
  }

  MangaStateResponse._();

  factory MangaStateResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaStateResponse()..mergeFromBuffer(data, registry);
  factory MangaStateResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaStateResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MangaStateResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: MangaStateResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'accountRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<MangaState>(3, _omitFieldNames ? '' : 'manga',
        subBuilder: MangaState.$_createMessage)
    ..aOM<ChapterProgressState>(4, _omitFieldNames ? '' : 'progress',
        subBuilder: ChapterProgressState.$_createMessage)
    ..aOM<BusinessStateError>(5, _omitFieldNames ? '' : 'error',
        subBuilder: BusinessStateError.$_createMessage)
    ..aOM<CategoryCatalog>(6, _omitFieldNames ? '' : 'categoryCatalog',
        subBuilder: CategoryCatalog.$_createMessage)
    ..aOM<ChapterBookmark>(7, _omitFieldNames ? '' : 'bookmark',
        subBuilder: ChapterBookmark.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaStateResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaStateResponse copyWith(void Function(MangaStateResponse) updates) =>
      super.copyWith((message) => updates(message as MangaStateResponse))
          as MangaStateResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use MangaStateResponse() / MangaStateResponse.new instead')
  static MangaStateResponse create() => MangaStateResponse._();
  static $pb.GeneratedMessage $_createMessage() => MangaStateResponse._();
  @$core.override
  MangaStateResponse createEmptyInstance() => MangaStateResponse._();
  @$core.pragma('dart2js:noInline')
  static MangaStateResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MangaStateResponse>(
          MangaStateResponse.$_createMessage);
  static MangaStateResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get accountRevision => $_getIZ(1);
  @$pb.TagNumber(2)
  set accountRevision($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccountRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccountRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  MangaState get manga => $_getN(2);
  @$pb.TagNumber(3)
  set manga(MangaState value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasManga() => $_has(2);
  @$pb.TagNumber(3)
  void clearManga() => $_clearField(3);
  @$pb.TagNumber(3)
  MangaState ensureManga() => $_ensure(2);

  @$pb.TagNumber(4)
  ChapterProgressState get progress => $_getN(3);
  @$pb.TagNumber(4)
  set progress(ChapterProgressState value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasProgress() => $_has(3);
  @$pb.TagNumber(4)
  void clearProgress() => $_clearField(4);
  @$pb.TagNumber(4)
  ChapterProgressState ensureProgress() => $_ensure(3);

  @$pb.TagNumber(5)
  BusinessStateError get error => $_getN(4);
  @$pb.TagNumber(5)
  set error(BusinessStateError value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
  @$pb.TagNumber(5)
  BusinessStateError ensureError() => $_ensure(4);

  @$pb.TagNumber(6)
  CategoryCatalog get categoryCatalog => $_getN(5);
  @$pb.TagNumber(6)
  set categoryCatalog(CategoryCatalog value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasCategoryCatalog() => $_has(5);
  @$pb.TagNumber(6)
  void clearCategoryCatalog() => $_clearField(6);
  @$pb.TagNumber(6)
  CategoryCatalog ensureCategoryCatalog() => $_ensure(5);

  @$pb.TagNumber(7)
  ChapterBookmark get bookmark => $_getN(6);
  @$pb.TagNumber(7)
  set bookmark(ChapterBookmark value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasBookmark() => $_has(6);
  @$pb.TagNumber(7)
  void clearBookmark() => $_clearField(7);
  @$pb.TagNumber(7)
  ChapterBookmark ensureBookmark() => $_ensure(6);
}

class BookmarkPageResponse extends $pb.GeneratedMessage {
  factory BookmarkPageResponse({
    $core.int? schemaVersion,
    $core.int? accountRevision,
    $core.String? mangaKey,
    $core.Iterable<ChapterBookmark>? entries,
    $core.String? nextKey,
    BusinessStateError? error,
  }) {
    final result = BookmarkPageResponse._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (accountRevision != null) result.accountRevision = accountRevision;
    if (mangaKey != null) result.mangaKey = mangaKey;
    if (entries != null) result.entries.addAll(entries);
    if (nextKey != null) result.nextKey = nextKey;
    if (error != null) result.error = error;
    return result;
  }

  BookmarkPageResponse._();

  factory BookmarkPageResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BookmarkPageResponse()..mergeFromBuffer(data, registry);
  factory BookmarkPageResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      BookmarkPageResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'BookmarkPageResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: BookmarkPageResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'accountRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'mangaKey')
    ..pPM<ChapterBookmark>(4, _omitFieldNames ? '' : 'entries',
        subBuilder: ChapterBookmark.$_createMessage)
    ..aOS(5, _omitFieldNames ? '' : 'nextKey')
    ..aOM<BusinessStateError>(6, _omitFieldNames ? '' : 'error',
        subBuilder: BusinessStateError.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BookmarkPageResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  BookmarkPageResponse copyWith(void Function(BookmarkPageResponse) updates) =>
      super.copyWith((message) => updates(message as BookmarkPageResponse))
          as BookmarkPageResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use BookmarkPageResponse() / BookmarkPageResponse.new instead')
  static BookmarkPageResponse create() => BookmarkPageResponse._();
  static $pb.GeneratedMessage $_createMessage() => BookmarkPageResponse._();
  @$core.override
  BookmarkPageResponse createEmptyInstance() => BookmarkPageResponse._();
  @$core.pragma('dart2js:noInline')
  static BookmarkPageResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<BookmarkPageResponse>(
          BookmarkPageResponse.$_createMessage);
  static BookmarkPageResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  /// Subsequent pages must use this revision; a changed revision restarts paging.
  @$pb.TagNumber(2)
  $core.int get accountRevision => $_getIZ(1);
  @$pb.TagNumber(2)
  set accountRevision($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccountRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccountRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get mangaKey => $_getSZ(2);
  @$pb.TagNumber(3)
  set mangaKey($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMangaKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearMangaKey() => $_clearField(3);

  /// Only bookmarked chapters are included, ordered by chapter identity.
  @$pb.TagNumber(4)
  $pb.PbList<ChapterBookmark> get entries => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get nextKey => $_getSZ(4);
  @$pb.TagNumber(5)
  set nextKey($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNextKey() => $_has(4);
  @$pb.TagNumber(5)
  void clearNextKey() => $_clearField(5);

  @$pb.TagNumber(6)
  BusinessStateError get error => $_getN(5);
  @$pb.TagNumber(6)
  set error(BusinessStateError value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  BusinessStateError ensureError() => $_ensure(5);
}

class ChapterProgressPageResponse extends $pb.GeneratedMessage {
  factory ChapterProgressPageResponse({
    $core.int? schemaVersion,
    $core.int? accountRevision,
    $core.String? mangaKey,
    $core.Iterable<ChapterProgressState>? entries,
    $core.String? nextKey,
    BusinessStateError? error,
  }) {
    final result = ChapterProgressPageResponse._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (accountRevision != null) result.accountRevision = accountRevision;
    if (mangaKey != null) result.mangaKey = mangaKey;
    if (entries != null) result.entries.addAll(entries);
    if (nextKey != null) result.nextKey = nextKey;
    if (error != null) result.error = error;
    return result;
  }

  ChapterProgressPageResponse._();

  factory ChapterProgressPageResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterProgressPageResponse()..mergeFromBuffer(data, registry);
  factory ChapterProgressPageResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ChapterProgressPageResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChapterProgressPageResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ChapterProgressPageResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'accountRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'mangaKey')
    ..pPM<ChapterProgressState>(4, _omitFieldNames ? '' : 'entries',
        subBuilder: ChapterProgressState.$_createMessage)
    ..aOS(5, _omitFieldNames ? '' : 'nextKey')
    ..aOM<BusinessStateError>(6, _omitFieldNames ? '' : 'error',
        subBuilder: BusinessStateError.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterProgressPageResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChapterProgressPageResponse copyWith(
          void Function(ChapterProgressPageResponse) updates) =>
      super.copyWith(
              (message) => updates(message as ChapterProgressPageResponse))
          as ChapterProgressPageResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ChapterProgressPageResponse() / ChapterProgressPageResponse.new instead')
  static ChapterProgressPageResponse create() =>
      ChapterProgressPageResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      ChapterProgressPageResponse._();
  @$core.override
  ChapterProgressPageResponse createEmptyInstance() =>
      ChapterProgressPageResponse._();
  @$core.pragma('dart2js:noInline')
  static ChapterProgressPageResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChapterProgressPageResponse>(
          ChapterProgressPageResponse.$_createMessage);
  static ChapterProgressPageResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  /// Subsequent pages must use this revision; a changed revision restarts paging.
  @$pb.TagNumber(2)
  $core.int get accountRevision => $_getIZ(1);
  @$pb.TagNumber(2)
  set accountRevision($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccountRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccountRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get mangaKey => $_getSZ(2);
  @$pb.TagNumber(3)
  set mangaKey($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMangaKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearMangaKey() => $_clearField(3);

  /// Stored read/unread epochs and optional anchors, ordered by chapter identity.
  @$pb.TagNumber(4)
  $pb.PbList<ChapterProgressState> get entries => $_getList(3);

  @$pb.TagNumber(5)
  $core.String get nextKey => $_getSZ(4);
  @$pb.TagNumber(5)
  set nextKey($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNextKey() => $_has(4);
  @$pb.TagNumber(5)
  void clearNextKey() => $_clearField(5);

  @$pb.TagNumber(6)
  BusinessStateError get error => $_getN(5);
  @$pb.TagNumber(6)
  set error(BusinessStateError value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  BusinessStateError ensureError() => $_ensure(5);
}

class LibraryPageResponse extends $pb.GeneratedMessage {
  factory LibraryPageResponse({
    $core.int? schemaVersion,
    $core.int? accountRevision,
    $core.Iterable<MangaState>? entries,
    $core.String? nextKey,
    BusinessStateError? error,
    CategoryCatalog? categoryCatalog,
  }) {
    final result = LibraryPageResponse._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (accountRevision != null) result.accountRevision = accountRevision;
    if (entries != null) result.entries.addAll(entries);
    if (nextKey != null) result.nextKey = nextKey;
    if (error != null) result.error = error;
    if (categoryCatalog != null) result.categoryCatalog = categoryCatalog;
    return result;
  }

  LibraryPageResponse._();

  factory LibraryPageResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LibraryPageResponse()..mergeFromBuffer(data, registry);
  factory LibraryPageResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      LibraryPageResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LibraryPageResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: LibraryPageResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'accountRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..pPM<MangaState>(3, _omitFieldNames ? '' : 'entries',
        subBuilder: MangaState.$_createMessage)
    ..aOS(4, _omitFieldNames ? '' : 'nextKey')
    ..aOM<BusinessStateError>(5, _omitFieldNames ? '' : 'error',
        subBuilder: BusinessStateError.$_createMessage)
    ..aOM<CategoryCatalog>(6, _omitFieldNames ? '' : 'categoryCatalog',
        subBuilder: CategoryCatalog.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LibraryPageResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LibraryPageResponse copyWith(void Function(LibraryPageResponse) updates) =>
      super.copyWith((message) => updates(message as LibraryPageResponse))
          as LibraryPageResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use LibraryPageResponse() / LibraryPageResponse.new instead')
  static LibraryPageResponse create() => LibraryPageResponse._();
  static $pb.GeneratedMessage $_createMessage() => LibraryPageResponse._();
  @$core.override
  LibraryPageResponse createEmptyInstance() => LibraryPageResponse._();
  @$core.pragma('dart2js:noInline')
  static LibraryPageResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LibraryPageResponse>(
          LibraryPageResponse.$_createMessage);
  static LibraryPageResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  /// Subsequent pages must use this revision; a changed revision restarts paging.
  @$pb.TagNumber(2)
  $core.int get accountRevision => $_getIZ(1);
  @$pb.TagNumber(2)
  set accountRevision($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccountRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccountRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<MangaState> get entries => $_getList(2);

  @$pb.TagNumber(4)
  $core.String get nextKey => $_getSZ(3);
  @$pb.TagNumber(4)
  set nextKey($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasNextKey() => $_has(3);
  @$pb.TagNumber(4)
  void clearNextKey() => $_clearField(4);

  @$pb.TagNumber(5)
  BusinessStateError get error => $_getN(4);
  @$pb.TagNumber(5)
  set error(BusinessStateError value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
  @$pb.TagNumber(5)
  BusinessStateError ensureError() => $_ensure(4);

  @$pb.TagNumber(6)
  CategoryCatalog get categoryCatalog => $_getN(5);
  @$pb.TagNumber(6)
  set categoryCatalog(CategoryCatalog value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasCategoryCatalog() => $_has(5);
  @$pb.TagNumber(6)
  void clearCategoryCatalog() => $_clearField(6);
  @$pb.TagNumber(6)
  CategoryCatalog ensureCategoryCatalog() => $_ensure(5);
}

class CategoryMutationResponse extends $pb.GeneratedMessage {
  factory CategoryMutationResponse({
    $core.int? schemaVersion,
    $core.String? mutationId,
    $core.int? accountRevision,
    CategoryCatalog? categoryCatalog,
    BusinessStateError? error,
  }) {
    final result = CategoryMutationResponse._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (mutationId != null) result.mutationId = mutationId;
    if (accountRevision != null) result.accountRevision = accountRevision;
    if (categoryCatalog != null) result.categoryCatalog = categoryCatalog;
    if (error != null) result.error = error;
    return result;
  }

  CategoryMutationResponse._();

  factory CategoryMutationResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CategoryMutationResponse()..mergeFromBuffer(data, registry);
  factory CategoryMutationResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CategoryMutationResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CategoryMutationResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CategoryMutationResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'mutationId')
    ..aI(3, _omitFieldNames ? '' : 'accountRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<CategoryCatalog>(4, _omitFieldNames ? '' : 'categoryCatalog',
        subBuilder: CategoryCatalog.$_createMessage)
    ..aOM<BusinessStateError>(5, _omitFieldNames ? '' : 'error',
        subBuilder: BusinessStateError.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategoryMutationResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategoryMutationResponse copyWith(
          void Function(CategoryMutationResponse) updates) =>
      super.copyWith((message) => updates(message as CategoryMutationResponse))
          as CategoryMutationResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CategoryMutationResponse() / CategoryMutationResponse.new instead')
  static CategoryMutationResponse create() => CategoryMutationResponse._();
  static $pb.GeneratedMessage $_createMessage() => CategoryMutationResponse._();
  @$core.override
  CategoryMutationResponse createEmptyInstance() =>
      CategoryMutationResponse._();
  @$core.pragma('dart2js:noInline')
  static CategoryMutationResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CategoryMutationResponse>(
          CategoryMutationResponse.$_createMessage);
  static CategoryMutationResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mutationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set mutationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMutationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMutationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get accountRevision => $_getIZ(2);
  @$pb.TagNumber(3)
  set accountRevision($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccountRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccountRevision() => $_clearField(3);

  @$pb.TagNumber(4)
  CategoryCatalog get categoryCatalog => $_getN(3);
  @$pb.TagNumber(4)
  set categoryCatalog(CategoryCatalog value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasCategoryCatalog() => $_has(3);
  @$pb.TagNumber(4)
  void clearCategoryCatalog() => $_clearField(4);
  @$pb.TagNumber(4)
  CategoryCatalog ensureCategoryCatalog() => $_ensure(3);

  @$pb.TagNumber(5)
  BusinessStateError get error => $_getN(4);
  @$pb.TagNumber(5)
  set error(BusinessStateError value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
  @$pb.TagNumber(5)
  BusinessStateError ensureError() => $_ensure(4);
}

class CategoryCatalogResponse extends $pb.GeneratedMessage {
  factory CategoryCatalogResponse({
    $core.int? schemaVersion,
    $core.int? accountRevision,
    CategoryCatalog? categoryCatalog,
    BusinessStateError? error,
  }) {
    final result = CategoryCatalogResponse._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (accountRevision != null) result.accountRevision = accountRevision;
    if (categoryCatalog != null) result.categoryCatalog = categoryCatalog;
    if (error != null) result.error = error;
    return result;
  }

  CategoryCatalogResponse._();

  factory CategoryCatalogResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CategoryCatalogResponse()..mergeFromBuffer(data, registry);
  factory CategoryCatalogResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      CategoryCatalogResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CategoryCatalogResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: CategoryCatalogResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'accountRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<CategoryCatalog>(3, _omitFieldNames ? '' : 'categoryCatalog',
        subBuilder: CategoryCatalog.$_createMessage)
    ..aOM<BusinessStateError>(4, _omitFieldNames ? '' : 'error',
        subBuilder: BusinessStateError.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategoryCatalogResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CategoryCatalogResponse copyWith(
          void Function(CategoryCatalogResponse) updates) =>
      super.copyWith((message) => updates(message as CategoryCatalogResponse))
          as CategoryCatalogResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use CategoryCatalogResponse() / CategoryCatalogResponse.new instead')
  static CategoryCatalogResponse create() => CategoryCatalogResponse._();
  static $pb.GeneratedMessage $_createMessage() => CategoryCatalogResponse._();
  @$core.override
  CategoryCatalogResponse createEmptyInstance() => CategoryCatalogResponse._();
  @$core.pragma('dart2js:noInline')
  static CategoryCatalogResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CategoryCatalogResponse>(
          CategoryCatalogResponse.$_createMessage);
  static CategoryCatalogResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get accountRevision => $_getIZ(1);
  @$pb.TagNumber(2)
  set accountRevision($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccountRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccountRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  CategoryCatalog get categoryCatalog => $_getN(2);
  @$pb.TagNumber(3)
  set categoryCatalog(CategoryCatalog value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCategoryCatalog() => $_has(2);
  @$pb.TagNumber(3)
  void clearCategoryCatalog() => $_clearField(3);
  @$pb.TagNumber(3)
  CategoryCatalog ensureCategoryCatalog() => $_ensure(2);

  @$pb.TagNumber(4)
  BusinessStateError get error => $_getN(3);
  @$pb.TagNumber(4)
  set error(BusinessStateError value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);
  @$pb.TagNumber(4)
  BusinessStateError ensureError() => $_ensure(3);
}

class ReaderSettings extends $pb.GeneratedMessage {
  factory ReaderSettings({
    ReaderMode? mode,
    ReaderPageLayout? pageLayout,
    ReaderBackground? background,
    $core.int? dimPercent,
    ReaderInputPreset? tapZones,
    ReaderInputPreset? keyboard,
    ReaderFit? fit,
    $core.bool? cropBorders,
  }) {
    final result = ReaderSettings._();
    if (mode != null) result.mode = mode;
    if (pageLayout != null) result.pageLayout = pageLayout;
    if (background != null) result.background = background;
    if (dimPercent != null) result.dimPercent = dimPercent;
    if (tapZones != null) result.tapZones = tapZones;
    if (keyboard != null) result.keyboard = keyboard;
    if (fit != null) result.fit = fit;
    if (cropBorders != null) result.cropBorders = cropBorders;
    return result;
  }

  ReaderSettings._();

  factory ReaderSettings.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReaderSettings()..mergeFromBuffer(data, registry);
  factory ReaderSettings.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReaderSettings()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReaderSettings',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ReaderSettings.$_createMessage)
    ..aE<ReaderMode>(1, _omitFieldNames ? '' : 'mode',
        enumValues: ReaderMode.values)
    ..aE<ReaderPageLayout>(2, _omitFieldNames ? '' : 'pageLayout',
        enumValues: ReaderPageLayout.values)
    ..aE<ReaderBackground>(3, _omitFieldNames ? '' : 'background',
        enumValues: ReaderBackground.values)
    ..aI(4, _omitFieldNames ? '' : 'dimPercent', fieldType: $pb.PbFieldType.OU3)
    ..aE<ReaderInputPreset>(5, _omitFieldNames ? '' : 'tapZones',
        enumValues: ReaderInputPreset.values)
    ..aE<ReaderInputPreset>(6, _omitFieldNames ? '' : 'keyboard',
        enumValues: ReaderInputPreset.values)
    ..aE<ReaderFit>(7, _omitFieldNames ? '' : 'fit',
        enumValues: ReaderFit.values)
    ..aOB(8, _omitFieldNames ? '' : 'cropBorders')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReaderSettings clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReaderSettings copyWith(void Function(ReaderSettings) updates) =>
      super.copyWith((message) => updates(message as ReaderSettings))
          as ReaderSettings;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use ReaderSettings() / ReaderSettings.new instead')
  static ReaderSettings create() => ReaderSettings._();
  static $pb.GeneratedMessage $_createMessage() => ReaderSettings._();
  @$core.override
  ReaderSettings createEmptyInstance() => ReaderSettings._();
  @$core.pragma('dart2js:noInline')
  static ReaderSettings getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReaderSettings>(
          ReaderSettings.$_createMessage);
  static ReaderSettings? _defaultInstance;

  @$pb.TagNumber(1)
  ReaderMode get mode => $_getN(0);
  @$pb.TagNumber(1)
  set mode(ReaderMode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);

  @$pb.TagNumber(2)
  ReaderPageLayout get pageLayout => $_getN(1);
  @$pb.TagNumber(2)
  set pageLayout(ReaderPageLayout value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPageLayout() => $_has(1);
  @$pb.TagNumber(2)
  void clearPageLayout() => $_clearField(2);

  @$pb.TagNumber(3)
  ReaderBackground get background => $_getN(2);
  @$pb.TagNumber(3)
  set background(ReaderBackground value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasBackground() => $_has(2);
  @$pb.TagNumber(3)
  void clearBackground() => $_clearField(3);

  /// Reading-content dimming only; never changes platform display brightness.
  @$pb.TagNumber(4)
  $core.int get dimPercent => $_getIZ(3);
  @$pb.TagNumber(4)
  set dimPercent($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDimPercent() => $_has(3);
  @$pb.TagNumber(4)
  void clearDimPercent() => $_clearField(4);

  @$pb.TagNumber(5)
  ReaderInputPreset get tapZones => $_getN(4);
  @$pb.TagNumber(5)
  set tapZones(ReaderInputPreset value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasTapZones() => $_has(4);
  @$pb.TagNumber(5)
  void clearTapZones() => $_clearField(5);

  @$pb.TagNumber(6)
  ReaderInputPreset get keyboard => $_getN(5);
  @$pb.TagNumber(6)
  set keyboard(ReaderInputPreset value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasKeyboard() => $_has(5);
  @$pb.TagNumber(6)
  void clearKeyboard() => $_clearField(6);

  @$pb.TagNumber(7)
  ReaderFit get fit => $_getN(6);
  @$pb.TagNumber(7)
  set fit(ReaderFit value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasFit() => $_has(6);
  @$pb.TagNumber(7)
  void clearFit() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get cropBorders => $_getBF(7);
  @$pb.TagNumber(8)
  set cropBorders($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCropBorders() => $_has(7);
  @$pb.TagNumber(8)
  void clearCropBorders() => $_clearField(8);
}

/// Missing fields inherit the global reader preference. AUTO is an explicit
/// value, distinct from inheritance. An empty message clears all overrides.
class ReaderSettingsOverride extends $pb.GeneratedMessage {
  factory ReaderSettingsOverride({
    ReaderMode? mode,
    ReaderPageLayout? pageLayout,
    ReaderBackground? background,
    $core.int? dimPercent,
    ReaderInputPreset? tapZones,
    ReaderInputPreset? keyboard,
    ReaderFit? fit,
    $core.bool? cropBorders,
  }) {
    final result = ReaderSettingsOverride._();
    if (mode != null) result.mode = mode;
    if (pageLayout != null) result.pageLayout = pageLayout;
    if (background != null) result.background = background;
    if (dimPercent != null) result.dimPercent = dimPercent;
    if (tapZones != null) result.tapZones = tapZones;
    if (keyboard != null) result.keyboard = keyboard;
    if (fit != null) result.fit = fit;
    if (cropBorders != null) result.cropBorders = cropBorders;
    return result;
  }

  ReaderSettingsOverride._();

  factory ReaderSettingsOverride.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReaderSettingsOverride()..mergeFromBuffer(data, registry);
  factory ReaderSettingsOverride.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ReaderSettingsOverride()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReaderSettingsOverride',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ReaderSettingsOverride.$_createMessage)
    ..aE<ReaderMode>(1, _omitFieldNames ? '' : 'mode',
        enumValues: ReaderMode.values)
    ..aE<ReaderPageLayout>(2, _omitFieldNames ? '' : 'pageLayout',
        enumValues: ReaderPageLayout.values)
    ..aE<ReaderBackground>(3, _omitFieldNames ? '' : 'background',
        enumValues: ReaderBackground.values)
    ..aI(4, _omitFieldNames ? '' : 'dimPercent', fieldType: $pb.PbFieldType.OU3)
    ..aE<ReaderInputPreset>(5, _omitFieldNames ? '' : 'tapZones',
        enumValues: ReaderInputPreset.values)
    ..aE<ReaderInputPreset>(6, _omitFieldNames ? '' : 'keyboard',
        enumValues: ReaderInputPreset.values)
    ..aE<ReaderFit>(7, _omitFieldNames ? '' : 'fit',
        enumValues: ReaderFit.values)
    ..aOB(8, _omitFieldNames ? '' : 'cropBorders')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReaderSettingsOverride clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReaderSettingsOverride copyWith(
          void Function(ReaderSettingsOverride) updates) =>
      super.copyWith((message) => updates(message as ReaderSettingsOverride))
          as ReaderSettingsOverride;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use ReaderSettingsOverride() / ReaderSettingsOverride.new instead')
  static ReaderSettingsOverride create() => ReaderSettingsOverride._();
  static $pb.GeneratedMessage $_createMessage() => ReaderSettingsOverride._();
  @$core.override
  ReaderSettingsOverride createEmptyInstance() => ReaderSettingsOverride._();
  @$core.pragma('dart2js:noInline')
  static ReaderSettingsOverride getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReaderSettingsOverride>(
          ReaderSettingsOverride.$_createMessage);
  static ReaderSettingsOverride? _defaultInstance;

  @$pb.TagNumber(1)
  ReaderMode get mode => $_getN(0);
  @$pb.TagNumber(1)
  set mode(ReaderMode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);

  @$pb.TagNumber(2)
  ReaderPageLayout get pageLayout => $_getN(1);
  @$pb.TagNumber(2)
  set pageLayout(ReaderPageLayout value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPageLayout() => $_has(1);
  @$pb.TagNumber(2)
  void clearPageLayout() => $_clearField(2);

  @$pb.TagNumber(3)
  ReaderBackground get background => $_getN(2);
  @$pb.TagNumber(3)
  set background(ReaderBackground value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasBackground() => $_has(2);
  @$pb.TagNumber(3)
  void clearBackground() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get dimPercent => $_getIZ(3);
  @$pb.TagNumber(4)
  set dimPercent($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDimPercent() => $_has(3);
  @$pb.TagNumber(4)
  void clearDimPercent() => $_clearField(4);

  @$pb.TagNumber(5)
  ReaderInputPreset get tapZones => $_getN(4);
  @$pb.TagNumber(5)
  set tapZones(ReaderInputPreset value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasTapZones() => $_has(4);
  @$pb.TagNumber(5)
  void clearTapZones() => $_clearField(5);

  @$pb.TagNumber(6)
  ReaderInputPreset get keyboard => $_getN(5);
  @$pb.TagNumber(6)
  set keyboard(ReaderInputPreset value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasKeyboard() => $_has(5);
  @$pb.TagNumber(6)
  void clearKeyboard() => $_clearField(6);

  @$pb.TagNumber(7)
  ReaderFit get fit => $_getN(6);
  @$pb.TagNumber(7)
  set fit(ReaderFit value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasFit() => $_has(6);
  @$pb.TagNumber(7)
  void clearFit() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.bool get cropBorders => $_getBF(7);
  @$pb.TagNumber(8)
  set cropBorders($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCropBorders() => $_has(7);
  @$pb.TagNumber(8)
  void clearCropBorders() => $_clearField(8);
}

/// Source identity stays independent of the currently published build or runtime.
/// Names and languages are display snapshots, never identity components.
class FavoriteSource extends $pb.GeneratedMessage {
  factory FavoriteSource({
    $core.String? packageName,
    $core.String? sourceId,
    $core.String? sourceName,
    $core.String? sourceLang,
  }) {
    final result = FavoriteSource._();
    if (packageName != null) result.packageName = packageName;
    if (sourceId != null) result.sourceId = sourceId;
    if (sourceName != null) result.sourceName = sourceName;
    if (sourceLang != null) result.sourceLang = sourceLang;
    return result;
  }

  FavoriteSource._();

  factory FavoriteSource.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FavoriteSource()..mergeFromBuffer(data, registry);
  factory FavoriteSource.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FavoriteSource()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FavoriteSource',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: FavoriteSource.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'packageName')
    ..aOS(2, _omitFieldNames ? '' : 'sourceId')
    ..aOS(3, _omitFieldNames ? '' : 'sourceName')
    ..aOS(4, _omitFieldNames ? '' : 'sourceLang')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FavoriteSource clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FavoriteSource copyWith(void Function(FavoriteSource) updates) =>
      super.copyWith((message) => updates(message as FavoriteSource))
          as FavoriteSource;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FavoriteSource() / FavoriteSource.new instead')
  static FavoriteSource create() => FavoriteSource._();
  static $pb.GeneratedMessage $_createMessage() => FavoriteSource._();
  @$core.override
  FavoriteSource createEmptyInstance() => FavoriteSource._();
  @$core.pragma('dart2js:noInline')
  static FavoriteSource getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FavoriteSource>(
          FavoriteSource.$_createMessage);
  static FavoriteSource? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get packageName => $_getSZ(0);
  @$pb.TagNumber(1)
  set packageName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPackageName() => $_has(0);
  @$pb.TagNumber(1)
  void clearPackageName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sourceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSourceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get sourceName => $_getSZ(2);
  @$pb.TagNumber(3)
  set sourceName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSourceName() => $_has(2);
  @$pb.TagNumber(3)
  void clearSourceName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get sourceLang => $_getSZ(3);
  @$pb.TagNumber(4)
  set sourceLang($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSourceLang() => $_has(3);
  @$pb.TagNumber(4)
  void clearSourceLang() => $_clearField(4);
}

/// Confirmed account intent, separate from each client's disposable code cache.
/// A package has one selected repository/build; replacement is explicit.
class InstalledExtension extends $pb.GeneratedMessage {
  factory InstalledExtension({
    $core.String? catalogUrl,
    $core.String? repoId,
    $core.String? packageName,
    $core.String? buildId,
    $core.String? bundleSha256,
    $core.bool? enabled,
  }) {
    final result = InstalledExtension._();
    if (catalogUrl != null) result.catalogUrl = catalogUrl;
    if (repoId != null) result.repoId = repoId;
    if (packageName != null) result.packageName = packageName;
    if (buildId != null) result.buildId = buildId;
    if (bundleSha256 != null) result.bundleSha256 = bundleSha256;
    if (enabled != null) result.enabled = enabled;
    return result;
  }

  InstalledExtension._();

  factory InstalledExtension.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InstalledExtension()..mergeFromBuffer(data, registry);
  factory InstalledExtension.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      InstalledExtension()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InstalledExtension',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: InstalledExtension.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'catalogUrl')
    ..aOS(2, _omitFieldNames ? '' : 'repoId')
    ..aOS(3, _omitFieldNames ? '' : 'packageName')
    ..aOS(4, _omitFieldNames ? '' : 'buildId')
    ..aOS(5, _omitFieldNames ? '' : 'bundleSha256')
    ..aOB(6, _omitFieldNames ? '' : 'enabled')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InstalledExtension clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InstalledExtension copyWith(void Function(InstalledExtension) updates) =>
      super.copyWith((message) => updates(message as InstalledExtension))
          as InstalledExtension;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use InstalledExtension() / InstalledExtension.new instead')
  static InstalledExtension create() => InstalledExtension._();
  static $pb.GeneratedMessage $_createMessage() => InstalledExtension._();
  @$core.override
  InstalledExtension createEmptyInstance() => InstalledExtension._();
  @$core.pragma('dart2js:noInline')
  static InstalledExtension getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InstalledExtension>(
          InstalledExtension.$_createMessage);
  static InstalledExtension? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get packageName => $_getSZ(2);
  @$pb.TagNumber(3)
  set packageName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPackageName() => $_has(2);
  @$pb.TagNumber(3)
  void clearPackageName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get buildId => $_getSZ(3);
  @$pb.TagNumber(4)
  set buildId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBuildId() => $_has(3);
  @$pb.TagNumber(4)
  void clearBuildId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get bundleSha256 => $_getSZ(4);
  @$pb.TagNumber(5)
  set bundleSha256($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBundleSha256() => $_has(4);
  @$pb.TagNumber(5)
  void clearBundleSha256() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get enabled => $_getBF(5);
  @$pb.TagNumber(6)
  set enabled($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasEnabled() => $_has(5);
  @$pb.TagNumber(6)
  void clearEnabled() => $_clearField(6);
}

class ExtensionRepository extends $pb.GeneratedMessage {
  factory ExtensionRepository({
    $core.String? catalogUrl,
    $core.String? repoId,
    $core.String? name,
  }) {
    final result = ExtensionRepository._();
    if (catalogUrl != null) result.catalogUrl = catalogUrl;
    if (repoId != null) result.repoId = repoId;
    if (name != null) result.name = name;
    return result;
  }

  ExtensionRepository._();

  factory ExtensionRepository.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExtensionRepository()..mergeFromBuffer(data, registry);
  factory ExtensionRepository.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      ExtensionRepository()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ExtensionRepository',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: ExtensionRepository.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'catalogUrl')
    ..aOS(2, _omitFieldNames ? '' : 'repoId')
    ..aOS(3, _omitFieldNames ? '' : 'name')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExtensionRepository clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ExtensionRepository copyWith(void Function(ExtensionRepository) updates) =>
      super.copyWith((message) => updates(message as ExtensionRepository))
          as ExtensionRepository;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use ExtensionRepository() / ExtensionRepository.new instead')
  static ExtensionRepository create() => ExtensionRepository._();
  static $pb.GeneratedMessage $_createMessage() => ExtensionRepository._();
  @$core.override
  ExtensionRepository createEmptyInstance() => ExtensionRepository._();
  @$core.pragma('dart2js:noInline')
  static ExtensionRepository getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ExtensionRepository>(
          ExtensionRepository.$_createMessage);
  static ExtensionRepository? _defaultInstance;

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

  @$pb.TagNumber(3)
  $core.String get name => $_getSZ(2);
  @$pb.TagNumber(3)
  set name($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasName() => $_has(2);
  @$pb.TagNumber(3)
  void clearName() => $_clearField(3);
}

class GlobalSettingsValues extends $pb.GeneratedMessage {
  factory GlobalSettingsValues({
    AppTheme? theme,
    ReaderSettings? reader,
    $core.Iterable<FavoriteSource>? favoriteSources,
    $core.Iterable<InstalledExtension>? installedExtensions,
    $core.Iterable<ExtensionRepository>? repositories,
  }) {
    final result = GlobalSettingsValues._();
    if (theme != null) result.theme = theme;
    if (reader != null) result.reader = reader;
    if (favoriteSources != null) result.favoriteSources.addAll(favoriteSources);
    if (installedExtensions != null)
      result.installedExtensions.addAll(installedExtensions);
    if (repositories != null) result.repositories.addAll(repositories);
    return result;
  }

  GlobalSettingsValues._();

  factory GlobalSettingsValues.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GlobalSettingsValues()..mergeFromBuffer(data, registry);
  factory GlobalSettingsValues.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GlobalSettingsValues()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GlobalSettingsValues',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: GlobalSettingsValues.$_createMessage)
    ..aE<AppTheme>(1, _omitFieldNames ? '' : 'theme',
        enumValues: AppTheme.values)
    ..aOM<ReaderSettings>(2, _omitFieldNames ? '' : 'reader',
        subBuilder: ReaderSettings.$_createMessage)
    ..pPM<FavoriteSource>(3, _omitFieldNames ? '' : 'favoriteSources',
        subBuilder: FavoriteSource.$_createMessage)
    ..pPM<InstalledExtension>(4, _omitFieldNames ? '' : 'installedExtensions',
        subBuilder: InstalledExtension.$_createMessage)
    ..pPM<ExtensionRepository>(5, _omitFieldNames ? '' : 'repositories',
        subBuilder: ExtensionRepository.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GlobalSettingsValues clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GlobalSettingsValues copyWith(void Function(GlobalSettingsValues) updates) =>
      super.copyWith((message) => updates(message as GlobalSettingsValues))
          as GlobalSettingsValues;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use GlobalSettingsValues() / GlobalSettingsValues.new instead')
  static GlobalSettingsValues create() => GlobalSettingsValues._();
  static $pb.GeneratedMessage $_createMessage() => GlobalSettingsValues._();
  @$core.override
  GlobalSettingsValues createEmptyInstance() => GlobalSettingsValues._();
  @$core.pragma('dart2js:noInline')
  static GlobalSettingsValues getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GlobalSettingsValues>(
          GlobalSettingsValues.$_createMessage);
  static GlobalSettingsValues? _defaultInstance;

  @$pb.TagNumber(1)
  AppTheme get theme => $_getN(0);
  @$pb.TagNumber(1)
  set theme(AppTheme value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasTheme() => $_has(0);
  @$pb.TagNumber(1)
  void clearTheme() => $_clearField(1);

  @$pb.TagNumber(2)
  ReaderSettings get reader => $_getN(1);
  @$pb.TagNumber(2)
  set reader(ReaderSettings value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasReader() => $_has(1);
  @$pb.TagNumber(2)
  void clearReader() => $_clearField(2);
  @$pb.TagNumber(2)
  ReaderSettings ensureReader() => $_ensure(1);

  @$pb.TagNumber(3)
  $pb.PbList<FavoriteSource> get favoriteSources => $_getList(2);

  @$pb.TagNumber(4)
  $pb.PbList<InstalledExtension> get installedExtensions => $_getList(3);

  @$pb.TagNumber(5)
  $pb.PbList<ExtensionRepository> get repositories => $_getList(4);
}

class GlobalSettings extends $pb.GeneratedMessage {
  factory GlobalSettings({
    $core.int? revision,
    GlobalSettingsValues? values,
  }) {
    final result = GlobalSettings._();
    if (revision != null) result.revision = revision;
    if (values != null) result.values = values;
    return result;
  }

  GlobalSettings._();

  factory GlobalSettings.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GlobalSettings()..mergeFromBuffer(data, registry);
  factory GlobalSettings.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      GlobalSettings()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GlobalSettings',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: GlobalSettings.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'revision', fieldType: $pb.PbFieldType.OU3)
    ..aOM<GlobalSettingsValues>(2, _omitFieldNames ? '' : 'values',
        subBuilder: GlobalSettingsValues.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GlobalSettings clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GlobalSettings copyWith(void Function(GlobalSettings) updates) =>
      super.copyWith((message) => updates(message as GlobalSettings))
          as GlobalSettings;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use GlobalSettings() / GlobalSettings.new instead')
  static GlobalSettings create() => GlobalSettings._();
  static $pb.GeneratedMessage $_createMessage() => GlobalSettings._();
  @$core.override
  GlobalSettings createEmptyInstance() => GlobalSettings._();
  @$core.pragma('dart2js:noInline')
  static GlobalSettings getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GlobalSettings>(
          GlobalSettings.$_createMessage);
  static GlobalSettings? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get revision => $_getIZ(0);
  @$pb.TagNumber(1)
  set revision($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRevision() => $_has(0);
  @$pb.TagNumber(1)
  void clearRevision() => $_clearField(1);

  @$pb.TagNumber(2)
  GlobalSettingsValues get values => $_getN(1);
  @$pb.TagNumber(2)
  set values(GlobalSettingsValues value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasValues() => $_has(1);
  @$pb.TagNumber(2)
  void clearValues() => $_clearField(2);
  @$pb.TagNumber(2)
  GlobalSettingsValues ensureValues() => $_ensure(1);
}

class MangaReaderSettings extends $pb.GeneratedMessage {
  factory MangaReaderSettings({
    $core.String? mangaKey,
    $core.int? revision,
    ReaderSettingsOverride? overrides,
  }) {
    final result = MangaReaderSettings._();
    if (mangaKey != null) result.mangaKey = mangaKey;
    if (revision != null) result.revision = revision;
    if (overrides != null) result.overrides = overrides;
    return result;
  }

  MangaReaderSettings._();

  factory MangaReaderSettings.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaReaderSettings()..mergeFromBuffer(data, registry);
  factory MangaReaderSettings.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      MangaReaderSettings()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MangaReaderSettings',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: MangaReaderSettings.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'mangaKey')
    ..aI(2, _omitFieldNames ? '' : 'revision', fieldType: $pb.PbFieldType.OU3)
    ..aOM<ReaderSettingsOverride>(3, _omitFieldNames ? '' : 'overrides',
        subBuilder: ReaderSettingsOverride.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaReaderSettings clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MangaReaderSettings copyWith(void Function(MangaReaderSettings) updates) =>
      super.copyWith((message) => updates(message as MangaReaderSettings))
          as MangaReaderSettings;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core
      .Deprecated('Use MangaReaderSettings() / MangaReaderSettings.new instead')
  static MangaReaderSettings create() => MangaReaderSettings._();
  static $pb.GeneratedMessage $_createMessage() => MangaReaderSettings._();
  @$core.override
  MangaReaderSettings createEmptyInstance() => MangaReaderSettings._();
  @$core.pragma('dart2js:noInline')
  static MangaReaderSettings getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MangaReaderSettings>(
          MangaReaderSettings.$_createMessage);
  static MangaReaderSettings? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mangaKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set mangaKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMangaKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearMangaKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get revision => $_getIZ(1);
  @$pb.TagNumber(2)
  set revision($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  ReaderSettingsOverride get overrides => $_getN(2);
  @$pb.TagNumber(3)
  set overrides(ReaderSettingsOverride value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasOverrides() => $_has(2);
  @$pb.TagNumber(3)
  void clearOverrides() => $_clearField(3);
  @$pb.TagNumber(3)
  ReaderSettingsOverride ensureOverrides() => $_ensure(2);
}

class SetMangaReaderSettings extends $pb.GeneratedMessage {
  factory SetMangaReaderSettings({
    $core.String? mangaKey,
    ReaderSettingsOverride? overrides,
  }) {
    final result = SetMangaReaderSettings._();
    if (mangaKey != null) result.mangaKey = mangaKey;
    if (overrides != null) result.overrides = overrides;
    return result;
  }

  SetMangaReaderSettings._();

  factory SetMangaReaderSettings.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetMangaReaderSettings()..mergeFromBuffer(data, registry);
  factory SetMangaReaderSettings.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SetMangaReaderSettings()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetMangaReaderSettings',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SetMangaReaderSettings.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'mangaKey')
    ..aOM<ReaderSettingsOverride>(2, _omitFieldNames ? '' : 'overrides',
        subBuilder: ReaderSettingsOverride.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMangaReaderSettings clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetMangaReaderSettings copyWith(
          void Function(SetMangaReaderSettings) updates) =>
      super.copyWith((message) => updates(message as SetMangaReaderSettings))
          as SetMangaReaderSettings;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SetMangaReaderSettings() / SetMangaReaderSettings.new instead')
  static SetMangaReaderSettings create() => SetMangaReaderSettings._();
  static $pb.GeneratedMessage $_createMessage() => SetMangaReaderSettings._();
  @$core.override
  SetMangaReaderSettings createEmptyInstance() => SetMangaReaderSettings._();
  @$core.pragma('dart2js:noInline')
  static SetMangaReaderSettings getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetMangaReaderSettings>(
          SetMangaReaderSettings.$_createMessage);
  static SetMangaReaderSettings? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mangaKey => $_getSZ(0);
  @$pb.TagNumber(1)
  set mangaKey($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMangaKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearMangaKey() => $_clearField(1);

  @$pb.TagNumber(2)
  ReaderSettingsOverride get overrides => $_getN(1);
  @$pb.TagNumber(2)
  set overrides(ReaderSettingsOverride value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOverrides() => $_has(1);
  @$pb.TagNumber(2)
  void clearOverrides() => $_clearField(2);
  @$pb.TagNumber(2)
  ReaderSettingsOverride ensureOverrides() => $_ensure(1);
}

enum SettingsMutation_Operation { setGlobal, setManga, notSet }

class SettingsMutation extends $pb.GeneratedMessage {
  factory SettingsMutation({
    $core.int? schemaVersion,
    $core.String? mutationId,
    $core.int? expectedRevision,
    GlobalSettingsValues? setGlobal,
    SetMangaReaderSettings? setManga,
  }) {
    final result = SettingsMutation._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (mutationId != null) result.mutationId = mutationId;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    if (setGlobal != null) result.setGlobal = setGlobal;
    if (setManga != null) result.setManga = setManga;
    return result;
  }

  SettingsMutation._();

  factory SettingsMutation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SettingsMutation()..mergeFromBuffer(data, registry);
  factory SettingsMutation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SettingsMutation()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, SettingsMutation_Operation>
      _SettingsMutation_OperationByTag = {
    10: SettingsMutation_Operation.setGlobal,
    11: SettingsMutation_Operation.setManga,
    0: SettingsMutation_Operation.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SettingsMutation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SettingsMutation.$_createMessage)
    ..oo(0, [10, 11])
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'mutationId')
    ..aI(3, _omitFieldNames ? '' : 'expectedRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<GlobalSettingsValues>(10, _omitFieldNames ? '' : 'setGlobal',
        subBuilder: GlobalSettingsValues.$_createMessage)
    ..aOM<SetMangaReaderSettings>(11, _omitFieldNames ? '' : 'setManga',
        subBuilder: SetMangaReaderSettings.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SettingsMutation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SettingsMutation copyWith(void Function(SettingsMutation) updates) =>
      super.copyWith((message) => updates(message as SettingsMutation))
          as SettingsMutation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SettingsMutation() / SettingsMutation.new instead')
  static SettingsMutation create() => SettingsMutation._();
  static $pb.GeneratedMessage $_createMessage() => SettingsMutation._();
  @$core.override
  SettingsMutation createEmptyInstance() => SettingsMutation._();
  @$core.pragma('dart2js:noInline')
  static SettingsMutation getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SettingsMutation>(
          SettingsMutation.$_createMessage);
  static SettingsMutation? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  SettingsMutation_Operation whichOperation() =>
      _SettingsMutation_OperationByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  void clearOperation() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mutationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set mutationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMutationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMutationId() => $_clearField(2);

  /// CAS for the selected scope, independent of reading-progress revisions.
  @$pb.TagNumber(3)
  $core.int get expectedRevision => $_getIZ(2);
  @$pb.TagNumber(3)
  set expectedRevision($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasExpectedRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearExpectedRevision() => $_clearField(3);

  @$pb.TagNumber(10)
  GlobalSettingsValues get setGlobal => $_getN(3);
  @$pb.TagNumber(10)
  set setGlobal(GlobalSettingsValues value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasSetGlobal() => $_has(3);
  @$pb.TagNumber(10)
  void clearSetGlobal() => $_clearField(10);
  @$pb.TagNumber(10)
  GlobalSettingsValues ensureSetGlobal() => $_ensure(3);

  @$pb.TagNumber(11)
  SetMangaReaderSettings get setManga => $_getN(4);
  @$pb.TagNumber(11)
  set setManga(SetMangaReaderSettings value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasSetManga() => $_has(4);
  @$pb.TagNumber(11)
  void clearSetManga() => $_clearField(11);
  @$pb.TagNumber(11)
  SetMangaReaderSettings ensureSetManga() => $_ensure(4);
}

class SettingsResponse extends $pb.GeneratedMessage {
  factory SettingsResponse({
    $core.int? schemaVersion,
    $core.int? accountRevision,
    GlobalSettings? global,
    MangaReaderSettings? manga,
    ReaderSettings? effectiveReader,
    BusinessStateError? error,
  }) {
    final result = SettingsResponse._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (accountRevision != null) result.accountRevision = accountRevision;
    if (global != null) result.global = global;
    if (manga != null) result.manga = manga;
    if (effectiveReader != null) result.effectiveReader = effectiveReader;
    if (error != null) result.error = error;
    return result;
  }

  SettingsResponse._();

  factory SettingsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SettingsResponse()..mergeFromBuffer(data, registry);
  factory SettingsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SettingsResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SettingsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SettingsResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'accountRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<GlobalSettings>(3, _omitFieldNames ? '' : 'global',
        subBuilder: GlobalSettings.$_createMessage)
    ..aOM<MangaReaderSettings>(4, _omitFieldNames ? '' : 'manga',
        subBuilder: MangaReaderSettings.$_createMessage)
    ..aOM<ReaderSettings>(5, _omitFieldNames ? '' : 'effectiveReader',
        subBuilder: ReaderSettings.$_createMessage)
    ..aOM<BusinessStateError>(6, _omitFieldNames ? '' : 'error',
        subBuilder: BusinessStateError.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SettingsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SettingsResponse copyWith(void Function(SettingsResponse) updates) =>
      super.copyWith((message) => updates(message as SettingsResponse))
          as SettingsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SettingsResponse() / SettingsResponse.new instead')
  static SettingsResponse create() => SettingsResponse._();
  static $pb.GeneratedMessage $_createMessage() => SettingsResponse._();
  @$core.override
  SettingsResponse createEmptyInstance() => SettingsResponse._();
  @$core.pragma('dart2js:noInline')
  static SettingsResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SettingsResponse>(
          SettingsResponse.$_createMessage);
  static SettingsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get accountRevision => $_getIZ(1);
  @$pb.TagNumber(2)
  set accountRevision($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccountRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccountRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  GlobalSettings get global => $_getN(2);
  @$pb.TagNumber(3)
  set global(GlobalSettings value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasGlobal() => $_has(2);
  @$pb.TagNumber(3)
  void clearGlobal() => $_clearField(3);
  @$pb.TagNumber(3)
  GlobalSettings ensureGlobal() => $_ensure(2);

  /// Present only for a manga-scoped request, even when no row exists yet.
  @$pb.TagNumber(4)
  MangaReaderSettings get manga => $_getN(3);
  @$pb.TagNumber(4)
  set manga(MangaReaderSettings value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasManga() => $_has(3);
  @$pb.TagNumber(4)
  void clearManga() => $_clearField(4);
  @$pb.TagNumber(4)
  MangaReaderSettings ensureManga() => $_ensure(3);

  @$pb.TagNumber(5)
  ReaderSettings get effectiveReader => $_getN(4);
  @$pb.TagNumber(5)
  set effectiveReader(ReaderSettings value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasEffectiveReader() => $_has(4);
  @$pb.TagNumber(5)
  void clearEffectiveReader() => $_clearField(5);
  @$pb.TagNumber(5)
  ReaderSettings ensureEffectiveReader() => $_ensure(4);

  @$pb.TagNumber(6)
  BusinessStateError get error => $_getN(5);
  @$pb.TagNumber(6)
  set error(BusinessStateError value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);
  @$pb.TagNumber(6)
  BusinessStateError ensureError() => $_ensure(5);
}

class SettingsMutationResponse extends $pb.GeneratedMessage {
  factory SettingsMutationResponse({
    $core.int? schemaVersion,
    $core.String? mutationId,
    $core.int? accountRevision,
    GlobalSettings? global,
    MangaReaderSettings? manga,
    ReaderSettings? effectiveReader,
    BusinessStateError? error,
  }) {
    final result = SettingsMutationResponse._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (mutationId != null) result.mutationId = mutationId;
    if (accountRevision != null) result.accountRevision = accountRevision;
    if (global != null) result.global = global;
    if (manga != null) result.manga = manga;
    if (effectiveReader != null) result.effectiveReader = effectiveReader;
    if (error != null) result.error = error;
    return result;
  }

  SettingsMutationResponse._();

  factory SettingsMutationResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SettingsMutationResponse()..mergeFromBuffer(data, registry);
  factory SettingsMutationResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SettingsMutationResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SettingsMutationResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SettingsMutationResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'mutationId')
    ..aI(3, _omitFieldNames ? '' : 'accountRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<GlobalSettings>(4, _omitFieldNames ? '' : 'global',
        subBuilder: GlobalSettings.$_createMessage)
    ..aOM<MangaReaderSettings>(5, _omitFieldNames ? '' : 'manga',
        subBuilder: MangaReaderSettings.$_createMessage)
    ..aOM<ReaderSettings>(6, _omitFieldNames ? '' : 'effectiveReader',
        subBuilder: ReaderSettings.$_createMessage)
    ..aOM<BusinessStateError>(7, _omitFieldNames ? '' : 'error',
        subBuilder: BusinessStateError.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SettingsMutationResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SettingsMutationResponse copyWith(
          void Function(SettingsMutationResponse) updates) =>
      super.copyWith((message) => updates(message as SettingsMutationResponse))
          as SettingsMutationResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SettingsMutationResponse() / SettingsMutationResponse.new instead')
  static SettingsMutationResponse create() => SettingsMutationResponse._();
  static $pb.GeneratedMessage $_createMessage() => SettingsMutationResponse._();
  @$core.override
  SettingsMutationResponse createEmptyInstance() =>
      SettingsMutationResponse._();
  @$core.pragma('dart2js:noInline')
  static SettingsMutationResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SettingsMutationResponse>(
          SettingsMutationResponse.$_createMessage);
  static SettingsMutationResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mutationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set mutationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMutationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMutationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get accountRevision => $_getIZ(2);
  @$pb.TagNumber(3)
  set accountRevision($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccountRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccountRevision() => $_clearField(3);

  @$pb.TagNumber(4)
  GlobalSettings get global => $_getN(3);
  @$pb.TagNumber(4)
  set global(GlobalSettings value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasGlobal() => $_has(3);
  @$pb.TagNumber(4)
  void clearGlobal() => $_clearField(4);
  @$pb.TagNumber(4)
  GlobalSettings ensureGlobal() => $_ensure(3);

  @$pb.TagNumber(5)
  MangaReaderSettings get manga => $_getN(4);
  @$pb.TagNumber(5)
  set manga(MangaReaderSettings value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasManga() => $_has(4);
  @$pb.TagNumber(5)
  void clearManga() => $_clearField(5);
  @$pb.TagNumber(5)
  MangaReaderSettings ensureManga() => $_ensure(4);

  @$pb.TagNumber(6)
  ReaderSettings get effectiveReader => $_getN(5);
  @$pb.TagNumber(6)
  set effectiveReader(ReaderSettings value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasEffectiveReader() => $_has(5);
  @$pb.TagNumber(6)
  void clearEffectiveReader() => $_clearField(6);
  @$pb.TagNumber(6)
  ReaderSettings ensureEffectiveReader() => $_ensure(5);

  @$pb.TagNumber(7)
  BusinessStateError get error => $_getN(6);
  @$pb.TagNumber(7)
  set error(BusinessStateError value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasError() => $_has(6);
  @$pb.TagNumber(7)
  void clearError() => $_clearField(7);
  @$pb.TagNumber(7)
  BusinessStateError ensureError() => $_ensure(6);
}

/// Source values are independent of reading settings and build/generation IDs.
/// Full replacement allows removing a stored key without conflating it with
/// false, zero, an empty string or an empty string set.
class SourcePreferences extends $pb.GeneratedMessage {
  factory SourcePreferences({
    $core.String? packageName,
    $core.String? sourceId,
    $core.int? revision,
    $core.Iterable<$0.PreferenceEntry>? entries,
  }) {
    final result = SourcePreferences._();
    if (packageName != null) result.packageName = packageName;
    if (sourceId != null) result.sourceId = sourceId;
    if (revision != null) result.revision = revision;
    if (entries != null) result.entries.addAll(entries);
    return result;
  }

  SourcePreferences._();

  factory SourcePreferences.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourcePreferences()..mergeFromBuffer(data, registry);
  factory SourcePreferences.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourcePreferences()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SourcePreferences',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SourcePreferences.$_createMessage)
    ..aOS(1, _omitFieldNames ? '' : 'packageName')
    ..aOS(2, _omitFieldNames ? '' : 'sourceId')
    ..aI(3, _omitFieldNames ? '' : 'revision', fieldType: $pb.PbFieldType.OU3)
    ..pPM<$0.PreferenceEntry>(4, _omitFieldNames ? '' : 'entries',
        subBuilder: $0.PreferenceEntry.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourcePreferences clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourcePreferences copyWith(void Function(SourcePreferences) updates) =>
      super.copyWith((message) => updates(message as SourcePreferences))
          as SourcePreferences;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use SourcePreferences() / SourcePreferences.new instead')
  static SourcePreferences create() => SourcePreferences._();
  static $pb.GeneratedMessage $_createMessage() => SourcePreferences._();
  @$core.override
  SourcePreferences createEmptyInstance() => SourcePreferences._();
  @$core.pragma('dart2js:noInline')
  static SourcePreferences getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SourcePreferences>(
          SourcePreferences.$_createMessage);
  static SourcePreferences? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get packageName => $_getSZ(0);
  @$pb.TagNumber(1)
  set packageName($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPackageName() => $_has(0);
  @$pb.TagNumber(1)
  void clearPackageName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sourceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSourceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get revision => $_getIZ(2);
  @$pb.TagNumber(3)
  set revision($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearRevision() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<$0.PreferenceEntry> get entries => $_getList(3);
}

class SourcePreferencesResponse extends $pb.GeneratedMessage {
  factory SourcePreferencesResponse({
    $core.int? schemaVersion,
    $core.int? accountRevision,
    $core.String? packageName,
    $core.Iterable<SourcePreferences>? sources,
    BusinessStateError? error,
    $0.CatalogReference? catalog,
    $core.Iterable<$0.PreferenceSyncRule>? syncRules,
  }) {
    final result = SourcePreferencesResponse._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (accountRevision != null) result.accountRevision = accountRevision;
    if (packageName != null) result.packageName = packageName;
    if (sources != null) result.sources.addAll(sources);
    if (error != null) result.error = error;
    if (catalog != null) result.catalog = catalog;
    if (syncRules != null) result.syncRules.addAll(syncRules);
    return result;
  }

  SourcePreferencesResponse._();

  factory SourcePreferencesResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourcePreferencesResponse()..mergeFromBuffer(data, registry);
  factory SourcePreferencesResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourcePreferencesResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SourcePreferencesResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SourcePreferencesResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'accountRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'packageName')
    ..pPM<SourcePreferences>(4, _omitFieldNames ? '' : 'sources',
        subBuilder: SourcePreferences.$_createMessage)
    ..aOM<BusinessStateError>(5, _omitFieldNames ? '' : 'error',
        subBuilder: BusinessStateError.$_createMessage)
    ..aOM<$0.CatalogReference>(6, _omitFieldNames ? '' : 'catalog',
        subBuilder: $0.CatalogReference.$_createMessage)
    ..pPM<$0.PreferenceSyncRule>(7, _omitFieldNames ? '' : 'syncRules',
        subBuilder: $0.PreferenceSyncRule.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourcePreferencesResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourcePreferencesResponse copyWith(
          void Function(SourcePreferencesResponse) updates) =>
      super.copyWith((message) => updates(message as SourcePreferencesResponse))
          as SourcePreferencesResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SourcePreferencesResponse() / SourcePreferencesResponse.new instead')
  static SourcePreferencesResponse create() => SourcePreferencesResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      SourcePreferencesResponse._();
  @$core.override
  SourcePreferencesResponse createEmptyInstance() =>
      SourcePreferencesResponse._();
  @$core.pragma('dart2js:noInline')
  static SourcePreferencesResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SourcePreferencesResponse>(
          SourcePreferencesResponse.$_createMessage);
  static SourcePreferencesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get accountRevision => $_getIZ(1);
  @$pb.TagNumber(2)
  set accountRevision($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAccountRevision() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccountRevision() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get packageName => $_getSZ(2);
  @$pb.TagNumber(3)
  set packageName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPackageName() => $_has(2);
  @$pb.TagNumber(3)
  void clearPackageName() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<SourcePreferences> get sources => $_getList(3);

  @$pb.TagNumber(5)
  BusinessStateError get error => $_getN(4);
  @$pb.TagNumber(5)
  set error(BusinessStateError value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
  @$pb.TagNumber(5)
  BusinessStateError ensureError() => $_ensure(4);

  @$pb.TagNumber(6)
  $0.CatalogReference get catalog => $_getN(5);
  @$pb.TagNumber(6)
  set catalog($0.CatalogReference value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasCatalog() => $_has(5);
  @$pb.TagNumber(6)
  void clearCatalog() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.CatalogReference ensureCatalog() => $_ensure(5);

  @$pb.TagNumber(7)
  $pb.PbList<$0.PreferenceSyncRule> get syncRules => $_getList(6);
}

class SourcePreferencesMutation extends $pb.GeneratedMessage {
  factory SourcePreferencesMutation({
    $core.int? schemaVersion,
    $core.String? mutationId,
    $core.String? packageName,
    $core.String? sourceId,
    $core.int? expectedRevision,
    $core.Iterable<$0.PreferenceEntry>? entries,
    $0.CatalogReference? catalog,
  }) {
    final result = SourcePreferencesMutation._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (mutationId != null) result.mutationId = mutationId;
    if (packageName != null) result.packageName = packageName;
    if (sourceId != null) result.sourceId = sourceId;
    if (expectedRevision != null) result.expectedRevision = expectedRevision;
    if (entries != null) result.entries.addAll(entries);
    if (catalog != null) result.catalog = catalog;
    return result;
  }

  SourcePreferencesMutation._();

  factory SourcePreferencesMutation.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourcePreferencesMutation()..mergeFromBuffer(data, registry);
  factory SourcePreferencesMutation.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourcePreferencesMutation()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SourcePreferencesMutation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SourcePreferencesMutation.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'mutationId')
    ..aOS(3, _omitFieldNames ? '' : 'packageName')
    ..aOS(4, _omitFieldNames ? '' : 'sourceId')
    ..aI(5, _omitFieldNames ? '' : 'expectedRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..pPM<$0.PreferenceEntry>(6, _omitFieldNames ? '' : 'entries',
        subBuilder: $0.PreferenceEntry.$_createMessage)
    ..aOM<$0.CatalogReference>(7, _omitFieldNames ? '' : 'catalog',
        subBuilder: $0.CatalogReference.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourcePreferencesMutation clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourcePreferencesMutation copyWith(
          void Function(SourcePreferencesMutation) updates) =>
      super.copyWith((message) => updates(message as SourcePreferencesMutation))
          as SourcePreferencesMutation;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SourcePreferencesMutation() / SourcePreferencesMutation.new instead')
  static SourcePreferencesMutation create() => SourcePreferencesMutation._();
  static $pb.GeneratedMessage $_createMessage() =>
      SourcePreferencesMutation._();
  @$core.override
  SourcePreferencesMutation createEmptyInstance() =>
      SourcePreferencesMutation._();
  @$core.pragma('dart2js:noInline')
  static SourcePreferencesMutation getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SourcePreferencesMutation>(
          SourcePreferencesMutation.$_createMessage);
  static SourcePreferencesMutation? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mutationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set mutationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMutationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMutationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get packageName => $_getSZ(2);
  @$pb.TagNumber(3)
  set packageName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPackageName() => $_has(2);
  @$pb.TagNumber(3)
  void clearPackageName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get sourceId => $_getSZ(3);
  @$pb.TagNumber(4)
  set sourceId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSourceId() => $_has(3);
  @$pb.TagNumber(4)
  void clearSourceId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get expectedRevision => $_getIZ(4);
  @$pb.TagNumber(5)
  set expectedRevision($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasExpectedRevision() => $_has(4);
  @$pb.TagNumber(5)
  void clearExpectedRevision() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<$0.PreferenceEntry> get entries => $_getList(5);

  @$pb.TagNumber(7)
  $0.CatalogReference get catalog => $_getN(6);
  @$pb.TagNumber(7)
  set catalog($0.CatalogReference value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasCatalog() => $_has(6);
  @$pb.TagNumber(7)
  void clearCatalog() => $_clearField(7);
  @$pb.TagNumber(7)
  $0.CatalogReference ensureCatalog() => $_ensure(6);
}

class SourcePreferencesMutationResponse extends $pb.GeneratedMessage {
  factory SourcePreferencesMutationResponse({
    $core.int? schemaVersion,
    $core.String? mutationId,
    $core.int? accountRevision,
    SourcePreferences? preferences,
    BusinessStateError? error,
    $0.CatalogReference? catalog,
    $core.Iterable<$0.PreferenceSyncRule>? syncRules,
  }) {
    final result = SourcePreferencesMutationResponse._();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (mutationId != null) result.mutationId = mutationId;
    if (accountRevision != null) result.accountRevision = accountRevision;
    if (preferences != null) result.preferences = preferences;
    if (error != null) result.error = error;
    if (catalog != null) result.catalog = catalog;
    if (syncRules != null) result.syncRules.addAll(syncRules);
    return result;
  }

  SourcePreferencesMutationResponse._();

  factory SourcePreferencesMutationResponse.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourcePreferencesMutationResponse()..mergeFromBuffer(data, registry);
  factory SourcePreferencesMutationResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      SourcePreferencesMutationResponse()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SourcePreferencesMutationResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: SourcePreferencesMutationResponse.$_createMessage)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'mutationId')
    ..aI(3, _omitFieldNames ? '' : 'accountRevision',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<SourcePreferences>(4, _omitFieldNames ? '' : 'preferences',
        subBuilder: SourcePreferences.$_createMessage)
    ..aOM<BusinessStateError>(5, _omitFieldNames ? '' : 'error',
        subBuilder: BusinessStateError.$_createMessage)
    ..aOM<$0.CatalogReference>(6, _omitFieldNames ? '' : 'catalog',
        subBuilder: $0.CatalogReference.$_createMessage)
    ..pPM<$0.PreferenceSyncRule>(7, _omitFieldNames ? '' : 'syncRules',
        subBuilder: $0.PreferenceSyncRule.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourcePreferencesMutationResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SourcePreferencesMutationResponse copyWith(
          void Function(SourcePreferencesMutationResponse) updates) =>
      super.copyWith((message) =>
              updates(message as SourcePreferencesMutationResponse))
          as SourcePreferencesMutationResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated(
      'Use SourcePreferencesMutationResponse() / SourcePreferencesMutationResponse.new instead')
  static SourcePreferencesMutationResponse create() =>
      SourcePreferencesMutationResponse._();
  static $pb.GeneratedMessage $_createMessage() =>
      SourcePreferencesMutationResponse._();
  @$core.override
  SourcePreferencesMutationResponse createEmptyInstance() =>
      SourcePreferencesMutationResponse._();
  @$core.pragma('dart2js:noInline')
  static SourcePreferencesMutationResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SourcePreferencesMutationResponse>(
          SourcePreferencesMutationResponse.$_createMessage);
  static SourcePreferencesMutationResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get mutationId => $_getSZ(1);
  @$pb.TagNumber(2)
  set mutationId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMutationId() => $_has(1);
  @$pb.TagNumber(2)
  void clearMutationId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get accountRevision => $_getIZ(2);
  @$pb.TagNumber(3)
  set accountRevision($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAccountRevision() => $_has(2);
  @$pb.TagNumber(3)
  void clearAccountRevision() => $_clearField(3);

  @$pb.TagNumber(4)
  SourcePreferences get preferences => $_getN(3);
  @$pb.TagNumber(4)
  set preferences(SourcePreferences value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasPreferences() => $_has(3);
  @$pb.TagNumber(4)
  void clearPreferences() => $_clearField(4);
  @$pb.TagNumber(4)
  SourcePreferences ensurePreferences() => $_ensure(3);

  @$pb.TagNumber(5)
  BusinessStateError get error => $_getN(4);
  @$pb.TagNumber(5)
  set error(BusinessStateError value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
  @$pb.TagNumber(5)
  BusinessStateError ensureError() => $_ensure(4);

  @$pb.TagNumber(6)
  $0.CatalogReference get catalog => $_getN(5);
  @$pb.TagNumber(6)
  set catalog($0.CatalogReference value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasCatalog() => $_has(5);
  @$pb.TagNumber(6)
  void clearCatalog() => $_clearField(6);
  @$pb.TagNumber(6)
  $0.CatalogReference ensureCatalog() => $_ensure(5);

  @$pb.TagNumber(7)
  $pb.PbList<$0.PreferenceSyncRule> get syncRules => $_getList(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
