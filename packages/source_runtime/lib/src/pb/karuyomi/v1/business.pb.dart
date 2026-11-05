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

class MangaState extends $pb.GeneratedMessage {
  factory MangaState({
    $core.String? mangaKey,
    $core.int? revision,
    LibraryMetadata? metadata,
    $core.bool? favorite,
    $core.int? addedAtSeconds,
    MangaResume? resume,
    $core.Iterable<$core.String>? categoryIds,
  }) {
    final result = MangaState._();
    if (mangaKey != null) result.mangaKey = mangaKey;
    if (revision != null) result.revision = revision;
    if (metadata != null) result.metadata = metadata;
    if (favorite != null) result.favorite = favorite;
    if (addedAtSeconds != null) result.addedAtSeconds = addedAtSeconds;
    if (resume != null) result.resume = resume;
    if (categoryIds != null) result.categoryIds.addAll(categoryIds);
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
  }) {
    final result = ReadingAnchor._();
    if (chapterKey != null) result.chapterKey = chapterKey;
    if (pageKey != null) result.pageKey = pageKey;
    if (manifestVersion != null) result.manifestVersion = manifestVersion;
    if (pageIndexHint != null) result.pageIndexHint = pageIndexHint;
    if (normalizedOffset != null) result.normalizedOffset = normalizedOffset;
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

  @$pb.TagNumber(5)
  $core.double get normalizedOffset => $_getN(4);
  @$pb.TagNumber(5)
  set normalizedOffset($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasNormalizedOffset() => $_has(4);
  @$pb.TagNumber(5)
  void clearNormalizedOffset() => $_clearField(5);
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

enum StateMutation_Operation {
  setFavorite,
  updateMetadata,
  saveProgress,
  resetProgress,
  setCategories,
  setBookmark,
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
    0: StateMutation_Operation.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StateMutation',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'karuyomi.v1'),
      createEmptyInstance: StateMutation.$_createMessage)
    ..oo(0, [10, 11, 12, 13, 14, 15])
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
  StateMutation_Operation whichOperation() =>
      _StateMutation_OperationByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
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

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
