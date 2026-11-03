import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'reading_progress.dart';

part 'reader_database.g.dart';

class ChapterProgressRows extends Table {
  TextColumn get identityKey => text()();
  TextColumn get mangaKey => text()();
  TextColumn get chapterKey => text()();
  TextColumn get currentJson => text()();
  TextColumn get furthestJson => text().nullable()();
  IntColumn get epoch => integer()();
  BoolColumn get completed => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {identityKey, mangaKey, chapterKey};

  @override
  List<String> get customConstraints => ['CHECK (epoch >= 0)'];
}

class MangaResumeRows extends Table {
  TextColumn get identityKey => text()();
  TextColumn get mangaKey => text()();
  TextColumn get chapterKey => text()();
  BoolColumn get reversedOrder => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {identityKey, mangaKey};
}

@DriftDatabase(tables: [ChapterProgressRows, MangaResumeRows])
class ReaderDatabase extends _$ReaderDatabase {
  ReaderDatabase(
    super.executor, {
    ProgressStorageMode storageMode = ProgressStorageMode.memoryOnly,
  }) : _mode = Future.value(storageMode);

  ReaderDatabase._(super.executor, this._mode);

  factory ReaderDatabase.open() {
    final capability = Completer<ProgressStorageMode>();
    final connection = driftDatabase(
      name: 'karuyomi_reader',
      native: DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('/database/sqlite3.wasm'),
        driftWorker: Uri.parse('/database/drift_worker.js'),
        onResult: (result) {
          capability.complete(switch (result.chosenImplementation) {
            WasmStorageImplementation.inMemory =>
              ProgressStorageMode.memoryOnly,
            WasmStorageImplementation.unsafeIndexedDb =>
              ProgressStorageMode.unsafePersistence,
            WasmStorageImplementation.opfsShared ||
            WasmStorageImplementation.opfsLocks ||
            WasmStorageImplementation.sharedIndexedDb =>
              ProgressStorageMode.persistent,
          });
        },
      ),
    );
    return ReaderDatabase._(
      connection,
      kIsWeb ? capability.future : Future.value(ProgressStorageMode.persistent),
    );
  }

  final Future<ProgressStorageMode> _mode;

  /// Forces the lazy executor to open, so failure is not mistaken for durable
  /// storage and the web classification comes from Drift's actual selection.
  Future<ProgressStorageMode> get storageMode async {
    await customSelect('SELECT 1').get();
    return _mode;
  }

  @override
  int get schemaVersion => 1;
}
