part of 'business_state_client.dart';

final class BusinessMigrationDraft {
  BusinessMigrationDraft(this.request, this.retryable);
  final wire.StateMutation request;
  final bool retryable;
}

extension BusinessStateMigrations on BusinessStateClient {
  BusinessMigrationDraft? pendingMigration(String sourceKey) {
    for (final pending in _pending.values) {
      if (pending.request.hasMigrateFrom() &&
          pending.request.migrateFrom.sourceMangaKey == sourceKey) {
        return BusinessMigrationDraft(
          pending.request.deepCopy()..freeze(),
          !pending.rejected,
        );
      }
    }
    return null;
  }

  void _assertNoMigration(String key) {
    _ensureOpen();
    if (_migrationClaims.containsKey(key) ||
        _pending.values.any(
          (pending) =>
              pending.request.hasMigrateFrom() &&
              (pending.request.mangaKey == key ||
                  pending.request.migrateFrom.sourceMangaKey == key),
        )) {
      throw BusinessPendingMutationException(key, '源或目标漫画有未确认迁移；请显式处理原操作。');
    }
  }

  void _assertNoMigrationCatalog() {
    _ensureOpen();
    if (_migrationClaims.isNotEmpty ||
        _pending.values.any((pending) => pending.request.hasMigrateFrom())) {
      throw StateError('请先处理未确认迁移，再编辑分类目录。');
    }
  }

  void checkMigrationAvailable(String sourceKey, String targetKey) {
    validateBusinessMangaKey(sourceKey);
    validateBusinessMangaKey(targetKey);
    if (sourceKey == targetKey) throw const FormatException('不能迁移到同一作品。');
    _assertNoMigration(sourceKey);
    _assertNoMigration(targetKey);
    if (_pending.containsKey(sourceKey) ||
        _pending.containsKey(targetKey) ||
        _pendingCategory != null) {
      throw StateError('源、目标或分类有未确认操作，请先处理原请求。');
    }
  }

  Future<T> _migrationQueues<T>(
    String source,
    String target,
    Future<T> Function() work,
  ) {
    final keys = [source, target]..sort();
    return _serial(
      'categories',
      () => _serial(keys[0], () => _serial(keys[1], work)),
    );
  }

  Future<wire.StateMutationResponse> migrateFrom({
    required String targetKey,
    required int targetRevision,
    required wire.MigrateFrom operation,
    bool Function()? shouldContinue,
  }) async {
    if (shouldContinue?.call() == false) throw StateError('迁移页面已关闭。');
    final selected = operation.deepCopy()..freeze();
    validateBusinessMigrateFrom(selected, targetKey: targetKey);
    validateBusinessRevision(targetRevision);
    final sourceKey = selected.sourceMangaKey;
    checkMigrationAvailable(sourceKey, targetKey);
    final claim = Object();
    _migrationClaims[sourceKey] = claim;
    _migrationClaims[targetKey] = claim;
    try {
      return await _migrationQueues(sourceKey, targetKey, () async {
        _ensureOpen();
        if (shouldContinue?.call() == false) throw StateError('迁移页面已关闭。');
        if (_pending.containsKey(sourceKey) ||
            _pending.containsKey(targetKey) ||
            _pendingCategory != null) {
          throw StateError('源、目标或分类有未确认操作，请先处理原请求。');
        }
        // Never adopt a newer CAS while preparing this explicit operation.
        if ((_manga[sourceKey]?.revision ?? selected.expectedSourceRevision) >
                selected.expectedSourceRevision ||
            (_manga[targetKey]?.revision ?? targetRevision) > targetRevision ||
            _catalog.revision > selected.expectedCatalogRevision) {
          throw StateError('迁移预览已过期，请重新读取并确认。');
        }
        final request = wire.StateMutation(
          schemaVersion: _schemaVersion,
          mutationId: _uuid.v4(),
          mangaKey: targetKey,
          expectedRevision: targetRevision,
          migrateFrom: selected,
        )..freeze();
        final body = jsonEncode(wire.encodeProtoJson(request));
        if (utf8.encode(body).length > 128 * 1024) {
          throw const FormatException('所选迁移超过请求预算，请减少章节选择。');
        }
        final pending = _PendingMutation(
          body,
          request,
          body,
          _accountRevision,
          true,
          null,
        );
        _pending[targetKey] = pending;
        return _send(pending);
      });
    } finally {
      if (identical(_migrationClaims[sourceKey], claim)) {
        _migrationClaims.remove(sourceKey);
      }
      if (identical(_migrationClaims[targetKey], claim)) {
        _migrationClaims.remove(targetKey);
      }
    }
  }

  Future<wire.StateMutationResponse> retryMigration(
    String sourceKey, {
    bool Function()? shouldContinue,
  }) async {
    if (shouldContinue?.call() == false) throw StateError('迁移页面已关闭。');
    final draft = pendingMigration(sourceKey);
    if (draft == null || !draft.retryable) throw StateError('没有可重试的原迁移请求。');
    final targetKey = draft.request.mangaKey;
    if (_migrationClaims.containsKey(sourceKey) ||
        _migrationClaims.containsKey(targetKey)) {
      throw StateError('迁移正在进行。');
    }
    final claim = Object();
    _migrationClaims[sourceKey] = claim;
    _migrationClaims[targetKey] = claim;
    try {
      return await _migrationQueues(sourceKey, targetKey, () async {
        if (shouldContinue?.call() == false) throw StateError('迁移页面已关闭。');
        final pending = _pending[targetKey];
        if (pending == null || pending.request != draft.request) {
          throw StateError('原迁移请求已改变。');
        }
        return _send(pending);
      });
    } finally {
      if (identical(_migrationClaims[sourceKey], claim)) {
        _migrationClaims.remove(sourceKey);
      }
      if (identical(_migrationClaims[targetKey], claim)) {
        _migrationClaims.remove(targetKey);
      }
    }
  }

  void discardRejectedMigration(String sourceKey) {
    _ensureOpen();
    final draft = pendingMigration(sourceKey);
    if (draft == null) return;
    if (draft.retryable || _migrationClaims.containsKey(sourceKey)) {
      throw StateError('未确认的原请求只能显式重试。');
    }
    _pending.remove(draft.request.mangaKey);
    _changes.add(null);
  }
}

void _validateMigrationAck(
  wire.MigrateFrom request,
  wire.StateMutationResponse value,
) {
  if (!value.hasMigration() ||
      !value.manga.favorite ||
      value.hasProgress() ||
      value.hasBookmark() ||
      value.categoryCatalog.revision != request.expectedCatalogRevision ||
      value.migration.copiedReadChapters >
          request.chapters.where((entry) => entry.copyRead).length ||
      value.migration.copiedBookmarks >
          request.chapters.where((entry) => entry.copyBookmark).length) {
    throw const FormatException('迁移确认结果无效。');
  }
}
