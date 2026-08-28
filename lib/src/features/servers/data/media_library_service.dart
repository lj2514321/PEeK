import 'dart:async';

import 'package:dio/dio.dart';
import 'package:embyplayer/src/core/storage/media_cache_store.dart';
import 'package:embyplayer/src/core/utils/pinyin_matcher.dart';
import 'package:embyplayer/src/features/servers/data/emby_media_item_parser.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

class MediaLibraryService {
  MediaLibraryService(
    this._dio, [
    MediaCacheStore? cache,
    DateTime Function()? clock,
  ]) : _cache = cache ?? MemoryMediaCacheStore(),
       _clock = clock ?? DateTime.now;

  final Dio _dio;
  final MediaCacheStore _cache;
  final DateTime Function() _clock;
  final Set<String> _refreshingCacheKeys = {};

  static const _libraryCacheAge = Duration(minutes: 30);
  static const _itemPageCacheAge = Duration(minutes: 10);
  static const _detailCacheAge = Duration(minutes: 15);
  static const _similarCacheAge = Duration(minutes: 30);
  static const _searchCacheAge = Duration(minutes: 5);
  static const _homeFeedCacheAge = Duration(minutes: 5);
  static const _recommendationCacheAge = Duration(days: 1);

  Future<List<MediaItem>> getLibraries(
    AuthenticatedServer account, {
    bool forceRefresh = false,
  }) async {
    final uri = _appendPath(
      account.server.apiBaseUri,
      'Users/${account.userId}/Views',
    );
    return (await _requestPage(
      uri,
      account,
      cacheAge: _libraryCacheAge,
      forceRefresh: forceRefresh,
    )).items;
  }

  Future<MediaPage> getItems(
    AuthenticatedServer account, {
    required String parentId,
    int startIndex = 0,
    int limit = 60,
    MediaLibrarySort sort = MediaLibrarySort.nameAscending,
    MediaLibraryKindFilter kind = MediaLibraryKindFilter.all,
    MediaLibraryStatusFilter status = MediaLibraryStatusFilter.all,
    MediaResolutionFilter resolution = MediaResolutionFilter.all,
    double? minCommunityRating,
    int? productionYear,
    bool forceRefresh = false,
  }) async {
    final query = <String, String>{
      'ParentId': parentId,
      'Recursive': 'true',
      'SortBy': sort.apiSortBy,
      'SortOrder': sort.apiSortOrder,
      'Fields':
          'Overview,PrimaryImageAspectRatio,ProductionYear,'
          'RunTimeTicks,UserData',
      'ImageTypeLimit': '1',
      'EnableImageTypes': 'Primary',
      'EnableUserData': 'true',
      'StartIndex': '$startIndex',
      'Limit': '$limit',
      'EnableTotalRecordCount': 'true',
      if (kind.apiTypes != null) 'IncludeItemTypes': kind.apiTypes!,
      if (status.apiFilter != null) 'Filters': status.apiFilter!,
      if (minCommunityRating != null)
        'MinCommunityRating': '$minCommunityRating',
      if (resolution == MediaResolutionFilter.res4k) 'MinWidth': '3840',
      if (resolution == MediaResolutionFilter.res1080p) 'MinWidth': '1920',
      if (resolution == MediaResolutionFilter.res720p) 'MinWidth': '1280',
      if (productionYear != null) 'Years': '$productionYear',
    };
    final uri = _appendPath(
      account.server.apiBaseUri,
      'Users/${account.userId}/Items',
    ).replace(queryParameters: query);
    return _requestPage(
      uri,
      account,
      startIndex: startIndex,
      cacheAge: _itemPageCacheAge,
      forceRefresh: forceRefresh,
    );
  }

  Future<MediaPage> getFavoriteItems(
    AuthenticatedServer account, {
    int startIndex = 0,
    int limit = 60,
    bool forceRefresh = false,
  }) async {
    final uri =
        _appendPath(
          account.server.apiBaseUri,
          'Users/${account.userId}/Items',
        ).replace(
          queryParameters: {
            'Recursive': 'true',
            'IncludeItemTypes': 'Movie,Series,Episode,Video,Audio',
            'Filters': 'IsFavorite',
            'SortBy': 'SortName',
            'SortOrder': 'Ascending',
            'Fields':
                'Overview,PrimaryImageAspectRatio,ProductionYear,'
                'RunTimeTicks,UserData',
            'ImageTypeLimit': '1',
            'EnableImageTypes': 'Primary',
            'EnableUserData': 'true',
            'StartIndex': '$startIndex',
            'Limit': '$limit',
            'EnableTotalRecordCount': 'true',
          },
        );
    return _requestPage(
      uri,
      account,
      startIndex: startIndex,
      cacheAge: _itemPageCacheAge,
      forceRefresh: forceRefresh,
    );
  }

  Future<MediaPage> getActors(
    AuthenticatedServer account, {
    String? parentId,
    int startIndex = 0,
    int limit = 60,
    bool forceRefresh = false,
  }) async {
    final query = <String, String>{
      'Recursive': 'true',
      'IncludeItemTypes': 'Movie,Series,Episode,Video',
      'Fields': 'People',
      'StartIndex': '$startIndex',
      'Limit': '$limit',
      'EnableTotalRecordCount': 'true',
      if (parentId != null && parentId.isNotEmpty) 'ParentId': parentId,
    };

    final itemsUri = _appendPath(
      account.server.apiBaseUri,
      'Users/${account.userId}/Items',
    ).replace(queryParameters: query);

    final page = await _requestPage(
      itemsUri,
      account,
      startIndex: startIndex,
      cacheAge: _itemPageCacheAge,
      forceRefresh: forceRefresh,
    );

    final Map<String, MediaItem> collectedActors = {};
    for (final item in page.items) {
      for (final person in item.people) {
        final key = person.id.isNotEmpty ? person.id : person.name;
        if (key.isNotEmpty && !collectedActors.containsKey(key)) {
          collectedActors[key] = MediaItem(
            id: person.id,
            name: person.name,
            kind: MediaItemKind.person,
            imageUri: person.imageUri,
            imageHeaders: person.imageHeaders,
          );
        }
      }
    }

    final itemsList = collectedActors.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return MediaPage(
      items: itemsList,
      totalRecordCount: page.totalRecordCount > itemsList.length
          ? page.totalRecordCount
          : itemsList.length,
      nextStartIndex: page.nextStartIndex,
      rawItemCount: page.rawItemCount,
    );
  }

  Future<MediaPage> search(
    AuthenticatedServer account, {
    required String query,
    MediaSearchScope scope = MediaSearchScope.all,
    int startIndex = 0,
    int limit = 40,
    bool forceRefresh = false,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const MediaPage(items: [], totalRecordCount: 0, nextStartIndex: 0);
    }
    final uri = _appendPath(account.server.apiBaseUri, 'Search/Hints').replace(
      queryParameters: {
        'SearchTerm': normalizedQuery,
        'UserId': account.userId,
        'StartIndex': '$startIndex',
        'Limit': '$limit',
        'IncludeItemTypes': scope.apiTypes,
        'IncludeMedia': '${scope != MediaSearchScope.people}',
        'IncludePeople': '${scope.includesPeople}',
      },
    );
    try {
      final data = await _requestJson(
        uri,
        account,
        cacheAge: _searchCacheAge,
        forceRefresh: forceRefresh,
      );
      final rawHints = data['SearchHints'];
      if (rawHints is! List) {
        throw const MediaLibraryException('服务器返回了无法识别的搜索结果。');
      }
      var items = rawHints
          .whereType<Map<String, dynamic>>()
          .map((hint) => _parseSearchHint(hint, account))
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .toList(growable: true);

      // Pinyin shorthand fallback (e.g., query 'zxc' -> matches '周星驰' if server Search/Hints returned 0)
      if (items.isEmpty && RegExp(r'^[a-zA-Z]{1,12}$').hasMatch(normalizedQuery)) {
        final candidates = await _getPinyinSearchCandidates(account, scope: scope);
        final pinyinMatched = candidates
            .where((item) => PinyinMatcher.matches(item.name, normalizedQuery))
            .toList();
        if (pinyinMatched.isNotEmpty) {
          items = pinyinMatched;
        }
      }

      return MediaPage(
        items: items,
        totalRecordCount:
            _readInt(data['TotalRecordCount']) ?? startIndex + items.length,
        nextStartIndex: startIndex + items.length,
      );
    } on MediaLibraryException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<List<MediaItem>> _getPinyinSearchCandidates(
    AuthenticatedServer account, {
    MediaSearchScope scope = MediaSearchScope.all,
  }) async {
    final uri = _appendPath(
      account.server.apiBaseUri,
      'Users/${account.userId}/Items',
    ).replace(
      queryParameters: {
        'Recursive': 'true',
        'Fields': 'Overview,ProductionYear,UserData',
        'IncludeItemTypes': scope == MediaSearchScope.people
            ? 'Person'
            : (scope.apiTypes),
        'Limit': '200',
      },
    );
    try {
      final data = await _requestJson(
        uri,
        account,
        cacheAge: _searchCacheAge,
        forceRefresh: false,
      );
      final items = data['Items'];
      if (items is! List) return const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map((item) => _parseItem(item, account))
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<RemoteSubtitleInfo>> searchRemoteSubtitles(
    AuthenticatedServer account, {
    required String itemId,
    String language = 'chi',
  }) async {
    final uri = _appendPath(
      account.server.apiBaseUri,
      'Items/$itemId/RemoteSearch/Subtitles/$language',
    );
    try {
      final data = await _requestJson(
        uri,
        account,
        cacheAge: Duration.zero,
        forceRefresh: true,
        allowListResponse: true,
      );
      final items = data['Items'];
      if (items is! List) return const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map((json) => RemoteSubtitleInfo.fromJson(json))
          .where((sub) => sub.id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<bool> downloadRemoteSubtitle(
    AuthenticatedServer account, {
    required String itemId,
    required String subtitleId,
  }) async {
    final uri = _appendPath(
      account.server.apiBaseUri,
      'Items/$itemId/RemoteSearch/Subtitles/$subtitleId',
    );
    try {
      await _dio.post(
        uri.toString(),
        options: Options(headers: {'X-Emby-Token': account.accessToken}),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<QuickConnectInitResult?> initiateQuickConnect(Uri serverUri) async {
    final uri = _appendPath(serverUri, 'QuickConnect/Initiate');
    try {
      final response = await _dio.post<Map<String, dynamic>>(uri.toString());
      if (response.data is Map<String, dynamic>) {
        return QuickConnectInitResult.fromJson(response.data!);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<QuickConnectStateResult?> checkQuickConnectState(
    Uri serverUri,
    String secret,
  ) async {
    final uri = _appendPath(serverUri, 'QuickConnect/Connect');
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        uri.toString(),
        queryParameters: {'secret': secret},
      );
      if (response.data is Map<String, dynamic>) {
        return QuickConnectStateResult.fromJson(response.data!);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<MediaPage> getItemsForPerson(
    AuthenticatedServer account, {
    required String personId,
    int startIndex = 0,
    int limit = 40,
    bool forceRefresh = false,
  }) async {
    final uri =
        _appendPath(
          account.server.apiBaseUri,
          'Users/${account.userId}/Items',
        ).replace(
          queryParameters: {
            'PersonIds': personId,
            'Recursive': 'true',
            'IncludeItemTypes': 'Movie,Series,Episode,Video',
            'SortBy': 'ProductionYear,SortName',
            'SortOrder': 'Descending',
            'Fields':
                'Overview,PrimaryImageAspectRatio,ProductionYear,'
                'RunTimeTicks,UserData',
            'ImageTypeLimit': '1',
            'EnableImageTypes': 'Primary',
            'EnableTotalRecordCount': 'true',
            'StartIndex': '$startIndex',
            'Limit': '$limit',
          },
        );
    return _requestPage(
      uri,
      account,
      startIndex: startIndex,
      cacheAge: _searchCacheAge,
      forceRefresh: forceRefresh,
    );
  }

  Future<List<MediaItem>> getEpisodesForSeries(
    AuthenticatedServer account, {
    required String seriesId,
    bool forceRefresh = false,
  }) async {
    final uri =
        _appendPath(
          account.server.apiBaseUri,
          'Users/${account.userId}/Items',
        ).replace(
          queryParameters: {
            'ParentId': seriesId,
            'Recursive': 'true',
            'IncludeItemTypes': 'Episode',
            'IsMissing': 'false',
            'SortBy': 'SortName',
            'SortOrder': 'Ascending',
            'Fields':
                'Overview,PrimaryImageAspectRatio,ProductionYear,'
                'RunTimeTicks,UserData,ParentId,SeriesId,SeriesName,'
                'IndexNumber,ParentIndexNumber',
            'ImageTypeLimit': '1',
            'EnableImageTypes': 'Primary',
            'EnableUserData': 'true',
            'EnableTotalRecordCount': 'true',
            'StartIndex': '0',
            'Limit': '10000',
          },
        );
    final page = await _requestPage(
      uri,
      account,
      cacheAge: _itemPageCacheAge,
      forceRefresh: forceRefresh,
    );
    return page.items
        .where((item) => item.kind == MediaItemKind.episode)
        .toList(growable: false);
  }

  Future<List<MediaItem>> getResumeItems(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
  }) async {
    final query = <String, String>{
      'UserId': account.userId,
      'MediaTypes': 'Video',
      'IncludeItemTypes': 'Movie,Episode,Video',
      'Fields':
          'Overview,PrimaryImageAspectRatio,ProductionYear,'
          'RunTimeTicks,UserData,ParentId,SeriesId,SeriesName,'
          'IndexNumber,ParentIndexNumber',
      'ImageTypeLimit': '1',
      'EnableImageTypes': 'Primary,Backdrop',
      'EnableImages': 'true',
      'EnableUserData': 'true',
      'ExcludeActiveSessions': 'true',
      'StartIndex': '0',
      'Limit': '$limit',
      'EnableTotalRecordCount': 'true',
    };
    final uri = _appendPath(
      account.server.apiBaseUri,
      'Users/${account.userId}/Items/Resume',
    ).replace(queryParameters: query);
    try {
      return (await _requestPage(
        uri,
        account,
        cacheAge: _homeFeedCacheAge,
        forceRefresh: forceRefresh,
      )).items;
    } on MediaLibraryException catch (error) {
      if (error.statusCode != 400 && error.statusCode != 404) rethrow;
      final fallbackUri =
          _appendPath(
            account.server.apiBaseUri,
            'Users/${account.userId}/Items',
          ).replace(
            queryParameters: {
              ...query,
              'Recursive': 'true',
              'Filters': 'IsResumable',
              'SortBy': 'DatePlayed',
              'SortOrder': 'Descending',
            },
          );
      return (await _requestPage(
        fallbackUri,
        account,
        cacheAge: _homeFeedCacheAge,
        forceRefresh: forceRefresh,
      )).items;
    }
  }

  Future<List<MediaItem>> getLatestMovies(
    AuthenticatedServer account, {
    int limit = 18,
    String? parentId,
    bool forceRefresh = false,
  }) {
    return _getLatestItems(
      account,
      includeItemTypes: 'Movie',
      limit: limit,
      parentId: parentId,
      forceRefresh: forceRefresh,
    );
  }

  Future<List<MediaItem>> getLatestEpisodes(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
  }) {
    return _getLatestItems(
      account,
      includeItemTypes: 'Episode',
      limit: limit,
      forceRefresh: forceRefresh,
    );
  }

  Future<List<MediaItem>> getRecommendations(
    AuthenticatedServer account, {
    int limit = 6,
    bool forceRefresh = false,
  }) async {
    final uri = _appendPath(account.server.apiBaseUri, 'Items/Suggestions')
        .replace(
          queryParameters: {
            'UserId': account.userId,
            'MediaType': 'Video',
            'Type': 'Movie,Episode,Video',
            'StartIndex': '0',
            'Limit': '$limit',
            'EnableTotalRecordCount': 'true',
          },
        );
    try {
      return (await _requestPage(
        uri,
        account,
        cacheAge: _recommendationCacheAge,
        forceRefresh: forceRefresh,
        cacheForCurrentDay: true,
        refreshCachedInBackground: false,
      )).items;
    } on MediaLibraryException catch (error) {
      if (error.statusCode != 400 && error.statusCode != 404) rethrow;
      final fallbackUri =
          _appendPath(
            account.server.apiBaseUri,
            'Users/${account.userId}/Items',
          ).replace(
            queryParameters: {
              'Recursive': 'true',
              'IncludeItemTypes': 'Movie,Episode,Video',
              'MediaTypes': 'Video',
              'SortBy': 'Random',
              'Filters': 'IsNotFolder',
              'Fields':
                  'Overview,PrimaryImageAspectRatio,ProductionYear,'
                  'RunTimeTicks,UserData,ParentId,SeriesId,SeriesName,'
                  'IndexNumber,ParentIndexNumber',
              'ImageTypeLimit': '1',
              'EnableImageTypes': 'Primary,Backdrop',
              'EnableImages': 'true',
              'EnableUserData': 'true',
              'StartIndex': '0',
              'Limit': '$limit',
              'EnableTotalRecordCount': 'true',
            },
          );
      return (await _requestPage(
        fallbackUri,
        account,
        cacheAge: _recommendationCacheAge,
        forceRefresh: forceRefresh,
        cacheForCurrentDay: true,
        refreshCachedInBackground: false,
      )).items;
    }
  }

  Future<List<MediaItem>> _getLatestItems(
    AuthenticatedServer account, {
    required String includeItemTypes,
    required int limit,
    String? parentId,
    required bool forceRefresh,
  }) async {
    final uri =
        _appendPath(
          account.server.apiBaseUri,
          'Users/${account.userId}/Items/Latest',
        ).replace(
          queryParameters: {
            'IncludeItemTypes': includeItemTypes,
            'MediaTypes': 'Video',
            'Fields':
                'Overview,PrimaryImageAspectRatio,ProductionYear,'
                'RunTimeTicks,UserData,ParentId,SeriesId,SeriesName,'
                'IndexNumber,ParentIndexNumber',
            'ImageTypeLimit': '1',
            'EnableImageTypes': 'Primary,Backdrop',
            'EnableImages': 'true',
            'EnableUserData': 'true',
            'GroupItems': 'false',
            'Limit': '$limit',
            if (parentId != null && parentId.isNotEmpty) 'ParentId': parentId,
          },
        );
    return (await _requestPage(
      uri,
      account,
      cacheAge: _homeFeedCacheAge,
      forceRefresh: forceRefresh,
      allowListResponse: true,
    )).items;
  }

  Future<MediaItem> getItem(
    AuthenticatedServer account,
    String itemId, {
    bool forceRefresh = false,
  }) async {
    final uri = _appendPath(
      account.server.apiBaseUri,
      'Users/${account.userId}/Items/$itemId',
    );
    try {
      final data = await _requestJson(
        uri,
        account,
        cacheAge: _detailCacheAge,
        forceRefresh: forceRefresh,
      );
      return _parseItem(data, account);
    } on MediaLibraryException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<List<MediaItem>> getSimilar(
    AuthenticatedServer account,
    String itemId, {
    int limit = 12,
    bool forceRefresh = false,
  }) async {
    final uri = _appendPath(account.server.apiBaseUri, 'Items/$itemId/Similar')
        .replace(
          queryParameters: {
            'UserId': account.userId,
            'Limit': '$limit',
            'Fields':
                'Overview,PrimaryImageAspectRatio,ProductionYear,RunTimeTicks,UserData',
          },
        );
    return (await _requestPage(
      uri,
      account,
      cacheAge: _similarCacheAge,
      forceRefresh: forceRefresh,
    )).items;
  }

  Future<void> setFavorite(
    AuthenticatedServer account,
    String itemId, {
    required bool favorite,
  }) {
    return setFavoriteForItems(account, [itemId], favorite: favorite);
  }

  Future<void> setPlayed(
    AuthenticatedServer account,
    String itemId, {
    required bool played,
  }) {
    return setPlayedForItems(account, [itemId], played: played);
  }

  Future<void> setFavoriteForItems(
    AuthenticatedServer account,
    Iterable<String> itemIds, {
    required bool favorite,
  }) {
    return _setUserItemsState(
      account,
      itemIds,
      pathSegment: 'FavoriteItems',
      enabled: favorite,
    );
  }

  Future<void> setPlayedForItems(
    AuthenticatedServer account,
    Iterable<String> itemIds, {
    required bool played,
  }) {
    return _setUserItemsState(
      account,
      itemIds,
      pathSegment: 'PlayedItems',
      enabled: played,
    );
  }

  Future<void> _setUserItemsState(
    AuthenticatedServer account,
    Iterable<String> itemIds, {
    required String pathSegment,
    required bool enabled,
  }) async {
    final ids = itemIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return;
    try {
      for (var start = 0; start < ids.length; start += 4) {
        final end = (start + 4).clamp(0, ids.length);
        await Future.wait(
          ids.sublist(start, end).map((itemId) async {
            final uri = _appendPath(
              account.server.apiBaseUri,
              'Users/${account.userId}/$pathSegment/$itemId',
            );
            final options = Options(headers: _authHeaders(account.accessToken));
            if (enabled) {
              await _dio.postUri<void>(uri, options: options);
            } else {
              await _dio.deleteUri<void>(uri, options: options);
            }
          }),
        );
      }
    } on DioException catch (error) {
      throw _mapDioException(error);
    } finally {
      try {
        await _cache.clear();
      } on Object {
        // User state is already updated; cache cleanup must not report failure.
      }
    }
  }

  Future<void> deleteItem(
    AuthenticatedServer account,
    String itemId,
  ) async {
    final uri = _appendPath(account.server.apiBaseUri, 'Items/$itemId');
    try {
      await _dio.deleteUri<void>(
        uri,
        options: Options(headers: _authHeaders(account.accessToken)),
      );
      try {
        await _cache.clear();
      } on Object {
        // Ignore cache clear error
      }
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<MediaPage> _requestPage(
    Uri uri,
    AuthenticatedServer account, {
    int startIndex = 0,
    required Duration cacheAge,
    bool forceRefresh = false,
    bool allowListResponse = false,
    bool cacheForCurrentDay = false,
    bool refreshCachedInBackground = true,
  }) async {
    try {
      final data = await _requestJson(
        uri,
        account,
        cacheAge: cacheAge,
        forceRefresh: forceRefresh,
        allowListResponse: allowListResponse,
        cacheForCurrentDay: cacheForCurrentDay,
        refreshCachedInBackground: refreshCachedInBackground,
      );
      final rawItems = data['Items'];
      if (rawItems is! List) {
        throw const MediaLibraryException('服务器返回了无法识别的媒体库数据。');
      }

      final items = rawItems
          .whereType<Map<String, dynamic>>()
          .map((item) => _parseItem(item, account))
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .toList(growable: false);
      return MediaPage(
        items: items,
        totalRecordCount:
            _readInt(data['TotalRecordCount']) ?? startIndex + rawItems.length,
        nextStartIndex: startIndex + rawItems.length,
        rawItemCount: rawItems.length,
      );
    } on MediaLibraryException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error);
    }
  }

  Future<Map<String, dynamic>> _requestJson(
    Uri uri,
    AuthenticatedServer account, {
    required Duration cacheAge,
    required bool forceRefresh,
    bool allowListResponse = false,
    bool cacheForCurrentDay = false,
    bool refreshCachedInBackground = true,
  }) async {
    final cacheKey = _cacheKey(account, uri);
    if (!forceRefresh) {
      final cached = await _readCache(
        cacheKey,
        maxAge: cacheForCurrentDay ? null : cacheAge,
      );
      if (cached != null &&
          (!cacheForCurrentDay || _isStoredToday(cached.storedAt))) {
        if (refreshCachedInBackground) {
          _refreshInBackground(
            cacheKey,
            uri,
            account,
            allowListResponse: allowListResponse,
          );
        }
        return cached.payload;
      }
    }

    try {
      return await _fetchAndCache(
        cacheKey,
        uri,
        account,
        allowListResponse: allowListResponse,
      );
    } on DioException {
      if (!forceRefresh) {
        final stale = await _readCache(cacheKey);
        if (stale != null) return stale.payload;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _fetchAndCache(
    String cacheKey,
    Uri uri,
    AuthenticatedServer account, {
    bool allowListResponse = false,
  }) async {
    final response = await _dio.getUri<Object?>(
      uri,
      options: Options(headers: _authHeaders(account.accessToken)),
    );
    final payload = response.data;
    final Map<String, dynamic>? data = switch (payload) {
      Map<String, dynamic>() => payload,
      Map() => Map<String, dynamic>.from(payload),
      List() when allowListResponse => <String, dynamic>{'Items': payload},
      _ => null,
    };
    if (data == null) {
      throw const MediaLibraryException('服务器返回了无法识别的媒体数据。');
    }
    try {
      await _cache.write(cacheKey, data);
    } on Object {
      // Cache writes are an optimization and must not block fresh data.
    }
    return data;
  }

  void _refreshInBackground(
    String cacheKey,
    Uri uri,
    AuthenticatedServer account, {
    bool allowListResponse = false,
  }) {
    if (!_refreshingCacheKeys.add(cacheKey)) return;
    unawaited(
      _fetchAndCache(
            cacheKey,
            uri,
            account,
            allowListResponse: allowListResponse,
          )
          .catchError((_) => <String, dynamic>{})
          .whenComplete(() => _refreshingCacheKeys.remove(cacheKey)),
    );
  }

  Future<MediaCacheEntry?> _readCache(
    String cacheKey, {
    Duration? maxAge,
  }) async {
    try {
      return await _cache.read(cacheKey, maxAge: maxAge);
    } on Object {
      return null;
    }
  }

  bool _isStoredToday(DateTime storedAt) {
    final stored = storedAt.toLocal();
    final now = _clock().toLocal();
    return stored.year == now.year &&
        stored.month == now.month &&
        stored.day == now.day;
  }

  String _cacheKey(AuthenticatedServer account, Uri uri) {
    return '${account.server.serverId}:${account.userId}:${uri.toString()}';
  }

  MediaItem _parseItem(Map<String, dynamic> data, AuthenticatedServer account) {
    return EmbyMediaItemParser.parseItem(data, account);
  }

  MediaItem _parseSearchHint(
    Map<String, dynamic> data,
    AuthenticatedServer account,
  ) {
    return EmbyMediaItemParser.parseSearchHint(data, account);
  }

  MediaLibraryException _mapDioException(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return MediaLibraryException(
        '登录凭据已失效，请重新登录服务器。',
        authenticationExpired: true,
        statusCode: status,
      );
    }
    return MediaLibraryException(
      status == null ? '无法连接媒体服务器，请检查网络后重试。' : '媒体服务器返回错误（HTTP $status）。',
      statusCode: status,
    );
  }

  Map<String, String> _authHeaders(String token) {
    return {'X-Emby-Token': token};
  }

  Uri _appendPath(Uri base, String path) {
    return base.replace(
      pathSegments: [...base.pathSegments, ...path.split('/')],
    );
  }

  int? _readInt(Object? value) {
    return value is num ? value.toInt() : null;
  }
}

enum MediaLibrarySort {
  nameAscending,
  dateCreatedDescending,
  productionYearDescending,
  ratingDescending,
}

extension MediaLibrarySortApi on MediaLibrarySort {
  String get label => switch (this) {
    MediaLibrarySort.nameAscending => '名称 A–Z',
    MediaLibrarySort.dateCreatedDescending => '最近添加',
    MediaLibrarySort.productionYearDescending => '上映年份',
    MediaLibrarySort.ratingDescending => '评分最高',
  };

  String get apiSortBy => switch (this) {
    MediaLibrarySort.nameAscending => 'SortName',
    MediaLibrarySort.dateCreatedDescending => 'DateCreated,SortName',
    MediaLibrarySort.productionYearDescending => 'ProductionYear,SortName',
    MediaLibrarySort.ratingDescending => 'CommunityRating,SortName',
  };

  String get apiSortOrder => switch (this) {
    MediaLibrarySort.nameAscending => 'Ascending',
    _ => 'Descending',
  };
}

enum MediaLibraryKindFilter { all, movies, series, episodes }

extension MediaLibraryKindFilterApi on MediaLibraryKindFilter {
  String get label => switch (this) {
    MediaLibraryKindFilter.all => '全部类型',
    MediaLibraryKindFilter.movies => '电影',
    MediaLibraryKindFilter.series => '剧集',
    MediaLibraryKindFilter.episodes => '单集',
  };

  String? get apiTypes => switch (this) {
    MediaLibraryKindFilter.all => null,
    MediaLibraryKindFilter.movies => 'Movie',
    MediaLibraryKindFilter.series => 'Series',
    MediaLibraryKindFilter.episodes => 'Episode',
  };
}

enum MediaResolutionFilter { all, res4k, res1080p, res720p }

extension MediaResolutionFilterApi on MediaResolutionFilter {
  String get label => switch (this) {
    MediaResolutionFilter.all => '全部画质',
    MediaResolutionFilter.res4k => '4K 超清',
    MediaResolutionFilter.res1080p => '1080P 高清',
    MediaResolutionFilter.res720p => '720P',
  };
}

enum MediaLibraryStatusFilter { all, unplayed, inProgress, played, favorites }

extension MediaLibraryStatusFilterApi on MediaLibraryStatusFilter {
  String get label => switch (this) {
    MediaLibraryStatusFilter.all => '全部状态',
    MediaLibraryStatusFilter.unplayed => '未观看',
    MediaLibraryStatusFilter.inProgress => '观看中',
    MediaLibraryStatusFilter.played => '已观看',
    MediaLibraryStatusFilter.favorites => '已收藏',
  };

  String? get apiFilter => switch (this) {
    MediaLibraryStatusFilter.unplayed => 'IsUnplayed',
    MediaLibraryStatusFilter.inProgress => 'IsResumable',
    MediaLibraryStatusFilter.played => 'IsPlayed',
    MediaLibraryStatusFilter.favorites => 'IsFavorite',
    MediaLibraryStatusFilter.all => null,
  };
}

enum MediaSearchScope { all, movies, series, episodes, people }

extension MediaSearchScopeApi on MediaSearchScope {
  String get apiTypes => switch (this) {
    MediaSearchScope.all => 'Movie,Series,Episode,Video,Person',
    MediaSearchScope.movies => 'Movie,Video',
    MediaSearchScope.series => 'Series',
    MediaSearchScope.episodes => 'Episode',
    MediaSearchScope.people => 'Person',
  };

  bool get includesPeople =>
      this == MediaSearchScope.all || this == MediaSearchScope.people;
}

class MediaPage {
  const MediaPage({
    required this.items,
    required this.totalRecordCount,
    required this.nextStartIndex,
    this.rawItemCount,
  });

  final List<MediaItem> items;
  final int totalRecordCount;
  final int nextStartIndex;
  final int? rawItemCount;

  bool get hasMore => nextStartIndex < totalRecordCount;
}

class MediaLibraryException implements Exception {
  const MediaLibraryException(
    this.message, {
    this.authenticationExpired = false,
    this.statusCode,
  });

  final String message;
  final bool authenticationExpired;
  final int? statusCode;

  @override
  String toString() => message;
}

class RemoteSubtitleInfo {
  const RemoteSubtitleInfo({
    required this.id,
    required this.name,
    required this.providerName,
    required this.format,
    this.comment,
  });

  factory RemoteSubtitleInfo.fromJson(Map<String, dynamic> json) {
    return RemoteSubtitleInfo(
      id: json['Id']?.toString() ?? '',
      name: json['Name']?.toString() ?? json['SubtitleId']?.toString() ?? '未知字幕',
      providerName: json['ProviderName']?.toString() ?? 'RemoteProvider',
      format: json['Format']?.toString() ?? 'srt',
      comment: json['Comment']?.toString(),
    );
  }

  final String id;
  final String name;
  final String providerName;
  final String format;
  final String? comment;
}

class QuickConnectInitResult {
  const QuickConnectInitResult({
    required this.code,
    required this.secret,
  });

  factory QuickConnectInitResult.fromJson(Map<String, dynamic> json) {
    return QuickConnectInitResult(
      code: json['Code']?.toString() ?? '',
      secret: json['Secret']?.toString() ?? '',
    );
  }

  final String code;
  final String secret;
}

class QuickConnectStateResult {
  const QuickConnectStateResult({
    required this.authenticated,
    this.accessToken,
    this.userId,
    this.userName,
  });

  factory QuickConnectStateResult.fromJson(Map<String, dynamic> json) {
    final auth = json['Authenticated'] == true;
    final result = json['AuthenticationResult'];
    final user = result is Map ? result['User'] : null;
    return QuickConnectStateResult(
      authenticated: auth,
      accessToken: result is Map ? result['AccessToken']?.toString() : null,
      userId: user is Map ? user['Id']?.toString() : null,
      userName: user is Map ? user['Name']?.toString() : null,
    );
  }

  final bool authenticated;
  final String? accessToken;
  final String? userId;
  final String? userName;
}
