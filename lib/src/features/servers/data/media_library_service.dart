import 'dart:async';

import 'package:dio/dio.dart';
import 'package:embyplayer/src/core/storage/media_cache_store.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';

class MediaLibraryService {
  MediaLibraryService(this._dio, [MediaCacheStore? cache])
    : _cache = cache ?? MemoryMediaCacheStore();

  final Dio _dio;
  final MediaCacheStore _cache;
  final Set<String> _refreshingCacheKeys = {};

  static const _libraryCacheAge = Duration(minutes: 30);
  static const _itemPageCacheAge = Duration(minutes: 10);
  static const _detailCacheAge = Duration(minutes: 15);
  static const _similarCacheAge = Duration(minutes: 30);

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
    bool forceRefresh = false,
  }) async {
    final uri =
        _appendPath(
          account.server.apiBaseUri,
          'Users/${account.userId}/Items',
        ).replace(
          queryParameters: {
            'ParentId': parentId,
            'SortBy': 'SortName',
            'SortOrder': 'Ascending',
            'Fields':
                'Overview,PrimaryImageAspectRatio,ProductionYear,'
                'RunTimeTicks,UserData',
            'ImageTypeLimit': '1',
            'EnableImageTypes': 'Primary',
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

  Future<MediaPage> _requestPage(
    Uri uri,
    AuthenticatedServer account, {
    int startIndex = 0,
    required Duration cacheAge,
    bool forceRefresh = false,
  }) async {
    try {
      final data = await _requestJson(
        uri,
        account,
        cacheAge: cacheAge,
        forceRefresh: forceRefresh,
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
  }) async {
    final cacheKey = _cacheKey(account, uri);
    if (!forceRefresh) {
      final cached = await _readCache(cacheKey, maxAge: cacheAge);
      if (cached != null) {
        _refreshInBackground(cacheKey, uri, account);
        return cached.payload;
      }
    }

    try {
      return await _fetchAndCache(cacheKey, uri, account);
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
    AuthenticatedServer account,
  ) async {
    final response = await _dio.getUri<Map<String, dynamic>>(
      uri,
      options: Options(headers: _authHeaders(account.accessToken)),
    );
    final data = response.data;
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
    AuthenticatedServer account,
  ) {
    if (!_refreshingCacheKeys.add(cacheKey)) return;
    unawaited(
      _fetchAndCache(cacheKey, uri, account)
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

  String _cacheKey(AuthenticatedServer account, Uri uri) {
    return '${account.server.serverId}:${account.userId}:${uri.toString()}';
  }

  MediaItem _parseItem(Map<String, dynamic> data, AuthenticatedServer account) {
    final id = _readString(data, 'Id');
    final imageTags = data['ImageTags'];
    final imageTag = imageTags is Map ? imageTags['Primary'] : null;
    final backdropTags = data['BackdropImageTags'];
    final backdropTag = backdropTags is List && backdropTags.isNotEmpty
        ? backdropTags.first
        : null;
    final primaryImageItemId = _readString(
      data,
      'PrimaryImageItemId',
      fallback: id,
    );
    final userData = data['UserData'];
    final runTimeTicks = _readInt(data['RunTimeTicks']);
    final resumeTicks = userData is Map
        ? _readInt(userData['PlaybackPositionTicks'])
        : null;
    final played = userData is Map && userData['Played'] == true;

    return MediaItem(
      id: id,
      name: _readString(data, 'Name'),
      kind: _readKind(_readString(data, 'Type')),
      overview: _readNullableString(data, 'Overview'),
      productionYear: _readInt(data['ProductionYear']),
      runTime: runTimeTicks == null
          ? null
          : Duration(microseconds: runTimeTicks ~/ 10),
      imageTag: imageTag is String ? imageTag : null,
      imageUri: imageTag is String && primaryImageItemId.isNotEmpty
          ? _imageUri(account.server.apiBaseUri, primaryImageItemId, imageTag)
          : null,
      backdropUri: backdropTag is String
          ? _imageUri(
              account.server.apiBaseUri,
              id,
              backdropTag,
              type: 'Backdrop',
              index: 0,
              maxWidth: 1600,
            )
          : null,
      imageHeaders: _authHeaders(account.accessToken),
      people: _readPeople(data['People'], account),
      genres: _readStringList(data['Genres']),
      communityRating: _readDouble(data['CommunityRating']),
      officialRating: _readNullableString(data, 'OfficialRating'),
      tagline:
          _readNullableString(data, 'Tagline') ??
          _readFirstString(data['Taglines']),
      seriesName: _readNullableString(data, 'SeriesName'),
      indexNumber: _readInt(data['IndexNumber']),
      parentIndexNumber: _readInt(data['ParentIndexNumber']),
      parentId: _readNullableString(data, 'ParentId'),
      played: played,
      resumePosition: resumeTicks == null
          ? Duration.zero
          : Duration(microseconds: resumeTicks ~/ 10),
    );
  }

  Uri _imageUri(
    Uri base,
    String itemId,
    String tag, {
    String type = 'Primary',
    int? index,
    int maxWidth = 480,
  }) {
    final path = index == null
        ? 'Items/$itemId/Images/$type'
        : 'Items/$itemId/Images/$type/$index';
    return _appendPath(base, path).replace(
      queryParameters: {'tag': tag, 'maxWidth': '$maxWidth', 'quality': '90'},
    );
  }

  MediaLibraryException _mapDioException(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return const MediaLibraryException(
        '登录凭据已失效，请重新登录服务器。',
        authenticationExpired: true,
      );
    }
    return MediaLibraryException(
      status == null ? '无法连接媒体服务器，请检查网络后重试。' : '媒体服务器返回错误（HTTP $status）。',
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

  MediaItemKind _readKind(String value) {
    return switch (value.toLowerCase()) {
      'movie' => MediaItemKind.movie,
      'series' => MediaItemKind.series,
      'season' => MediaItemKind.season,
      'episode' => MediaItemKind.episode,
      'video' => MediaItemKind.video,
      'audio' || 'musicalbum' || 'musicartist' => MediaItemKind.audio,
      _ => MediaItemKind.folder,
    };
  }

  String _readString(
    Map<String, dynamic> data,
    String key, {
    String fallback = '',
  }) {
    final value = data[key];
    return value is String && value.isNotEmpty ? value : fallback;
  }

  String? _readNullableString(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  int? _readInt(Object? value) {
    return value is num ? value.toInt() : null;
  }

  double? _readDouble(Object? value) {
    return value is num ? value.toDouble() : null;
  }

  List<String> _readStringList(Object? value) {
    return value is List
        ? value.whereType<String>().where((item) => item.isNotEmpty).toList()
        : const [];
  }

  List<MediaPerson> _readPeople(Object? value, AuthenticatedServer account) {
    if (value is! List) return const [];
    return value
        .whereType<Map<String, dynamic>>()
        .map((person) {
          final id = _readString(person, 'Id');
          final imageTag = _readNullableString(person, 'PrimaryImageTag');
          return MediaPerson(
            id: id,
            name: _readString(person, 'Name'),
            type: _readString(person, 'Type'),
            role: _readNullableString(person, 'Role'),
            imageUri: id.isNotEmpty && imageTag != null
                ? _imageUri(account.server.apiBaseUri, id, imageTag)
                : null,
            imageHeaders: _authHeaders(account.accessToken),
          );
        })
        .where((person) => person.name.isNotEmpty)
        .toList(growable: false);
  }

  String? _readFirstString(Object? value) {
    if (value is! List) return null;
    for (final item in value.whereType<String>()) {
      if (item.isNotEmpty) return item;
    }
    return null;
  }
}

class MediaPage {
  const MediaPage({
    required this.items,
    required this.totalRecordCount,
    required this.nextStartIndex,
  });

  final List<MediaItem> items;
  final int totalRecordCount;
  final int nextStartIndex;

  bool get hasMore => nextStartIndex < totalRecordCount;
}

class MediaLibraryException implements Exception {
  const MediaLibraryException(
    this.message, {
    this.authenticationExpired = false,
  });

  final String message;
  final bool authenticationExpired;

  @override
  String toString() => message;
}
