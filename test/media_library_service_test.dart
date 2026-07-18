import 'dart:async';

import 'package:dio/dio.dart';
import 'package:embyplayer/src/core/storage/media_cache_store.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
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
}
