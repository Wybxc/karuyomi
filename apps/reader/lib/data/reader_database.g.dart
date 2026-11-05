// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reader_database.dart';

// ignore_for_file: type=lint
class $ChapterProgressRowsTable extends ChapterProgressRows
    with TableInfo<$ChapterProgressRowsTable, ChapterProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChapterProgressRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mangaKeyMeta = const VerificationMeta(
    'mangaKey',
  );
  @override
  late final GeneratedColumn<String> mangaKey = GeneratedColumn<String>(
    'manga_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterKeyMeta = const VerificationMeta(
    'chapterKey',
  );
  @override
  late final GeneratedColumn<String> chapterKey = GeneratedColumn<String>(
    'chapter_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentJsonMeta = const VerificationMeta(
    'currentJson',
  );
  @override
  late final GeneratedColumn<String> currentJson = GeneratedColumn<String>(
    'current_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _furthestJsonMeta = const VerificationMeta(
    'furthestJson',
  );
  @override
  late final GeneratedColumn<String> furthestJson = GeneratedColumn<String>(
    'furthest_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _epochMeta = const VerificationMeta('epoch');
  @override
  late final GeneratedColumn<int> epoch = GeneratedColumn<int>(
    'epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    identityKey,
    mangaKey,
    chapterKey,
    currentJson,
    furthestJson,
    epoch,
    completed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chapter_progress_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChapterProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('manga_key')) {
      context.handle(
        _mangaKeyMeta,
        mangaKey.isAcceptableOrUnknown(data['manga_key']!, _mangaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_mangaKeyMeta);
    }
    if (data.containsKey('chapter_key')) {
      context.handle(
        _chapterKeyMeta,
        chapterKey.isAcceptableOrUnknown(data['chapter_key']!, _chapterKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_chapterKeyMeta);
    }
    if (data.containsKey('current_json')) {
      context.handle(
        _currentJsonMeta,
        currentJson.isAcceptableOrUnknown(
          data['current_json']!,
          _currentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentJsonMeta);
    }
    if (data.containsKey('furthest_json')) {
      context.handle(
        _furthestJsonMeta,
        furthestJson.isAcceptableOrUnknown(
          data['furthest_json']!,
          _furthestJsonMeta,
        ),
      );
    }
    if (data.containsKey('epoch')) {
      context.handle(
        _epochMeta,
        epoch.isAcceptableOrUnknown(data['epoch']!, _epochMeta),
      );
    } else if (isInserting) {
      context.missing(_epochMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    } else if (isInserting) {
      context.missing(_completedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {identityKey, mangaKey, chapterKey};
  @override
  ChapterProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChapterProgressRow(
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      mangaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manga_key'],
      )!,
      chapterKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_key'],
      )!,
      currentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_json'],
      )!,
      furthestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}furthest_json'],
      ),
      epoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}epoch'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
    );
  }

  @override
  $ChapterProgressRowsTable createAlias(String alias) {
    return $ChapterProgressRowsTable(attachedDatabase, alias);
  }
}

class ChapterProgressRow extends DataClass
    implements Insertable<ChapterProgressRow> {
  final String identityKey;
  final String mangaKey;
  final String chapterKey;
  final String currentJson;
  final String? furthestJson;
  final int epoch;
  final bool completed;
  const ChapterProgressRow({
    required this.identityKey,
    required this.mangaKey,
    required this.chapterKey,
    required this.currentJson,
    this.furthestJson,
    required this.epoch,
    required this.completed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['identity_key'] = Variable<String>(identityKey);
    map['manga_key'] = Variable<String>(mangaKey);
    map['chapter_key'] = Variable<String>(chapterKey);
    map['current_json'] = Variable<String>(currentJson);
    if (!nullToAbsent || furthestJson != null) {
      map['furthest_json'] = Variable<String>(furthestJson);
    }
    map['epoch'] = Variable<int>(epoch);
    map['completed'] = Variable<bool>(completed);
    return map;
  }

  ChapterProgressRowsCompanion toCompanion(bool nullToAbsent) {
    return ChapterProgressRowsCompanion(
      identityKey: Value(identityKey),
      mangaKey: Value(mangaKey),
      chapterKey: Value(chapterKey),
      currentJson: Value(currentJson),
      furthestJson: furthestJson == null && nullToAbsent
          ? const Value.absent()
          : Value(furthestJson),
      epoch: Value(epoch),
      completed: Value(completed),
    );
  }

  factory ChapterProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChapterProgressRow(
      identityKey: serializer.fromJson<String>(json['identityKey']),
      mangaKey: serializer.fromJson<String>(json['mangaKey']),
      chapterKey: serializer.fromJson<String>(json['chapterKey']),
      currentJson: serializer.fromJson<String>(json['currentJson']),
      furthestJson: serializer.fromJson<String?>(json['furthestJson']),
      epoch: serializer.fromJson<int>(json['epoch']),
      completed: serializer.fromJson<bool>(json['completed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'identityKey': serializer.toJson<String>(identityKey),
      'mangaKey': serializer.toJson<String>(mangaKey),
      'chapterKey': serializer.toJson<String>(chapterKey),
      'currentJson': serializer.toJson<String>(currentJson),
      'furthestJson': serializer.toJson<String?>(furthestJson),
      'epoch': serializer.toJson<int>(epoch),
      'completed': serializer.toJson<bool>(completed),
    };
  }

  ChapterProgressRow copyWith({
    String? identityKey,
    String? mangaKey,
    String? chapterKey,
    String? currentJson,
    Value<String?> furthestJson = const Value.absent(),
    int? epoch,
    bool? completed,
  }) => ChapterProgressRow(
    identityKey: identityKey ?? this.identityKey,
    mangaKey: mangaKey ?? this.mangaKey,
    chapterKey: chapterKey ?? this.chapterKey,
    currentJson: currentJson ?? this.currentJson,
    furthestJson: furthestJson.present ? furthestJson.value : this.furthestJson,
    epoch: epoch ?? this.epoch,
    completed: completed ?? this.completed,
  );
  ChapterProgressRow copyWithCompanion(ChapterProgressRowsCompanion data) {
    return ChapterProgressRow(
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      mangaKey: data.mangaKey.present ? data.mangaKey.value : this.mangaKey,
      chapterKey: data.chapterKey.present
          ? data.chapterKey.value
          : this.chapterKey,
      currentJson: data.currentJson.present
          ? data.currentJson.value
          : this.currentJson,
      furthestJson: data.furthestJson.present
          ? data.furthestJson.value
          : this.furthestJson,
      epoch: data.epoch.present ? data.epoch.value : this.epoch,
      completed: data.completed.present ? data.completed.value : this.completed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChapterProgressRow(')
          ..write('identityKey: $identityKey, ')
          ..write('mangaKey: $mangaKey, ')
          ..write('chapterKey: $chapterKey, ')
          ..write('currentJson: $currentJson, ')
          ..write('furthestJson: $furthestJson, ')
          ..write('epoch: $epoch, ')
          ..write('completed: $completed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    identityKey,
    mangaKey,
    chapterKey,
    currentJson,
    furthestJson,
    epoch,
    completed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChapterProgressRow &&
          other.identityKey == this.identityKey &&
          other.mangaKey == this.mangaKey &&
          other.chapterKey == this.chapterKey &&
          other.currentJson == this.currentJson &&
          other.furthestJson == this.furthestJson &&
          other.epoch == this.epoch &&
          other.completed == this.completed);
}

class ChapterProgressRowsCompanion extends UpdateCompanion<ChapterProgressRow> {
  final Value<String> identityKey;
  final Value<String> mangaKey;
  final Value<String> chapterKey;
  final Value<String> currentJson;
  final Value<String?> furthestJson;
  final Value<int> epoch;
  final Value<bool> completed;
  final Value<int> rowid;
  const ChapterProgressRowsCompanion({
    this.identityKey = const Value.absent(),
    this.mangaKey = const Value.absent(),
    this.chapterKey = const Value.absent(),
    this.currentJson = const Value.absent(),
    this.furthestJson = const Value.absent(),
    this.epoch = const Value.absent(),
    this.completed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChapterProgressRowsCompanion.insert({
    required String identityKey,
    required String mangaKey,
    required String chapterKey,
    required String currentJson,
    this.furthestJson = const Value.absent(),
    required int epoch,
    required bool completed,
    this.rowid = const Value.absent(),
  }) : identityKey = Value(identityKey),
       mangaKey = Value(mangaKey),
       chapterKey = Value(chapterKey),
       currentJson = Value(currentJson),
       epoch = Value(epoch),
       completed = Value(completed);
  static Insertable<ChapterProgressRow> custom({
    Expression<String>? identityKey,
    Expression<String>? mangaKey,
    Expression<String>? chapterKey,
    Expression<String>? currentJson,
    Expression<String>? furthestJson,
    Expression<int>? epoch,
    Expression<bool>? completed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (identityKey != null) 'identity_key': identityKey,
      if (mangaKey != null) 'manga_key': mangaKey,
      if (chapterKey != null) 'chapter_key': chapterKey,
      if (currentJson != null) 'current_json': currentJson,
      if (furthestJson != null) 'furthest_json': furthestJson,
      if (epoch != null) 'epoch': epoch,
      if (completed != null) 'completed': completed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChapterProgressRowsCompanion copyWith({
    Value<String>? identityKey,
    Value<String>? mangaKey,
    Value<String>? chapterKey,
    Value<String>? currentJson,
    Value<String?>? furthestJson,
    Value<int>? epoch,
    Value<bool>? completed,
    Value<int>? rowid,
  }) {
    return ChapterProgressRowsCompanion(
      identityKey: identityKey ?? this.identityKey,
      mangaKey: mangaKey ?? this.mangaKey,
      chapterKey: chapterKey ?? this.chapterKey,
      currentJson: currentJson ?? this.currentJson,
      furthestJson: furthestJson ?? this.furthestJson,
      epoch: epoch ?? this.epoch,
      completed: completed ?? this.completed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (mangaKey.present) {
      map['manga_key'] = Variable<String>(mangaKey.value);
    }
    if (chapterKey.present) {
      map['chapter_key'] = Variable<String>(chapterKey.value);
    }
    if (currentJson.present) {
      map['current_json'] = Variable<String>(currentJson.value);
    }
    if (furthestJson.present) {
      map['furthest_json'] = Variable<String>(furthestJson.value);
    }
    if (epoch.present) {
      map['epoch'] = Variable<int>(epoch.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChapterProgressRowsCompanion(')
          ..write('identityKey: $identityKey, ')
          ..write('mangaKey: $mangaKey, ')
          ..write('chapterKey: $chapterKey, ')
          ..write('currentJson: $currentJson, ')
          ..write('furthestJson: $furthestJson, ')
          ..write('epoch: $epoch, ')
          ..write('completed: $completed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MangaResumeRowsTable extends MangaResumeRows
    with TableInfo<$MangaResumeRowsTable, MangaResumeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MangaResumeRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mangaKeyMeta = const VerificationMeta(
    'mangaKey',
  );
  @override
  late final GeneratedColumn<String> mangaKey = GeneratedColumn<String>(
    'manga_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterKeyMeta = const VerificationMeta(
    'chapterKey',
  );
  @override
  late final GeneratedColumn<String> chapterKey = GeneratedColumn<String>(
    'chapter_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reversedOrderMeta = const VerificationMeta(
    'reversedOrder',
  );
  @override
  late final GeneratedColumn<bool> reversedOrder = GeneratedColumn<bool>(
    'reversed_order',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reversed_order" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    identityKey,
    mangaKey,
    chapterKey,
    reversedOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'manga_resume_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<MangaResumeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('manga_key')) {
      context.handle(
        _mangaKeyMeta,
        mangaKey.isAcceptableOrUnknown(data['manga_key']!, _mangaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_mangaKeyMeta);
    }
    if (data.containsKey('chapter_key')) {
      context.handle(
        _chapterKeyMeta,
        chapterKey.isAcceptableOrUnknown(data['chapter_key']!, _chapterKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_chapterKeyMeta);
    }
    if (data.containsKey('reversed_order')) {
      context.handle(
        _reversedOrderMeta,
        reversedOrder.isAcceptableOrUnknown(
          data['reversed_order']!,
          _reversedOrderMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reversedOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {identityKey, mangaKey};
  @override
  MangaResumeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MangaResumeRow(
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      mangaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manga_key'],
      )!,
      chapterKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_key'],
      )!,
      reversedOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reversed_order'],
      )!,
    );
  }

  @override
  $MangaResumeRowsTable createAlias(String alias) {
    return $MangaResumeRowsTable(attachedDatabase, alias);
  }
}

class MangaResumeRow extends DataClass implements Insertable<MangaResumeRow> {
  final String identityKey;
  final String mangaKey;
  final String chapterKey;
  final bool reversedOrder;
  const MangaResumeRow({
    required this.identityKey,
    required this.mangaKey,
    required this.chapterKey,
    required this.reversedOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['identity_key'] = Variable<String>(identityKey);
    map['manga_key'] = Variable<String>(mangaKey);
    map['chapter_key'] = Variable<String>(chapterKey);
    map['reversed_order'] = Variable<bool>(reversedOrder);
    return map;
  }

  MangaResumeRowsCompanion toCompanion(bool nullToAbsent) {
    return MangaResumeRowsCompanion(
      identityKey: Value(identityKey),
      mangaKey: Value(mangaKey),
      chapterKey: Value(chapterKey),
      reversedOrder: Value(reversedOrder),
    );
  }

  factory MangaResumeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MangaResumeRow(
      identityKey: serializer.fromJson<String>(json['identityKey']),
      mangaKey: serializer.fromJson<String>(json['mangaKey']),
      chapterKey: serializer.fromJson<String>(json['chapterKey']),
      reversedOrder: serializer.fromJson<bool>(json['reversedOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'identityKey': serializer.toJson<String>(identityKey),
      'mangaKey': serializer.toJson<String>(mangaKey),
      'chapterKey': serializer.toJson<String>(chapterKey),
      'reversedOrder': serializer.toJson<bool>(reversedOrder),
    };
  }

  MangaResumeRow copyWith({
    String? identityKey,
    String? mangaKey,
    String? chapterKey,
    bool? reversedOrder,
  }) => MangaResumeRow(
    identityKey: identityKey ?? this.identityKey,
    mangaKey: mangaKey ?? this.mangaKey,
    chapterKey: chapterKey ?? this.chapterKey,
    reversedOrder: reversedOrder ?? this.reversedOrder,
  );
  MangaResumeRow copyWithCompanion(MangaResumeRowsCompanion data) {
    return MangaResumeRow(
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      mangaKey: data.mangaKey.present ? data.mangaKey.value : this.mangaKey,
      chapterKey: data.chapterKey.present
          ? data.chapterKey.value
          : this.chapterKey,
      reversedOrder: data.reversedOrder.present
          ? data.reversedOrder.value
          : this.reversedOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MangaResumeRow(')
          ..write('identityKey: $identityKey, ')
          ..write('mangaKey: $mangaKey, ')
          ..write('chapterKey: $chapterKey, ')
          ..write('reversedOrder: $reversedOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(identityKey, mangaKey, chapterKey, reversedOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MangaResumeRow &&
          other.identityKey == this.identityKey &&
          other.mangaKey == this.mangaKey &&
          other.chapterKey == this.chapterKey &&
          other.reversedOrder == this.reversedOrder);
}

class MangaResumeRowsCompanion extends UpdateCompanion<MangaResumeRow> {
  final Value<String> identityKey;
  final Value<String> mangaKey;
  final Value<String> chapterKey;
  final Value<bool> reversedOrder;
  final Value<int> rowid;
  const MangaResumeRowsCompanion({
    this.identityKey = const Value.absent(),
    this.mangaKey = const Value.absent(),
    this.chapterKey = const Value.absent(),
    this.reversedOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MangaResumeRowsCompanion.insert({
    required String identityKey,
    required String mangaKey,
    required String chapterKey,
    required bool reversedOrder,
    this.rowid = const Value.absent(),
  }) : identityKey = Value(identityKey),
       mangaKey = Value(mangaKey),
       chapterKey = Value(chapterKey),
       reversedOrder = Value(reversedOrder);
  static Insertable<MangaResumeRow> custom({
    Expression<String>? identityKey,
    Expression<String>? mangaKey,
    Expression<String>? chapterKey,
    Expression<bool>? reversedOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (identityKey != null) 'identity_key': identityKey,
      if (mangaKey != null) 'manga_key': mangaKey,
      if (chapterKey != null) 'chapter_key': chapterKey,
      if (reversedOrder != null) 'reversed_order': reversedOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MangaResumeRowsCompanion copyWith({
    Value<String>? identityKey,
    Value<String>? mangaKey,
    Value<String>? chapterKey,
    Value<bool>? reversedOrder,
    Value<int>? rowid,
  }) {
    return MangaResumeRowsCompanion(
      identityKey: identityKey ?? this.identityKey,
      mangaKey: mangaKey ?? this.mangaKey,
      chapterKey: chapterKey ?? this.chapterKey,
      reversedOrder: reversedOrder ?? this.reversedOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (mangaKey.present) {
      map['manga_key'] = Variable<String>(mangaKey.value);
    }
    if (chapterKey.present) {
      map['chapter_key'] = Variable<String>(chapterKey.value);
    }
    if (reversedOrder.present) {
      map['reversed_order'] = Variable<bool>(reversedOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MangaResumeRowsCompanion(')
          ..write('identityKey: $identityKey, ')
          ..write('mangaKey: $mangaKey, ')
          ..write('chapterKey: $chapterKey, ')
          ..write('reversedOrder: $reversedOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LibraryMangaRowsTable extends LibraryMangaRows
    with TableInfo<$LibraryMangaRowsTable, LibraryMangaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryMangaRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mangaKeyMeta = const VerificationMeta(
    'mangaKey',
  );
  @override
  late final GeneratedColumn<String> mangaKey = GeneratedColumn<String>(
    'manga_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packageNameMeta = const VerificationMeta(
    'packageName',
  );
  @override
  late final GeneratedColumn<String> packageName = GeneratedColumn<String>(
    'package_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceLangMeta = const VerificationMeta(
    'sourceLang',
  );
  @override
  late final GeneratedColumn<String> sourceLang = GeneratedColumn<String>(
    'source_lang',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mangaJsonMeta = const VerificationMeta(
    'mangaJson',
  );
  @override
  late final GeneratedColumn<String> mangaJson = GeneratedColumn<String>(
    'manga_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    identityKey,
    mangaKey,
    packageName,
    sourceId,
    sourceName,
    sourceLang,
    mangaJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_manga_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryMangaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('manga_key')) {
      context.handle(
        _mangaKeyMeta,
        mangaKey.isAcceptableOrUnknown(data['manga_key']!, _mangaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_mangaKeyMeta);
    }
    if (data.containsKey('package_name')) {
      context.handle(
        _packageNameMeta,
        packageName.isAcceptableOrUnknown(
          data['package_name']!,
          _packageNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_packageNameMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceNameMeta);
    }
    if (data.containsKey('source_lang')) {
      context.handle(
        _sourceLangMeta,
        sourceLang.isAcceptableOrUnknown(data['source_lang']!, _sourceLangMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceLangMeta);
    }
    if (data.containsKey('manga_json')) {
      context.handle(
        _mangaJsonMeta,
        mangaJson.isAcceptableOrUnknown(data['manga_json']!, _mangaJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_mangaJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {identityKey, mangaKey};
  @override
  LibraryMangaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryMangaRow(
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      mangaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manga_key'],
      )!,
      packageName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}package_name'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      )!,
      sourceLang: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_lang'],
      )!,
      mangaJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manga_json'],
      )!,
    );
  }

  @override
  $LibraryMangaRowsTable createAlias(String alias) {
    return $LibraryMangaRowsTable(attachedDatabase, alias);
  }
}

class LibraryMangaRow extends DataClass implements Insertable<LibraryMangaRow> {
  final String identityKey;
  final String mangaKey;
  final String packageName;
  final String sourceId;
  final String sourceName;
  final String sourceLang;
  final String mangaJson;
  const LibraryMangaRow({
    required this.identityKey,
    required this.mangaKey,
    required this.packageName,
    required this.sourceId,
    required this.sourceName,
    required this.sourceLang,
    required this.mangaJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['identity_key'] = Variable<String>(identityKey);
    map['manga_key'] = Variable<String>(mangaKey);
    map['package_name'] = Variable<String>(packageName);
    map['source_id'] = Variable<String>(sourceId);
    map['source_name'] = Variable<String>(sourceName);
    map['source_lang'] = Variable<String>(sourceLang);
    map['manga_json'] = Variable<String>(mangaJson);
    return map;
  }

  LibraryMangaRowsCompanion toCompanion(bool nullToAbsent) {
    return LibraryMangaRowsCompanion(
      identityKey: Value(identityKey),
      mangaKey: Value(mangaKey),
      packageName: Value(packageName),
      sourceId: Value(sourceId),
      sourceName: Value(sourceName),
      sourceLang: Value(sourceLang),
      mangaJson: Value(mangaJson),
    );
  }

  factory LibraryMangaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryMangaRow(
      identityKey: serializer.fromJson<String>(json['identityKey']),
      mangaKey: serializer.fromJson<String>(json['mangaKey']),
      packageName: serializer.fromJson<String>(json['packageName']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      sourceLang: serializer.fromJson<String>(json['sourceLang']),
      mangaJson: serializer.fromJson<String>(json['mangaJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'identityKey': serializer.toJson<String>(identityKey),
      'mangaKey': serializer.toJson<String>(mangaKey),
      'packageName': serializer.toJson<String>(packageName),
      'sourceId': serializer.toJson<String>(sourceId),
      'sourceName': serializer.toJson<String>(sourceName),
      'sourceLang': serializer.toJson<String>(sourceLang),
      'mangaJson': serializer.toJson<String>(mangaJson),
    };
  }

  LibraryMangaRow copyWith({
    String? identityKey,
    String? mangaKey,
    String? packageName,
    String? sourceId,
    String? sourceName,
    String? sourceLang,
    String? mangaJson,
  }) => LibraryMangaRow(
    identityKey: identityKey ?? this.identityKey,
    mangaKey: mangaKey ?? this.mangaKey,
    packageName: packageName ?? this.packageName,
    sourceId: sourceId ?? this.sourceId,
    sourceName: sourceName ?? this.sourceName,
    sourceLang: sourceLang ?? this.sourceLang,
    mangaJson: mangaJson ?? this.mangaJson,
  );
  LibraryMangaRow copyWithCompanion(LibraryMangaRowsCompanion data) {
    return LibraryMangaRow(
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      mangaKey: data.mangaKey.present ? data.mangaKey.value : this.mangaKey,
      packageName: data.packageName.present
          ? data.packageName.value
          : this.packageName,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      sourceLang: data.sourceLang.present
          ? data.sourceLang.value
          : this.sourceLang,
      mangaJson: data.mangaJson.present ? data.mangaJson.value : this.mangaJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryMangaRow(')
          ..write('identityKey: $identityKey, ')
          ..write('mangaKey: $mangaKey, ')
          ..write('packageName: $packageName, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceName: $sourceName, ')
          ..write('sourceLang: $sourceLang, ')
          ..write('mangaJson: $mangaJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    identityKey,
    mangaKey,
    packageName,
    sourceId,
    sourceName,
    sourceLang,
    mangaJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryMangaRow &&
          other.identityKey == this.identityKey &&
          other.mangaKey == this.mangaKey &&
          other.packageName == this.packageName &&
          other.sourceId == this.sourceId &&
          other.sourceName == this.sourceName &&
          other.sourceLang == this.sourceLang &&
          other.mangaJson == this.mangaJson);
}

class LibraryMangaRowsCompanion extends UpdateCompanion<LibraryMangaRow> {
  final Value<String> identityKey;
  final Value<String> mangaKey;
  final Value<String> packageName;
  final Value<String> sourceId;
  final Value<String> sourceName;
  final Value<String> sourceLang;
  final Value<String> mangaJson;
  final Value<int> rowid;
  const LibraryMangaRowsCompanion({
    this.identityKey = const Value.absent(),
    this.mangaKey = const Value.absent(),
    this.packageName = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.sourceLang = const Value.absent(),
    this.mangaJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryMangaRowsCompanion.insert({
    required String identityKey,
    required String mangaKey,
    required String packageName,
    required String sourceId,
    required String sourceName,
    required String sourceLang,
    required String mangaJson,
    this.rowid = const Value.absent(),
  }) : identityKey = Value(identityKey),
       mangaKey = Value(mangaKey),
       packageName = Value(packageName),
       sourceId = Value(sourceId),
       sourceName = Value(sourceName),
       sourceLang = Value(sourceLang),
       mangaJson = Value(mangaJson);
  static Insertable<LibraryMangaRow> custom({
    Expression<String>? identityKey,
    Expression<String>? mangaKey,
    Expression<String>? packageName,
    Expression<String>? sourceId,
    Expression<String>? sourceName,
    Expression<String>? sourceLang,
    Expression<String>? mangaJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (identityKey != null) 'identity_key': identityKey,
      if (mangaKey != null) 'manga_key': mangaKey,
      if (packageName != null) 'package_name': packageName,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceName != null) 'source_name': sourceName,
      if (sourceLang != null) 'source_lang': sourceLang,
      if (mangaJson != null) 'manga_json': mangaJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryMangaRowsCompanion copyWith({
    Value<String>? identityKey,
    Value<String>? mangaKey,
    Value<String>? packageName,
    Value<String>? sourceId,
    Value<String>? sourceName,
    Value<String>? sourceLang,
    Value<String>? mangaJson,
    Value<int>? rowid,
  }) {
    return LibraryMangaRowsCompanion(
      identityKey: identityKey ?? this.identityKey,
      mangaKey: mangaKey ?? this.mangaKey,
      packageName: packageName ?? this.packageName,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      sourceLang: sourceLang ?? this.sourceLang,
      mangaJson: mangaJson ?? this.mangaJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (mangaKey.present) {
      map['manga_key'] = Variable<String>(mangaKey.value);
    }
    if (packageName.present) {
      map['package_name'] = Variable<String>(packageName.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (sourceLang.present) {
      map['source_lang'] = Variable<String>(sourceLang.value);
    }
    if (mangaJson.present) {
      map['manga_json'] = Variable<String>(mangaJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryMangaRowsCompanion(')
          ..write('identityKey: $identityKey, ')
          ..write('mangaKey: $mangaKey, ')
          ..write('packageName: $packageName, ')
          ..write('sourceId: $sourceId, ')
          ..write('sourceName: $sourceName, ')
          ..write('sourceLang: $sourceLang, ')
          ..write('mangaJson: $mangaJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LibraryFavoriteRowsTable extends LibraryFavoriteRows
    with TableInfo<$LibraryFavoriteRowsTable, LibraryFavoriteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LibraryFavoriteRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _identityKeyMeta = const VerificationMeta(
    'identityKey',
  );
  @override
  late final GeneratedColumn<String> identityKey = GeneratedColumn<String>(
    'identity_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mangaKeyMeta = const VerificationMeta(
    'mangaKey',
  );
  @override
  late final GeneratedColumn<String> mangaKey = GeneratedColumn<String>(
    'manga_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [identityKey, mangaKey, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'library_favorite_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<LibraryFavoriteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('identity_key')) {
      context.handle(
        _identityKeyMeta,
        identityKey.isAcceptableOrUnknown(
          data['identity_key']!,
          _identityKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_identityKeyMeta);
    }
    if (data.containsKey('manga_key')) {
      context.handle(
        _mangaKeyMeta,
        mangaKey.isAcceptableOrUnknown(data['manga_key']!, _mangaKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_mangaKeyMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {identityKey, mangaKey};
  @override
  LibraryFavoriteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LibraryFavoriteRow(
      identityKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_key'],
      )!,
      mangaKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manga_key'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $LibraryFavoriteRowsTable createAlias(String alias) {
    return $LibraryFavoriteRowsTable(attachedDatabase, alias);
  }
}

class LibraryFavoriteRow extends DataClass
    implements Insertable<LibraryFavoriteRow> {
  final String identityKey;
  final String mangaKey;
  final DateTime addedAt;
  const LibraryFavoriteRow({
    required this.identityKey,
    required this.mangaKey,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['identity_key'] = Variable<String>(identityKey);
    map['manga_key'] = Variable<String>(mangaKey);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  LibraryFavoriteRowsCompanion toCompanion(bool nullToAbsent) {
    return LibraryFavoriteRowsCompanion(
      identityKey: Value(identityKey),
      mangaKey: Value(mangaKey),
      addedAt: Value(addedAt),
    );
  }

  factory LibraryFavoriteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LibraryFavoriteRow(
      identityKey: serializer.fromJson<String>(json['identityKey']),
      mangaKey: serializer.fromJson<String>(json['mangaKey']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'identityKey': serializer.toJson<String>(identityKey),
      'mangaKey': serializer.toJson<String>(mangaKey),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  LibraryFavoriteRow copyWith({
    String? identityKey,
    String? mangaKey,
    DateTime? addedAt,
  }) => LibraryFavoriteRow(
    identityKey: identityKey ?? this.identityKey,
    mangaKey: mangaKey ?? this.mangaKey,
    addedAt: addedAt ?? this.addedAt,
  );
  LibraryFavoriteRow copyWithCompanion(LibraryFavoriteRowsCompanion data) {
    return LibraryFavoriteRow(
      identityKey: data.identityKey.present
          ? data.identityKey.value
          : this.identityKey,
      mangaKey: data.mangaKey.present ? data.mangaKey.value : this.mangaKey,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LibraryFavoriteRow(')
          ..write('identityKey: $identityKey, ')
          ..write('mangaKey: $mangaKey, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(identityKey, mangaKey, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LibraryFavoriteRow &&
          other.identityKey == this.identityKey &&
          other.mangaKey == this.mangaKey &&
          other.addedAt == this.addedAt);
}

class LibraryFavoriteRowsCompanion extends UpdateCompanion<LibraryFavoriteRow> {
  final Value<String> identityKey;
  final Value<String> mangaKey;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const LibraryFavoriteRowsCompanion({
    this.identityKey = const Value.absent(),
    this.mangaKey = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LibraryFavoriteRowsCompanion.insert({
    required String identityKey,
    required String mangaKey,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : identityKey = Value(identityKey),
       mangaKey = Value(mangaKey),
       addedAt = Value(addedAt);
  static Insertable<LibraryFavoriteRow> custom({
    Expression<String>? identityKey,
    Expression<String>? mangaKey,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (identityKey != null) 'identity_key': identityKey,
      if (mangaKey != null) 'manga_key': mangaKey,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LibraryFavoriteRowsCompanion copyWith({
    Value<String>? identityKey,
    Value<String>? mangaKey,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return LibraryFavoriteRowsCompanion(
      identityKey: identityKey ?? this.identityKey,
      mangaKey: mangaKey ?? this.mangaKey,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (identityKey.present) {
      map['identity_key'] = Variable<String>(identityKey.value);
    }
    if (mangaKey.present) {
      map['manga_key'] = Variable<String>(mangaKey.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LibraryFavoriteRowsCompanion(')
          ..write('identityKey: $identityKey, ')
          ..write('mangaKey: $mangaKey, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ReaderDatabase extends GeneratedDatabase {
  _$ReaderDatabase(QueryExecutor e) : super(e);
  $ReaderDatabaseManager get managers => $ReaderDatabaseManager(this);
  late final $ChapterProgressRowsTable chapterProgressRows =
      $ChapterProgressRowsTable(this);
  late final $MangaResumeRowsTable mangaResumeRows = $MangaResumeRowsTable(
    this,
  );
  late final $LibraryMangaRowsTable libraryMangaRows = $LibraryMangaRowsTable(
    this,
  );
  late final $LibraryFavoriteRowsTable libraryFavoriteRows =
      $LibraryFavoriteRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    chapterProgressRows,
    mangaResumeRows,
    libraryMangaRows,
    libraryFavoriteRows,
  ];
}

typedef $$ChapterProgressRowsTableCreateCompanionBuilder =
    ChapterProgressRowsCompanion Function({
      required String identityKey,
      required String mangaKey,
      required String chapterKey,
      required String currentJson,
      Value<String?> furthestJson,
      required int epoch,
      required bool completed,
      Value<int> rowid,
    });
typedef $$ChapterProgressRowsTableUpdateCompanionBuilder =
    ChapterProgressRowsCompanion Function({
      Value<String> identityKey,
      Value<String> mangaKey,
      Value<String> chapterKey,
      Value<String> currentJson,
      Value<String?> furthestJson,
      Value<int> epoch,
      Value<bool> completed,
      Value<int> rowid,
    });

class $$ChapterProgressRowsTableFilterComposer
    extends Composer<_$ReaderDatabase, $ChapterProgressRowsTable> {
  $$ChapterProgressRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mangaKey => $composableBuilder(
    column: $table.mangaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterKey => $composableBuilder(
    column: $table.chapterKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentJson => $composableBuilder(
    column: $table.currentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get furthestJson => $composableBuilder(
    column: $table.furthestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChapterProgressRowsTableOrderingComposer
    extends Composer<_$ReaderDatabase, $ChapterProgressRowsTable> {
  $$ChapterProgressRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mangaKey => $composableBuilder(
    column: $table.mangaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterKey => $composableBuilder(
    column: $table.chapterKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentJson => $composableBuilder(
    column: $table.currentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get furthestJson => $composableBuilder(
    column: $table.furthestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChapterProgressRowsTableAnnotationComposer
    extends Composer<_$ReaderDatabase, $ChapterProgressRowsTable> {
  $$ChapterProgressRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mangaKey =>
      $composableBuilder(column: $table.mangaKey, builder: (column) => column);

  GeneratedColumn<String> get chapterKey => $composableBuilder(
    column: $table.chapterKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentJson => $composableBuilder(
    column: $table.currentJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get furthestJson => $composableBuilder(
    column: $table.furthestJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get epoch =>
      $composableBuilder(column: $table.epoch, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);
}

class $$ChapterProgressRowsTableTableManager
    extends
        RootTableManager<
          _$ReaderDatabase,
          $ChapterProgressRowsTable,
          ChapterProgressRow,
          $$ChapterProgressRowsTableFilterComposer,
          $$ChapterProgressRowsTableOrderingComposer,
          $$ChapterProgressRowsTableAnnotationComposer,
          $$ChapterProgressRowsTableCreateCompanionBuilder,
          $$ChapterProgressRowsTableUpdateCompanionBuilder,
          (
            ChapterProgressRow,
            BaseReferences<
              _$ReaderDatabase,
              $ChapterProgressRowsTable,
              ChapterProgressRow
            >,
          ),
          ChapterProgressRow,
          PrefetchHooks Function()
        > {
  $$ChapterProgressRowsTableTableManager(
    _$ReaderDatabase db,
    $ChapterProgressRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChapterProgressRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChapterProgressRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ChapterProgressRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> identityKey = const Value.absent(),
                Value<String> mangaKey = const Value.absent(),
                Value<String> chapterKey = const Value.absent(),
                Value<String> currentJson = const Value.absent(),
                Value<String?> furthestJson = const Value.absent(),
                Value<int> epoch = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChapterProgressRowsCompanion(
                identityKey: identityKey,
                mangaKey: mangaKey,
                chapterKey: chapterKey,
                currentJson: currentJson,
                furthestJson: furthestJson,
                epoch: epoch,
                completed: completed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String identityKey,
                required String mangaKey,
                required String chapterKey,
                required String currentJson,
                Value<String?> furthestJson = const Value.absent(),
                required int epoch,
                required bool completed,
                Value<int> rowid = const Value.absent(),
              }) => ChapterProgressRowsCompanion.insert(
                identityKey: identityKey,
                mangaKey: mangaKey,
                chapterKey: chapterKey,
                currentJson: currentJson,
                furthestJson: furthestJson,
                epoch: epoch,
                completed: completed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChapterProgressRowsTable, ChapterProgressRow>(
                    table,
                  ),
                  BaseReferences<
                    _$ReaderDatabase,
                    $ChapterProgressRowsTable,
                    ChapterProgressRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChapterProgressRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$ReaderDatabase,
      $ChapterProgressRowsTable,
      ChapterProgressRow,
      $$ChapterProgressRowsTableFilterComposer,
      $$ChapterProgressRowsTableOrderingComposer,
      $$ChapterProgressRowsTableAnnotationComposer,
      $$ChapterProgressRowsTableCreateCompanionBuilder,
      $$ChapterProgressRowsTableUpdateCompanionBuilder,
      (
        ChapterProgressRow,
        BaseReferences<
          _$ReaderDatabase,
          $ChapterProgressRowsTable,
          ChapterProgressRow
        >,
      ),
      ChapterProgressRow,
      PrefetchHooks Function()
    >;
typedef $$MangaResumeRowsTableCreateCompanionBuilder =
    MangaResumeRowsCompanion Function({
      required String identityKey,
      required String mangaKey,
      required String chapterKey,
      required bool reversedOrder,
      Value<int> rowid,
    });
typedef $$MangaResumeRowsTableUpdateCompanionBuilder =
    MangaResumeRowsCompanion Function({
      Value<String> identityKey,
      Value<String> mangaKey,
      Value<String> chapterKey,
      Value<bool> reversedOrder,
      Value<int> rowid,
    });

class $$MangaResumeRowsTableFilterComposer
    extends Composer<_$ReaderDatabase, $MangaResumeRowsTable> {
  $$MangaResumeRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mangaKey => $composableBuilder(
    column: $table.mangaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterKey => $composableBuilder(
    column: $table.chapterKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reversedOrder => $composableBuilder(
    column: $table.reversedOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MangaResumeRowsTableOrderingComposer
    extends Composer<_$ReaderDatabase, $MangaResumeRowsTable> {
  $$MangaResumeRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mangaKey => $composableBuilder(
    column: $table.mangaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterKey => $composableBuilder(
    column: $table.chapterKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reversedOrder => $composableBuilder(
    column: $table.reversedOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MangaResumeRowsTableAnnotationComposer
    extends Composer<_$ReaderDatabase, $MangaResumeRowsTable> {
  $$MangaResumeRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mangaKey =>
      $composableBuilder(column: $table.mangaKey, builder: (column) => column);

  GeneratedColumn<String> get chapterKey => $composableBuilder(
    column: $table.chapterKey,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get reversedOrder => $composableBuilder(
    column: $table.reversedOrder,
    builder: (column) => column,
  );
}

class $$MangaResumeRowsTableTableManager
    extends
        RootTableManager<
          _$ReaderDatabase,
          $MangaResumeRowsTable,
          MangaResumeRow,
          $$MangaResumeRowsTableFilterComposer,
          $$MangaResumeRowsTableOrderingComposer,
          $$MangaResumeRowsTableAnnotationComposer,
          $$MangaResumeRowsTableCreateCompanionBuilder,
          $$MangaResumeRowsTableUpdateCompanionBuilder,
          (
            MangaResumeRow,
            BaseReferences<
              _$ReaderDatabase,
              $MangaResumeRowsTable,
              MangaResumeRow
            >,
          ),
          MangaResumeRow,
          PrefetchHooks Function()
        > {
  $$MangaResumeRowsTableTableManager(
    _$ReaderDatabase db,
    $MangaResumeRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MangaResumeRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MangaResumeRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MangaResumeRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> identityKey = const Value.absent(),
                Value<String> mangaKey = const Value.absent(),
                Value<String> chapterKey = const Value.absent(),
                Value<bool> reversedOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MangaResumeRowsCompanion(
                identityKey: identityKey,
                mangaKey: mangaKey,
                chapterKey: chapterKey,
                reversedOrder: reversedOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String identityKey,
                required String mangaKey,
                required String chapterKey,
                required bool reversedOrder,
                Value<int> rowid = const Value.absent(),
              }) => MangaResumeRowsCompanion.insert(
                identityKey: identityKey,
                mangaKey: mangaKey,
                chapterKey: chapterKey,
                reversedOrder: reversedOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MangaResumeRowsTable, MangaResumeRow>(table),
                  BaseReferences<
                    _$ReaderDatabase,
                    $MangaResumeRowsTable,
                    MangaResumeRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MangaResumeRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$ReaderDatabase,
      $MangaResumeRowsTable,
      MangaResumeRow,
      $$MangaResumeRowsTableFilterComposer,
      $$MangaResumeRowsTableOrderingComposer,
      $$MangaResumeRowsTableAnnotationComposer,
      $$MangaResumeRowsTableCreateCompanionBuilder,
      $$MangaResumeRowsTableUpdateCompanionBuilder,
      (
        MangaResumeRow,
        BaseReferences<_$ReaderDatabase, $MangaResumeRowsTable, MangaResumeRow>,
      ),
      MangaResumeRow,
      PrefetchHooks Function()
    >;
typedef $$LibraryMangaRowsTableCreateCompanionBuilder =
    LibraryMangaRowsCompanion Function({
      required String identityKey,
      required String mangaKey,
      required String packageName,
      required String sourceId,
      required String sourceName,
      required String sourceLang,
      required String mangaJson,
      Value<int> rowid,
    });
typedef $$LibraryMangaRowsTableUpdateCompanionBuilder =
    LibraryMangaRowsCompanion Function({
      Value<String> identityKey,
      Value<String> mangaKey,
      Value<String> packageName,
      Value<String> sourceId,
      Value<String> sourceName,
      Value<String> sourceLang,
      Value<String> mangaJson,
      Value<int> rowid,
    });

class $$LibraryMangaRowsTableFilterComposer
    extends Composer<_$ReaderDatabase, $LibraryMangaRowsTable> {
  $$LibraryMangaRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mangaKey => $composableBuilder(
    column: $table.mangaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packageName => $composableBuilder(
    column: $table.packageName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceLang => $composableBuilder(
    column: $table.sourceLang,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mangaJson => $composableBuilder(
    column: $table.mangaJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LibraryMangaRowsTableOrderingComposer
    extends Composer<_$ReaderDatabase, $LibraryMangaRowsTable> {
  $$LibraryMangaRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mangaKey => $composableBuilder(
    column: $table.mangaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packageName => $composableBuilder(
    column: $table.packageName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceLang => $composableBuilder(
    column: $table.sourceLang,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mangaJson => $composableBuilder(
    column: $table.mangaJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LibraryMangaRowsTableAnnotationComposer
    extends Composer<_$ReaderDatabase, $LibraryMangaRowsTable> {
  $$LibraryMangaRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mangaKey =>
      $composableBuilder(column: $table.mangaKey, builder: (column) => column);

  GeneratedColumn<String> get packageName => $composableBuilder(
    column: $table.packageName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceLang => $composableBuilder(
    column: $table.sourceLang,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mangaJson =>
      $composableBuilder(column: $table.mangaJson, builder: (column) => column);
}

class $$LibraryMangaRowsTableTableManager
    extends
        RootTableManager<
          _$ReaderDatabase,
          $LibraryMangaRowsTable,
          LibraryMangaRow,
          $$LibraryMangaRowsTableFilterComposer,
          $$LibraryMangaRowsTableOrderingComposer,
          $$LibraryMangaRowsTableAnnotationComposer,
          $$LibraryMangaRowsTableCreateCompanionBuilder,
          $$LibraryMangaRowsTableUpdateCompanionBuilder,
          (
            LibraryMangaRow,
            BaseReferences<
              _$ReaderDatabase,
              $LibraryMangaRowsTable,
              LibraryMangaRow
            >,
          ),
          LibraryMangaRow,
          PrefetchHooks Function()
        > {
  $$LibraryMangaRowsTableTableManager(
    _$ReaderDatabase db,
    $LibraryMangaRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryMangaRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryMangaRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LibraryMangaRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> identityKey = const Value.absent(),
                Value<String> mangaKey = const Value.absent(),
                Value<String> packageName = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<String> sourceLang = const Value.absent(),
                Value<String> mangaJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryMangaRowsCompanion(
                identityKey: identityKey,
                mangaKey: mangaKey,
                packageName: packageName,
                sourceId: sourceId,
                sourceName: sourceName,
                sourceLang: sourceLang,
                mangaJson: mangaJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String identityKey,
                required String mangaKey,
                required String packageName,
                required String sourceId,
                required String sourceName,
                required String sourceLang,
                required String mangaJson,
                Value<int> rowid = const Value.absent(),
              }) => LibraryMangaRowsCompanion.insert(
                identityKey: identityKey,
                mangaKey: mangaKey,
                packageName: packageName,
                sourceId: sourceId,
                sourceName: sourceName,
                sourceLang: sourceLang,
                mangaJson: mangaJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LibraryMangaRowsTable, LibraryMangaRow>(table),
                  BaseReferences<
                    _$ReaderDatabase,
                    $LibraryMangaRowsTable,
                    LibraryMangaRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LibraryMangaRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$ReaderDatabase,
      $LibraryMangaRowsTable,
      LibraryMangaRow,
      $$LibraryMangaRowsTableFilterComposer,
      $$LibraryMangaRowsTableOrderingComposer,
      $$LibraryMangaRowsTableAnnotationComposer,
      $$LibraryMangaRowsTableCreateCompanionBuilder,
      $$LibraryMangaRowsTableUpdateCompanionBuilder,
      (
        LibraryMangaRow,
        BaseReferences<
          _$ReaderDatabase,
          $LibraryMangaRowsTable,
          LibraryMangaRow
        >,
      ),
      LibraryMangaRow,
      PrefetchHooks Function()
    >;
typedef $$LibraryFavoriteRowsTableCreateCompanionBuilder =
    LibraryFavoriteRowsCompanion Function({
      required String identityKey,
      required String mangaKey,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$LibraryFavoriteRowsTableUpdateCompanionBuilder =
    LibraryFavoriteRowsCompanion Function({
      Value<String> identityKey,
      Value<String> mangaKey,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$LibraryFavoriteRowsTableFilterComposer
    extends Composer<_$ReaderDatabase, $LibraryFavoriteRowsTable> {
  $$LibraryFavoriteRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mangaKey => $composableBuilder(
    column: $table.mangaKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LibraryFavoriteRowsTableOrderingComposer
    extends Composer<_$ReaderDatabase, $LibraryFavoriteRowsTable> {
  $$LibraryFavoriteRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mangaKey => $composableBuilder(
    column: $table.mangaKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LibraryFavoriteRowsTableAnnotationComposer
    extends Composer<_$ReaderDatabase, $LibraryFavoriteRowsTable> {
  $$LibraryFavoriteRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get identityKey => $composableBuilder(
    column: $table.identityKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mangaKey =>
      $composableBuilder(column: $table.mangaKey, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$LibraryFavoriteRowsTableTableManager
    extends
        RootTableManager<
          _$ReaderDatabase,
          $LibraryFavoriteRowsTable,
          LibraryFavoriteRow,
          $$LibraryFavoriteRowsTableFilterComposer,
          $$LibraryFavoriteRowsTableOrderingComposer,
          $$LibraryFavoriteRowsTableAnnotationComposer,
          $$LibraryFavoriteRowsTableCreateCompanionBuilder,
          $$LibraryFavoriteRowsTableUpdateCompanionBuilder,
          (
            LibraryFavoriteRow,
            BaseReferences<
              _$ReaderDatabase,
              $LibraryFavoriteRowsTable,
              LibraryFavoriteRow
            >,
          ),
          LibraryFavoriteRow,
          PrefetchHooks Function()
        > {
  $$LibraryFavoriteRowsTableTableManager(
    _$ReaderDatabase db,
    $LibraryFavoriteRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LibraryFavoriteRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LibraryFavoriteRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LibraryFavoriteRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> identityKey = const Value.absent(),
                Value<String> mangaKey = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LibraryFavoriteRowsCompanion(
                identityKey: identityKey,
                mangaKey: mangaKey,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String identityKey,
                required String mangaKey,
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => LibraryFavoriteRowsCompanion.insert(
                identityKey: identityKey,
                mangaKey: mangaKey,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LibraryFavoriteRowsTable, LibraryFavoriteRow>(
                    table,
                  ),
                  BaseReferences<
                    _$ReaderDatabase,
                    $LibraryFavoriteRowsTable,
                    LibraryFavoriteRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LibraryFavoriteRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$ReaderDatabase,
      $LibraryFavoriteRowsTable,
      LibraryFavoriteRow,
      $$LibraryFavoriteRowsTableFilterComposer,
      $$LibraryFavoriteRowsTableOrderingComposer,
      $$LibraryFavoriteRowsTableAnnotationComposer,
      $$LibraryFavoriteRowsTableCreateCompanionBuilder,
      $$LibraryFavoriteRowsTableUpdateCompanionBuilder,
      (
        LibraryFavoriteRow,
        BaseReferences<
          _$ReaderDatabase,
          $LibraryFavoriteRowsTable,
          LibraryFavoriteRow
        >,
      ),
      LibraryFavoriteRow,
      PrefetchHooks Function()
    >;

class $ReaderDatabaseManager {
  final _$ReaderDatabase _db;
  $ReaderDatabaseManager(this._db);
  $$ChapterProgressRowsTableTableManager get chapterProgressRows =>
      $$ChapterProgressRowsTableTableManager(_db, _db.chapterProgressRows);
  $$MangaResumeRowsTableTableManager get mangaResumeRows =>
      $$MangaResumeRowsTableTableManager(_db, _db.mangaResumeRows);
  $$LibraryMangaRowsTableTableManager get libraryMangaRows =>
      $$LibraryMangaRowsTableTableManager(_db, _db.libraryMangaRows);
  $$LibraryFavoriteRowsTableTableManager get libraryFavoriteRows =>
      $$LibraryFavoriteRowsTableTableManager(_db, _db.libraryFavoriteRows);
}
