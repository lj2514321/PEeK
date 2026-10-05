import 'dart:async';

import 'package:dio/dio.dart';
import 'package:embyplayer/src/features/home/data/home_feed_service.dart';
import 'package:embyplayer/src/features/servers/data/media_library_service.dart';
import 'package:embyplayer/src/features/servers/domain/media_item.dart';
import 'package:embyplayer/src/features/servers/domain/server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final account = _account();

  test('combines the three home feed sections', () async {
    final service = HomeFeedService(
      _FakeLibraryService(
        recommendations: const [
          MediaItem(
            id: 'resume-id',
            name: '重复的续播项目',
            kind: MediaItemKind.movie,
          ),
          MediaItem(
            id: 'recommendation-id',
            name: '每日推荐',
            kind: MediaItemKind.movie,
          ),
        ],
        resumeItems: const [
          MediaItem(id: 'resume-id', name: '继续观看', kind: MediaItemKind.movie),
        ],
        latestMovies: const [
          MediaItem(id: 'movie-id', name: '最新电影', kind: MediaItemKind.movie),
        ],
        latestEpisodes: const [
          MediaItem(
            id: 'episode-id',
            name: '最新剧集',
            kind: MediaItemKind.episode,
          ),
        ],
      ),
    );

    final feed = await service.load(account);

    expect(feed.heroItem?.id, 'recommendation-id');
    expect(feed.dailyRecommendations.items.single.id, 'recommendation-id');
    expect(feed.latestMovies.groups.single.section.items.single.id, 'movie-id');
    expect(feed.latestEpisodes.items.single.id, 'episode-id');
    expect(feed.hasAnyError, isFalse);
  });

  test('keeps successful sections when one request fails', () async {
    final service = HomeFeedService(
      _FakeLibraryService(
        resumeItems: const [
          MediaItem(id: 'resume-id', name: '继续观看', kind: MediaItemKind.movie),
        ],
        latestMoviesError: const MediaLibraryException('电影分区失败'),
      ),
    );

    final feed = await service.load(account);

    expect(feed.heroItem?.id, 'resume-id');
    expect(feed.latestMovies.groups.single.section.items, isEmpty);
    expect(feed.latestMovies.groups.single.section.error, '电影分区失败');
    expect(feed.hasAnyError, isTrue);
  });

  test(
    'groups latest movies by movie library and skips TV libraries',
    () async {
      final library = _FakeLibraryService(
        libraries: const [
          MediaItem(
            id: 'movies-main',
            name: '电影',
            kind: MediaItemKind.folder,
            collectionType: 'movies',
          ),
          MediaItem(
            id: 'movies-docs',
            name: '纪录片',
            kind: MediaItemKind.folder,
            collectionType: 'mixed',
          ),
          MediaItem(
            id: 'shows',
            name: '剧集',
            kind: MediaItemKind.folder,
            collectionType: 'tvshows',
          ),
        ],
        latestMoviesByLibrary: const {
          'movies-main': [
            MediaItem(
              id: 'movie-main',
              name: '主电影库新片',
              kind: MediaItemKind.movie,
            ),
          ],
          'movies-docs': [
            MediaItem(
              id: 'movie-doc',
              name: '纪录片新片',
              kind: MediaItemKind.movie,
            ),
          ],
        },
      );

      final feed = await HomeFeedService(library).load(account);

      expect(feed.latestMovies.groups.map((group) => group.library.name), [
        '电影',
        '纪录片',
      ]);
      expect(library.latestMovieParentIds, ['movies-main', 'movies-docs']);
      expect(
        feed.latestMovies.groups.last.section.items.single.id,
        'movie-doc',
      );
    },
  );

  test('limits latest movie library requests to four at a time', () async {
    final release = Completer<void>();
    final library = _FakeLibraryService(
      libraries: List.generate(
        6,
        (index) => MediaItem(
          id: 'movies-$index',
          name: '电影库 $index',
          kind: MediaItemKind.folder,
          collectionType: 'movies',
        ),
      ),
      latestMoviesRelease: release.future,
    );

    final load = HomeFeedService(library).load(account);
    for (var turn = 0; turn < 5; turn++) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(library.activeLatestMovieRequests, 4);
    expect(library.maximumLatestMovieConcurrency, 4);

    release.complete();
    await load;

    expect(library.latestMovieRequests, 6);
    expect(library.maximumLatestMovieConcurrency, 4);
  });

  test('propagates an expired session instead of showing partial data', () {
    final service = HomeFeedService(
      _FakeLibraryService(
        resumeItemsError: const MediaLibraryException(
          '登录已失效',
          authenticationExpired: true,
          statusCode: 401,
        ),
      ),
    );

    expect(
      () => service.load(account),
      throwsA(
        isA<MediaLibraryException>().having(
          (error) => error.authenticationExpired,
          'authenticationExpired',
          isTrue,
        ),
      ),
    );
  });

  test(
    'refreshes continue watching without reloading recommendations',
    () async {
      final library = _FakeLibraryService(
        recommendations: const [
          MediaItem(
            id: 'recommendation-id',
            name: '每日推荐',
            kind: MediaItemKind.movie,
          ),
        ],
        resumeItems: const [
          MediaItem(id: 'resume-id', name: '继续观看', kind: MediaItemKind.movie),
        ],
        latestMovies: const [
          MediaItem(id: 'movie-id', name: '最新电影', kind: MediaItemKind.movie),
        ],
      );
      final service = HomeFeedService(library);
      final currentFeed = await service.load(account);

      library.resetRequestCounts();
      final refreshed = await service.refreshContinueWatching(
        account,
        currentFeed,
      );

      expect(library.recommendationRequests, 0);
      expect(library.resumeRequests, 1);
      expect(library.latestMovieRequests, 0);
      expect(library.latestEpisodeRequests, 0);
      expect(library.lastResumeForceRefresh, isTrue);
      expect(
        refreshed.dailyRecommendations,
        same(currentFeed.dailyRecommendations),
      );
      expect(refreshed.latestMovies, same(currentFeed.latestMovies));
      expect(refreshed.latestEpisodes, same(currentFeed.latestEpisodes));
    },
  );

  test('refreshes only daily recommendations', () async {
    final library = _FakeLibraryService(
      recommendations: const [
        MediaItem(
          id: 'recommendation-1',
          name: '第一天推荐',
          kind: MediaItemKind.movie,
        ),
      ],
      resumeItems: const [
        MediaItem(id: 'resume-id', name: '继续观看', kind: MediaItemKind.movie),
      ],
      latestMovies: const [
        MediaItem(id: 'movie-id', name: '最新电影', kind: MediaItemKind.movie),
      ],
    );
    final service = HomeFeedService(library);
    final currentFeed = await service.load(account);
    library.recommendations = const [
      MediaItem(
        id: 'recommendation-2',
        name: '第二天推荐',
        kind: MediaItemKind.movie,
      ),
    ];

    library.resetRequestCounts();
    final refreshed = await service.refreshRecommendations(
      account,
      currentFeed,
    );

    expect(library.recommendationRequests, 1);
    expect(library.resumeRequests, 0);
    expect(library.latestMovieRequests, 0);
    expect(library.latestEpisodeRequests, 0);
    expect(refreshed.dailyRecommendations.items.single.id, 'recommendation-2');
    expect(refreshed.continueWatching, same(currentFeed.continueWatching));
    expect(refreshed.latestMovies, same(currentFeed.latestMovies));
    expect(refreshed.latestEpisodes, same(currentFeed.latestEpisodes));
  });
}

class _FakeLibraryService extends MediaLibraryService {
  _FakeLibraryService({
    this.libraries = const [
      MediaItem(
        id: 'movies',
        name: '电影',
        kind: MediaItemKind.folder,
        collectionType: 'movies',
      ),
    ],
    this.recommendations = const [],
    this.resumeItems = const [],
    this.latestMovies = const [],
    this.latestMoviesByLibrary = const {},
    this.latestMoviesRelease,
    this.latestEpisodes = const [],
    this.resumeItemsError,
    this.latestMoviesError,
  }) : super(Dio());

  final List<MediaItem> libraries;
  List<MediaItem> recommendations;
  final List<MediaItem> resumeItems;
  final List<MediaItem> latestMovies;
  final Map<String, List<MediaItem>> latestMoviesByLibrary;
  final Future<void>? latestMoviesRelease;
  final List<MediaItem> latestEpisodes;
  final MediaLibraryException? resumeItemsError;
  final MediaLibraryException? latestMoviesError;
  int recommendationRequests = 0;
  int resumeRequests = 0;
  int latestMovieRequests = 0;
  int latestEpisodeRequests = 0;
  final latestMovieParentIds = <String?>[];
  int activeLatestMovieRequests = 0;
  int maximumLatestMovieConcurrency = 0;
  bool? lastResumeForceRefresh;

  void resetRequestCounts() {
    recommendationRequests = 0;
    resumeRequests = 0;
    latestMovieRequests = 0;
    latestEpisodeRequests = 0;
    latestMovieParentIds.clear();
    lastResumeForceRefresh = null;
  }

  @override
  Future<List<MediaItem>> getLibraries(
    AuthenticatedServer account, {
    bool forceRefresh = false,
  }) async {
    return libraries;
  }

  @override
  Future<List<MediaItem>> getRecommendations(
    AuthenticatedServer account, {
    int limit = 6,
    bool forceRefresh = false,
  }) async {
    recommendationRequests += 1;
    return recommendations;
  }

  @override
  Future<List<MediaItem>> getResumeItems(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
    bool excludeActiveSessions = true,
  }) async {
    resumeRequests += 1;
    lastResumeForceRefresh = forceRefresh;
    if (resumeItemsError != null) throw resumeItemsError!;
    return resumeItems;
  }

  @override
  Future<List<MediaItem>> getLatestMovies(
    AuthenticatedServer account, {
    int limit = 18,
    String? parentId,
    bool forceRefresh = false,
  }) async {
    latestMovieRequests += 1;
    latestMovieParentIds.add(parentId);
    activeLatestMovieRequests += 1;
    if (activeLatestMovieRequests > maximumLatestMovieConcurrency) {
      maximumLatestMovieConcurrency = activeLatestMovieRequests;
    }
    try {
      if (latestMoviesRelease != null) await latestMoviesRelease;
      if (latestMoviesError != null) throw latestMoviesError!;
      return latestMoviesByLibrary[parentId] ?? latestMovies;
    } finally {
      activeLatestMovieRequests -= 1;
    }
  }

  @override
  Future<List<MediaItem>> getLatestEpisodes(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
  }) async {
    latestEpisodeRequests += 1;
    return latestEpisodes;
  }
}

AuthenticatedServer _account() {
  return AuthenticatedServer(
    server: DiscoveredServer(
      kind: ServerKind.jellyfin,
      name: 'Living Room',
      version: '10.11.6',
      serverId: 'server-id',
      apiBaseUri: Uri.parse('http://192.168.1.20:8096'),
    ),
    userId: 'user-id',
    userName: 'Alex',
    deviceId: 'device-id',
    accessToken: 'secret-token',
  );
}
