import 'dart:async';

import 'package:dio/dio.dart';
import 'package:embyplayer/src/core/storage/media_cache_store.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/remote_search_result.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final discoveredServer = DiscoveredServer(
    kind: ServerKind.jellyfin,
    name: 'Living Room',
    version: '10.11.6',
    serverId: 'server-id',
    apiBaseUri: Uri(scheme: 'http', host: '192.168.1.20', port: 8096),
  );
  final account = AuthenticatedServer(
    server: discoveredServer,
    userId: 'user-id',
    userName: 'Alex',
    deviceId: 'device-id',
    accessToken: 'secret-token',
  );

  test('loads actors across libraries with person type filtering', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'TotalRecordCount': 12,
                  'Items': [
                    {
                      'Id': 'item-1',
                      'Name': '电影一',
                      'Type': 'Movie',
                      'People': [
                        {
                          'Id': 'person-1',
                          'Name': '演员甲',
                          'Type': 'Actor',
                          'PrimaryImageTag': 'avatar-tag',
                        },
                      ],
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

    final page = await MediaLibraryService(dio).getActors(account);

    expect(request?.uri.path, '/Users/user-id/Items');
    expect(request?.uri.queryParameters['Recursive'], 'true');
    expect(
      request?.uri.queryParameters['IncludeItemTypes'],
      'Movie,Series,Episode,Video',
    );
    expect(request?.uri.queryParameters['Fields'], 'People');
    expect(request?.uri.queryParameters.containsKey('ParentId'), isFalse);
    expect(request?.uri.queryParameters['StartIndex'], '0');
    expect(request?.uri.queryParameters['Limit'], '60');
    expect(request?.uri.queryParameters['EnableTotalRecordCount'], 'true');
    expect(request?.headers['X-Emby-Token'], 'secret-token');
    expect(page.totalRecordCount, 12);
    expect(page.nextStartIndex, 1);
    expect(page.hasMore, isTrue);
    expect(page.items.single.kind, MediaItemKind.person);
    expect(page.items.single.name, '演员甲');
    expect(page.items.single.imageUri?.path, '/Items/person-1/Images/Primary');
    expect(page.items.single.imageUri?.queryParameters['tag'], 'avatar-tag');
    expect(page.items.single.imageHeaders['X-Emby-Token'], 'secret-token');
  });

  test('passes start index and limit through the actors query', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {'TotalRecordCount': 0, 'Items': []},
              ),
            );
          },
        ),
      );

    final page = await MediaLibraryService(
      dio,
    ).getActors(account, startIndex: 60, limit: 40);

    expect(request?.uri.path, '/Users/user-id/Items');
    expect(request?.uri.queryParameters['StartIndex'], '60');
    expect(request?.uri.queryParameters['Limit'], '40');
    expect(page.hasMore, isFalse);
  });

  test('scopes the actors query to a selected library', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {'TotalRecordCount': 0, 'Items': []},
              ),
            );
          },
        ),
      );

    final page = await MediaLibraryService(
      dio,
    ).getActors(account, parentId: 'movies-lib');

    expect(request?.uri.path, '/Users/user-id/Items');
    expect(request?.uri.queryParameters['ParentId'], 'movies-lib');
    expect(request?.uri.queryParameters['Fields'], 'People');
    expect(page.items, isEmpty);
  });

  test('serves cached actors and refreshes them in the background', () async {
    var requestCount = 0;
    final releaseRefresh = Completer<void>();
    final refreshStarted = Completer<void>();
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requestCount++;
            if (requestCount > 1) {
              if (!refreshStarted.isCompleted) refreshStarted.complete();
              await releaseRefresh.future;
            }
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'TotalRecordCount': 1,
                  'Items': [
                    {
                      'Id': 'item-cache',
                      'Name': '电影缓存',
                      'Type': 'Movie',
                      'People': [
                        {
                          'Id': 'person-cache',
                          'Name': requestCount == 1 ? '缓存演员' : '刷新演员',
                          'Type': 'Actor',
                        },
                      ],
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
    final service = MediaLibraryService(dio, MemoryMediaCacheStore());

    expect((await service.getActors(account)).items.single.name, '缓存演员');
    final cached = await service
        .getActors(account)
        .timeout(const Duration(milliseconds: 100));

    expect(cached.items.single.name, '缓存演员');
    await refreshStarted.future.timeout(const Duration(seconds: 1));
    expect(requestCount, 2);
    releaseRefresh.complete();
  });

  test('loads libraries with authentication and artwork metadata', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'TotalRecordCount': 1,
                  'Items': [
                    {
                      'Id': 'movies-id',
                      'Name': '电影',
                      'Type': 'CollectionFolder',
                      'CollectionType': 'movies',
                      'ImageTags': {'Primary': 'image-tag'},
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

    final libraries = await MediaLibraryService(dio).getLibraries(account);

    expect(request?.uri.path, '/Users/user-id/Views');
    expect(request?.headers['X-Emby-Token'], 'secret-token');
    expect(libraries, hasLength(1));
    expect(libraries.single.name, '电影');
    expect(libraries.single.kind, MediaItemKind.folder);
    expect(libraries.single.collectionType, 'movies');
    expect(libraries.single.imageUri?.path, '/Items/movies-id/Images/Primary');
    expect(libraries.single.imageHeaders['X-Emby-Token'], 'secret-token');
  });

  test(
    'returns cached libraries without waiting for background refresh',
    () async {
      var requestCount = 0;
      final releaseRefresh = Completer<void>();
      final refreshStarted = Completer<void>();
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              requestCount++;
              if (requestCount > 1) {
                if (!refreshStarted.isCompleted) refreshStarted.complete();
                await releaseRefresh.future;
              }
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'TotalRecordCount': 1,
                    'Items': [
                      {
                        'Id': 'movies-id',
                        'Name': requestCount == 1 ? '缓存电影' : '刷新电影',
                        'Type': 'CollectionFolder',
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );
      final service = MediaLibraryService(dio, MemoryMediaCacheStore());

      expect((await service.getLibraries(account)).single.name, '缓存电影');
      final cached = await service
          .getLibraries(account)
          .timeout(const Duration(milliseconds: 100));

      expect(cached.single.name, '缓存电影');
      await refreshStarted.future.timeout(const Duration(seconds: 1));
      expect(requestCount, 2);
      releaseRefresh.complete();
    },
  );

  test('loads and maps items from the selected library', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'TotalRecordCount': 245,
                  'Items': [
                    {
                      'Id': 'series-id',
                      'Name': '示例剧集',
                      'Type': 'Series',
                      'ProductionYear': 2026,
                      'RunTimeTicks': 600000000,
                      'ImageTags': {'Primary': 'poster-tag'},
                      'UserData': {
                        'Played': false,
                        'IsFavorite': true,
                        'PlaybackPositionTicks': 300000000,
                      },
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

    final page = await MediaLibraryService(
      dio,
    ).getItems(account, parentId: 'tv-id', startIndex: 60, limit: 60);

    expect(request?.uri.path, '/Users/user-id/Items');
    expect(request?.uri.queryParameters['ParentId'], 'tv-id');
    expect(request?.uri.queryParameters['Recursive'], 'true');
    expect(request?.uri.queryParameters['SortBy'], 'SortName');
    expect(request?.uri.queryParameters['StartIndex'], '60');
    expect(request?.uri.queryParameters['Limit'], '60');
    expect(page.totalRecordCount, 245);
    expect(page.nextStartIndex, 61);
    expect(page.hasMore, isTrue);
    expect(page.items.single.kind, MediaItemKind.series);
    expect(page.items.single.productionYear, 2026);
    expect(page.items.single.runTime, const Duration(minutes: 1));
    expect(page.items.single.resumePosition, const Duration(seconds: 30));
    expect(page.items.single.favorite, isTrue);
    expect(request?.uri.queryParameters['EnableUserData'], 'true');
    expect(request?.uri.queryParameters['CollapseBoxSetItems'], 'false');
    expect(request?.uri.queryParameters['GroupItemsIntoCollections'], 'false');
    expect(request?.uri.queryParameters['ExcludeItemTypes'], 'Folder,BoxSet');
  });

  test('passes sorting and filtering through the paged item query', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {'Items': [], 'TotalRecordCount': 0},
              ),
            );
          },
        ),
      );

    await MediaLibraryService(dio).getItems(
      account,
      parentId: 'movies-id',
      sort: MediaLibrarySort.ratingDescending,
      kind: MediaLibraryKindFilter.movies,
      status: MediaLibraryStatusFilter.favorites,
      productionYear: 2025,
    );

    expect(request?.uri.queryParameters['SortBy'], 'CommunityRating,SortName');
    expect(request?.uri.queryParameters['SortOrder'], 'Descending');
    expect(request?.uri.queryParameters['IncludeItemTypes'], 'Movie,Video');
    expect(request?.uri.queryParameters['Filters'], 'IsFavorite');
    expect(request?.uri.queryParameters['Years'], '2025');
    expect(request?.uri.queryParameters['CollapseBoxSetItems'], 'false');
    expect(request?.uri.queryParameters['GroupItemsIntoCollections'], 'false');
    expect(request?.uri.queryParameters['ExcludeItemTypes'], 'Folder,BoxSet');
  });

  test('passes collapseBoxSets=true to group items into collections', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {'Items': [], 'TotalRecordCount': 0},
              ),
            );
          },
        ),
      );

    await MediaLibraryService(
      dio,
    ).getItems(account, parentId: 'movies-id', collapseBoxSets: true);

    expect(request?.uri.queryParameters['CollapseBoxSetItems'], 'true');
    expect(request?.uri.queryParameters['GroupItemsIntoCollections'], 'true');
    expect(
      request?.uri.queryParameters.containsKey('ExcludeItemTypes'),
      isFalse,
    );
  });

  test('does not exclude BoxSet when collectionType is boxsets', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {'Items': [], 'TotalRecordCount': 0},
              ),
            );
          },
        ),
      );

    await MediaLibraryService(
      dio,
    ).getItems(account, parentId: 'boxsets-id', collectionType: 'boxsets');

    expect(
      request?.uri.queryParameters.containsKey('ExcludeItemTypes'),
      isFalse,
    );
  });

  test('loads global favorites across all media libraries', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'TotalRecordCount': 1,
                  'Items': [
                    {
                      'Id': 'favorite-id',
                      'Name': '收藏影片',
                      'Type': 'Movie',
                      'UserData': {'IsFavorite': true},
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

    final page = await MediaLibraryService(
      dio,
    ).getFavoriteItems(account, startIndex: 60, limit: 30);

    expect(request?.uri.path, '/Users/user-id/Items');
    expect(request?.uri.queryParameters['ParentId'], isNull);
    expect(request?.uri.queryParameters['Recursive'], 'true');
    expect(request?.uri.queryParameters['Filters'], 'IsFavorite');
    expect(
      request?.uri.queryParameters['IncludeItemTypes'],
      'Movie,Series,Episode,Video,Audio',
    );
    expect(request?.uri.queryParameters['EnableUserData'], 'true');
    expect(request?.uri.queryParameters['StartIndex'], '60');
    expect(request?.uri.queryParameters['Limit'], '30');
    expect(page.items.single.favorite, isTrue);
    expect(page.nextStartIndex, 61);
  });

  test(
    'updates favorite and played state through user item endpoints',
    () async {
      final requests = <RequestOptions>[];
      final cache = _TrackingCacheStore();
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add(options);
              handler.resolve(
                Response<void>(requestOptions: options, statusCode: 204),
              );
            },
          ),
        );
      final service = MediaLibraryService(dio, cache);

      await service.setFavorite(account, 'movie-id', favorite: true);
      await service.setFavorite(account, 'movie-id', favorite: false);
      await service.setPlayed(account, 'movie-id', played: true);
      await service.setPlayed(account, 'movie-id', played: false);

      expect(requests.map((request) => request.method), [
        'POST',
        'DELETE',
        'POST',
        'DELETE',
      ]);
      expect(requests.map((request) => request.uri.path), [
        '/Users/user-id/FavoriteItems/movie-id',
        '/Users/user-id/FavoriteItems/movie-id',
        '/Users/user-id/PlayedItems/movie-id',
        '/Users/user-id/PlayedItems/movie-id',
      ]);
      expect(
        requests.every(
          (request) => request.headers['X-Emby-Token'] == 'secret-token',
        ),
        isTrue,
      );
      expect(cache.clearCount, 4);
    },
  );

  test('clears media cache once after a batch user-state update', () async {
    final requests = <RequestOptions>[];
    final cache = _TrackingCacheStore();
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response<void>(requestOptions: options, statusCode: 204),
            );
          },
        ),
      );

    await MediaLibraryService(dio, cache).setFavoriteForItems(account, [
      'movie-1',
      'movie-2',
      'movie-2',
    ], favorite: true);

    expect(requests, hasLength(2));
    expect(cache.clearCount, 1);
  });

  test('loads rich item details including backdrop metadata', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'Id': 'movie-id',
                  'Name': '示例电影',
                  'Type': 'Movie',
                  'Overview': '电影简介',
                  'Genres': ['剧情', '科幻'],
                  'CommunityRating': 8.4,
                  'OfficialRating': 'PG-13',
                  'Taglines': ['示例标语'],
                  'BackdropImageTags': ['backdrop-tag'],
                  'Chapters': [
                    {'Name': '第二幕', 'StartPositionTicks': 36000000000},
                    {'Name': '开场', 'StartPositionTicks': 0},
                  ],
                  'People': [
                    {
                      'Id': 'person-id',
                      'Name': '示例演员',
                      'Type': 'Actor',
                      'Role': '主角',
                      'PrimaryImageTag': 'person-tag',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

    final item = await MediaLibraryService(dio).getItem(account, 'movie-id');

    expect(item.overview, '电影简介');
    expect(item.genres, ['剧情', '科幻']);
    expect(item.communityRating, 8.4);
    expect(item.tagline, '示例标语');
    expect(item.backdropUri?.path, '/Items/movie-id/Images/Backdrop/0');
    expect(item.people.single.name, '示例演员');
    expect(item.people.single.role, '主角');
    expect(item.chapters, hasLength(2));
    expect(item.chapters.first.name, '开场');
    expect(item.chapters.last.startPosition, const Duration(hours: 1));
    expect(
      item.people.single.imageUri?.path,
      '/Items/person-id/Images/Primary',
    );
  });

  test('loads similar items for the current user', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'TotalRecordCount': 1,
                  'Items': [
                    {'Id': 'similar-id', 'Name': '推荐电影', 'Type': 'Movie'},
                  ],
                },
              ),
            );
          },
        ),
      );

    final items = await MediaLibraryService(
      dio,
    ).getSimilar(account, 'movie-id');

    expect(request?.uri.path, '/Items/movie-id/Similar');
    expect(request?.uri.queryParameters['UserId'], 'user-id');
    expect(request?.uri.queryParameters['Limit'], '12');
    expect(items.single.name, '推荐电影');
  });

  test(
    'searches media and people with the compatible hints endpoint',
    () async {
      RequestOptions? request;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              request = options;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {
                    'TotalRecordCount': 2,
                    'SearchHints': [
                      {
                        'Id': 'movie-id',
                        'Name': '示例电影',
                        'Type': 'Movie',
                        'ProductionYear': 2026,
                        'PrimaryImageTag': 'movie-tag',
                      },
                      {
                        'ItemId': 'person-id',
                        'Name': '示例演员',
                        'Type': 'Person',
                        'PrimaryImageTag': 'person-tag',
                        'PrimaryImageItemId': 'person-image-id',
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );

      final page = await MediaLibraryService(dio).search(
        account,
        query: '示例',
        scope: MediaSearchScope.all,
        startIndex: 40,
        limit: 20,
      );

      expect(request?.uri.path, '/Search/Hints');
      expect(request?.uri.queryParameters['SearchTerm'], '示例');
      expect(request?.uri.queryParameters['UserId'], 'user-id');
      expect(request?.uri.queryParameters['StartIndex'], '40');
      expect(request?.uri.queryParameters['Limit'], '20');
      expect(request?.uri.queryParameters['IncludePeople'], 'true');
      expect(
        request?.uri.queryParameters['IncludeItemTypes'],
        contains('Person'),
      );
      expect(page.totalRecordCount, 2);
      expect(page.items.first.kind, MediaItemKind.movie);
      expect(page.items.last.kind, MediaItemKind.person);
      expect(page.items.last.id, 'person-id');
      expect(
        page.items.last.imageUri?.path,
        '/Items/person-image-id/Images/Primary',
      );
    },
  );

  test('loads a person filmography with a recursive item query', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'TotalRecordCount': 1,
                  'Items': [
                    {'Id': 'credit-id', 'Name': '演员作品', 'Type': 'Movie'},
                  ],
                },
              ),
            );
          },
        ),
      );

    final page = await MediaLibraryService(
      dio,
    ).getItemsForPerson(account, personId: 'person-id');

    expect(request?.uri.path, '/Users/user-id/Items');
    expect(request?.uri.queryParameters['PersonIds'], 'person-id');
    expect(request?.uri.queryParameters['Recursive'], 'true');
    expect(request?.uri.queryParameters['IncludeItemTypes'], contains('Movie'));
    expect(page.items.single.name, '演员作品');
  });

  test('loads every playable episode for a series queue', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'TotalRecordCount': 2,
                  'Items': [
                    {
                      'Id': 'episode-2',
                      'Name': '第二集',
                      'Type': 'Episode',
                      'SeriesId': 'series-id',
                      'ParentIndexNumber': 1,
                      'IndexNumber': 2,
                    },
                    {
                      'Id': 'episode-1',
                      'Name': '第一集',
                      'Type': 'Episode',
                      'SeriesId': 'series-id',
                      'ParentIndexNumber': 1,
                      'IndexNumber': 1,
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

    final episodes = await MediaLibraryService(
      dio,
    ).getEpisodesForSeries(account, seriesId: 'series-id');

    expect(request?.uri.path, '/Users/user-id/Items');
    expect(request?.uri.queryParameters['ParentId'], 'series-id');
    expect(request?.uri.queryParameters['Recursive'], 'true');
    expect(request?.uri.queryParameters['IncludeItemTypes'], 'Episode');
    expect(request?.uri.queryParameters['IsMissing'], 'false');
    expect(request?.uri.queryParameters['Limit'], '10000');
    expect(episodes, hasLength(2));
    expect(episodes.first.seriesId, 'series-id');
  });

  test('loads resumable video items for the home feed', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'TotalRecordCount': 1,
                  'Items': [
                    {
                      'Id': 'resume-id',
                      'Name': '继续观看电影',
                      'Type': 'Movie',
                      'RunTimeTicks': 72000000000,
                      'UserData': {
                        'PlaybackPositionTicks': 18000000000,
                        'Played': false,
                      },
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

    final items = await MediaLibraryService(dio).getResumeItems(account);

    expect(request?.uri.path, '/Users/user-id/Items/Resume');
    expect(request?.uri.queryParameters['MediaTypes'], 'Video');
    expect(
      request?.uri.queryParameters['IncludeItemTypes'],
      'Movie,Episode,Video',
    );
    expect(request?.uri.queryParameters['ExcludeActiveSessions'], 'true');
    expect(items.single.resumePosition, const Duration(minutes: 30));
  });

  test('falls back to the compatible resumable item query', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            if (options.uri.path.endsWith('/Items/Resume')) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<void>(
                    requestOptions: options,
                    statusCode: 404,
                  ),
                ),
              );
              return;
            }
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'Items': [
                    {'Id': 'fallback-id', 'Name': '兼容续播', 'Type': 'Episode'},
                  ],
                },
              ),
            );
          },
        ),
      );

    final items = await MediaLibraryService(dio).getResumeItems(account);

    expect(requests, hasLength(2));
    expect(requests.last.uri.path, '/Users/user-id/Items');
    expect(requests.last.uri.queryParameters['Filters'], 'IsResumable');
    expect(requests.last.uri.queryParameters['SortBy'], 'DatePlayed');
    expect(items.single.id, 'fallback-id');
  });

  test('loads latest media from an array response', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: 200,
                data: const [
                  {'Id': 'latest-id', 'Name': '最新电影', 'Type': 'Movie'},
                ],
              ),
            );
          },
        ),
      );

    final items = await MediaLibraryService(
      dio,
    ).getLatestMovies(account, parentId: 'movies-id');

    expect(request?.uri.path, '/Users/user-id/Items/Latest');
    expect(request?.uri.queryParameters['IncludeItemTypes'], 'Movie');
    expect(request?.uri.queryParameters['GroupItems'], 'false');
    expect(request?.uri.queryParameters['ParentId'], 'movies-id');
    expect(items.single.id, 'latest-id');
  });

  test('loads daily recommendations from the suggestions endpoint', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'Items': [
                    {
                      'Id': 'recommendation-id',
                      'Name': '每日推荐',
                      'Type': 'Movie',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

    final items = await MediaLibraryService(dio).getRecommendations(account);

    expect(request?.uri.path, '/Items/Suggestions');
    expect(request?.uri.queryParameters['UserId'], 'user-id');
    expect(request?.uri.queryParameters['MediaType'], 'Video');
    expect(request?.uri.queryParameters['Type'], 'Movie,Episode,Video');
    expect(items.single.id, 'recommendation-id');
  });

  test('refreshes recommendations once per local calendar day', () async {
    var now = DateTime(2026, 7, 18, 9);
    var requestCount = 0;
    final cache = MemoryMediaCacheStore(clock: () => now);
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestCount += 1;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'Items': [
                    {
                      'Id': 'recommendation-$requestCount',
                      'Name': '第 $requestCount 天推荐',
                      'Type': 'Movie',
                    },
                  ],
                },
              ),
            );
          },
        ),
      );
    final service = MediaLibraryService(dio, cache, () => now);

    expect(
      (await service.getRecommendations(account)).single.id,
      'recommendation-1',
    );
    now = DateTime(2026, 7, 18, 23, 59);
    expect(
      (await service.getRecommendations(account)).single.id,
      'recommendation-1',
    );
    expect(requestCount, 1);

    expect(
      (await service.getRecommendations(account, forceRefresh: true)).single.id,
      'recommendation-2',
    );
    expect(requestCount, 2);

    now = DateTime(2026, 7, 20, 0, 0);
    expect(
      (await service.getRecommendations(account)).single.id,
      'recommendation-3',
    );
    expect(requestCount, 3);
  });

  test('falls back to random library items for recommendations', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            if (options.uri.path == '/Items/Suggestions') {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<void>(
                    requestOptions: options,
                    statusCode: 404,
                  ),
                ),
              );
              return;
            }
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'Items': [
                    {'Id': 'random-id', 'Name': '随机推荐', 'Type': 'Episode'},
                  ],
                },
              ),
            );
          },
        ),
      );

    final items = await MediaLibraryService(dio).getRecommendations(account);

    expect(requests, hasLength(2));
    expect(requests.last.uri.path, '/Users/user-id/Items');
    expect(requests.last.uri.queryParameters['SortBy'], 'Random');
    expect(
      requests.last.uri.queryParameters['IncludeItemTypes'],
      'Movie,Episode,Video',
    );
    expect(items.single.id, 'random-id');
  });

  test(
    'searchRemoteSubtitles sends correct Jellyfin API request and parses results',
    () async {
      RequestOptions? request;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              request = options;
              handler.resolve(
                Response<List<dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    {
                      'Id': 'sub-123',
                      'Name': '正片中英双语字幕',
                      'ProviderName': 'OpenSubtitles',
                      'Format': 'srt',
                      'Comment': '4K 蓝光',
                    },
                  ],
                ),
              );
            },
          ),
        );

      final subs = await MediaLibraryService(
        dio,
      ).searchRemoteSubtitles(account, itemId: 'item-100', language: 'chi');

      expect(request?.uri.path, '/Items/item-100/RemoteSearch/Subtitles/chi');
      expect(subs, hasLength(1));
      expect(subs.first.id, 'sub-123');
      expect(subs.first.name, '正片中英双语字幕');
      expect(subs.first.providerName, 'OpenSubtitles');
    },
  );

  test(
    'downloadRemoteSubtitle sends POST request to Jellyfin server',
    () async {
      RequestOptions? request;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              request = options;
              handler.resolve(
                Response<void>(requestOptions: options, statusCode: 200),
              );
            },
          ),
        );

      final success = await MediaLibraryService(dio).downloadRemoteSubtitle(
        account,
        itemId: 'item-100',
        subtitleId: 'sub-123',
      );

      expect(request?.method, 'POST');
      expect(
        request?.uri.path,
        '/Items/item-100/RemoteSearch/Subtitles/sub-123',
      );
      expect(success, isTrue);
    },
  );

  test(
    'searchRemoteMetadata sends POST request to Items/RemoteSearch/{Type} and parses results',
    () async {
      RequestOptions? request;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              request = options;
              handler.resolve(
                Response<List<dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    {
                      'Name': '奥本海默',
                      'OriginalTitle': 'Oppenheimer',
                      'ProductionYear': 2023,
                      'ImageUrl':
                          'https://image.tmdb.org/t/p/w500/oppenheimer.jpg',
                      'Overview': '物理学家奥本海默领导曼哈顿计划的故事。',
                      'ProviderIds': {'Tmdb': '872585', 'Imdb': 'tt15398776'},
                    },
                  ],
                ),
              );
            },
          ),
        );

      final results = await MediaLibraryService(dio).searchRemoteMetadata(
        account,
        itemId: 'movie-100',
        kind: MediaItemKind.movie,
        name: '奥本海默',
        year: 2023,
        providerIds: const {'Tmdb': '872585'},
      );

      expect(request?.method, 'POST');
      expect(request?.uri.path, '/Items/RemoteSearch/Movie');
      expect(request?.headers['X-Emby-Token'], 'secret-token');
      final body = request?.data as Map<String, dynamic>?;
      expect(body?['ItemId'], 'movie-100');
      final searchInfo = body?['SearchInfo'] as Map<String, dynamic>?;
      expect(searchInfo?['Name'], '奥本海默');
      expect(searchInfo?['Year'], 2023);
      expect(searchInfo?['ProviderIds'], {'Tmdb': '872585'});

      expect(results, hasLength(1));
      final first = results.first;
      expect(first.name, '奥本海默');
      expect(first.originalTitle, 'Oppenheimer');
      expect(first.productionYear, 2023);
      expect(first.imageUrl, 'https://image.tmdb.org/t/p/w500/oppenheimer.jpg');
      expect(first.overview, '物理学家奥本海默领导曼哈顿计划的故事。');
      expect(first.providerIds['Tmdb'], '872585');
      expect(first.providerIds['Imdb'], 'tt15398776');
    },
  );

  test(
    'searchRemoteMetadata handles response wrapped in Items map for Series',
    () async {
      RequestOptions? request;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              request = options;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {
                    'Items': [
                      {
                        'Name': '黑镜',
                        'ProductionYear': 2011,
                        'ProviderIds': {'Tmdb': '42009'},
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );

      final results = await MediaLibraryService(dio).searchRemoteMetadata(
        account,
        itemId: 'series-200',
        kind: MediaItemKind.series,
        name: '黑镜',
      );

      expect(request?.method, 'POST');
      expect(request?.uri.path, '/Items/RemoteSearch/Series');
      expect(results, hasLength(1));
      expect(results.first.name, '黑镜');
      expect(results.first.productionYear, 2011);
    },
  );

  test(
    'applyRemoteMetadata sends POST to Items/RemoteSearch/Apply/:itemId and invalidates cache',
    () async {
      RequestOptions? request;
      final trackingCache = _TrackingCacheStore();
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              request = options;
              handler.resolve(
                Response<void>(requestOptions: options, statusCode: 204),
              );
            },
          ),
        );

      final candidate = RemoteSearchResult.fromJson(const {
        'Name': '奥本海默',
        'ProductionYear': 2023,
        'ProviderIds': {'Tmdb': '872585'},
      });

      await MediaLibraryService(dio, trackingCache).applyRemoteMetadata(
        account,
        itemId: 'item-100',
        result: candidate,
        replaceAllImages: true,
      );

      expect(request?.method, 'POST');
      expect(request?.uri.path, '/Items/RemoteSearch/Apply/item-100');
      expect(request?.uri.queryParameters['ReplaceAllImages'], 'true');
      expect(request?.headers['X-Emby-Token'], 'secret-token');
      expect(request?.data, candidate.rawPayload);
      expect(trackingCache.clearCount, 1);
    },
  );

  test(
    'getExternalIdInfos fetches external providers including plugins like Douban and Bangumi',
    () async {
      RequestOptions? request;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              request = options;
              handler.resolve(
                Response<List<dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: [
                    {'Name': 'TheMovieDb', 'Key': 'Tmdb', 'Type': 'Movie'},
                    {'Name': 'IMDb', 'Key': 'Imdb', 'Type': 'Movie'},
                    {'Name': '豆瓣', 'Key': 'Douban', 'Type': 'Movie'},
                    {'Name': 'Bangumi', 'Key': 'Bangumi', 'Type': 'Series'},
                  ],
                ),
              );
            },
          ),
        );

      final providers = await MediaLibraryService(
        dio,
      ).getExternalIdInfos(account, itemId: 'item-movie-1');

      expect(request?.method, 'GET');
      expect(request?.uri.path, '/Items/item-movie-1/ExternalIdInfos');
      expect(request?.headers['X-Emby-Token'], 'secret-token');
      expect(providers, hasLength(4));
      expect(providers.map((p) => p.name).toList(), [
        'TheMovieDb',
        'IMDb',
        '豆瓣',
        'Bangumi',
      ]);
      expect(providers.map((p) => p.key).toList(), [
        'Tmdb',
        'Imdb',
        'Douban',
        'Bangumi',
      ]);
    },
  );

  test(
    'getCollectionsForItem returns collections from primary /Items/{id}/Collections',
    () async {
      RequestOptions? request;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              request = options;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {
                    'TotalRecordCount': 1,
                    'Items': [
                      {
                        'Id': 'boxset-matrix',
                        'Name': '黑客帝国（系列）',
                        'Type': 'BoxSet',
                        'Overview': 'Matrix trilogy collection',
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );

      final collections = await MediaLibraryService(
        dio,
      ).getCollectionsForItem(account, 'movie-matrix-1');

      expect(request?.uri.path, '/Items/movie-matrix-1/Collections');
      expect(request?.uri.queryParameters['UserId'], 'user-id');
      expect(collections, hasLength(1));
      expect(collections.first.id, 'boxset-matrix');
      expect(collections.first.name, '黑客帝国（系列）');
      expect(collections.first.kind, MediaItemKind.folder);
    },
  );

  test(
    'getCollectionsForItem falls back to /Items/{id}/Ancestors when /Collections is unavailable',
    () async {
      final requestedPaths = <String>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestedPaths.add(options.uri.path);
              if (options.uri.path.contains('/Collections')) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 404,
                    ),
                    type: DioExceptionType.badResponse,
                  ),
                );
              } else {
                handler.resolve(
                  Response<List<dynamic>>(
                    requestOptions: options,
                    statusCode: 200,
                    data: const [
                      {'Id': 'boxset-lotr', 'Name': '指环王三部曲', 'Type': 'BoxSet'},
                      {'Id': 'folder-movies', 'Name': '电影库', 'Type': 'Folder'},
                    ],
                  ),
                );
              }
            },
          ),
        );

      final collections = await MediaLibraryService(
        dio,
      ).getCollectionsForItem(account, 'movie-lotr-1');

      expect(requestedPaths, contains('/Items/movie-lotr-1/Collections'));
      expect(requestedPaths, contains('/Items/movie-lotr-1/Ancestors'));
      expect(collections, hasLength(1));
      expect(collections.first.id, 'boxset-lotr');
      expect(collections.first.name, '指环王三部曲');
    },
  );

  test('getCollectionItems fetches items inside the collection', () async {
    RequestOptions? request;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            request = options;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'TotalRecordCount': 2,
                  'Items': [
                    {'Id': 'movie-1', 'Name': '黑客帝国 1', 'Type': 'Movie'},
                    {'Id': 'movie-2', 'Name': '黑客帝国 2', 'Type': 'Movie'},
                  ],
                },
              ),
            );
          },
        ),
      );

    final items = await MediaLibraryService(
      dio,
    ).getCollectionItems(account, 'boxset-matrix');

    expect(request?.uri.path, '/Users/user-id/Items');
    expect(request?.uri.queryParameters['ParentId'], 'boxset-matrix');
    expect(items, hasLength(2));
    expect(items[0].name, '黑客帝国 1');
    expect(items[1].name, '黑客帝国 2');
  });
}

class _TrackingCacheStore implements MediaCacheStore {
  int clearCount = 0;

  @override
  Future<void> clear({bool preserveRecommendations = false}) async {
    clearCount += 1;
  }

  @override
  Future<MediaCacheEntry?> read(String key, {Duration? maxAge}) async => null;

  @override
  Future<void> write(String key, Map<String, dynamic> payload) async {}
}
