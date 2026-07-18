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
    expect(feed.latestMovies.items.single.id, 'movie-id');
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
    expect(feed.latestMovies.items, isEmpty);
    expect(feed.latestMovies.error, '电影分区失败');
    expect(feed.hasAnyError, isTrue);
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
}

class _FakeLibraryService extends MediaLibraryService {
  _FakeLibraryService({
    this.recommendations = const [],
    this.resumeItems = const [],
    this.latestMovies = const [],
    this.latestEpisodes = const [],
    this.resumeItemsError,
    this.latestMoviesError,
  }) : super(Dio());

  final List<MediaItem> recommendations;
  final List<MediaItem> resumeItems;
  final List<MediaItem> latestMovies;
  final List<MediaItem> latestEpisodes;
  final MediaLibraryException? resumeItemsError;
  final MediaLibraryException? latestMoviesError;

  @override
  Future<List<MediaItem>> getRecommendations(
    AuthenticatedServer account, {
    int limit = 6,
    bool forceRefresh = false,
  }) async {
    return recommendations;
  }

  @override
  Future<List<MediaItem>> getResumeItems(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
  }) async {
    if (resumeItemsError != null) throw resumeItemsError!;
    return resumeItems;
  }

  @override
  Future<List<MediaItem>> getLatestMovies(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
  }) async {
    if (latestMoviesError != null) throw latestMoviesError!;
    return latestMovies;
  }

  @override
  Future<List<MediaItem>> getLatestEpisodes(
    AuthenticatedServer account, {
    int limit = 18,
    bool forceRefresh = false,
  }) async {
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
