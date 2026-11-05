import 'dart:async';
import 'dart:convert';

import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:protobuf/protobuf.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

final class TestBusinessRequest {
  TestBusinessRequest({
    required this.path,
    this.method = 'GET',
    Map<String, String> headers = const {},
    this.body,
  }) : headers = Map.unmodifiable(headers);

  final String path;
  final String method;
  final Map<String, String> headers;
  final String? body;
  Uri get uri => Uri.parse(path);
}

final class _Account {
  int revision = 0;
  final catalog = wire.CategoryCatalog();
  final mangas = <String, wire.MangaState>{};
  final progress = <(String, String), wire.ChapterProgressState>{};
  final bookmarks = <(String, String)>{};
  final globalSettings = wire.GlobalSettings(
    revision: 0,
    values: wire.GlobalSettingsValues(
      theme: wire.AppTheme.APP_THEME_SYSTEM,
      reader: wire.ReaderSettings(
        mode: wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
        pageLayout: wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      ),
    ),
  );
  final mangaSettings = <String, wire.MangaReaderSettings>{};
  final mutations = <String, (String, ApiReply)>{};
}

/// Component-test supplier using the real generated protocol. D1 transactions
/// and authenticated production requests are verified by the API tests.
final class TestBusinessServer implements ApiFetch {
  TestBusinessServer({
    this.defaultSubject = 'owner-subject',
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String defaultSubject;
  final DateTime Function() _now;
  final _accounts = <String, _Account>{};
  final requests = <TestBusinessRequest>[];
  FutureOr<ApiReply?> Function(TestBusinessRequest request)? beforeRequest;
  bool failNextRequest = false;
  bool failWrites = false;
  bool loseNextResponse = false;
  int appliedMutations = 0;

  TestBusinessServer get fetch => this;
  int get accountRevision => _account(defaultSubject).revision;
  int accountRevisionFor(String subject) => _account(subject).revision;
  wire.CategoryCatalog catalog({String? subject}) =>
      _account(subject ?? defaultSubject).catalog.deepCopy();
  ApiFetch forSubject(String subject) => _SubjectApi(this, subject);

  wire.MangaState? manga(String key, {String? subject}) =>
      _account(subject ?? defaultSubject).mangas[key]?.deepCopy();
  wire.ChapterProgressState? progress(
    String key,
    String chapterKey, {
    String? subject,
  }) => _account(
    subject ?? defaultSubject,
  ).progress[(key, chapterKey)]?.deepCopy();

  bool bookmarked(String key, String chapterKey, {String? subject}) =>
      _account(subject ?? defaultSubject).bookmarks.contains((key, chapterKey));

  _Account _account(String subject) =>
      _accounts.putIfAbsent(subject, _Account.new);

  @override
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) => handle(
    TestBusinessRequest(
      path: path,
      method: method,
      headers: headers,
      body: body,
    ),
  );

  Future<ApiReply> handle(
    TestBusinessRequest request, {
    String? subject,
  }) async {
    requests.add(request);
    final replacement = await beforeRequest?.call(request);
    if (replacement != null) return replacement;
    if (failNextRequest) {
      failNextRequest = false;
      throw StateError('Injected business network failure');
    }
    final trustedSubject = subject ?? defaultSubject;
    final expectedSubject = request.headers.entries
        .where((entry) => entry.key.toLowerCase() == 'x-app-subject')
        .map((entry) => entry.value)
        .firstOrNull;
    if (expectedSubject != trustedSubject) {
      return _errorReply(
        request,
        wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
        'Authenticated identity changed',
        status: 403,
      );
    }
    final account = _account(trustedSubject);
    if (request.method == 'GET' &&
        (request.uri.path == '/api/settings' ||
            request.uri.path.startsWith('/api/settings/manga/'))) {
      final key = request.uri.path == '/api/settings'
          ? null
          : request.uri.pathSegments.last;
      return _reply(_settingsSnapshot(account, mangaKey: key));
    }
    if (request.method == 'POST' &&
        request.uri.path == '/api/settings/mutations') {
      if (failWrites) {
        final mutation = wire.decodeProtoJson(
          wire.SettingsMutation(),
          jsonDecode(request.body!),
        );
        return _errorReply(
          request,
          wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_UNAVAILABLE,
          'Injected business write failure',
          status: 503,
          mutationId: mutation.mutationId,
        );
      }
      final response = _mutateSettings(account, request);
      if (loseNextResponse) {
        loseNextResponse = false;
        throw StateError('Injected lost settings mutation response');
      }
      return response;
    }
    if (request.method == 'GET' && request.uri.path == '/api/categories') {
      return _reply(
        wire.CategoryCatalogResponse(
          schemaVersion: 1,
          accountRevision: account.revision,
          categoryCatalog: account.catalog.deepCopy(),
        ),
      );
    }
    if (request.method == 'POST' &&
        request.uri.path == '/api/categories/mutations') {
      if (failWrites) {
        final mutation = wire.decodeProtoJson(
          wire.CategoryMutation(),
          jsonDecode(request.body!),
        );
        return _errorReply(
          request,
          wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_UNAVAILABLE,
          'Injected business write failure',
          status: 503,
          mutationId: mutation.mutationId,
        );
      }
      final response = _mutateCategories(account, request);
      if (loseNextResponse) {
        loseNextResponse = false;
        throw StateError('Injected lost business mutation response');
      }
      return response;
    }
    if (request.method == 'POST' &&
        request.uri.path == '/api/state/mutations') {
      if (failWrites) {
        final mutation = wire.decodeProtoJson(
          wire.StateMutation(),
          jsonDecode(request.body!),
          maxBytes: 128 * 1024,
        );
        return _errorReply(
          request,
          wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_UNAVAILABLE,
          'Injected business write failure',
          status: 503,
          mutationId: mutation.mutationId,
        );
      }
      final response = _mutate(account, request);
      if (loseNextResponse) {
        loseNextResponse = false;
        throw StateError('Injected lost business mutation response');
      }
      return response;
    }
    if (request.method == 'GET' && request.uri.path == '/api/library') {
      final revision = request.uri.queryParameters['revision'];
      if (revision != null && int.tryParse(revision) != account.revision) {
        return _reply(
          wire.LibraryPageResponse(
            schemaVersion: 1,
            accountRevision: account.revision,
            categoryCatalog: account.catalog.deepCopy(),
            error: _error(
              wire
                  .BusinessStateErrorCode
                  .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
              'Library changed during pagination',
            ),
          ),
          status: 409,
        );
      }
      final after = request.uri.queryParameters['afterKey'] ?? '';
      final entries =
          account.mangas.values
              .where(
                (value) =>
                    value.favorite && value.mangaKey.compareTo(after) > 0,
              )
              .toList()
            ..sort((a, b) => a.mangaKey.compareTo(b.mangaKey));
      final page = entries.take(8).map((value) => value.deepCopy()).toList();
      return _reply(
        wire.LibraryPageResponse(
          schemaVersion: 1,
          accountRevision: account.revision,
          categoryCatalog: account.catalog.deepCopy(),
          entries: page,
          nextKey: entries.length > page.length ? page.last.mangaKey : '',
        ),
      );
    }
    if (request.method == 'GET' &&
        request.uri.pathSegments.length == 5 &&
        request.uri.pathSegments.take(3).join('/') == 'api/state/manga' &&
        request.uri.pathSegments.last == 'bookmarks') {
      final key = request.uri.pathSegments[3];
      final revision = request.uri.queryParameters['revision'];
      if (revision != null && int.tryParse(revision) != account.revision) {
        return _reply(
          wire.BookmarkPageResponse(
            schemaVersion: 1,
            accountRevision: account.revision,
            mangaKey: key,
            error: _error(
              wire
                  .BusinessStateErrorCode
                  .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
              'Bookmarks changed during pagination',
            ),
          ),
          status: 409,
        );
      }
      final after = request.uri.queryParameters['afterKey'] ?? '';
      String order(String value) => String.fromCharCodes(utf8.encode(value));
      final entries =
          account.bookmarks
              .where(
                (entry) =>
                    entry.$1 == key &&
                    order(entry.$2).compareTo(order(after)) > 0,
              )
              .map((entry) => entry.$2)
              .toList()
            ..sort((a, b) => order(a).compareTo(order(b)));
      final page = entries.take(64).toList();
      return _reply(
        wire.BookmarkPageResponse(
          schemaVersion: 1,
          accountRevision: account.revision,
          mangaKey: key,
          entries: page.map(
            (chapterKey) =>
                wire.ChapterBookmark(chapterKey: chapterKey, bookmarked: true),
          ),
          nextKey: entries.length > page.length ? page.last : '',
        ),
      );
    }
    if (request.method == 'GET' &&
        request.uri.path.startsWith('/api/state/manga/')) {
      final key = request.uri.pathSegments.last;
      final chapterKey = request.uri.queryParameters['chapterKey'];
      return _reply(
        wire.MangaStateResponse(
          schemaVersion: 1,
          accountRevision: account.revision,
          categoryCatalog: account.catalog.deepCopy(),
          manga:
              account.mangas[key]?.deepCopy() ?? wire.MangaState(mangaKey: key),
          progress: chapterKey == null
              ? null
              : account.progress[(key, chapterKey)]?.deepCopy(),
          bookmark: chapterKey == null
              ? null
              : wire.ChapterBookmark(
                  chapterKey: chapterKey,
                  bookmarked: account.bookmarks.contains((key, chapterKey)),
                ),
        ),
      );
    }
    throw StateError(
      'Unexpected business API ${request.method} ${request.path}',
    );
  }

  wire.SettingsResponse _settingsSnapshot(
    _Account account, {
    String? mangaKey,
  }) {
    final manga = mangaKey == null
        ? null
        : (account.mangaSettings[mangaKey]?.deepCopy() ??
              wire.MangaReaderSettings(
                mangaKey: mangaKey,
                overrides: wire.ReaderSettingsOverride(),
              ));
    final defaults = account.globalSettings.values.reader;
    final overrides = manga?.overrides;
    return wire.SettingsResponse(
      schemaVersion: 1,
      accountRevision: account.revision,
      global: account.globalSettings.deepCopy(),
      manga: manga,
      effectiveReader: wire.ReaderSettings(
        mode: overrides?.hasMode() == true ? overrides!.mode : defaults.mode,
        pageLayout: overrides?.hasPageLayout() == true
            ? overrides!.pageLayout
            : defaults.pageLayout,
      ),
    );
  }

  ApiReply _mutateSettings(_Account account, TestBusinessRequest request) {
    final mutation = wire.decodeProtoJson(
      wire.SettingsMutation(),
      jsonDecode(request.body!),
      maxBytes: 128 * 1024,
    );
    final key = mutation.hasSetManga() ? mutation.setManga.mangaKey : null;
    ApiReply response({wire.BusinessStateError? error, int status = 200}) {
      final snapshot = _settingsSnapshot(account, mangaKey: key);
      return _reply(
        wire.SettingsMutationResponse(
          schemaVersion: 1,
          mutationId: mutation.mutationId,
          accountRevision: snapshot.accountRevision,
          global: snapshot.global,
          manga: snapshot.hasManga() ? snapshot.manga : null,
          effectiveReader: snapshot.effectiveReader,
          error: error,
        ),
        status: status,
      );
    }

    final fingerprint =
        'settings\n${jsonEncode(wire.encodeProtoJson(mutation))}';
    final previous = account.mutations[mutation.mutationId];
    if (previous != null) {
      return previous.$1 == fingerprint
          ? previous.$2
          : response(
              error: _error(
                wire
                    .BusinessStateErrorCode
                    .BUSINESS_STATE_ERROR_CODE_IDEMPOTENCY_CONFLICT,
                'Mutation ID already has a different payload',
              ),
              status: 409,
            );
    }
    final revision = key == null
        ? account.globalSettings.revision
        : (account.mangaSettings[key]?.revision ?? 0);
    if (mutation.expectedRevision != revision) {
      return response(
        error: _error(
          wire
              .BusinessStateErrorCode
              .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
          'Settings changed on another device',
        ),
        status: 409,
      );
    }
    if (mutation.hasSetGlobal()) {
      account.globalSettings.revision++;
      account.globalSettings.values = mutation.setGlobal.deepCopy();
    } else if (mutation.hasSetManga()) {
      account.mangaSettings[key!] = wire.MangaReaderSettings(
        mangaKey: key,
        revision: revision + 1,
        overrides: mutation.setManga.overrides.deepCopy(),
      );
    } else {
      throw StateError('Missing settings operation');
    }
    account.revision++;
    final reply = response();
    account.mutations[mutation.mutationId] = (fingerprint, reply);
    appliedMutations++;
    return reply;
  }

  ApiReply _mutate(_Account account, TestBusinessRequest request) {
    final body = request.body;
    if (body == null || utf8.encode(body).length > 128 * 1024) {
      return _errorReply(
        request,
        wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
        'Mutation body exceeds budget',
      );
    }
    final mutation = wire.decodeProtoJson(
      wire.StateMutation(),
      jsonDecode(body),
      maxBytes: 128 * 1024,
    );
    if (mutation.schemaVersion != 1 ||
        mutation.mutationId.isEmpty ||
        mutation.mangaKey.isEmpty ||
        mutation.whichOperation() == wire.StateMutation_Operation.notSet) {
      return _errorReply(
        request,
        wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
        'Invalid mutation',
        mutationId: mutation.mutationId,
      );
    }
    final fingerprint = 'manga\n${jsonEncode(wire.encodeProtoJson(mutation))}';
    final previous = account.mutations[mutation.mutationId];
    if (previous != null) {
      return previous.$1 == fingerprint
          ? previous.$2
          : _mutationError(
              account,
              mutation,
              wire
                  .BusinessStateErrorCode
                  .BUSINESS_STATE_ERROR_CODE_IDEMPOTENCY_CONFLICT,
              'Mutation ID already has a different payload',
            );
    }
    final current =
        account.mangas[mutation.mangaKey] ??
        wire.MangaState(mangaKey: mutation.mangaKey);
    if (mutation.expectedRevision != current.revision) {
      return _mutationError(
        account,
        mutation,
        wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
        'Manga changed on another device',
      );
    }
    final next = current.deepCopy();
    wire.ChapterProgressState? nextProgress;
    wire.ChapterBookmark? nextBookmark;
    switch (mutation.whichOperation()) {
      case wire.StateMutation_Operation.setFavorite:
        if (mutation.setFavorite.hasMetadata()) {
          next.metadata = mutation.setFavorite.metadata.deepCopy();
        }
        if (mutation.setFavorite.favorite && !next.favorite) {
          next.addedAtSeconds = _now().millisecondsSinceEpoch ~/ 1000;
        }
        next.favorite = mutation.setFavorite.favorite;
      case wire.StateMutation_Operation.updateMetadata:
        next.metadata = mutation.updateMetadata.deepCopy();
      case wire.StateMutation_Operation.saveProgress:
        final operation = mutation.saveProgress;
        final before = account
            .progress[(mutation.mangaKey, operation.snapshot.chapterKey)];
        if (operation.progress.epoch != (before?.epoch ?? 0)) {
          return _mutationError(
            account,
            mutation,
            wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_STALE_EPOCH,
            'Reading progress was reset',
            progress: before,
          );
        }
        nextProgress = _mergeProgress(
          operation.snapshot,
          before,
          operation.progress,
        );
        next.resume = wire.MangaResume(
          chapterKey: nextProgress.chapterKey,
          reversedOrder: operation.reversedOrder,
        );
      case wire.StateMutation_Operation.resetProgress:
        final operation = mutation.resetProgress;
        final before = account
            .progress[(mutation.mangaKey, operation.snapshot.chapterKey)];
        nextProgress = wire.ChapterProgressState(
          chapterKey: operation.snapshot.chapterKey,
          current: wire.ReadingAnchor(
            chapterKey: operation.snapshot.chapterKey,
            pageKey: operation.snapshot.pageKeys.first,
            manifestVersion: operation.snapshot.manifestVersion,
          ),
          epoch: (before?.epoch ?? 0) + 1,
        );
        next.resume = wire.MangaResume(
          chapterKey: nextProgress.chapterKey,
          reversedOrder: operation.reversedOrder,
        );
      case wire.StateMutation_Operation.setCategories:
        if (mutation.setCategories.expectedCatalogRevision !=
            account.catalog.revision) {
          return _mutationError(
            account,
            mutation,
            wire
                .BusinessStateErrorCode
                .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
            'Categories changed on another device',
          );
        }
        final ids = mutation.setCategories.categoryIds;
        if (!next.hasMetadata() ||
            ids.any(
              (id) => !account.catalog.categories.any(
                (category) => category.id == id,
              ),
            )) {
          return _mutationError(
            account,
            mutation,
            wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
            'Unknown manga or category',
          );
        }
        next.categoryIds
          ..clear()
          ..addAll(
            account.catalog.categories
                .where((category) => ids.contains(category.id))
                .map((category) => category.id),
          );
      case wire.StateMutation_Operation.setBookmark:
        final operation = mutation.setBookmark;
        if (operation.chapterKey.isEmpty || operation.chapterKey.length > 200) {
          return _mutationError(
            account,
            mutation,
            wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
            'Invalid bookmark chapter',
          );
        }
        nextBookmark = wire.ChapterBookmark(
          chapterKey: operation.chapterKey,
          bookmarked: operation.bookmarked,
        );
      case wire.StateMutation_Operation.notSet:
        throw StateError('Missing operation');
    }
    next.revision++;
    account.revision++;
    account.mangas[mutation.mangaKey] = next;
    if (nextProgress != null) {
      account.progress[(mutation.mangaKey, nextProgress.chapterKey)] =
          nextProgress;
    }
    if (nextBookmark != null) {
      final identity = (mutation.mangaKey, nextBookmark.chapterKey);
      if (nextBookmark.bookmarked) {
        account.bookmarks.add(identity);
      } else {
        account.bookmarks.remove(identity);
      }
    }
    final reply = _reply(
      wire.StateMutationResponse(
        schemaVersion: 1,
        mutationId: mutation.mutationId,
        accountRevision: account.revision,
        categoryCatalog: account.catalog.deepCopy(),
        manga: next.deepCopy(),
        progress: nextProgress?.deepCopy(),
        bookmark: nextBookmark?.deepCopy(),
      ),
    );
    account.mutations[mutation.mutationId] = (fingerprint, reply);
    appliedMutations++;
    return reply;
  }

  ApiReply _mutationError(
    _Account account,
    wire.StateMutation mutation,
    wire.BusinessStateErrorCode code,
    String message, {
    wire.ChapterProgressState? progress,
  }) => _reply(
    wire.StateMutationResponse(
      schemaVersion: 1,
      mutationId: mutation.mutationId,
      accountRevision: account.revision,
      categoryCatalog: account.catalog.deepCopy(),
      manga:
          account.mangas[mutation.mangaKey]?.deepCopy() ??
          wire.MangaState(mangaKey: mutation.mangaKey),
      progress: progress?.deepCopy(),
      bookmark: mutation.hasSetBookmark()
          ? wire.ChapterBookmark(
              chapterKey: mutation.setBookmark.chapterKey,
              bookmarked: account.bookmarks.contains((
                mutation.mangaKey,
                mutation.setBookmark.chapterKey,
              )),
            )
          : null,
      error: _error(code, message),
    ),
    status: 409,
  );

  ApiReply _mutateCategories(_Account account, TestBusinessRequest request) {
    final mutation = wire.decodeProtoJson(
      wire.CategoryMutation(),
      jsonDecode(request.body!),
      maxBytes: 128 * 1024,
    );
    final fingerprint =
        'category\n${jsonEncode(wire.encodeProtoJson(mutation))}';
    final previous = account.mutations[mutation.mutationId];
    ApiReply failure(wire.BusinessStateErrorCode code, String message) =>
        _reply(
          wire.CategoryMutationResponse(
            schemaVersion: 1,
            mutationId: mutation.mutationId,
            accountRevision: account.revision,
            categoryCatalog: account.catalog.deepCopy(),
            error: _error(code, message),
          ),
          status: 409,
        );
    if (previous != null) {
      return previous.$1 == fingerprint
          ? previous.$2
          : failure(
              wire
                  .BusinessStateErrorCode
                  .BUSINESS_STATE_ERROR_CODE_IDEMPOTENCY_CONFLICT,
              'Mutation ID already has a different payload',
            );
    }
    if (mutation.expectedRevision != account.catalog.revision) {
      return failure(
        wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
        'Categories changed on another device',
      );
    }
    final categories = account.catalog.categories;
    switch (mutation.whichOperation()) {
      case wire.CategoryMutation_Operation.createCategory:
        final category = mutation.createCategory.category;
        if (categories.any((value) => value.id == category.id) ||
            categories.length >= 64) {
          return failure(
            wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
            'Invalid new category',
          );
        }
        categories.add(category.deepCopy());
      case wire.CategoryMutation_Operation.renameCategory:
        final category = categories
            .where((value) => value.id == mutation.renameCategory.categoryId)
            .firstOrNull;
        if (category == null) {
          return failure(
            wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
            'Unknown category',
          );
        }
        category.name = mutation.renameCategory.name;
      case wire.CategoryMutation_Operation.reorderCategories:
        final ids = mutation.reorderCategories.categoryIds;
        if (ids.length != categories.length ||
            ids.toSet().length != categories.length ||
            categories.any((category) => !ids.contains(category.id))) {
          return failure(
            wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
            'Reorder requires every category',
          );
        }
        final ordered = ids
            .map((id) => categories.firstWhere((category) => category.id == id))
            .toList();
        categories
          ..clear()
          ..addAll(ordered);
        for (final manga in account.mangas.values) {
          final sorted = ids.where(manga.categoryIds.contains).toList();
          manga.categoryIds
            ..clear()
            ..addAll(sorted);
        }
      case wire.CategoryMutation_Operation.deleteCategory:
        final id = mutation.deleteCategory.categoryId;
        if (!categories.any((category) => category.id == id)) {
          return failure(
            wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
            'Unknown category',
          );
        }
        categories.removeWhere((category) => category.id == id);
        for (final manga in account.mangas.values) {
          if (manga.categoryIds.remove(id)) manga.revision++;
        }
      case wire.CategoryMutation_Operation.notSet:
        return failure(
          wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_INVALID_INPUT,
          'Missing category operation',
        );
    }
    account.revision++;
    account.catalog.revision++;
    final response = _reply(
      wire.CategoryMutationResponse(
        schemaVersion: 1,
        mutationId: mutation.mutationId,
        accountRevision: account.revision,
        categoryCatalog: account.catalog.deepCopy(),
      ),
    );
    account.mutations[mutation.mutationId] = (fingerprint, response);
    appliedMutations++;
    return response;
  }

  ApiReply _errorReply(
    TestBusinessRequest request,
    wire.BusinessStateErrorCode code,
    String message, {
    int status = 400,
    String mutationId = '',
  }) {
    final error = _error(code, message);
    if (request.uri.path == '/api/settings/mutations') {
      return _reply(
        wire.SettingsMutationResponse(
          schemaVersion: 1,
          mutationId: mutationId,
          error: error,
        ),
        status: status,
      );
    }
    if (request.uri.path.startsWith('/api/settings')) {
      return _reply(
        wire.SettingsResponse(schemaVersion: 1, error: error),
        status: status,
      );
    }
    if (request.uri.path.endsWith('/bookmarks')) {
      return _reply(
        wire.BookmarkPageResponse(
          schemaVersion: 1,
          mangaKey: request.uri.pathSegments[3],
          error: error,
        ),
        status: status,
      );
    }
    if (request.uri.path == '/api/library') {
      return _reply(
        wire.LibraryPageResponse(schemaVersion: 1, error: error),
        status: status,
      );
    }
    if (request.uri.path == '/api/state/mutations') {
      return _reply(
        wire.StateMutationResponse(
          schemaVersion: 1,
          mutationId: mutationId,
          error: error,
        ),
        status: status,
      );
    }
    if (request.uri.path == '/api/categories/mutations') {
      return _reply(
        wire.CategoryMutationResponse(
          schemaVersion: 1,
          mutationId: mutationId,
          error: error,
        ),
        status: status,
      );
    }
    if (request.uri.path == '/api/categories') {
      return _reply(
        wire.CategoryCatalogResponse(schemaVersion: 1, error: error),
        status: status,
      );
    }
    return _reply(
      wire.MangaStateResponse(schemaVersion: 1, error: error),
      status: status,
    );
  }

  wire.BusinessStateError _error(
    wire.BusinessStateErrorCode code,
    String message,
  ) => wire.BusinessStateError(
    code: code,
    message: message,
    retryable:
        code ==
        wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_UNAVAILABLE,
  );

  ApiReply _reply(GeneratedMessage message, {int status = 200}) => ApiReply(
    status: status,
    headers: const {'content-type': 'application/json'},
    body: jsonEncode(wire.encodeProtoJson(message, maxBytes: 2 * 1024 * 1024)),
    redirected: false,
  );
}

final class _SubjectApi implements ApiFetch {
  _SubjectApi(this.server, this.subject);
  final TestBusinessServer server;
  final String subject;

  @override
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) => server.handle(
    TestBusinessRequest(
      path: path,
      method: method,
      headers: headers,
      body: body,
    ),
    subject: subject,
  );
}

wire.ReadingAnchor? _project(
  wire.ChapterSnapshot snapshot,
  wire.ReadingAnchor? anchor,
) {
  if (anchor == null || anchor.chapterKey != snapshot.chapterKey) return null;
  final index = snapshot.pageKeys.indexOf(anchor.pageKey);
  if (index < 0) return null;
  return wire.ReadingAnchor(
    chapterKey: snapshot.chapterKey,
    pageKey: anchor.pageKey,
    manifestVersion: snapshot.manifestVersion,
    pageIndexHint: index,
    normalizedOffset: anchor.normalizedOffset,
  );
}

wire.ChapterProgressState _mergeProgress(
  wire.ChapterSnapshot snapshot,
  wire.ChapterProgressState? before,
  wire.ChapterProgressState incoming,
) {
  final current = _project(snapshot, incoming.current);
  if (current == null) {
    throw StateError('Current page is absent from the supplied snapshot');
  }
  final oldFurthest = before?.hasFurthest() == true ? before!.furthest : null;
  final incomingFurthest = incoming.hasFurthest() ? incoming.furthest : null;
  final oldProjected = _project(snapshot, oldFurthest);
  final newProjected = _project(snapshot, incomingFurthest);
  wire.ReadingAnchor? furthest;
  if (oldFurthest != null && oldProjected == null) {
    furthest = oldFurthest;
  } else if (incomingFurthest != null && newProjected == null) {
    furthest = oldFurthest ?? incomingFurthest;
  } else if (oldProjected == null) {
    furthest = newProjected;
  } else if (newProjected == null) {
    furthest = oldProjected;
  } else {
    furthest =
        newProjected.pageIndexHint > oldProjected.pageIndexHint ||
            (newProjected.pageIndexHint == oldProjected.pageIndexHint &&
                newProjected.normalizedOffset > oldProjected.normalizedOffset)
        ? newProjected
        : oldProjected;
  }
  return wire.ChapterProgressState(
    chapterKey: snapshot.chapterKey,
    current: current,
    furthest: furthest?.deepCopy(),
    epoch: incoming.epoch,
    completed:
        (before?.completed == true &&
            before!.current.manifestVersion == snapshot.manifestVersion) ||
        (incoming.completed &&
            incoming.current.manifestVersion == snapshot.manifestVersion),
  );
}
